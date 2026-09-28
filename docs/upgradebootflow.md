# Boot loading and upgrading sequences
## SD card structure

The SD Card contains 3 files
### factory_t31_ZMC6tiIDQN
This is the file that the wyze stock boot loader (and our replacement u-boot) looks for on the SD card.  When the boot loader finds this file it boots the file as a kernel with the following cmdline parameters

```
console=ttyS1,115200n8 mem=64M@0x0 rmem=64M@0x4000000 root=/dev/ram0 rw rdinit=/linuxrc
```

This instructs the kernel to boot from it's own internal initramfs.  factory_t31_ZMC6tiIDQN contains an initramfs which is capable of upgrading the nor flash rom from the MMC image.  This file must be less than 5242880 bytes or the factory u-boot doesn't copy the whole image to ram before trying to boot it.

### nor_full.bin
This file contains the concatenation of the wyrecam u-boot image (including patches for ingenic and to also look for factory_t31_ZMC6tiIDQN), the wyrecam built kernel (without the initramfs) and the wyrecam rootfs.  It the size of the nor flash, so writing this file to the nor will overwrite overlayfs resetting any configuration contained therein.

### upgrade.sh
Only the installer kernel (initramfs boot) runs this file; the installed system ignores the SD card. When first installing on a factory flashed device, this backs up the factory image (never overwriting an earlier backup), overwrites the nor flash and configures the device from `wyrecam.conf`. Afterwards it deletes `wyrecam.conf` and `homekit/` from the card and renames `factory_t31_ZMC6tiIDQN` to `factory_t31_ZMC6tiIDQN.done` so the install does not repeat.

### wyrecam.conf
Wi-Fi, root password and SSH settings for the install (see the README). `homekit/40.10` and `homekit/40.11`, created by `scripts/homekit_setup_code.py`, optionally provide a private HomeKit setup code.


## Boot procedure to install wyrecam from the factory image
* T31 loads the factory u-boot image from the nor and boots it
* Factory u-boot image looks for factory_t31_ZMC6tiIDQN and boots it with cmdline parameters that instruct it to boot from it's own initramfs
* wyrecam kernel (with initramfs) boots and executes upgrade.sh
* upgrade.sh backs up the factory image (SAVE THIS FROM THE SD CARD TO REVERT LATER)
* upgrade.sh flashes the nor flash with nor_full.bin
* upgrade.sh applies the settings from wyrecam.conf and the homekit/ setup code
* upgrade.sh blinks the led to indicate that the upgrade process is complete

## Boot procedure during a normal wyrecam boot
* T31 loads the wyrecam u-boot image from the nor and boots it
* Factory u-boot image looks for factory_t31_ZMC6tiIDQN and doesn't find it, so boots nor kernel
* wyrecam nor kernel (without initramfs) boots; it never runs upgrade.sh or anything else from the SD card

## Boot procedure during an upgrade from an older wyrecam image
* T31 loads the wyrecam u-boot image from the nor and boots it
* Wyrecam u-boot image looks for factory_t31_ZMC6tiIDQN and boots it with cmdline parameters that instruct it to boot from the internal initramfs
* wyrecam kernel (with initramfs) boots and executes upgrade.sh
* upgrade.sh backs up the old image
* upgrade.sh flashes the nor flash with nor_full.bin

## Boot procedure during an downgrade from wyrecam back to wyze image
* T31 loads the wyrecam u-boot image from the nor and boots it
* Wyrecam u-boot image looks for wyrecam factory_t31_ZMC6tiIDQN and boots it with cmdline parameters that instruct it to boot from the internal initramfs
* wyrecam kernel (with initramfs) boots and executes upgrade.sh
* upgrade.sh backs up the wyrecam image (to backup-N.bin; backup.bin is never overwritten)
* upgrade.sh flashes the nor flash with the factory wyze image backed up during the first install of wyrecam (copy backup.bin to nor_full.bin on the card first)
* upgrade.sh sees the image has no WyreCam squashfs at 0x350000, so it skips all WyreCam configuration (the stock partition layout differs; WyreCam's rootfs_data would overlap the stock aback/cfg/para partitions)


