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

#include <memory>
#include <vector>
#include <algorithm>

namespace
{
constexpr const char *TRANSFORMER_NAME = "wayfire-startup-zoom-tr";
}

class wayfire_startup_zoom_t : public wf::per_output_plugin_instance_t
{
    wf::option_wrapper_t<wf::animation_description_t> duration_opt{"wayfire-startup-zoom/duration"};
    wf::option_wrapper_t<double> initial_scale_opt{"wayfire-startup-zoom/initial_scale"};
    wf::option_wrapper_t<int> grace_ms_opt{"wayfire-startup-zoom/grace_ms"};

    wf::animation::simple_animation_t anim{duration_opt};

    enum class state_t { PENDING, RUNNING, DONE };
    state_t state = state_t::PENDING;

    struct tracked_t
    {
        wayfire_view view;
        std::shared_ptr<wf::scene::view_2d_transformer_t> tr;
        wf::signal::connection_t<wf::view_unmapped_signal> on_unmap;
    };

    std::vector<std::unique_ptr<tracked_t>> tracked;

    // Hard deadline so we don't sit RUNNING forever if no view ever maps.
    wl_event_source *grace_timer = nullptr;

    wf::signal::connection_t<wf::view_mapped_signal> on_view_mapped =
        [this] (wf::view_mapped_signal *ev)
    {
        if (state == state_t::DONE)
        {
            return;
        }

        if (!ev->view || (ev->view->get_output() != output))
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
        // If the grace window expires before anything mapped, give up quietly.
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
        wl_event_source_timer_update(grace_timer, std::max(100, (int) grace_ms_opt));
    }

    void fini() override
    {
        if (grace_timer)
        {
            wl_event_source_remove(grace_timer);
            grace_timer = nullptr;
        }

        if (state == state_t::RUNNING)
        {
            output->render->rem_effect(&on_frame);
        }

        clear_transformers();
        state = state_t::DONE;
    }

  private:
    void track_view(wayfire_view view)
    {
        if (std::any_of(tracked.begin(), tracked.end(),
            [&] (auto& t) { return t->view == view; }))
        {
            return;
        }

        auto t = std::make_unique<tracked_t>();
        t->view = view;
        t->tr   = std::make_shared<wf::scene::view_2d_transformer_t>(view);

        auto tnode = view->get_transformed_node();
        tnode->add_transformer(t->tr, wf::TRANSFORMER_2D, TRANSFORMER_NAME);

        wayfire_view captured = view;
        t->on_unmap = [this, captured] (wf::view_unmapped_signal*)
        {
            drop_view(captured);
        };
        view->connect(&t->on_unmap);

        tracked.push_back(std::move(t));

        // Apply the in-flight progress immediately so a late-mapping view
        // doesn't pop in at full size mid-animation.
        if (state == state_t::RUNNING)
        {
            apply_progress((double) anim);
        } else
        {
            apply_progress(0.0);
        }
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
        const double s0 = std::clamp((double) initial_scale_opt, 0.01, 1.0);
        const double s  = s0 + (1.0 - s0) * p;

        const auto geo = output->get_relative_geometry();
        const double ocx = geo.x + geo.width  / 2.0;
        const double ocy = geo.y + geo.height / 2.0;

        for (auto& t : tracked)
        {
            if (!t->tr || !t->view)
            {
                continue;
            }

            // Use the surface-root node bounding box so this works for both
            // toplevel views and layer-shell surfaces (panel, desktop drawer).
            auto root = t->view->get_surface_root_node();
            if (!root)
            {
                continue;
            }

            auto wgeo = root->get_bounding_box();
            if ((wgeo.width <= 0) || (wgeo.height <= 0))
            {
                continue;
            }

            const double vcx = wgeo.x + wgeo.width  / 2.0;
            const double vcy = wgeo.y + wgeo.height / 2.0;

            // view_2d_transformer scales about the view center, then translates
            // in screen pixels. To make the scale appear to happen about the
            // output center, push the view center toward the output center
            // by (1 - s).
            auto tnode = t->view->get_transformed_node();
            tnode->begin_transform_update();
            t->tr->scale_x       = (float) s;
            t->tr->scale_y       = (float) s;
            t->tr->translation_x = (float) ((1.0 - s) * (ocx - vcx));
            t->tr->translation_y = (float) ((1.0 - s) * (ocy - vcy));
            tnode->end_transform_update();
        }
    }

    void drop_view(wayfire_view view)
    {
        auto it = std::find_if(tracked.begin(), tracked.end(),
            [&] (auto& t) { return t->view == view; });
        if (it == tracked.end())
        {
            return;
        }

        if ((*it)->tr && view)
        {
            auto tnode = view->get_transformed_node();
            tnode->rem_transformer((*it)->tr);
        }
        (*it)->on_unmap.disconnect();
        tracked.erase(it);
    }

    void clear_transformers()
    {
        for (auto& t : tracked)
        {
            if (t->tr && t->view)
            {
                auto tnode = t->view->get_transformed_node();
                tnode->rem_transformer(t->tr);
            }
            t->on_unmap.disconnect();
        }
        tracked.clear();
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

        clear_transformers();
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
