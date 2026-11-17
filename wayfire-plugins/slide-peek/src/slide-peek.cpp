#include <wayfire/view-transform.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/config/types.hpp>
#include <wayfire/util/duration.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/scene-operations.hpp>
#include "ipc_wrapper.hpp"
#include "log.hpp"
#include "peek_helpers.hpp"

#include <memory>
#include <vector>
#include <cmath>

#define slide_log(...) lumen::file_log("/tmp/wayfire-slide-peek.log", __VA_ARGS__)

namespace
{
constexpr const char *DESKTOP_TRANSFORMER_NAME = "wayfire-slide-peek-slide";
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
        // tex is non-null: the node is only built after lumen::capture_output() succeeded.
        wf::texture_t tex;
        tex.texture = self->tex;

        const auto g   = self->geo;
        const int  dy  = (int) std::lround(self->translate_y);

        wf::geometry_t geo = {g.x, g.y + dy, g.width, g.height};
        data.pass->add_texture(tex, data.target, geo, data.damage & geo);
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

    // Hide the grid as soon as it maps unless a reveal is open.
    wf::signal::connection_t<wf::view_mapped_signal> on_view_mapped =
        [this] (wf::view_mapped_signal *ev)
    {
        if ((ev->view->get_app_id() != (std::string) drawer_app_id_opt))
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
                // Static once settled: stop the per-frame damage.
                output->render->rem_effect(&on_frame);
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
        output->connect(&on_view_mapped);
        output->connect(&on_view_unmapped);

        // Logged because a stale app-id in wayfire.ini otherwise fails silently.
        slide_log("app ids: drawer='%s' widget='%s'",
            ((std::string) drawer_app_id_opt).c_str(),
            ((std::string) widget_app_id_opt).c_str());

        desktop_view = lumen::find_bottom_view(output, drawer_app_id_opt);
        if (desktop_view)
        {
            set_desktop_visible(false);
        }

        slide_log("found on init: drawer=%s widget=%s",
            desktop_view ? "yes" : "no",
            lumen::find_bottom_view(output, widget_app_id_opt) ? "yes" : "no");
    }

    void fini() override
    {
        slide_log("per-output fini on output=%p state=%d", (void *) output, (int) state);
        output->rem_binding(&on_toggle);
        on_view_mapped.disconnect();
        on_view_unmapped.disconnect();
        if (state != state_t::IDLE)
        {
            hard_reset();
        }
        // Don't leave the grid stuck hidden on unload. (hard_reset already
        // re-showed the widgets; set_node_enabled counts, so no second show.)
        set_desktop_visible(true);
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
        // Transparent clear so the live wallpaper shows through empty areas.
        const bool captured = lumen::capture_output(output, screenshot_buf, 0.0f);
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
        if (!desktop_view)
        {
            desktop_view = lumen::find_bottom_view(output, drawer_app_id_opt);
        }
        lumen::focus_view(desktop_view);

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

        if (state == state_t::OPEN)
        {
            // Hook was removed once settled; nothing else drives frames.
            output->render->add_effect(&on_frame, wf::OUTPUT_EFFECT_PRE);
            output->render->schedule_redraw();
        }

        state = state_t::CLOSING;
        anim.animate((double) anim, 0.0);
    }

    void apply_progress(double p)
    {
        screenshot_node->translate_y = (float) (slide_sign * H * p);

        if (desktop_tr && desktop_view)
        {
            auto n = desktop_view->get_transformed_node();
            n->begin_transform_update();
            desktop_tr->translation_y = (float) (-slide_sign * H * (1.0 - p));
            n->end_transform_update();
        }

        output->render->damage_whole();
    }

    void set_desktop_visible(bool visible)
    {
        lumen::set_view_visible(desktop_view, output, drawer_app_id_opt, visible);
    }

    void set_widgets_visible(bool visible)
    {
        lumen::set_view_visible(widget_view, output, widget_app_id_opt, visible);
    }

    void set_live_layers_hidden(bool hidden)
    {
        for (auto layer : {wf::scene::layer::WORKSPACE, wf::scene::layer::TOP})
        {
            wf::scene::set_node_enabled(output->node_for_layer(layer), !hidden);
        }
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

        set_live_layers_hidden(false);

        // Show only the view start_open() hid: looking one up here would show
        // a widget that mapped mid-peek (never hidden) and unbalance its counter.
        if (widget_view)
        {
            set_widgets_visible(true);
        }
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
