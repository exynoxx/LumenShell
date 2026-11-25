#include "lumen_bsd.h"

#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/procctl.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <sys/backlight.h>

#include <errno.h>
#include <fcntl.h>
#include <kenv.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

int lumen_bsd_set_pdeathsig(int sig)
{
    return procctl(P_PID, 0, PROC_PDEATHSIG_CTL, &sig);
}

gchar *lumen_bsd_sysctl_string(const char *name)
{
    size_t len = 0;
    if (sysctlbyname(name, NULL, &len, NULL, 0) != 0 || len == 0)
        return NULL;
    gchar *buf = g_malloc0(len + 1);
    if (sysctlbyname(name, buf, &len, NULL, 0) != 0) {
        g_free(buf);
        return NULL;
    }
    buf[len] = '\0';
    return buf;
}

gint64 lumen_bsd_sysctl_int64(const char *name, gint64 def)
{
    /* Read into the widest buffer and decode by the size the kernel wrote. */
    union { int32_t i32; int64_t i64; } v;
    size_t len = sizeof(v);
    memset(&v, 0, sizeof(v));
    if (sysctlbyname(name, &v, &len, NULL, 0) != 0)
        return def;
    if (len == sizeof(int32_t))
        return (gint64) v.i32;
    if (len == sizeof(int64_t))
        return (gint64) v.i64;
    return def;
}

gint64 lumen_bsd_uptime_seconds(void)
{
    /* CLOCK_UPTIME counts time since boot, excluding nothing we care about;
     * kern.boottime is the fallback for very old kernels. */
    struct timespec ts;
    if (clock_gettime(CLOCK_UPTIME, &ts) == 0)
        return (gint64) ts.tv_sec;

    struct timeval boot;
    size_t len = sizeof(boot);
    if (sysctlbyname("kern.boottime", &boot, &len, NULL, 0) != 0)
        return -1;
    return (gint64) (time(NULL) - boot.tv_sec);
}

gchar *lumen_bsd_kenv(const char *name)
{
    char buf[KENV_MVALLEN + 1];
    int n = kenv(KENV_GET, name, buf, sizeof(buf));
    if (n <= 0)
        return NULL;
    buf[sizeof(buf) - 1] = '\0';
    return g_strdup(buf);
}

static int backlight_ioctl(const char *device, unsigned long req,
                           struct backlight_props *props, int flags)
{
    int fd = open(device, flags | O_CLOEXEC);
    if (fd < 0)
        return -1;
    int rc = ioctl(fd, req, props);
    int saved = errno;
    close(fd);
    errno = saved;
    return rc;
}

int lumen_bsd_backlight_get(const char *device)
{
    struct backlight_props props;
    memset(&props, 0, sizeof(props));
    if (backlight_ioctl(device, BACKLIGHTGETSTATUS, &props, O_RDONLY) != 0)
        return -1;
    return (int) props.brightness;
}

int lumen_bsd_backlight_type(const char *device)
{
    struct backlight_info info;
    memset(&info, 0, sizeof(info));
    int fd = open(device, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return -1;
    int rc = ioctl(fd, BACKLIGHTGETINFO, &info);
    close(fd);
    return rc != 0 ? -1 : (int) info.type;
}

int lumen_bsd_backlight_set(const char *device, int percent)
{
    struct backlight_props props;
    memset(&props, 0, sizeof(props));
    if (percent < 0)   percent = 0;
    if (percent > 100) percent = 100;
    props.brightness = (uint32_t) percent;
    return backlight_ioctl(device, BACKLIGHTUPDATESTATUS, &props, O_RDWR) != 0 ? -1 : 0;
}
