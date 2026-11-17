// Global-namespace type: must be rejected (GType name could clash).
public class Wedge : Lumen.Extension {
    public override void enable (Lumen.Context ctx) throws GLib.Error {}
}

public Lumen.Extension lumen_extension_new () {
    return new Wedge ();
}
