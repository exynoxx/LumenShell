#include <wayfire/per-output-plugin.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/output.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/view-transform.hpp>
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
constexpr const char *TRANSFORMER_NAME = "wayfire-curtain-peek-split";

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

// Layer-shell namespace of the lumen-desktop app grid. It is the surface we
// keep fixed as the reveal, so it must never be picked up as a curtain door.
constexpr const char *LUMEN_DESKTOP_APP_ID = "lumen-desktop";
}

// ---------------------------------------------------------------------------
// Backdrop: a static full-output solid-colour fill inserted at the very back
// of the BACKGROUND layer (below the wallpaper). While the curtain is closed
// the wallpaper covers it completely; as the wallpaper splits and slides away
// it is revealed behind the (transparent) lumen-desktop grid — a flat,
// GNOME-Shell-like grey backdrop. It never moves, so it is a plain node, not a
// transformer.
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
// Split transformer: draws the view's content twice — the part left of the
// seam shifted left, the part right of the seam shifted right. A view that
// straddles the seam is therefore cut in two; a view fully on one side has an
// empty half and is drawn once. With the per-side translations uniform across
// all tracked views, the composite is pixel-identical to cutting the whole
// foreground as a single surface (see PLAN.md "Key insight").
// ---------------------------------------------------------------------------
class curtain_split_transformer_t : public wf::scene::transformer_base_node_t
{
  public:
    // Updated each frame by the plugin inside begin/end_transform_update().
    int   seam_x   = 0;     // absolute layout-x of the seam
    float left_dx  = 0.0f;  // translation of the left half  (<= 0)
    float right_dx = 0.0f;  // translation of the right half (>= 0)

    curtain_split_transformer_t() : wf::scene::transformer_base_node_t(false)
    {}

    std::string stringify() const override
    {
        return "curtain-peek-split";
    }

    // Cover both shifted halves so damage / visibility tracking repaints the
    // gap the view vacates as well as where the halves travel to.
    wf::geometry_t get_bounding_box() override
    {
        auto b = get_children_bounding_box();
        const int x0 = b.x + (int) std::floor(std::min(0.0f, left_dx));
        const int x1 = b.x + b.width + (int) std::ceil(std::max(0.0f, right_dx));
        return {x0, b.y, x1 - x0, b.height};
    }

    void gen_render_instances(std::vector<wf::scene::render_instance_uptr>& instances,
        wf::scene::damage_callback push_damage, wf::output_t *shown_on) override;
};

class curtain_split_render_instance_t :
    public wf::scene::transformer_render_instance_t<curtain_split_transformer_t>
{
  public:
    using transformer_render_instance_t::transformer_render_instance_t;

    void render(const wf::scene::render_instruction_t& data) override
    {
        const auto bbox = self->get_children_bounding_box();
        if ((bbox.width <= 0) || (bbox.height <= 0))
        {
            return;
        }

        wf::texture_t tex = get_texture(data.target.scale);

        const int ldx  = (int) std::lround(self->left_dx);
        const int rdx  = (int) std::lround(self->right_dx);
        const int seam = std::clamp(self->seam_x, bbox.x, bbox.x + bbox.width);

        // Left half: full texture drawn at bbox+ldx, but only the columns that
        // were left of the seam are actually painted (clip via the damage arg).
        if (seam > bbox.x)
        {
            wf::geometry_t geo  = {bbox.x + ldx, bbox.y, bbox.width, bbox.height};
            wf::geometry_t clip = {bbox.x + ldx, bbox.y, seam - bbox.x, bbox.height};
            wf::region_t dmg = data.damage & clip;
            data.pass->add_texture(tex, data.target, geo, dmg);
        }

        // Right half.
        if (seam < bbox.x + bbox.width)
        {
            wf::geometry_t geo  = {bbox.x + rdx, bbox.y, bbox.width, bbox.height};
            wf::geometry_t clip = {seam + rdx, bbox.y, (bbox.x + bbox.width) - seam, bbox.height};
            wf::region_t dmg = data.damage & clip;
            data.pass->add_texture(tex, data.target, geo, dmg);
        }
    }
};

inline void curtain_split_transformer_t::gen_render_instances(
    std::vector<wf::scene::render_instance_uptr>& instances,
    wf::scene::damage_callback push_damage, wf::output_t *shown_on)
{
    instances.push_back(std::make_unique<curtain_split_render_instance_t>(
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
    wf::option_wrapper_t<wf::animation_description_t> duration_opt{"wayfire-curtain-peek/duration"};

    wf::animation::simple_animation_t anim{duration_opt};

    // Static grey fill revealed behind lumen-desktop as the wallpaper splits.
    std::shared_ptr<curtain_backdrop_node_t> backdrop;

    enum class state_t { IDLE, OPENING, OPEN, CLOSING };
    state_t state = state_t::IDLE;

    struct tracked_t
    {
        wayfire_view view;
        std::shared_ptr<curtain_split_transformer_t> tr;
        float left_dx_full  = 0.0f;
        float right_dx_full = 0.0f;
        wf::signal::connection_t<wf::view_unmapped_signal> on_unmap;
    };

    std::vector<std::unique_ptr<tracked_t>> tracked_views;

    // No grab (capabilities = 0): while open, the revealed lumen-desktop grid
    // must stay clickable, same rationale as wayfire-desktop-peek.
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
    }

    void fini() override
    {
        curtain_log("per-output fini on output=%p state=%d", (void *) output, (int) state);
        output->rem_binding(&on_toggle);
        output->rem_binding(&on_dismiss);
        if (state != state_t::IDLE)
        {
            hard_reset();
        }
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

        tracked_views.clear();

        const auto lg = output->get_layout_geometry();
        const int W = lg.width;
        const double ratio = std::clamp((double) split_ratio_opt, 0.1, 0.9);
        const int seam_off = (int) std::lround(W * ratio);
        const int edge = std::clamp((int) edge_px_opt, 0,
            std::max(0, std::min(seam_off, W - seam_off)));

        const int seam_x = lg.x + seam_off;
        const float left_dx_full  = -(float) (seam_off - edge);
        const float right_dx_full = (float) (W - seam_off - edge);

        // The curtain doors are everything EXCEPT the lumen-desktop grid:
        // the wallpaper (BACKGROUND), all app windows (WORKSPACE) and the panel
        // (TOP) split and slide aside. lumen-desktop lives on BOTTOM and is left
        // out of the collection entirely, so it stays fixed and becomes the
        // reveal; behind it, the grey backdrop (added below) shows through where
        // the wallpaper used to be.
        auto views = wf::collect_views_from_output(output,
            {wf::scene::layer::BACKGROUND, wf::scene::layer::WORKSPACE, wf::scene::layer::TOP});

        for (auto& view : views)
        {
            if (!view || !view->is_mapped())
            {
                continue;
            }

            if (auto tv = wf::toplevel_cast(view); tv && tv->minimized)
            {
                continue;
            }

            // Belt-and-suspenders: never split lumen-desktop even if it should
            // ever be reparented to a collected layer.
            if (view->get_app_id() == LUMEN_DESKTOP_APP_ID)
            {
                continue;
            }

            auto root = view->get_surface_root_node();
            if (!root)
            {
                continue;
            }

            auto bb = root->get_bounding_box();
            if ((bb.width <= 0) || (bb.height <= 0))
            {
                continue;
            }

            auto t = std::make_unique<tracked_t>();
            t->view = view;
            t->left_dx_full  = left_dx_full;
            t->right_dx_full = right_dx_full;
            t->tr = std::make_shared<curtain_split_transformer_t>();
            t->tr->seam_x   = seam_x;
            t->tr->left_dx  = 0.0f;
            t->tr->right_dx = 0.0f;

            view->get_transformed_node()->add_transformer(
                t->tr, wf::TRANSFORMER_2D, TRANSFORMER_NAME);

            wayfire_view captured = view;
            t->on_unmap = [this, captured] (wf::view_unmapped_signal*)
            {
                drop_view(captured);
            };
            view->connect(&t->on_unmap);

            tracked_views.push_back(std::move(t));
        }

        curtain_log("start_open: %zu tracked views, W=%d seam_off=%d edge=%d",
            tracked_views.size(), W, seam_off, edge);

        if (tracked_views.empty())
        {
            output->deactivate_plugin(&activation);
            return false;
        }

        // Insert the grey backdrop at the very back of the BACKGROUND layer, in
        // output-relative coords (the layer's output node is rooted at 0,0). It
        // sits below the wallpaper, so it only becomes visible as the wallpaper
        // doors slide apart.
        backdrop = std::make_shared<curtain_backdrop_node_t>(
            output->get_relative_geometry(), (wf::color_t) backdrop_color_opt);
        wf::scene::add_back(output->node_for_layer(wf::scene::layer::BACKGROUND),
            backdrop);

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
        for (auto& t : tracked_views)
        {
            if (!t->tr || !t->view)
            {
                continue;
            }

            auto tnode = t->view->get_transformed_node();
            tnode->begin_transform_update();
            t->tr->left_dx  = (float) (t->left_dx_full * p);
            t->tr->right_dx = (float) (t->right_dx_full * p);
            tnode->end_transform_update();
        }
    }

    void drop_view(wayfire_view view)
    {
        auto it = std::find_if(tracked_views.begin(), tracked_views.end(),
            [&] (auto& t) { return t->view == view; });
        if (it == tracked_views.end())
        {
            return;
        }

        if ((*it)->tr && view)
        {
            view->get_transformed_node()->rem_transformer((*it)->tr);
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
                t->view->get_transformed_node()->rem_transformer(t->tr);
            }
            t->on_unmap.disconnect();
        }
        tracked_views.clear();

        if (backdrop)
        {
            wf::scene::remove_child(backdrop);
            backdrop.reset();
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
