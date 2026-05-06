#!/bin/bash

# eyes-wide-open: Verify all anti-suspend measures are in place
# Run without sudo for basic checks; with sudo for full report

echo "=== eyes-wide-open verification ==="
echo ""

PASS=0
FAIL=0

check() {
    if [ $1 -eq 0 ]; then
        echo "  [OK]   $2"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $2"
        FAIL=$((FAIL + 1))
    fi
}

echo "--- systemd targets ---"
for target in sleep.target suspend.target hibernate.target hybrid-sleep.target; do
    systemctl is-enabled "$target" 2>&1 | grep -q "masked"
    check $? "$target is masked"
done

echo ""
echo "--- systemd services ---"
for svc in systemd-suspend.service systemd-hibernate.service systemd-hybrid-sleep.service systemd-suspend-then-hibernate.service; do
    systemctl is-enabled "$svc" 2>&1 | grep -q "masked"
    check $? "$svc is masked"
done

echo ""
echo "--- logind.conf ---"
LOGIND="/etc/systemd/logind.conf"
grep -q "^IdleAction=ignore" "$LOGIND" 2>/dev/null
check $? "IdleAction=ignore"
grep -q "^HandleLidSwitch=ignore" "$LOGIND" 2>/dev/null
check $? "HandleLidSwitch=ignore"

echo ""
echo "--- GNOME session ---"
if command -v gsettings &> /dev/null; then
    VAL=$(gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 2>/dev/null)
    [ "$VAL" = "'nothing'" ]
    check $? "sleep-inactive-ac-type = nothing (got: $VAL)"

    VAL=$(gsettings get org.gnome.desktop.session idle-delay 2>/dev/null)
    echo "$VAL" | grep -q "0"
    check $? "idle-delay = 0 (got: $VAL)"
else
    echo "  [SKIP] gsettings not available"
fi

echo ""
echo "--- GDM dconf override ---"
if [ -f /etc/dconf/db/gdm.d/disable-suspend.conf ]; then
    grep -q 'sleep-inactive-ac-type="nothing"' /etc/dconf/db/gdm.d/disable-suspend.conf
    check $? "GDM suspend override exists"
else
    check 1 "GDM suspend override exists"
fi

echo ""
echo "--- Sleep inhibitor service ---"
systemctl is-active nosuspend.service &>/dev/null
check $? "nosuspend.service is active"

echo ""
echo "--- Active inhibit locks ---"
systemd-inhibit --list 2>/dev/null | grep -q "nosuspend" 2>/dev/null
check $? "nosuspend inhibit lock held"

echo ""
echo "--- Wake-on-LAN ---"
if command -v ethtool &> /dev/null; then
    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo); do
        WOL=$(sudo ethtool "$iface" 2>/dev/null | grep "Wake-on:" | tail -1 | awk '{print $2}')
        if [ -n "$WOL" ]; then
            [ "$WOL" = "g" ]
            check $? "WoL on $iface = g (got: $WOL)"
        fi
    done
else
    echo "  [SKIP] ethtool not installed"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ $FAIL -gt 0 ]; then
    echo "Run 'sudo ./disable-sleep.sh' to fix."
    exit 1
fi
