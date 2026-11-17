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
#include "ipc_wrapper.hpp"
#include "log.hpp"
#include "transformed_views.hpp"

#include <string>

#define push_log(...) lumen::file_log("/tmp/wayfire-panel-push.log", __VA_ARGS__)

// Slides every view in BACKGROUND..TOP except the panel by ±push_px. The 2D
// transformer remaps input with rendering, so the pushed scene stays interactive.
class wayfire_panel_push_t : public wf::per_output_plugin_instance_t
{
    wf::option_wrapper_t<int> push_px_opt{"wayfire-panel-push/push_px"};
    wf::option_wrapper_t<std::string> direction_opt{"wayfire-panel-push/direction"};
    wf::option_wrapper_t<std::string> exclude_app_id_opt{"wayfire-panel-push/exclude_app_id"};
    wf::option_wrapper_t<wf::animation_description_t> duration_opt{"wayfire-panel-push/duration"};

    wf::animation::simple_animation_t anim{duration_opt};

    enum class state_t { IDLE, OUT, PUSHED, IN };
    state_t state = state_t::IDLE;

    // push distance (px) and sign (+1 = down, panel at top; -1 = up, bottom),
    // recomputed per push.
    int push_px = 0;
    int push_sign = +1;

    lumen::transformed_views_t tracked_views{"wayfire-panel-push-slide"};

    // No input grab: the pushed scene must stay usable while the panel is shown.
    wf::plugin_activation_data_t activation = {
        .name = "wayfire-panel-push",
        .capabilities = 0,
        .cancel = [this] { hard_reset(); },
    };

    // A view mapping mid-push must appear already shifted, not at the origin.
    wf::signal::connection_t<wf::view_mapped_signal> on_view_mapped =
        [this] (wf::view_mapped_signal *ev)
    {
        if ((state != state_t::OUT) && (state != state_t::PUSHED))
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
                // Static once settled: stop the per-frame damage.
                output->render->rem_effect(&on_frame);
            } else if (state == state_t::IN)
            {
                hard_reset(); // removes the transformers outright
            }
        }
    };

  public:
    void init() override
    {
        push_log("per-output init on output=%p", (void *) output);
        output->connect(&on_view_mapped);
    }

    void fini() override
    {
        push_log("per-output fini on output=%p state=%d", (void *) output, (int) state);
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

    void track_view(wayfire_view view)
    {
        if (!view || !view->is_mapped() || is_excluded(view))
        {
            return;
        }
        if (auto *t = tracked_views.add(view))
        {
            auto n = view->get_transformed_node();
            n->begin_transform_update();
            t->tr->translation_y = offset((double) anim);
            n->end_transform_update();
        }
    }

    bool start_push()
    {
        push_log("start_push: activating");
        if (!output->activate_plugin(&activation))
        {
            push_log("start_push: activate_plugin returned false");
            return false;
        }

        push_px = push_px_opt;
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
            tracked_views.entries.size(), push_px, push_sign);

        if (tracked_views.entries.empty())
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

        if (state == state_t::PUSHED)
        {
            // Hook was removed once settled; nothing else drives frames.
            output->render->add_effect(&on_frame, wf::OUTPUT_EFFECT_PRE);
            output->render->schedule_redraw();
        }

        state = state_t::IN;
        anim.animate((double) anim, 0.0);
    }

    float offset(double p) const
    {
        return (float) (push_sign * push_px * p);
    }

    // end_transform_update() damages each moved view; no damage_whole() needed.
    void apply_progress(double p)
    {
        tracked_views.update_all([&] (auto& t) { t.tr->translation_y = offset(p); });
    }

    void hard_reset()
    {
        tracked_views.clear();

        if (state != state_t::IDLE)
        {
            output->render->rem_effect(&on_frame);
            output->deactivate_plugin(&activation);
        }
        state = state_t::IDLE;
    }
};

struct wayfire_panel_push_plugin_t : lumen::ipc_plugin_t<wayfire_panel_push_t>
{
    wayfire_panel_push_plugin_t() : ipc_plugin_t("wayfire-panel-push")
    {}
};

DECLARE_WAYFIRE_PLUGIN(wayfire_panel_push_plugin_t)
