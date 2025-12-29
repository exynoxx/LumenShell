### Work in progress!!

# Introduction
ExyShell is a early-ChromeOS lookalike Wayland shell featuring Wayfire as compositor, a custom panel (ExyPanel) and application launcher (Kickoff) for navigation. Both ExyPanel and kickoff avoids QT or other heavy UI toolkits and instead utilize **Drawkit** for harware accelerated rendering. Interaction with wayland is done through **WLHooks** a slim wayland client lib. Both the panel and Kickoff are implemented in vala.

### DrawKit
Is a small lightweight 2d graphics library made in C using GLES2 and EGL as backend. It can draw rectangles, circles, textures and text.

### WLHooks
Is a small wayland client lib implementing protocols:
- 

# Show case
Bottom panel
<img width="1920" height="1080" alt="20251229_19h31m16s_grim" src="https://github.com/user-attachments/assets/79427174-5150-4ea8-8304-a39ef679c654" />
  
Kickoff
<img width="1920" height="1080" alt="20251229_19h31m35s_grim" src="https://github.com/user-attachments/assets/31268306-9153-4358-aa86-85810d480bc1" />

### License
