default:
	gcc -o panel *.c ../src/*.c \
	-I/usr/include/graphene-1.0 -I/usr/lib64/graphene-1.0/include -mfpmath=sse -msse -msse2 -I/usr/include/glib-2.0 -I/usr/lib64/glib-2.0/include -I/usr/include/sysprof-6 -pthread -lgraphene-1.0 -lGLESv2 -lEGL -lwayland-client \
	-lpng \
	-lm \
	-L/home/nicholas/Dokumenter/layer-shell-experiments/liblayershell/build \
	-llayershell \
	-Wl,-rpath=/home/nicholas/Dokumenter/layer-shell-experiments/liblayershell/build

