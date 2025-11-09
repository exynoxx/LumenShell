default:
	valac --vapidir=vapi \
	--pkg=glesv2 \
	--pkg=wayland-client \
	--pkg glib-2.0 \
	--pkg gee-0.8 \
	--pkg=egl \
	--pkg=drawkit \
	--pkg=liblayershell \
	-X -I/home/nicholas/Dokumenter/layer-shell-experiments/liblayershell \
	-X -L/home/nicholas/Dokumenter/layer-shell-experiments/liblayershell/build \
	-X -Wl,-rpath,/home/nicholas/Dokumenter/layer-shell-experiments/liblayershell/build \
	-X -llayershell \
	-X -lm \
	src/*.vala
	