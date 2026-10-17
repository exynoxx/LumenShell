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
constexpr const char *DRAWER_TRANSFORMER_NAME = "wayfire-zoom-peek-zoom";

// Debug log, append-only; truncate manually before a test session.
inline void zoom_log(const char *fmt, ...)
{
    FILE *fp = std::fopen("/tmp/wayfire-zoom-peek.log", "a");
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

inline double smoothstep(double a, double b, double x)
{
    const double t = std::clamp((x - a) / (b - a), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}
}

// Front of BACKGROUND: the frozen wallpaper + windows, cross-faded into a
// blurred, dimmed copy. Sits under the drawer (BOTTOM) and the live panel (TOP).
class zoom_backdrop_node_t : public wf::scene::node_t
{
  public:
    wf::geometry_t geo;              // full output, output-relative {0,0,W,H}
    wlr_texture   *sharp   = nullptr;
    wlr_texture   *blurred = nullptr;
    float blur = 0.0f;               // 0 = sharp, 1 = fully blurred + dimmed
    float dim  = 0.0f;               // black overlay alpha at blur == 1

    zoom_backdrop_node_t(wf::geometry_t g, wlr_texture *s, wlr_texture *b, float d) :
        wf::scene::node_t(false), geo(g), sharp(s), blurred(b), dim(d)
    {}

    std::string stringify() const override
    {
        return "zoom-peek-backdrop";
    }

    wf::geometry_t get_bounding_box() override
    {
        return geo;
    }

    void gen_render_instances(std::vector<wf::scene::render_instance_uptr>& instances,
        wf::scene::damage_callback push_damage, wf::output_t *shown_on) override;
};

class zoom_backdrop_render_instance_t :
    public wf::scene::simple_render_instance_t<zoom_backdrop_node_t>
{
  public:
    using simple_render_instance_t::simple_render_instance_t;

    void render(const wf::scene::render_instruction_t& data) override
    {
        const auto damage = data.damage & self->geo;
        const float b     = std::clamp(self->blur, 0.0f, 1.0f);

        if (self->sharp && (b < 1.0f))
        {
            wf::texture_t tex;
            tex.texture = self->sharp;
            data.pass->add_texture(tex, data.target, self->geo, damage);
        }

        if (self->blurred && (b > 0.0f))
        {
            wf::texture_t tex;
            tex.texture     = self->blurred;
            tex.filter_mode = WLR_SCALE_FILTER_BILINEAR;
            data.pass->add_texture(tex, data.target, self->geo, damage, b);
        }

        if (self->dim > 0.0f)
        {
            data.pass->add_rect({0.0, 0.0, 0.0, self->dim * b}, data.target,
                self->geo, damage);
        }
    }
};

inline void zoom_backdrop_node_t::gen_render_instances(
    std::vector<wf::scene::render_instance_uptr>& instances,
    wf::scene::damage_callback push_damage, wf::output_t *shown_on)
{
    instances.push_back(std::make_unique<zoom_backdrop_render_instance_t>(
        this, push_damage, shown_on));
}

class wayfire_zoom_peek_t : public wf::per_output_plugin_instance_t
{
    wf::option_wrapper_t<wf::activatorbinding_t> toggle_opt{"wayfire-zoom-peek/toggle"};
    wf::option_wrapper_t<wf::activatorbinding_t> dismiss_opt{"wayfire-zoom-peek/dismiss"};
    wf::option_wrapper_t<std::string> drawer_app_id_opt{"wayfire-zoom-peek/drawer_app_id"};
    wf::option_wrapper_t<double> initial_scale_opt{"wayfire-zoom-peek/initial_scale"};
    wf::option_wrapper_t<int> blur_levels_opt{"wayfire-zoom-peek/blur_levels"};
    wf::option_wrapper_t<double> dim_opt{"wayfire-zoom-peek/dim"};
    wf::option_wrapper_t<wf::animation_description_t> duration_opt{"wayfire-zoom-peek/duration"};

    wf::option_wrapper_t<wf::animation_description_t> close_duration_opt{"wayfire-zoom-peek/close_duration"};

    wf::animation::simple_animation_t open_anim{duration_opt};
    wf::animation::simple_animation_t close_anim{close_duration_opt};
    // Whichever of the two is driving; closing has its own easing.
    wf::animation::simple_animation_t *anim = &open_anim;

    enum class state_t { IDLE, OPENING, OPEN, CLOSING };
    state_t state = state_t::IDLE;

    wf::auxilliary_buffer_t screenshot_buf;
    // Halving pyramid; after the up-pass, levels[0] (half size) is the blur.
    std::vector<wf::auxilliary_buffer_t> levels;
    std::shared_ptr<zoom_backdrop_node_t> backdrop_node;

    int H = 0;

    // Cached so we can re-enable it after disabling its node.
    wayfire_view drawer_view;
    std::shared_ptr<wf::scene::view_2d_transformer_t> drawer_tr;

    // No grab: the revealed grid must stay clickable.
    wf::plugin_activation_data_t activation = {
        .name = "wayfire-zoom-peek",
        .capabilities = 0,
        .cancel = [this] { hard_reset(); },
    };

    wf::activator_callback on_toggle = [this] (const wf::activator_data_t&)
    {
        return ipc_toggle();
    };

    // Restore-only; a no-op from IDLE so it doesn't steal Escape when nothing is open.
    wf::activator_callback on_dismiss = [this] (const wf::activator_data_t&)
    {
        return ipc_stop();
    };

    // Hide the grid as soon as it maps unless a reveal is open.
    wf::signal::connection_t<wf::view_mapped_signal> on_view_mapped =
        [this] (wf::view_mapped_signal *ev)
    {
        if (!is_drawer_view(ev->view))
        {
            return;
        }

        drawer_view = ev->view;
        if (state == state_t::IDLE)
        {
            set_drawer_visible(false);
        }
    };

    wf::signal::connection_t<wf::view_unmapped_signal> on_view_unmapped =
        [this] (wf::view_unmapped_signal *ev)
    {
        if (ev->view == drawer_view)
        {
            drawer_tr.reset();
            drawer_view = nullptr;
        }
    };

    wf::effect_hook_t on_frame = [this] ()
    {
        apply_progress((double) *anim);

        if (!anim->running())
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
        zoom_log("per-output init on output=%p drawer_app_id='%s'", (void *) output,
            ((std::string) drawer_app_id_opt).c_str());
        output->add_activator(toggle_opt, &on_toggle);
        output->add_activator(dismiss_opt, &on_dismiss);
        output->connect(&on_view_mapped);
        output->connect(&on_view_unmapped);

        drawer_view = find_drawer_view();
        if (drawer_view)
        {
            set_drawer_visible(false);
        }
    }

    void fini() override
    {
        output->rem_binding(&on_toggle);
        output->rem_binding(&on_dismiss);
        on_view_mapped.disconnect();
        on_view_unmapped.disconnect();
        if (state != state_t::IDLE)
        {
            hard_reset();
        }
        // Don't leave the drawer stuck hidden on unload.
        set_drawer_visible(true);
        drawer_view = nullptr;
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
        return (state == state_t::IDLE) && start_open();
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
        if (!output->activate_plugin(&activation))
        {
            zoom_log("start_open: activate_plugin returned false");
            return false;
        }

        // Output-relative: output_node_t children are output-local.
        const auto rel = output->get_relative_geometry();
        H = rel.height;

        if (!capture_output() || !build_blur())
        {
            zoom_log("start_open: capture/blur failed");
            screenshot_buf.free();
            levels.clear();
            output->deactivate_plugin(&activation);
            return false;
        }

        backdrop_node = std::make_shared<zoom_backdrop_node_t>(rel,
            screenshot_buf.get_texture(), levels[0].get_texture(),
            (float) std::clamp((double) dim_opt, 0.0, 1.0));
        wf::scene::add_front(output->node_for_layer(wf::scene::layer::BACKGROUND),
            backdrop_node);

        // The snapshot stands in for the windows; the panel (TOP) stays live.
        wf::scene::set_node_enabled(
            output->node_for_layer(wf::scene::layer::WORKSPACE), false);

        set_drawer_visible(true);
        focus_drawer();

        if (drawer_view)
        {
            drawer_tr = std::make_shared<wf::scene::view_2d_transformer_t>(drawer_view);
            drawer_view->get_transformed_node()->add_transformer(
                drawer_tr, wf::TRANSFORMER_2D, DRAWER_TRANSFORMER_NAME);
        }

        apply_progress(0.0);
        output->render->add_effect(&on_frame, wf::OUTPUT_EFFECT_PRE);
        state = state_t::OPENING;
        anim = &open_anim;
        anim->animate(0.0, 1.0);
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
        const double from = (double) *anim;
        anim = &close_anim;
        anim->animate(from, 0.0);
    }

    // p: 0 = grid zoomed in above the screen, invisible; 1 = grid in place.
    void apply_progress(double p)
    {
        const double rest = 1.0 - p;

        if (drawer_tr && drawer_view)
        {
            const float s = (float) (1.0 + (std::max(1.0, (double) initial_scale_opt) - 1.0) * rest);
            auto n = drawer_view->get_transformed_node();
            n->begin_transform_update();
            drawer_tr->scale_x = s;
            drawer_tr->scale_y = s;
            drawer_tr->translation_y = (float) (-0.5 * H * rest);
            n->end_transform_update();
        }

        // Blur arrives only as the grid is nearly in place.
        if (backdrop_node)
        {
            backdrop_node->blur = (float) smoothstep(0.55, 0.95, p);
        }

        output->render->damage_whole();
    }

    bool is_drawer_view(wayfire_view view) const
    {
        return view && (view->get_app_id() == (std::string) drawer_app_id_opt);
    }

    wayfire_view find_drawer_view()
    {
        for (auto& view : wf::collect_views_from_output(output,
            {wf::scene::layer::BOTTOM}))
        {
            if (view && view->is_mapped() && is_drawer_view(view))
            {
                return view;
            }
        }
        return nullptr;
    }

    // A BOTTOM-layer surface can't take focus client-side, so the compositor
    // focuses the grid to make its search field typeable at once.
    void focus_drawer()
    {
        if (!drawer_view)
        {
            drawer_view = find_drawer_view();
        }
        auto seat = wf::get_core().seat.get();
        if (drawer_view && seat)
        {
            seat->set_active_node(drawer_view->get_surface_root_node(),
                wf::keyboard_focus_reason::REFOCUS);
        }
    }

    // Toggles the scene node only; the view stays mapped throughout.
    void set_drawer_visible(bool visible)
    {
        if (!drawer_view)
        {
            drawer_view = find_drawer_view();
        }
        if (drawer_view)
        {
            wf::scene::set_node_enabled(drawer_view->get_root_node(), visible);
        }
    }

    // Wallpaper + windows only: BOTTOM/TOP/OVERLAY (drawer, panel, OSD) are
    // left out so the live panel isn't doubled by a frozen, blurred copy.
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

        const wf::scene::layer skipped[] = {wf::scene::layer::BOTTOM,
            wf::scene::layer::TOP, wf::scene::layer::OVERLAY};
        for (auto l : skipped)
        {
            wf::scene::set_node_enabled(output->node_for_layer(l), false);
        }

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

        instances.clear();
        for (auto l : skipped)
        {
            wf::scene::set_node_enabled(output->node_for_layer(l), true);
        }

        return screenshot_buf.get_texture() != nullptr;
    }

    // Blurred once per open, not per frame: bilinear blits halve the snapshot
    // `blur_levels` times, then double it back up to half size. Each upsample
    // smooths the previous one, giving a soft pyramid blur with no shaders.
    // ponytail: pyramid blur, swap for a dual-Kawase GLES pass if it looks blocky.
    bool build_blur()
    {
        const int n = std::clamp((int) blur_levels_opt, 1, 8);
        levels.clear();
        levels.resize(n);

        auto size = screenshot_buf.get_size();
        wf::auxilliary_buffer_t *prev = &screenshot_buf;
        for (int i = 0; i < n; i++)
        {
            const wf::dimensions_t ps = size;
            size = {std::max(1, size.width / 2), std::max(1, size.height / 2)};
            if (levels[i].allocate(size) == wf::buffer_reallocation_result_t::FAILED)
            {
                return false;
            }
            levels[i].get_renderbuffer().blit(*prev,
                {0, 0, (double) ps.width, (double) ps.height},
                {0, 0, size.width, size.height});
            prev = &levels[i];
        }

        for (int i = n - 1; i > 0; i--)
        {
            const auto src = levels[i].get_size();
            const auto dst = levels[i - 1].get_size();
            levels[i - 1].get_renderbuffer().blit(levels[i],
                {0, 0, (double) src.width, (double) src.height},
                {0, 0, dst.width, dst.height});
        }

        levels.resize(1);
        return levels[0].get_texture() != nullptr;
    }

    void hard_reset()
    {
        if (backdrop_node)
        {
            wf::scene::remove_child(backdrop_node);
            backdrop_node.reset();
        }
        screenshot_buf.free();
        levels.clear();

        if (drawer_tr && drawer_view)
        {
            drawer_view->get_transformed_node()->rem_transformer(drawer_tr);
        }
        drawer_tr.reset();

        if (state != state_t::IDLE)
        {
            wf::scene::set_node_enabled(
                output->node_for_layer(wf::scene::layer::WORKSPACE), true);
            set_drawer_visible(false);
        }

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

struct wayfire_zoom_peek_plugin_t : lumen::ipc_plugin_t<wayfire_zoom_peek_t>
{
    wayfire_zoom_peek_plugin_t() : ipc_plugin_t("lumen-peek")
    {}
};

DECLARE_WAYFIRE_PLUGIN(wayfire_zoom_peek_plugin_t)
