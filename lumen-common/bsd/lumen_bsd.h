#ifndef LUMEN_BSD_H
#define LUMEN_BSD_H

/* FreeBSD kernel interfaces that have no GLib/Vala binding: sysctl(3),
 * kenv(2), procctl(2) and the backlight(9) character devices. Compiled only
 * when meson's host_machine.system() is 'freebsd'. Every string returned is
 * g_malloc'd (Vala `owned`), NULL on failure. */

#include <glib.h>

/* procctl(PROC_PDEATHSIG_CTL): the FreeBSD analogue of Linux's
 * prctl(PR_SET_PDEATHSIG). Async-signal-safe; usable from a child_setup. */
int      lumen_bsd_set_pdeathsig(int sig);

gchar   *lumen_bsd_sysctl_string(const char *name);
/* Integer sysctls of any width (int, long, u_int, uint64_t). `def` on error. */
gint64   lumen_bsd_sysctl_int64(const char *name, gint64 def);
/* Seconds since kern.boottime; -1 on error. */
gint64   lumen_bsd_uptime_seconds(void);
/* kenv(2) KENV_GET, e.g. "smbios.system.maker". */
gchar   *lumen_bsd_kenv(const char *name);

/* backlight(9): /dev/backlight/backlightN. Brightness is a 0..100 percentage
 * on every driver. get returns -1 on error; set returns 0 on success, -1 on
 * error (errno set: EACCES means the user is not in the device's group). */
int      lumen_bsd_backlight_get(const char *device);
/* BACKLIGHTGETINFO type: 0 = panel, 1 = keyboard; -1 on error. */
int      lumen_bsd_backlight_type(const char *device);
int      lumen_bsd_backlight_set(const char *device, int percent);

#endif /* LUMEN_BSD_H */
