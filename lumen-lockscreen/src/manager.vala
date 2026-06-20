using Gtk;

// LockManager — the lock state machine. Owns the GtkSessionLock instance, one
// LockWindow per output, the PAM auth orchestration, and the logind bridge.
//
// Triggers all converge here: DBus (LockService), logind Session.Lock/Unlock,
// PrepareForSleep, the password Enter on the primary window, and idle (via
// ext-idle-notify-v1 bound through wlhooks — see IdleWatcher).
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

        // Bind ext-idle-notify-v1 on GTK's wl_display for idle auto-lock.
        init_wlhooks();

        // Idle auto-lock. Arm immediately; disarm while locked so it can't
        // re-fire, re-arm on unlock.
        this.idle = new IdleWatcher((uint32) Theme.idle_timeout_ms);
        idle.idled.connect(() => { DiagLog.log("trigger: idle timeout"); lock_now(); });
        idle.arm();

        // Warm the blurred-wallpaper cache and the user-identity lookup off the
        // main loop so the first lock doesn't pay the GL-realize + blur cost nor
        // the system-bus AccountsService roundtrip (both cached for the session).
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
                lock_now_immediate();   // no transition — screen is powering off
                // Lock request is in flight; let the kernel proceed to sleep.
                logind.release_delay_inhibitor();
            } else {
                // Re-arm for the next sleep cycle.
                logind.take_delay_inhibitor();
            }
        });
    }

    // ---- lock --------------------------------------------------------------

    private void init_wlhooks() {
        var gdk = Gdk.Display.get_default();
        if (gdk is Gdk.Wayland.Display) {
            unowned Wl.Display wl = ((Gdk.Wayland.Display) gdk).get_wl_display();
            // Bind ext-idle-notify-v1 (idle auto-lock) on GTK's wl_display.
            if (WLHooks.idle_notify_init(wl) == 0) {
                DiagLog.log("wlhooks: idle_notify_init ok");
                return;
            }
        }
        warning("lumen-lockscreen: wlhooks init failed; idle auto-lock disabled");
    }

    // Lock the session. Used by every trigger (Win+L/DBus, logind Lock, idle,
    // PrepareForSleep). The lock surfaces simply appear — there is no pre-lock
    // transition.
    public void lock_now() {
        DiagLog.log("lock requested: (is_locked=%s instance=%s)",
            is_locked.to_string(), (instance != null).to_string());

        // Re-entrancy guard: already locked or a lock in flight.
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

    // Kept for the PrepareForSleep path; identical to lock_now (no transition).
    public void lock_now_immediate() {
        lock_now();
    }

    private void begin_lock() {
        if (is_locked || instance != null) return;
        // Card backdrop: the wallpaper blurred once and cached (BlurredWallpaper).
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
        // gtk4-session-lock emits `unlocked` from inside its unlock() call
        // BEFORE it sends ext_session_lock_v1.unlock_and_destroy to the
        // compositor and BEFORE it unmaps + gtk_window_destroy()s our lock
        // windows itself (see clear_lock_state() in the library). Destroying
        // the windows from here would tear down the lock-surface wl_surfaces
        // while the session is *still* locked — Wayfire is then briefly locked
        // with no lock surface to draw, which flashes a stale frame for an
        // instant before the real unlock reveals the desktop. So we must NOT
        // touch the windows here; the library destroys them for us, correctly
        // ordered after unlock_and_destroy. We only drop our bookkeeping.
        release_bookkeeping();
        instance = null;
        is_locked = false;
        failures = 0;
        idle.arm();      // re-arm idle auto-lock for the unlocked session
        DiagLog.log("unlocked: session unlocked, idle re-armed");
        unlocked();
    }

    // Drop the manager's references and the hotplug watch WITHOUT destroying the
    // lock windows — gtk4-session-lock owns their lifecycle once they are lock
    // surfaces. The GtkApplication keeps each window alive until the library's
    // own gtk_window_destroy() runs, so clearing our HashTable here is safe.
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

    // Hard teardown for the `failed` path: the lock was never granted, so the
    // library will NOT destroy anything for us. Destroy whatever we built (a
    // no-op when the lock failed before any surface was created).
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

    // Build/destroy lock windows so there is exactly one per connected output,
    // with the password card on a single primary. Idempotent — safe to call on
    // lock and on every hotplug.
    private void reconcile_monitors() {
        if (instance == null) return;
        var display = Gdk.Display.get_default();
        if (display == null) return;

        var model = display.get_monitors();
        uint n = model.get_n_items();

        // Snapshot the live set.
        var live = new GenericArray<Gdk.Monitor>();
        for (uint i = 0; i < n; i++)
            live.add((Gdk.Monitor) model.get_item(i));

        // Drop windows for monitors that went away.
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

        // Make sure a primary monitor is designated and still present.
        if (primary_monitor == null || !contains(live, primary_monitor))
            primary_monitor = live.get(0);

        // Create or re-role windows so each monitor has the right surface.
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
