#!/bin/bash

CWD=`pwd` # current working directory
BASE="/tmp/$$.asg2asi" # temp working directory
ISO=`basename $1` # ISO file name
ISOPATH="`dirname $1`/$ISO" # full path to ISO
ISOTYPE=`echo $ISO | cut -d '-' -f 1` # should be 'asg'
ISONAME=`echo $ISO | cut -d '-' -f 2-` # should be version
BISO="$BASE/iso" # temp working directory for iso mount
BPATCH="$BASE/patched" # temp workin directory for patched files

# How to handle interrupts
on_die() {
  echo "Interrupting..."
  cd "$CWD"
  if [ -e "$BISO" ]; then
    sudo umount "$BISO"
  fi
  exit 1
}

trap 'on_die' TERM
trap 'on_die' KILL
trap 'on_die' INT

# test if iso missing
if [ ! -e "$ISOPATH" ]; then
  echo "Please specify an existing ASG ISO file: asg-*.iso"
  on_die
fi

# test if iso begins with 'asg'
if [ ! "$ISOTYPE" = "asg" ]; then
  echo "Sorry, only ASG ISOs supported"
  on_die
fi

# check for custom installer.ini
if [ -e "$CWD/installer.ini" ]; then
  echo "Using custom installer.ini"
  INI="$CWD/installer.ini"
fi

# check for custom rules
if [ -e "$CWD/70-persistent-net.rules" ]; then
  echo "Using custom 70-persistent-net.rules"
  UDEV="$CWD/70-persistent-net.rules"
fi

# Make sure we're clean, deletes contents of temp working directory
rm -rf "$BASE"

echo "Copy contents of ISO to Patching Area: '$BPATCH'"
mkdir -p "$BISO" # makes tmp ISO mount point
mkdir -p "$BPATCH" # makes tmp patched dir
sudo mount -o loop "$ISOPATH" "$BISO" # mounts ISO read-only to ISO mount point
cp -a "$BISO"/* "$BPATCH" # makes copy of ISO to edit

echo "Patch initramfs"
mkdir -p "$BPATCH/patched-initramfs"
chmod 755 "$BPATCH/isolinux"
chmod 644 "$BPATCH/isolinux"/*
mv "$BPATCH/isolinux/initramfs.gz" "$BPATCH/patched-initramfs"
cd "$BPATCH/patched-initramfs"
zcat initramfs.gz | (while true; do cpio -m -i -d -H newc --no-absolute-filenames 2> /dev/null || exit; done)
rm -f initramfs.gz
if [ ! "$UDEV" = "" ]; then
  echo "Integrating custom 70-persistent-net.rules"
  mkdir -p "$BPATCH/patched-initramfs/etc/bootstrap/postinst.d"
  cat > "$BPATCH/patched-initramfs/etc/bootstrap/postinst.d/77-nicsort.sh"  /dest/etc/udev/rules.d/70-persistent-net.rules  /dev/null | gzip -9 > initramfs.gz
  mv initramfs.gz "$BPATCH/isolinux/initramfs.gz"
  rm -rf "$BPATCH/patched-initramfs"
fi

echo "Patch isolinux.cfg"
chmod 660 "$BPATCH/isolinux/isolinux.cfg"
sed -i "s/APPEND/APPEND auto ini\=file\:\/\/\/install\/installer\.ini/" "$BPATCH/isolinux/isolinux.cfg"
sed -i "s/TIMEOUT 300/TIMEOUT 10/" "$BPATCH/isolinux/isolinux.cfg"

# Add installer.ini
if [ ! "$INI" = "" ]; then
  echo "Integrating custom installer.ini"
  cat "$INI" > "$BPATCH/installer.ini" 
fi

cd $CWD
# repackage iso
echo "Repacking the ISO file"
genisoimage -l -r -J -V "Sophos" -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -c isolinux/boot.cat -o "$ISOPATH"-new.iso "$BPATCH"
