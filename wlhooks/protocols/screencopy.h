#ifndef SCREENCOPY_H
#define SCREENCOPY_H

#include <wayland-client.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint32_t width;
    uint32_t height;
    uint32_t stride;
    uint32_t format;
    uint8_t *data;
} screencopy_buffer_t;

typedef void (*screencopy_ready_callback)(screencopy_buffer_t *buffer, void *user_data);
typedef void (*screencopy_failed_callback)(void *user_data);

void screencopy_init(void);
void screencopy_cleanup(void);

// Capture the entire output
void screencopy_capture(screencopy_ready_callback ready_cb,
                       void *user_data_ready,
                       screencopy_failed_callback failed_cb,
                       void *user_data_fail);

// Free buffer data after use
void screencopy_buffer_free(screencopy_buffer_t *buffer);

#endif // SCREENCOPY_H