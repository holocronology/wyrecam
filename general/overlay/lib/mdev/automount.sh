#!/bin/sh

destdir=/mnt

my_umount()
{
    if grep -qs "^/dev/$1 " /proc/mounts ; then
        umount "${destdir}/$1";
    fi

    [ -d "${destdir}/$1" ] && rmdir "${destdir}/$1"
}

my_mount()
{
    mkdir -p "${destdir}/$1" || exit 1

    # noexec/nosuid/nodev: nothing on a removable card may run on the camera.
    if ! mount -t auto -o sync,noexec,nosuid,nodev "/dev/$1" "${destdir}/$1"; then
        # failed to mount, clean up mountpoint
        rmdir "${destdir}/$1"
        exit 1
    fi

    # OpenIPC's autoconfig/, autoconfig.sh and autostart.sh hooks were removed:
    # they ran whatever was on an inserted card as root.
}

case "${ACTION}" in
add|"")
    my_umount ${MDEV}
    my_mount ${MDEV}
    ;;
remove)
    my_umount ${MDEV}
    ;;
esac
