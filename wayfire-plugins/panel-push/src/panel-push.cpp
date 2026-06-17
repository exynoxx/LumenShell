#include <wayfire/per-output-plugin.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/output.hpp>
#include <wayfire/core.hpp>
#include <wayfire/view.hpp>
#include <wayfire/view-helpers.hpp>
#include <wayfire/view-transform.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/config/types.hpp>
#include <wayfire/util/duration.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/scene.hpp>
#include <wayfire/scene-operations.hpp>
#include <wayfire/plugins/ipc/ipc-method-repository.hpp>
#include <wayfire/plugins/common/shared-core-data.hpp>
#include <wayfire/seat.hpp>

#include <memory>
#include <vector>
#include <algorithm>
#include <string>
#include <cstdio>
#include <cstdarg>
#include <ctime>

namespace
{
constexpr const char *TRANSFORMER_NAME = "wayfire-panel-push-slide";

// Tmp logging, mirroring the peek plugins' /tmp logs so a single tail -f can
// follow every reveal variant. Append-only; truncate before a session.
inline void push_log(const char *fmt, ...)
{
    FILE *fp = std::fopen("/tmp/wayfire-panel-push.log", "a");
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
// Per-output plugin instance.
//
// On push, every mapped view across BACKGROUND / BOTTOM / WORKSPACE / TOP
// (wallpaper, the lumen-desktop drawer, app windows, other layer-shell
// surfaces) — except the panel itself (exclude_app_id) — gets a
// view_2d_transformer_t whose translation_y animates uniformly to ±push_px.
// This slides the WHOLE scene away from the panel's edge to free a strip the
// (separately revealed) panel slides into. view_2d_transformer_t moves input
// together with rendering, so the pushed scene stays interactive; no grab.
// ---------------------------------------------------------------------------
class wayfire_panel_push_t : public wf::per_output_plugin_instance_t
{
    wf::option_wrapper_t<wf::activatorbinding_t> toggle_opt{"wayfire-panel-push/toggle"};
    wf::option_wrapper_t<wf::activatorbinding_t> dismiss_opt{"wayfire-panel-push/dismiss"};
    wf::option_wrapper_t<int> push_px_opt{"wayfire-panel-push/push_px"};
    wf::option_wrapper_t<std::string> direction_opt{"wayfire-panel-push/direction"};
    wf::option_wrapper_t<std::string> exclude_app_id_opt{"wayfire-panel-push/exclude_app_id"};
    wf::option_wrapper_t<wf::animation_description_t> duration_opt{"wayfire-panel-push/duration"};

    wf::animation::simple_animation_t anim{duration_opt};

    enum class state_t { IDLE, OUT, PUSHED, IN };
    state_t state = state_t::IDLE;

    // push distance (px) and sign (+1 = down, panel at top; -1 = up, bottom),
    // recomputed per push.
    int push_px = 60;
    int push_sign = +1;

    struct tracked_t
    {
        wayfire_view view;
        std::shared_ptr<wf::scene::view_2d_transformer_t> tr;
        wf::signal::connection_t<wf::view_unmapped_signal> on_unmap;
    };

    std::vector<std::unique_ptr<tracked_t>> tracked_views;

    // No CAPABILITY_GRAB_INPUT and no input grab: the pushed scene must stay
    // fully interactive (the user keeps using their shifted windows while the
    // panel is revealed). The transformer remaps input along with rendering.
    wf::plugin_activation_data_t activation = {
        .name = "wayfire-panel-push",
        .capabilities = 0,
        .cancel = [this] { hard_reset(); },
    };

    wf::activator_callback on_toggle = [this] (const wf::activator_data_t&)
    {
        if (state == state_t::IDLE)
        {
            return start_push();
        }
        if ((state == state_t::PUSHED) || (state == state_t::OUT))
        {
            start_restore();
            return true;
        }
        return false;
    };

    // Restore-only; a no-op from IDLE so it doesn't steal Escape from other
    // consumers when nothing is pushed.
    wf::activator_callback on_dismiss = [this] (const wf::activator_data_t&)
    {
        if ((state == state_t::PUSHED) || (state == state_t::OUT))
        {
            start_restore();
            return true;
        }
        return false;
    };

    // A view that maps while the scene is (or is becoming) pushed — e.g. a new
    // window or layer-shell surface — must appear already shifted, in line with
    // everything else, instead of popping in at the un-pushed origin.
    wf::signal::connection_t<wf::view_mapped_signal> on_view_mapped =
        [this] (wf::view_mapped_signal *ev)
    {
        if ((state != state_t::OUT) && (state != state_t::PUSHED))
        {
            return;
        }
        if (!ev->view)
        {
            return;
        }
        auto vo = ev->view->get_output();
        if (vo && (vo != output))
        {
            return;
        }
        track_view(ev->view);
    };

    wf::effect_hook_t on_frame = [this] ()
    {
        const double v = (double) anim;
        apply_progress(v);

        if (!anim.running())
        {
            if (state == state_t::OUT)
            {
                apply_progress(1.0);
                state = state_t::PUSHED;
            } else if (state == state_t::IN)
            {
                apply_progress(0.0);
                hard_reset();
            }
        }
    };

  public:
    void init() override
    {
        push_log("per-output init on output=%p", (void *) output);
        output->add_activator(toggle_opt, &on_toggle);
        output->add_activator(dismiss_opt, &on_dismiss);
        output->connect(&on_view_mapped);
    }

    void fini() override
    {
        push_log("per-output fini on output=%p state=%d", (void *) output, (int) state);
        output->rem_binding(&on_toggle);
        output->rem_binding(&on_dismiss);
        on_view_mapped.disconnect();
        if (state != state_t::IDLE)
        {
            hard_reset();
        }
    }

    // Public entry points for the plugin-wide IPC handlers.
    bool ipc_toggle()
    {
        push_log("ipc_toggle on output=%p state=%d", (void *) output, (int) state);
        if (state == state_t::IDLE)
        {
            return start_push();
        }
        if ((state == state_t::PUSHED) || (state == state_t::OUT))
        {
            start_restore();
            return true;
        }
        return false;
    }

    bool ipc_start()
    {
        push_log("ipc_start on output=%p state=%d", (void *) output, (int) state);
        if (state == state_t::IDLE)
        {
            return start_push();
        }
        return false;
    }

    bool ipc_stop()
    {
        push_log("ipc_stop on output=%p state=%d", (void *) output, (int) state);
        if ((state == state_t::PUSHED) || (state == state_t::OUT))
        {
            start_restore();
            return true;
        }
        return false;
    }

  private:
    bool is_excluded(wayfire_view view) const
    {
        return view && (view->get_app_id() == (std::string) exclude_app_id_opt);
    }

    // Attach a slide transformer to a view and settle it to the current
    // animation value. Skips the panel, unmapped views, and views already
    // tracked.
    void track_view(wayfire_view view)
    {
        if (!view || !view->is_mapped() || is_excluded(view))
        {
            return;
        }
        for (auto& t : tracked_views)
        {
            if (t->view == view)
            {
                return;
            }
        }

        auto t = std::make_unique<tracked_t>();
        t->view = view;
        t->tr = std::make_shared<wf::scene::view_2d_transformer_t>(view);
        view->get_transformed_node()->add_transformer(
            t->tr, wf::TRANSFORMER_2D, TRANSFORMER_NAME);

        wayfire_view captured = view;
        t->on_unmap = [this, captured] (wf::view_unmapped_signal*)
        {
            drop_view(captured);
        };
        view->connect(&t->on_unmap);

        set_view_translation(*t, (double) anim);
        tracked_views.push_back(std::move(t));
    }

    bool start_push()
    {
        push_log("start_push: activating");
        if (!output->activate_plugin(&activation))
        {
            push_log("start_push: activate_plugin returned false");
            return false;
        }

        tracked_views.clear();
        push_px = std::clamp((int) push_px_opt, 0, 400);
        push_sign = ((std::string) direction_opt == "bottom") ? -1 : +1;

        for (auto& view : wf::collect_views_from_output(output, {
            wf::scene::layer::BACKGROUND,
            wf::scene::layer::BOTTOM,
            wf::scene::layer::WORKSPACE,
            wf::scene::layer::TOP,
        }))
        {
            track_view(view);
        }

        push_log("start_push: %zu tracked views, push_px=%d sign=%d",
            tracked_views.size(), push_px, push_sign);

        if (tracked_views.empty())
        {
            output->deactivate_plugin(&activation);
            return false;
        }

        output->render->add_effect(&on_frame, wf::OUTPUT_EFFECT_PRE);
        state = state_t::OUT;
        anim.animate(0.0, 1.0);
        return true;
    }

    void start_restore()
    {
        if ((state != state_t::PUSHED) && (state != state_t::OUT))
        {
            return;
        }

        state = state_t::IN;
        anim.animate((double) anim, 0.0);
    }

    void set_view_translation(tracked_t& t, double p)
    {
        if (!t.tr || !t.view)
        {
            return;
        }
        auto n = t.view->get_transformed_node();
        n->begin_transform_update();
        t.tr->translation_y = (float) (push_sign * push_px * p);
        n->end_transform_update();
    }

    void apply_progress(double p)
    {
        for (auto& t : tracked_views)
        {
            set_view_translation(*t, p);
        }

        // Drive the animation: keep the output repainting until the
        // simple_animation_t settles.
        output->render->damage_whole();
    }

    void drop_view(wayfire_view view)
    {
        auto it = std::find_if(tracked_views.begin(), tracked_views.end(),
            [&] (auto& t) { return t->view == view; });
        if (it == tracked_views.end())
        {
            return;
        }

        if ((*it)->tr && view)
        {
            view->get_transformed_node()->rem_transformer((*it)->tr);
        }

        tracked_views.erase(it);
    }

    void hard_reset()
    {
        for (auto& t : tracked_views)
        {
            if (t->tr && t->view)
            {
                t->view->get_transformed_node()->rem_transformer(t->tr);
            }
            t->on_unmap.disconnect();
        }
        tracked_views.clear();

        if (state != state_t::IDLE)
        {
            output->render->rem_effect(&on_frame);
            output->deactivate_plugin(&activation);
        }
        state = state_t::IDLE;
    }
};

// ---------------------------------------------------------------------------
// Plugin wrapper: per-output instances + plugin-wide IPC surface, same shape as
// the peek plugins so lumen-panel can drive it.
// ---------------------------------------------------------------------------
class wayfire_panel_push_plugin_t :
    public wf::per_output_plugin_t<wayfire_panel_push_t>
{
    wf::shared_data::ref_ptr_t<wf::ipc::method_repository_t> ipc_repo;

    wayfire_panel_push_t *instance_for_active_output()
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
        push_log("plugin init: registering IPC methods");
        wf::per_output_plugin_t<wayfire_panel_push_t>::init();
        ipc_repo->register_method("wayfire-panel-push/toggle", on_toggle_ipc);
        ipc_repo->register_method("wayfire-panel-push/start",  on_start_ipc);
        ipc_repo->register_method("wayfire-panel-push/stop",   on_stop_ipc);
    }

    void fini() override
    {
        push_log("plugin fini: unregistering IPC methods");
        ipc_repo->unregister_method("wayfire-panel-push/toggle");
        ipc_repo->unregister_method("wayfire-panel-push/start");
        ipc_repo->unregister_method("wayfire-panel-push/stop");
        wf::per_output_plugin_t<wayfire_panel_push_t>::fini();
    }
};

DECLARE_WAYFIRE_PLUGIN(wayfire_panel_push_plugin_t)
