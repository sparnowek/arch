#!/bin/bash
set -e

# --- 1. PRE-FLIGHT CHECKS ---
echo "--- Available Disks ---"
lsblk -dno NAME,SIZE,MODEL | grep -v "loop"
echo "-----------------------"
read -p "Enter the disk name to WIPE and install to (e.g., sda or nvme0n1): " DISK_NAME
DISK="/dev/$DISK_NAME"

read -p "Enter Username: " USERNAME
read -sp "Enter Password: " PASSWORD
echo
read -p "Enter Swap size in GB (e.g., 8 or 16): " SWAP_SIZE

# Detect UEFI vs BIOS
if [ -d "/sys/firmware/efi" ]; then
    BOOT_MODE="UEFI"
    LABEL="g" # GPT
    TYPE_EFI="1" # EFI System
    TYPE_SWAP="19"
else
    BOOT_MODE="BIOS"
    LABEL="o" # MBR/DOS
    TYPE_EFI="ef"
    TYPE_SWAP="82"
fi

echo "Preparing to format $DISK in $BOOT_MODE mode..."

# --- 2. AUTOMATED FDISK ---
# This wipes the disk and creates 3 partitions: 1G Boot, Swap, and rest for Root.
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk "$DISK"
  $LABEL  # Create new table
  n       # Part 1 (Boot)
  1
          # Start
  +1G     # 1GB Size
  t       # Change type
  $TYPE_EFI
  n       # Part 2 (Swap)
  2
          # Start
  +${SWAP_SIZE}G
  t       # Change type
  2
  $TYPE_SWAP
  n       # Part 3 (Root)
  3
          # Start
          # Use remaining space
  w       # Write and exit
EOF

# Handle naming (nvme0n1p1 vs sda1)
if [[ $DISK == *"nvme"* ]]; then
    P1="${DISK}p1"; P2="${DISK}p2"; P3="${DISK}p3"
else
    P1="${DISK}1"; P2="${DISK}2"; P3="${DISK}3"
fi

# --- 3. FILESYSTEMS & MOUNTING ---
mkfs.fat -F32 "$P1"
mkswap "$P2"
swapon "$P2"
mkfs.btrfs -f "$P3"

mount "$P3" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt

mount -o noatime,compress=zstd,subvol=@ "$P3" /mnt
mkdir -p /mnt/{boot,home}
mount -o noatime,compress=zstd,subvol=@home "$P3" /mnt/home
mount "$P1" /mnt/boot

# --- 4. INSTALLATION ---
pacstrap /mnt base linux linux-firmware btrfs-progs sudo networkmanager intel-ucode amd-ucode

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF
set -e
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "arch-machine" > /etc/hostname

useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

pacman -S --noconfirm grub efibootmgr
if [ "$BOOT_MODE" == "UEFI" ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
    grub-install --target=i386-pc "$DISK"
fi
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager
EOF

# --- 5. CLEAN UP ---
echo "Installation finished. Cleaning up..."
umount -R /mnt
swapoff "$P2"

echo "--------------------------------------------------------"
echo " SUCCESS!"
echo " Everything is unmounted safely."
echo " You can now remove your USB drive and type 'reboot'."
echo "--------------------------------------------------------"
