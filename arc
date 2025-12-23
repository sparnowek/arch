#!/usr/bin/env bash

: "${DESKTOP:=0}"
: "${SHELL:=1}"

set -e

echo "|-----------------------------|"
echo "|- Arch Linux install script -|"
echo "|-----------------------------|"

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

read -p "Done? Press ENTER to continue..."

# --- numeric selection ---
echo
echo "Scanning for partitions..."
# Get list of partitions (Name, Size, Type)
mapfile -t parts < <(lsblk -pnlo NAME,SIZE,TYPE | grep 'part')

select_partition() {
    local prompt=$1
    echo -e "\n$prompt"
    for i in "${!parts[@]}"; do
        printf "%d) %s\n" "$((i+1))" "${parts[$i]}"
    done
    read -p "Enter number: " choice
    echo "${parts[$((choice-1))]}" | awk '{print $1}'
}

EFI=$(select_partition "Select EFI Partition")
SWAP=$(select_partition "Select SWAP Partition")
ROOT=$(select_partition "Select ROOT Partition")

echo -e "\nSelected: EFI=$EFI, SWAP=$SWAP, ROOT=$ROOT"
# -----------------------------------

ping -c 1 archlinux.org >/dev/null 2>&1 || { echo "No internet"; exit 1; }

echo "|------------|"
echo "|- Cleaning -|"
echo "|------------|"
swapoff -a 2>/dev/null || true
umount -R /mnt 2>/dev/null || true

echo "|------------|"
echo "|- Building -|"
echo "|------------|"
mkfs.fat -F32 "${EFI}"
mkfs.ext4 -F "${ROOT}"
mkswap "${SWAP}"
swapon "${SWAP}"

echo "|------------|"
echo "|- Mounting -|"
echo "|------------|"
# mount ROOT first
mount "${ROOT}" /mnt

# create the directories inside the mounted root
mkdir -p /mnt/boot/efi

# mount EFI into the newly created dir
mount "${EFI}" /mnt/boot/efi

echo
echo "|--------|"
echo "|- Base -|"
echo "|--------|"
pacstrap /mnt base base-devel linux-lts linux-lts-headers linux-firmware sudo nano --noconfirm

genfstab -U -p /mnt > /mnt/etc/fstab

echo
echo "|--------|"
echo "|- User -|"
echo "|--------|"
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
127.0.1.1   ${HOSTNAME}
HOSTS

echo 
echo "|------------------|"
echo "|- Administration -|"
echo "|------------------|"
echo "root:${ROOTPASS}" | chpasswd
useradd -m -G wheel,storage,power,audio,video -s /bin/bash ${USERNAME}
echo "${USERNAME}:${USERPASS}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

echo 
echo "|----------|"
echo "|- Shells -|"
echo "|----------|"
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

echo 
echo "|-----------|"
echo "|- Network -|"
echo "|-----------|"
pacman -S networkmanager dhcpcd --noconfirm
systemctl enable NetworkManager
systemctl enable dhcpcd

echo 
echo "|--------|"
echo "|- Boot -|"
echo "|--------|"
pacman -S grub efibootmgr --noconfirm
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

if [[ "$GRUB_CHOICE" == "1" ]]; then
  sed -i 's/^#\?GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/' /etc/default/grub
fi
grub-mkconfig -o /boot/grub/grub.cfg

echo 
echo "|-----------|"
echo "|- Desktop -|"
echo "|-----------|"
if [[ "${DE}" == "1" ]]; then
  pacman -S xorg plasma sddm konsole dolphin ark kwrite kcalc spectacle krunner partitionmanager --noconfirm
  systemctl enable sddm
elif [[ "${DE}" == "2" ]]; then
  pacman -S xorg gnome gdm gnome-terminal nautilus gnome-extra gnome-disk-utility gnome-tweaks --noconfirm
  systemctl enable gdm
else
  echo "No desktop installed."
fi

echo 
echo "|-------------|"
echo "|- Cleaning 2-|"
echo "|-------------|"
rm -f /install_chroot.sh

echo "| ARCHroot Done |"

INSTALL

chmod +x /mnt/install_chroot.sh
arch-chroot /mnt /install_chroot.sh

echo 
echo "|------------|"
echo "|- Umounting-|"
echo "|------------|"
umount /mnt/boot/efi || true
umount /mnt || true

echo "| Removing installer script |"
rm -- "$0"

echo
echo "|--------------|"
echo "|-  Finished  -|"
echo "|-  Have fun! -|"
echo "|--------------|"
