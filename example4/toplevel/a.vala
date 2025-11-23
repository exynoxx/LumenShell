using Gtk;
using Gdk;
using GLib;

int main (string[] args) {
    print("=== GTK4 Wayland Diagnostic ===\n");

    // Step 1: Print environment variables
    print("Environment:\n");
    print("XDG_SESSION_TYPE=%s\n", Environment.get_variable("XDG_SESSION_TYPE"));
    print("WAYLAND_DISPLAY=%s\n", Environment.get_variable("WAYLAND_DISPLAY"));
    print("DISPLAY=%s\n", Environment.get_variable("DISPLAY"));
    print("\n");

    // Step 2: Initialize GTK
    Gtk.init(ref args);
    print("GTK initialized\n");

    // Step 3: Get default display
    Gdk.Display gdk_display = Gdk.Display.get_default();
    if (gdk_display == null) {
        print("GDK Display is null!\n");
        return 1;
    }

    print("GDK Display type: %s\n", gdk_display());

    // Step 4: Check runtime type
    if (gdk_display is Gdk.Wayland.Display) {
        print("GTK thinks we are running on Wayland\n");

        // Safe cast to Wayland display
        Gdk.Wayland.Display wayland_display = gdk_display as Gdk.Wayland.Display;
        var wl = wayland_display.get_wl_display();
        print("Got wl_display pointer: %p\n", wl);
    } 
     else {
        print("Unknown GDK display backend\n");
    }

    // Step 5: Create a simple window to ensure backend is fully initialized
    var window = new Gtk.Window();
    window.realize.connect(() => {
        print("Window realized\n");

        Gdk.Display win_display = window.get_display();
        print("Window get_display() type: %s\n", win_display.get_type_name());
        print("GDK_IS_WAYLAND_DISPLAY: %s\n",
              GDK_IS_WAYLAND_DISPLAY(win_display) ? "TRUE" : "FALSE");
    });
    window.show();

    Gtk.main();
    return 0;
}
