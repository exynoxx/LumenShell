#include <stdbool.h>
#include <GLES2/gl2.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>

#include "liblayershell.h"
#include "graphics.h"

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

// Common Fedora icon paths
const char* ICON_PATHS[] = {
    "/usr/share/icons/hicolor/48x48/apps/fedora-logo-icon.png",
    "/usr/share/icons/Adwaita/48x48/apps/utilities-terminal.png",
    "/usr/share/icons/Adwaita/48x48/apps/system-file-manager.png",
    "/usr/share/icons/Adwaita/48x48/apps/system-software-install.png",
    "/usr/share/icons/Adwaita/48x48/places/folder.png",
    "/usr/share/icons/Adwaita/48x48/status/dialog-information.png",
    "/usr/share/icons/Adwaita/48x48/status/dialog-warning.png",
    "/usr/share/icons/hicolor/scalable/apps/org.gnome.Settings.svg",
    NULL
};

// Try to find and load an icon
bool load_system_icon(g2d_texture *tex, const char **attempted_path) {
    for (int i = 0; ICON_PATHS[i] != NULL; i++) {
        int width, height, channels;
        unsigned char *data = stbi_load(ICON_PATHS[i], &width, &height, &channels, 0);
        
        if (data) {
            printf("✓ Successfully loaded: %s\n", ICON_PATHS[i]);
            printf("  Size: %dx%d, Channels: %d\n", width, height, channels);
            
            bool success = g2d_load_texture(tex, data, width, height, channels);
            stbi_image_free(data);
            
            if (attempted_path) {
                *attempted_path = ICON_PATHS[i];
            }
            
            return success;
        } else {
            printf("✗ Not found: %s\n", ICON_PATHS[i]);
        }
    }
    
    return false;
}

// Load a specific icon by path
bool load_icon_from_path(g2d_texture *tex, const char *path) {
    int width, height, channels;
    unsigned char *data = stbi_load(path, &width, &height, &channels, 0);
    
    if (!data) {
        fprintf(stderr, "Failed to load icon: %s\n", path);
        fprintf(stderr, "Reason: %s\n", stbi_failure_reason());
        return false;
    }
    
    printf("✓ Loaded: %s\n", path);
    printf("  Size: %dx%d, Channels: %d\n", width, height, channels);
    
    bool success = g2d_load_texture(tex, data, width, height, channels);
    stbi_image_free(data);
    
    return success;
}

int main() {

    int width = 1920;  // typical screen width, adjust as needed
    int height = 100;

    init_layer_shell("panel", width, 100);
    EGLDisplay egl_display = get_egl_display();
    EGLSurface egl_surface = get_egl_surface();
    EGLContext egl_context = get_egl_context();
    struct wl_display *display = get_wl_display();

    g2d_context ctx;
    g2d_init(&ctx, width, height);

    // Load icon
    g2d_texture icon_tex;
    const char *loaded_path = NULL;
    bool icon_loaded = false;
    
    // If no argument or loading failed, try system icons
    if (!icon_loaded) {
        printf("\nSearching for Fedora system icons...\n");
        icon_loaded = load_system_icon(&icon_tex, &loaded_path);
    }
    
    if (!icon_loaded) {
        fprintf(stderr, "\n❌ Could not load any system icon!\n");
        g2d_cleanup(&ctx);
        return -1;
    }
    
    printf("\n🎨 Icon loaded successfully!\n");
    printf("Press ESC to exit\n\n");

    // --- Render loop ---
    while (wl_display_dispatch(display) != -1) {
        g2d_begin_frame(&ctx);
        
        // Draw icon at original size
        g2d_set_color(&ctx, 1.0f, 1.0f, 1.0f, 1.0f);
        g2d_draw_texture(&ctx, &icon_tex, 100, 0, icon_tex.width, icon_tex.height);
        
        // Draw icon scaled 2x
        g2d_draw_texture(&ctx, &icon_tex, 300, 0, icon_tex.width * 2, icon_tex.height * 2);
        
        // Draw icon scaled 3x
        g2d_draw_texture(&ctx, &icon_tex, 550, 0, icon_tex.width * 3, icon_tex.height * 3);
        
        g2d_end_frame();
        eglSwapBuffers(egl_display, egl_surface);
    }

    // --- Cleanup ---
    destroy_layer_shell();
    return 0;
}