# HDMI EDID Compositor Freeze

## The Problem

NVIDIA dGPU systems (e.g., Lenovo laptop with NVIDIA + Intel iGPU, Ubuntu, GNOME/X11) connected to certain monitors via HDMI suffer chronic EDID read failures. The NVIDIA driver periodically fails to read the EDID, logging:

```
nvidia-modeset: WARNING: GPU:0: Unable to read EDID for display device Samsung LC49G95T (HDMI-0)
```

This happens dozens of times per day during normal operation. Most of the time the driver re-reads successfully and continues. But occasionally the failure wedges gnome-shell/mutter, producing a compositor freeze:

- Mouse cursor moves but nothing else responds (no clicks, no keyboard, no window updates)
- `gsd-media-keys: Couldn't lock screen: Timeout was reached` in journal
- EDID warnings repeat rapidly in kernel log
- No OOM, no kernel panic, no segfault -- the compositor is wedged

This also triggers Nemo file manager segfaults (null deref at offset 0x18 during hotplug events).

## Affected Hardware

- **Monitor:** Samsung LC49G95T (49" ultrawide, 5120x1440, 240Hz) -- HDMI input
- **GPU:** NVIDIA dGPU (laptop, hybrid graphics with Intel iGPU)
- **Connection:** HDMI
- **OS:** Ubuntu with GNOME/X11

Other monitors with HDMI EDID negotiation issues will show the same pattern.

## Recovery (When Frozen)

### 1. Switch to a TTY

`Ctrl+Alt+F4` (or F3/F5/F6). If that fails, open the laptop lid -- this triggers a display mode switch that drops to fbcon.

### 2. Restart the display manager

```bash
sudo systemctl restart display-manager
```

This kills the frozen X session and starts a fresh GDM login. Unsaved GUI work is lost, but terminal sessions (tmux, screen) and background processes survive.

### 3. Return to desktop

`Ctrl+Alt+F1` or `Ctrl+Alt+F2` to switch back to the graphical session.

## Mitigations

### Option A: Force a Static EDID (Recommended)

Capture a known-good EDID once, then tell the NVIDIA driver to use it instead of polling the monitor:

```bash
# Use the included script:
sudo ./scripts/fix-hdmi-edid.sh
```

This captures the current EDID from the working HDMI connection, saves it to `/etc/nvidia/`, and creates an xorg.conf.d snippet that forces the driver to use the cached copy. See `scripts/fix-hdmi-edid.sh` for details.

### Option B: Switch to DisplayPort

The EDID failures are HDMI-specific. If the monitor has a DP input and the laptop has a USB-C/DP output, switching to DisplayPort eliminates the issue entirely. This was confirmed on a DGX Spark cluster where HDMI caused Xid 119/120 GSP crashes but USB-C/DP did not.

### Option C: Disable Hotplug Detection

Already available via the repo's existing fixes:

```
options nvidia NVreg_EnableHotplugDetection=0
```

This prevents EDID polling entirely but means monitor connect/disconnect won't be detected automatically. Apply via `scripts/fix.sh` or `fix-sleep-permanently.sh`.

## How This Differs from the GSP Crash (Xid 119/120)

| | EDID Compositor Freeze | GSP Firmware Crash |
|---|---|---|
| **Trigger** | EDID read failure during display detect | Hotplug detection polling crashes GSP firmware |
| **Symptoms** | Desktop frozen, cursor moves, system alive | GPU completely dead, system reboots |
| **Log signature** | `Unable to read EDID` (WARNING) | `Xid 119/120/154` (ERROR) |
| **Recovery** | Restart display-manager from TTY | Reboot required |
| **Fix** | Static EDID or switch to DP | Disable hotplug detection |

Both are HDMI-related. Disabling hotplug detection (Option C) prevents both, but a static EDID (Option A) is the targeted fix for the compositor freeze specifically.

## Incident Log

| Date | Event | Resolution |
|------|-------|------------|
| 2026-05-07 | Xid 119/120 GSP crash via HDMI hotplug polling | Disabled hotplug detection, switched to USB-C/DP |
| 2026-06-21 17:43 | Nemo segfault (null deref during EDID/hotplug event) | Nemo auto-restarted |
| 2026-06-24 19:28 | Compositor freeze (EDID failure wedged gnome-shell) | Lid open -> tty4 login -> `sudo systemctl restart display-manager` |
