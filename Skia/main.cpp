#include <stdlib.h>
#include <string.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>

#include "include/core/SkCanvas.h"
#include "include/core/SkColor.h"
#include "include/core/SkSurface.h"
#include "include/core/SkPaint.h"
#include "include/gpu/ganesh/GrBackendSurface.h"
#include "include/gpu/ganesh/gl/GrGLInterface.h"
#include "include/gpu/ganesh/GrDirectContext.h"

extern EGLDisplay egl_display;
extern EGLSurface egl_surface;

int main() {
    
    draw_skia_circle(egl_display, egl_surface, 400, 300);

    // --- Cleanup ---
    
    return 0;
}

void draw_skia_circle(EGLDisplay egl_display, EGLSurface egl_surface, int width, int height) {
    // --- 1. Build Skia GPU interface/context ---
    sk_sp<const GrGLInterface> glInterface = GrGLMakeNativeInterface();
    if (!glInterface) { fprintf(stderr, "Skia: no GL interface\n"); return; }

    sk_sp<GrDirectContext> grCtx = GrDirectContext::MakeGL(glInterface);
    if (!grCtx) { fprintf(stderr, "Skia: failed to make GrDirectContext\n"); return; }

    // --- 2. Describe the current EGL framebuffer (FBO 0) ---
    GrGLFramebufferInfo fbInfo;
    fbInfo.fFBOID = 0;            // default framebuffer
    fbInfo.fFormat = GL_RGBA8;    // or GL_RGBA if GLES2

    GrBackendRenderTarget backendRT(
        width, height,        // size
        0,                    // sample count
        8,                    // stencil bits
        fbInfo
    );

    SkColorType colorType = kRGBA_8888_SkColorType;

    // --- 3. Create Skia surface wrapping the current framebuffer ---
    sk_sp<SkSurface> surface = SkSurface::MakeFromBackendRenderTarget(
        grCtx.get(),
        backendRT,
        kBottomLeft_GrSurfaceOrigin,  // GL-style origin
        colorType,
        nullptr,                      // sRGB colorspace optional
        nullptr                       // surface props
    );

    if (!surface) { fprintf(stderr, "Skia: failed to make surface\n"); return; }

    // --- 4. Draw a red circle ---
    SkCanvas* canvas = surface->getCanvas();
    canvas->clear(SK_ColorTRANSPARENT);

    SkPaint paint;
    paint.setAntiAlias(true);
    paint.setColor(SK_ColorRED);

    canvas->drawCircle(width / 2.0f, height / 2.0f, 80.0f, paint);

    // --- 5. Flush and show ---
    surface->flushAndSubmit();
    grCtx->flushAndSubmit();
    eglSwapBuffers(egl_display, egl_surface);
}