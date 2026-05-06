#!/bin/bash

# eyes-wide-open: Post-incident diagnosis
# Run this AFTER recovering from an unexpected suspend/freeze
# to determine what triggered it

echo "=== eyes-wide-open: Post-Incident Diagnosis ==="
echo ""
echo "Analyzing previous boot's logs for suspend/sleep events..."
echo ""

echo "--- Last boot time ---"
who -b
uptime
echo ""

echo "--- Suspend/sleep events in previous boot ---"
journalctl -b -1 --no-pager 2>/dev/null | grep -i "suspend\|sleep\|hibernate\|PM: suspend\|PM: resume" | tail -20
echo ""

echo "--- OOM kills in previous boot ---"
journalctl -b -1 --no-pager 2>/dev/null | grep -i "oom\|killed process\|out of memory" | tail -10
echo ""

echo "--- systemd-logind actions in previous boot ---"
journalctl -b -1 -u systemd-logind --no-pager 2>/dev/null | grep -i "suspend\|sleep\|idle\|lid\|power" | tail -10
echo ""

echo "--- NVIDIA/GPU issues (current boot) ---"
dmesg 2>/dev/null | grep -i "nvidia\|nvrm\|gpu\|error\|fault" | tail -10
echo ""

echo "--- Power supply / ACPI events (previous boot) ---"
journalctl -b -1 --no-pager 2>/dev/null | grep -i "acpi\|power.*button\|battery\|ac_adapter" | tail -10
echo ""

echo "--- NetworkManager state changes (previous boot) ---"
journalctl -b -1 -u NetworkManager --no-pager 2>/dev/null | grep -i "sleep\|suspend\|disconn\|deactivat" | tail -10
echo ""

echo "--- Current inhibit locks ---"
systemd-inhibit --list 2>/dev/null
echo ""

echo "--- Last 10 lines before previous shutdown ---"
journalctl -b -1 --no-pager 2>/dev/null | tail -10
echo ""

echo "=== Diagnosis complete ==="
echo "If nothing above shows a clear trigger, the cause was likely:"
echo "  1. GDM greeter suspend (check /etc/dconf/db/gdm.d/)"
echo "  2. Kernel-level ACPI event not logged to journald"
echo "  3. Hardware-initiated power state change (check BIOS settings)"
