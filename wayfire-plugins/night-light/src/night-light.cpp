#include <wayfire/per-output-plugin.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/output.hpp>
#include <wayfire/core.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/render.hpp>
#include <wayfire/opengl.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/config/types.hpp>
#include <wayfire/util/duration.hpp>
#include <wayfire/scene.hpp>
#include <wayfire/scene-render.hpp>
#include <wayfire/scene-operations.hpp>
#include <wayfire/plugins/ipc/ipc-method-repository.hpp>
#include <wayfire/plugins/common/shared-core-data.hpp>
#include <wayfire/region.hpp>

#include <memory>
#include <vector>
#include <algorithm>
#include <cmath>

namespace
{
// Tanner-Helland black-body approximation: map a colour temperature in Kelvin
// to a linear RGB multiplier in [0, 1], then normalise so the brightest channel
// is 1.0. The result is a pure colour shift (warm tint) with no dimming — at
// 6500K it returns ~(1,1,1) and so leaves the screen untouched, while lower
// temperatures push the green/blue channels down toward amber.
inline void kelvin_to_rgb(int kelvin, float &r, float &g, float &b)
{
    const double t = std::clamp(kelvin, 1000, 40000) / 100.0;

    double rr, gg, bb;

    // red
    rr = (t <= 66) ? 255.0 : 329.698727446 * std::pow(t - 60.0, -0.1332047592);

    // green
    gg = (t <= 66) ? 99.4708025861 * std::log(t) - 161.1195681661
                   : 288.1221695283 * std::pow(t - 60.0, -0.0755148492);

    // blue
    bb = (t >= 66) ? 255.0
         : (t <= 19) ? 0.0
         : 138.5177312231 * std::log(t - 10.0) - 305.0447927307;

    r = (float) (std::clamp(rr, 0.0, 255.0) / 255.0);
    g = (float) (std::clamp(gg, 0.0, 255.0) / 255.0);
    b = (float) (std::clamp(bb, 0.0, 255.0) / 255.0);

    const float m = std::max({r, g, b, 0.0001f});
    r /= m;
    g /= m;
    b /= m;
}

// A trivial full-output solid-colour quad. No texture: the warm tint is a flat
// colour, and the per-pixel multiply happens via the blend func, not the
// shader. version 100 GLES so it matches the rest of the tree (curtain-peek).
static const char *tint_vert_source =
    R"(
#version 100
attribute highp vec2 pos;
uniform mat4 matrix;
void main() { gl_Position = matrix * vec4(pos, 0.0, 1.0); }
)";

static const char *tint_frag_source =
    R"(
#version 100
precision highp float;
uniform vec4 u_tint;        // current (animated) RGB multiplier, a == 1.0
void main() { gl_FragColor = u_tint; }
)";
}

// ---------------------------------------------------------------------------
// Tint node: a full-output quad on the OVERLAY layer, drawn with a MULTIPLY
// blend (out = dst * tint) so it shifts every pixel's colour toward amber
// instead of laying a translucent veil over it. White goes warm, black stays
// black — a true colour-temperature filter, like Redshift / GNOME Night Light.
// ---------------------------------------------------------------------------
class night_tint_node_t : public wf::scene::node_t
{
  public:
    wf::geometry_t geo;             // output-relative full geometry
    float tint[3] = {1.0f, 1.0f, 1.0f}; // current (animated) RGB multiplier

    OpenGL::program_t program;
    bool gl_ready = false;

    night_tint_node_t(wf::geometry_t g) :
        wf::scene::node_t(false), geo(g)
    {}

    ~night_tint_node_t() override
    {
        wf::gles::run_in_context_if_gles([&] { program.free_resources(); });
    }

    std::string stringify() const override
    {
        return "night-light-tint";
    }

    wf::geometry_t get_bounding_box() override
    {
        return geo;
    }

    void gen_render_instances(std::vector<wf::scene::render_instance_uptr>& instances,
        wf::scene::damage_callback push_damage, wf::output_t *shown_on) override;
};

class night_tint_render_instance_t :
    public wf::scene::simple_render_instance_t<night_tint_node_t>
{
  public:
    using simple_render_instance_t::simple_render_instance_t;

    void render(const wf::scene::render_instruction_t& data) override
    {
        const auto g = self->geo;
        if ((g.width <= 0) || (g.height <= 0))
        {
            return;
        }

        const float x0 = (float) g.x, y0 = (float) g.y;
        const float x1 = (float) (g.x + g.width), y1 = (float) (g.y + g.height);
        const float verts[12] = {x0, y0, x1, y0, x1, y1, x0, y0, x1, y1, x0, y1};

        data.pass->custom_gles_subpass([&]
        {
            if (!self->gl_ready)
            {
                self->program.compile(tint_vert_source, tint_frag_source);
                self->gl_ready = true;
            }

            const auto matrix =
                wf::gles::render_target_orthographic_projection(data.target);
            self->program.use(wf::TEXTURE_TYPE_RGBA);
            self->program.uniformMatrix4f("matrix", matrix);
            self->program.uniform4f("u_tint",
                glm::vec4(self->tint[0], self->tint[1], self->tint[2], 1.0f));
            self->program.attrib_pointer("pos", 2, 0, verts);

            // MULTIPLY: out = dst * src. This is what makes it a warm filter
            // rather than a dim haze (which a source-over alpha blend would be).
            GL_CALL(glBlendFunc(GL_DST_COLOR, GL_ZERO));
            for (const auto& box : data.damage)
            {
                wf::gles::render_target_logic_scissor(data.target,
                    wlr_box_from_pixman_box(box));
                GL_CALL(glDrawArrays(GL_TRIANGLES, 0, 6));
            }

            // Restore the subpass default blend (1, 1-src_alpha) so any later
            // draw in this pass composites normally.
            GL_CALL(glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA));
            GL_CALL(glDisable(GL_SCISSOR_TEST));
            self->program.deactivate();
        });
    }
};

inline void night_tint_node_t::gen_render_instances(
    std::vector<wf::scene::render_instance_uptr>& instances,
    wf::scene::damage_callback push_damage, wf::output_t *shown_on)
{
    instances.push_back(std::make_unique<night_tint_render_instance_t>(
        this, push_damage, shown_on));
}

// ---------------------------------------------------------------------------
// Per-output plugin instance. Owns this output's tint node and animation. The
// node is added to the OVERLAY layer on start and removed once a fade-out
// completes; while it is present the tint LERPs white -> warm by the 0..1
// animation value, giving a smooth fade in / out.
// ---------------------------------------------------------------------------
class wayfire_night_light_t : public wf::per_output_plugin_instance_t
{
    wf::option_wrapper_t<int> temperature_opt{"wayfire-night-light/temperature"};
    wf::option_wrapper_t<wf::animation_description_t> duration_opt{
        "wayfire-night-light/duration"};

    wf::animation::simple_animation_t anim{duration_opt};

    enum class state_t { OFF, FADING_IN, ON, FADING_OUT };
    state_t state = state_t::OFF;

    std::shared_ptr<night_tint_node_t> node;
    float warm[3] = {1.0f, 1.0f, 1.0f}; // target tint for the current temperature

    wf::effect_hook_t on_frame = [this] ()
    {
        const float p = (float) (double) anim;  // 0..1 strength
        if (node)
        {
            for (int i = 0; i < 3; i++)
            {
                node->tint[i] = 1.0f + (warm[i] - 1.0f) * p; // LERP white -> warm
            }

            // Repaint while animating. Once settled we keep a single trailing
            // damage so the static tint is composited at least once more; the
            // node then stays in the OVERLAY layer and re-applies on natural
            // damage from windows below it.
            output->render->damage_whole();
        }

        if (!anim.running())
        {
            if (state == state_t::FADING_IN)
            {
                state = state_t::ON;
            } else if (state == state_t::FADING_OUT)
            {
                teardown();
            }
        }
    };

  public:
    // No keybinding: night light is panel-driven only, over IPC.
    void init() override
    {}

    void fini() override
    {
        if (state != state_t::OFF)
        {
            teardown();
        }
    }

    bool ipc_start()
    {
        if ((state == state_t::ON) || (state == state_t::FADING_IN))
        {
            return false;
        }

        if (state == state_t::OFF)
        {
            setup();
        }

        kelvin_to_rgb((int) temperature_opt, warm[0], warm[1], warm[2]);
        state = state_t::FADING_IN;
        anim.animate((double) anim, 1.0);
        return true;
    }

    bool ipc_stop()
    {
        if ((state == state_t::OFF) || (state == state_t::FADING_OUT))
        {
            return false;
        }

        state = state_t::FADING_OUT;
        anim.animate((double) anim, 0.0);
        return true;
    }

    bool ipc_toggle()
    {
        return ((state == state_t::OFF) || (state == state_t::FADING_OUT))
            ? ipc_start() : ipc_stop();
    }

  private:
    void setup()
    {
        node = std::make_shared<night_tint_node_t>(output->get_relative_geometry());
        wf::scene::add_front(output->node_for_layer(wf::scene::layer::OVERLAY), node);
        output->render->add_effect(&on_frame, wf::OUTPUT_EFFECT_PRE);
    }

    void teardown()
    {
        output->render->rem_effect(&on_frame);
        if (node)
        {
            wf::scene::remove_child(node);
            node.reset();
        }
        output->render->damage_whole();
        state = state_t::OFF;
    }
};

// ---------------------------------------------------------------------------
// Plugin wrapper: per-output instances + a plugin-wide IPC surface. Night light
// is a global effect, so each verb fans out to EVERY tracked output (not just
// the focused one, unlike the peek plugins). A single plugin-level `enabled`
// flag keeps all outputs in lockstep so toggle stays consistent.
// ---------------------------------------------------------------------------
class wayfire_night_light_plugin_t :
    public wf::per_output_plugin_t<wayfire_night_light_t>
{
    wf::shared_data::ref_ptr_t<wf::ipc::method_repository_t> ipc_repo;
    bool enabled = false;

    wf::json_t set_all(bool on)
    {
        bool any = false;
        for (auto& [out, inst] : this->output_instance)
        {
            any |= on ? inst->ipc_start() : inst->ipc_stop();
        }

        if (any)
        {
            enabled = on;
        }

        wf::json_t res;
        res["result"] = any ? "ok" : "noop";
        return res;
    }

    wf::ipc::method_callback on_toggle_ipc = [this] (const wf::json_t&) -> wf::json_t
    {
        return set_all(!enabled);
    };

    wf::ipc::method_callback on_start_ipc = [this] (const wf::json_t&) -> wf::json_t
    {
        return set_all(true);
    };

    wf::ipc::method_callback on_stop_ipc = [this] (const wf::json_t&) -> wf::json_t
    {
        return set_all(false);
    };

  public:
    void init() override
    {
        wf::per_output_plugin_t<wayfire_night_light_t>::init();
        ipc_repo->register_method("wayfire-night-light/toggle", on_toggle_ipc);
        ipc_repo->register_method("wayfire-night-light/start",  on_start_ipc);
        ipc_repo->register_method("wayfire-night-light/stop",   on_stop_ipc);
    }

    void fini() override
    {
        ipc_repo->unregister_method("wayfire-night-light/toggle");
        ipc_repo->unregister_method("wayfire-night-light/start");
        ipc_repo->unregister_method("wayfire-night-light/stop");
        wf::per_output_plugin_t<wayfire_night_light_t>::fini();
    }
};

DECLARE_WAYFIRE_PLUGIN(wayfire_night_light_plugin_t)
