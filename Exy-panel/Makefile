ROOT_DIR       = $(CURDIR)
DRAWKIT_SRC    = $(ROOT_DIR)/../libdrawkit
DRAWKIT_BUILD  = $(ROOT_DIR)/../libdrawkit/build
WLHOOKS_SRC = $(ROOT_DIR)/../wlhooks
WLHOOKS_BUILD = $(ROOT_DIR)/../wlhooks/build

# Vala packages
VALA_PKGS = \
    --pkg=libdrawkit \
    --pkg=libwlhooks \
    --pkg=glesv2 \
    --pkg=wayland-client \
    --pkg=glib-2.0 \
    --pkg=gee-0.8 \
    --pkg=egl

# Compiler and linker flags (static libraries)
CFLAGS = \
    -X -I$(DRAWKIT_SRC) \
    -X $(DRAWKIT_BUILD)/libdrawkit.a \
    -X -I$(WLHOOKS_SRC) \
    -X $(WLHOOKS_BUILD)/libwlhooks.a \
    -X -lwayland-egl \
    -X -lwayland-client \
    -X -lEGL \
    -X -lGLESv2 \
    -X -lm \
    -X -lfreetype \
    -X -lxkbcommon

default:
	valac --vapidir=../vapi $(VALA_PKGS) $(CFLAGS) -o main src/*.vala
