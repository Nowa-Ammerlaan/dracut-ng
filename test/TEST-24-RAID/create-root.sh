#!/bin/sh

trap 'poweroff -f' EXIT
set -e

# populate TEST_FSTYPE
. /env

if [ "$TEST_FSTYPE" = "zfs" ]; then
    zpool create dracut /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_raid[12]
    zfs create dracut/root
elif [ "$TEST_FSTYPE" = "btrfs" ]; then
    mkfs.btrfs -q -draid0 -mraid0 -L root /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_raid[12]
    udevadm settle
    btrfs device scan
else
    mdadm --create /dev/md0 --run --auto=yes --level=0 --raid-devices=2 /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_raid[12]
    # wait for the array to finish initializing, otherwise this sometimes fails randomly.
    mdadm -W /dev/md0 || :

    lvm pvcreate -ff -y /dev/md0
    lvm vgcreate dracut /dev/md0
    lvm lvcreate --yes -l 100%FREE -n root dracut
    lvm vgchange -ay

    eval "mkfs.${TEST_FSTYPE} -q -L root /dev/dracut/root"
fi

udevadm settle
mkdir -p /sysroot

if [ "$TEST_FSTYPE" = "zfs" ]; then
    zfs set mountpoint=/sysroot dracut/root
    zfs get mounted dracut/root
elif [ "$TEST_FSTYPE" = "btrfs" ]; then
    mount -t "$TEST_FSTYPE" /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_raid1 /sysroot
else
    mount -t "$TEST_FSTYPE" /dev/dracut/root /sysroot
fi

cp -a -t /sysroot /source/*
umount /sysroot

if [ -e /dev/md0 ]; then
    lvm lvchange -a n /dev/dracut/root
    udevadm settle
    mdadm -W /dev/md0 || :
    udevadm settle
    mdadm --detail --export /dev/md0 | grep -F MD_UUID > /tmp/mduuid
    . /tmp/mduuid
    udevadm settle
fi

echo "dracut-root-block-created" | dd oflag=direct,dsync of=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_marker status=none
sync
poweroff -f