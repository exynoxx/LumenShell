using LumenCommon;

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
        DiagLog.log("trigger: DBus Lock");
        manager.lock_now();
    }

    // Drops the lock WITHOUT a password — callers are trusted. The password path
    // (LockManager.try_auth) is never exposed on the bus.
    public void Unlock() throws DBusError, IOError {
        DiagLog.log("trigger: DBus Unlock");
        manager.unlock_now();
    }

    public bool IsLocked() throws DBusError, IOError {
        return manager.is_locked;
    }
}
