ROOT_DIR       = $(CURDIR)
DRAWKIT_SRC    = $(ROOT_DIR)/../libdrawkit
DRAWKIT_BUILD  = $(ROOT_DIR)/../libdrawkit/build
LAYERSHELL_SRC = $(ROOT_DIR)/../libwayland-unstable
LAYERSHELL_BUILD = $(ROOT_DIR)/../libwayland-unstable/build

# Vala packages
VALA_PKGS = \
    --pkg=libdrawkit \
    --pkg=libwayland-unstable \
    --pkg=glesv2 \
    --pkg=wayland-client \
    --pkg=glib-2.0 \
    --pkg=gee-0.8 \
    --pkg=egl

# Compiler and linker flags (static libraries)
CFLAGS = \
    -X -I$(DRAWKIT_SRC) \
    -X $(DRAWKIT_BUILD)/libdrawkit.a \
    -X -I$(LAYERSHELL_SRC) \
    -X $(LAYERSHELL_BUILD)/libwayland-unstable.a \
    -X -lwayland-egl \
    -X -lwayland-client \
    -X -lEGL \
    -X -lGLESv2 \
    -X -lm \
    -X -lfreetype \
    -X -lxkbcommon

default:
	valac --vapidir=vapi $(VALA_PKGS) $(CFLAGS) -o main src/*.vala
