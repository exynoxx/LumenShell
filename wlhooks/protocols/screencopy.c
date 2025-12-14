#define _GNU_SOURCE
#include "screencopy.h"
#include "registry.h"
#include "../generated/wlr-screencopy-unstable.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

static struct zwlr_screencopy_manager_v1 *screencopy_manager = NULL;
struct wl_output *wl_output;
struct wl_shm *wl_shm = NULL;

typedef struct {
    struct zwlr_screencopy_frame_v1 *frame;
    struct wl_buffer *buffer;
    screencopy_buffer_t *result;
    screencopy_ready_callback ready_cb;
    screencopy_failed_callback failed_cb;
    void *user_data_ready;
    void *user_data_fail;
    int shm_fd;
    void *shm_data;
    size_t shm_size;
} screencopy_state_t;

static void handle_shm_registry(void *user_data, struct wl_registry *registry,
                                uint32_t name, const char *interface,
                                uint32_t version) {
    wl_shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    printf("wl_shm bound successfully\n");
}

static int create_shm_file(void) {
    int fd;
    
    fd = memfd_create("screencopy-shm", MFD_CLOEXEC);
    if (fd >= 0)
        return fd;

    return -1;
}

static int allocate_shm(screencopy_state_t *state, size_t size) {
    state->shm_fd = create_shm_file();
    if (state->shm_fd < 0) {
        fprintf(stderr, "Failed to create shm file\n");
        return -1;
    }

    if (ftruncate(state->shm_fd, size) < 0) {
        fprintf(stderr, "Failed to truncate shm file: %s\n", strerror(errno));
        close(state->shm_fd);
        return -1;
    }

    state->shm_data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, state->shm_fd, 0);
    if (state->shm_data == MAP_FAILED) {
        fprintf(stderr, "Failed to mmap shm file: %s\n", strerror(errno));
        close(state->shm_fd);
        return -1;
    }

    state->shm_size = size;
    return 0;
}

static void frame_handle_buffer(void *data,
                                struct zwlr_screencopy_frame_v1 *frame,
                                uint32_t format,
                                uint32_t width,
                                uint32_t height,
                                uint32_t stride) {
    screencopy_state_t *state = data;

    printf("frame_handle_buffer\n");
    
    state->result->width = width;
    state->result->height = height;
    state->result->stride = stride;
    state->result->format = format;

    size_t size = stride * height;
    
    if (allocate_shm(state, size) < 0) {
        if (state->failed_cb) {
            state->failed_cb(state->user_data_fail);
        }
        return;
    }

    // Get shm pool
    if (!wl_shm) {
        fprintf(stderr, "wl_shm not available\n");
        if (state->failed_cb) {
            state->failed_cb(state->user_data_fail);
        }
        return;
    }

    struct wl_shm_pool *pool = wl_shm_create_pool(wl_shm, state->shm_fd, size);
    state->buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride, format);
    wl_shm_pool_destroy(pool);

    zwlr_screencopy_frame_v1_copy(frame, state->buffer);
}

static void frame_handle_flags(void *data,
                               struct zwlr_screencopy_frame_v1 *frame,
                               uint32_t flags) {
    // Handle flags if needed
}

static void frame_handle_ready(void *data,
                              struct zwlr_screencopy_frame_v1 *frame,
                              uint32_t tv_sec_hi,
                              uint32_t tv_sec_lo,
                              uint32_t tv_nsec) {
    screencopy_state_t *state = data;
    

    // Copy data to result buffer
    state->result->data = malloc(state->shm_size);
    if (state->result->data) {
        memcpy(state->result->data, state->shm_data, state->shm_size);
        
        if (state->ready_cb) {
            printf("callback\n");
            state->ready_cb(state->result, state->user_data_ready);
        }
    } else {
        fprintf(stderr, "Failed to allocate result buffer\n");
        if (state->failed_cb) {
            state->failed_cb(state->user_data_fail);
        }
    }

    // Cleanup
    if (state->shm_data) {
        munmap(state->shm_data, state->shm_size);
    }
    if (state->shm_fd >= 0) {
        close(state->shm_fd);
    }
    if (state->buffer) {
        wl_buffer_destroy(state->buffer);
    }
    if (state->frame) {
        zwlr_screencopy_frame_v1_destroy(state->frame);
    }
    free(state->result);
    free(state);
}

static void frame_handle_failed(void *data,
                               struct zwlr_screencopy_frame_v1 *frame) {
    screencopy_state_t *state = data;
    
    fprintf(stderr, "Screencopy failed\n");
    
    if (state->failed_cb) {
        state->failed_cb(state->user_data_fail);
    }

    // Cleanup
    if (state->shm_data) {
        munmap(state->shm_data, state->shm_size);
    }
    if (state->shm_fd >= 0) {
        close(state->shm_fd);
    }
    if (state->buffer) {
        wl_buffer_destroy(state->buffer);
    }
    if (state->frame) {
        zwlr_screencopy_frame_v1_destroy(state->frame);
    }
    free(state->result);
    free(state);
}

static const struct zwlr_screencopy_frame_v1_listener frame_listener = {
    .buffer = frame_handle_buffer,
    .flags = frame_handle_flags,
    .ready = frame_handle_ready,
    .failed = frame_handle_failed
};

static void screencopy_registry_handler(void *data, struct wl_registry *registry,
                                       uint32_t name, const char *interface,
                                       uint32_t version) {
    screencopy_manager = wl_registry_bind(registry, name,
                                         &zwlr_screencopy_manager_v1_interface, 3);
}

// Somewhere globally or in your context struct

static void output_handler(void *user_data, struct wl_registry *registry,
                           uint32_t name, const char *interface, uint32_t version) {
    wl_output = wl_registry_bind(registry, name, &wl_output_interface, version);
}

void screencopy_init(void) {
    registry_add_handler("zwlr_screencopy_manager_v1", screencopy_registry_handler, NULL);
    registry_add_handler("wl_output", output_handler, NULL);
    registry_add_handler("wl_shm", handle_shm_registry, NULL);
}

void screencopy_cleanup(void) {
    if (screencopy_manager) {
        zwlr_screencopy_manager_v1_destroy(screencopy_manager);
        screencopy_manager = NULL;
    }
    if (wl_shm) {
        wl_shm_destroy(wl_shm);
        wl_shm = NULL;
    }
}

void screencopy_capture(screencopy_ready_callback ready_cb,
                       void *user_data_ready,
                       screencopy_failed_callback failed_cb,
                       void *user_data_fail) {
    if (!screencopy_manager) {
        fprintf(stderr, "Screencopy manager not available\n");
        if (failed_cb) {
            failed_cb(user_data_fail);
        }
        return;
    }

    screencopy_state_t *state = calloc(1, sizeof(screencopy_state_t));
    state->result = calloc(1, sizeof(screencopy_buffer_t));
    state->ready_cb = ready_cb;
    state->failed_cb = failed_cb;
    state->user_data_ready = user_data_ready;
    state->user_data_fail = user_data_fail;
    state->shm_fd = -1;

    state->frame = zwlr_screencopy_manager_v1_capture_output(screencopy_manager, 0, wl_output);
    zwlr_screencopy_frame_v1_add_listener(state->frame, &frame_listener, state);
}

void screencopy_buffer_free(screencopy_buffer_t *buffer) {
    if (buffer) {
        free(buffer->data);
        buffer->data = NULL;
    }
}