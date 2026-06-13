using GLib;

// LockService — org.lumenshell.Lock1, the DBus face of LockManager. Mirrors the
// lumen-osd OsdService pattern (bus-owning done in main.vala). Third parties
// (lumen-lockctl, panel power menu, scripts) call Lock/Unlock/IsLocked; the
// Locked/Unlocked signals let session-aware services observe lock state.
[DBus(name = "org.lumenshell.Lock1")]
public class LockService : Object {

    public signal void Locked();
    public signal void Unlocked();

    private LockManager manager;

    public LockService(LockManager manager) {
        this.manager = manager;
        manager.locked.connect(()   => Locked());
        manager.unlocked.connect(() => Unlocked());
    }

    public void Lock() throws DBusError, IOError {
        manager.lock_now();
    }

    // Drops the lock WITHOUT a password — the caller (loginctl unlock-session,
    // an authenticated agent) is trusted. The password path lives entirely in
    // LockManager.try_auth; it is not exposed on the bus.
    public void Unlock() throws DBusError, IOError {
        manager.unlock_now();
    }

    public bool IsLocked() throws DBusError, IOError {
        return manager.is_locked;
    }
}
