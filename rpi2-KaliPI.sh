#!/bin/bash
. rpi2-KaliPI.config

# This is the Raspberry Pi2 Kali ARM build script - http://www.kali.org/downloads
# A trusted Kali Linux image created by Offensive Security - http://www.offensive-security.com
# Modded by CyberSec2k @8/2015

if [[ $# -eq 0 ]] ; then
    echo "Please pass version number, e.g. $0 2.0"
    exit 0
fi

basedir=`pwd`/rpi2-$1
# Make sure that the cross compiler can be found in the path before we do
# anything else, that way the builds don't fail half way through.
if [ $(compgen -c $CROSS_COMPILE | wc -l) -eq 0 ] ; then
    echo "Missing cross compiler."
    exit 1
fi

rm -rf rpi2-${kalipirelease}

# Package installations for various sections.
# This will build a minimal XFCE Kali system with the top 10 tools.
# This is the section to edit if you would like to add more packages.
# See http://www.kali.org/new/kali-linux-metapackages/ for meta packages you can
# use. You can also install packages, using just the package name, but keep in
# mind that not all packages work on ARM! If you specify one of those, the
# script will throw an error, but will still continue on, and create an unusable
# image, keep that in mind.

arm="abootimg cgpt fake-hwclock ntpdate u-boot-tools vboot-utils vboot-kernel-utils"
base="e2fsprogs initramfs-tools kali-defaults kali-menu parted sudo usbutils"
desktop="fonts-croscore fonts-crosextra-caladea fonts-crosextra-carlito gnome-theme-kali gtk3-engines-xfce kali-desktop-xfce kali-root-login lightdm network-manager network-manager-gnome xfce4 xserver-xorg-video-fbdev"
tools="aircrack-ng ethtool hydra john libnfc-bin mfoc nmap passing-the-hash sqlmap usbutils winexe wireshark"
services="apache2 openssh-server"
extras="iceweasel xfce4-terminal wpasupplicant"
# kernel sauces take up space yo.
size=7000 # Size of image in megabytes

packages="${arm} ${base} ${desktop} ${tools} ${services} ${extras}"
architecture="armhf"
# If you have your own preferred mirrors, set them here.
# You may want to leave security.kali.org alone, but if you trust your local
# mirror, feel free to change this as well.
# After generating the rootfs, we set the sources.list to the default settings.
mirror=repo.kali.org
security=security.kali.org

# Set this to use an http proxy, like apt-cacher-ng, and uncomment further down
# to unset it.
if [ "${useaptcacher}" == "YES" ]; then
export http_proxy="http://localhost:3142/"
fi

mkdir -p ${basedir}
cd ${basedir}

# create the rootfs - not much to modify here, except maybe the hostname.
debootstrap --foreign --arch $architecture sana kali-$architecture http://$mirror/kali

cp /usr/bin/qemu-arm-static kali-$architecture/usr/bin/

LANG=C chroot kali-$architecture /debootstrap/debootstrap --second-stage
cat << EOF > kali-$architecture/etc/apt/sources.list
deb http://$mirror/kali sana main contrib non-free
deb http://$security/kali-security sana/updates main contrib non-free
EOF

# Set hostname
echo "KaliPI" > kali-$architecture/etc/hostname

cat << EOF > kali-$architecture/etc/hosts
127.0.0.1       KaliPI    localhost
::1             localhost ip6-localhost ip6-loopback
fe00::0         ip6-localnet
ff00::0         ip6-mcastprefix
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

cat << EOF > kali-$architecture/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

cat << EOF > kali-$architecture/etc/resolv.conf
nameserver 8.8.8.8
EOF

export MALLOC_CHECK_=0 # workaround for LP: #520465
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

mount -t proc proc kali-$architecture/proc
mount -o bind /dev/ kali-$architecture/dev/
mount -o bind /dev/pts kali-$architecture/dev/pts

cat << EOF > kali-$architecture/debconf.set
console-common console-data/keymap/policy select Select keymap from full list
console-common console-data/keymap/full select en-latin1-nodeadkeys
EOF

cat << EOF > kali-$architecture/third-stage
#!/bin/bash
dpkg-divert --add --local --divert /usr/sbin/invoke-rc.d.chroot --rename /usr/sbin/invoke-rc.d
cp /bin/true /usr/sbin/invoke-rc.d
echo -e "#!/bin/sh\nexit 101" > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d

apt-get update
apt-get install locales-all

debconf-set-selections /debconf.set
rm -f /debconf.set
apt-get update
apt-get -y install git-core binutils ca-certificates initramfs-tools u-boot-tools
apt-get -y install locales console-common less nano git
echo "root:toor" | chpasswd
sed -i -e 's/KERNEL\!=\"eth\*|/KERNEL\!=\"/' /lib/udev/rules.d/75-persistent-net-generator.rules
rm -f /etc/udev/rules.d/70-persistent-net.rules
export DEBIAN_FRONTEND=noninteractive
apt-get --yes --force-yes install $packages
apt-get --yes --force-yes dist-upgrade
apt-get --yes --force-yes autoremove

# Because copying in authorized_keys is hard for people to do, let's make the
# image insecure and enable root login with a password.

echo "Making the image insecure"
sed -i -e 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config
update-rc.d ssh enable

rm -f /usr/sbin/policy-rc.d
rm -f /usr/sbin/invoke-rc.d
dpkg-divert --remove --rename /usr/sbin/invoke-rc.d

rm -f /third-stage
EOF

chmod +x kali-$architecture/third-stage
LANG=C chroot kali-$architecture /third-stage

cat << EOF > kali-$architecture/cleanup
#!/bin/bash
rm -rf /root/.bash_history
apt-get update
apt-get clean
rm -f /0
rm -f /hs_err*
rm -f cleanup
rm -f /usr/bin/qemu*
EOF

chmod +x kali-$architecture/cleanup
LANG=C chroot kali-$architecture /cleanup

umount kali-$architecture/proc/sys/fs/binfmt_misc
umount kali-$architecture/dev/pts
umount kali-$architecture/dev/
umount kali-$architecture/proc

# Create the disk and partition it
echo "Creating image file for Raspberry Pi2"
dd if=/dev/zero of=${basedir}/kali-$1-rpi2.img bs=1M count=$size
parted kali-$1-rpi2.img --script -- mklabel msdos
parted kali-$1-rpi2.img --script -- mkpart primary fat32 0 64
parted kali-$1-rpi2.img --script -- mkpart primary ext4 64 -1

# Set the partition variables
loopdevice=`losetup -f --show ${basedir}/kali-$1-rpi2.img`
device=`kpartx -va $loopdevice| sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
device="/dev/mapper/${device}"
bootp=${device}p1
rootp=${device}p2

# Create file systems
# Wait for loop0p1
sleep 5 ; sync
mkfs.vfat $bootp
mkfs.ext4 $rootp

# Create the dirs for the partitions and mount them
mkdir -p ${basedir}/bootp ${basedir}/root
mount $bootp ${basedir}/bootp
mount $rootp ${basedir}/root

echo "Rsyncing rootfs into image file"
rsync -HPavz -q ${basedir}/kali-$architecture/ ${basedir}/root/

# Enable login over serial
echo "T0:23:respawn:/sbin/agetty -L ttyAMA0 115200 vt100" >> ${basedir}/root/etc/inittab

cat << EOF > ${basedir}/root/etc/apt/sources.list
deb http://http.kali.org/kali sana main non-free contrib
deb http://security.kali.org/kali-security sana/updates main contrib non-free

deb-src http://http.kali.org/kali sana main non-free contrib
deb-src http://security.kali.org/kali-security sana/updates main contrib non-free
EOF

# Create cmdline.txt file
cat << EOF > ${basedir}/bootp/cmdline.txt
dwc_otg.fiq_fix_enable=2 console=tty1 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rootflags=noload
EOF

# Create config.txt file
cat << EOF > ${basedir}/bootp/config.txt
gpu_mem=16
EOF

# systemd doesn't seem to be generating the fstab properly for some people, so
# let's create one.
cat << EOF > ${basedir}/root/etc/fstab
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc /proc proc nodev,noexec,nosuid 0  0
/dev/mmcblk0p2  / ext4 errors=remount-ro 0 1
# Change this if you add a swap partition or file
#/dev/SWAP none swap sw 0 0 
/dev/mmcblk0p1 /boot vfat noauto 0 0
EOF

# Uncomment this if you use apt-cacher-ng otherwise git clones will fail.
if [ "${useaptcacher}" == "YES" ]; then
unset http_proxy
fi

# Kernel section. If you want to use a custom kernel, or configuration, replace them in this section.
git clone --depth 1 https://github.com/raspberrypi/linux -b rpi-3.18.y ${basedir}/root/usr/src/kernel
cd ${basedir}/root/usr/src/kernel
git rev-parse HEAD > kernel-at-commit
patch -p1 --no-backup-if-mismatch < ${basedir}/../../kali-arm-build-scripts/patches/kali-wifi-injection-3.18.patch
touch .scmversion
make clean
cp ${basedir}/../kernel-configs/${kernelconf} .config
cp ${basedir}/../kernel-configs/${kernelconf} ../${kernelconf}
make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE -j $(grep -c processor /proc/cpuinfo)
make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE modules_install INSTALL_MOD_PATH=${basedir}/root
git clone --depth 1 https://github.com/raspberrypi/firmware.git rpi-firmware
cp -rf rpi-firmware/boot/* ${basedir}/bootp/
cp arch/arm/boot/zImage ${basedir}/bootp/kernel7.img
cp arch/arm/boot/dts/bcm*.dtb ${basedir}/bootp/
make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE mrproper
cp ../${kernelconf} .config
make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE modules_prepare
cd ${basedir}
rm -rf ${basedir}/root/lib/firmware
cd ${basedir}/root/lib
git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git firmware
rm -rf ${basedir}/root/lib/firmware/.git
cp ${basedir}/../misc/zram ${basedir}/root/etc/init.d/zram
chmod +x ${basedir}/root/etc/init.d/zram

# Unmount partitions
cd ${basedir}
sync
umount $bootp
umount $rootp
sync
kpartx -dv $loopdevice
sync
losetup -d $loopdevice

# Clean up all the temporary build stuff and remove the directories.
# Comment this out to keep things around if you want to see what may have gone
# wrong.
#echo "Cleaning up the temporary build files..."
#rm -rf ${basedir}/kernel ${basedir}/bootp ${basedir}/root ${basedir}/kali-armhf ${basedir}/boot ${basedir}/patches

# If you're building an image for yourself, comment all of this out, as you
# don't need the sha1sum or to compress the image, since you will be testing it
# soon.
echo "Generating sha1sum for kali-$1-rpi2.img"
cd ${basedir}
sha1sum kali-$1-rpi2.img > kali-$1-rpi2.img.sha1sum
# Don't pixz on 32bit, there isn't enough memory to compress the images.
MACHINE_TYPE=`uname -m`
if [ ${MACHINE_TYPE} == 'x86_64' ]; then
echo "Compressing kali-$1-rpi2.img"
pixz kali-$1-rpi2.img kali-$1-rpi2.img.xz
rm kali-$1-rpi2.img
echo "Generating sha1sum for kali-$1-rpi2.img.xz"
sha1sum kali-$1-rpi2.img.xz > kali-$1-rpi2.img.xz.sha1sum
fi
