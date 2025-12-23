#!/usr/bin/env bash

echo "Enter EFI partition (/dev/sda | /dev/nvme0n1)"
read EFI

echo "Enter SWAP partition (/dev/sda | /dev/nvme0n1)"
read SWAP

echo "Enter root (/) partition (/dev/sda | /dev/nvme0n1)"
read ROOT

echo "Enter username"
read USER

echo "Enter secure password"
read PASSWORD

echo "Choose DE"
echo "1 Gnome"
echo "2 KDE"
echo "3 No desktop"
read DESKTOP

#filesystem
echo -e "creating filesystems..."
mkfs.fat -F32 "${EFI}"
mkfs -t ext4 "${ROOT}"
mkswap "${SWAP}"
swapon "${SWAP}"

#mount target
mkdir /mnt
mount "${ROOT}" /mnt
mkdir -p /mnt/boot/efi
mount "${EFI}" /mnt/boot/efi


echo "|----------------------------|"
echo "|- Installing Arch and BASE -|"
echo "|----------------------------|"
pacstrap /mnt base base-devel --noconfirm --needed

#kernel
echo "|---------------------|"
echo "|- Installing Kernel -|"
echo "|---------------------|"
pacstrap /mnt linux-lts linux-lts-headers linux-firmware --noconfirm --needed

#dependencies
echo "|---------------------------------|"
echo "|- Setup dependencies and extras -|"
echo "|---------------------------------|"
pacstrap /mnt networkmanager network-manager-applet wireless_tools intel-ucode amd-ucode bluez bluez-utils nano git 

#fstab
genfstab -U /mnt >> /mnt/etc/fstab
echo "|--------------|"
echo "|- Bootloader -|"
echo "|--------------|"
bootctl install --path /mnt/boot/efi
echo "default arch.conf" >> /mnt/boot/efi/loader/loader.conf
cat <<EOF > /mnt/boot/efi/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux-lts
options root=${ROOT} rw
EOF

cat <<REALEND > /mnt/next.sh
useradd -m $USER
usermod -aG wheel,storage,audio,video,power $USER
echo $USER:$PASSWORD | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL)/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "|------------------------|"
echo "|- Set Language English -|"
echo "|------------------------|"
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >> /etc/locale.conf
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
hwclock -systohc

echo "|----------------|"
echo "|- Set Hostname -|"
echo "|----------------|"
echo "arch" > /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   arch
EOF

echo "|---------------------|"
echo "|- Display and Audio -|"
echo "|---------------------|"

pacman -S xorg pulseaudio --noconfirm --needed

systemctl enable NetworkManager bluetooth

#de
if [[ $DESKTOP == '1' ]]
then
  pacman -S gnome gnome-terminal nautilus gnome-extra gnome-disk-utility network-manager-applet gnome-tweaks --noconfirm --needed
  systemctl enable gdm
elif [[ $DESKTOP == '2' ]]
then
  pacman -S plasma konsole dolphin ark kwrite kcalc spectacle krunner partitionmanager
  systemctl enable sddm
else
  echo "You have chosen to install DE yourself"
fi

echo "|--------------------|"
echo "|- Install complete -|"
echo "|--------------------|"

REALEND

arch-chroot /mnt sh next.sh
