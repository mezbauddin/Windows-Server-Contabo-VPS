#!/bin/bash

apt update && apt upgrade -y
apt install grub2 wimtools ntfs-3g -y

# Get the disk size in GB and convert to MB
disk_size_gb=$(parted /dev/sda --script print | awk '/^Disk \/dev\/sda:/ {print int($3)}')
disk_size_mb=$((disk_size_gb * 1024))

# Calculate partition size (25% of total size)
part_size_mb=$((disk_size_mb / 4))

# Create GPT partition table with BIOS Boot Partition
parted /dev/sda --script -- mklabel gpt
parted /dev/sda --script -- mkpart primary 1MiB 2MiB
parted /dev/sda --script -- set 1 bios_grub on
parted /dev/sda --script -- mkpart primary ntfs 2MiB ${part_size_mb}MiB
parted /dev/sda --script -- mkpart primary ntfs ${part_size_mb}MiB $((2 * part_size_mb))MiB

# Inform kernel of partition table changes
partprobe /dev/sda
sleep 10

# Format the partitions
mkfs.ntfs -f /dev/sda2
mkfs.ntfs -f /dev/sda3

echo "NTFS partitions created successfully."

# Mount the first partition
mount /dev/sda2 /mnt || { echo "Failed to mount /dev/sda2"; exit 1; }

# Prepare directory for Windows disk
mkdir -p /root/windisk
umount /dev/sda3 2>/dev/null
mount /dev/sda3 /root/windisk || { echo "Failed to mount /dev/sda3"; exit 1; }

# Install GRUB
grub-install --target=i386-pc --boot-directory=/mnt/boot --recheck /dev/sda

# Edit GRUB configuration
mkdir -p /mnt/boot/grub
cat <<EOF > /mnt/boot/grub/grub.cfg
menuentry "windows installer" {
    insmod ntfs
    search --set=root --file=/bootmgr
    ntldr /bootmgr
    boot
}
EOF

# Download Windows Server ISO with resume support
wget -c -O /root/windisk/winserver.iso "https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
if [ ! -s /root/windisk/winserver.iso ]; then
    echo "Failed to download Windows Server ISO. Exiting..."
    exit 1
fi

# Mount the ISO
if mount -o loop /root/windisk/winserver.iso /root/windisk/winfile; then
    rsync -avz --progress /root/windisk/winfile/* /mnt
    umount /root/windisk/winfile
else
    echo "Failed to mount Windows Server ISO. Exiting..."
    exit 1
fi

# Download VirtIO drivers ISO
wget -O /root/windisk/virtio.iso "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
if [ ! -s /root/windisk/virtio.iso ]; then
    echo "Failed to download VirtIO ISO. Exiting..."
    exit 1
fi

# Mount VirtIO ISO
if mount -o loop /root/windisk/virtio.iso /root/windisk/winfile; then
    mkdir -p /mnt/sources/virtio
    rsync -avz --progress /root/windisk/winfile/* /mnt/sources/virtio
    umount /root/windisk/winfile
else
    echo "Failed to mount VirtIO ISO. Exiting..."
    exit 1
fi

# Add VirtIO drivers to boot.wim
cd /mnt/sources || exit
touch cmd.txt
echo 'add virtio /virtio_drivers' > cmd.txt
wimlib-imagex update boot.wim 2 < cmd.txt

# Rebooting
reboot
