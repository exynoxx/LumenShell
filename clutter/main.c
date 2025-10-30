#include <clutter/clutter.h>
#include <wayland-client.h>
#include <gdk/gdkwayland.h>
#include "wlr-layer-shell-unstable-v1-client-protocol.h"

struct {
    struct wl_display *display;
    struct wl_registry *registry;
    struct zwlr_layer_shell_v1 *layer_shell;
    struct wl_output *output;
    struct wl_surface *wl_surface;
    struct zwlr_layer_surface_v1 *layer_surface;
} wl_globals;

static void registry_handle_global(void *data, struct wl_registry *registry,
                                   uint32_t name, const char *interface,
                                   uint32_t version) {
    if (strcmp(interface, zwlr_layer_shell_v1_interface.name) == 0) {
        wl_globals.layer_shell = wl_registry_bind(registry, name,
                                                   &zwlr_layer_shell_v1_interface, 4);
    } else if (strcmp(interface, wl_output_interface.name) == 0) {
        if (!wl_globals.output) {
            wl_globals.output = wl_registry_bind(registry, name,
                                                 &wl_output_interface, 4);
        }
    }
}

static void registry_handle_global_remove(void *data, struct wl_registry *registry,
                                          uint32_t name) {
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_handle_global,
    .global_remove = registry_handle_global_remove,
};

static void layer_surface_configure(void *data, struct zwlr_layer_surface_v1 *surface,
                                    uint32_t serial, uint32_t w, uint32_t h) {
    zwlr_layer_surface_v1_ack_configure(surface, serial);
}

static void layer_surface_closed(void *data, struct zwlr_layer_surface_v1 *surface) {
    clutter_main_quit();
}

static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
    .configure = layer_surface_configure,
    .closed = layer_surface_closed,
};

static gboolean on_stage_paint(ClutterActor *actor, gpointer user_data) {
    return FALSE;
}

int main(int argc, char *argv[]) {
    ClutterActor *stage, *rect, *text;
    ClutterColor bg_color = { 26, 26, 46, 255 };
    ClutterColor text_color = { 255, 255, 255, 255 };
    
    // Initialize Clutter
    clutter_init(&argc, &argv);
    
    // Get Wayland display from Clutter's GDK backend
    GdkDisplay *gdk_display = gdk_display_get_default();
    if (!GDK_IS_WAYLAND_DISPLAY(gdk_display)) {
        g_error("Not running on Wayland");
        return 1;
    }
    
    wl_globals.display = gdk_wayland_display_get_wl_display(gdk_display);
    
    // Get Wayland registry and bind to layer shell
    wl_globals.registry = wl_display_get_registry(wl_globals.display);
    wl_registry_add_listener(wl_globals.registry, &registry_listener, NULL);
    wl_display_roundtrip(wl_globals.display);
    
    if (!wl_globals.layer_shell) {
        g_error("Layer shell protocol not available");
        return 1;
    }
    
    // Create Clutter stage
    stage = clutter_stage_new();
    clutter_stage_set_title(CLUTTER_STAGE(stage), "Clutter Panel");
    clutter_actor_set_size(stage, 1920, 50);
    clutter_actor_set_background_color(stage, &bg_color);
    
    // Get the underlying Wayland surface from Clutter's window
    ClutterBackend *backend = clutter_get_default_backend();

    ClutterStageWayland *stage_wl = CLUTTER_STAGE_COGL(stage);
    wl_globals.wl_surface = clutter_wayland_stage_get_wl_surface(CLUTTER_STAGE(stage));
    
    if (!wl_globals.wl_surface) {
        g_error("Failed to get Wayland surface from Clutter stage");
        return 1;
    }
    
    // Create layer shell surface
    wl_globals.layer_surface = zwlr_layer_shell_v1_get_layer_surface(
        wl_globals.layer_shell,
        wl_globals.wl_surface,
        wl_globals.output,
        ZWLR_LAYER_SHELL_V1_LAYER_TOP,
        "clutter-panel"
    );
    
    if (!wl_globals.layer_surface) {
        g_error("Failed to create layer surface");
        return 1;
    }
    
    zwlr_layer_surface_v1_add_listener(wl_globals.layer_surface,
                                       &layer_surface_listener, NULL);
    
    // Configure layer surface
    zwlr_layer_surface_v1_set_size(wl_globals.layer_surface, 0, 50);
    zwlr_layer_surface_v1_set_anchor(wl_globals.layer_surface,
                                     1 |
                                     2 |
                                     4);
    zwlr_layer_surface_v1_set_exclusive_zone(wl_globals.layer_surface, 50);
    
    wl_surface_commit(wl_globals.wl_surface);
    wl_display_roundtrip(wl_globals.display);
    
    // Add Clutter content (example: colored rectangles and text)
    rect = clutter_actor_new();
    clutter_actor_set_size(rect, 100, 50);
    clutter_actor_set_background_color(rect, &(ClutterColor){ 100, 150, 255, 255 });
    clutter_actor_add_child(stage, rect);
    
    text = clutter_text_new_with_text("Monospace 16", "Clutter Panel");
    clutter_text_set_color(CLUTTER_TEXT(text), &text_color);
    clutter_actor_set_position(text, 120, 15);
    clutter_actor_add_child(stage, text);
    
    // Show stage
    clutter_actor_show(stage);
    
    g_signal_connect(stage, "paint", G_CALLBACK(on_stage_paint), NULL);
    
    clutter_main();
    
    return 0;
}