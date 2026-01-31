#!/bin/bash

# eyes-wide-open: Disable all sleep/suspend/hibernate on Linux
# Run with sudo

set -e

echo "=== eyes-wide-open ==="
echo "Disabling sleep/suspend/hibernate..."
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo ./disable-sleep.sh)"
    exit 1
fi

# 1. Mask systemd targets
echo "[1/3] Masking systemd sleep targets..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
echo "      Done."

# 2. Configure logind.conf
echo "[2/3] Configuring logind.conf..."
LOGIND_CONF="/etc/systemd/logind.conf"

# Backup original
if [ ! -f "${LOGIND_CONF}.backup" ]; then
    cp "$LOGIND_CONF" "${LOGIND_CONF}.backup"
    echo "      Backup created at ${LOGIND_CONF}.backup"
fi

# Add or update settings
declare -A settings=(
    ["HandleSuspendKey"]="ignore"
    ["HandleHibernateKey"]="ignore"
    ["HandleLidSwitch"]="ignore"
    ["IdleAction"]="ignore"
)

for key in "${!settings[@]}"; do
    value="${settings[$key]}"
    if grep -q "^${key}=" "$LOGIND_CONF"; then
        sed -i "s/^${key}=.*/${key}=${value}/" "$LOGIND_CONF"
    elif grep -q "^#${key}=" "$LOGIND_CONF"; then
        sed -i "s/^#${key}=.*/${key}=${value}/" "$LOGIND_CONF"
    else
        echo "${key}=${value}" >> "$LOGIND_CONF"
    fi
done
echo "      Done."

# 3. GNOME settings (if gsettings available and GNOME session)
echo "[3/3] Configuring GNOME power settings..."
if command -v gsettings &> /dev/null; then
    # Run as the actual user, not root
    ACTUAL_USER="${SUDO_USER:-$USER}"
    if [ "$ACTUAL_USER" != "root" ]; then
        sudo -u "$ACTUAL_USER" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0 2>/dev/null || true
        sudo -u "$ACTUAL_USER" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0 2>/dev/null || true
        sudo -u "$ACTUAL_USER" gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'nothing' 2>/dev/null || true
        sudo -u "$ACTUAL_USER" gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action 'nothing' 2>/dev/null || true
        echo "      Done."
    else
        echo "      Skipped (run as regular user to configure GNOME settings)"
    fi
else
    echo "      Skipped (gsettings not found - not using GNOME?)"
fi

echo ""
echo "=== Configuration complete ==="
echo ""
echo "NOTE: You need to restart systemd-logind for changes to take effect."
echo "      This will log you out of your current session!"
echo ""
read -p "Restart systemd-logind now? [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl restart systemd-logind
    echo "Done. You may need to log back in."
else
    echo "Run 'sudo systemctl restart systemd-logind' when ready."
fi
