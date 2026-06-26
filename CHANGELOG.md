# Changelog

## 2026-06-26

### HDMI EDID Compositor Freeze — Documentation + Fix Script

**Problem:** NVIDIA driver intermittently fails to read EDID over HDMI from Samsung LC49G95T ultrawide. Usually harmless, but occasionally wedges gnome-shell/mutter — desktop freezes while cursor still moves.

**Distinct from the Xid 119/120 GSP crash** (2026-05-07): the GSP crash kills the GPU entirely and requires a reboot. The EDID compositor freeze leaves the system alive — recovery is `Ctrl+Alt+F4` then `sudo systemctl restart display-manager`.

**Added:**
- `docs/hdmi-edid-compositor-freeze.md` — full writeup: symptoms, recovery, three mitigation options, incident log
- `scripts/fix-hdmi-edid.sh` — captures a known-good EDID and configures the NVIDIA driver to use the static copy instead of polling the monitor

**Incidents logged:**
| Date | Event |
|------|-------|
| 2026-06-21 | Nemo segfault from null deref during EDID/hotplug event |
| 2026-06-24 | Full compositor freeze, recovered via TTY + display-manager restart |

---

## 2026-05-07

### CRITICAL: NVIDIA GSP Crash (Xid 119/120) - System Rebooted Overnight

**Symptom:** System appeared to "suspend" overnight but was actually forced to reboot due to GPU crash.

**Root Cause:** NVIDIA GSP (GPU System Processor) firmware crash triggered by **display hotplug detection** polling.

**Timeline:**
| Time | Event |
|------|-------|
| 03:00:18 | gnome-shell wakes up, triggers display connector detection |
| 03:00:18 | GPU's GSP hangs processing `nv_drm_connector_detect` |
| 03:00:36 | USB keyboard (AK820) connected |
| 03:01:03 | **Xid 119** - GSP Timeout after 45s waiting for RPC response |
| 03:01:31 | **Xid 120** - GSP firmware crash (load access fault) |
| 03:01:31 | **Xid 154** - GPU flagged "Reset Required" |
| ~03:11 | System rebooted |

**Key Log Evidence:**
```
NVRM: Xid (PCI:000f:01:00): 119, pid=3849, name=KMS thread, Timeout after 45s of waiting for RPC response from GPU0 GSP!
NVRM: Xid (PCI:000f:01:00): 120, pid=9111, name=python, GSP task exception: load access fault
nvidia-modeset: ERROR: GPU:0: Failed detecting connected display devices
gnome-shell[3849]: Failed to post KMS update: drmModeAtomicCommit: Invalid argument
```

**Resolution:**
1. Disabled `nvidia-suspend`, `nvidia-hibernate`, `nvidia-resume` systemd services
2. Added `options nvidia NVreg_EnableHotplugDetection=0` to modprobe config
3. Run `sudo update-initramfs -u` and reboot

**Script Updated:**
- Now 7 layers of protection instead of 5
- Added NVIDIA suspend service disabling (step 2)
- Added NVIDIA driver settings with hotplug detection disabled (step 7)

**Critical Lessons:**
1. NVIDIA's `nvidia-suspend`/`nvidia-hibernate` services cause GPU crashes - disable them
2. Hotplug detection polling can crash the GPU even with no display connected
3. **Driver updates re-enable these services** - must re-run script after updates
4. GPU crashes look like "suspend" from outside but are actually firmware crashes requiring reboot

---

## 2026-05-06

### Initial deployment

Applied 5-layer anti-suspend configuration:
- systemd targets masked
- logind configured
- GNOME power settings disabled
- GDM greeter anti-suspend configured
- Permanent sleep inhibitor service installed

**Status:** Incomplete - missing NVIDIA-specific fixes that caused overnight crash.
