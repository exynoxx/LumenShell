// liblumen-ext core logic + panel tray-order resolution. Light by design:
// integration is verified by running the panel with a real extension.
class Dummy : GLib.Object {}

Lumen.Manifest manifest (string json) throws GLib.Error {
    var p = new Json.Parser ();
    p.load_from_data (json);
    return Lumen.Manifest.parse (p.get_root ().get_object (), "/tmp");
}

void test_manifest () throws GLib.Error {
    var m = manifest ("""{"id":"tray-wedge","name":"W","version":"1","api":1,
        "provides":["tray.presenter"],
        "params":{"height":{"type":"int","default":320,"min":100,"max":800}}}""");
    assert (m.provides.length == 1 && m.parameters.length == 1);
    assert (m.type_namespace () == "TrayWedge" && m.symbol_prefix () == "tray_wedge_");

    try { manifest ("""{"id":"Tray Wedge","name":"W","version":"1","api":1}"""); assert_not_reached (); }
    catch (Lumen.ManifestError.BAD_ID e) {}
    try { manifest ("""{"id":"w","name":"W","version":"1","api":2}"""); assert_not_reached (); }
    catch (Lumen.ManifestError.API_MISMATCH e) {}

    // Param: config value clamped to max, wrong type falls back to default.
    var cfg = Lumen.ExtensionConfig.from_json ("""{"params":{"tray-wedge":{"height":9999}}}""");
    var ctx = new Lumen.Context (m, new Lumen.Registry (cfg), cfg, null);
    assert (ctx.param_int ("height") == 800);
    cfg = Lumen.ExtensionConfig.from_json ("""{"params":{"tray-wedge":{"height":"tall"}}}""");
    ctx = new Lumen.Context (m, new Lumen.Registry (cfg), cfg, null);
    assert (ctx.param_int ("height") == 320);
}

void test_registry () {
    var cfg = Lumen.ExtensionConfig.from_json ("""{"slots":{"tray.presenter":"b"},"disabled":["clock"]}""");
    assert (!cfg.is_enabled ("clock") && cfg.is_enabled ("x"));
    assert (Lumen.ExtensionConfig.load ("/nonexistent").active_for ("tray.presenter") == null);

    var r = new Lumen.Registry (cfg);
    r.declare ("tray.presenter", Lumen.Cardinality.ONE);
    var a = new Dummy ();
    var b = new Dummy ();
    r.provide ("tray.presenter", "a", a);
    r.provide ("tray.presenter", "b", b);
    assert (r.active ("tray.presenter") == b);       // config choice wins
    int changed = 0;
    r.changed.connect (() => changed++);
    r.withdraw ("b");
    assert (changed == 1 && r.active ("tray.presenter") == a);   // falls back to first
    r.provide ("nope", "a", a);                       // undeclared: ignored
    assert (r.all ("nope").length == 0);
}

void test_tray_order () {
    PanelConfig.tray_order = { "clock" };
    PanelConfig.tray_disabled = { "wifi" };
    // Catalog ids fill in around "clock"; extension applet "myext" is kept, at the end.
    var got = string.joinv (",", PanelConfig.tray_enabled_order ({ "wifi", "clock", "myext" }));
    assert (got == "clock,myext");
}

void test_shape () {
    var r = Lumen.ShapedSurface.bands (Gsk.Path.parse ("M0 320 L320 0 L640 320 Z"), 640, 320, 4);
    assert (r.contains_point (320, 300) && !r.contains_point (10, 10));
}

// Builds fixture <name> with the real valac; returns the .so or rethrows.
string build_fixture (Lumen.Compiler c, string name) throws GLib.Error {
    var m = Lumen.Manifest.load (Path.build_filename (Environment.get_variable ("EXT_FIXTURES"), name));
    var loop = new MainLoop ();
    string? so = null;
    GLib.Error? err = null;
    c.build.begin (m, null, (o, res) => {
        try { so = c.build.end (res); } catch (GLib.Error e) { err = e; }
        loop.quit ();
    });
    loop.run ();
    if (err != null) throw err;
    return so;
}

void test_build () throws GLib.Error {
    var c = new Lumen.Compiler (DirUtils.make_tmp ("ext-cache-XXXXXX"),
                                Environment.get_variable ("LUMEN_EXT_VAPIDIR"),
                                Environment.get_variable ("LUMEN_EXT_PCDIR"));
    var so = build_fixture (c, "hello");
    assert (FileUtils.test (so, FileTest.EXISTS));
    Posix.Stat st1, st2;
    Posix.stat (so, out st1);
    assert (build_fixture (c, "hello") == so);        // cache hit: not rebuilt
    Posix.stat (so, out st2);
    assert (st1.st_mtime == st2.st_mtime && st1.st_ino == st2.st_ino);
    assert (Lumen.Loader.load (so) != null);

    try { build_fixture (c, "bad"); assert_not_reached (); }
    catch (Lumen.CompileError.BAD_TYPES e) { assert ("wedge_get_type" in e.message); }
}

int main () {
    try { test_manifest (); } catch (GLib.Error e) { error (e.message); }
    test_registry ();
    test_tray_order ();
    test_shape ();
    try { test_build (); } catch (GLib.Error e) { error (e.message); }
    return 0;
}
