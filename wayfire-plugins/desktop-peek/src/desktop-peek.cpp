#include <wayfire/per-output-plugin.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/output.hpp>
#include <wayfire/workspace-set.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/view-transform.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/util/duration.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/geometry.hpp>
#include <wayfire/scene-operations.hpp>
#include <wayfire/scene.hpp>
#include "ipc_wrapper.hpp"
#include "log.hpp"
#include "transformed_views.hpp"

#include <array>
#include <utility>

#define peek_log(...) lumen::file_log("/tmp/wayfire-desktop-peek.log", __VA_ARGS__)

class wayfire_desktop_peek_t : public wf::per_output_plugin_instance_t
{
    wf::option_wrapper_t<wf::activatorbinding_t> toggle_opt{"wayfire-desktop-peek/toggle"};
    wf::option_wrapper_t<int> peek_px_opt{"wayfire-desktop-peek/peek_px"};
    wf::option_wrapper_t<wf::animation_description_t> duration_opt{"wayfire-desktop-peek/duration"};

    wf::animation::simple_animation_t anim{duration_opt};

    enum class state_t { IDLE, OUT, PEEKED, IN };
    state_t state = state_t::IDLE;

    lumen::transformed_views_t tracked_views{"wayfire-desktop-peek-slide"};

    // No input grab: while peeked the desktop must stay clickable.
    wf::plugin_activation_data_t activation = {
        .name = "wayfire-desktop-peek",
        .capabilities = 0,
        .cancel = [this] { hard_reset(); },
    };

    wf::activator_callback on_toggle = [this] (const wf::activator_data_t&)
    {
        return ipc_toggle();
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
                state = state_t::PEEKED;
                // Static while peeked: stop re-damaging every view each frame.
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
        peek_log("per-output init on output=%p", (void *) output);
        tracked_views.on_empty = [this]
        {
            if (state != state_t::IDLE)
            {
                hard_reset();
            }
        };
        output->add_activator(toggle_opt, &on_toggle);
    }

    void fini() override
    {
        peek_log("per-output fini on output=%p state=%d", (void *) output, (int) state);
        output->rem_binding(&on_toggle);
        if (state != state_t::IDLE)
        {
            hard_reset();
        }
    }

    // Public entry points for the plugin-wide IPC handlers.
    bool ipc_toggle()
    {
        peek_log("ipc_toggle on output=%p state=%d", (void *) output, (int) state);
        if (state == state_t::IDLE)
        {
            return start_peek();
        }
        if ((state == state_t::PEEKED) || (state == state_t::OUT))
        {
            start_restore();
            return true;
        }
        return false;
    }

    bool ipc_start()
    {
        peek_log("ipc_start on output=%p state=%d", (void *) output, (int) state);
        if (state == state_t::IDLE)
        {
            return start_peek();
        }
        return false;
    }

    bool ipc_stop()
    {
        peek_log("ipc_stop on output=%p state=%d", (void *) output, (int) state);
        if ((state == state_t::PEEKED) || (state == state_t::OUT))
        {
            start_restore();
            return true;
        }
        return false;
    }

  private:
    bool start_peek()
    {
        peek_log("start_peek: activating");
        if (!output->activate_plugin(&activation))
        {
            peek_log("start_peek: activate_plugin returned false");
            return false;
        }

        const auto geo = output->get_relative_geometry();
        const int W = geo.width, H = geo.height;
        const int peek = peek_px_opt;

        auto views = output->wset()->get_views(
            wf::WSET_MAPPED_ONLY | wf::WSET_CURRENT_WORKSPACE | wf::WSET_SORT_STACKING);

        // Round-robin corners TL, TR, BL, BR as {left, top}.
        constexpr std::array<std::pair<bool, bool>, 4> slots = {{
            {true,  true},
            {false, true},
            {true,  false},
            {false, false},
        }};
        size_t slot_idx = 0;

        for (auto view : views)
        {
            if (view->minimized)
            {
                continue;
            }

            auto wgeo = view->get_geometry();
            if ((wgeo.width <= 0) || (wgeo.height <= 0))
            {
                continue;
            }

            auto *t = tracked_views.add(view);
            if (!t)
            {
                continue;
            }

            const auto [left, top] = slots[slot_idx % slots.size()];
            ++slot_idx;

            const double target_x = left ? (peek - wgeo.width) : (W - peek);
            const double target_y = top  ? (peek - wgeo.height) : (H - peek);

            t->dx = target_x - wgeo.x;
            t->dy = target_y - wgeo.y;
        }

        peek_log("start_peek: %zu tracked views, output %dx%d, peek_px=%d",
            tracked_views.entries.size(), W, H, peek);

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
        if ((state != state_t::PEEKED) && (state != state_t::OUT))
        {
            return;
        }

        if (state == state_t::PEEKED)
        {
            // Hook was removed once the peek settled; nothing else drives frames.
            output->render->add_effect(&on_frame, wf::OUTPUT_EFFECT_PRE);
            output->render->schedule_redraw();
        }

        state = state_t::IN;
        anim.animate((double) anim, 0.0);
    }

    void apply_progress(double p)
    {
        tracked_views.update_all([p] (auto& t)
        {
            t.tr->translation_x = (float) (t.dx * p);
            t.tr->translation_y = (float) (t.dy * p);
        });
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

struct wayfire_desktop_peek_plugin_t : lumen::ipc_plugin_t<wayfire_desktop_peek_t>
{
    wayfire_desktop_peek_plugin_t() : ipc_plugin_t("wayfire-desktop-peek")
    {}
};

DECLARE_WAYFIRE_PLUGIN(wayfire_desktop_peek_plugin_t)
