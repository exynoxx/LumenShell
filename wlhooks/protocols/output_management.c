#include "output_management.h"
#include "../generated/wlr-output-management-unstable-v1-client-protocol.h"

#include <stdio.h>
#include <string.h>
#include <stdint.h>

#define OM_MAX_HEADS  16
#define OM_MAX_MODES  128
#define OM_MGR_MAX_VERSION 4   // generated from the v4 XML (adaptive_sync)

typedef struct {
    struct zwlr_output_mode_v1 *proxy;
    int32_t w, h;
    int32_t refresh_mhz;
    bool    preferred;
} om_mode_t;

typedef struct {
    struct zwlr_output_head_v1 *proxy;
    char    name[64];
    char    desc[256];
    bool    enabled;
    int32_t x, y;
    int32_t transform;
    double  scale;
    om_mode_t modes[OM_MAX_MODES];
    int     mode_count;
    struct zwlr_output_mode_v1 *current_mode_proxy;  // resolved to index lazily
    int     current_mode_idx;                        // -1 if none
    bool    finished;
} om_head_t;

static struct wl_display              *s_display  = NULL;
static struct wl_event_queue          *s_queue    = NULL;
static struct wl_registry             *s_registry = NULL;
static struct zwlr_output_manager_v1  *s_manager  = NULL;
static uint32_t s_serial      = 0;
static bool     s_have_serial = false;

static om_head_t s_heads[OM_MAX_HEADS];
static int       s_head_count = 0;

// pending configuration build
static struct zwlr_output_configuration_v1 *s_config = NULL;
static int  s_apply_result = -1;   // -1 pending, 0 ok, 1 failed, 2 cancelled
static bool s_apply_done   = false;

// ---- lookup helpers --------------------------------------------------------

static om_head_t *head_by_name(const char *name) {
    for (int i = 0; i < s_head_count; i++) {
        if (!s_heads[i].finished && strcmp(s_heads[i].name, name) == 0)
            return &s_heads[i];
    }
    return NULL;
}

static void resolve_current_modes(void) {
    for (int i = 0; i < s_head_count; i++) {
        om_head_t *h = &s_heads[i];
        h->current_mode_idx = -1;
        if (!h->current_mode_proxy) continue;
        for (int m = 0; m < h->mode_count; m++) {
            if (h->modes[m].proxy == h->current_mode_proxy) { h->current_mode_idx = m; break; }
        }
    }
}

// ---- mode listener ---------------------------------------------------------

static void mode_size(void *data, struct zwlr_output_mode_v1 *m, int32_t w, int32_t h) {
    (void) m; om_mode_t *mode = data; mode->w = w; mode->h = h;
}
static void mode_refresh(void *data, struct zwlr_output_mode_v1 *m, int32_t r) {
    (void) m; om_mode_t *mode = data; mode->refresh_mhz = r;
}
static void mode_preferred(void *data, struct zwlr_output_mode_v1 *m) {
    (void) m; om_mode_t *mode = data; mode->preferred = true;
}
static void mode_finished(void *data, struct zwlr_output_mode_v1 *m) {
    (void) data; zwlr_output_mode_v1_destroy(m);
}
static const struct zwlr_output_mode_v1_listener mode_listener = {
    .size = mode_size, .refresh = mode_refresh,
    .preferred = mode_preferred, .finished = mode_finished,
};

// ---- head listener ---------------------------------------------------------

static void head_name(void *data, struct zwlr_output_head_v1 *h, const char *name) {
    (void) h; om_head_t *hd = data;
    snprintf(hd->name, sizeof(hd->name), "%s", name ? name : "");
}
static void head_description(void *data, struct zwlr_output_head_v1 *h, const char *d) {
    (void) h; om_head_t *hd = data;
    snprintf(hd->desc, sizeof(hd->desc), "%s", d ? d : "");
}
static void head_physical_size(void *data, struct zwlr_output_head_v1 *h, int32_t w, int32_t hh) {
    (void) data; (void) h; (void) w; (void) hh;
}
static void head_mode(void *data, struct zwlr_output_head_v1 *h, struct zwlr_output_mode_v1 *m) {
    (void) h; om_head_t *hd = data;
    if (hd->mode_count >= OM_MAX_MODES) { zwlr_output_mode_v1_destroy(m); return; }
    om_mode_t *mode = &hd->modes[hd->mode_count++];
    memset(mode, 0, sizeof(*mode));
    mode->proxy = m;
    zwlr_output_mode_v1_add_listener(m, &mode_listener, mode);
}
static void head_enabled(void *data, struct zwlr_output_head_v1 *h, int32_t enabled) {
    (void) h; om_head_t *hd = data; hd->enabled = enabled != 0;
}
static void head_current_mode(void *data, struct zwlr_output_head_v1 *h, struct zwlr_output_mode_v1 *m) {
    (void) h; om_head_t *hd = data; hd->current_mode_proxy = m;
}
static void head_position(void *data, struct zwlr_output_head_v1 *h, int32_t x, int32_t y) {
    (void) h; om_head_t *hd = data; hd->x = x; hd->y = y;
}
static void head_transform(void *data, struct zwlr_output_head_v1 *h, int32_t t) {
    (void) h; om_head_t *hd = data; hd->transform = t;
}
static void head_scale(void *data, struct zwlr_output_head_v1 *h, wl_fixed_t scale) {
    (void) h; om_head_t *hd = data; hd->scale = wl_fixed_to_double(scale);
}
static void head_finished(void *data, struct zwlr_output_head_v1 *h) {
    om_head_t *hd = data; hd->finished = true; zwlr_output_head_v1_destroy(h);
}
static void head_make(void *data, struct zwlr_output_head_v1 *h, const char *s) {
    (void) data; (void) h; (void) s;
}
static void head_model(void *data, struct zwlr_output_head_v1 *h, const char *s) {
    (void) data; (void) h; (void) s;
}
static void head_serial_number(void *data, struct zwlr_output_head_v1 *h, const char *s) {
    (void) data; (void) h; (void) s;
}
static void head_adaptive_sync(void *data, struct zwlr_output_head_v1 *h, uint32_t state) {
    (void) data; (void) h; (void) state;
}
static const struct zwlr_output_head_v1_listener head_listener = {
    .name          = head_name,
    .description   = head_description,
    .physical_size = head_physical_size,
    .mode          = head_mode,
    .enabled       = head_enabled,
    .current_mode  = head_current_mode,
    .position      = head_position,
    .transform     = head_transform,
    .scale         = head_scale,
    .finished      = head_finished,
    .make          = head_make,
    .model         = head_model,
    .serial_number = head_serial_number,
    .adaptive_sync = head_adaptive_sync,
};

// ---- manager listener ------------------------------------------------------

static void mgr_head(void *data, struct zwlr_output_manager_v1 *mgr, struct zwlr_output_head_v1 *h) {
    (void) data; (void) mgr;
    if (s_head_count >= OM_MAX_HEADS) { zwlr_output_head_v1_destroy(h); return; }
    om_head_t *hd = &s_heads[s_head_count++];
    memset(hd, 0, sizeof(*hd));
    hd->proxy = h;
    hd->scale = 1.0;
    hd->current_mode_idx = -1;
    zwlr_output_head_v1_add_listener(h, &head_listener, hd);
}
static void mgr_done(void *data, struct zwlr_output_manager_v1 *mgr, uint32_t serial) {
    (void) data; (void) mgr;
    s_serial = serial; s_have_serial = true;
    resolve_current_modes();
}
static void mgr_finished(void *data, struct zwlr_output_manager_v1 *mgr) {
    (void) data;
    zwlr_output_manager_v1_destroy(mgr);
    if (s_manager == mgr) s_manager = NULL;
}
static const struct zwlr_output_manager_v1_listener manager_listener = {
    .head = mgr_head, .done = mgr_done, .finished = mgr_finished,
};

// ---- registry --------------------------------------------------------------

static void reg_global(void *data, struct wl_registry *r, uint32_t name,
                       const char *iface, uint32_t version) {
    (void) data;
    if (strcmp(iface, zwlr_output_manager_v1_interface.name) == 0 && !s_manager) {
        uint32_t v = version > OM_MGR_MAX_VERSION ? OM_MGR_MAX_VERSION : version;
        s_manager = wl_registry_bind(r, name, &zwlr_output_manager_v1_interface, v);
        zwlr_output_manager_v1_add_listener(s_manager, &manager_listener, NULL);
    }
}
static void reg_remove(void *data, struct wl_registry *r, uint32_t name) {
    (void) data; (void) r; (void) name;
}
static const struct wl_registry_listener registry_listener = {
    .global = reg_global, .global_remove = reg_remove,
};

// ---- config listener -------------------------------------------------------

static void cfg_succeeded(void *d, struct zwlr_output_configuration_v1 *c) {
    (void) d; (void) c; s_apply_result = 0; s_apply_done = true;
}
static void cfg_failed(void *d, struct zwlr_output_configuration_v1 *c) {
    (void) d; (void) c; s_apply_result = 1; s_apply_done = true;
}
static void cfg_cancelled(void *d, struct zwlr_output_configuration_v1 *c) {
    (void) d; (void) c; s_apply_result = 2; s_apply_done = true;
}
static const struct zwlr_output_configuration_v1_listener config_listener = {
    .succeeded = cfg_succeeded, .failed = cfg_failed, .cancelled = cfg_cancelled,
};

// ---- public API ------------------------------------------------------------

int wlhooks_output_mgmt_init(struct wl_display *display) {
    if (!display) return -1;
    if (s_manager) return 0;        // already initialised

    s_display = display;
    s_queue = wl_display_create_queue(display);
    if (!s_queue) return -1;

    s_registry = wl_display_get_registry(display);
    // Pin the registry (and therefore the manager/heads/modes bound from it)
    // to our private queue so our roundtrips never dispatch GDK's events.
    wl_proxy_set_queue((struct wl_proxy *) s_registry, s_queue);
    wl_registry_add_listener(s_registry, &registry_listener, NULL);

    // First roundtrip: receive globals + bind the manager.
    if (wl_display_roundtrip_queue(display, s_queue) < 0) return -1;
    if (!s_manager) {
        fprintf(stderr, "output_mgmt: compositor does not expose zwlr_output_manager_v1\n");
        return -1;
    }
    // Second roundtrip: drain the head/mode/done burst.
    wl_display_roundtrip_queue(display, s_queue);
    return 0;
}

bool wlhooks_output_mgmt_available(void) { return s_manager != NULL; }

void wlhooks_output_mgmt_refresh(void) {
    if (s_display && s_queue) wl_display_roundtrip_queue(s_display, s_queue);
}

void wlhooks_output_mgmt_for_each_head(output_mgmt_head_cb cb, void *user_data) {
    if (!cb) return;
    for (int i = 0; i < s_head_count; i++) {
        om_head_t *h = &s_heads[i];
        if (h->finished) continue;
        cb(i, h->name, h->desc, h->enabled ? 1 : 0, h->x, h->y, h->transform, h->scale, user_data);
    }
}

void wlhooks_output_mgmt_for_each_mode(int head_idx, output_mgmt_mode_cb cb, void *user_data) {
    if (!cb || head_idx < 0 || head_idx >= s_head_count) return;
    om_head_t *h = &s_heads[head_idx];
    if (h->finished) return;
    for (int m = 0; m < h->mode_count; m++) {
        om_mode_t *mode = &h->modes[m];
        cb(head_idx, mode->w, mode->h, mode->refresh_mhz,
           mode->preferred ? 1 : 0, (m == h->current_mode_idx) ? 1 : 0, user_data);
    }
}

int wlhooks_output_mgmt_config_begin(void) {
    if (!s_manager || !s_have_serial) return -1;
    if (s_config) { zwlr_output_configuration_v1_destroy(s_config); s_config = NULL; }
    s_config = zwlr_output_manager_v1_create_configuration(s_manager, s_serial);
    zwlr_output_configuration_v1_add_listener(s_config, &config_listener, NULL);
    s_apply_result = -1;
    s_apply_done = false;
    return 0;
}

void wlhooks_output_mgmt_config_disable(const char *name) {
    if (!s_config) return;
    om_head_t *h = head_by_name(name);
    if (!h) { fprintf(stderr, "output_mgmt: disable: head '%s' not found\n", name ? name : "(null)"); return; }
    zwlr_output_configuration_v1_disable_head(s_config, h->proxy);
}

void wlhooks_output_mgmt_config_enable(const char *name, int w, int h_, int refresh_mhz,
                                       int x, int y, int transform) {
    if (!s_config) return;
    om_head_t *h = head_by_name(name);
    if (!h) { fprintf(stderr, "output_mgmt: enable: head '%s' not found\n", name ? name : "(null)"); return; }

    struct zwlr_output_configuration_head_v1 *ch =
        zwlr_output_configuration_v1_enable_head(s_config, h->proxy);

    struct zwlr_output_mode_v1 *match = NULL;
    for (int m = 0; m < h->mode_count; m++) {
        if (h->modes[m].w == w && h->modes[m].h == h_ && h->modes[m].refresh_mhz == refresh_mhz) {
            match = h->modes[m].proxy; break;
        }
    }
    if (match) zwlr_output_configuration_head_v1_set_mode(ch, match);
    else       zwlr_output_configuration_head_v1_set_custom_mode(ch, w, h_, refresh_mhz);

    zwlr_output_configuration_head_v1_set_position(ch, x, y);
    zwlr_output_configuration_head_v1_set_transform(ch, transform);
}

int wlhooks_output_mgmt_config_apply(void) {
    if (!s_config) return -1;
    zwlr_output_configuration_v1_apply(s_config);
    s_apply_done = false;
    s_apply_result = -1;
    while (!s_apply_done) {
        if (wl_display_roundtrip_queue(s_display, s_queue) < 0) break;
    }
    int r = s_apply_result;
    zwlr_output_configuration_v1_destroy(s_config);
    s_config = NULL;
    return (r < 0) ? 1 : r;   // treat an interrupted wait as failure
}

void wlhooks_output_mgmt_destroy(void) {
    if (s_config) { zwlr_output_configuration_v1_destroy(s_config); s_config = NULL; }
    for (int i = 0; i < s_head_count; i++) {
        om_head_t *h = &s_heads[i];
        for (int m = 0; m < h->mode_count; m++)
            if (h->modes[m].proxy) zwlr_output_mode_v1_destroy(h->modes[m].proxy);
        if (h->proxy && !h->finished) zwlr_output_head_v1_destroy(h->proxy);
    }
    s_head_count = 0;
    if (s_manager)  { zwlr_output_manager_v1_destroy(s_manager); s_manager = NULL; }
    if (s_registry) { wl_registry_destroy(s_registry); s_registry = NULL; }
    if (s_queue)    { wl_event_queue_destroy(s_queue); s_queue = NULL; }
    s_display = NULL;
    s_have_serial = false;
}
