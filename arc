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

read -p "Done? Press ENTER to continue..."

# --- NEW NUMERIC SELECTION LOGIC ---
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

echo "| Cleaning old mount and directories |"
swapoff -a 2>/dev/null || true
umount -R /mnt 2>/dev/null || true

echo "| Creating filesystems |"
mkfs.fat -F32 "${EFI}"
mkfs.ext4 -F "${ROOT}"
mkswap "${SWAP}"
swapon "${SWAP}"

echo "| Mount partitions |"
# 1. Mount ROOT first
mount "${ROOT}" /mnt

# 2. NOW create the directories inside the mounted root
mkdir -p /mnt/boot/efi

# 3. Mount EFI into the newly created folder
mount "${EFI}" /mnt/boot/efi
