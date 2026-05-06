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
echo "[1/5] Masking systemd sleep targets and services..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
systemctl mask systemd-suspend.service systemd-hibernate.service systemd-hybrid-sleep.service systemd-suspend-then-hibernate.service 2>/dev/null || true
echo "      Done."

# 2. Configure logind.conf
echo "[2/5] Configuring logind.conf..."
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

# 3. GNOME user session power settings
echo "[3/5] Configuring GNOME power settings for user '$ACTUAL_USER'..."
if command -v gsettings &> /dev/null && [ "$ACTUAL_USER" != "root" ]; then
    sudo -u "$ACTUAL_USER" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
    sudo -u "$ACTUAL_USER" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0 2>/dev/null || true
    sudo -u "$ACTUAL_USER" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0 2>/dev/null || true
    sudo -u "$ACTUAL_USER" gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'nothing' 2>/dev/null || true
    sudo -u "$ACTUAL_USER" gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action 'nothing' 2>/dev/null || true
    sudo -u "$ACTUAL_USER" gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
    sudo -u "$ACTUAL_USER" gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || true
    sudo -u "$ACTUAL_USER" gsettings set org.gnome.desktop.screensaver idle-activation-enabled false 2>/dev/null || true
    echo "      Done."
else
    echo "      Skipped (gsettings not found or running as root)"
fi

# 4. GDM greeter power settings (dconf system override)
echo "[4/5] Configuring GDM greeter anti-suspend..."
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
lock-enabled=false
idle-activation-enabled=false
EOF

dconf update 2>/dev/null || true
echo "      Done."

# 5. Install permanent sleep inhibitor service
echo "[5/5] Installing nosuspend inhibitor service..."
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

echo ""
echo "=== All layers configured ==="
echo ""
echo "Summary of what was disabled:"
echo "  - systemd sleep/suspend/hibernate targets: MASKED"
echo "  - systemd sleep services: MASKED"
echo "  - logind idle/button actions: IGNORE"
echo "  - GNOME session power management: NOTHING/DISABLED"
echo "  - GDM greeter power management: NOTHING/DISABLED"
echo "  - Permanent sleep inhibitor: ACTIVE"
echo ""
echo "NOTE: logind changes require a restart to fully take effect."
echo ""
read -p "Restart systemd-logind now? (will kill desktop session) [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl restart systemd-logind
    echo "Done. You may need to log back in."
else
    echo "Run 'sudo systemctl restart systemd-logind' when ready."
fi
