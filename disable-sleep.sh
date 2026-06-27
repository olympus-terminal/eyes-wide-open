#!/bin/bash

# eyes-wide-open: Comprehensive anti-suspend for Linux workstations
# Disables ALL known sleep/suspend paths across systemd, logind, GNOME, and GDM
# Run with sudo

set -e

echo "=== eyes-wide-open ==="
echo "Disabling all sleep/suspend/hibernate paths..."
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Run as root (sudo ./disable-sleep.sh)"
    exit 1
fi

ACTUAL_USER="${SUDO_USER:-$USER}"

# 1. Mask systemd targets AND services
echo "[1/7] Masking systemd sleep targets and services..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
systemctl mask systemd-suspend.service systemd-hibernate.service systemd-hybrid-sleep.service systemd-suspend-then-hibernate.service 2>/dev/null || true
echo "      Done."

# 2. Disable NVIDIA suspend/hibernate/resume services
# CRITICAL: These services write to /proc/driver/nvidia/suspend and cause GPU crashes on resume
# They get re-enabled after every driver update - must re-run this script!
echo "[2/7] Disabling NVIDIA power management services..."
if systemctl list-unit-files | grep -q nvidia-suspend; then
    systemctl disable nvidia-suspend nvidia-hibernate nvidia-resume 2>/dev/null || true
    systemctl stop nvidia-suspend nvidia-hibernate nvidia-resume 2>/dev/null || true
    echo "      Disabled nvidia-suspend, nvidia-hibernate, nvidia-resume"
else
    echo "      Skipped (NVIDIA suspend services not found)"
fi
echo "      Done."

# 3. Configure logind.conf
echo "[3/7] Configuring logind.conf..."
LOGIND_CONF="/etc/systemd/logind.conf"

if [ ! -f "${LOGIND_CONF}.backup" ]; then
    cp "$LOGIND_CONF" "${LOGIND_CONF}.backup"
    echo "      Backup created at ${LOGIND_CONF}.backup"
fi

declare -A settings=(
    ["HandleSuspendKey"]="ignore"
    ["HandleHibernateKey"]="ignore"
    ["HandleLidSwitch"]="ignore"
    ["HandleLidSwitchExternalPower"]="ignore"
    ["HandleLidSwitchDocked"]="ignore"
    ["IdleAction"]="ignore"
    ["IdleActionSec"]="0"
)

for key in "${!settings[@]}"; do
    value="${settings[$key]}"
    if grep -q "^${key}=" "$LOGIND_CONF"; then
        sed -i "s/^${key}=.*/${key}=${value}/" "$LOGIND_CONF"
    elif grep -q "^#${key}=" "$LOGIND_CONF"; then
        sed -i "s/^#${key}=.*/${key}=${value}/" "$LOGIND_CONF"
    else
        sed -i "/^\[Login\]/a ${key}=${value}" "$LOGIND_CONF"
    fi
done
echo "      Done."

# 4. GNOME user session power settings
echo "[4/7] Configuring GNOME power settings for user '$ACTUAL_USER'..."
if command -v gsettings &> /dev/null && [ "$ACTUAL_USER" != "root" ]; then
    sudo -u "$ACTUAL_USER" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
    sudo -u "$ACTUAL_USER" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0 2>/dev/null || true
    sudo -u "$ACTUAL_USER" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0 2>/dev/null || true
    sudo -u "$ACTUAL_USER" gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'nothing' 2>/dev/null || true
    sudo -u "$ACTUAL_USER" gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action 'nothing' 2>/dev/null || true
    sudo -u "$ACTUAL_USER" gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
    sudo -u "$ACTUAL_USER" gsettings set org.gnome.desktop.screensaver idle-activation-enabled false 2>/dev/null || true
    echo "      Done."
else
    echo "      Skipped (gsettings not found or running as root)"
fi

# 5. GDM greeter power settings (dconf system override)
echo "[5/7] Configuring GDM greeter anti-suspend..."
mkdir -p /etc/dconf/db/gdm.d
cat > /etc/dconf/db/gdm.d/disable-suspend.conf << 'EOF'
[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type="nothing"
sleep-inactive-ac-timeout=0
sleep-inactive-battery-type="nothing"
sleep-inactive-battery-timeout=0

[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/desktop/screensaver]
idle-activation-enabled=false
EOF

dconf update 2>/dev/null || true
echo "      Done."

# 6. Install permanent sleep inhibitor service
echo "[6/7] Installing nosuspend inhibitor service..."
cat > /etc/systemd/system/nosuspend.service << 'EOF'
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
EOF

systemctl daemon-reload
systemctl enable --now nosuspend.service 2>/dev/null || true
echo "      Done."

# 7. NVIDIA driver settings (prevents GSP firmware crashes)
# CRITICAL: Hotplug detection polling causes Xid 119/120 GSP crashes
echo "[7/7] Configuring NVIDIA driver settings..."
if lsmod | grep -q nvidia; then
    NVIDIA_CONF="/etc/modprobe.d/nvidia-eyes-wide-open.conf"
    cat > "$NVIDIA_CONF" << 'NVIDIACONF'
# eyes-wide-open: NVIDIA stability settings
# CRITICAL: Disable display hotplug detection - prevents GSP firmware crashes (Xid 119/120)
# Without this, gnome-shell's connector polling can hang the GPU firmware
options nvidia NVreg_EnableHotplugDetection=0
# Disable dynamic power management (prevents GPU sleep/wake issues)
options nvidia NVreg_DynamicPowerManagement=0x00
# Preserve video memory on suspend (if suspend somehow happens)
options nvidia NVreg_PreserveVideoMemoryAllocations=1
NVIDIACONF
    echo "      NVIDIA config written to $NVIDIA_CONF"
    echo "      NOTE: Run 'sudo update-initramfs -u' and reboot to apply"
else
    echo "      Skipped (NVIDIA driver not loaded)"
fi
echo "      Done."

echo ""
echo "=== All layers configured ==="
echo ""
echo "Summary of what was disabled:"
echo "  - systemd sleep/suspend/hibernate targets: MASKED"
echo "  - systemd sleep services: MASKED"
echo "  - NVIDIA suspend/hibernate/resume services: DISABLED"
echo "  - logind idle/button actions: IGNORE"
echo "  - GNOME session power management: NOTHING/DISABLED"
echo "  - GDM greeter power management: NOTHING/DISABLED"
echo "  - Permanent sleep inhibitor: ACTIVE"
echo "  - NVIDIA hotplug detection: DISABLED"
echo ""
echo "IMPORTANT:"
echo "  1. Run 'sudo update-initramfs -u' to apply NVIDIA settings"
echo "  2. Reboot for all changes to take effect"
echo "  3. Re-run this script after NVIDIA driver updates!"
echo ""
read -p "Restart systemd-logind now? (will kill desktop session) [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl restart systemd-logind
    echo "Done. You may need to log back in."
else
    echo "Run 'sudo systemctl restart systemd-logind' when ready."
fi
