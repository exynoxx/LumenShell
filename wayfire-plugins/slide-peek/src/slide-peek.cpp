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
#include "ipc_wrapper.hpp"
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
constexpr const char *DESKTOP_TRANSFORMER_NAME = "wayfire-slide-peek-slide";

// Debug log, append-only; truncate manually before a test session.
inline void slide_log(const char *fmt, ...)
{
    FILE *fp = std::fopen("/tmp/wayfire-slide-peek.log", "a");
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

// OVERLAY node drawing the frozen foreground snapshot (wallpaper excluded),
// translated vertically as the live grid slides in from the opposite edge.
class slide_screenshot_node_t : public wf::scene::node_t
{
  public:
    wf::geometry_t geo;            // full output, output-relative {0,0,W,H}
    wlr_texture   *tex = nullptr;  // the captured snapshot (owned by the plugin)
    float translate_y = 0.0f;      // vertical translation (+ down, - up)

    slide_screenshot_node_t(wf::geometry_t g, wlr_texture *t) :
        wf::scene::node_t(false), geo(g), tex(t)
    {}

    std::string stringify() const override
    {
        return "slide-peek-screenshot";
    }

    // The snapshot can travel a full output height past either edge.
    wf::geometry_t get_bounding_box() override
    {
        return {geo.x, geo.y - geo.height, geo.width, geo.height * 3};
    }

    void gen_render_instances(std::vector<wf::scene::render_instance_uptr>& instances,
        wf::scene::damage_callback push_damage, wf::output_t *shown_on) override;
};

class slide_screenshot_render_instance_t :
    public wf::scene::simple_render_instance_t<slide_screenshot_node_t>
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

inline void slide_screenshot_node_t::gen_render_instances(
    std::vector<wf::scene::render_instance_uptr>& instances,
    wf::scene::damage_callback push_damage, wf::output_t *shown_on)
{
    instances.push_back(std::make_unique<slide_screenshot_render_instance_t>(
        this, push_damage, shown_on));
}

class wayfire_slide_peek_t : public wf::per_output_plugin_instance_t
{
    wf::option_wrapper_t<wf::activatorbinding_t> toggle_opt{"wayfire-slide-peek/toggle"};
    wf::option_wrapper_t<wf::activatorbinding_t> dismiss_opt{"wayfire-slide-peek/dismiss"};
    wf::option_wrapper_t<std::string> drawer_app_id_opt{"wayfire-slide-peek/drawer_app_id"};
    wf::option_wrapper_t<std::string> widget_app_id_opt{"wayfire-slide-peek/widget_app_id"};
    wf::option_wrapper_t<std::string> direction_opt{"wayfire-slide-peek/direction"};
    wf::option_wrapper_t<wf::animation_description_t> duration_opt{"wayfire-slide-peek/duration"};

    wf::animation::simple_animation_t anim{duration_opt};

    enum class state_t { IDLE, OPENING, OPEN, CLOSING };
    state_t state = state_t::IDLE;

    wf::auxilliary_buffer_t screenshot_buf;
    std::shared_ptr<slide_screenshot_node_t> screenshot_node;

    // slide_sign = +1: grid enters from the top; -1: from the bottom.
    int H = 0;
    int slide_sign = +1;

    // Cached so we can re-enable it after disabling its node.
    wayfire_view desktop_view;

    // Shares BOTTOM with the grid, so it is hidden while the reveal is open.
    wayfire_view widget_view;

    std::shared_ptr<wf::scene::view_2d_transformer_t> desktop_tr;

    // No grab: the revealed grid must stay clickable.
    wf::plugin_activation_data_t activation = {
        .name = "wayfire-slide-peek",
        .capabilities = 0,
        .cancel = [this] { hard_reset(); },
    };

    wf::activator_callback on_toggle = [this] (const wf::activator_data_t&)
    {
        return ipc_toggle();
    };

    // Restore-only; a no-op from IDLE so it doesn't steal Escape from other
    // consumers when nothing is open.
    wf::activator_callback on_dismiss = [this] (const wf::activator_data_t&)
    {
        return ipc_stop();
    };

    // Hide the grid as soon as it maps unless a reveal is open.
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
            desktop_tr.reset();
            desktop_view = nullptr;
        }

        if (ev->view == widget_view)
        {
            widget_view = nullptr;
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
        slide_log("per-output init on output=%p", (void *) output);
        output->add_activator(toggle_opt, &on_toggle);
        output->add_activator(dismiss_opt, &on_dismiss);
        output->connect(&on_view_mapped);
        output->connect(&on_view_unmapped);

        // Logged because a stale app-id in wayfire.ini otherwise fails silently.
        slide_log("app ids: drawer='%s' widget='%s'",
            ((std::string) drawer_app_id_opt).c_str(),
            ((std::string) widget_app_id_opt).c_str());

        desktop_view = find_desktop_view();
        if (desktop_view)
        {
            set_desktop_visible(false);
        }

        slide_log("found on init: drawer=%s widget=%s",
            desktop_view ? "yes" : "no",
            find_widget_view() ? "yes" : "no");
    }

    void fini() override
    {
        slide_log("per-output fini on output=%p state=%d", (void *) output, (int) state);
        output->rem_binding(&on_toggle);
        output->rem_binding(&on_dismiss);
        on_view_mapped.disconnect();
        on_view_unmapped.disconnect();
        if (state != state_t::IDLE)
        {
            hard_reset();
        }
        // Don't leave either BOTTOM-layer surface stuck hidden on unload.
        set_desktop_visible(true);
        set_widgets_visible(true);
        desktop_view = nullptr;
        widget_view = nullptr;
    }

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
        slide_log("start_open: activating");
        if (!output->activate_plugin(&activation))
        {
            slide_log("start_open: activate_plugin returned false");
            return false;
        }

        // Relative geometry: output_node_t children are output-local (layout
        // geometry would double-offset); capture_output() needs layout geometry.
        const auto rel = output->get_relative_geometry();
        H = rel.height;
        slide_sign = ((std::string) direction_opt == "bottom") ? -1 : +1;

        // Capture without BACKGROUND so the snapshot is windows + panel over
        // transparency (the grid is still hidden here).
        wf::scene::set_node_enabled(
            output->node_for_layer(wf::scene::layer::BACKGROUND), false);
        const bool captured = capture_output();
        wf::scene::set_node_enabled(
            output->node_for_layer(wf::scene::layer::BACKGROUND), true);

        if (!captured)
        {
            slide_log("start_open: capture failed");
            output->deactivate_plugin(&activation);
            return false;
        }

        set_desktop_visible(true);
        set_widgets_visible(false);
        focus_desktop();

        // Park the live grid offscreen on the entering edge.
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

        set_live_layers_hidden(true);

        screenshot_node = std::make_shared<slide_screenshot_node_t>(
            rel, screenshot_buf.get_texture());
        wf::scene::add_front(output->node_for_layer(wf::scene::layer::OVERLAY),
            screenshot_node);

        slide_log("start_open: H=%d slide_sign=%d", H, slide_sign);

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
            screenshot_node->translate_y = (float) (slide_sign * H * p);
        }

        if (desktop_tr && desktop_view)
        {
            auto n = desktop_view->get_transformed_node();
            n->begin_transform_update();
            desktop_tr->translation_y = (float) (-slide_sign * H * (1.0 - p));
            n->end_transform_update();
        }

        output->render->damage_whole();
    }

    bool is_desktop_view(wayfire_view view) const
    {
        return view && (view->get_app_id() == (std::string) drawer_app_id_opt);
    }

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

    // A BOTTOM-layer surface can't take focus client-side, so the compositor
    // focuses the grid to make its search field typeable at once.
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

    // Toggles the scene node only; the view stays mapped throughout.
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

    bool is_widget_view(wayfire_view view) const
    {
        return view && (view->get_app_id() == (std::string) widget_app_id_opt);
    }

    wayfire_view find_widget_view()
    {
        for (auto& view : wf::collect_views_from_output(output,
            {wf::scene::layer::BOTTOM}))
        {
            if (view && view->is_mapped() && is_widget_view(view))
            {
                return view;
            }
        }

        return nullptr;
    }

    void set_widgets_visible(bool visible)
    {
        if (!widget_view)
        {
            widget_view = find_widget_view();
        }

        if (widget_view)
        {
            wf::scene::set_node_enabled(widget_view->get_root_node(), visible);
        }
    }

    void set_live_layers_hidden(bool hidden)
    {
        for (auto layer : {wf::scene::layer::WORKSPACE, wf::scene::layer::TOP})
        {
            wf::scene::set_node_enabled(output->node_for_layer(layer), !hidden);
        }
    }

    // Transparent clear so the live wallpaper shows through empty areas.
    bool capture_output()
    {
        // Layout geometry: this renders the GLOBAL scene.
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

        if (desktop_tr && desktop_view)
        {
            desktop_view->get_transformed_node()->rem_transformer(desktop_tr);
        }
        desktop_tr.reset();

        // Defensively re-enable the wallpaper in case a capture left it disabled.
        set_live_layers_hidden(false);
        wf::scene::set_node_enabled(
            output->node_for_layer(wf::scene::layer::BACKGROUND), true);

        set_widgets_visible(true);
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

struct wayfire_slide_peek_plugin_t : lumen::ipc_plugin_t<wayfire_slide_peek_t>
{
    wayfire_slide_peek_plugin_t() : ipc_plugin_t("lumen-peek")
    {}
};

DECLARE_WAYFIRE_PLUGIN(wayfire_slide_peek_plugin_t)
