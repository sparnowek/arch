#!/usr/bin/env bash

# Set defaults
: "${DESKTOP:=0}"
: "${SHELL_CHOICE:=1}"

set -e

echo "|-----------------------------|"
echo "|- Arch Linux install script -|"
echo "|-----------------------------|"

echo 
echo "|-------------------|"
echo "|- Synchronization -|"
echo "|-------------------|"
pacman -Syy --noconfirm

echo
echo "|----------------|"
echo "|- Partitioning -|"
echo "|----------------|"
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

echo 
echo "|------------|"
echo "|- Umouning -|"
echo "|------------|"
swapoff -a 2>/dev/null || true
umount -R /mnt 2>/dev/null || true

echo 
echo "|---------------|"
echo "|- Filesystems -|"
echo "|---------------|"
mkfs.fat -F32 "${EFI}"
mkfs.ext4 -F "${ROOT}"
mkswap "${SWAP}"
swapon "${SWAP}"

echo 
echo "|------------|"
echo "|- Mounting -|"
echo "|------------|"
mount "${ROOT}" /mnt
mkdir -p /mnt/boot/efi  # Must happen AFTER mounting /mnt
mount "${EFI}" /mnt/boot/efi

echo 
echo "|--------|"
echo "|- Base -|"
echo "|--------|"
pacstrap /mnt base base-devel linux-lts linux-lts-headers linux-firmware sudo nano --noconfirm

genfstab -U /mnt >> /mnt/etc/fstab

echo 
echo "|--------|"
echo "|- User -|"
echo "|--------|"
read -p "Hostname: " HOSTNAME
read -p "Username: " USERNAME
read -s -p "User password: " USERPASS
echo
read -s -p "Root password: " ROOTPASS
echo

echo "Choose desktop environment:"
echo "1. KDE"
echo "2. GNOME" 
echo "3. None"
read DE

echo
echo "Default Shell:"
echo "1. Bash"
echo "2. Zsh" 
echo "3. Nushell"
read SHELL_INPUT

echo
echo "GRUB bootmenu:"
echo "1. No Menu"
echo "2. Menu"
read GRUB_CHOICE

# We use 'INSTALL' in quotes to prevent the host shell from expanding variables too early
cat <<INSTALL > /mnt/install_chroot.sh
#!/usr/bin/env bash
set -e

echo 
echo "|---------|"
echo "|- Clock -|"
echo "|---------|"
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
hwclock --systohc

echo 
echo "|--------|"
echo "|- Host -|"
echo "|--------|"
echo "${HOSTNAME}" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

echo 
echo "|------------------|"
echo "|- Administration -|"
echo "|------------------|"
echo "root:${ROOTPASS}" | chpasswd
useradd -m -G wheel,storage,power,audio,video -s /bin/bash ${USERNAME}
echo "${USERNAME}:${USERPASS}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo 
echo "|----------|"
echo "|- Shells -|"
echo "|----------|"
pacman -S --noconfirm zsh nushell
# Add Nushell to /etc/shells so chsh accepts it
echo "/usr/bin/nu" >> /etc/shells

if [[ "$SHELL_INPUT" == "2" ]]; then
    chsh -s /bin/zsh ${USERNAME}
elif [[ "$SHELL_INPUT" == "3" ]]; then
    chsh -s /usr/bin/nu ${USERNAME}
fi

echo 
echo "|--------------|"
echo "|- Networking -|"
echo "|--------------|"
pacman -S networkmanager --noconfirm
systemctl enable NetworkManager

echo 
echo "|--------|"
echo "|- Boot -|"
echo "|--------|"
pacman -S grub efibootmgr --noconfirm
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
if [[ "$GRUB_CHOICE" == "1" ]]; then
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
fi
grub-mkconfig -o /boot/grub/grub.cfg

echo 
echo "|-----------|"
echo "|- Desktop -|"
echo "|-----------|"
if [[ "${DE}" == "1" ]]; then
  pacman -S xorg plasma sddm konsole dolphin --noconfirm
  systemctl enable sddm
elif [[ "${DE}" == "2" ]]; then
  pacman -S xorg gnome gdm --noconfirm
  systemctl enable gdm
fi

echo 
echo "|----------------|"
echo "|- Install Done -|"
echo "|----------------|"
INSTALL

chmod +x /mnt/install_chroot.sh
arch-chroot /mnt /bin/bash /install_chroot.sh

rm /mnt/install_chroot.sh
umount -R /mnt

echo 
echo "|--------------|"
echo "|-  Finished  -|"
echo "|-  Have fun! -|"
echo "|--------------|"
