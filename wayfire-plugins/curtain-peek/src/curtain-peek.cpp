#include <wayfire/plugin.hpp>
#include <wayfire/output.hpp>
#include <wayfire/core.hpp>
#include <wayfire/view.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/render.hpp>
#include <wayfire/opengl.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/config/types.hpp>
#include <wayfire/util/duration.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/scene.hpp>
#include <wayfire/scene-render.hpp>
#include <wayfire/scene-operations.hpp>
#include <wayfire/region.hpp>
#include "ipc_wrapper.hpp"
#include "log.hpp"
#include "peek_helpers.hpp"

#include <memory>
#include <vector>
#include <algorithm>
#include <cmath>

#define curtain_log(...) lumen::file_log("/tmp/wayfire-curtain-peek.log", __VA_ARGS__)

// Static solid fill behind the desktop grid, showing through its transparent areas.
class curtain_backdrop_node_t : public wf::scene::node_t
{
  public:
    wf::geometry_t geo;
    wf::color_t    color;

    curtain_backdrop_node_t(wf::geometry_t g, wf::color_t c) :
        wf::scene::node_t(false), geo(g), color(c)
    {}

    std::string stringify() const override
    {
        return "curtain-peek-backdrop";
    }

    wf::geometry_t get_bounding_box() override
    {
        return geo;
    }

    void gen_render_instances(std::vector<wf::scene::render_instance_uptr>& instances,
        wf::scene::damage_callback push_damage, wf::output_t *shown_on) override;
};

class curtain_backdrop_render_instance_t :
    public wf::scene::simple_render_instance_t<curtain_backdrop_node_t>
{
  public:
    using simple_render_instance_t::simple_render_instance_t;

    void render(const wf::scene::render_instruction_t& data) override
    {
        data.pass->add_rect(self->color, data.target, self->geo, data.damage);
    }
};

inline void curtain_backdrop_node_t::gen_render_instances(
    std::vector<wf::scene::render_instance_uptr>& instances,
    wf::scene::damage_callback push_damage, wf::output_t *shown_on)
{
    instances.push_back(std::make_unique<curtain_backdrop_render_instance_t>(
        this, push_damage, shown_on));
}

// OVERLAY node: the frozen snapshot split at a seam, each half one warped mesh
// (one draw call) gathered aside like a pleated curtain.

// Warps a (u, v) grid of the half onto the gathered, pleated, arced band.
// All displacement is analytic so the grid can stay coarse.
static const char *curtain_vert_source =
    R"(
#version 100
attribute highp vec2 grid;          // (u, v), each in [0, 1]

uniform mat4 matrix;                // logical output coords -> clip space
uniform highp float u_p;            // raw progress 0 (closed) .. 1 (open)
uniform highp float u_foldP;        // eased fold amount, 0 .. 1
uniform highp float u_foldDepth;    // pleat compression amplitude, 0 .. <1
uniform highp float u_folds;        // pleat count across the half
uniform highp float u_W;            // full output width (logical px)
uniform highp float u_gy;           // output top edge (logical px)
uniform highp float u_H;            // output height (logical px)
uniform highp float u_src_x0;       // half's source left edge (logical px)
uniform highp float u_src_w;        // half's source width (logical px)
uniform highp float u_gathered;     // residual stack width when fully open
uniform highp float u_flare;        // extra width the base bows out by
uniform highp float u_origin;       // logical x the band is pinned to
uniform highp float u_cum_base;     // 0 for the left half, 1 for the right

varying highp vec2  v_uv;
varying highp float v_u;

void main()
{
    const highp float TWO_PI = 6.2831853;
    highp float u = grid.x;
    highp float v = grid.y;

    // Cumulative pleat position: the integral of the per-column width weight
    // 1 + a*cos(2*pi*f*u), normalised to [0, 1]. Monotonic since a < 1, so the
    // cloth never folds back on itself.
    highp float a     = u_foldDepth * u_foldP;
    highp float farg  = TWO_PI * u_folds;
    highp float total = 1.0 + a * sin(farg) / farg;
    highp float cum   = (u + a * sin(farg * u) / farg) / total;

    // Band width: full at rest, shrinking to the gathered stack as it opens,
    // and bowing out quadratically toward the floor for the curtain's arc.
    highp float gw     = u_gathered + u_flare * v * v * u_foldP;
    highp float band_w = u_src_w * (1.0 - u_p) + gw * u_p;

    highp float x = u_origin + (cum - u_cum_base) * band_w;
    highp float y = u_gy + v * u_H;

    v_uv = vec2((u_src_x0 + u * u_src_w) / u_W, 1.0 - v);
    v_u  = u;
    gl_Position = matrix * vec4(x, y, 0.0, 1.0);
}
)";

// Fake fold lighting; the phase offset keeps ridge/trough off the crease so it
// reads as a side light, not flat ambient occlusion.
static const char *curtain_frag_source =
    R"(
#version 100
@builtin_ext@
@builtin@
precision highp float;

uniform float u_folds;
uniform float u_foldP;
uniform float u_shade;

varying highp vec2  v_uv;
varying highp float v_u;

void main()
{
    const float TWO_PI = 6.2831853;
    const float LIGHT_PHASE = 1.2;

    vec4 c = get_pixel(v_uv);

    float lit  = cos(TWO_PI * u_folds * v_u + LIGHT_PHASE);
    float dark = u_shade * u_foldP * max(0.0, -lit);
    float high = 0.25 * u_shade * u_foldP * max(0.0, lit);

    vec3 rgb = c.rgb * (1.0 - dark);    // darken the troughs
    rgb = rgb * (1.0 - high) + vec3(high); // lift the lit ridges
    gl_FragColor = vec4(rgb, c.a);
}
)";

// Static (u, v) triangle list shared by both halves; motion lives in uniforms.
inline std::vector<float> curtain_build_grid(int nu, int nv)
{
    std::vector<float> g;
    g.reserve((size_t) nu * nv * 6 * 2);
    auto push = [&] (float u, float v) { g.push_back(u); g.push_back(v); };
    for (int j = 0; j < nv; j++)
    {
        const float v0 = (float) j / nv, v1 = (float) (j + 1) / nv;
        for (int i = 0; i < nu; i++)
        {
            const float u0 = (float) i / nu, u1 = (float) (i + 1) / nu;
            push(u0, v0); push(u1, v0); push(u1, v1);
            push(u0, v0); push(u1, v1); push(u0, v1);
        }
    }
    return g;
}

// Owned by the per-output plugin instance, which outlives every node it creates,
// so the shader compiles once per output instead of on every open.
struct curtain_gl_t
{
    OpenGL::program_t program;
    GLuint grid_vbo = 0;    // the static (u, v) grid, uploaded once
    bool ready = false;
};

class curtain_screenshot_node_t : public wf::scene::node_t
{
  public:
    wf::geometry_t geo;            // full output, output-relative {0,0,W,H}
    wlr_texture   *tex = nullptr;  // the captured snapshot (owned by the plugin)
    int   seam_x    = 0;           // seam position, output-relative
    int   edge_px   = 0;           // residual gathered stack width per half (px)
    float progress  = 0.0f;        // 0 = closed (flat), 1 = fully gathered open

    int   fold_count  = 5;         // pleats across each half
    float fold_depth  = 0.4f;      // strip-width modulation amplitude (0..1)
    float shade_depth = 0.5f;      // peak fold shadow opacity (0..1)

    curtain_gl_t& gl;

    curtain_screenshot_node_t(wf::geometry_t g, wlr_texture *t, curtain_gl_t& gl) :
        wf::scene::node_t(false), geo(g), tex(t), gl(gl)
    {}

    std::string stringify() const override
    {
        return "curtain-peek-screenshot";
    }

    wf::geometry_t get_bounding_box() override
    {
        return geo;
    }

    void gen_render_instances(std::vector<wf::scene::render_instance_uptr>& instances,
        wf::scene::damage_callback push_damage, wf::output_t *shown_on) override;
};

class curtain_screenshot_render_instance_t :
    public wf::scene::simple_render_instance_t<curtain_screenshot_node_t>
{
  public:
    using simple_render_instance_t::simple_render_instance_t;

    // NU resolves the pleats, NV the inner-edge arc.
    static constexpr int NU = 64;
    static constexpr int NV = 24;

    void render(const wf::scene::render_instruction_t& data) override
    {
        // tex and a non-empty geo are guaranteed: the node is only built after
        // lumen::capture_output() succeeded. Option ranges come from the XML.
        const auto g = self->geo;           // logical, full output
        const int  W = g.width;

        const float p     = std::clamp(self->progress, 0.0f, 1.0f);
        const int   seam  = self->seam_x - g.x; // 0..W
        const int   folds = self->fold_count;
        const float foldDepth  = self->fold_depth;
        const float shadeDepth = self->shade_depth;

        // Eased so a closed curtain is perfectly flat.
        const float foldP = std::sin(p * 1.5707963f);

        auto& program = self->gl.program;

        data.pass->custom_gles_subpass([&]
        {
            // Lazy: the subpass is the only point with a guaranteed GL context.
            if (!self->gl.ready)
            {
                program.compile(curtain_vert_source, curtain_frag_source);
                const auto grid = curtain_build_grid(NU, NV);
                GL_CALL(glGenBuffers(1, &self->gl.grid_vbo));
                GL_CALL(glBindBuffer(GL_ARRAY_BUFFER, self->gl.grid_vbo));
                GL_CALL(glBufferData(GL_ARRAY_BUFFER, grid.size() * sizeof(float),
                    grid.data(), GL_STATIC_DRAW));
                GL_CALL(glBindBuffer(GL_ARRAY_BUFFER, 0));
                self->gl.ready = true;
            }

            const auto matrix =
                wf::gles::render_target_orthographic_projection(data.target);
            const int n_verts = NU * NV * 6;

            wf::gles_texture_t gtex{self->tex};
            program.use(wf::TEXTURE_TYPE_RGBA);
            program.set_active_texture(gtex);
            // With a VBO bound the pointer is a buffer offset. The attrib keeps
            // the buffer, so unbind at once: Wayfire's own draws use client arrays.
            GL_CALL(glBindBuffer(GL_ARRAY_BUFFER, self->gl.grid_vbo));
            program.attrib_pointer("grid", 2, 0, nullptr);
            GL_CALL(glBindBuffer(GL_ARRAY_BUFFER, 0));
            program.uniformMatrix4f("matrix", matrix);

            program.uniform1f("u_p", p);
            program.uniform1f("u_foldP", foldP);
            program.uniform1f("u_foldDepth", foldDepth);
            program.uniform1f("u_folds", (float) folds);
            program.uniform1f("u_shade", shadeDepth);
            program.uniform1f("u_W", (float) W);
            program.uniform1f("u_gy", (float) g.y);
            program.uniform1f("u_H", (float) g.height);

            // Each half is pinned to its outer wall; src_x0/src_w are output-relative.
            auto draw_half = [&] (int src_x0, int src_w, bool is_left)
            {
                if (src_w <= 0)
                {
                    return;
                }

                const float gathered = (float) self->edge_px; // <= either half, see start_open
                const float flare = std::min((float) src_w * 0.22f,
                    (float) src_w - gathered);

                program.uniform1f("u_src_x0", (float) src_x0);
                program.uniform1f("u_src_w", (float) src_w);
                program.uniform1f("u_gathered", gathered);
                program.uniform1f("u_flare", flare);
                program.uniform1f("u_origin",
                    is_left ? (float) g.x : (float) (g.x + W));
                program.uniform1f("u_cum_base", is_left ? 0.0f : 1.0f);

                // Mirrors the vertex shader: band_w peaks at v = 1 and the band
                // spans [origin, origin +/- band_w], so damage outside it (e.g.
                // the drawer while fully open) costs no draw.
                const float max_bw = (float) src_w * (1.0f - p) +
                    (gathered + flare * foldP) * p;
                const float hx0 = is_left ? (float) g.x : (float) (g.x + W) - max_bw;
                const float hx1 = is_left ? (float) g.x + max_bw : (float) (g.x + W);

                for (const auto& box : data.damage)
                {
                    const auto b = wlr_box_from_pixman_box(box);
                    if ((b.x >= hx1 + 1.0f) || (b.x + b.width <= hx0 - 1.0f))
                    {
                        continue;
                    }

                    wf::gles::render_target_logic_scissor(data.target, b);
                    GL_CALL(glDrawArrays(GL_TRIANGLES, 0, n_verts));
                }
            };

            draw_half(0, seam, true);
            draw_half(seam, W - seam, false);

            program.deactivate();
            GL_CALL(glDisable(GL_SCISSOR_TEST));
        });
    }
};

inline void curtain_screenshot_node_t::gen_render_instances(
    std::vector<wf::scene::render_instance_uptr>& instances,
    wf::scene::damage_callback push_damage, wf::output_t *shown_on)
{
    instances.push_back(std::make_unique<curtain_screenshot_render_instance_t>(
        this, push_damage, shown_on));
}

class wayfire_curtain_peek_t : public wf::per_output_plugin_instance_t
{
    wf::option_wrapper_t<wf::activatorbinding_t> toggle_opt{"wayfire-curtain-peek/toggle"};
    wf::option_wrapper_t<double> split_ratio_opt{"wayfire-curtain-peek/split_ratio"};
    wf::option_wrapper_t<int> edge_px_opt{"wayfire-curtain-peek/edge_px"};
    wf::option_wrapper_t<wf::color_t> backdrop_color_opt{"wayfire-curtain-peek/backdrop_color"};
    wf::option_wrapper_t<std::string> drawer_app_id_opt{"wayfire-curtain-peek/drawer_app_id"};
    wf::option_wrapper_t<std::string> widget_app_id_opt{"wayfire-curtain-peek/widget_app_id"};
    wf::option_wrapper_t<wf::animation_description_t> duration_opt{"wayfire-curtain-peek/duration"};
    wf::option_wrapper_t<int> fold_count_opt{"wayfire-curtain-peek/fold_count"};
    wf::option_wrapper_t<double> fold_depth_opt{"wayfire-curtain-peek/fold_depth"};
    wf::option_wrapper_t<double> fold_shade_opt{"wayfire-curtain-peek/fold_shade"};

    wf::animation::simple_animation_t anim{duration_opt};

    enum class state_t { IDLE, OPENING, OPEN, CLOSING };
    state_t state = state_t::IDLE;

    wf::auxilliary_buffer_t screenshot_buf;
    std::shared_ptr<curtain_screenshot_node_t> screenshot_node;
    curtain_gl_t gl;

    std::shared_ptr<curtain_backdrop_node_t> backdrop;

    // Cached so we can re-enable it after disabling its node.
    wayfire_view desktop_view;

    // Shares BOTTOM with the grid, so it is hidden while the reveal is open.
    wayfire_view widget_view;

    // No grab: the revealed grid must stay clickable.
    wf::plugin_activation_data_t activation = {
        .name = "wayfire-curtain-peek",
        .capabilities = 0,
        .cancel = [this] { hard_reset(); },
    };

    wf::activator_callback on_toggle = [this] (const wf::activator_data_t&)
    {
        return ipc_toggle();
    };

    // Hide the grid as soon as it maps unless a reveal is open.
    wf::signal::connection_t<wf::view_mapped_signal> on_view_mapped =
        [this] (wf::view_mapped_signal *ev)
    {
        if ((ev->view->get_app_id() != (std::string) drawer_app_id_opt))
        {
            return;
        }

        desktop_view = ev->view;
        if (state == state_t::IDLE)
        {
            set_desktop_visible(false);
        }
    };

    wf::signal::connection_t<wf::view_unmapped_signal> on_view_unmapped =
        [this] (wf::view_unmapped_signal *ev)
    {
        if (ev->view == desktop_view)
        {
            desktop_view = nullptr;
        }

        if (ev->view == widget_view)
        {
            widget_view = nullptr;
        }
    };

    wf::effect_hook_t on_frame = [this] ()
    {
        const double v = (double) anim;
        apply_progress(v);

        if (!anim.running())
        {
            if (state == state_t::OPENING)
            {
                apply_progress(1.0);
                state = state_t::OPEN;
                // Static while open: stop the per-frame full-output damage.
                output->render->rem_effect(&on_frame);
            } else if (state == state_t::CLOSING)
            {
                apply_progress(0.0);
                hard_reset();
            }
        }
    };

  public:
    void init() override
    {
        curtain_log("per-output init on output=%p", (void *) output);
        output->add_activator(toggle_opt, &on_toggle);
        output->connect(&on_view_mapped);
        output->connect(&on_view_unmapped);

        // Logged because a stale app-id in wayfire.ini otherwise fails silently.
        curtain_log("app ids: drawer='%s' widget='%s'",
            ((std::string) drawer_app_id_opt).c_str(),
            ((std::string) widget_app_id_opt).c_str());

        desktop_view = lumen::find_bottom_view(output, drawer_app_id_opt);
        if (desktop_view)
        {
            set_desktop_visible(false);
        }

        curtain_log("found on init: drawer=%s widget=%s",
            desktop_view ? "yes" : "no",
            lumen::find_bottom_view(output, widget_app_id_opt) ? "yes" : "no");
    }

    void fini() override
    {
        curtain_log("per-output fini on output=%p state=%d", (void *) output, (int) state);
        output->rem_binding(&on_toggle);
        on_view_mapped.disconnect();
        on_view_unmapped.disconnect();
        if (state != state_t::IDLE)
        {
            hard_reset();
        }
        // The drawer is hidden while idle; balance that hide so it isn't left
        // stuck hidden on unload. The widget is already shown again (it is only
        // hidden while open, and hard_reset() re-shows it).
        set_desktop_visible(true);
        desktop_view = nullptr;
        widget_view = nullptr;
        // hard_reset() above already dropped the node that referenced it.
        wf::gles::run_in_context_if_gles([&]
        {
            gl.program.free_resources();
            if (gl.grid_vbo)
            {
                GL_CALL(glDeleteBuffers(1, &gl.grid_vbo));
                gl.grid_vbo = 0;
            }
        });
    }

    bool ipc_toggle()
    {
        if (state == state_t::IDLE)
        {
            return start_open();
        }
        if ((state == state_t::OPEN) || (state == state_t::OPENING))
        {
            start_close();
            return true;
        }
        return false;
    }

    bool ipc_start()
    {
        if (state == state_t::IDLE)
        {
            return start_open();
        }
        return false;
    }

    bool ipc_stop()
    {
        if ((state == state_t::OPEN) || (state == state_t::OPENING))
        {
            start_close();
            return true;
        }
        return false;
    }

  private:
    bool start_open()
    {
        curtain_log("start_open: activating");
        if (!output->activate_plugin(&activation))
        {
            curtain_log("start_open: activate_plugin returned false");
            return false;
        }

        // Relative geometry: output_node_t children are output-local (layout
        // geometry would double-offset); capture_output() needs layout geometry.
        const auto rel = output->get_relative_geometry();
        const int W = rel.width;
        const int seam_off = (int) std::lround(W * (double) split_ratio_opt);
        // XML caps edge_px at 400; it must also fit the narrower half.
        const int edge = std::min((int) edge_px_opt, std::min(seam_off, W - seam_off));

        // The grid is still hidden, so it is not captured.
        // Opaque black clear: lumen::capture_output frees the buffer on failure.
        if (!lumen::capture_output(output, screenshot_buf, 1.0f))
        {
            curtain_log("start_open: capture failed");
            output->deactivate_plugin(&activation);
            return false;
        }

        set_desktop_visible(true);
        set_widgets_visible(false);
        // Unfocusing the toplevel also fires lumen-drawer's foreign-toplevel
        // watcher, which drives its client-side search_entry.grab_focus().
        if (!desktop_view)
        {
            desktop_view = lumen::find_bottom_view(output, drawer_app_id_opt);
        }
        lumen::focus_view(desktop_view);

        // Back of BOTTOM, since the wallpaper is about to be hidden.
        backdrop = std::make_shared<curtain_backdrop_node_t>(
            rel, (wf::color_t) backdrop_color_opt);
        wf::scene::add_back(output->node_for_layer(wf::scene::layer::BOTTOM),
            backdrop);

        set_live_layers_hidden(true);

        screenshot_node = std::make_shared<curtain_screenshot_node_t>(
            rel, screenshot_buf.get_texture(), gl);
        screenshot_node->seam_x      = rel.x + seam_off;
        screenshot_node->edge_px     = edge;
        screenshot_node->progress    = 0.0f;
        screenshot_node->fold_count  = fold_count_opt;
        screenshot_node->fold_depth  = (float) (double) fold_depth_opt;
        screenshot_node->shade_depth = (float) (double) fold_shade_opt;
        wf::scene::add_front(output->node_for_layer(wf::scene::layer::OVERLAY),
            screenshot_node);

        curtain_log("start_open: W=%d seam_off=%d edge=%d", W, seam_off, edge);

        output->render->add_effect(&on_frame, wf::OUTPUT_EFFECT_PRE);
        state = state_t::OPENING;
        anim.animate(0.0, 1.0);
        return true;
    }

    void start_close()
    {
        if ((state != state_t::OPEN) && (state != state_t::OPENING))
        {
            return;
        }

        if (state == state_t::OPEN)
        {
            // Hook was removed once the open settled; nothing else drives frames.
            output->render->add_effect(&on_frame, wf::OUTPUT_EFFECT_PRE);
            output->render->schedule_redraw();
        }

        state = state_t::CLOSING;
        anim.animate((double) anim, 0.0);
    }

    void apply_progress(double p)
    {
        screenshot_node->progress = (float) p;
        output->render->damage_whole();
    }

    // set_node_enabled is a counter: every hide needs exactly one show.
    void set_desktop_visible(bool visible)
    {
        lumen::set_view_visible(desktop_view, output, drawer_app_id_opt, visible);
    }

    void set_widgets_visible(bool visible)
    {
        lumen::set_view_visible(widget_view, output, widget_app_id_opt, visible);
    }

    void set_live_layers_hidden(bool hidden)
    {
        for (auto layer : {wf::scene::layer::BACKGROUND,
            wf::scene::layer::WORKSPACE, wf::scene::layer::TOP})
        {
            wf::scene::set_node_enabled(output->node_for_layer(layer), !hidden);
        }
    }

    void hard_reset()
    {
        if (screenshot_node)
        {
            wf::scene::remove_child(screenshot_node);
            screenshot_node.reset();
        }
        screenshot_buf.free();

        set_live_layers_hidden(false);

        if (backdrop)
        {
            wf::scene::remove_child(backdrop);
            backdrop.reset();
        }

        // Show only the view start_open() hid: looking one up here would show
        // a widget that mapped mid-peek (never hidden) and unbalance its counter.
        if (widget_view)
        {
            set_widgets_visible(true);
        }
        set_desktop_visible(false);
        if (auto seat = wf::get_core().seat.get())
        {
            seat->refocus();
        }

        if (state != state_t::IDLE)
        {
            output->render->rem_effect(&on_frame);
            output->deactivate_plugin(&activation);
        }
        state = state_t::IDLE;
    }
};

struct wayfire_curtain_peek_plugin_t : lumen::ipc_plugin_t<wayfire_curtain_peek_t>
{
    wayfire_curtain_peek_plugin_t() : ipc_plugin_t("lumen-peek")
    {}
};

DECLARE_WAYFIRE_PLUGIN(wayfire_curtain_peek_plugin_t)
