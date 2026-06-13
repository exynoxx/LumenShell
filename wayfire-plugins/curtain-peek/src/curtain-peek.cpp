#include <wayfire/per-output-plugin.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/output.hpp>
#include <wayfire/core.hpp>
#include <wayfire/view.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/view-helpers.hpp>
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
#include <wayfire/plugins/ipc/ipc-method-repository.hpp>
#include <wayfire/plugins/common/shared-core-data.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/region.hpp>

#include <memory>
#include <vector>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdarg>
#include <ctime>

namespace
{
constexpr const char *SCREENSHOT_NODE_NAME = "wayfire-curtain-peek-screenshot";

// Tmp logging, mirroring the desktop-peek plugin's /tmp log so a single
// tail -f can follow both peek variants. Append-only; truncate before a session.
inline void curtain_log(const char *fmt, ...)
{
    FILE *fp = std::fopen("/tmp/wayfire-curtain-peek.log", "a");
    if (!fp)
    {
        return;
    }

    timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    std::fprintf(fp, "[%ld.%03ld] ", (long) ts.tv_sec, (long) (ts.tv_nsec / 1000000));

    va_list ap;
    va_start(ap, fmt);
    std::vfprintf(fp, fmt, ap);
    va_end(ap);

    std::fputc('\n', fp);
    std::fclose(fp);
}
}

// ---------------------------------------------------------------------------
// Backdrop: a static full-output solid-colour fill drawn behind the desktop
// grid (a flat, GNOME-Shell-like grey). While the curtain is closed it is
// hidden under the screenshot; once the screenshot splits it shows through the
// grid's transparent areas. It never moves, so it is a plain node.
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Screenshot curtain: a full-output node, sitting on the OVERLAY layer (above
// everything), that draws a captured snapshot of the screen split down a
// vertical seam, then gathers each half aside like a real fabric curtain.
//
// Each half is drawn as a single warped triangle mesh through a small GLES
// program. The vertex shader maps a regular (u, v) grid over the half's
// snapshot region onto the gathered band: a sinusoidal fold function compresses
// the cloth where a pleat turns away from the viewer and stretches it where one
// faces forward (the classic "vertex displacement" curtain trick), while the
// band's width grows quadratically toward the floor so the free inner edge
// bows out in a smooth arc instead of a straight line. The fragment shader
// samples the snapshot and shades it per-pixel with a cosine fold-lighting
// term, giving the flat capture a 3D, cloth-like read with no banding. This is
// two draw calls per frame — far cheaper, and far smoother, than the previous
// approach of tiling the half with thousands of axis-aligned textured strips.
// ---------------------------------------------------------------------------

// Vertex shader: warp a (u, v) grid of the half onto the gathered, pleated,
// arced band. All displacement is analytic so the grid can stay coarse.
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

// Fragment shader: sample the snapshot and fake fold lighting. The phase offset
// keeps the lit ridge and shadowed trough off the geometric crease, so it reads
// as a side light rather than flat ambient occlusion.
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

// Build the static (u, v) grid for one half as a triangle list. The mesh is
// identical every frame and for both halves, so it is built once and reused;
// all the per-frame motion lives in the vertex shader's uniforms.
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

class curtain_screenshot_node_t : public wf::scene::node_t
{
  public:
    wf::geometry_t geo;            // full output, output-relative {0,0,W,H}
    wlr_texture   *tex = nullptr;  // the captured snapshot (owned by the plugin)
    float tex_scale = 1.0f;        // output scale: logical px -> buffer texels
    int   seam_x    = 0;           // seam position, output-relative
    int   edge_px   = 0;           // residual gathered stack width per half (px)
    float progress  = 0.0f;        // 0 = closed (flat), 1 = fully gathered open

    // Cloth-fold tunables (mirrored from plugin options).
    int   fold_count  = 5;         // pleats across each half
    float fold_depth  = 0.4f;      // strip-width modulation amplitude (0..1)
    float shade_depth = 0.5f;      // peak fold shadow opacity (0..1)

    // GLES warp program + cached mesh, compiled/built lazily on first render
    // (the only point we are guaranteed a current GL context).
    OpenGL::program_t  program;
    bool               gl_ready = false;
    std::vector<float> grid;

    curtain_screenshot_node_t(wf::geometry_t g, wlr_texture *t, float scale) :
        wf::scene::node_t(false), geo(g), tex(t), tex_scale(scale)
    {}

    ~curtain_screenshot_node_t() override
    {
        wf::gles::run_in_context_if_gles([&] { program.free_resources(); });
    }

    std::string stringify() const override
    {
        return "curtain-peek-screenshot";
    }

    // The two halves only ever gather within the output, so the full output is
    // a safe (and simple) bounding box.
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

    // Mesh resolution per half. The warp is analytic and interpolates smoothly,
    // so a coarse grid suffices: NU across resolves the pleats, NV down resolves
    // the inner-edge arc. 64 x 24 = ~9k verts/half, two draw calls per frame.
    static constexpr int NU = 64;
    static constexpr int NV = 24;

    void render(const wf::scene::render_instruction_t& data) override
    {
        if (!self->tex)
        {
            return;
        }

        const auto g = self->geo;           // logical, full output
        const int  W = g.width;
        if ((W <= 0) || (g.height <= 0))
        {
            return;
        }

        const float p     = std::clamp(self->progress, 0.0f, 1.0f);
        const int   seam  = std::clamp(self->seam_x, g.x, g.x + W) - g.x; // 0..W
        const int   folds = std::max(1, self->fold_count);
        const float foldDepth  = std::clamp(self->fold_depth, 0.0f, 0.9f);
        const float shadeDepth = std::clamp(self->shade_depth, 0.0f, 1.0f);

        // Ease the folds + shading in so a closed curtain is perfectly flat and
        // the pleating only develops once the halves start to part.
        const float foldP = std::sin(p * 1.5707963f);

        data.pass->custom_gles_subpass([&]
        {
            if (!self->gl_ready)
            {
                self->program.compile(curtain_vert_source, curtain_frag_source);
                self->grid     = curtain_build_grid(NU, NV);
                self->gl_ready = true;
            }

            const auto matrix =
                wf::gles::render_target_orthographic_projection(data.target);
            const int n_verts = (int) (self->grid.size() / 2);

            wf::gles_texture_t gtex{self->tex};
            self->program.use(wf::TEXTURE_TYPE_RGBA);
            self->program.set_active_texture(gtex);
            self->program.attrib_pointer("grid", 2, 0, self->grid.data());
            self->program.uniformMatrix4f("matrix", matrix);

            // Uniforms shared by both halves.
            self->program.uniform1f("u_p", p);
            self->program.uniform1f("u_foldP", foldP);
            self->program.uniform1f("u_foldDepth", foldDepth);
            self->program.uniform1f("u_folds", (float) folds);
            self->program.uniform1f("u_shade", shadeDepth);
            self->program.uniform1f("u_W", (float) W);
            self->program.uniform1f("u_gy", (float) g.y);
            self->program.uniform1f("u_H", (float) g.height);

            // src_x0 / src_w are output-relative (the texture spans [0, W]); the
            // left half is pinned to the left wall (origin g.x, cum 0..1) and the
            // right half to the right wall (origin g.x+W, cum walks back to it).
            auto draw_half = [&] (int src_x0, int src_w, bool is_left)
            {
                if (src_w <= 0)
                {
                    return;
                }

                const float gathered = std::min((float) self->edge_px, (float) src_w);
                const float flare = std::min((float) src_w * 0.22f,
                    (float) src_w - gathered);

                self->program.uniform1f("u_src_x0", (float) src_x0);
                self->program.uniform1f("u_src_w", (float) src_w);
                self->program.uniform1f("u_gathered", gathered);
                self->program.uniform1f("u_flare", flare);
                self->program.uniform1f("u_origin",
                    is_left ? (float) g.x : (float) (g.x + W));
                self->program.uniform1f("u_cum_base", is_left ? 0.0f : 1.0f);

                for (const auto& box : data.damage)
                {
                    wf::gles::render_target_logic_scissor(data.target,
                        wlr_box_from_pixman_box(box));
                    GL_CALL(glDrawArrays(GL_TRIANGLES, 0, n_verts));
                }
            };

            // Left half: snapshot columns [0, seam]; right half: [seam, W].
            draw_half(0, seam, true);
            draw_half(seam, W - seam, false);

            self->program.deactivate();
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

// ---------------------------------------------------------------------------
// Per-output plugin instance.
// ---------------------------------------------------------------------------
class wayfire_curtain_peek_t : public wf::per_output_plugin_instance_t
{
    wf::option_wrapper_t<wf::activatorbinding_t> toggle_opt{"wayfire-curtain-peek/toggle"};
    wf::option_wrapper_t<wf::activatorbinding_t> dismiss_opt{"wayfire-curtain-peek/dismiss"};
    wf::option_wrapper_t<double> split_ratio_opt{"wayfire-curtain-peek/split_ratio"};
    wf::option_wrapper_t<int> edge_px_opt{"wayfire-curtain-peek/edge_px"};
    wf::option_wrapper_t<wf::color_t> backdrop_color_opt{"wayfire-curtain-peek/backdrop_color"};
    wf::option_wrapper_t<std::string> desktop_app_id_opt{"wayfire-curtain-peek/desktop_app_id"};
    wf::option_wrapper_t<wf::animation_description_t> duration_opt{"wayfire-curtain-peek/duration"};
    wf::option_wrapper_t<int> fold_count_opt{"wayfire-curtain-peek/fold_count"};
    wf::option_wrapper_t<double> fold_depth_opt{"wayfire-curtain-peek/fold_depth"};
    wf::option_wrapper_t<double> fold_shade_opt{"wayfire-curtain-peek/fold_shade"};

    wf::animation::simple_animation_t anim{duration_opt};

    enum class state_t { IDLE, OPENING, OPEN, CLOSING };
    state_t state = state_t::IDLE;

    // The frozen snapshot of the screen and the node that splits it.
    wf::auxilliary_buffer_t screenshot_buf;
    std::shared_ptr<curtain_screenshot_node_t> screenshot_node;

    // Grey fill drawn behind the desktop grid.
    std::shared_ptr<curtain_backdrop_node_t> backdrop;

    // The desktop grid view (app-id == desktop_app_id). It is kept hidden while
    // the curtain is closed and revealed only while it is open; cached so we can
    // toggle it even after we have disabled (and thus hidden) its node.
    wayfire_view desktop_view;

    // No grab (capabilities = 0): while open, the revealed desktop grid must
    // stay clickable, same rationale as wayfire-desktop-peek.
    wf::plugin_activation_data_t activation = {
        .name = "wayfire-curtain-peek",
        .capabilities = 0,
        .cancel = [this] { hard_reset(); },
    };

    wf::activator_callback on_toggle = [this] (const wf::activator_data_t&)
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
    };

    // Restore-only; a no-op from IDLE so it doesn't steal Escape from other
    // consumers when nothing is open.
    wf::activator_callback on_dismiss = [this] (const wf::activator_data_t&)
    {
        if ((state == state_t::OPEN) || (state == state_t::OPENING))
        {
            start_close();
            return true;
        }
        return false;
    };

    // Keep the desktop grid hidden until a curtain peek reveals it. Catch it as
    // soon as it maps and hide it straight away if nothing is open.
    wf::signal::connection_t<wf::view_mapped_signal> on_view_mapped =
        [this] (wf::view_mapped_signal *ev)
    {
        if (!is_desktop_view(ev->view))
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
        output->add_activator(dismiss_opt, &on_dismiss);
        output->connect(&on_view_mapped);
        output->connect(&on_view_unmapped);

        // The desktop grid may already be mapped by the time we initialise.
        desktop_view = find_desktop_view();
        if (desktop_view)
        {
            set_desktop_visible(false);
        }
    }

    void fini() override
    {
        curtain_log("per-output fini on output=%p state=%d", (void *) output, (int) state);
        output->rem_binding(&on_toggle);
        output->rem_binding(&on_dismiss);
        on_view_mapped.disconnect();
        on_view_unmapped.disconnect();
        if (state != state_t::IDLE)
        {
            hard_reset();
        }
        // Don't leave the desktop stuck hidden if the plugin is unloaded.
        set_desktop_visible(true);
        desktop_view = nullptr;
    }

    // Entry points for the plugin-wide IPC handlers.
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

        // Layout (global) geometry, not relative: the snapshot is rendered from
        // the global scene root and the overlay/backdrop nodes are placed in the
        // output's render target, both of which use layout coordinates. On a
        // non-primary output relative geometry is still {0,0,W,H}, which would
        // capture the primary output's region (black/garbage) and draw the
        // curtain off-screen — the multi-monitor bug this fixes.
        const auto rel = output->get_layout_geometry();
        const int W = rel.width;
        const float scale = output->handle ? output->handle->scale : 1.0f;
        const double ratio = std::clamp((double) split_ratio_opt, 0.1, 0.9);
        const int seam_off = (int) std::lround(W * ratio);
        const int edge = std::clamp((int) edge_px_opt, 0,
            std::max(0, std::min(seam_off, W - seam_off)));

        // 1. Freeze the screen as it is right now. The desktop grid is still
        //    hidden at this point, so the snapshot is purely the wallpaper, app
        //    windows and panel — exactly the "curtain" we want to split.
        if (!capture_output())
        {
            curtain_log("start_open: capture failed");
            output->deactivate_plugin(&activation);
            return false;
        }

        // 2. Reveal the (live, interactive) desktop grid. It lives on BOTTOM, so
        //    it is naturally below the OVERLAY screenshot added in step 5.
        set_desktop_visible(true);

        // 2a. Hand keyboard focus to the revealed grid so the user can start
        //     typing into its search field straight away. Moving the seat off
        //     the previously-focused toplevel also makes lumen-desktop's
        //     foreign-toplevel watcher fire (no toplevel focused), which is
        //     what drives its client-side search_entry.grab_focus().
        focus_desktop();

        // 3. Grey backdrop behind the grid (back of the BOTTOM layer), so the
        //    grid's transparent areas show grey rather than the now-hidden
        //    wallpaper.
        backdrop = std::make_shared<curtain_backdrop_node_t>(
            rel, (wf::color_t) backdrop_color_opt);
        wf::scene::add_back(output->node_for_layer(wf::scene::layer::BOTTOM),
            backdrop);

        // 4. Hide the live wallpaper / windows / panel so only the grid and the
        //    grey backdrop are visible behind the splitting snapshot. (The frozen
        //    copy of them lives in the snapshot.)
        set_live_layers_hidden(true);

        // 5. Drop the snapshot on top of everything (OVERLAY) and start closed.
        screenshot_node = std::make_shared<curtain_screenshot_node_t>(
            rel, screenshot_buf.get_texture(), scale);
        screenshot_node->seam_x      = rel.x + seam_off;
        screenshot_node->edge_px     = edge;
        screenshot_node->progress    = 0.0f;
        screenshot_node->fold_count  = std::max(1, (int) fold_count_opt);
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

        state = state_t::CLOSING;
        anim.animate((double) anim, 0.0);
    }

    void apply_progress(double p)
    {
        if (!screenshot_node)
        {
            return;
        }

        screenshot_node->progress = (float) p;
        // Drive the animation: a continuous full-output repaint until the
        // simple_animation_t settles.
        output->render->damage_whole();
    }

    bool is_desktop_view(wayfire_view view) const
    {
        return view && (view->get_app_id() == (std::string) desktop_app_id_opt);
    }

    // Find the desktop grid (the BOTTOM-layer view whose app-id matches the
    // configured id) on this output, if it is currently mapped.
    wayfire_view find_desktop_view()
    {
        for (auto& view : wf::collect_views_from_output(output,
            {wf::scene::layer::BOTTOM}))
        {
            if (view && view->is_mapped() && is_desktop_view(view))
            {
                return view;
            }
        }
        return nullptr;
    }

    // Give keyboard focus to the desktop grid's layer surface. Layer-shell
    // surfaces can't grab focus client-side below the shell layer, so the
    // compositor has to do it — mirrors wayfire-default-focus. Used on reveal
    // so the grid's search field is ready to type into immediately.
    void focus_desktop()
    {
        if (!desktop_view)
        {
            desktop_view = find_desktop_view();
        }
        if (!desktop_view)
        {
            return;
        }

        auto seat = wf::get_core().seat.get();
        if (!seat)
        {
            return;
        }

        seat->set_active_node(desktop_view->get_surface_root_node(),
            wf::keyboard_focus_reason::REFOCUS);
    }

    // Show or hide the desktop grid by toggling its scene node. The view stays
    // mapped throughout, so the GTK app keeps running; we just stop rendering it
    // while the curtain is closed.
    void set_desktop_visible(bool visible)
    {
        if (!desktop_view)
        {
            desktop_view = find_desktop_view();
        }
        if (desktop_view)
        {
            wf::scene::set_node_enabled(desktop_view->get_root_node(), visible);
        }
    }

    // Hide / show the live foreground layers (wallpaper, app windows, panel).
    // BOTTOM (the desktop grid + grey backdrop) and OVERLAY (the snapshot) are
    // left enabled.
    void set_live_layers_hidden(bool hidden)
    {
        for (auto layer : {wf::scene::layer::BACKGROUND,
            wf::scene::layer::WORKSPACE, wf::scene::layer::TOP})
        {
            wf::scene::set_node_enabled(output->node_for_layer(layer), !hidden);
        }
    }

    // Render the current scene of this output into screenshot_buf. Uses the
    // output's layout geometry so the correct (possibly non-primary) region of
    // the global scene is captured rather than the top-left of the layout.
    bool capture_output()
    {
        const auto rel = output->get_layout_geometry();
        const float scale = output->handle ? output->handle->scale : 1.0f;
        if ((rel.width <= 0) || (rel.height <= 0))
        {
            return false;
        }

        screenshot_buf.allocate({rel.width, rel.height}, scale);

        std::vector<wf::scene::render_instance_uptr> instances;
        wf::get_core().scene()->gen_render_instances(instances,
            [] (const wf::region_t&) {}, output);

        wf::render_target_t target{screenshot_buf};
        target.geometry     = rel;
        target.scale        = scale;
        target.wl_transform = WL_OUTPUT_TRANSFORM_NORMAL;

        wf::render_pass_params_t params;
        params.instances        = &instances;
        params.target           = target;
        params.damage           = wf::region_t{rel};
        params.background_color = {0.0, 0.0, 0.0, 1.0};
        params.reference_output = output;
        params.flags            = wf::RPASS_CLEAR_BACKGROUND;
        wf::render_pass_t::run(params);

        return screenshot_buf.get_texture() != nullptr;
    }

    void hard_reset()
    {
        if (screenshot_node)
        {
            wf::scene::remove_child(screenshot_node);
            screenshot_node.reset();
        }
        screenshot_buf.free();

        // Bring the live layers back before touching the grid/backdrop.
        set_live_layers_hidden(false);

        if (backdrop)
        {
            wf::scene::remove_child(backdrop);
            backdrop.reset();
        }

        // Curtain closed → desktop grid goes back to hidden. Hand keyboard
        // focus back to whatever real window should hold it now that the grid's
        // surface is no longer visible.
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

// ---------------------------------------------------------------------------
// Plugin wrapper: per-output instances + plugin-wide IPC surface, identical in
// shape to wayfire-desktop-peek so lumen-desktop/lumen-panel can drive it.
// ---------------------------------------------------------------------------
class wayfire_curtain_peek_plugin_t :
    public wf::per_output_plugin_t<wayfire_curtain_peek_t>
{
    wf::shared_data::ref_ptr_t<wf::ipc::method_repository_t> ipc_repo;

    wayfire_curtain_peek_t *instance_for_active_output()
    {
        auto seat = wf::get_core().seat.get();
        wf::output_t *active = seat ? seat->get_active_output() : nullptr;

        if (active)
        {
            auto it = this->output_instance.find(active);
            if (it != this->output_instance.end())
            {
                return it->second.get();
            }
        }

        if (!this->output_instance.empty())
        {
            return this->output_instance.begin()->second.get();
        }

        return nullptr;
    }

    wf::ipc::method_callback on_toggle_ipc = [this] (const wf::json_t&) -> wf::json_t
    {
        auto inst = instance_for_active_output();
        wf::json_t res;
        res["result"] = (inst != nullptr) && inst->ipc_toggle() ? "ok" : "noop";
        return res;
    };

    wf::ipc::method_callback on_start_ipc = [this] (const wf::json_t&) -> wf::json_t
    {
        auto inst = instance_for_active_output();
        wf::json_t res;
        res["result"] = (inst != nullptr) && inst->ipc_start() ? "ok" : "noop";
        return res;
    };

    wf::ipc::method_callback on_stop_ipc = [this] (const wf::json_t&) -> wf::json_t
    {
        auto inst = instance_for_active_output();
        wf::json_t res;
        res["result"] = (inst != nullptr) && inst->ipc_stop() ? "ok" : "noop";
        return res;
    };

  public:
    void init() override
    {
        curtain_log("plugin init: registering IPC methods");
        wf::per_output_plugin_t<wayfire_curtain_peek_t>::init();
        ipc_repo->register_method("wayfire-curtain-peek/toggle", on_toggle_ipc);
        ipc_repo->register_method("wayfire-curtain-peek/start",  on_start_ipc);
        ipc_repo->register_method("wayfire-curtain-peek/stop",   on_stop_ipc);
    }

    void fini() override
    {
        curtain_log("plugin fini: unregistering IPC methods");
        ipc_repo->unregister_method("wayfire-curtain-peek/toggle");
        ipc_repo->unregister_method("wayfire-curtain-peek/start");
        ipc_repo->unregister_method("wayfire-curtain-peek/stop");
        wf::per_output_plugin_t<wayfire_curtain_peek_t>::fini();
    }
};

DECLARE_WAYFIRE_PLUGIN(wayfire_curtain_peek_plugin_t)
