#pragma once

// Plugin-wide IPC surface shared by the peek-style plugins: registers
// `<prefix>/{toggle,start,stop}` and routes each verb to the per-output
// instance on the active output (falling back to any tracked output).
// Instance must expose bool ipc_toggle() / ipc_start() / ipc_stop().
// Replies are {"result":"ok"|"noop"} — lumen-panel and lumen-drawer rely on
// the verb names, so keep the prefix exactly the plugin name.

#include <wayfire/per-output-plugin.hpp>
#include <wayfire/core.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/plugins/ipc/ipc-method-repository.hpp>
#include <wayfire/plugins/common/shared-core-data.hpp>

#include <string>

namespace lumen
{
template<class Instance>
class ipc_plugin_t : public wf::per_output_plugin_t<Instance>
{
    wf::shared_data::ref_ptr_t<wf::ipc::method_repository_t> ipc_repo;
    std::string prefix;

    Instance *instance_for_active_output()
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

    wf::ipc::method_callback make(bool (Instance::*verb)())
    {
        return [this, verb] (const wf::json_t&) -> wf::json_t
        {
            auto inst = instance_for_active_output();
            wf::json_t res;
            res["result"] = (inst != nullptr) && (inst->*verb)() ? "ok" : "noop";
            return res;
        };
    }

    wf::ipc::method_callback on_toggle_ipc = make(&Instance::ipc_toggle);
    wf::ipc::method_callback on_start_ipc  = make(&Instance::ipc_start);
    wf::ipc::method_callback on_stop_ipc   = make(&Instance::ipc_stop);

  public:
    explicit ipc_plugin_t(std::string prefix) : prefix(std::move(prefix))
    {}

    void init() override
    {
        wf::per_output_plugin_t<Instance>::init();
        ipc_repo->register_method(prefix + "/toggle", on_toggle_ipc);
        ipc_repo->register_method(prefix + "/start", on_start_ipc);
        ipc_repo->register_method(prefix + "/stop", on_stop_ipc);
    }

    void fini() override
    {
        ipc_repo->unregister_method(prefix + "/toggle");
        ipc_repo->unregister_method(prefix + "/start");
        ipc_repo->unregister_method(prefix + "/stop");
        wf::per_output_plugin_t<Instance>::fini();
    }
};
}
