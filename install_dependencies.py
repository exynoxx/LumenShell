
#!/usr/bin/env python3

import platform
import shutil
import subprocess
import sys
import os

def detect_distro():
    if platform.system() == 'FreeBSD':
        return 'freebsd'
    try: 
        with open('/etc/os-release', 'r') as f:
            os_release = f.read().lower()
            if 'ubuntu' in os_release or 'debian' in os_release:
                return 'ubuntu'
            elif 'fedora' in os_release: 
                return 'fedora'
            elif 'arch' in os_release or 'manjaro' in os_release:
                return 'arch'
    except FileNotFoundError:
        pass
    
    print("Error: Could not detect distribution.  Supported:  Ubuntu, Fedora, Arch Linux, FreeBSD")
    sys.exit(1)

def privilege_tool():
    # FreeBSD base has neither; doas (security/doas) is the common choice there.
    for tool in ('sudo', 'doas'):
        if shutil.which(tool):
            return tool
    return None

def run_command(cmd, use_sudo=True):
    if use_sudo and os.geteuid() != 0:
        tool = privilege_tool()
        if tool is None:
            print("Error: run as root, or install sudo or doas.")
            return False
        cmd = [tool] + cmd
    
    print(f"Running: {' '. join(cmd)}")
    try:
        subprocess.run(cmd, check=True)
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {e}")
        return False

def install_ubuntu():
    print("Installing dependencies for Ubuntu/Debian...")
    
    packages = [
        'build-essential',
        'meson',
        'ninja-build',
        'pkg-config',
        'valac',
        'libglib2.0-dev',
        'libgee-0.8-dev',
        'libjson-glib-dev',
        'libwayland-dev',
        'libwayland-bin',
        'wayland-protocols',
        'libgtk-4-dev',
        'libadwaita-1-dev',
        'libgtk4-layer-shell-dev',
        # lumen-settings' Wayfire plugin pages parse the metadata XML.
        'libxml2-dev',
        # lumen-settings' shortcut recorder names keys via libevdev.
        'libevdev-dev',
        'wayfire',
        # C++ Wayfire plugins: headers + wlroots, plus glm which the Wayfire
        # headers #include but wayfire.pc does not list.
        'wayfire-dev',
        # Ubuntu/Debian version the wlroots dev package; the unversioned name
        # is the fallback. Whichever apt doesn't know is skipped below.
        'libwlroots-0.19-dev',
        'libwlroots-dev',
        'libglm-dev',
        # lumen-search (tinysparql-3.0) + the LocalSearch file index it reads.
        'libtinysparql-dev',
        'localsearch',
        # Runtime tools the panel/osdctl/settings shell out to.
        'pulseaudio-utils',   # pactl
        'brightnessctl',
        'bluez',              # bluetoothctl
        'network-manager',    # nmcli
        'pkexec',
        'pciutils',           # lspci (Settings > System)
        'libpam-gnome-keyring',
        'xdg-desktop-portal',
        'xdg-desktop-portal-gtk',
        'xdg-desktop-portal-wlr',
        # lumen-lockscreen: PAM (build) + keyring/accounts (runtime).
        # gtk4-session-lock isn't packaged: build https://github.com/wmww/gtk4-session-lock
        'libpam0g-dev',
        'gnome-keyring',
        'accountsservice',
        # lumen-polkit-agent (build-time .pc + headers).
        'libpolkit-agent-1-dev',
        'libpolkit-gobject-1-dev',
    ]

    # apt-get aborts the WHOLE install on one unknown name, so drop the names
    # this release doesn't have instead of installing nothing.
    run_command(['apt-get', 'update'])
    known = [p for p in packages
             if subprocess.run(['apt-cache', 'show', p], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL).returncode == 0]
    skipped = [p for p in packages if p not in known]
    if skipped:
        print(f"Not available on this release, skipped: {' '.join(skipped)}")
    return run_command(['apt-get', 'install', '-y'] + known)

def install_fedora():
    print("Installing dependencies for Fedora...")
    
    packages = [
        'gcc',
        'gcc-c++',
        'make',
        'meson',
        'ninja-build',
        'pkgconfig',
        'vala',
        'glib2-devel',
        'libgee-devel',
        'json-glib-devel',
        'wayland-devel',
        'wayland-protocols-devel',
        'gtk4-devel',
        'libadwaita-devel',
        'gtk4-layer-shell-devel',
        # lumen-settings' Wayfire plugin pages parse the metadata XML.
        'libxml2-devel',
        # lumen-settings' shortcut recorder names keys via libevdev.
        'libevdev-devel',
        'wayfire',
        # C++ Wayfire plugins: headers + wlroots, plus glm which the Wayfire
        # headers #include but wayfire.pc does not list.
        'wayfire-devel',
        'wlroots-devel',
        'glm-devel',
        'xdg-desktop-portal',
        'xdg-desktop-portal-gtk',
        'xdg-desktop-portal-wlr',
        # lumen-lockscreen: PAM (build) + keyring/accounts (runtime).
        # gtk4-session-lock isn't packaged: build https://github.com/wmww/gtk4-session-lock
        'pam-devel',
        'gnome-keyring',
        'accountsservice',
        # lumen-polkit-agent (build-time .pc + headers).
        'polkit-devel',
    ]

    cmd = ['dnf', 'install', '-y'] + packages
    return run_command(cmd)

def install_arch():
    print("Installing dependencies for Arch Linux...")
    
    packages = [
        'base-devel',
        'meson',
        'ninja',
        'pkgconf',
        'vala',
        'glib2',
        'libgee',
        'json-glib',
        'wayland',
        'wayland-protocols',
        'gtk4',
        'libadwaita',
        'gtk4-layer-shell',
        # lumen-settings' Wayfire plugin pages parse the metadata XML.
        'libxml2',
        # lumen-settings' shortcut recorder names keys via libevdev.
        'libevdev',
        # Arch's `wayfire` ships the headers; the C++ plugins also need wlroots
        # and glm (the Wayfire headers #include glm but wayfire.pc omits it).
        'wayfire',
        'wlroots0.19',
        'glm',
        'xdg-desktop-portal',
        'xdg-desktop-portal-gtk',
        'xdg-desktop-portal-wlr',
        # lumen-lockscreen: PAM (build) + keyring/accounts (runtime).
        # gtk4-session-lock comes from the AUR.
        'pam',
        'gnome-keyring',
        'accountsservice',
        # lumen-polkit-agent: Arch's `polkit` also ships the .pc/headers.
        'polkit',
    ]

    cmd = ['pacman', '-S', '--needed', '--noconfirm'] + packages
    return run_command(cmd)

def install_freebsd():
    print("Installing dependencies for FreeBSD...")

    packages = [
        'meson',
        'ninja',
        'pkgconf',
        'vala',
        'glib',
        'libgee',
        'json-glib',
        'wayland',
        'wayland-protocols',
        'gtk4',
        'libadwaita',
        # >= 1.1 also provides the gtk_session_lock API lumen-lockscreen uses
        # (no separate gtk4-session-lock package on FreeBSD).
        'gtk4-layer-shell',
        # lumen-settings' Wayfire plugin pages parse the metadata XML.
        'libxml2',
        # lumen-settings' shortcut recorder names keys via libevdev; its
        # headers include <linux/input.h>, which evdev-proto provides.
        'libevdev',
        'evdev-proto',
        # Compositor. The C++ plugins need Wayfire 0.10 + wlroots 0.19; the
        # wayfire package tracks newer releases, so either build the shell with
        # the plugin options off, or run scripts/freebsd/build-extern.sh wayfire
        # (which needs the build deps below).
        'wayfire',
        'wlroots019',
        'glm',
        'libinotify',
        'libudev-devd',
        'yyjson',
        'git',
        'cmake',
        # Session plumbing that systemd provides on Linux: seat access for
        # Wayfire, a session/power manager, the buses.
        'seatd',
        'consolekit2',
        'dbus',
        'upower',
        'xdg-desktop-portal',
        'xdg-desktop-portal-gtk',
        'xdg-desktop-portal-wlr',
        # lumen-lockscreen: OpenPAM is in base; keyring/accounts at runtime.
        'gnome-keyring',
        'accountsservice',
        # lumen-polkit-agent, and the pkexec prompts for root-only settings.
        'polkit',
        # lumen-search (tinysparql-3.0) + the LocalSearch file index it reads.
        'tinysparql',
        'localsearch',
    ]

    # pkg aborts the whole transaction on one unknown name: drop the names the
    # configured repository doesn't carry instead of installing nothing.
    known = [p for p in packages
             if subprocess.run(['pkg', 'rquery', '%n', p], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL).returncode == 0]
    skipped = [p for p in packages if p not in known]
    if skipped:
        print(f"Not available in the pkg repository, skipped: {' '.join(skipped)}")
    if not run_command(['pkg', 'install', '-y'] + known):
        return False
    print()
    print("Next: scripts/freebsd/setup-system.sh (groups, rc.conf services,")
    print("devfs rules, wpa_supplicant, syslog). See docs/FREEBSD.md.")
    return True

def main():
    print("Lumen Dependency Installation Script")
    print("=" * 50)
    
    if os.geteuid() != 0:
        print(f"Note: This script will use '{privilege_tool() or 'sudo'}' to install packages.")
        print("You may be prompted for your password.")
        print()
    
    distro = detect_distro()
    print(f"Detected distribution: {distro. capitalize()}")
    print()
    
    success = False
    if distro == 'ubuntu': 
        success = install_ubuntu()
    elif distro == 'fedora':
        success = install_fedora()
    elif distro == 'arch':
        success = install_arch()
    elif distro == 'freebsd':
        success = install_freebsd()
    
    print()
    print("=" * 50)
    if success:
        print("✓ All dependencies installed successfully!")
    else:
        print("✗ Failed to install some dependencies.")
        print("Please check the error messages above.")
        sys.exit(1)

if __name__ == '__main__':
    main()