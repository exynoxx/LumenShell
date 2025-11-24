ROOT_DIR = /home/nicholas/Dokumenter/layer-shell-experiments
DRAWKIT_SRC = $(ROOT_DIR)/src
LAYERSHELL_SRC = $(ROOT_DIR)/libwayland-unstable
LAYERSHELL_BUILD = $(ROOT_DIR)/libwayland-unstable/build

# Vala packages
VALA_PKGS = --pkg=glesv2 \
            --pkg=wayland-client \
            --pkg=glib-2.0 \
            --pkg=gee-0.8 \
            --pkg=egl \
            --pkg=drawkit \
            --pkg=libwayland-unstable

# C compiler flags for external libraries
CFLAGS = -X -I$(DRAWKIT_SRC) \
         -X -I$(LAYERSHELL_SRC) \
         -X -L$(LAYERSHELL_BUILD) \
         -X -lwayland-unstable \
         -X -Wl,-rpath,$(LAYERSHELL_BUILD) \
         -X -lm \
         -o main

# DrawKit C source files to compile
DRAWKIT_SOURCES = $(DRAWKIT_SRC)/*.c

default:
	valac --vapidir=vapi \
	$(VALA_PKGS) \
	$(CFLAGS) \
	$(DRAWKIT_SOURCES) \
	src/*.vala