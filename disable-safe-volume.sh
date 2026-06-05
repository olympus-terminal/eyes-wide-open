#!/bin/bash

# eyes-wide-open: Disable Android "safe volume" auto-reduction via ADB
# Stops the phone from silently lowering media volume and nagging about hearing damage
# Requires: USB debugging enabled, device authorized

set -e

echo "=== eyes-wide-open: safe volume ==="
echo "Disabling automatic volume reduction on Android/MagicOS..."
echo ""

# Check ADB is available
if ! command -v adb &>/dev/null; then
    echo "ERROR: adb not found. Install Android platform-tools."
    exit 1
fi

# Check device is connected and authorized
DEVICE_STATE=$(adb get-state 2>/dev/null || true)
if [ "$DEVICE_STATE" != "device" ]; then
    echo "ERROR: No authorized device found (state: ${DEVICE_STATE:-not connected})"
    echo "       Enable USB debugging and approve the connection on the phone."
    exit 1
fi

DEVICE_MODEL=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
DEVICE_OS=$(adb shell getprop ro.build.display.id 2>/dev/null | tr -d '\r')
echo "Device: ${DEVICE_MODEL:-unknown} (${DEVICE_OS:-unknown})"
echo ""

# Show current state
echo "[1/3] Reading current safe volume settings..."
for key in audio_safe_volume_state audio_safe_volume_state_bt audio_safe_volume_state_wired; do
    val=$(adb shell settings get global "$key" 2>/dev/null | tr -d '\r')
    echo "      global/$key = ${val:-<not set>}"
done
val=$(adb shell settings get secure unsafe_volume_music_active_ms 2>/dev/null | tr -d '\r')
echo "      secure/unsafe_volume_music_active_ms = ${val:-<not set>}"
echo ""

# Disable safe volume enforcement
echo "[2/3] Disabling safe volume..."
adb shell settings put global audio_safe_volume_state 0
adb shell settings put global audio_safe_volume_state_bt 0
adb shell settings put global audio_safe_volume_state_wired 0
adb shell settings put secure unsafe_volume_music_active_ms 0
echo "      Done."
echo ""

# Verify
echo "[3/3] Verifying..."
ALL_OK=true
for key in audio_safe_volume_state audio_safe_volume_state_bt audio_safe_volume_state_wired; do
    val=$(adb shell settings get global "$key" 2>/dev/null | tr -d '\r')
    if [ "$val" != "0" ]; then
        echo "      WARN: global/$key = $val (expected 0)"
        ALL_OK=false
    fi
done
val=$(adb shell settings get secure unsafe_volume_music_active_ms 2>/dev/null | tr -d '\r')
if [ "$val" != "0" ]; then
    echo "      WARN: secure/unsafe_volume_music_active_ms = $val (expected 0)"
    ALL_OK=false
fi

if $ALL_OK; then
    echo "      All settings confirmed at 0."
    echo ""
    echo "Volume will no longer be automatically reduced."
    echo "NOTE: A factory reset or major OS update may re-enable this."
else
    echo ""
    echo "Some settings did not apply. Try rebooting and re-running."
fi
