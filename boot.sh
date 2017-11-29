#!/bin/bash

function status {
  echo $1 >> ~/boot_status
}

REPO_SERVER="http://169.55.123.216:8000"
MINOS_ROOT_IMAGE="$REPO_SERVER/xvdc2"
ALT_PREFIX="/alt_root"

status "Step 1" 
# Remove extra disk partition
umount /disk0
(
echo d # Delete a partition
echo   # Delete Last sector (Accept default: varies)
echo w # Write changes
) | fdisk /dev/sda
partprobe

# Add new root partition for minOS
(
echo n # New partition (by default it is logical sector)
echo   # Start sector default
echo +20G  # Create 20G for minOS
echo w # Write changes
) | fdisk /dev/sda
partprobe

# Wget image into new partition. TODO: This should be HTTPS or encrypted in some way
MINOS_PART=`fdisk -l | tail -n 1 | awk '{print $1}'`
wget ${MINOS_ROOT_IMAGE} -p -O - | dd of=${MINOS_PART}

status "Done Step 1" 

MINOS_UUID=`lsblk -o name,uuid | grep sda7 | awk '{print $2}'`

status "Perform fstab changes" 

cp /etc/fstab /etc/fstab.bkup
sed '/disk0/d' /etc/fstab.bkup > /etc/fstab

mkdir -p ${ALT_PREFIX}
mount ${MINOS_PART} ${ALT_PREFIX}

BOOT_FSTAB_LINE=`cat /etc/fstab | grep -v ^# | grep /boot`
cp /alt_root/etc/fstab ${ALT_PREFIX}/etc/fstab.bkup
sed 's,'.*/boot.*','"$BOOT_FSTAB_LINE"',' $ALT_PREFIX/etc/fstab.bkup > $ALT_PREFIX/etc/fstab
# TODO: Delete backup once done
# TODO: CHange this once ifenslave is in the minOS

KERNEL_TARS=("boot_96.tar" "boot_98.tar")
for k in ${KERNEL_TARS[@]}; do
  echo $k;
  wget $REPO_SERVER/$k
  tar -xf $k -C /boot
  tar -xf $k -C $ALT_PREFIX/boot  #just in case
done

function copy_file {
  new_path=${ALT_PREFIX}/$1
  echo $new_path
  mkdir -p $(dirname $new_path)
  cp -r $1 $new_path
}

status "Step 2" 
status "Copying Network Files" 
cp -r $ALT_PREFIX/etc/network ~/network_bkup
rm -rf $ALT_PREFIX/etc/network
cp -r /etc/network $ALT_PREFIX/etc/network

copy_file /sbin/ifenslave
copy_file /usr/share/doc/ifenslave
copy_file /etc/hostname
copy_file /etc/hosts

status "Transferring root password"
# Transfer root password
cp /alt_root/etc/shadow ${ALT_PREFIX}/etc/shadow.bkup
root_pw=`cat /etc/shadow | grep ^root | awk -F ':' '{print $2}'`
sed 's,'root:[^:]*','root:$root_pw',' ${ALT_PREFIX}/etc/shadow.bkup > ${ALT_PREFIX}/etc/shadow
# TODO: Delete backup once done

status "Adding Kernel module"
if grep -q bonding ${ALT_PREFIX}/etc/modules; then
  :
else
  echo "bonding" >> ${ALT_PREFIX}/etc/modules
fi
status "Done Step 2" 
