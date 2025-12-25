#!/bin/bash

#stop on error

set -e

#define partitions
DISK="/dev/sda"
HOSTNAME="archlinux"
USERNAME="user"
PASSWORD="password"
TIMEZONE="Europe/Berlin"

echo "Starting Arch Install on $DISK..."

# partitioning
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary linux-swap 513MiB 8.5GiB
parted -s "$DISK" mkpart primary btrfs 8.5GiB 100%

# Define partition paths based on disk type
if [[ $DISK == *"nvme"* ]]; then
    PART_ESP="${DISK}p1"
    PART_SWAP="${DISK}p2"
    PART_ROOT="${DISK}p3"
else
    PART_ESP="${DISK}1"
    PART_SWAP="${DISK}2"
    PART_ROOT="${DISK}3"
fi

# 4. FORMATTING & BTRFS SUBVOLUMES
mkfs.fat -F32 "$PART_ESP"
mkswap "$PART_SWAP"
swapon "$PART_SWAP"
mkfs.btrfs -f "$PART_ROOT"

# Mount root to create subvolumes
mount "$PART_ROOT" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
umount /mnt

# 5. MOUNT WITH OPTIMIZED OPTIONS
# Added 'compress=zstd' and 'noatime' for better SSD life/speed.
mount -o noatime,compress=zstd,subvol=@ "$PART_ROOT" /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg}
mount -o noatime,compress=zstd,subvol=@home "$PART_ROOT" /mnt/home
mount -o noatime,compress=zstd,subvol=@log "$PART_ROOT" /mnt/var/log
mount -o noatime,compress=zstd,subvol=@pkg "$PART_ROOT" /mnt/var/cache/pacman/pkg
mount "$PART_ESP" /mnt/boot

# 6. PACSTRAP (Added amd-ucode check)
# It's safer to include both ucode packages or detect the CPU.
pacstrap /mnt base linux linux-firmware btrfs-progs sudo nano networkmanager intel-ucode amd-ucode

# 7. GENERATE FSTAB
genfstab -U /mnt >> /mnt/etc/fstab

# 8. SYSTEM CONFIGURATION (The Chroot Block)
arch-chroot /mnt /bin/bash <<EOF
set -e
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Fix Locale Bug: Uncommenting the line before generating
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname

# User setup (Quoted variables to prevent shell injection)
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
echo "root:$PASSWORD" | chpasswd

# Sudoers fix
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Bootloader (GRUB for EFI)
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable Services
systemctl enable NetworkManager
EOF

echo "Installation complete! You can now reboot."
