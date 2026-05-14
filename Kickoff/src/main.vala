int main(string[] args) {
    var app = new Gtk.Application("dev.lumen.kickoff", GLib.ApplicationFlags.DEFAULT_FLAGS);
    app.activate.connect(() => {
        var win = new KickoffWindow(app);
        win.present();
    });
    return app.run(args);
}
