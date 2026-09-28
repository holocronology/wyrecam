#!/bin/sh
#
# WyreCam installer. Runs from the installer kernel (factory_t31_ZMC6tiIDQN)
# when it finds this file on the SD card. Settings come from wyrecam.conf on
# the same card; you should not need to edit this file.
#
# LED signals:
#   blue on, red off    installing
#   red blinking        finished: unplug the camera and remove the SD card
#   red solid           failed: nothing was flashed unless upgrade.out says so

SD=/mnt/mmcblk0p1
CONF=$SD/wyrecam.conf
BACKUP_DIR=$SD/spi_backups
IMAGE=$SD/nor_full.bin
INSTALLER=$SD/factory_t31_ZMC6tiIDQN

echo "UPGRADE SCRIPT START"

gpio_out() {
  [ -d /sys/class/gpio/gpio$1 ] || echo $1 > /sys/class/gpio/export
  echo out > /sys/class/gpio/gpio$1/direction
  echo $2 > /sys/class/gpio/gpio$1/value
}

red_led() { gpio_out 38 $((1 - $1)); }   # active low
blue_led() { gpio_out 39 $((1 - $1)); }  # active low

# Stop here with a solid red LED. Never let the installer boot any further:
# its root account has no password.
fail() {
  echo "INSTALL FAILED: $*"
  sync
  blue_led 0
  red_led 1
  while true; do sleep 60; done
}

red_led 0
blue_led 1

# Settings
WIFI_SSID=''
WIFI_PASSWORD=''
ROOT_PASSWORD=''
ENABLE_SSH='no'
SSH_AUTHORIZED_KEY=''
if [ -f "$CONF" ]; then
  # Strip DOS line endings in case the file was edited on Windows.
  sed 's/\r$//' "$CONF" > /tmp/wyrecam.conf
  . /tmp/wyrecam.conf
  rm -f /tmp/wyrecam.conf
else
  echo "WARNING: $CONF not found, installing without Wi-Fi settings"
fi

if [ "$ENABLE_SSH" = "yes" ] && [ -z "$SSH_AUTHORIZED_KEY" ] && [ -z "$ROOT_PASSWORD" ]; then
  fail "ENABLE_SSH='yes' needs SSH_AUTHORIZED_KEY or ROOT_PASSWORD in wyrecam.conf"
fi
case "$ROOT_PASSWORD" in
  *:*) fail "ROOT_PASSWORD must not contain ':'" ;;
esac
if [ -n "$WIFI_PASSWORD" ]; then
  len=${#WIFI_PASSWORD}
  [ $len -ge 8 ] && [ $len -le 63 ] || fail "WIFI_PASSWORD must be 8 to 63 characters"
fi

# Check the image before touching the flash
[ -f "$IMAGE" ] || fail "$IMAGE not found"
flash_size=$(awk '/^mtd0:/ {print $2}' /proc/mtd)
[ -n "$flash_size" ] || fail "could not find mtd0 in /proc/mtd"
flash_size=$((0x$flash_size))
image_size=$(wc -c < "$IMAGE")
[ "$image_size" -eq "$flash_size" ] || \
  fail "$IMAGE is $image_size bytes but the flash is $flash_size bytes; refusing to flash it"

# Back up the current flash. Never overwrite an earlier backup: the first one
# is the only copy of the original Wyze firmware.
mkdir -p "$BACKUP_DIR" || fail "cannot create $BACKUP_DIR"
backup=$BACKUP_DIR/backup.bin
n=1
while [ -e "$backup" ]; do
  backup=$BACKUP_DIR/backup-$n.bin
  n=$((n + 1))
done
echo "Backing up the flash to $backup"
dd if=/dev/mtdblock0 of="$backup" bs=32768 || fail "backup failed (is the SD card full?)"
sync
[ "$(wc -c < "$backup")" -eq "$flash_size" ] || fail "backup $backup is incomplete (is the SD card full?)"

# Flash
echo "Flashing $IMAGE"
flashcp -v "$IMAGE" /dev/mtd0 || fail "flashcp failed; the camera may not boot. Re-run the install with this SD card"
sync

# Mount the new root filesystem and its (now empty) settings overlay
mtdpart add /dev/mtd0 env 0x40000 0x10000
mtdpart add /dev/mtd0 kernel 0x50000 0x300000
mtdpart add /dev/mtd0 rootfs 0x350000 0xa00000
mtdpart add /dev/mtd0 rootfs_data 0xD50000 0x2B0000
mtdinfo

mkdir -p /newroot /pivot
mount /dev/mtdblock3 /newroot || fail "cannot mount the new rootfs"

mtdblkdev=`awk -F ':' '/rootfs_data/ {print $1}' /proc/mtd | sed 's/mtd/mtdblock/'`
mtdchrdev=`grep 'rootfs_data' /proc/mtd | cut -d: -f1`
mount -t jffs2 /dev/${mtdblkdev} /newroot/overlay
if [ $? -ne 0 ] || { dmesg | grep "jffs2.*: Magic bitmask.*not found" > /dev/null 2>&1; } then
  echo "jffs2 health check error, format required!"
  flash_eraseall -j /dev/${mtdchrdev}
  mount -t jffs2 /dev/${mtdblkdev} /newroot/overlay || fail "cannot mount the settings partition"
fi

mount -t overlayfs overlayfs -o lowerdir=/newroot,upperdir=/newroot/overlay,ro /pivot || fail "cannot mount overlay"
mount -o remount,rw /pivot || fail "cannot remount overlay read-write"

# Root password: set it, or lock root logins if none was given
if [ -n "$ROOT_PASSWORD" ]; then
  echo "root:$ROOT_PASSWORD" | chpasswd -c sha512 || echo "root:$ROOT_PASSWORD" | chpasswd || fail "chpasswd failed"
  hash=$(grep '^root:' /etc/shadow | cut -d: -f2)
  echo "Setting the root password"
else
  hash='*'
  echo "No ROOT_PASSWORD given: root logins are locked"
fi
sed -i "s|^root:[^:]*:|root:${hash}:|" /pivot/etc/shadow || fail "cannot update /etc/shadow"

# Wi-Fi. wpa_passphrase stores a derived key, not the password itself.
if [ -n "$WIFI_SSID" ]; then
  {
    echo "ctrl_interface=/var/run/wpa_supplicant"
    echo "ap_scan=1"
    echo
    if [ -n "$WIFI_PASSWORD" ]; then
      wpa_passphrase "$WIFI_SSID" "$WIFI_PASSWORD" | grep -v '^[[:space:]]*#psk=' | awk '{ print } /^network=\{/ { print "\tscan_ssid=1" }'
    else
      printf 'network={\n\tscan_ssid=1\n\tssid="%s"\n\tkey_mgmt=NONE\n}\n' "$WIFI_SSID"
    fi
  } > /pivot/etc/wpa_supplicant.conf || fail "cannot write wpa_supplicant.conf"
  chmod 600 /pivot/etc/wpa_supplicant.conf
  grep -qE 'psk=|key_mgmt=NONE' /pivot/etc/wpa_supplicant.conf || fail "wpa_passphrase failed"
  echo "Wi-Fi configured for $WIFI_SSID"
else
  echo "WARNING: no WIFI_SSID in wyrecam.conf, the camera will not join a network"
fi

# SSH (off unless asked for). Key-only when a key is given.
if [ "$ENABLE_SSH" = "yes" ]; then
  mkdir -p /pivot/etc/default /pivot/etc/dropbear
  if [ -n "$SSH_AUTHORIZED_KEY" ]; then
    chmod 700 /pivot/etc/dropbear
    echo "$SSH_AUTHORIZED_KEY" > /pivot/etc/dropbear/authorized_keys
    chmod 600 /pivot/etc/dropbear/authorized_keys
    printf 'DROPBEAR_ENABLE=yes\nDROPBEAR_ARGS="-s"\n' > /pivot/etc/default/dropbear
    echo "SSH enabled (public key only)"
  else
    printf 'DROPBEAR_ENABLE=yes\n' > /pivot/etc/default/dropbear
    echo "SSH enabled (root password)"
  fi
else
  echo "SSH disabled"
fi

# HomeKit setup code. Without these files the camera uses the public default
# code 0107-2024, which anyone on your network can use to pair with it first.
if [ -f $SD/homekit/40.10 ] && [ -f $SD/homekit/40.11 ]; then
  [ "$(wc -c < $SD/homekit/40.10)" -eq 400 ] && [ "$(wc -c < $SD/homekit/40.11)" -eq 5 ] || \
    fail "homekit/40.10 or homekit/40.11 has the wrong size; re-run scripts/homekit_setup_code.py"
  mkdir -p /pivot/PositronStore/.HomeKitStore
  cp $SD/homekit/40.10 $SD/homekit/40.11 /pivot/PositronStore/.HomeKitStore/ || fail "cannot install HomeKit setup code"
  echo "Installed your private HomeKit setup code"
else
  echo "WARNING: no homekit/ folder on the SD card. The camera uses the PUBLIC setup code 0107-2024."
  echo "WARNING: pair it right away, or re-install with a code from scripts/homekit_setup_code.py"
fi

sync
umount /pivot
umount /newroot/overlay
umount /newroot
sync

# Make sure leaving the card in cannot re-run the install, and remove the
# secrets from the card. The backups stay: copy them somewhere safe.
mv "$INSTALLER" "$INSTALLER.done" || echo "WARNING: could not rename $INSTALLER; remove the SD card before rebooting"
rm -f "$CONF"
rm -rf $SD/homekit
sync

echo "UPGRADE SCRIPT FINISHED"

# Blink the red light forever (don't boot the installer any further)
blue_led 0
while true; do
  red_led 1
  sleep 1
  red_led 0
  sleep 1
done
