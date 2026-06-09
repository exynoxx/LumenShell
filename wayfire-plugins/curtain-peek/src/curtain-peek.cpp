#include <wayfire/per-output-plugin.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/output.hpp>
#include <wayfire/core.hpp>
#include <wayfire/view.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/view-helpers.hpp>
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
constexpr const char *SCREENSHOT_NODE_NAME = "wayfire-curtain-peek-screenshot";

// Tmp logging, mirroring the desktop-peek plugin's /tmp log so a single
// tail -f can follow both peek variants. Append-only; truncate before a session.
inline void curtain_log(const char *fmt, ...)
{
    FILE *fp = std::fopen("/tmp/wayfire-curtain-peek.log", "a");
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
// Backdrop: a static full-output solid-colour fill drawn behind the desktop
// grid (a flat, GNOME-Shell-like grey). While the curtain is closed it is
// hidden under the screenshot; once the screenshot splits it shows through the
// grid's transparent areas. It never moves, so it is a plain node.
// ---------------------------------------------------------------------------
class curtain_backdrop_node_t : public wf::scene::node_t
{
  public:
    wf::geometry_t geo;
    wf::color_t    color;

    curtain_backdrop_node_t(wf::geometry_t g, wf::color_t c) :
        wf::scene::node_t(false), geo(g), color(c)
    {}

    std::string stringify() const override
    {
        return "curtain-peek-backdrop";
    }

    wf::geometry_t get_bounding_box() override
    {
        return geo;
    }

    void gen_render_instances(std::vector<wf::scene::render_instance_uptr>& instances,
        wf::scene::damage_callback push_damage, wf::output_t *shown_on) override;
};

class curtain_backdrop_render_instance_t :
    public wf::scene::simple_render_instance_t<curtain_backdrop_node_t>
{
  public:
    using simple_render_instance_t::simple_render_instance_t;

    void render(const wf::scene::render_instruction_t& data) override
    {
        data.pass->add_rect(self->color, data.target, self->geo, data.damage);
    }
};

inline void curtain_backdrop_node_t::gen_render_instances(
    std::vector<wf::scene::render_instance_uptr>& instances,
    wf::scene::damage_callback push_damage, wf::output_t *shown_on)
{
    instances.push_back(std::make_unique<curtain_backdrop_render_instance_t>(
        this, push_damage, shown_on));
}

// ---------------------------------------------------------------------------
// Screenshot curtain: a full-output node, sitting on the OVERLAY layer (above
// everything), that draws a captured snapshot of the screen split down a
// vertical seam. The left part of the snapshot is drawn shifted left, the
// right part shifted right, so the single frozen image opens like a pair of
// double doors. The widening gap reveals whatever is live behind it — here, the
// desktop grid on top of the grey backdrop.
// ---------------------------------------------------------------------------
class curtain_screenshot_node_t : public wf::scene::node_t
{
  public:
    wf::geometry_t geo;            // full output, output-relative {0,0,W,H}
    wlr_texture   *tex = nullptr;  // the captured snapshot (owned by the plugin)
    int   seam_x   = 0;            // seam position, output-relative
    float left_dx  = 0.0f;         // left-half translation  (<= 0)
    float right_dx = 0.0f;         // right-half translation (>= 0)

    curtain_screenshot_node_t(wf::geometry_t g, wlr_texture *t) :
        wf::scene::node_t(false), geo(g), tex(t)
    {}

    std::string stringify() const override
    {
        return "curtain-peek-screenshot";
    }

    // The two halves only ever travel within the output, so the full output is
    // a safe (and simple) bounding box.
    wf::geometry_t get_bounding_box() override
    {
        return geo;
    }

    void gen_render_instances(std::vector<wf::scene::render_instance_uptr>& instances,
        wf::scene::damage_callback push_damage, wf::output_t *shown_on) override;
};

class curtain_screenshot_render_instance_t :
    public wf::scene::simple_render_instance_t<curtain_screenshot_node_t>
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

        const auto g    = self->geo;
        const int  ldx  = (int) std::lround(self->left_dx);
        const int  rdx  = (int) std::lround(self->right_dx);
        const int  seam = std::clamp(self->seam_x, g.x, g.x + g.width);

        // Left half: the whole snapshot shifted by ldx, clipped to the columns
        // that were left of the seam.
        if (seam > g.x)
        {
            wf::geometry_t geo  = {g.x + ldx, g.y, g.width, g.height};
            wf::geometry_t clip = {g.x + ldx, g.y, seam - g.x, g.height};
            data.pass->add_texture(tex, data.target, geo, data.damage & clip);
        }

        // Right half.
        if (seam < g.x + g.width)
        {
            wf::geometry_t geo  = {g.x + rdx, g.y, g.width, g.height};
            wf::geometry_t clip = {seam + rdx, g.y, (g.x + g.width) - seam, g.height};
            data.pass->add_texture(tex, data.target, geo, data.damage & clip);
        }
    }
};

inline void curtain_screenshot_node_t::gen_render_instances(
    std::vector<wf::scene::render_instance_uptr>& instances,
    wf::scene::damage_callback push_damage, wf::output_t *shown_on)
{
    instances.push_back(std::make_unique<curtain_screenshot_render_instance_t>(
        this, push_damage, shown_on));
}

// ---------------------------------------------------------------------------
// Per-output plugin instance.
// ---------------------------------------------------------------------------
class wayfire_curtain_peek_t : public wf::per_output_plugin_instance_t
{
    wf::option_wrapper_t<wf::activatorbinding_t> toggle_opt{"wayfire-curtain-peek/toggle"};
    wf::option_wrapper_t<wf::activatorbinding_t> dismiss_opt{"wayfire-curtain-peek/dismiss"};
    wf::option_wrapper_t<double> split_ratio_opt{"wayfire-curtain-peek/split_ratio"};
    wf::option_wrapper_t<int> edge_px_opt{"wayfire-curtain-peek/edge_px"};
    wf::option_wrapper_t<wf::color_t> backdrop_color_opt{"wayfire-curtain-peek/backdrop_color"};
    wf::option_wrapper_t<std::string> desktop_app_id_opt{"wayfire-curtain-peek/desktop_app_id"};
    wf::option_wrapper_t<wf::animation_description_t> duration_opt{"wayfire-curtain-peek/duration"};

    wf::animation::simple_animation_t anim{duration_opt};

    enum class state_t { IDLE, OPENING, OPEN, CLOSING };
    state_t state = state_t::IDLE;

    // The frozen snapshot of the screen and the node that splits it.
    wf::auxilliary_buffer_t screenshot_buf;
    std::shared_ptr<curtain_screenshot_node_t> screenshot_node;

    // Grey fill drawn behind the desktop grid.
    std::shared_ptr<curtain_backdrop_node_t> backdrop;

    // Full-open translations (recomputed per open from the current geometry).
    float left_dx_full  = 0.0f;
    float right_dx_full = 0.0f;

    // The desktop grid view (app-id == desktop_app_id). It is kept hidden while
    // the curtain is closed and revealed only while it is open; cached so we can
    // toggle it even after we have disabled (and thus hidden) its node.
    wayfire_view desktop_view;

    // No grab (capabilities = 0): while open, the revealed desktop grid must
    // stay clickable, same rationale as wayfire-desktop-peek.
    wf::plugin_activation_data_t activation = {
        .name = "wayfire-curtain-peek",
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

    // Keep the desktop grid hidden until a curtain peek reveals it. Catch it as
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
        curtain_log("per-output init on output=%p", (void *) output);
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
        curtain_log("per-output fini on output=%p state=%d", (void *) output, (int) state);
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
        curtain_log("start_open: activating");
        if (!output->activate_plugin(&activation))
        {
            curtain_log("start_open: activate_plugin returned false");
            return false;
        }

        const auto rel = output->get_relative_geometry();
        const int W = rel.width;
        const double ratio = std::clamp((double) split_ratio_opt, 0.1, 0.9);
        const int seam_off = (int) std::lround(W * ratio);
        const int edge = std::clamp((int) edge_px_opt, 0,
            std::max(0, std::min(seam_off, W - seam_off)));

        left_dx_full  = -(float) (seam_off - edge);
        right_dx_full = (float) (W - seam_off - edge);

        // 1. Freeze the screen as it is right now. The desktop grid is still
        //    hidden at this point, so the snapshot is purely the wallpaper, app
        //    windows and panel — exactly the "curtain" we want to split.
        if (!capture_output())
        {
            curtain_log("start_open: capture failed");
            output->deactivate_plugin(&activation);
            return false;
        }

        // 2. Reveal the (live, interactive) desktop grid. It lives on BOTTOM, so
        //    it is naturally below the OVERLAY screenshot added in step 5.
        set_desktop_visible(true);

        // 2a. Hand keyboard focus to the revealed grid so the user can start
        //     typing into its search field straight away. Moving the seat off
        //     the previously-focused toplevel also makes lumen-desktop's
        //     foreign-toplevel watcher fire (no toplevel focused), which is
        //     what drives its client-side search_entry.grab_focus().
        focus_desktop();

        // 3. Grey backdrop behind the grid (back of the BOTTOM layer), so the
        //    grid's transparent areas show grey rather than the now-hidden
        //    wallpaper.
        backdrop = std::make_shared<curtain_backdrop_node_t>(
            rel, (wf::color_t) backdrop_color_opt);
        wf::scene::add_back(output->node_for_layer(wf::scene::layer::BOTTOM),
            backdrop);

        // 4. Hide the live wallpaper / windows / panel so only the grid and the
        //    grey backdrop are visible behind the splitting snapshot. (The frozen
        //    copy of them lives in the snapshot.)
        set_live_layers_hidden(true);

        // 5. Drop the snapshot on top of everything (OVERLAY) and start closed.
        screenshot_node = std::make_shared<curtain_screenshot_node_t>(
            rel, screenshot_buf.get_texture());
        screenshot_node->seam_x = rel.x + seam_off;
        wf::scene::add_front(output->node_for_layer(wf::scene::layer::OVERLAY),
            screenshot_node);

        curtain_log("start_open: W=%d seam_off=%d edge=%d", W, seam_off, edge);

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
        if (!screenshot_node)
        {
            return;
        }

        screenshot_node->left_dx  = (float) (left_dx_full * p);
        screenshot_node->right_dx = (float) (right_dx_full * p);
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
    // compositor has to do it — mirrors wayfire-default-focus. Used on reveal
    // so the grid's search field is ready to type into immediately.
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
    // while the curtain is closed.
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

    // Hide / show the live foreground layers (wallpaper, app windows, panel).
    // BOTTOM (the desktop grid + grey backdrop) and OVERLAY (the snapshot) are
    // left enabled.
    void set_live_layers_hidden(bool hidden)
    {
        for (auto layer : {wf::scene::layer::BACKGROUND,
            wf::scene::layer::WORKSPACE, wf::scene::layer::TOP})
        {
            wf::scene::set_node_enabled(output->node_for_layer(layer), !hidden);
        }
    }

    // Render the current scene of this output into screenshot_buf.
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
        params.background_color = {0.0, 0.0, 0.0, 1.0};
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

        // Bring the live layers back before touching the grid/backdrop.
        set_live_layers_hidden(false);

        if (backdrop)
        {
            wf::scene::remove_child(backdrop);
            backdrop.reset();
        }

        // Curtain closed → desktop grid goes back to hidden. Hand keyboard
        // focus back to whatever real window should hold it now that the grid's
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
// shape to wayfire-desktop-peek so lumen-desktop/lumen-panel can drive it.
// ---------------------------------------------------------------------------
class wayfire_curtain_peek_plugin_t :
    public wf::per_output_plugin_t<wayfire_curtain_peek_t>
{
    wf::shared_data::ref_ptr_t<wf::ipc::method_repository_t> ipc_repo;

    wayfire_curtain_peek_t *instance_for_active_output()
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
        curtain_log("plugin init: registering IPC methods");
        wf::per_output_plugin_t<wayfire_curtain_peek_t>::init();
        ipc_repo->register_method("wayfire-curtain-peek/toggle", on_toggle_ipc);
        ipc_repo->register_method("wayfire-curtain-peek/start",  on_start_ipc);
        ipc_repo->register_method("wayfire-curtain-peek/stop",   on_stop_ipc);
    }

    void fini() override
    {
        curtain_log("plugin fini: unregistering IPC methods");
        ipc_repo->unregister_method("wayfire-curtain-peek/toggle");
        ipc_repo->unregister_method("wayfire-curtain-peek/start");
        ipc_repo->unregister_method("wayfire-curtain-peek/stop");
        wf::per_output_plugin_t<wayfire_curtain_peek_t>::fini();
    }
};

DECLARE_WAYFIRE_PLUGIN(wayfire_curtain_peek_plugin_t)
