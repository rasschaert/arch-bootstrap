#!/bin/bash

bootstrapper_dialog() {
    DIALOG_RESULT=$(dialog --clear --stdout --backtitle "Arch bootstrapper" --no-shadow "$@" 2>/dev/null)
}

#################
#### Welcome ####
#################
bootstrapper_dialog --title "Welcome" --msgbox "\nWelcome to Kenny's Arch Linux bootstrapper.\n" 6 60

##############################
#### UEFI / BIOS detection ###
##############################
efivar -l >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
    UEFI_BIOS_text="UEFI detected."
    UEFI_radio="on"
    BIOS_radio="off"
else
    UEFI_BIOS_text="BIOS detected."
    UEFI_radio="off"
    BIOS_radio="on"
fi

bootstrapper_dialog --title "UEFI or BIOS" --radiolist "${UEFI_BIOS_text}\nPress <Enter> to accept." 10 30 2 1 UEFI "$UEFI_radio" 2 BIOS "$BIOS_radio"
[[ $DIALOG_RESULT -eq 1 ]] && UEFI=1 || UEFI=0

#################
#### Prompts ####
#################
bootstrapper_dialog --title "Hostname" --inputbox "Please enter a name for this host.\n" 8 60
hostname="$DIALOG_RESULT"

##########################
#### Password prompts ####
##########################
bootstrapper_dialog --title "Disk encryption" --passwordbox "Please enter a strong passphrase for the full disk encryption.\n" 8 60
encryption_passphrase="$DIALOG_RESULT"

bootstrapper_dialog --title "Root password" --passwordbox "Please enter a strong password for the root user.\n" 8 60
root_password="$DIALOG_RESULT"

#################
#### Warning ####
#################
bootstrapper_dialog --title "WARNING" --msgbox "This script will NUKE /dev/sda from orbit.\nPress <Enter> to continue or <Esc> to cancel.\n" 6 60
[[ $? -ne 0 ]] && (bootstrapper_dialog --title "Cancelled" --msgbox "Script was cancelled at your request." 5 40; exit 0)

##########################
#### reset the screen ####
##########################
reset

#########################################
#### Nuke and set up disk partitions ####
#########################################
echo "Zapping disk"
sgdisk --zap-all /dev/sda

echo "Creating /dev/sda1"
if [[ $UEFI -eq 1 ]]; then
    printf "n\n1\n\n+1G\nef00\nw\ny\n" | gdisk /dev/sda
    yes | mkfs.fat -F32 /dev/sda1
else
    printf "n\np\n1\n\n+200M\nw\n" | fdisk /dev/sda
    yes | mkfs.xfs /dev/sda1
fi

echo "Creating /dev/sda2"
if [[ $UEFI -eq 1 ]]; then
    printf "n\n2\n\n\n8e00\nw\ny\n"| gdisk /dev/sda
else
    printf "n\np\n2\n\n\nt\n2\n8e\nw\n" | fdisk /dev/sda
fi

echo "Setting up encryption"
printf "%s" "$encryption_passphrase" | cryptsetup luksFormat /dev/sda2 -
printf "%s" "$encryption_passphrase" | cryptsetup open --type luks /dev/sda2 lvm -

echo "Setting up LVM"
pvcreate /dev/mapper/lvm
vgcreate vg00 /dev/mapper/lvm
lvcreate -L 20G vg00 -n lvroot
lvcreate -l +100%FREE vg00 -n lvhome

echo "Creating XFS file systems on top of logical volumes"
yes | mkfs.xfs /dev/mapper/vg00-lvroot
yes | mkfs.xfs /dev/mapper/vg00-lvhome

######################
#### Install Arch ####
######################

mount /dev/vg00/lvroot /mnt
mkdir /mnt/{boot,home}
mount /dev/sda1 /mnt/boot
mount /dev/vg00/lvhome /mnt/home

yes '' | pacstrap -i /mnt base base-devel

genfstab -U -p /mnt >> /mnt/etc/fstab

###############################
#### Configure base system ####
###############################
arch-chroot /mnt /bin/bash <<EOF
echo "Setting and generating locale"
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
export LANG=en_US.UTF-8
echo "LANG=en_US.UTF-8" >> /etc/locale.conf
echo "Setting time zone"
ln -s /usr/share/zoneinfo/Europe/Brussels /etc/localtime
echo "Setting hostname"
echo $hostname > /etc/hostname
sed -i "/localhost/s/$/ $hostname/" /etc/hosts
echo "Installing wifi packages"
pacman --noconfirm -S iw wpa_supplicant dialog wpa_actiond
echo "Generating initramfs"
sed -i 's/^HOOKS.*/HOOKS="base udev autodetect modconf block encrypt lvm2 filesystems keyboard fsck"/' /etc/mkinitcpio.conf
mkinitcpio -p linux
echo "Setting root password"
echo "root:${root_password}" | chpasswd
EOF

#############################
#### Install boot loader ####
#############################
if [[ $UEFI -eq 1 ]]; then
arch-chroot /mnt /bin/bash <<EOF
echo "Installing Gummiboot boot loader"
pacman --noconfirm -S gummiboot
gummiboot install
cat << GRUB > /boot/loader/entries/arch.conf
title          Arch Linux
linux          /vmlinuz-linux
initrd         /initramfs-linux.img
options        cryptdevice=/dev/sda2:vg00 root=/dev/mapper/vg00-lvroot rw
GRUB
EOF
else
arch-chroot /mnt /bin/bash <<EOF
    echo "Installing Grub boot loader"
    pacman --noconfirm -S grub
    grub-install --target=i386-pc --recheck /dev/sda
    sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT.*|GRUB_CMDLINE_LINUX_DEFAULT="quiet cryptdevice=/dev/partition:MyStorage root=/dev/mapper/MyStorage-rootvol"|' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
EOF
fi

#################
#### The end ####
#################

