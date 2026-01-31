# eyes-wide-open

Linux configuration to prevent system freezing/suspending during idle. Disables all sleep, suspend, and hibernate functionality at multiple levels.

## The Problem

Linux systems can freeze or become unresponsive when entering sleep/suspend states, especially with NVIDIA GPUs or certain hardware configurations. This is particularly frustrating for workstations that need to remain available.

## The Solution

Disable sleep/suspend at three levels:
1. **systemd targets** - Nuclear option, completely disables sleep capability
2. **logind configuration** - Ignores hardware buttons and idle actions
3. **GNOME settings** - Desktop environment power management

---

## Quick Setup

```bash
# Clone and run
git clone https://github.com/olympus-terminal/eyes-wide-open.git
cd eyes-wide-open
chmod +x disable-sleep.sh
sudo ./disable-sleep.sh
```

---

## Manual Configuration

### 1. Mask systemd Sleep Targets

This completely disables the system's ability to sleep/suspend/hibernate:

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

To verify:
```bash
systemctl status sleep.target suspend.target hibernate.target
# Should show "masked" for all targets
```

To undo:
```bash
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

### 2. Configure logind

Edit `/etc/systemd/logind.conf` and add/modify under the `[Login]` section:

```ini
[Login]
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
IdleAction=ignore
```

Then restart logind:
```bash
sudo systemctl restart systemd-logind
```

**Note:** This will log you out of your current session. Save your work first.

### 3. GNOME Power Settings (if using GNOME)

```bash
# Disable automatic sleep on AC and battery (0 = never)
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0

# Lid close does nothing
gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action 'nothing'
```

To verify current settings:
```bash
gsettings list-recursively org.gnome.settings-daemon.plugins.power
```

---

## Verification

After applying all settings, verify with:

```bash
# Check systemd targets are masked
systemctl status sleep.target suspend.target hibernate.target hybrid-sleep.target

# Check logind config
grep -v "^#" /etc/systemd/logind.conf | grep -v "^$"

# Check GNOME settings (if applicable)
gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout
# Should return: uint32 0
```

---

## Troubleshooting

### System still sleeps?

1. Check for other power management tools: `dpkg -l | grep -E "(tlp|powertop|laptop-mode)"`
2. Check NVIDIA settings if you have an NVIDIA GPU
3. Look for desktop environment specific power settings

### Want to re-enable sleep?

```bash
# Unmask systemd targets
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Reset logind.conf to defaults (comment out or remove the lines)
sudo nano /etc/systemd/logind.conf
sudo systemctl restart systemd-logind

# Reset GNOME settings
gsettings reset org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout
gsettings reset org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout
gsettings reset org.gnome.settings-daemon.plugins.power lid-close-ac-action
gsettings reset org.gnome.settings-daemon.plugins.power lid-close-battery-action
```

---

## License

MIT
