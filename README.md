Termux Terraria One-click Installer

Run Linux Terraria on Android (Termux) via Mono + FNA, with Vulkan acceleration (Mesa Freedreno) and XFCE4 desktop.

Features

· One-click installation, automatically switches to Tsinghua mirror for faster downloads
· Uses mesa-vulkan-icd-freedreno to provide Vulkan support
· Provides four startup commands:
  · start-desktop — Launch Termux:X11 + XFCE4 desktop
  · start-terraria — Run Terraria client (OpenGL ES compatibility mode)
  · start-terraria-vulkan — Run Vulkan backend client (experimental)
  · start-server — Run Terraria server
· Automatically detects Terraria self-extracting script (e.g., terraria_v1_4_4_9.sh) from /sdcard/Download/
· FNA3D / FAudio libraries are downloaded from the libs/ directory of this repository (ARM architecture)

Prerequisites

```bash
termux-setup-storage
```
