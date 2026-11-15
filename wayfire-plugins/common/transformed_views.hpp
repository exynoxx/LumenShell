#pragma once

// A set of views that each carry one named 2D transformer (desktop-peek,
// panel-push, startup-zoom). A view that unmaps is dropped on its own, and
// on_empty fires when that drop leaves the set empty.

#include <wayfire/view.hpp>
#include <wayfire/view-transform.hpp>
#include <wayfire/signal-definitions.hpp>

#include <algorithm>
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace lumen
{
class transformed_views_t
{
  public:
    struct entry_t
    {
        wayfire_view view;
        std::shared_ptr<wf::scene::view_2d_transformer_t> tr;
        double dx = 0, dy = 0; // free per-view parameters for the owner
        wf::signal::connection_t<wf::view_unmapped_signal> on_unmap;
    };

    std::vector<std::unique_ptr<entry_t>> entries;
    std::function<void()> on_empty;

    explicit transformed_views_t(std::string transformer_name) :
        name(std::move(transformer_name))
    {}

    ~transformed_views_t()
    {
        clear();
    }

    bool contains(wayfire_view view) const
    {
        return std::any_of(entries.begin(), entries.end(),
            [&] (auto& e) { return e->view == view; });
    }

    // Attaches the transformer; null if the view is already tracked.
    entry_t *add(wayfire_view view)
    {
        if (!view || contains(view))
        {
            return nullptr;
        }

        auto e = std::make_unique<entry_t>();
        e->view = view;
        e->tr   = std::make_shared<wf::scene::view_2d_transformer_t>(view);
        view->get_transformed_node()->add_transformer(e->tr, wf::TRANSFORMER_2D, name);
        e->on_unmap = [this, view] (wf::view_unmapped_signal*)
        {
            // drop() destroys this closure, so copy what's needed out first.
            auto *self = this;
            self->drop(view);
            if (self->entries.empty() && self->on_empty)
            {
                self->on_empty();
            }
        };
        view->connect(&e->on_unmap);

        entries.push_back(std::move(e));
        return entries.back().get();
    }

    void drop(wayfire_view view)
    {
        auto it = std::find_if(entries.begin(), entries.end(),
            [&] (auto& e) { return e->view == view; });
        if (it == entries.end())
        {
            return;
        }

        (*it)->view->get_transformed_node()->rem_transformer((*it)->tr);
        entries.erase(it);
    }

    void clear()
    {
        for (auto& e : entries)
        {
            e->view->get_transformed_node()->rem_transformer(e->tr);
            e->on_unmap.disconnect();
        }

        entries.clear();
    }

    // Wraps the begin/end_transform_update pair around fn(entry) for every view.
    template<class F>
    void update_all(F&& fn)
    {
        for (auto& e : entries)
        {
            auto n = e->view->get_transformed_node();
            n->begin_transform_update();
            fn(*e);
            n->end_transform_update();
        }
    }

  private:
    std::string name;
};
}
