#include "idle_notify.h"
#include "registry.h"
#include "seat.h"
#include "../generated/ext-idle-notify-v1-client-protocol.h"

#include <stdio.h>

static struct ext_idle_notifier_v1    *notifier     = NULL;
static struct ext_idle_notification_v1 *notification = NULL;

// Vala-side callbacks (function pointer + target), stored across the
// registration's lifetime. Mirrors the output_management.c convention.
static idle_notify_cb s_idled_cb     = NULL;
static void          *s_idled_data   = NULL;
static idle_notify_cb s_resumed_cb   = NULL;
static void          *s_resumed_data = NULL;

static void handle_idled(void *data, struct ext_idle_notification_v1 *n) {
    (void) data; (void) n;
    if (s_idled_cb) s_idled_cb(s_idled_data);
}

static void handle_resumed(void *data, struct ext_idle_notification_v1 *n) {
    (void) data; (void) n;
    if (s_resumed_cb) s_resumed_cb(s_resumed_data);
}

static const struct ext_idle_notification_v1_listener notif_listener = {
    .idled   = handle_idled,
    .resumed = handle_resumed,
};

static void idle_registry_handler(void *data, struct wl_registry *registry,
                                   uint32_t name, const char *interface,
                                   uint32_t version) {
    (void) data; (void) interface; (void) version;
    notifier = wl_registry_bind(registry, name, &ext_idle_notifier_v1_interface, 1);
}

void idle_notify_init(void) {
    registry_add_handler(ext_idle_notifier_v1_interface.name,
                         idle_registry_handler, NULL);
}

void idle_notify_cleanup(void) {
    idle_notify_unregister();
    if (notifier) {
        ext_idle_notifier_v1_destroy(notifier);
        notifier = NULL;
    }
}

bool idle_notify_available(void) {
    return notifier != NULL;
}

int idle_notify_register(uint32_t timeout_ms,
                         idle_notify_cb idled, void *idled_data,
                         idle_notify_cb resumed, void *resumed_data) {
    if (!notifier) {
        fprintf(stderr, "idle_notify: ext_idle_notifier_v1 unavailable\n");
        return -1;
    }
    struct wl_seat *seat = get_wl_seat();
    if (!seat) {
        fprintf(stderr, "idle_notify: no wl_seat bound\n");
        return -1;
    }

    // Replace any previously-armed notification.
    idle_notify_unregister();

    s_idled_cb     = idled;
    s_idled_data   = idled_data;
    s_resumed_cb   = resumed;
    s_resumed_data = resumed_data;

    notification = ext_idle_notifier_v1_get_idle_notification(notifier, timeout_ms, seat);
    if (!notification) return -1;
    ext_idle_notification_v1_add_listener(notification, &notif_listener, NULL);
    return 0;
}

void idle_notify_unregister(void) {
    if (notification) {
        ext_idle_notification_v1_destroy(notification);
        notification = NULL;
    }
}
