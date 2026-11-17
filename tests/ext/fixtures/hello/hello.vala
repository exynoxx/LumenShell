// Every kind of type valac registers, all inside the id's namespace.
namespace Hello {
    public enum Color { RED, GREEN }
    public errordomain Oops { BAD }
    public interface Greeter : GLib.Object { public abstract string greet (); }
    internal class Hidden : GLib.Object {}
    public struct Point { int x; int y; }

    public class Ext : Lumen.Extension, Greeter {
        public string greet () { return "hi"; }
        public override void enable (Lumen.Context ctx) throws GLib.Error {}
    }
}

public Lumen.Extension lumen_extension_new () {
    return new Hello.Ext ();
}
