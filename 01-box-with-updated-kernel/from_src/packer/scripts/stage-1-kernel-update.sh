#!/bin/bash
#Get source tarball
cd /usr/src/
curl -O https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.4.41.tar.xz
tar xvf linux-5.4.41.tar.xz

cd linux-5.4.41

#Install compile tools
yum groupinstall -y "Development Tools"
yum install -y ncurses-devel openssl-devel bc elfutils-libelf-devel

#Compile
yes "" | make oldconfig
make -j4

#Install
make modules_install install

#не компилится вбокс гест? и похуй, все равно работает через плагин

#Update boot record
grub2-mkconfig -o /boot/grub2/grub.cfg
grub2-set-default 0
echo "Grub update done."
# Reboot VM
shutdown -r now
