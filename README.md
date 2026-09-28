# WyreCam: Simple, Secure Home Security Camera
 
WyreCam is an open-source firmware for the Wyze v3 camera that integrates seamlessly with HomeKit Secure Video (HKSV). WyreCam offers enhanced privacy, security, and convenience.

## Benefits of WyreCam HomeKit Secure Video (HKSV)
 
- **End-to-End Encryption**: HKSV ensures that your video recordings are fully encrypted, providing a higher level of privacy and security.
- **Rich Notifications**: Receive detailed notifications that include snapshots and recorded video clips, keeping you informed of important events.
- **iCloud Storage**: Store your recordings securely in iCloud without needing an additional subscription service.
- **Smart Detection**: HKSV can recognize and notify you about specific activities, such as animals, people, and vehicles.
- **Familiar Face Recognition**: Use your iOS photo library to recognize familiar faces in your camera footage.
- **Integration with HomeKit**: Seamlessly integrate with your existing HomeKit setup, enabling you to manage all your smart home devices from one app.
 
## Features
 
- **Video Streaming and Recording**: Secure end-to-end encryption for streaming and recording.
- **HomeKit Pairing**: Private per-camera setup code (see [Create a private HomeKit setup code](#create-a-private-homekit-setup-code)).
- **Jpeg Snapshots**: Capture high-quality images.
- **Audio Streaming**: (Recording and talkback coming soon).
- **Motion Detection**: HomeKit motion notifications.
- **Automatic IR Filter**: The day/night IR filter is enabled based on scene brightness.
- **IR LED Night Vision**: Night vision lights for clear visibility in the dark.
 
## Getting Started
 
### What you need

- A Wyze Cam v3 and a microSD card.
- A computer with Python 3, to create your HomeKit setup code.

### Get the WyreCam image

Build the SD card image from this repository (see [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md)). It produces `output/images/wyrecam_install.img`.

> **Note:** Images published on the [Releases page](https://github.com/radredgreen/wyrecam/releases) before these security fixes do not include them. For example, their SSH server can end up open without a password. Use an image built from this repository until a new release is published.

### Write the image to an SD card

#### Using Balena Etcher

1. Download and install [Balena Etcher](https://www.balena.io/etcher/).
2. Insert your SD card into your computer.
3. Open Balena Etcher, select the WyreCam image file, select your SD card, and click "Flash".

#### Using Raspberry Pi Imager

1. Download and install [Raspberry Pi Imager](https://www.raspberrypi.org/downloads/).
2. Insert your SD card into your computer.
3. Open Raspberry Pi Imager, click "Choose OS," select "Use custom," and find the WyreCam image file.
4. Click "Choose SD Card" and select your SD card.
5. Click "Write" to write the image to the SD card.

After writing, remove the card and insert it again so your computer mounts it. It contains `factory_t31_ZMC6tiIDQN`, `nor_full.bin`, `upgrade.sh` and `wyrecam.conf`.

### Configure the install (`wyrecam.conf`)

Open `wyrecam.conf` on the SD card in a text editor and fill it in. Put each value in single quotes:

```sh
WIFI_SSID='your network name'
WIFI_PASSWORD='your wifi password'

# Optional. Leave empty to lock root logins entirely (recommended).
ROOT_PASSWORD=''

# Optional. SSH is off unless you turn it on.
ENABLE_SSH='no'
SSH_AUTHORIZED_KEY=''
```

- **Wi-Fi**: The camera stores a key derived from your password, not the password itself. Leave `WIFI_PASSWORD` empty for an open network. If a value contains a single quote, write it as `'\''`.
- **Root password**: If you leave it empty, nobody can log in as root, on the serial console or over SSH. Set one only if you need shell access. It must not contain `:`.
- **SSH**: Set `ENABLE_SSH='yes'` to turn it on. If you also paste a public key into `SSH_AUTHORIZED_KEY` (one line, such as `ssh-ed25519 AAAA... you@laptop`), SSH accepts only that key and refuses passwords. This is the recommended setup. Without a key, SSH uses `ROOT_PASSWORD`, which must then be set.

You no longer need to edit `upgrade.sh`.

### Create a private HomeKit setup code

Every WyreCam used to share the setup code 0107-2024. It is printed in this README, so anyone on your network could use it to pair with a new or reset camera before you did. Create your own code instead. From a checkout of this repository, with the SD card mounted:

```sh
python3 scripts/homekit_setup_code.py /path/to/sdcard
```

The script needs only Python 3. It writes a `homekit/` folder to the card and prints your code, for example `3764-6081`. **Write the code down now:** it isn't saved anywhere in readable form, and you need it to add the camera to the Home app. To choose the code yourself, use `--code 123-45-678` (codes like `111-11-111` or `123-45-678` are refused).

If you skip this step, the install still works but the camera uses the public code 0107-2024. In that case, add it to the Home app as soon as it is online.

### Install the image

1. Eject the SD card, insert it into the camera and power the camera on.
2. Wait. The red LED comes on at power-up, and the **blue** LED comes on once the installer is running. The whole install takes up to 10 minutes. Do not remove power during this time.
3. When the **red LED blinks**, the install has finished. Unplug the camera and remove the SD card.
   - A **solid red** LED means the install stopped. `upgrade.out` on the SD card says why. If it failed before the flashing step, the camera is unchanged.
4. Plug the camera back in. It boots WyreCam and joins your Wi-Fi.

After a successful install, the installer:

- deletes `wyrecam.conf` and the `homekit/` folder from the card, so your Wi-Fi password and setup code don't stay on it;
- renames `factory_t31_ZMC6tiIDQN` to `factory_t31_ZMC6tiIDQN.done`, so booting with the card still inserted does not reinstall. To install again, rename it back and add a new `wyrecam.conf`.

### Keep the backup of the original firmware safe

The installer copies the camera's original flash to `spi_backups/backup.bin` before it changes anything. It never overwrites an existing backup: later installs save to `backup-1.bin`, `backup-2.bin` and so on. So `backup.bin` is always the oldest copy, which is the original Wyze firmware if WyreCam was installed on a stock camera.

`backup.bin` is the only way back to the stock firmware. It also contains the stock firmware's saved settings, likely including your old Wi-Fi password and Wyze device credentials. **Copy it to a safe place, then delete it and `upgrade.out` from the SD card.**

To go back to the stock firmware:

1. On a WyreCam SD card, copy (don't move) your original `spi_backups/backup.bin` to the top level of the card and name the copy `nor_full.bin`, replacing the WyreCam one.
2. Make sure `factory_t31_ZMC6tiIDQN` is present. If it is named `factory_t31_ZMC6tiIDQN.done`, rename it back.
3. Insert the card and power the camera on, as for an install. `wyrecam.conf` and `homekit/` are not needed; they are ignored when restoring.
4. When the red LED blinks, unplug the camera and remove the card. The camera now boots the Wyze firmware with the settings it had before WyreCam was installed.

The installer recognizes a WyreCam image by its layout. It flashes any other image exactly as it is and skips all WyreCam setup, so the stock firmware's own partitions are left untouched. It first backs up the current WyreCam flash to `backup-1.bin` (or the next free number), so `backup.bin` is never overwritten. It refuses to flash a file that isn't exactly the size of the flash (16 MB).

### Add WyreCam to HomeKit

1. Open the Home app on your iPhone or iPad.
2. Tap the "+" icon and select "Add Accessory."
3. Tap "More options" to see the accessory.
4. Enter the setup code you created (or 0107-2024 if you skipped that step).
5. Follow the on-screen instructions to complete the setup.
6. Assign the camera to a room and customize its settings as desired.

### Factory reset

If you have shell access, `firstboot` erases all WyreCam settings and reboots. That removes Wi-Fi, root password, SSH settings, HomeKit pairings and your private setup code. Afterwards the camera is offline, root logins and SSH are off, and it would use the public setup code again. To set it up again, reinstall from the SD card with a new `wyrecam.conf` and `homekit/` folder.

https://github.com/user-attachments/assets/b5304535-5445-485d-a184-c80f98ddb3db
 
## Configuration in Home.app
 
- **Night Vision**: Controlled automatically based on the brightness of the scene. The "Night Vision Light" switch in Home.app turns on the infrared LED when the scene is dark.
- **Camera Status Light**: Toggle the red LED on/off to help with reflections if the camera is near a window. Toggling twice flips the image.
- **Invert Image**: Useful for ceiling-mounted cameras. Toggle the Camera Status Light twice to flip the image.
 
## Security notes

- **No cloud, no telemetry.** WyreCam talks only to your Home hub and devices on your network, plus NTP servers (`*.openwrt.pool.ntp.org`) for the clock.
- **The SD card is only used for installing.** The installed system never runs anything from an inserted SD card or USB drive, and mounts them `noexec`.
- **Physical access is still powerful.** The bootloader boots `factory_t31_ZMC6tiIDQN` from any inserted card without checking a signature. This is what makes installing and reverting possible, but it also means someone who can reach the card slot can reflash the camera. Mount the camera where it can't be easily reached.
- **Root is locked by default** in the firmware image itself. A corrupted or erased settings partition therefore leaves no passwordless root account behind, and SSH stays off unless the installer turned it on.
- **Known issues in the camera software ([positron](https://github.com/radredgreen/positron)), which is not part of this repository:**
  - The Home app's microphone mute, "record audio" and "camera off" settings are saved but not enforced on the camera.
  - Debug logging can include stream encryption keys when decryption fails. That logging is off by default (`/etc/init.d/S95videosys`).

## Documentation
 
Refer to the [docs directory](docs/) for more information.
 
## Similar Projects, References, and Credits
 
- [thingino](https://github.com/themactep/thingino-firmware)
- [v3-unlocker](https://git.i386.io/wyze/v3-unlocker)
- [OpenIPC](https://github.com/OpenIPC)
- [t20_rtspd](https://github.com/geekman/t20-rtspd)
- [ingenic_videocap](https://github.com/openmiko/ingenic_videocap)
- [Ingenic-SDK-T31](https://github.com/cgrrty/Ingenic-SDK-T31-1.1.1-20200508)
- [Wyze GPL source](https://support.wyze.com/hc/en-us/articles/360012546832-Open-Source-Software)
- [Dafang-Hacks](https://github.com/Dafang-Hacks)
- [Apple HAP ADK](https://github.com/apple/HomeKitADK)
- [hkcam](https://github.com/brutella/hkcam)
- [hap-nodejs](https://github.com/homebridge/HAP-NodeJS)
- [homebridge-ffmpeg](https://github.com/Sunoo/homebridge-camera-ffmpeg)
- [homebridge-unity](https://github.com/hjdhjd/homebridge-unifi-protect/blob/main/docs/HomeKitSecureVideo.md)
 
## Build Instructions
 
Detailed build instructions have been moved to a dedicated file. Please refer to [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md) for step-by-step guidance on building WyreCam from source.
