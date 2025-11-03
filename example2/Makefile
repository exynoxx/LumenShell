default:
	valac --vapidir=vapi \
	--pkg=graphene-gobject-1.0 \
	--pkg=glesv2 \
	--pkg=wayland-client \
	--pkg=egl \
	--pkg=liblayershell \
	-X -I/home/nicholas/Dokumenter/layer-shell-experiments/liblayershell \
	-X -L/home/nicholas/Dokumenter/layer-shell-experiments/liblayershell/build \
	-X -Wl,-rpath,/home/nicholas/Dokumenter/layer-shell-experiments/liblayershell/build \
	-X -llayershell \
	-X -lm \
	src/*.vala
	