[CCode (cprefix = "EGL", lower_case_cprefix = "egl_", cheader_filename = "EGL/egl.h")]
namespace EGL {

    // Basic opaque handles
    [SimpleType] public struct Display : void*;
    [SimpleType] public struct Context : void*;
    [SimpleType] public struct Surface : void*;
    [SimpleType] public struct Config : void*;
    [SimpleType] public struct ClientBuffer : void*;
    [SimpleType] public struct Sync : void*;
    [SimpleType] public struct Image : void*;

    // Basic types
    public const int TRUE;
    public const int FALSE;
    public const int NONE;
    public const int DONT_CARE;

    // Common attribute constants (partial)
    public const int SURFACE_TYPE;
    public const int RENDERABLE_TYPE;
    public const int RED_SIZE;
    public const int GREEN_SIZE;
    public const int BLUE_SIZE;
    public const int ALPHA_SIZE;
    public const int WINDOW_BIT;
    public const int OPENGL_ES2_BIT;

    [CCode (cname = "EGLint")]
    public struct Int : int;

    [CCode (cname = "EGLBoolean")]
    public struct Boolean : uint;

    [CCode (cname = "EGLenum")]
    public struct Enum : uint;

    // --- EGL core functions ---
    [CCode (cname = "eglGetDisplay")]
    public static unowned Display get_display (void* native_display);

    [CCode (cname = "eglInitialize")]
    public static Boolean initialize (Display dpy, out int major, out int minor);

    [CCode (cname = "eglChooseConfig")]
    public static Boolean choose_config (Display dpy, int[] attrib_list,
                                         out Config configs, int config_size,
                                         out int num_config);

    [CCode (cname = "eglCreateWindowSurface")]
    public static unowned Surface create_window_surface (Display dpy, Config config,
                                                         void* native_window,
                                                         int[] attrib_list);

    [CCode (cname = "eglCreateContext")]
    public static unowned Context create_context (Display dpy, Config config,
                                                  Context share_context,
                                                  int[] attrib_list);

    [CCode (cname = "eglMakeCurrent")]
    public static Boolean make_current (Display dpy, Surface draw, Surface read, Context ctx);

    [CCode (cname = "eglSwapBuffers")]
    public static Boolean swap_buffers (Display dpy, Surface surface);

    [CCode (cname = "eglDestroySurface")]
    public static Boolean destroy_surface (Display dpy, Surface surface);

    [CCode (cname = "eglDestroyContext")]
    public static Boolean destroy_context (Display dpy, Context ctx);

    [CCode (cname = "eglTerminate")]
    public static Boolean terminate (Display dpy);

    [CCode (cname = "eglGetError")]
    public static int get_error ();
}
