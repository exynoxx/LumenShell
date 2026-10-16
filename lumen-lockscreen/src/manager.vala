using LumenCommon;

public class LockManager : GLib.Object {

    // Mirrored onto DBus by LockService.
    public signal void locked();
    public signal void unlocked();

    public bool is_locked { get; private set; default = false; }

    private Gtk.Application app;
    private LogindBridge    logind;
    private PamAuth         pam;
    private IdleWatcher     idle;

    private GtkSessionLock.Instance? instance = null;
    private HashTable<Gdk.Monitor, LockWindow> windows;
    private Gdk.Monitor? primary_monitor = null;
    private ulong monitors_handler = 0;

    private bool authenticating = false;
    private int  failures = 0;

    private Gdk.Texture? backdrop = null;       // cached blurred wallpaper (card backdrop)

    public LockManager(Gtk.Application app) {
        this.app = app;
        this.pam = new PamAuth(Utils.PAM_SERVICE);
        this.windows = new HashTable<Gdk.Monitor, LockWindow>(direct_hash, direct_equal);

        DiagLog.log("manager: idle_timeout_ms=%d", Theme.idle_timeout_ms);

        init_wlhooks();

        // Idle auto-lock. Arm immediately; disarm while locked so it can't
        // re-fire, re-arm on unlock.
        this.idle = new IdleWatcher((uint32) Theme.idle_timeout_ms);
        idle.idled.connect(() => { DiagLog.log("trigger: idle timeout"); lock_now(); });
        idle.arm();

        // Warm both session-long caches so the first lock doesn't pay the blur
        // or the AccountsService roundtrip.
        Idle.add(() => {
            BlurredWallpaper.get_texture();
            AccountsClient.load_current_user();
            return Source.REMOVE;
        });

        this.logind = new LogindBridge();
        logind.lock_requested.connect(() => { DiagLog.log("trigger: logind Lock"); lock_now(); });
        logind.unlock_requested.connect(() => { DiagLog.log("trigger: logind Unlock"); unlock_now(); });   // loginctl already authenticated
        logind.prepare_for_sleep.connect((starting) => {
            DiagLog.log("trigger: PrepareForSleep starting=%s", starting.to_string());
            if (starting) {
                if (lock_on_suspend_enabled()) lock_now();
                // Lock request is in flight; let the kernel proceed to sleep.
                logind.release_delay_inhibitor();
            } else {
                // Re-arm for the next sleep cycle.
                logind.take_delay_inhibitor();
            }
        });
    }

    // power.ini [power] lock-on-suspend, written by lumen-settings; default on.
    private static bool lock_on_suspend_enabled() {
        var kf = new KeyFile();
        try {
            kf.load_from_file(Paths.power_ini(), KeyFileFlags.NONE);
            return kf.get_string("power", "lock-on-suspend").strip() == "true";
        } catch (Error e) {
            return true;
        }
    }

    // Bind ext-idle-notify-v1 (idle auto-lock) on GTK's own wl_display, so the
    // GDK main loop dispatches the idled/resumed events.
    private void init_wlhooks() {
        var gdk = Gdk.Display.get_default();
        if (gdk is Gdk.Wayland.Display) {
            unowned Wl.Display wl = ((Gdk.Wayland.Display) gdk).get_wl_display();
            if (WLHooks.idle_notify_init(wl) == 0) {
                DiagLog.log("wlhooks: idle_notify_init ok");
                return;
            }
        }
        warning("lumen-lockscreen: wlhooks init failed; idle auto-lock disabled");
    }

    // ---- lock --------------------------------------------------------------

    public void lock_now() {
        DiagLog.log("lock requested: (is_locked=%s instance=%s)",
            is_locked.to_string(), (instance != null).to_string());

        if (is_locked || instance != null) {
            DiagLog.log("lock ignored: re-entrancy guard");
            return;
        }

        if (!GtkSessionLock.is_supported()) {
            warning("lumen-lockscreen: compositor lacks ext-session-lock-v1; cannot lock");
            return;
        }

        begin_lock();
    }

    private void begin_lock() {
        // Null falls back to the theme image / a solid scrim.
        backdrop = BlurredWallpaper.get_texture();

        instance = new GtkSessionLock.Instance();
        instance.locked.connect(on_locked);
        instance.failed.connect(on_failed);
        instance.unlocked.connect(on_unlocked);

        DiagLog.log("begin_lock: requesting ext-session-lock");
        if (!instance.@lock()) {
            warning("lumen-lockscreen: lock request could not be sent");
            instance = null;
            backdrop = null;
        }
    }

    // Compositor granted the lock — NOW we may create lock surfaces.
    private void on_locked() {
        is_locked = true;
        failures = 0;
        DiagLog.log("locked: compositor granted lock; building surfaces");
        idle.disarm();   // already locked — don't let idle re-fire

        var display = Gdk.Display.get_default();
        if (display == null) {
            warning("lumen-lockscreen: no default display");
            return;
        }

        reconcile_monitors();

        // Track hotplug while locked: the protocol requires a surface per
        // output, so a newly-attached monitor needs a lock window immediately.
        monitors_handler = display.get_monitors().items_changed.connect(
            (pos, removed, added) => reconcile_monitors());

        focus_primary();
        locked();
    }

    private void on_failed() {
        warning("lumen-lockscreen: another locker holds the session; aborting");
        teardown_windows();
        instance = null;
        is_locked = false;
    }

    // ---- unlock ------------------------------------------------------------

    // External, pre-authenticated unlock (loginctl unlock-session / DBus Unlock).
    public void unlock_now() {
        if (!is_locked || instance == null) return;
        instance.unlock();   // → on_unlocked tears everything down
    }

    private void on_unlocked() {
        // `unlocked` fires inside unlock() BEFORE unlock_and_destroy is sent.
        // Destroying the windows here leaves Wayfire locked with no surface (a
        // stale-frame flash); the library destroys them afterwards. Bookkeeping only.
        release_bookkeeping();
        instance = null;
        is_locked = false;
        failures = 0;
        idle.arm();      // re-arm idle auto-lock for the unlocked session
        DiagLog.log("unlocked: session unlocked, idle re-armed");
        unlocked();
    }

    // Does NOT destroy the windows: gtk4-session-lock owns lock surfaces, and the
    // GtkApplication keeps them alive until the library destroys them.
    private void release_bookkeeping() {
        var display = Gdk.Display.get_default();
        if (display != null && monitors_handler != 0) {
            SignalHandler.disconnect(display.get_monitors(), monitors_handler);
            monitors_handler = 0;
        }
        windows.remove_all();
        primary_monitor = null;
        backdrop = null;        // release the blurred-wallpaper texture
    }

    // `failed` path: the lock was never granted, so the library destroys nothing.
    private void teardown_windows() {
        windows.foreach((mon, win) => win.destroy());
        release_bookkeeping();
    }

    // ---- auth --------------------------------------------------------------

    private void try_auth(string password) {
        if (authenticating) return;
        var primary = current_primary();
        if (primary == null || primary.password == null) return;

        authenticating = true;
        primary.password.set_busy(true);

        pam.authenticate_async(password, (ok) => {
            authenticating = false;
            // Outcome only — the password buffer is never logged anywhere.
            DiagLog.log("auth: %s", ok ? "success" : "failure");
            if (ok) {
                unlock_now();
            } else {
                on_auth_fail();
            }
        });
    }

    private void on_auth_fail() {
        failures++;
        var primary = current_primary();
        if (primary == null || primary.password == null) return;

        primary.password.clear();
        primary.password.set_error("Incorrect password");

        if (failures >= 3) {
            // Backoff: lock input for the configured window, then reset.
            primary.password.set_input_enabled(false);
            Timeout.add(Theme.failure_backoff_ms, () => {
                failures = 0;
                var p = current_primary();
                if (p != null && p.password != null) {
                    p.password.clear_status();
                    p.password.set_input_enabled(true);
                }
                return Source.REMOVE;
            });
        } else {
            primary.password.set_input_enabled(true);
        }
    }

    // ---- per-output windows -------------------------------------------------

    // Idempotent: exactly one window per output, the card on a single primary.
    private void reconcile_monitors() {
        if (instance == null) return;
        var display = Gdk.Display.get_default();
        if (display == null) return;

        var model = display.get_monitors();
        uint n = model.get_n_items();

        var live = new GenericArray<Gdk.Monitor>();
        for (uint i = 0; i < n; i++)
            live.add((Gdk.Monitor) model.get_item(i));

        var gone = new GenericArray<Gdk.Monitor>();
        windows.foreach((mon, win) => {
            if (!contains(live, mon)) gone.add(mon);
        });
        for (int i = 0; i < gone.length; i++) {
            var win = windows.get(gone.get(i));
            if (win != null) win.destroy();
            windows.remove(gone.get(i));
        }

        if (live.length == 0) return;

        if (primary_monitor == null || !contains(live, primary_monitor))
            primary_monitor = live.get(0);

        for (int i = 0; i < live.length; i++) {
            var mon = live.get(i);
            bool want_primary = (mon == primary_monitor);
            var existing = windows.get(mon);
            if (existing == null) {
                make_window(mon, want_primary);
            } else if (existing.is_primary != want_primary) {
                existing.destroy();
                windows.remove(mon);
                make_window(mon, want_primary);
            }
        }
    }

    private void make_window(Gdk.Monitor mon, bool is_primary) {
        var user = AccountsClient.load_current_user();
        var win = new LockWindow(app, is_primary, user, logind, backdrop);
        // Assign to the output BEFORE present() so gtk4-session-lock makes it a
        // lock surface on that monitor.
        instance.assign_window_to_monitor(win, mon);
        if (is_primary && win.password != null)
            win.password.submitted.connect((pw) => try_auth(pw));
        win.present();
        windows.set(mon, win);
    }

    private LockWindow? current_primary() {
        if (primary_monitor == null) return null;
        return windows.get(primary_monitor);
    }

    private void focus_primary() {
        var primary = current_primary();
        if (primary != null && primary.password != null)
            primary.password.focus_entry();
    }

    private static bool contains(GenericArray<Gdk.Monitor> arr, Gdk.Monitor m) {
        for (int i = 0; i < arr.length; i++)
            if (arr.get(i) == m) return true;
        return false;
    }
}
