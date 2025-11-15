/* #ifndef TOPLEVEL_UTILITIES_H
#define TOPLEVEL_UTILITIES_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <gio/gio.h>

/* const char *desktop_paths[] = {
    "/usr/share/applications/",
    "/usr/local/share/applications/"
}; */

// Typical search paths in order:
// 1. $XDG_DATA_HOME/applications/  (defaults to ~/.local/share/applications/)
// 2. $XDG_DATA_DIRS/applications/  (defaults to /usr/local/share:/usr/share)

const char *icon_paths[] = {
    "/usr/share/icons/hicolor/48x48/apps/",
    "/usr/share/icons/hicolor/scalable/apps/",
    "/usr/share/pixmaps/"
};
void parse_desktop_dirs(){
    char* xdg_data_dirs = getenv("XDG_DATA_DIRS");
    if (!xdg_data_dirs) {
        xdg_data_dirs = "/usr/local/share:/usr/share";
    }

    char *token = strtok(xdg_data_dirs, ":");
    
    while (token != NULL) {
        token = strtok(NULL, ":"); // + /applications
    }

}

void load_icon(){

char* find_icon_with_gio(const char* icon_name) {
    GtkIconTheme* theme = gtk_icon_theme_get_default();
    GtkIconInfo* info = gtk_icon_theme_lookup_icon(theme, icon_name, 48, 0);
    if (info) {
        const char* path = gtk_icon_info_get_filename(info);
        char* result = strdup(path);
        g_object_unref(info);
        return result;
    }
    return NULL;
}
}

#endif */