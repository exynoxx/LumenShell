default:
	gcc `pkg-config --cflags --libs wayland-client wayland-egl egl glesv2` *.c