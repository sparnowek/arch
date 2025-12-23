#!/usr/bin/env bash

: "${DESKTOP:=0}"
: "${SHELL:=1}"

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

echo
echo "Enter EFI (ex: /dev/sda1)"
read EFI
echo "Enter SWAP (ex: /dev/sda2)"
read SWAP
echo "Enter ROOT (ex: /dev/sda3)"
read ROOT

echo
for part in "$EFI" "$ROOT" "$SWAP"; do
  if [[ ! -b $part ]]; then
    echo "Error: Partition $part does not exist"
    exit 1
  fi
done

ping -c 1 archlinux.org >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "No internet, connect to wifi/ethernet and run again"
  exit 1
fi

echo "| Cleaning old mount and directories |"
swapoff -a 2>/dev/null || true
umount -R /mnt 2>/dev/null || true
rm -rf /mnt

echo
echo "| Adding mount directory |"
mkdir /mnt
mkdir /mnt/boot
mkdir /mnt/boot/efi

echo
echo "| Creating filesystems |"
mkfs.fat -F32 "${EFI}"
mkfs.ext4 "${ROOT}"
mkswap "${SWAP}"
swapon "${SWAP}"

echo
echo "| Mount partitions |"
mount "${ROOT}" /mnt
mkdir -p /mnt/boot/efi
mount "${EFI}" /mnt/boot/efi

echo
echo "| Install base system |"
pacstrap /mnt base base-devel linux-lts linux-lts-headers linux-firmware sudo nano --noconfirm

genfstab -U -p /mnt > /mnt/etc/fstab

echo
echo "| User configuration |"
echo "Hostname:"
read HOSTNAME
echo "Username:"
read USERNAME
echo "User password:"
read -s USERPASS
echo "Root password:"
read -s ROOTPASS
echo

echo
echo "Choose desktop environment"
echo "1. KDE (sddm)"
echo "2. GNOME (gdm)"
echo "3. No Desktop"
read DE

echo "Default Shell"
echo "1. Bash"
echo "2. Zsh"
echo "3. Nushell"
read SHELL


echo "GRUB bootmenu"
echo "1. no bootmenu"
echo "2. menu"
read GRUB_CHOICE

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
127.0.1.1   ${HOSTNAME}
HOSTS

echo "| Users |"
echo "root:${ROOTPASS}" | chpasswd
useradd -m -G wheel,storage,power,audio,video -s /bin/bash ${USERNAME}
echo "${USERNAME}:${USERPASS}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

echo "| Xtra shells |"
pacman -S --noconfirm zsh nushell

if [[ "$SHELL" == "1" ]]; then
    chsh -s /bin/bash $USER
elif [[ "$SHELL" == "2" ]]; then
    chsh -s /bin/zsh $USER
elif [[ "$SHELL" == "3" ]]; then
    chsh -s /usr/bin/nu $USER
else
    echo "No change, default bash used"
fi

echo "| Network |"
pacman -S networkmanager dhcpcd --noconfirm
systemctl enable NetworkManager
systemctl enable dhcpcd

echo "| Bootloader |"
pacman -S grub efibootmgr --noconfirm
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

if [[ "$GRUB_CHOICE" == "1" ]]; then
  sed -i 's/^#\?GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/' /etc/default/grub
fi
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

echo "| Cleaning up |"
rm -f /install_chroot.sh

echo "| ARCHroot Done |"

INSTALL

chmod +x /mnt/install_chroot.sh
arch-chroot /mnt /install_chroot.sh

echo "| Unmounting |"
umount /mnt/boot/efi || true
umount /mnt || true

echo "| Removing installer script |"
rm -- "$0"

echo
echo "|--------------|"
echo "|-  Finished  -|"
echo "|-  Have fun! -|"
echo "|--------------|"
