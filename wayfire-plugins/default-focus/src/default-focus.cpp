// wayfire-default-focus
//
// Hand keyboard focus back to a designated layer-shell surface whenever no
// toplevel view holds it. Solves the "type after closing the last window
// and nothing happens" problem for desktop-style shells (lumen-desktop,
// nwg-drawer, etc.) that live on the BOTTOM layer.
//
// Why this can't be done client-side: wlr-layer-shell forbids EXCLUSIVE
// keyboard interactivity on the BACKGROUND and BOTTOM layers — only the
// TOP and OVERLAY layers can grab. A BOTTOM-layer shell stuck with
// ON_DEMAND therefore has no protocol-level way to claim focus when the
// last toplevel disappears. The compositor, however, is free to call the
// seat focus API on any view, so we do that here.
//
// The target surface is identified by its wlr_layer_surface_v1::namespace
// (configured via the "namespace" option, default "lumen-desktop"). This
// matches the value passed to GtkLayerShell.set_namespace() / equivalent
// on the client side.

#include <wayfire/plugin.hpp>
#include <wayfire/core.hpp>
#include <wayfire/view.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/signal-provider.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/debug.hpp>

extern "C" {
#define namespace namespace_t
#include <wlr/types/wlr_layer_shell_v1.h>
#undef namespace
}

#include <cstring>
#include <string>

class wayfire_default_focus_t : public wf::plugin_interface_t
{
    wf::option_wrapper_t<std::string> ns_opt{"wayfire-default-focus/namespace"};

    bool refocusing = false;

    wf::signal::connection_t<wf::keyboard_focus_changed_signal> on_focus_changed =
        [=] (wf::keyboard_focus_changed_signal *ev)
        {
            (void) ev;
            if (refocusing) return;
            maybe_refocus();
        };

    bool matches_namespace(wayfire_view v)
    {
        const std::string target_ns = (std::string) ns_opt;
        if (target_ns.empty()) return false;
        if (!v || !v->is_mapped()) return false;
        auto wlr_surf = v->get_wlr_surface();
        if (!wlr_surf) return false;
        auto ls = wlr_layer_surface_v1_try_from_wlr_surface(wlr_surf);
        if (!ls) return false;
        const char *ns = ls->namespace_t;
        return ns && (target_ns == (std::string) ns);
    }

    // Prefer the matching surface on the active output. With one grid per
    // monitor (multi-monitor lumen-desktop) all share the namespace, so without
    // this a peek on a secondary output would have its keyboard yanked back to
    // the primary output's grid. Falls back to the first match if the active
    // output has none.
    wayfire_view find_target_view()
    {
        auto seat = wf::get_core().seat.get();
        wf::output_t *active = seat ? seat->get_active_output() : nullptr;

        wayfire_view fallback = nullptr;
        for (auto& v : wf::get_core().get_all_views())
        {
            if (!matches_namespace(v)) continue;
            if (!fallback) fallback = v;
            if (active && (v->get_output() == active)) return v;
        }
        return fallback;
    }

    void maybe_refocus()
    {
        auto seat = wf::get_core().seat.get();
        if (!seat) return;

        // If a real app window already has keyboard focus, do nothing — we
        // only step in when the keyboard would otherwise land nowhere.
        auto active = seat->get_active_view();
        if (active && active->is_mapped() && (active->role == wf::VIEW_ROLE_TOPLEVEL))
        {
            return;
        }

        // Already on one of our grids (e.g. the one a peek just focused on a
        // secondary output) — leave it rather than dragging focus to another
        // monitor's grid.
        if (matches_namespace(active))
        {
            return;
        }

        auto target = find_target_view();
        if (!target) return;

        auto target_node = target->get_surface_root_node();
        if (seat->get_active_node() == target_node) return;

        LOGD("wayfire-default-focus: refocusing layer surface '", (std::string) ns_opt, "'");
        refocusing = true;
        seat->set_active_node(target_node, wf::keyboard_focus_reason::REFOCUS);
        refocusing = false;
    }

  public:
    void init() override
    {
        wf::get_core().connect(&on_focus_changed);
        // Catch the boot case where the target is already mapped but no
        // toplevel exists yet.
        maybe_refocus();
    }

    void fini() override
    {
        on_focus_changed.disconnect();
    }
};

DECLARE_WAYFIRE_PLUGIN(wayfire_default_focus_t)
