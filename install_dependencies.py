
#!/usr/bin/env python3

import subprocess
import sys
import os

def detect_distro():
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
    
    print("Error: Could not detect distribution.  Supported:  Ubuntu, Fedora, Arch Linux")
    sys.exit(1)

def run_command(cmd, use_sudo=True):
    if use_sudo and os.geteuid() != 0:
        cmd = ['sudo'] + cmd
    
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
        'wayfire',
        # C++ Wayfire plugins: headers + wlroots, plus glm which the Wayfire
        # headers #include but wayfire.pc does not list.
        'wayfire-dev',
        'libwlroots-dev',
        'libglm-dev',
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

    cmd = ['apt-get', 'install', '-y'] + packages
    return run_command(cmd)

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

def main():
    print("Lumen Dependency Installation Script")
    print("=" * 50)
    
    if os.geteuid() != 0:
        print("Note: This script will use 'sudo' to install packages.")
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