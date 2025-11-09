using LayerShell;

public static int main(string[] args) {
    
    int width = 1920;
    int height = 50;

    LayerShell.init("panel", width, height, BOTTOM, true);
    var mouse_info = LayerShell.seat_mouse_info();
    var ctx = new DrawKit.Context(width, height);

    while (LayerShell.display_dispatch_blocking() != -1) {

        UI.Draw(ctx, mouse_info);
        LayerShell.swap_buffers();
    }

    return 0;
}


/*  print("Searching for app_id: %s\n", app_id);
    
    string? icon_path = DesktopFileHelper.get_icon_path_from_app_id(app_id, size);
    
    if (icon_path != null) {
        print("✓ Icon found: %s\n", icon_path);
    } else {
        print("✗ Icon not found\n");
    }  */