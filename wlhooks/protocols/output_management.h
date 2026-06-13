#ifndef OUTPUT_MANAGEMENT_H
#define OUTPUT_MANAGEMENT_H

#include <stdbool.h>
#include <wayland-client.h>

// In-process wlr-output-management-v1 client. Self-contained: it runs on a
// PRIVATE wl_event_queue so our synchronous roundtrips dispatch only this
// protocol's events and never reenter GDK's default-queue dispatch. This is a
// parallel entry point to wlhooks_init_toplevel_with_display() and shares no
// state with the foreign-toplevel path (it does NOT use registry.c).
//
// Used by lumen-settings' Display page to enumerate outputs and apply a layout
// live, replacing the old wlr-randr CLI shell-out.

// Callback convention matches the register_on_window_* pattern: user_data is
// the trailing argument, so the Vala vapi can expose a bare delegate.
typedef void (*output_mgmt_head_cb)(int idx, const char *name, const char *description,
                                    int enabled, int x, int y, int transform, double scale,
                                    void *user_data);
typedef void (*output_mgmt_mode_cb)(int head_idx, int width, int height, int refresh_mhz,
                                    int preferred, int is_current, void *user_data);
// Stable identity of a head (EDID make/model/serial; any may be ""). Used to
// key remembered display profiles independent of which connector/port is used.
typedef void (*output_mgmt_head_id_cb)(int idx, const char *name, const char *make,
                                       const char *model, const char *serial,
                                       const char *description, void *user_data);
// Fired from the manager `done` handler, but ONLY when the connected SET of
// heads changes (property-only `done`s — including the one our own apply
// triggers — are suppressed). The load-bearing guard against an
// apply->done->apply loop for a headless daemon that re-applies on hotplug.
typedef void (*output_mgmt_outputs_changed_cb)(void *user_data);

// Bind the manager on `display` via a private queue and drain the initial
// head/mode/done burst. Returns 0 if the manager bound, nonzero otherwise.
int  wlhooks_output_mgmt_init(struct wl_display *display);
void wlhooks_output_mgmt_destroy(void);
bool wlhooks_output_mgmt_available(void);

// Register a callback fired when the connected SET of heads changes (hotplug).
// Call after init; the current set is taken as the baseline so it does not fire
// for the already-connected heads. Pass cb=NULL to unregister.
void wlhooks_output_mgmt_register_outputs_changed(output_mgmt_outputs_changed_cb cb,
                                                  void *user_data);

// Main-loop integration for a headless daemon (no GDK pumping the connection):
//   get_fd   -> the wl_display fd to poll for G_IO_IN (-1 if not initialised)
//   dispatch -> dispatch the private queue + flush; returns the wl dispatch
//               count, or <0 on error (caller should tear down).
int  wlhooks_output_mgmt_get_fd(void);
int  wlhooks_output_mgmt_dispatch(void);

// Roundtrip the private queue to pick up any pending changes (call before
// re-enumerating / before building a configuration).
void wlhooks_output_mgmt_refresh(void);

// Replay the current snapshot. `idx` passed to head_cb is the same value to
// pass to for_each_mode().
void wlhooks_output_mgmt_for_each_head(output_mgmt_head_cb cb, void *user_data);
void wlhooks_output_mgmt_for_each_head_identity(output_mgmt_head_id_cb cb, void *user_data);
void wlhooks_output_mgmt_for_each_mode(int head_idx, output_mgmt_mode_cb cb, void *user_data);

// Build + apply a configuration (synchronous).
//   config_begin  -> 0 ok, -1 if no manager / no serial yet
//   config_enable -> matches an existing mode by (w,h,refresh_mhz), else custom
//   config_apply  -> 0 succeeded, 1 failed, 2 cancelled, -1 nothing built
int  wlhooks_output_mgmt_config_begin(void);
void wlhooks_output_mgmt_config_disable(const char *name);
void wlhooks_output_mgmt_config_enable(const char *name, int w, int h, int refresh_mhz,
                                       int x, int y, int transform);
int  wlhooks_output_mgmt_config_apply(void);

#endif // OUTPUT_MANAGEMENT_H
