#!/usr/bin/env bash

# Set defaults
: "${DESKTOP:=0}"
: "${SHELL_CHOICE:=1}"

set -e

echo "|-----------------------------|"
echo "|- Arch Linux install script -|"
echo "|-----------------------------|"

echo "| Sync Pacman |"
pacman -Syy --noconfirm

echo
echo "| Partition disks |"
echo "Use fdisk/cfdisk now"
echo "EFI  : 1G  (EFI System)"
echo "SWAP : RAM size or about 8G"
echo "ROOT : Rest (Linux filesystem)"

echo
read -p "Done? Press ENTER to continue..."

echo "Enter EFI (ex: /dev/sda1)"
read EFI
echo "Enter SWAP (ex: /dev/sda2)"
read SWAP
echo "Enter ROOT (ex: /dev/sda3)"
read ROOT

# Verify partitions exist
for part in "$EFI" "$ROOT" "$SWAP"; do
  if [[ ! -b $part ]]; then
    echo "Error: Partition $part does not exist"
    exit 1
  fi
done

# Check Internet
if ! ping -c 1 archlinux.org >/dev/null 2>&1; then
  echo "No internet, connect to wifi/ethernet and run again"
  exit 1
fi

echo "| Cleaning old mount and directories |"
swapoff -a 2>/dev/null || true
umount -R /mnt 2>/dev/null || true

echo "| Creating filesystems |"
mkfs.fat -F32 "${EFI}"
mkfs.ext4 -F "${ROOT}"
mkswap "${SWAP}"
swapon "${SWAP}"

echo "| Mount partitions |"
mount "${ROOT}" /mnt
mkdir -p /mnt/boot/efi  # Must happen AFTER mounting /mnt
mount "${EFI}" /mnt/boot/efi

echo "| Install base system |"
pacstrap /mnt base base-devel linux-lts linux-lts-headers linux-firmware sudo nano --noconfirm

genfstab -U /mnt >> /mnt/etc/fstab

echo "| User configuration |"
read -p "Hostname: " HOSTNAME
read -p "Username: " USERNAME
read -s -p "User password: " USERPASS
echo
read -s -p "Root password: " ROOTPASS
echo

echo "Choose desktop environment: 1) KDE, 2) GNOME, 3) None"
read DE

echo "Default Shell: 1) Bash, 2) Zsh, 3) Nushell"
read SHELL_INPUT

echo "GRUB bootmenu: 1) No menu (0s), 2) Standard menu"
read GRUB_CHOICE

# We use 'INSTALL' in quotes to prevent the host shell from expanding variables too early
cat <<INSTALL > /mnt/install_chroot.sh
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
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

echo "| Users |"
echo "root:${ROOTPASS}" | chpasswd
useradd -m -G wheel,storage,power,audio,video -s /bin/bash ${USERNAME}
echo "${USERNAME}:${USERPASS}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "| Xtra shells |"
pacman -S --noconfirm zsh nushell
# Add Nushell to /etc/shells so chsh accepts it
echo "/usr/bin/nu" >> /etc/shells

if [[ "$SHELL_INPUT" == "2" ]]; then
    chsh -s /bin/zsh ${USERNAME}
elif [[ "$SHELL_INPUT" == "3" ]]; then
    chsh -s /usr/bin/nu ${USERNAME}
fi

echo "| Network |"
pacman -S networkmanager --noconfirm
systemctl enable NetworkManager

echo "| Bootloader |"
pacman -S grub efibootmgr --noconfirm
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
if [[ "$GRUB_CHOICE" == "1" ]]; then
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
fi
grub-mkconfig -o /boot/grub/grub.cfg

echo "| Desktop |"
if [[ "${DE}" == "1" ]]; then
  pacman -S xorg plasma sddm konsole dolphin --noconfirm
  systemctl enable sddm
elif [[ "${DE}" == "2" ]]; then
  pacman -S xorg gnome gdm --noconfirm
  systemctl enable gdm
fi

echo "| ARCHroot Done |"
INSTALL

chmod +x /mnt/install_chroot.sh
arch-chroot /mnt /bin/bash /install_chroot.sh

rm /mnt/install_chroot.sh
umount -R /mnt

echo "Finished! Reboot now."
