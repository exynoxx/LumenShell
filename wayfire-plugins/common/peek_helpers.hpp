#pragma once

// Helpers shared by the drawer-reveal plugins (curtain/slide/zoom-peek): find a
// BOTTOM-layer surface by app-id, hide/show it, focus it, and snapshot the output.

#include <wayfire/core.hpp>
#include <wayfire/output.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/view.hpp>
#include <wayfire/view-helpers.hpp>
#include <wayfire/render.hpp>
#include <wayfire/scene.hpp>
#include <wayfire/scene-render.hpp>
#include <wayfire/region.hpp>

#include <string>
#include <vector>

namespace lumen
{
inline wayfire_view find_bottom_view(wf::output_t *output, const std::string& app_id)
{
    for (auto& view : wf::collect_views_from_output(output, {wf::scene::layer::BOTTOM}))
    {
        if (view && view->is_mapped() && (view->get_app_id() == app_id))
        {
            return view;
        }
    }

    return nullptr;
}

// Looks the view up into `cache` when it isn't known yet. Toggles the scene node
// only; the view stays mapped. set_node_enabled is a COUNTER, not a flag: every
// hide must be paired with exactly one show.
inline void set_view_visible(wayfire_view& cache, wf::output_t *output,
    const std::string& app_id, bool visible)
{
    if (!cache)
    {
        cache = find_bottom_view(output, app_id);
    }

    if (cache)
    {
        wf::scene::set_node_enabled(cache->get_root_node(), visible);
    }
}

// A BOTTOM-layer surface can't take focus client-side, so the compositor focuses
// it to make the drawer's search field typeable at once.
inline void focus_view(wayfire_view view)
{
    auto seat = wf::get_core().seat.get();
    if (view && seat)
    {
        seat->set_active_node(view->get_surface_root_node(),
            wf::keyboard_focus_reason::REFOCUS);
    }
}

// Renders the global scene as seen on `output` into `buf` (layout geometry,
// output scale, NORMAL transform). Disable layers around the call to leave them
// out. On failure `buf` is freed and false returned.
inline bool capture_output(wf::output_t *output, wf::auxilliary_buffer_t& buf,
    float clear_alpha)
{
    const auto layout = output->get_layout_geometry();
    const float scale = output->handle ? output->handle->scale : 1.0f;
    if ((layout.width <= 0) || (layout.height <= 0))
    {
        return false;
    }

    buf.allocate({layout.width, layout.height}, scale);

    std::vector<wf::scene::render_instance_uptr> instances;
    wf::get_core().scene()->gen_render_instances(instances,
        [] (const wf::region_t&) {}, output);

    wf::render_target_t target{buf};
    target.geometry     = layout;
    target.scale        = scale;
    target.wl_transform = WL_OUTPUT_TRANSFORM_NORMAL;

    wf::render_pass_params_t params;
    params.instances        = &instances;
    params.target           = target;
    params.damage           = wf::region_t{layout};
    params.background_color = {0.0, 0.0, 0.0, clear_alpha};
    params.reference_output = output;
    params.flags            = wf::RPASS_CLEAR_BACKGROUND;
    wf::render_pass_t::run(params);

    if (!buf.get_texture())
    {
        buf.free();
        return false;
    }

    return true;
}
}
