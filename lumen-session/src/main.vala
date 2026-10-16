using GLib;

// Must run as a child of Wayfire ([autostart]) to inherit $WAYLAND_DISPLAY.
namespace LumenSession {

    static MainLoop loop;
    static bool     restore_queued = false;

    public static int main(string[] args) {
        loop = new MainLoop();

        // MUST run before any Wayland work, so it still happens on a compositor
        // without wlr-output-management-v1 (where we exit early below).
        session_bootstrap();

        string sock = Environment.get_variable("WAYLAND_DISPLAY") ?? "wayland-0";
        Wl.Display? display = new Wl.Display.connect(sock);
        if (display == null) {
            warning("lumen-session: cannot connect to Wayland display '%s' "
                    + "(must run under Wayfire)", sock);
            return 1;
        }

        if (WLHooks.output_mgmt_init(display) != 0 || !WLHooks.output_mgmt_available()) {
            warning("lumen-session: compositor lacks wlr-output-management-v1; "
                    + "nothing to do");
            return 1;
        }

        // add_watch refs the channel, so it outlives this scope.
        int fd = WLHooks.output_mgmt_get_fd();
        if (fd < 0) {
            warning("lumen-session: no wayland fd; exiting");
            return 1;
        }
        var chan = new IOChannel.unix_new(fd);
        chan.add_watch(IOCondition.IN | IOCondition.HUP | IOCondition.ERR, (source, cond) => {
            if ((cond & (IOCondition.HUP | IOCondition.ERR)) != 0
                || WLHooks.output_mgmt_dispatch() < 0) {
                warning("lumen-session: wayland connection lost; exiting");
                loop.quit();
                return Source.REMOVE;
            }
            return Source.CONTINUE;
        });

        // Registration baselines the current set and won't fire for it, hence
        // the explicit first restore.
        WLHooks.output_mgmt_register_outputs_changed(() => schedule_restore());
        schedule_restore();

        message("lumen-session: started (display-profile restore)");
        loop.run();

        WLHooks.output_mgmt_destroy();
        return 0;
    }

    // Under Wayfire nothing else imports the env and starts the target, so
    // xdg-desktop-portal (Requisite=graphical-session.target) would never start.
    // Best-effort and idempotent.
    static void session_bootstrap() {
        string vars = "WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP";
        run_best_effort("systemctl --user import-environment " + vars);
        run_best_effort("dbus-update-activation-environment --systemd " + vars);
        run_best_effort("systemctl --user start lumenshell-session.target");

        // Guarded so a dev-run under another DE never clobbers the user's real
        // last-session.
        if (Environment.get_variable("XDG_CURRENT_DESKTOP") == "LumenShell")
            AccountsClient.set_current_session("lumenshell");
    }

    static void run_best_effort(string cmdline) {
        try {
            string[] argv;
            Shell.parse_argv(cmdline, out argv);
            int status;
            Process.spawn_sync(null, argv, null,
                SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL
                    | SpawnFlags.STDERR_TO_DEV_NULL,
                null, null, null, out status);
            if (status != 0)
                warning("lumen-session: `%s` exited with status %d", cmdline, status);
        } catch (Error e) {
            warning("lumen-session: could not run `%s`: %s", cmdline, e.message);
        }
    }

    // Deferred to idle: config_apply's synchronous roundtrip must not reenter
    // the queue from inside the fd-dispatch callback.
    static void schedule_restore() {
        if (restore_queued) return;
        restore_queued = true;
        Idle.add(() => {
            restore_queued = false;
            do_restore();
            return Source.REMOVE;
        });
    }

    static void do_restore() {
        WLHooks.output_mgmt_refresh();

        var current_keys = new GenericArray<string>();
        var conns = new GenericArray<string>();
        WLHooks.output_mgmt_for_each_head_identity((idx, name, make, model, serial, desc) => {
            current_keys.add(DisplayProfileStore.identity_for(make, model, serial, desc, name));
            conns.add(name);
        });
        DisplayProfileStore.disambiguate(current_keys, conns);
        var conn_for = new HashTable<string, string>(str_hash, str_equal);
        for (int i = 0; i < current_keys.length; i++)
            conn_for.set(current_keys.get(i), conns.get(i));

        if (current_keys.length == 0) return;   // nothing connected yet

        var prof = DisplayProfileStore.match(current_keys);
        if (prof == null) {
            message("lumen-session: no saved profile for set [%s]",
                    DisplayProfileStore.set_key_for(current_keys));
            return;   // first time on this set — user arranges + Keeps to save it
        }

        if (WLHooks.output_mgmt_config_begin() != 0) {
            warning("lumen-session: config_begin failed (no manager/serial)");
            return;
        }

        int enable_count = 0;
        // Configuring one head twice is a protocol error that drops the connection.
        var configured = new GenericSet<string>(str_hash, str_equal);
        for (int i = 0; i < current_keys.length; i++) {
            var id = current_keys.get(i);
            var conn = conn_for.get(id);
            var st = prof.states.get(id);
            if (st == null) continue;            // connected head not in profile: leave as-is
            if (conn in configured) continue;
            configured.add(conn);
            if (st.enabled && st.width > 0 && st.height > 0) {
                WLHooks.output_mgmt_config_enable(conn, st.width, st.height,
                    st.refresh_mhz, st.x, st.y, st.transform);
                enable_count++;
            } else {
                WLHooks.output_mgmt_config_disable(conn);
            }
        }

        // Never blank every screen; the next config_begin frees the abandoned config.
        if (enable_count == 0) {
            warning("lumen-session: profile for set [%s] enables no output; skipping",
                    prof.set_key());
            return;
        }

        int rc = WLHooks.output_mgmt_config_apply();
        if (rc == 0)
            message("lumen-session: applied profile for set [%s]", prof.set_key());
        else
            warning("lumen-session: apply profile for set [%s] failed rc=%d",
                    prof.set_key(), rc);
    }
}
