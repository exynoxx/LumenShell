#include "activation.h"
#include "registry.h"
#include "seat.h"
#include "layershell.h"
#include "../generated/xdg-activation-v1-client-protocol.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <glib.h>
#include <wayland-client.h>

extern struct wl_display *wl_display;

#define ACTIVATION_MAX_ROUNDTRIPS 4

static struct xdg_activation_v1 *activation = NULL;

typedef struct {
    char *token;   // g_strdup'd so the Vala caller can g_free()
    bool  done;
} token_request_t;

static void token_handle_done(void *data,
                              struct xdg_activation_token_v1 *token_obj,
                              const char *token) {
    token_request_t *req = data;
    req->token = g_strdup(token);
    req->done  = true;
}

static const struct xdg_activation_token_v1_listener token_listener = {
    .done = token_handle_done,
};

static void activation_registry_handler(void *data, struct wl_registry *registry,
                                        uint32_t name, const char *interface,
                                        uint32_t version) {
    activation = wl_registry_bind(registry, name, &xdg_activation_v1_interface, 1);
}

void activation_init(void) {
    registry_add_handler(xdg_activation_v1_interface.name,
                         activation_registry_handler, NULL);
}

void activation_cleanup(void) {
    if (activation) {
        xdg_activation_v1_destroy(activation);
        activation = NULL;
    }
}

bool activation_available(void) {
    return activation != NULL;
}

char *activation_get_token(const char *app_id) {
    if (!activation) return NULL;

    struct xdg_activation_token_v1 *tok =
        xdg_activation_v1_get_activation_token(activation);

    token_request_t req = { .token = NULL, .done = false };
    xdg_activation_token_v1_add_listener(tok, &token_listener, &req);

    uint32_t serial = seat_get_last_serial();
    struct wl_seat *seat = get_wl_seat();
    if (seat && serial != 0)
        xdg_activation_token_v1_set_serial(tok, serial, seat);

    if (app_id && *app_id)
        xdg_activation_token_v1_set_app_id(tok, app_id);

    struct wl_surface *surface = layer_shell_get_surface();
    if (surface)
        xdg_activation_token_v1_set_surface(tok, surface);

    xdg_activation_token_v1_commit(tok);

    // Bounded roundtrip: a misbehaving compositor that never replies must not
    // hang the panel.
    for (int i = 0; !req.done && i < ACTIVATION_MAX_ROUNDTRIPS; i++) {
        if (wl_display_roundtrip(wl_display) < 0) break;
    }
    if (!req.done) {
        fprintf(stderr, "activation: token request timed out\n");
    }

    xdg_activation_token_v1_destroy(tok);
    return req.token;
}

void activation_activate_self(void) {
    if (!activation) return;
    struct wl_surface *surface = layer_shell_get_surface();
    if (!surface) return;

    char *token = activation_get_token(NULL);
    if (!token) return;

    xdg_activation_v1_activate(activation, token, surface);
    g_free(token);
}
