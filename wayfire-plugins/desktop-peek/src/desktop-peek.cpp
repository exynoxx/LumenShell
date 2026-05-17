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
#include <wayfire/plugins/ipc/ipc-method-repository.hpp>
#include <wayfire/plugins/common/shared-core-data.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/debug.hpp>

#include <wayland-server-protocol.h>
#include <wlr/types/wlr_pointer.h>

#include <memory>
#include <vector>
#include <algorithm>
#include <array>
#include <utility>
#include <cstdio>
#include <cstdarg>
#include <ctime>

namespace
{
constexpr const char *TRANSFORMER_NAME = "wayfire-desktop-peek-slide";

// Tmp logging — writes to /tmp/wayfire-desktop-peek.log so we can correlate
// with the Vala side's /tmp/lumen-desktop-peek.log. Both append; truncate
// manually before a test session.
inline void peek_log(const char *fmt, ...)
{
    FILE *fp = std::fopen("/tmp/wayfire-desktop-peek.log", "a");
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

class wayfire_desktop_peek_t :
    public wf::per_output_plugin_instance_t,
    public wf::pointer_interaction_t
{
    wf::option_wrapper_t<wf::activatorbinding_t> toggle_opt{"wayfire-desktop-peek/toggle"};
    wf::option_wrapper_t<wf::activatorbinding_t> dismiss_opt{"wayfire-desktop-peek/dismiss"};
    wf::option_wrapper_t<int> peek_px_opt{"wayfire-desktop-peek/peek_px"};
    wf::option_wrapper_t<wf::animation_description_t> duration_opt{"wayfire-desktop-peek/duration"};

    wf::animation::simple_animation_t anim{duration_opt};

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

    // No CAPABILITY_GRAB_INPUT and no input grab: while peeked, the
    // user must still be able to click lumen-desktop tiles, dismiss via the
    // keybinding, or click empty wallpaper area to toggle the peek off again
    // (which goes through the IPC path).
    wf::plugin_activation_data_t activation = {
        .name = "wayfire-desktop-peek",
        .capabilities = 0,
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

    // dismiss is restore-only; firing it from IDLE is a no-op so it doesn't
    // step on Escape's other consumers (search bar, expo, etc.) when nothing
    // is peeked. Returning false in that case lets the keypress propagate.
    wf::activator_callback on_dismiss = [this] (const wf::activator_data_t&)
    {
        peek_log("on_dismiss: state=%d", (int) state);
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
        peek_log("per-output init on output=%p", (void *) output);
        output->add_activator(toggle_opt, &on_toggle);
        output->add_activator(dismiss_opt, &on_dismiss);
    }

    void fini() override
    {
        peek_log("per-output fini on output=%p state=%d", (void *) output, (int) state);
        output->rem_binding(&on_toggle);
        output->rem_binding(&on_dismiss);
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

    // pointer_interaction_t base requires the override, but with no input
    // grab installed it is never invoked. Kept as a no-op so we still
    // satisfy the interface contract.
    void handle_pointer_button(const wlr_pointer_button_event& event) override
    {
        (void) event;
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

        peek_log("start_peek: %zu tracked views, output %dx%d, peek_px=%d",
            tracked_views.size(), W, H, peek);

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
            output->deactivate_plugin(&activation);
        }
        state = state_t::IDLE;
    }
};

class wayfire_desktop_peek_plugin_t :
    public wf::per_output_plugin_t<wayfire_desktop_peek_t>
{
    wf::shared_data::ref_ptr_t<wf::ipc::method_repository_t> ipc_repo;

    wayfire_desktop_peek_t *instance_for_active_output()
    {
        auto seat = wf::get_core().seat.get();
        wf::output_t *active = seat ? seat->get_active_output() : nullptr;
        peek_log("instance_for_active_output: active=%p", (void *) active);

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
            peek_log("falling back to first tracked output instance");
            return this->output_instance.begin()->second.get();
        }

        return nullptr;
    }

    wf::ipc::method_callback on_toggle_ipc = [this] (const wf::json_t&) -> wf::json_t
    {
        peek_log("IPC: wayfire-desktop-peek/toggle invoked");
        auto inst = instance_for_active_output();
        wf::json_t res;
        res["result"] = (inst != nullptr) && inst->ipc_toggle() ? "ok" : "noop";
        return res;
    };

    wf::ipc::method_callback on_start_ipc = [this] (const wf::json_t&) -> wf::json_t
    {
        peek_log("IPC: wayfire-desktop-peek/start invoked");
        auto inst = instance_for_active_output();
        wf::json_t res;
        res["result"] = (inst != nullptr) && inst->ipc_start() ? "ok" : "noop";
        return res;
    };

    wf::ipc::method_callback on_stop_ipc = [this] (const wf::json_t&) -> wf::json_t
    {
        peek_log("IPC: wayfire-desktop-peek/stop invoked");
        auto inst = instance_for_active_output();
        wf::json_t res;
        res["result"] = (inst != nullptr) && inst->ipc_stop() ? "ok" : "noop";
        return res;
    };

  public:
    void init() override
    {
        peek_log("plugin init: registering IPC methods");
        wf::per_output_plugin_t<wayfire_desktop_peek_t>::init();
        ipc_repo->register_method("wayfire-desktop-peek/toggle", on_toggle_ipc);
        ipc_repo->register_method("wayfire-desktop-peek/start",  on_start_ipc);
        ipc_repo->register_method("wayfire-desktop-peek/stop",   on_stop_ipc);
    }

    void fini() override
    {
        peek_log("plugin fini: unregistering IPC methods");
        ipc_repo->unregister_method("wayfire-desktop-peek/toggle");
        ipc_repo->unregister_method("wayfire-desktop-peek/start");
        ipc_repo->unregister_method("wayfire-desktop-peek/stop");
        wf::per_output_plugin_t<wayfire_desktop_peek_t>::fini();
    }
};

DECLARE_WAYFIRE_PLUGIN(wayfire_desktop_peek_plugin_t)
