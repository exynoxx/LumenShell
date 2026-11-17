#include <wayfire/per-output-plugin.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/output.hpp>
#include <wayfire/view.hpp>
#include <wayfire/view-transform.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/util/duration.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/scene.hpp>
#include <wayfire/scene-operations.hpp>
#include <wayfire/core.hpp>

#include <wayland-server-core.h>

#include "transformed_views.hpp"

class wayfire_startup_zoom_t : public wf::per_output_plugin_instance_t
{
    wf::option_wrapper_t<wf::animation_description_t> duration_opt{"wayfire-startup-zoom/duration"};
    wf::option_wrapper_t<double> initial_scale_opt{"wayfire-startup-zoom/initial_scale"};
    wf::option_wrapper_t<int> grace_ms_opt{"wayfire-startup-zoom/grace_ms"};

    wf::animation::simple_animation_t anim{duration_opt};

    enum class state_t { PENDING, RUNNING, DONE };
    state_t state = state_t::PENDING;

    lumen::transformed_views_t tracked{"wayfire-startup-zoom-tr"};

    // Gives up if no view maps within grace_ms, so we never sit armed forever.
    wl_event_source *grace_timer = nullptr;

    wf::signal::connection_t<wf::view_mapped_signal> on_view_mapped =
        [this] (wf::view_mapped_signal *ev)
    {
        // finish() disconnects this handler, so state is never DONE here.
        if (ev->view->get_output() != output)
        {
            return;
        }

        track_view(ev->view);
        ensure_running();
    };

    wf::effect_hook_t on_frame = [this] ()
    {
        const double p = (double) anim;
        apply_progress(p);

        if (!anim.running())
        {
            apply_progress(1.0);
            finish();
        }
    };

    static int grace_timer_cb(void *data)
    {
        auto *self = static_cast<wayfire_startup_zoom_t *>(data);
        if (self->state == state_t::PENDING)
        {
            self->finish();
        }
        return 0;
    }

  public:
    void init() override
    {
        wf::get_core().connect(&on_view_mapped);

        auto loop = wl_display_get_event_loop(wf::get_core().display);
        grace_timer = wl_event_loop_add_timer(loop, &grace_timer_cb, this);
        wl_event_source_timer_update(grace_timer, grace_ms_opt);
    }

    void fini() override
    {
        finish();
    }

  private:
    void track_view(wayfire_view view)
    {
        if (!tracked.add(view))
        {
            return;
        }

        // Apply the in-flight progress immediately so a late-mapping view
        // doesn't pop in at full size mid-animation.
        apply_progress(state == state_t::RUNNING ? (double) anim : 0.0);
    }

    void ensure_running()
    {
        if (state != state_t::PENDING)
        {
            return;
        }

        state = state_t::RUNNING;
        anim.animate(0.0, 1.0);
        output->render->add_effect(&on_frame, wf::OUTPUT_EFFECT_PRE);
    }

    void apply_progress(double p)
    {
        const double s0 = initial_scale_opt;
        const double s  = s0 + (1.0 - s0) * p;

        const auto geo = output->get_relative_geometry();
        const double ocx = geo.x + geo.width  / 2.0;
        const double ocy = geo.y + geo.height / 2.0;

        tracked.update_all([&] (auto& t)
        {
            // Use the surface-root node bounding box so this works for both
            // toplevel views and layer-shell surfaces (panel, desktop drawer).
            auto root = t.view->get_surface_root_node();
            if (!root)
            {
                return;
            }

            auto wgeo = root->get_bounding_box();
            if ((wgeo.width <= 0) || (wgeo.height <= 0))
            {
                return;
            }

            const double vcx = wgeo.x + wgeo.width  / 2.0;
            const double vcy = wgeo.y + wgeo.height / 2.0;

            // The transformer scales about the view centre; translate by (1 - s)
            // toward the output centre so the zoom is centred on the output.
            t.tr->scale_x       = (float) s;
            t.tr->scale_y       = (float) s;
            t.tr->translation_x = (float) ((1.0 - s) * (ocx - vcx));
            t.tr->translation_y = (float) ((1.0 - s) * (ocy - vcy));
        });
    }

    void finish()
    {
        if (state == state_t::DONE)
        {
            return;
        }

        if (state == state_t::RUNNING)
        {
            output->render->rem_effect(&on_frame);
        }

        tracked.clear();
        on_view_mapped.disconnect();

        if (grace_timer)
        {
            wl_event_source_remove(grace_timer);
            grace_timer = nullptr;
        }

        state = state_t::DONE;
    }
};

DECLARE_WAYFIRE_PLUGIN(wf::per_output_plugin_t<wayfire_startup_zoom_t>)
