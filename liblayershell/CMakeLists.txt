cmake_minimum_required(VERSION 3.15)
project(liblayershell LANGUAGES C)

# Set version
set(LIBLAYERSHELL_VERSION 1.0)

# Require C11
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# --- Find dependencies using pkg-config ---
find_package(PkgConfig REQUIRED)

pkg_check_modules(WAYLAND_CLIENT REQUIRED wayland-client)
pkg_check_modules(WAYLAND_EGL REQUIRED wayland-egl)
pkg_check_modules(EGL REQUIRED egl)
pkg_check_modules(GLESv2 REQUIRED glesv2)

# Include directories
include_directories(
    ${WAYLAND_CLIENT_INCLUDE_DIRS}
    ${WAYLAND_EGL_INCLUDE_DIRS}
    ${EGL_INCLUDE_DIRS}
    ${GLESv2_INCLUDE_DIRS}
    ${CMAKE_CURRENT_SOURCE_DIR}       # your headers (liblayershell.h)
)

# --- Source and header files ---
set(SOURCES
    liblayershell.c
    xdg-shell-client-protocol.c
    wlr-layer-shell-unstable-v1-protocol.c
)

set(HEADERS
    liblayershell.h
    xdg-shell-client-protocol.h
    wlr-layer-shell-unstable-v1-client-protocol.h
)

# --- Build shared library ---
add_library(${PROJECT_NAME} SHARED ${SOURCES} ${HEADERS})

# --- Link system libraries ---
target_link_libraries(${PROJECT_NAME}
    ${WAYLAND_CLIENT_LIBRARIES}
    ${WAYLAND_EGL_LIBRARIES}
    ${EGL_LIBRARIES}
    ${GLESv2_LIBRARIES}
)

# --- Additional compile flags ---
target_compile_options(${PROJECT_NAME} PRIVATE
    ${WAYLAND_CLIENT_CFLAGS_OTHER}
    ${WAYLAND_EGL_CFLAGS_OTHER}
)

# --- Version info ---
set_target_properties(${PROJECT_NAME} PROPERTIES
    VERSION ${LIBLAYERSHELL_VERSION}
    SOVERSION 1
)

# --- Installation paths ---
install(TARGETS ${PROJECT_NAME}
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)

install(FILES ${HEADERS} DESTINATION include)

# --- Optional: message about dependencies ---
message(STATUS "Ensure Wayland, EGL, and GLES2 development packages are installed")
