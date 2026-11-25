# Ports skeleton for x11/lumenshell. Copy this directory to
# /usr/ports/x11/lumenshell (or a local overlay), then:
#   make makesum && make install clean
# Regenerate pkg-plist after source changes with `make makeplist`.

PORTNAME=	lumenshell
DISTVERSION=	1.0
CATEGORIES=	x11 wayland

MAINTAINER=	ports@FreeBSD.org
COMMENT=	ChromeOS-inspired desktop shell for the Wayfire compositor
WWW=		https://github.com/exynoxx/LumenShell

LICENSE=	GPLv3
LICENSE_FILE=	${WRKSRC}/LICENSE

BUILD_DEPENDS=	evdev-proto>0:devel/evdev-proto \
		wayland-protocols>=1.32:graphics/wayland-protocols
LIB_DEPENDS=	libevdev.so:devel/libevdev \
		libgee-0.8.so:devel/libgee \
		libgtk4-layer-shell.so:x11-toolkits/gtk4-layer-shell \
		libjson-glib-1.0.so:devel/json-glib \
		libwayland-client.so:graphics/wayland
RUN_DEPENDS=	dbus-daemon:devel/dbus \
		seatd:sysutils/seatd \
		upower:sysutils/upower \
		wayfire:x11-wm/wayfire \
		xdg-desktop-portal-gtk>0:x11/xdg-desktop-portal-gtk \
		xdg-desktop-portal-wlr>0:x11/xdg-desktop-portal-wlr

USES=		compiler:c11 gnome meson pkgconfig vala:build
USE_GITHUB=	yes
GH_ACCOUNT=	exynoxx
GH_PROJECT=	LumenShell
USE_GNOME=	glib20 gtk40 libadwaita libxml2

# The C++ Wayfire plugins target the Wayfire 0.10 / wlroots 0.19 plugin API;
# x11-wm/wayfire tracks newer releases. Build them with
# scripts/freebsd/build-extern.sh (side-by-side Wayfire 0.10) instead.
MESON_ARGS=	-Dwith_curtain_peek=false \
		-Dwith_desktop_peek=false \
		-Dwith_night_light=false \
		-Dwith_panel_push=false \
		-Dwith_slide_peek=false \
		-Dwith_startup_zoom=false \
		-Dwith_zoom_peek=false

OPTIONS_DEFINE=		CONSOLEKIT LOCKSCREEN POLKIT SEARCH
OPTIONS_DEFAULT=	CONSOLEKIT LOCKSCREEN POLKIT
OPTIONS_SUB=		yes

CONSOLEKIT_DESC=	Session/power management via ConsoleKit2 (else zzz/shutdown)
LOCKSCREEN_DESC=	lumen-lockscreen (ext-session-lock-v1, OpenPAM)
POLKIT_DESC=		lumen-polkit-agent authentication agent
SEARCH_DESC=		lumen-search, Spotlight-style search (TinySPARQL)

CONSOLEKIT_RUN_DEPENDS=	ck-launch-session:sysutils/consolekit2
LOCKSCREEN_MESON_ENABLED=	with_lockscreen
POLKIT_LIB_DEPENDS=	libpolkit-agent-1.so:sysutils/polkit
POLKIT_MESON_ENABLED=	with_polkit_agent
SEARCH_LIB_DEPENDS=	libtinysparql-3.0.so:devel/tinysparql
SEARCH_RUN_DEPENDS=	localsearch:sysutils/localsearch
SEARCH_MESON_ENABLED=	with_search

.include <bsd.port.mk>
