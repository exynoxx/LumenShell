[DBus(name = "org.lumenshell.Lock1")]
public interface LockProxy : Object {
    public abstract void Lock()   throws DBusError, IOError;
    public abstract void Unlock() throws DBusError, IOError;
    public abstract bool IsLocked() throws DBusError, IOError;
}
