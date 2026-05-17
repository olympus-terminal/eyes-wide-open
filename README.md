# JMS567 USB-SATA Controller Troubleshooting Guide

## Overview

This guide documents troubleshooting steps for JMicron JMS567 USB-to-SATA bridge controllers that report incorrect drive capacities or fail to mount properly on Linux systems.

## Problem Symptoms

### 1. Incorrect Capacity Reporting
- Drive shows impossibly large size (e.g., 115.5P instead of 22TB)
- `lsblk` shows capacity in petabytes
- Kernel messages show: `Very big device. Trying to use READ CAPACITY(16)`
- Reported sector count is corrupted (e.g., `253879390758630` which is `0xE6E6E6E6E6E6` in hex)

### 2. Input/Output Errors
- Cannot read directory contents
- `ls: reading directory '.': Input/output error`
- Kernel logs show: `attempt to access beyond end of device`

### 3. Filesystem Corruption After Improper Shutdown
- exFAT boot sector mismatch
- `boot region is corrupted` messages from fsck.exfat
- Drive was working fine until system crashed/rebooted with drive attached

## Common Causes

1. **Hardware failure in JMS567 USB bridge chip** - The controller itself has failed or firmware is corrupted
2. **Improper shutdown while drive was mounted** - Corrupts exFAT boot sectors
3. **Known JMS567 firmware bug** - Reports incorrect capacity via READ CAPACITY(16)
4. **Multiple controllers in multi-bay enclosures** - Some bays may have failed controllers while others work

## Diagnostic Steps

### Check Drive Detection

```bash
# Check if drive is detected and what size it reports
lsblk

# Check USB device information
lsusb | grep JMicron
dmesg | grep -i "usb" | tail -30

# Check for capacity errors
dmesg | grep "READ CAPACITY"
```

### Identify Controller Issues

Look for these patterns in `dmesg`:

```
# Hardware failure pattern - repeated 0xE6 bytes
sd 0:0:0:0: [sda] 253879390758630 512-byte logical blocks: (130 PB/115 PiB)

# Quirk being applied
usb-storage 4-3:1.0: Quirks match for vid 152d pid 0567: 5000000

# I/O errors
attempt to access beyond end of device
```

## Solutions

### Solution 1: Try a Different Port/Slot (RECOMMENDED FIRST)

If you have a multi-bay enclosure:

1. **Unplug the external drive**
2. **Move drive to a different bay/slot** in the enclosure
3. **Plug back in and check:**
   ```bash
   lsblk
   dmesg | tail -30
   ```
4. If size now shows correctly (e.g., 21.8T instead of 115.5P), the original slot has a failed controller

**This is the quickest fix and often works immediately.**

### Solution 2: Apply USB Storage Quirks

If the controller needs help but isn't completely dead:

```bash
# Unplug drive first

# Try capacity fix quirk
sudo modprobe -r uas usb_storage
sudo modprobe usb_storage quirks=152d:0567:c

# Plug drive back in
lsblk
```

Common quirk flags for JMS567:
- `c` - Use READ CAPACITY(10) instead of (16)
- `u` - Ignore device capacity, recalculate
- `0x00000010` - US_FL_CAPACITY_OK flag

### Solution 3: Fix exFAT Boot Sector Corruption

If the drive is detected with correct size but won't mount or shows corruption:

#### Step 1: Try fsck

```bash
# Unmount if mounted
sudo umount /dev/sda

# Run filesystem check
sudo fsck.exfat -y /dev/sda
```

#### Step 2: Use TestDisk if Boot Sectors Don't Match

```bash
sudo testdisk /dev/sda
```

In TestDisk:
1. Select "No Log" or "Create"
2. Select the disk
3. Choose "None" for partition table type
4. Choose "Advanced"
5. Select the partition
6. Choose "Boot" to analyze boot sector
7. If it shows "Sectors are not identical", TestDisk can sync them
8. Look for "Backup BS" or similar option to synchronize
9. Press 'Q' to quit when done

#### Step 3: Mount and Verify

```bash
sudo mkdir -p /media/drn/External
sudo mount /dev/sda /media/drn/External
ls -la /media/drn/External
```

### Solution 4: Remove the Drive from Enclosure

If all else fails:

1. Open the USB enclosure
2. Connect the drive directly via SATA, or
3. Use a different USB-SATA adapter/enclosure

The actual hard drive is likely fine - the USB bridge controller has failed.

## Important Notes

### About Quirks and Rebooting

**WARNING:** Do not reboot with external drive plugged in when using custom quirks. This can cause:
- GRUB authentication issues
- Kernel boot problems
- Further filesystem corruption

**Best practice:**
1. Always safely eject: `sudo umount /dev/sdX`
2. Unplug drive before rebooting
3. Plug drive back in after system is fully booted

### Device Name Changes

When you switch slots in a multi-bay enclosure, the device name may change:
- `/dev/sda` → `/dev/sdb`
- Mount point may change: `/media/drn/External` → `/media/drn/External1`

**Always check `lsblk` to see the current device name.**

### Clean Up Stale Mounts

If you get I/O errors but the drive is working:

```bash
# Check all mounts
mount | grep sd

# Unmount the old broken mount
sudo umount /media/drn/External

# Use the new correct mount point
cd /media/drn/External1
```

## JMS567 Controller Information

**Vendor ID:** 152d (JMicron Technology Corp.)
**Product ID:** 0567 (JMS567 SATA 6Gb/s bridge)
**Common in:** USB 3.0 external hard drive enclosures

**Known Issues:**
- Firmware bug returning `0xE6E6E6E6E6E6` as capacity
- READ CAPACITY(16) returns incorrect values
- Some units fail completely while others in same enclosure work

**Better Alternatives:**
- ASMedia ASM1351/ASM1352
- JMicron JMS578 (newer, more reliable)

## Troubleshooting Checklist

- [ ] Check if drive size looks correct in `lsblk`
- [ ] If size is wrong (petabytes), try different slot/port
- [ ] If still wrong, apply USB quirks
- [ ] If size is correct but won't mount, run `fsck.exfat`
- [ ] If fsck fails, use TestDisk to repair boot sectors
- [ ] Check for device name changes (`sda` vs `sdb`)
- [ ] Verify mount point is correct
- [ ] Clean up any stale mounts
- [ ] Always safely eject before unplugging

## Prevention

1. **Always safely eject drives:**
   ```bash
   sudo umount /dev/sdX
   # Wait for command to complete
   # Then unplug
   ```

2. **Don't reboot with external drives attached** (especially with quirks loaded)

3. **Use UPS or backup power** to prevent improper shutdowns

4. **Label good/bad slots** in multi-bay enclosures

5. **Consider replacing enclosures** with known-bad JMS567 controllers

## Recovery Success Story

This guide was created after successfully recovering a 22TB exFAT drive that:
- Initially showed as 115.5P (corrupted JMS567 controller)
- Had boot sector corruption from improper shutdown
- Was fixed by moving to different slot in same enclosure
- Required TestDisk to sync boot sectors
- All 4.1TB of data recovered successfully

## Additional Resources

- [Linux USB Storage Quirks Documentation](https://www.kernel.org/doc/html/latest/usb/storage.html)
- [TestDisk Documentation](https://www.cgsecurity.org/wiki/TestDisk)
- [exFAT Filesystem Utilities](https://github.com/exfatprogs/exfatprogs)

## Contributing

If you've encountered similar issues or have additional solutions, please open an issue or pull request.

## License

MIT License - Feel free to use and adapt this guide.
