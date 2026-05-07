# eyes-wide-open

Comprehensive Linux anti-suspend/sleep configuration for headless and GPU workstations that must remain online during long-running jobs.

## The Problem

Linux desktop environments have **multiple independent layers** that can trigger suspend/sleep, and disabling one does not disable the others. This is a well-known, long-standing issue that bites anyone running overnight GPU jobs, ML training, or batch processing on a Linux workstation.

The failure mode is catastrophic for headless machines: the system suspends, the network interface goes down, SSH dies, and if the machine doesn't respond to Wake-on-LAN, you need physical access to power-cycle it — losing all running jobs.

### Why It Keeps Happening

There are at least **7 independent systems** that can put a Linux machine to sleep or crash the GPU:

| Layer | What Controls It | Scope |
|-------|-----------------|-------|
| systemd targets | `sleep.target`, `suspend.target`, etc. | System-wide |
| systemd-logind | `IdleAction`, `HandleLidSwitch` in `logind.conf` | All sessions |
| GDM greeter | Its own gsettings/dconf power profile | Login screen (no user session) |
| GNOME session | User's gsettings power profile | Active desktop session |
| systemd services | `systemd-suspend.service`, etc. | Service execution |
| **NVIDIA services** | `nvidia-suspend`, `nvidia-hibernate`, `nvidia-resume` | GPU power state |
| **NVIDIA driver** | Hotplug detection, display polling | GPU firmware (GSP) |

The critical trap: **GDM has its own power management** that runs even when no user is logged in (or when the screen is locked). You can disable everything else and GDM will still suspend the machine after 20 minutes of "inactivity" at the login screen.

### Headless-Specific Risks

On a machine with no native display (like the DGX Spark):
- No Ctrl+Alt+F2 TTY recovery — you cannot get a console
- If networking suspends, the machine is a brick until physically power-cycled
- HDMI being disconnected can trigger the system to think "no display = idle"
- The GNOME display server (Wayland/Xwayland) crashing can cascade into suspend

### NVIDIA-Specific Risks (CRITICAL)

NVIDIA GPUs have their own firmware (GSP - GPU System Processor) that can crash independently:

- **Xid 119**: GSP timeout - firmware hangs waiting for RPC response (often 45+ seconds)
- **Xid 120**: GSP task exception - firmware crash requiring full GPU reset
- **Xid 154**: GPU flags "Reset Required" - system must reboot

**Common triggers:**
- `nvidia-suspend`/`nvidia-hibernate` services interacting with `/proc/driver/nvidia/suspend`
- Display hotplug detection polling (gnome-shell calling `nv_drm_connector_detect`)
- DPMS/screen blanking triggering display mode changes

When the GPU crashes, the **entire system becomes unresponsive** - including SSH. This is NOT a suspend, but looks like one from the outside.

---

## Applied Fixes (Defense Layer 1 — Currently Active)

These are the fixes currently deployed. They address all 5 layers.

### 1. Mask systemd Sleep Services

Prevents the system from physically executing any sleep transition, regardless of what requests it:

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
sudo systemctl mask systemd-suspend.service systemd-hibernate.service systemd-hybrid-sleep.service systemd-suspend-then-hibernate.service
```

Verification:
```bash
systemctl status sleep.target suspend.target hibernate.target
# All should show "Loaded: masked"

systemctl status systemd-suspend.service
# Should show "Loaded: masked"
```

This is the nuclear option — even if some other component calls `systemctl suspend`, it will fail.

### 2. Disable NVIDIA Suspend Services (CRITICAL)

NVIDIA ships systemd services that interact with `/proc/driver/nvidia/suspend` during power state transitions. These cause GPU crashes and black screens.

```bash
sudo systemctl disable nvidia-suspend nvidia-hibernate nvidia-resume
sudo systemctl stop nvidia-suspend nvidia-hibernate nvidia-resume
```

**WARNING:** NVIDIA driver updates re-enable these services. You must re-run this after every driver update.

Verification:
```bash
systemctl is-enabled nvidia-suspend nvidia-hibernate nvidia-resume
# All should show "disabled"
```

### 3. logind.conf — Disable Idle/Button Triggers

Edit `/etc/systemd/logind.conf`:

```ini
[Login]
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
IdleAction=ignore
IdleActionSec=0
```

Apply:
```bash
sudo systemctl restart systemd-logind
```

**Warning:** Restarting logind kills active desktop sessions. Do this over SSH or before starting jobs.

### 4. GNOME User Session — Power Management

```bash
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0
gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'nothing'
gsettings set org.gnome.desktop.session idle-delay 0
```

### 5. GDM Greeter — The Hidden Culprit

GDM runs its own GNOME session with its own power settings. The user-level gsettings have NO effect on it. Must use dconf system override:

Create `/etc/dconf/db/gdm.d/disable-suspend.conf`:
```ini
[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type="nothing"
sleep-inactive-ac-timeout=0
```

Apply:
```bash
sudo dconf update
```

### 6. Screen Blanking / DPMS (Prevents Idle Cascade)

Sometimes display blanking triggers the system to think it's idle, cascading into suspend:

```bash
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.screensaver idle-activation-enabled false
```

### 7. NVIDIA Driver Settings (CRITICAL - Prevents GPU Crashes)

Create `/etc/modprobe.d/nvidia-eyes-wide-open.conf`:

```
# CRITICAL: Disable display hotplug detection
# Without this, gnome-shell connector polling causes GSP firmware crashes (Xid 119/120)
options nvidia NVreg_EnableHotplugDetection=0

# Disable dynamic power management
options nvidia NVreg_DynamicPowerManagement=0x00

# Preserve video memory on suspend
options nvidia NVreg_PreserveVideoMemoryAllocations=1
```

Apply:
```bash
sudo update-initramfs -u
sudo reboot
```

Verification:
```bash
cat /proc/driver/nvidia/params | grep -E "EnableHotplug|DynamicPower"
# EnableHotplugDetection: 0
# DynamicPowerManagement: 0
```

---

## Reserve Fixes (Defense Layer 2 — If Current Run Fails)

Deploy these if the machine still suspends despite Layer 1.

### A. Permanent Sleep Inhibitor Service

A systemd service that holds an inhibit lock, blocking any sleep request at the dbus level:

Create `/etc/systemd/system/nosuspend.service`:
```ini
[Unit]
Description=Inhibit sleep/suspend permanently
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/systemd-inhibit --what=idle:sleep:handle-lid-switch --who=nosuspend --why="Workstation must stay awake" --mode=block sleep infinity
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now nosuspend.service
```

Verify:
```bash
systemd-inhibit --list
# Should show "nosuspend" holding idle:sleep:handle-lid-switch locks
```

### B. Wake-on-LAN (Remote Recovery)

If the machine does suspend, WoL lets you wake it over ethernet without physical access:

Check current WoL status:
```bash
sudo ethtool <interface> | grep Wake-on
# "g" means WoL is enabled; "d" means disabled
```

Enable:
```bash
sudo ethtool -s <interface> wol g
```

Make persistent via NetworkManager:
```bash
nmcli connection modify "<connection-name>" 802-3-ethernet.wake-on-lan magic
```

Or via udev rule (create `/etc/udev/rules.d/81-wol.rules`):
```
ACTION=="add", SUBSYSTEM=="net", NAME=="<interface>", RUN+="/usr/sbin/ethtool -s $name wol g"
```

To send a WoL packet from another machine (using the target's MAC address):
```bash
# With wakeonlan package:
wakeonlan AA:BB:CC:DD:EE:FF

# Without any package (bash + socat):
MAC="AABBCCDDEEFF"
MAGIC=$(printf 'f%.0s' {1..12})$(printf "${MAC}%.0s" {1..16})
echo -ne $(echo "$MAGIC" | sed 's/../\\x&/g') | socat - UDP-DATAGRAM:255.255.255.255:9,broadcast
```

### C. Disable Unattended Upgrades Auto-Reboot

Ubuntu's unattended-upgrades can silently reboot the machine after kernel updates:

Edit `/etc/apt/apt.conf.d/50unattended-upgrades`:
```
Unattended-Upgrade::Automatic-Reboot "false";
```

Or disable entirely:
```bash
sudo systemctl disable --now unattended-upgrades.service
```

### D. Caffeine / Keep-Alive Process

A lightweight userspace approach — run a process that simulates activity:

```bash
# Simple approach: wiggle an X input every 5 minutes
while true; do xdotool key shift; sleep 300; done &
```

Or install `caffeine`:
```bash
sudo apt install caffeine
```

### E. BIOS/Firmware: AC Power Recovery

For headless machines, ensure the BIOS is set to "Power On" after AC power loss. This means if you unplug/replug the machine, it boots automatically without needing to press the power button. Check manufacturer documentation for UEFI/BIOS access.

### F. NetworkManager Prevent Ethernet Sleep

Ensure NetworkManager doesn't power-manage the ethernet interface:

```bash
nmcli connection modify "<connection-name>" connection.autoconnect yes
nmcli connection modify "<connection-name>" ipv4.may-fail no
```

Create `/etc/NetworkManager/conf.d/no-powersave.conf`:
```ini
[connection]
wifi.powersave = 2

[device]
match-device=interface-name:<ethernet-interface>
managed=1
```

---

## Diagnosis Playbook

When the machine becomes unreachable:

### Step 1: Determine if it's network-only or full suspend

| Symptom | Likely Cause |
|---------|-------------|
| Ping fails, fans spinning, hot | Network interface suspended (partial sleep or driver crash) |
| Ping fails, fans off, cool | Full system suspend/hibernate |
| Ping works, SSH timeout | Kernel alive, userspace frozen (OOM, GPU lockup) |
| Ping works, SSH works, no GPU | NVIDIA driver crashed |

### Step 2: Recovery Ladder

1. **Send Wake-on-LAN packet** (if configured) — non-destructive, try first
2. **Short press power button** — sends ACPI wake event if suspended
3. **Long press power button (5-10 sec)** — forces power off (kills running jobs)
4. **Unplug/replug power** — last resort (kills running jobs)

### Step 3: Post-Recovery Forensics

After getting back in, check what happened:

```bash
# When did the system last wake/sleep?
journalctl -b -1 | grep -i "suspend\|sleep\|wake\|PM:"

# Was there an OOM kill?
journalctl -b -1 | grep -i "oom\|killed process"

# NVIDIA driver issues?
dmesg | grep -i "nvidia\|nvrm\|gpu"

# What was the last systemd action before it went down?
journalctl -b -1 --no-pager | tail -50

# Check if logind triggered it
journalctl -b -1 -u systemd-logind | grep -i "suspend\|sleep\|idle"
```

---

## Quick Deployment

```bash
# Clone and run
git clone https://github.com/olympus-terminal/eyes-wide-open.git
cd eyes-wide-open
chmod +x disable-sleep.sh
sudo ./disable-sleep.sh
```

---

## Verification Checklist

Run after applying fixes to confirm everything is locked down:

```bash
echo "=== systemd targets ==="
systemctl is-enabled sleep.target suspend.target hibernate.target 2>&1

echo "=== systemd services ==="
systemctl is-enabled systemd-suspend.service systemd-hibernate.service 2>&1

echo "=== logind.conf ==="
grep -v "^#" /etc/systemd/logind.conf | grep -v "^$"

echo "=== GNOME power (user) ==="
gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type
gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout
gsettings get org.gnome.desktop.session idle-delay

echo "=== GDM dconf override ==="
cat /etc/dconf/db/gdm.d/disable-suspend.conf 2>/dev/null || echo "NOT SET"

echo "=== Inhibit locks ==="
systemd-inhibit --list

echo "=== Wake-on-LAN ==="
sudo ethtool <interface> | grep Wake-on
```

---

## Undoing Everything

If you ever need to re-enable sleep:

```bash
# Unmask targets
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target
sudo systemctl unmask systemd-suspend.service systemd-hibernate.service systemd-hybrid-sleep.service systemd-suspend-then-hibernate.service

# Reset logind
sudo cp /etc/systemd/logind.conf.backup /etc/systemd/logind.conf
sudo systemctl restart systemd-logind

# Reset GNOME
gsettings reset org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type
gsettings reset org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout
gsettings reset org.gnome.desktop.session idle-delay

# Remove GDM override
sudo rm /etc/dconf/db/gdm.d/disable-suspend.conf
sudo dconf update

# Disable inhibitor service
sudo systemctl disable --now nosuspend.service
```

---

## Platform Notes

### DGX Spark (GB10 Grace Blackwell)
- Headless — no native display, no TTY recovery
- Ethernet is the only reliable management interface
- HDMI is for convenience only; don't depend on it
- After power loss, may auto-power-on depending on firmware config
- The ethernet interface name and WiFi interface name may differ between boots if not pinned by udev

### General Linux Workstations
- GNOME on Wayland is more aggressive about idle detection than X11
- Multi-GPU systems with NVIDIA proprietary drivers can trigger suspend via display-off signals
- Some motherboards have their own BMC/IPMI for remote power — check if available

---

## License

MIT
