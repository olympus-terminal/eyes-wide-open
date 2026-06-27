# Changelog

## 2026-06-27

### Lock Screen Disabled by Anti-Sleep Scripts — Fixed

**Problem:** After running the anti-sleep/anti-suspend scripts (`disable-sleep.sh`, `fix-sleep-permanently.sh`, `kill-all-sleep.sh`, `scripts/fix.sh`), the GNOME lock screen stopped working entirely. The screen would never lock — not on idle, not on `Super+L`, not manually. This left the workstation completely unprotected when walking away.

**Root Cause:** The anti-sleep scripts included `lock-enabled=false` in their GNOME dconf overrides and gsettings calls. This setting (`org.gnome.desktop.screensaver lock-enabled`) controls whether the screen *locks* — it has nothing to do with sleep or suspend. It was included by mistake, conflating "screen lock" with "screen blanking" and "idle suspend."

The setting was present in five places across the codebase:
- `disable-sleep.sh` — gsettings call and GDM dconf override
- `fix-sleep-permanently.sh` — GDM dconf, GNOME gsettings, and the 60-second enforcement service
- `kill-all-sleep.sh` — GDM dconf override
- `scripts/fix.sh` — dconf system override and dconf locks
- `scripts/install-monitor.sh` — regression checker's dconf recreation blocks

**How We Found It:** The lock screen simply stopped working after running the anti-sleep stack. Bisecting the settings, `gsettings get org.gnome.desktop.screensaver lock-enabled` returned `false`, confirming the scripts had disabled it. The anti-sleep intent was to prevent idle *suspend* (the system going to sleep), not to prevent the screen from *locking* (showing a password prompt). These are independent GNOME subsystems.

**Fix:** Removed all instances of `lock-enabled=false` from every script. The relevant settings for preventing sleep are `idle-activation-enabled=false` (prevents the screensaver from activating on idle), `idle-delay=0` (no idle timeout), and the `sleep-inactive-*-type='nothing'` family (prevents sleep after inactivity). None of these affect whether the lock screen works when explicitly invoked.

**Verification:** After removing `lock-enabled=false` and re-running the scripts, `gsettings get org.gnome.desktop.screensaver lock-enabled` returns `true`, and `Super+L` locks the screen correctly. Sleep/suspend remains fully disabled.

**Debugging scripts removed:** Three ad-hoc scripts created during the debugging process in the parent directory (`~/Documents/`) have been deleted:
- `fix-lock-screen.sh` — re-enabled lock-enabled via gsettings + NVIDIA modprobe fixes
- `fix-samsung-edid.sh` — attempted EDID copy (wrong approach for this issue)
- `fix-samsung-freeze-step2.sh` — disabled GSP firmware (wrong approach for this issue)

---

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
