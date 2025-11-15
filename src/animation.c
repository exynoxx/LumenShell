/* #include <stdlib.h>
//#include <cstdint>

typedef struct {
    float x, y;        // current position
    float scale;       // current scale
    float rotation;    // current rotation in degrees
} Transform;

typedef struct {
    Transform current;
    Transform start;
    Transform end;
    float duration;    // in seconds
    float elapsed;     // time passed since animation start
    int active;        // 0 = done, 1 = animating
} Animation;

typedef struct {
    Animation* animations;
    int count;
} AnimationManager;

void update_animation(Animation* anim, float dt) {
    if (!anim->active) return;

    anim->elapsed += dt;
    float t = anim->elapsed / anim->duration;
    if (t >= 1.0f) {
        t = 1.0f;
        anim->active = 0;
    }

    // Linear interpolation
    anim->current.x = anim->start.x + (anim->end.x - anim->start.x) * t;
    anim->current.y = anim->start.y + (anim->end.y - anim->start.y) * t;
    anim->current.scale = anim->start.scale + (anim->end.scale - anim->start.scale) * t;
    anim->current.rotation = anim->start.rotation + (anim->end.rotation - anim->start.rotation) * t;
}

uint32_t last_time = 0;

void frame_done(void *data, struct wl_callback *cb, uint32_t time_ms) {
    uint32_t *last = (uint32_t*)data;
    float dt = (time_ms - *last) / 1000.0f;
    *last = time_ms;

    update_animations(dt);
    draw_scene();

    wl_callback_destroy(cb);
    frame_callback = wl_surface_frame(surface);
    wl_callback_add_listener(frame_callback, &frame_listener, last);
}


void update_animations(AnimationManager* mgr, float dt) {
    for (int i = 0; i < mgr->count; ++i)
        update_animation(&mgr->animations[i], dt);
}

void animate_move(Animation* anim, float x_end, float y_end, float duration) {
    anim->start = anim->current; // start from current state
    anim->end.x = x_end;
    anim->end.y = y_end;
    anim->duration = duration;
    anim->elapsed = 0;
    anim->active = 1;
}
 */