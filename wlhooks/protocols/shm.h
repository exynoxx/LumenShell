#ifndef SHM_H
#define SHM_H

struct wl_shm;

void shm_init(void);
void shm_cleanup(void);
struct wl_shm *get_wl_shm(void);

#endif
