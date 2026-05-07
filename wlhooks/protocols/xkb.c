#include "xkb.h"

#include <stdio.h>
#include <sys/mman.h>
#include <xkbcommon/xkbcommon.h>

static struct xkb_context *ctx     = NULL;
static struct xkb_keymap  *keymap  = NULL;
static struct xkb_state   *state   = NULL;

void xkb_module_init(void) {
    if (ctx) return;
    ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (!ctx) {
        fprintf(stderr, "xkb: xkb_context_new failed\n");
    }
}

void xkb_module_cleanup(void) {
    if (state)  { xkb_state_unref(state);   state  = NULL; }
    if (keymap) { xkb_keymap_unref(keymap); keymap = NULL; }
    if (ctx)    { xkb_context_unref(ctx);   ctx    = NULL; }
}

int xkb_load_keymap_from_fd(int fd, uint32_t size) {
    if (!ctx) return -1;

    char *map_shm = mmap(NULL, size, PROT_READ, MAP_SHARED, fd, 0);
    if (map_shm == MAP_FAILED) return -1;

    if (state)  { xkb_state_unref(state);   state  = NULL; }
    if (keymap) { xkb_keymap_unref(keymap); keymap = NULL; }

    keymap = xkb_keymap_new_from_string(ctx, map_shm,
                                        XKB_KEYMAP_FORMAT_TEXT_V1,
                                        XKB_KEYMAP_COMPILE_NO_FLAGS);
    munmap(map_shm, size);

    if (!keymap) return -1;
    state = xkb_state_new(keymap);
    return state ? 0 : -1;
}

void xkb_update_modifiers(uint32_t depressed, uint32_t latched,
                          uint32_t locked, uint32_t group) {
    if (!state) return;
    xkb_state_update_mask(state, depressed, latched, locked, 0, 0, group);
}

uint32_t xkb_translate_keycode(uint32_t keycode) {
    if (!state) return 0;
    return xkb_state_key_get_one_sym(state, keycode + 8);
}
