
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
        'libgio2.0-cil-dev',
        'libwayland-dev',
        'libwayland-client0',
        'libwayland-egl1',
        'wayland-protocols',
        'libegl1-mesa-dev',
        'libgles2-mesa-dev',
        'libgl1-mesa-dev',
        'libfreetype6-dev',
        'libxkbcommon-dev',
        'libgtk-4-dev',
        'libgtk4-layer-shell-dev',
        'wayfire',
        'xdg-desktop-portal',
        'xdg-desktop-portal-gtk',
        'xdg-desktop-portal-wlr',
        # lumen-lockscreen: PAM (build) + keyring/accounts (runtime).
        # gtk4-session-lock is NOT in Debian/Ubuntu repos — build from source
        # (https://github.com/wmww/gtk4-session-lock); the lockscreen is
        # auto-skipped by meson until it is present.
        'libpam0g-dev',
        'gnome-keyring',
        'accountsservice',
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
        'wayland-devel',
        'wayland-protocols-devel',
        'mesa-libEGL-devel',
        'mesa-libGLES-devel',
        'mesa-libGL-devel',
        'freetype-devel',
        'libxkbcommon-devel',
        'gtk4-devel',
        'gtk4-layer-shell-devel',
        'wayfire',
        'xdg-desktop-portal',
        'xdg-desktop-portal-gtk',
        'xdg-desktop-portal-wlr',
        # lumen-lockscreen: PAM (build) + keyring/accounts (runtime).
        # gtk4-session-lock is NOT in Fedora repos — build from source
        # (https://github.com/wmww/gtk4-session-lock); the lockscreen is
        # auto-skipped by meson until it is present.
        'pam-devel',
        'gnome-keyring',
        'accountsservice',
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
        'wayland',
        'wayland-protocols',
        'mesa',
        'glu',
        'freetype2',
        'libxkbcommon',
        'gtk4',
        'gtk4-layer-shell',
        'wayfire',
        'xdg-desktop-portal',
        'xdg-desktop-portal-gtk',
        'xdg-desktop-portal-wlr',
        # lumen-lockscreen: PAM (build) + keyring/accounts (runtime).
        # gtk4-session-lock is in the AUR (gtk4-session-lock) — install with an
        # AUR helper; the lockscreen is auto-skipped by meson until it is present.
        'pam',
        'gnome-keyring',
        'accountsservice',
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
    
    # Print result
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