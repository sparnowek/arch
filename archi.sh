#!/usr/bin/env bash
set -e

echo "|-------------------------------|"
echo "| Arch Linux Installation Script |"
echo "|-------------------------------|"

echo "| Step 1: Sync Pacman |"
pacman -Syy --noconfirm

echo
echo "| Step 2: Partition Disks |"
echo "Use fdisk/cfdisk now."
echo "EFI  : 1G  (EFI System)"
echo "ROOT : Rest (Linux filesystem)"
echo "SWAP : RAM size or ~8G"
echo
read -p "Press ENTER when partitions are ready..."

echo
echo "Enter EFI partition (e.g. /dev/sda1)"
read EFI

echo "Enter ROOT partition (e.g. /dev/sda2)"
read ROOT

echo "Enter SWAP partition (e.g. /dev/sda3)"
read SWAP

echo
echo "| Step 3: Create filesystems |"
mkfs.fat -F32 "${EFI}"
mkfs.ext4 "${ROOT}"
mkswap "${SWAP}"
swapon "${SWAP}"

echo
echo "| Step 4: Mount partitions |"
mount "${ROOT}" /mnt
mkdir -p /mnt/boot/efi
mount "${EFI}" /mnt/boot/efi

echo
echo "| Step 5: Install base system |"
pacstrap /mnt base base-devel linux-lts linux-lts-headers linux-firmware sudo nano --noconfirm

genfstab -U -p /mnt > /mnt/etc/fstab

echo
echo "| Step 6: User configuration |"
echo "Enter hostname:"
read HOSTNAME

echo "Enter username:"
read USERNAME

echo "Enter root password:"
read -s ROOTPASS
echo

echo "Enter user password:"
read -s USERPASS
echo

echo
echo "Choose Desktop Environment"
echo "1 KDE (SDDM)"
echo "2 GNOME (GDM)"
echo "3 No Desktop"
read DE

cat <<EOF > /mnt/install_chroot.sh
#!/usr/bin/env bash
set -e

echo "| Locale & Time |"
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
hwclock --systohc

echo "| Hostname |"
echo "${HOSTNAME}" > /etc/hostname

cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}
HOSTS

echo "| Users |"
echo "root:${ROOTPASS}" | chpasswd
useradd -m -G wheel,storage,power,audio,video -s /bin/bash ${USERNAME}
echo "${USERNAME}:${USERPASS}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

echo "| Network |"
pacman -S networkmanager dhcpcd --noconfirm
systemctl enable NetworkManager
systemctl enable dhcpcd

echo "| Bootloader |"
pacman -S grub efibootmgr --noconfirm
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "| Desktop |"
if [[ "${DE}" == "1" ]]; then
  pacman -S xorg plasma sddm konsole dolphin ark kwrite kcalc spectacle krunner partitionmanager --noconfirm
  systemctl enable sddm
elif [[ "${DE}" == "2" ]]; then
  pacman -S xorg gnome gdm gnome-terminal nautilus gnome-extra gnome-disk-utility gnome-tweaks --noconfirm
  systemctl enable gdm
else
  echo "No desktop installed."
fi

echo "| Done |"
EOF

chmod +x /mnt/install_chroot.sh
arch-chroot /mnt /install_chroot.sh

echo
echo "| Installation finished |"
echo "Unmounting and rebooting..."
umount -R /mnt
swapoff "${SWAP}"
reboot
