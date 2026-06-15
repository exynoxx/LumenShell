#include <wayfire/per-output-plugin.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/output.hpp>
#include <wayfire/core.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/render.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/config/types.hpp>
#include <wayfire/util/duration.hpp>
#include <wayfire/util.hpp>
#include <wayfire/scene.hpp>
#include <wayfire/scene-render.hpp>
#include <wayfire/scene-operations.hpp>
#include <wayfire/plugins/ipc/ipc-method-repository.hpp>
#include <wayfire/plugins/common/shared-core-data.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/region.hpp>

#include <memory>
#include <vector>
#include <cmath>
#include <cstdio>
#include <cstdarg>
#include <ctime>
#include <string>

namespace
{
// Tmp logging, mirroring converge-lock / curtain-peek / slide-peek so a single
// tail -f follows every reveal/transition variant. Append-only.
inline void flip_log(const char *fmt, ...)
{
    FILE *fp = std::fopen("/tmp/wayfire-flip-lock.log", "a");
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
// Backdrop: a static full-output solid-colour fill (black by default) drawn
// behind the foreshortening screenshot. As the frozen screen rotates edge-on,
// the backdrop is what fills the widening margins, so the desktop appears to
// turn away over a void. It never moves.
// ---------------------------------------------------------------------------
class flip_backdrop_node_t : public wf::scene::node_t
{
  public:
    wf::geometry_t geo;
    wf::color_t    color;

    flip_backdrop_node_t(wf::geometry_t g, wf::color_t c) :
        wf::scene::node_t(false), geo(g), color(c)
    {}

    std::string stringify() const override
    {
        return "flip-lock-backdrop";
    }

    wf::geometry_t get_bounding_box() override
    {
        return geo;
    }

    void gen_render_instances(std::vector<wf::scene::render_instance_uptr>& instances,
        wf::scene::damage_callback push_damage, wf::output_t *shown_on) override;
};

class flip_backdrop_render_instance_t :
    public wf::scene::simple_render_instance_t<flip_backdrop_node_t>
{
  public:
    using simple_render_instance_t::simple_render_instance_t;

    void render(const wf::scene::render_instruction_t& data) override
    {
        data.pass->add_rect(self->color, data.target, self->geo, data.damage);
    }
};

inline void flip_backdrop_node_t::gen_render_instances(
    std::vector<wf::scene::render_instance_uptr>& instances,
    wf::scene::damage_callback push_damage, wf::output_t *shown_on)
{
    instances.push_back(std::make_unique<flip_backdrop_render_instance_t>(
        this, push_damage, shown_on));
}

// ---------------------------------------------------------------------------
// Flip screenshot: a full-output OVERLAY node drawing a frozen snapshot of the
// screen as one plane that foreshortens toward an axis, as if the screen were
// rotating away on a hinge until it goes edge-on (invisible) at progress 1.
//
// Like converge-lock this avoids a GLES shader: a true 3D perspective rotation
// can't be expressed with add_texture()'s axis-aligned dst rect, so we use an
// orthographic foreshorten — width (Y axis) or height (X axis) scaled by
// cos(progress * pi/2), anchored at the output centre. The lock surface that
// expands out of this (lumen-lockscreen's FlipReveal) does the matching 3D
// rotate in GSK; the two only ever meet at the invisible edge-on frame, so the
// projection mismatch is never on screen at once.
// ---------------------------------------------------------------------------
class flip_screenshot_node_t : public wf::scene::node_t
{
  public:
    wf::geometry_t geo;            // full output, output-relative {0,0,W,H}
    wlr_texture   *tex = nullptr;  // the captured snapshot (owned by the plugin)
    float          tex_scale = 1.0f;
    double         progress = 0.0; // 0 = full screen, 1 = edge-on (invisible)
    bool           horizontal = true; // true = Y axis (shrink width), false = X axis

    flip_screenshot_node_t(wf::geometry_t g, wlr_texture *t, float s, bool horiz) :
        wf::scene::node_t(false), geo(g), tex(t), tex_scale(s), horizontal(horiz)
    {}

    std::string stringify() const override
    {
        return "flip-lock-screenshot";
    }

    wf::geometry_t get_bounding_box() override
    {
        return geo;   // the plane only ever shrinks inward, never exceeds the output
    }

    void gen_render_instances(std::vector<wf::scene::render_instance_uptr>& instances,
        wf::scene::damage_callback push_damage, wf::output_t *shown_on) override;
};

class flip_screenshot_render_instance_t :
    public wf::scene::simple_render_instance_t<flip_screenshot_node_t>
{
  public:
    using simple_render_instance_t::simple_render_instance_t;

    void render(const wf::scene::render_instruction_t& data) override
    {
        if (!self->tex)
        {
            return;
        }

        const auto   g = self->geo;
        const float  s = self->tex_scale;
        // cos foreshorten: full at progress 0, zero at progress 1 (edge-on).
        const double fs = std::cos(self->progress * M_PI * 0.5);

        wf::texture_t tex;
        tex.texture    = self->tex;
        tex.source_box = wlr_fbox{0.0, 0.0, g.width * (double) s, g.height * (double) s};

        if (self->horizontal)
        {
            // Y axis: shrink width, keep height, anchor at the horizontal centre.
            const double w = g.width * fs;
            if (w <= 0.5)
            {
                return;
            }
            const double cx = g.x + g.width * 0.5;
            wlr_fbox dst{cx - w * 0.5, (double) g.y, w, (double) g.height};
            data.pass->add_texture(tex, data.target, dst, data.damage);
        } else
        {
            // X axis: shrink height, keep width, anchor at the vertical centre.
            const double h = g.height * fs;
            if (h <= 0.5)
            {
                return;
            }
            const double cy = g.y + g.height * 0.5;
            wlr_fbox dst{(double) g.x, cy - h * 0.5, (double) g.width, h};
            data.pass->add_texture(tex, data.target, dst, data.damage);
        }
    }
};

inline void flip_screenshot_node_t::gen_render_instances(
    std::vector<wf::scene::render_instance_uptr>& instances,
    wf::scene::damage_callback push_damage, wf::output_t *shown_on)
{
    instances.push_back(std::make_unique<flip_screenshot_render_instance_t>(
        this, push_damage, shown_on));
}

// ---------------------------------------------------------------------------
// Per-output plugin instance.
// ---------------------------------------------------------------------------
class wayfire_flip_lock_t : public wf::per_output_plugin_instance_t
{
    wf::option_wrapper_t<wf::activatorbinding_t> toggle_opt{"wayfire-flip-lock/toggle"};
    wf::option_wrapper_t<wf::color_t> backdrop_opt{"wayfire-flip-lock/backdrop_color"};
    wf::option_wrapper_t<int> safety_opt{"wayfire-flip-lock/safety_timeout"};
    wf::option_wrapper_t<wf::animation_description_t> duration_opt{"wayfire-flip-lock/duration"};
    wf::option_wrapper_t<std::string> axis_opt{"wayfire-flip-lock/axis"};

    wf::animation::simple_animation_t anim{duration_opt};

    enum class state_t { IDLE, FLIPPING, COLLAPSED, RESTORING };
    state_t state = state_t::IDLE;

    // Per-run axis, taken from the IPC payload when present, else the option.
    bool run_horizontal = true;

    wf::auxilliary_buffer_t screenshot_buf;
    std::shared_ptr<flip_screenshot_node_t> screenshot_node;
    std::shared_ptr<flip_backdrop_node_t>   backdrop;

    // Safety net: if the lockscreen daemon dies and never sends `stop`, restore
    // the desktop after a generous timeout rather than freezing forever.
    wf::wl_timer<false> safety_timer;

    // No grab (capabilities = 0): a real ext-session-lock surface takes the seat
    // immediately after, so a plugin grab would only fight it. During the brief
    // flip the live layers are disabled, so stray clicks hit nothing.
    wf::plugin_activation_data_t activation = {
        .name = "wayfire-flip-lock",
        .capabilities = 0,
        .cancel = [this] { hard_reset(); },
    };

    // Optional dev keybinding: toggle the flip by hand (IDLE -> flip, else ->
    // animated restore). Unset by default; the real driver is IPC.
    wf::activator_callback on_toggle = [this] (const wf::activator_data_t&)
    {
        if (state == state_t::IDLE)
        {
            return start_flip(axis_is_horizontal());
        }
        start_restore();
        return true;
    };

    wf::effect_hook_t on_frame = [this] ()
    {
        apply_progress((double) anim);

        if (!anim.running())
        {
            if (state == state_t::FLIPPING)
            {
                apply_progress(1.0);
                state = state_t::COLLAPSED;
                // Hold a static edge-on frame: stop pumping a whole-output
                // repaint every vsync (the OVERLAY nodes stay in the scene).
                output->render->rem_effect(&on_frame);
                output->render->damage_whole();
                arm_safety_timer();
            } else if (state == state_t::RESTORING)
            {
                apply_progress(0.0);
                hard_reset();
            }
        }
    };

  public:
    void init() override
    {
        flip_log("per-output init on output=%p", (void *) output);
        output->add_activator(toggle_opt, &on_toggle);
    }

    void fini() override
    {
        flip_log("per-output fini on output=%p state=%d", (void *) output, (int) state);
        output->rem_binding(&on_toggle);
        if (state != state_t::IDLE)
        {
            hard_reset();
        }
    }

    // Entry points for the plugin-wide IPC handlers. `horiz` is the resolved
    // axis: true = rotate about the Y axis (shrink width), false = X axis.
    bool ipc_start(bool horiz)
    {
        if (state == state_t::IDLE)
        {
            return start_flip(horiz);
        }
        return false;
    }

    // IPC stop is the lock-coordination path: by the time the lockscreen calls
    // it, its lock surface fully covers the screen, so an animated reverse would
    // be invisible churn. Restore instantly underneath.
    bool ipc_stop()
    {
        if (state != state_t::IDLE)
        {
            hard_reset();
            return true;
        }
        return false;
    }

    bool ipc_toggle(bool horiz)
    {
        if (state == state_t::IDLE)
        {
            return start_flip(horiz);
        }
        start_restore();
        return true;
    }

  private:
    bool axis_is_horizontal()
    {
        std::string a = axis_opt;
        return a != "x" && a != "X";   // default / "y" -> Y axis (horizontal foreshorten)
    }

    bool start_flip(bool horiz)
    {
        flip_log("start_flip: activating (horizontal=%d)", (int) horiz);
        if (!output->activate_plugin(&activation))
        {
            flip_log("start_flip: activate_plugin returned false");
            return false;
        }

        run_horizontal = horiz;

        // Output-relative geometry for the scene nodes (see converge-lock for the
        // double-offset rationale: nodes live under output->node_for_layer()).
        const auto rel = output->get_relative_geometry();

        // 1. Freeze the whole live screen (wallpaper + windows + panel).
        if (!capture_output())
        {
            flip_log("start_flip: capture failed");
            output->deactivate_plugin(&activation);
            return false;
        }

        // 2. Hide every live layer so the frozen capture is all that animates and
        //    the margins behind it are the (black) backdrop, not the live desktop.
        set_live_layers_hidden(true);

        // 3. Black backdrop first, then the foreshortening screenshot on top, both
        //    on OVERLAY. Start fully open (progress 0, covering the whole output).
        const float scale = output->handle ? output->handle->scale : 1.0f;
        backdrop = std::make_shared<flip_backdrop_node_t>(rel, (wf::color_t) backdrop_opt);
        wf::scene::add_front(output->node_for_layer(wf::scene::layer::OVERLAY), backdrop);

        screenshot_node = std::make_shared<flip_screenshot_node_t>(
            rel, screenshot_buf.get_texture(), scale, run_horizontal);
        wf::scene::add_front(output->node_for_layer(wf::scene::layer::OVERLAY), screenshot_node);

        flip_log("start_flip: rel=%dx%d scale=%.2f", rel.width, rel.height, (double) scale);

        output->render->add_effect(&on_frame, wf::OUTPUT_EFFECT_PRE);
        state = state_t::FLIPPING;
        anim.animate(0.0, 1.0);
        return true;
    }

    // Animated reverse (dev toggle / cancel binding only). Keyed off the current
    // transition value so a mid-flip reverse is smooth.
    void start_restore()
    {
        if ((state != state_t::FLIPPING) && (state != state_t::COLLAPSED))
        {
            return;
        }

        safety_timer.disconnect();
        if (state == state_t::COLLAPSED)
        {
            output->render->add_effect(&on_frame, wf::OUTPUT_EFFECT_PRE);
        }
        state = state_t::RESTORING;
        anim.animate((double) anim, 0.0);
    }

    void apply_progress(double p)
    {
        if (screenshot_node)
        {
            screenshot_node->progress = p;
        }
        output->render->damage_whole();
    }

    void arm_safety_timer()
    {
        const int ms = safety_opt;
        if (ms <= 0)
        {
            return;
        }
        safety_timer.set_timeout((uint32_t) ms, [this] ()
        {
            flip_log("safety timeout fired — restoring (no stop received)");
            hard_reset();
        });
    }

    // Hide / show every live layer (wallpaper, desktop grid, app windows, panel).
    // OVERLAY (our backdrop + screenshot) is left enabled.
    void set_live_layers_hidden(bool hidden)
    {
        for (auto layer : {wf::scene::layer::BACKGROUND, wf::scene::layer::BOTTOM,
                           wf::scene::layer::WORKSPACE, wf::scene::layer::TOP})
        {
            wf::scene::set_node_enabled(output->node_for_layer(layer), !hidden);
        }
    }

    // Render the current scene of this output into screenshot_buf with an opaque
    // black clear, so any transparent gaps in the capture read as black rather
    // than letting a re-enabled layer bleed through.
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
        safety_timer.disconnect();

        if (screenshot_node)
        {
            wf::scene::remove_child(screenshot_node);
            screenshot_node.reset();
        }
        if (backdrop)
        {
            wf::scene::remove_child(backdrop);
            backdrop.reset();
        }
        screenshot_buf.free();

        set_live_layers_hidden(false);

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
// shape to wayfire-converge-lock so lumen-lockscreen drives it over the same
// IPC framing. The optional "axis" field of the IPC `data` object ("x"|"y")
// overrides the per-plugin axis option for that run.
// ---------------------------------------------------------------------------
class wayfire_flip_lock_plugin_t :
    public wf::per_output_plugin_t<wayfire_flip_lock_t>
{
    wf::shared_data::ref_ptr_t<wf::ipc::method_repository_t> ipc_repo;
    wf::option_wrapper_t<std::string> axis_opt{"wayfire-flip-lock/axis"};

    wayfire_flip_lock_t *instance_for_active_output()
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

    // Resolve the axis for a run: an explicit "axis" in the IPC data wins, else
    // the plugin option. Returns true for Y axis (horizontal foreshorten).
    bool resolve_horizontal(const wf::json_t& data)
    {
        std::string a = axis_opt;
        if (data.has_member("axis") && data["axis"].is_string())
        {
            a = data["axis"].as_string();
        }
        return a != "x" && a != "X";
    }

    wf::ipc::method_callback on_start_ipc = [this] (const wf::json_t& data) -> wf::json_t
    {
        auto inst = instance_for_active_output();
        wf::json_t res;
        res["result"] = (inst != nullptr) && inst->ipc_start(resolve_horizontal(data)) ? "ok" : "noop";
        return res;
    };

    wf::ipc::method_callback on_stop_ipc = [this] (const wf::json_t&) -> wf::json_t
    {
        auto inst = instance_for_active_output();
        wf::json_t res;
        res["result"] = (inst != nullptr) && inst->ipc_stop() ? "ok" : "noop";
        return res;
    };

    wf::ipc::method_callback on_toggle_ipc = [this] (const wf::json_t& data) -> wf::json_t
    {
        auto inst = instance_for_active_output();
        wf::json_t res;
        res["result"] = (inst != nullptr) && inst->ipc_toggle(resolve_horizontal(data)) ? "ok" : "noop";
        return res;
    };

  public:
    void init() override
    {
        flip_log("plugin init: registering IPC methods");
        wf::per_output_plugin_t<wayfire_flip_lock_t>::init();
        ipc_repo->register_method("wayfire-flip-lock/start",  on_start_ipc);
        ipc_repo->register_method("wayfire-flip-lock/stop",   on_stop_ipc);
        ipc_repo->register_method("wayfire-flip-lock/toggle", on_toggle_ipc);
    }

    void fini() override
    {
        flip_log("plugin fini: unregistering IPC methods");
        ipc_repo->unregister_method("wayfire-flip-lock/start");
        ipc_repo->unregister_method("wayfire-flip-lock/stop");
        ipc_repo->unregister_method("wayfire-flip-lock/toggle");
        wf::per_output_plugin_t<wayfire_flip_lock_t>::fini();
    }
};

DECLARE_WAYFIRE_PLUGIN(wayfire_flip_lock_plugin_t)
