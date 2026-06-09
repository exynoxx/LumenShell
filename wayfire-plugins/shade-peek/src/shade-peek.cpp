#include <wayfire/per-output-plugin.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/output.hpp>
#include <wayfire/core.hpp>
#include <wayfire/view.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/view-helpers.hpp>
#include <wayfire/view-transform.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/render.hpp>
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
constexpr const char *SCREENSHOT_NODE_NAME = "wayfire-shade-peek-screenshot";
constexpr const char *DESKTOP_TRANSFORMER_NAME = "wayfire-shade-peek-slide";

// Tmp logging, mirroring the curtain-peek/desktop-peek plugins' /tmp logs so a
// single tail -f can follow every reveal variant. Append-only; truncate before
// a session.
inline void shade_log(const char *fmt, ...)
{
    FILE *fp = std::fopen("/tmp/wayfire-shade-peek.log", "a");
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
// Shade screenshot: a full-output node, sitting on the OVERLAY layer (above
// everything), that draws a captured snapshot of the foreground (app windows +
// panel, the wallpaper excluded) translated vertically. As the shade opens the
// snapshot slides off one screen edge while the live desktop grid slides in
// from the opposite edge; the live wallpaper stays put behind them.
// ---------------------------------------------------------------------------
class shade_screenshot_node_t : public wf::scene::node_t
{
  public:
    wf::geometry_t geo;            // full output, output-relative {0,0,W,H}
    wlr_texture   *tex = nullptr;  // the captured snapshot (owned by the plugin)
    float translate_y = 0.0f;      // vertical translation (+ down, - up)

    shade_screenshot_node_t(wf::geometry_t g, wlr_texture *t) :
        wf::scene::node_t(false), geo(g), tex(t)
    {}

    std::string stringify() const override
    {
        return "shade-peek-screenshot";
    }

    // The snapshot travels a full output height past either the top or the
    // bottom edge, so the swept band is up to one output above and one below.
    wf::geometry_t get_bounding_box() override
    {
        return {geo.x, geo.y - geo.height, geo.width, geo.height * 3};
    }

    void gen_render_instances(std::vector<wf::scene::render_instance_uptr>& instances,
        wf::scene::damage_callback push_damage, wf::output_t *shown_on) override;
};

class shade_screenshot_render_instance_t :
    public wf::scene::simple_render_instance_t<shade_screenshot_node_t>
{
  public:
    using simple_render_instance_t::simple_render_instance_t;

    void render(const wf::scene::render_instruction_t& data) override
    {
        if (!self->tex)
        {
            return;
        }

        wf::texture_t tex;
        tex.texture = self->tex;

        const auto g   = self->geo;
        const int  dy  = (int) std::lround(self->translate_y);

        wf::geometry_t geo  = {g.x, g.y + dy, g.width, g.height};
        wf::geometry_t clip = {g.x, g.y + dy, g.width, g.height};
        data.pass->add_texture(tex, data.target, geo, data.damage & clip);
    }
};

inline void shade_screenshot_node_t::gen_render_instances(
    std::vector<wf::scene::render_instance_uptr>& instances,
    wf::scene::damage_callback push_damage, wf::output_t *shown_on)
{
    instances.push_back(std::make_unique<shade_screenshot_render_instance_t>(
        this, push_damage, shown_on));
}

// ---------------------------------------------------------------------------
// Per-output plugin instance.
// ---------------------------------------------------------------------------
class wayfire_shade_peek_t : public wf::per_output_plugin_instance_t
{
    wf::option_wrapper_t<wf::activatorbinding_t> toggle_opt{"wayfire-shade-peek/toggle"};
    wf::option_wrapper_t<wf::activatorbinding_t> dismiss_opt{"wayfire-shade-peek/dismiss"};
    wf::option_wrapper_t<std::string> desktop_app_id_opt{"wayfire-shade-peek/desktop_app_id"};
    wf::option_wrapper_t<std::string> direction_opt{"wayfire-shade-peek/direction"};
    wf::option_wrapper_t<wf::animation_description_t> duration_opt{"wayfire-shade-peek/duration"};

    wf::animation::simple_animation_t anim{duration_opt};

    enum class state_t { IDLE, OPENING, OPEN, CLOSING };
    state_t state = state_t::IDLE;

    // The frozen snapshot of the foreground and the node that slides it.
    wf::auxilliary_buffer_t screenshot_buf;
    std::shared_ptr<shade_screenshot_node_t> screenshot_node;

    // Output height and slide sign, recomputed per open. slide_sign = +1 when
    // the grid enters from the top (foreground exits off the bottom), -1 when
    // it enters from the bottom (foreground exits off the top).
    int H = 0;
    int slide_sign = +1;

    // The desktop grid view (app-id == desktop_app_id). Kept hidden while the
    // shade is closed and revealed only while it is open; cached so we can
    // toggle it even after we have disabled (and thus hidden) its node.
    wayfire_view desktop_view;

    // Transformer that slides the live grid in from the offscreen edge.
    std::shared_ptr<wf::scene::view_2d_transformer_t> desktop_tr;

    // No grab (capabilities = 0): while open, the revealed desktop grid must
    // stay clickable, same rationale as wayfire-curtain-peek.
    wf::plugin_activation_data_t activation = {
        .name = "wayfire-shade-peek",
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

    // Keep the desktop grid hidden until a shade peek reveals it. Catch it as
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
            // The grid is going away; drop our transformer reference so we do
            // not touch a stale node.
            desktop_tr.reset();
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
        shade_log("per-output init on output=%p", (void *) output);
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
        shade_log("per-output fini on output=%p state=%d", (void *) output, (int) state);
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
        shade_log("start_open: activating");
        if (!output->activate_plugin(&activation))
        {
            shade_log("start_open: activate_plugin returned false");
            return false;
        }

        const auto rel = output->get_relative_geometry();
        H = rel.height;
        slide_sign = ((std::string) direction_opt == "bottom") ? -1 : +1;

        // 1. Freeze the foreground as it is right now, with the wallpaper
        //    excluded: disable the BACKGROUND layer for the capture so the
        //    snapshot is purely app windows + panel over a transparent fill.
        //    The desktop grid is still hidden here, so it is not captured.
        wf::scene::set_node_enabled(
            output->node_for_layer(wf::scene::layer::BACKGROUND), false);
        const bool captured = capture_output();
        wf::scene::set_node_enabled(
            output->node_for_layer(wf::scene::layer::BACKGROUND), true);

        if (!captured)
        {
            shade_log("start_open: capture failed");
            output->deactivate_plugin(&activation);
            return false;
        }

        // 2. Reveal the (live, interactive) desktop grid. It lives on BOTTOM,
        //    so it is naturally below the OVERLAY screenshot added in step 5.
        set_desktop_visible(true);

        // 2a. Hand keyboard focus to the revealed grid so the user can start
        //     typing into its search field straight away.
        focus_desktop();

        // 3. Attach a transformer to the live grid and park it offscreen on the
        //    entering edge so it can slide into place.
        if (desktop_view)
        {
            desktop_tr = std::make_shared<wf::scene::view_2d_transformer_t>(desktop_view);
            desktop_view->get_transformed_node()->add_transformer(
                desktop_tr, wf::TRANSFORMER_2D, DESKTOP_TRANSFORMER_NAME);
            auto n = desktop_view->get_transformed_node();
            n->begin_transform_update();
            desktop_tr->translation_y = (float) (-slide_sign * H);
            n->end_transform_update();
        }

        // 4. Hide the live app windows / panel so only the grid and the live
        //    wallpaper are visible behind the sliding snapshot. (The frozen copy
        //    of the foreground lives in the snapshot; the wallpaper stays live.)
        set_live_layers_hidden(true);

        // 5. Drop the snapshot on top of everything (OVERLAY) and start closed
        //    (translate_y == 0, covering the foreground's old position).
        screenshot_node = std::make_shared<shade_screenshot_node_t>(
            rel, screenshot_buf.get_texture());
        wf::scene::add_front(output->node_for_layer(wf::scene::layer::OVERLAY),
            screenshot_node);

        shade_log("start_open: H=%d slide_sign=%d", H, slide_sign);

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
        if (screenshot_node)
        {
            // Foreground slides off the exiting edge.
            screenshot_node->translate_y = (float) (slide_sign * H * p);
        }

        if (desktop_tr && desktop_view)
        {
            // Grid slides in from the entering edge to its resting position.
            auto n = desktop_view->get_transformed_node();
            n->begin_transform_update();
            desktop_tr->translation_y = (float) (-slide_sign * H * (1.0 - p));
            n->end_transform_update();
        }

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
    // compositor has to do it. Used on reveal so the grid's search field is
    // ready to type into immediately.
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
    // while the shade is closed.
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

    // Hide / show the live foreground layers (app windows + panel). BACKGROUND
    // (the live wallpaper) stays untouched, BOTTOM (the desktop grid) and
    // OVERLAY (the snapshot) are left enabled.
    void set_live_layers_hidden(bool hidden)
    {
        for (auto layer : {wf::scene::layer::WORKSPACE, wf::scene::layer::TOP})
        {
            wf::scene::set_node_enabled(output->node_for_layer(layer), !hidden);
        }
    }

    // Render the current scene of this output into screenshot_buf, with a
    // transparent clear so areas that have no window let the live wallpaper
    // (re-enabled by the caller) show through behind the sliding snapshot.
    bool capture_output()
    {
        const auto rel = output->get_relative_geometry();
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
        params.background_color = {0.0, 0.0, 0.0, 0.0};
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

        // Remove the grid transformer before re-enabling layers, so the grid
        // snaps back to its resting position.
        if (desktop_tr && desktop_view)
        {
            desktop_view->get_transformed_node()->rem_transformer(desktop_tr);
        }
        desktop_tr.reset();

        // Bring the live foreground layers back; defensively re-enable the
        // wallpaper in case a capture left it disabled.
        set_live_layers_hidden(false);
        wf::scene::set_node_enabled(
            output->node_for_layer(wf::scene::layer::BACKGROUND), true);

        // Shade closed → desktop grid goes back to hidden. Hand keyboard focus
        // back to whatever real window should hold it now that the grid's
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
// shape to wayfire-curtain-peek so lumen-desktop/lumen-panel can drive it.
// ---------------------------------------------------------------------------
class wayfire_shade_peek_plugin_t :
    public wf::per_output_plugin_t<wayfire_shade_peek_t>
{
    wf::shared_data::ref_ptr_t<wf::ipc::method_repository_t> ipc_repo;

    wayfire_shade_peek_t *instance_for_active_output()
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
        shade_log("plugin init: registering IPC methods");
        wf::per_output_plugin_t<wayfire_shade_peek_t>::init();
        ipc_repo->register_method("wayfire-shade-peek/toggle", on_toggle_ipc);
        ipc_repo->register_method("wayfire-shade-peek/start",  on_start_ipc);
        ipc_repo->register_method("wayfire-shade-peek/stop",   on_stop_ipc);
    }

    void fini() override
    {
        shade_log("plugin fini: unregistering IPC methods");
        ipc_repo->unregister_method("wayfire-shade-peek/toggle");
        ipc_repo->unregister_method("wayfire-shade-peek/start");
        ipc_repo->unregister_method("wayfire-shade-peek/stop");
        wf::per_output_plugin_t<wayfire_shade_peek_t>::fini();
    }
};

DECLARE_WAYFIRE_PLUGIN(wayfire_shade_peek_plugin_t)
