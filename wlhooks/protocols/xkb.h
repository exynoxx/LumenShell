#ifndef WLHOOKS_XKB_H
#define WLHOOKS_XKB_H

#include <stdint.h>
#include <stddef.h>

void xkb_module_init(void);
void xkb_module_cleanup(void);

// Load a new keymap from a memory-mapped fd of size `size`. Replaces any
// previously loaded keymap and resets state. fd is closed by the caller.
// Returns 0 on success, -1 on failure.
int  xkb_load_keymap_from_fd(int fd, uint32_t size);

void xkb_update_modifiers(uint32_t depressed, uint32_t latched,
                          uint32_t locked, uint32_t group);

// Translate a Wayland-protocol keycode into an xkb_keysym_t. Returns 0 if no
// keymap is currently loaded.
uint32_t xkb_translate_keycode(uint32_t keycode);

#endif
