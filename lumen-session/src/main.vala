using GLib;

// lumen-session — persistent, headless (no-GTK) session daemon.
//
// Today its single job is *display-profile restore*: it owns its own Wayland
// connection, watches wlr-output-management hotplug, and whenever the connected
// SET of monitors matches a remembered layout (written by lumen-settings on
// "Keep" to ~/.config/lumen-shell/display-profiles.json) it re-applies that
// layout. Profiles are keyed by EDID identity (see DisplayProfileStore) so a
// layout follows a monitor across ports.
//
// It must be launched as a descendant of the Wayfire process (Wayfire
// [autostart]) so it inherits $WAYLAND_DISPLAY. See lumen-session/PLAN.md.
namespace LumenSession {

    static MainLoop loop;
    static bool     restore_queued = false;

    public static int main(string[] args) {
        loop = new MainLoop();

        // Session bootstrap (the Nautilus/libadwaita portal fix) MUST run first,
        // before any Wayland work, so it happens even on a compositor without
        // wlr-output-management-v1 (where we exit early below). See
        // nautilus-portal-bug.md.
        session_bootstrap();

        // Own Wayland connection — no GDK in this process. Mirror
        // wl_display_connect(NULL): honour $WAYLAND_DISPLAY, else "wayland-0".
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

        // Pump the private event queue from the main loop (no GDK to do it).
        // add_watch refs the channel for the source's lifetime, so it outlives
        // this scope.
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

        // Re-apply on hotplug. Registration baselines the current set, so this
        // does NOT fire for the heads already present — we restore those once,
        // explicitly, below.
        WLHooks.output_mgmt_register_outputs_changed(() => schedule_restore());
        schedule_restore();

        message("lumen-session: started (display-profile restore)");
        loop.run();

        WLHooks.output_mgmt_destroy();
        return 0;
    }

    // Push the Wayland session environment into systemd/D-Bus and activate
    // lumenshell-session.target. Under Wayfire nothing else does this, so
    // xdg-desktop-portal (Requisite=graphical-session.target) never starts and
    // libadwaita apps (Nautilus, etc.) fall back to light theme / ScreenCast is
    // dead. lumen-session is the right owner: it runs as a child of Wayfire, so
    // $WAYLAND_DISPLAY and the XDG_* identity vars are already in our
    // environment, and it outlives the GUI shell. All steps are best-effort —
    // failures are logged, never fatal (keeps ./build dev-runs and non-systemd
    // distros harmless). Idempotent, so a daemon restart safely re-runs it.
    static void session_bootstrap() {
        string vars = "WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP";
        run_best_effort("systemctl --user import-environment " + vars);
        run_best_effort("dbus-update-activation-environment --systemd " + vars);
        run_best_effort("systemctl --user start lumenshell-session.target");

        // Stamp the chosen session onto the user's AccountsService record so a
        // Wayland login manager preselects LumenShell next time. This is the one
        // responsibility the (junked) lumen-greeter would have owned — the
        // greeter is unprivileged and read-only w.r.t. AccountsService, so the
        // *session* self-sets it instead (greeter PLAN, "Deferred"). Guarded on
        // our own desktop id so a dev-run under another DE never clobbers the
        // user's real last-session; fail-soft inside AccountsClient.
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

    // Coalesce change events and defer the apply to idle so it runs OUTSIDE the
    // fd-dispatch callback: config_apply does a synchronous roundtrip on the
    // private queue, and nesting that inside the dispatch that delivered the
    // event would reenter the queue.
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

        // Current connected set: EDID identity per head + identity->connector.
        var current_keys = new GenericArray<string>();
        var conn_for = new HashTable<string, string>(str_hash, str_equal);
        WLHooks.output_mgmt_for_each_head_identity((idx, name, make, model, serial, desc) => {
            var id = DisplayProfileStore.identity_for(make, model, serial, desc, name);
            current_keys.add(id);
            conn_for.set(id, name);
        });

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
        for (int i = 0; i < current_keys.length; i++) {
            var id = current_keys.get(i);
            var conn = conn_for.get(id);
            var st = prof.states.get(id);
            if (st == null) continue;            // connected head not in profile: leave as-is
            if (st.enabled && st.width > 0 && st.height > 0) {
                WLHooks.output_mgmt_config_enable(conn, st.width, st.height,
                    st.refresh_mhz, st.x, st.y, st.transform);
                enable_count++;
            } else {
                WLHooks.output_mgmt_config_disable(conn);
            }
        }

        // Never blank every screen — if the profile would disable all connected
        // heads, abandon the config rather than apply it (the next
        // config_begin frees the dangling configuration object).
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
