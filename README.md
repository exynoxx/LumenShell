### Work in progress!!

# Introduction
ExyShell is a early-ChromeOS lookalike Wayland shell featuring Wayfire as compositor, a custom panel (ExyPanel) and application launcher (Kickoff) for navigation. Both ExyPanel and kickoff avoids QT or other heavy UI toolkits and instead utilize **Drawkit** for hardware accelerated rendering, both implemented in vala. Wayland interactions are handled via **WLHooks**, a lightweight Wayland client library.

### DrawKit
Is a minimal, high-performance 2D graphics library written in C, using GLES2 and EGL as its backend. It supports rendering rectangles, circles, textures, and text. Source is included in this repo.

### WLHooks
Is a lightweight Wayland client library implementing the following protocols:
-  ``` wl_compositor ```
- ``` wl_seat ```
- ``` wl_output ```
- ``` wlr-layer-shell-unstable-v1 ```
- ``` wlr-foreign-toplevel-management-unstable-v1 ```

Source also included in this repo.

# Show case
Bottom panel
<img width="1920" height="1080" alt="20251229_19h31m16s_grim" src="https://github.com/user-attachments/assets/79427174-5150-4ea8-8304-a39ef679c654" />
  
Kickoff
<img width="1920" height="1080" alt="20251229_19h31m35s_grim" src="https://github.com/user-attachments/assets/31268306-9153-4358-aa86-85810d480bc1" />

### License
