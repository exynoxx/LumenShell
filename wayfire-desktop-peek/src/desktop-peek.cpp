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
#include <wayfire/scene-input.hpp>
#include <wayfire/scene.hpp>
#include <wayfire/plugins/common/input-grab.hpp>

#include <wayland-server-protocol.h>
#include <wlr/types/wlr_pointer.h>

#include <memory>
#include <vector>
#include <algorithm>
#include <array>
#include <utility>

namespace
{
constexpr const char *TRANSFORMER_NAME = "wayfire-desktop-peek-slide";
}

class wayfire_desktop_peek_t :
    public wf::per_output_plugin_instance_t,
    public wf::pointer_interaction_t
{
    wf::option_wrapper_t<wf::activatorbinding_t> toggle_opt{"wayfire-desktop-peek/toggle"};
    wf::option_wrapper_t<int> peek_px_opt{"wayfire-desktop-peek/peek_px"};
    wf::option_wrapper_t<wf::animation_description_t> duration_opt{"wayfire-desktop-peek/duration"};

    wf::animation::simple_animation_t anim{duration_opt};
    std::unique_ptr<wf::input_grab_t> grab;

    enum class state_t { IDLE, OUT, PEEKED, IN };
    state_t state = state_t::IDLE;

    struct tracked_t
    {
        wayfire_toplevel_view view;
        std::shared_ptr<wf::scene::view_2d_transformer_t> tr;
        double dx = 0, dy = 0;
        wf::signal::connection_t<wf::view_unmapped_signal> on_unmap;
    };

    std::vector<std::unique_ptr<tracked_t>> tracked_views;

    wf::plugin_activation_data_t activation = {
        .name = "wayfire-desktop-peek",
        .capabilities = wf::CAPABILITY_GRAB_INPUT,
        .cancel = [this] { hard_reset(); },
    };

    wf::activator_callback on_toggle = [this] (const wf::activator_data_t&)
    {
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
        grab = std::make_unique<wf::input_grab_t>(
            "wayfire-desktop-peek", output, nullptr, this, nullptr);
        output->add_activator(toggle_opt, &on_toggle);
    }

    void fini() override
    {
        output->rem_binding(&on_toggle);
        if (state != state_t::IDLE)
        {
            hard_reset();
        }
        grab.reset();
    }

    void handle_pointer_button(const wlr_pointer_button_event& event) override
    {
        if (event.state != WL_POINTER_BUTTON_STATE_PRESSED)
        {
            return;
        }

        if ((state == state_t::PEEKED) || (state == state_t::OUT))
        {
            start_restore();
        }
    }

  private:
    bool start_peek()
    {
        if (!output->activate_plugin(&activation))
        {
            return false;
        }

        tracked_views.clear();
        const auto geo = output->get_relative_geometry();
        const int W = geo.width, H = geo.height;
        const int peek = std::clamp((int) peek_px_opt, 0, 400);

        auto views = output->wset()->get_views(
            wf::WSET_MAPPED_ONLY | wf::WSET_CURRENT_WORKSPACE | wf::WSET_SORT_STACKING);

        // Corner order for round-robin assignment: TL, TR, BL, BR.
        // {left, top} flags per slot.
        constexpr std::array<std::pair<bool, bool>, 4> slots = {{
            {true,  true},   // top-left
            {false, true},   // top-right
            {true,  false},  // bottom-left
            {false, false},  // bottom-right
        }};
        size_t slot_idx = 0;

        for (auto view : views)
        {
            if (!view->is_mapped() || view->minimized)
            {
                continue;
            }

            auto wgeo = view->get_geometry();
            if ((wgeo.width <= 0) || (wgeo.height <= 0))
            {
                continue;
            }

            const auto [left, top] = slots[slot_idx % slots.size()];
            ++slot_idx;

            const double target_x = left ? (peek - wgeo.width) : (W - peek);
            const double target_y = top  ? (peek - wgeo.height) : (H - peek);

            auto t = std::make_unique<tracked_t>();
            t->view = view;
            t->dx = target_x - wgeo.x;
            t->dy = target_y - wgeo.y;
            t->tr = std::make_shared<wf::scene::view_2d_transformer_t>(view);

            auto tnode = view->get_transformed_node();
            tnode->add_transformer(t->tr, wf::TRANSFORMER_2D, TRANSFORMER_NAME);

            wayfire_toplevel_view captured = view;
            t->on_unmap = [this, captured] (wf::view_unmapped_signal*)
            {
                drop_view(captured);
            };
            view->connect(&t->on_unmap);

            tracked_views.push_back(std::move(t));
        }

        if (tracked_views.empty())
        {
            output->deactivate_plugin(&activation);
            return false;
        }

        output->render->add_effect(&on_frame, wf::OUTPUT_EFFECT_PRE);
        grab->grab_input(wf::scene::layer::TOP);
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

        state = state_t::IN;
        anim.animate((double) anim, 0.0);
    }

    void apply_progress(double p)
    {
        for (auto& t : tracked_views)
        {
            if (!t->tr)
            {
                continue;
            }

            auto tnode = t->view->get_transformed_node();
            tnode->begin_transform_update();
            t->tr->translation_x = (float) (t->dx * p);
            t->tr->translation_y = (float) (t->dy * p);
            tnode->end_transform_update();
        }
    }

    void drop_view(wayfire_toplevel_view view)
    {
        auto it = std::find_if(tracked_views.begin(), tracked_views.end(),
            [&] (auto& t) { return t->view == view; });
        if (it == tracked_views.end())
        {
            return;
        }

        if ((*it)->tr && view)
        {
            auto tnode = view->get_transformed_node();
            tnode->rem_transformer((*it)->tr);
        }

        tracked_views.erase(it);

        if (tracked_views.empty() && (state != state_t::IDLE))
        {
            hard_reset();
        }
    }

    void hard_reset()
    {
        for (auto& t : tracked_views)
        {
            if (t->tr && t->view)
            {
                auto tnode = t->view->get_transformed_node();
                tnode->rem_transformer(t->tr);
            }
            t->on_unmap.disconnect();
        }
        tracked_views.clear();

        if (state != state_t::IDLE)
        {
            output->render->rem_effect(&on_frame);
            if (grab && grab->is_grabbed())
            {
                grab->ungrab_input();
            }
            output->deactivate_plugin(&activation);
        }
        state = state_t::IDLE;
    }
};

class wayfire_desktop_peek_plugin_t :
    public wf::per_output_plugin_t<wayfire_desktop_peek_t>
{};

DECLARE_WAYFIRE_PLUGIN(wayfire_desktop_peek_plugin_t)
