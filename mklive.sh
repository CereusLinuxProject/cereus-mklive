#!/bin/bash
#
#-
# Copyright (c) 2009-2015 Juan Romero Pardines.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#-
umask 022

. ./lib.sh

readonly REQUIRED_PKGS="base-files>=2022.07.03 libgcc dash coreutils sed tar gawk syslinux grub-cereus-i386-efi grub-cereus-x86_64-efi memtest86+ squashfs-tools xorriso"
readonly INITRAMFS_PKGS="binutils xz device-mapper dhclient dracut-network openresolv"
readonly PROGNAME=$(basename "$0")
declare -a INCLUDE_DIRS=()

info_msg() {
    printf "\033[1m$@\n\033[m"
}
die() {
    info_msg "ERROR: $@"
    error_out 1 $LINENO
}
print_step() {
    CURRENT_STEP=$((CURRENT_STEP+1))
    info_msg "[${CURRENT_STEP}/${STEP_COUNT}] $@"
}
mount_pseudofs() {
    for f in sys dev proc; do
        mkdir -p "$ROOTFS"/$f
        mount --rbind /$f "$ROOTFS"/$f
    done
}
umount_pseudofs() {
	for f in sys dev proc; do
		if [ -d "$ROOTFS/$f" ] && ! umount -R -f "$ROOTFS/$f"; then
			info_msg "ERROR: failed to unmount $ROOTFS/$f/"
			return 1
		fi
	done
}
error_out() {
	trap - INT TERM 0
    umount_pseudofs || exit "${1:-0}"
    [ -d "$BUILDDIR" ] && [ -z "$KEEP_BUILDDIR" ] && rm -rf --one-file-system "$BUILDDIR"
    exit "${1:-0}"
}

usage() {
	cat <<-EOH
	Usage: $PROGNAME [options]

	Generates a basic live ISO image of Cereus Linux. This ISO image can be written
	to a CD/DVD-ROM or any USB stick.

	To generate a more complete live ISO image, use build-x86-images.sh.
	
	OPTIONS
	 -a <arch>          Set XBPS_ARCH in the ISO image
	 -b <system-pkg>    Set an alternative base package (default: base-cereus)
	 -r <repo>          Use this XBPS repository. May be specified multiple times
	 -c <cachedir>      Use this XBPS cache directory (default: ./xbps-cachedir-<arch>)
	 -k <keymap>        Default keymap to use (default: us)
	 -l <locale>        Default locale to use (default: en_US.UTF-8)
	 -i <lz4|gzip|bzip2|xz>
	                    Compression type for the initramfs image (default: xz)
	 -s <gzip|lzo|xz>   Compression type for the squashfs image (default: xz)
	 -o <file>          Output file name for the ISO image (default: automatic)
	 -p "<pkg> ..."     Install additional packages in the ISO image
	 -g "<pkg> ..."     Ignore packages when building the ISO image
	 -I <includedir>    Include directory structure under given path in the ROOTFS
	 -S "<service> ..." Enable services in the ISO image
	 -C "<arg> ..."     Add additional kernel command line arguments
	 -T <title>         Modify the bootloader title (default: Cereus Linux)
	 -v linux<version>  Install a custom Linux version on ISO image (default: linux-default-cereus metapackage)
	 -K                 Do not remove builddir
	 -h                 Show this help and exit
	 -V                 Show version and exit
	EOH
}

copy_xbps_keys() {
    mkdir -p "$1"/var/db/xbps/keys
    cp keys/*.plist "$1"/var/db/xbps/keys
}

copy_dracut_files() {
    mkdir -p "$1"/usr/lib/dracut/modules.d/01vmklive
    cp dracut/vmklive/* "$1"/usr/lib/dracut/modules.d/01vmklive/
}

copy_autoinstaller_files() {
    mkdir -p "$1"/usr/lib/dracut/modules.d/01autoinstaller
    cp dracut/autoinstaller/* "$1"/usr/lib/dracut/modules.d/01autoinstaller/
}

install_prereqs() {
    XBPS_ARCH=$ARCH "$XBPS_INSTALL_CMD" -r "$CEREUSHOSTDIR" ${XBPS_REPOSITORY} \
         -c "$XBPS_HOST_CACHEDIR" -y $REQUIRED_PKGS
    [ $? -ne 0 ] && die "Failed to install required software, exiting..."
}

install_packages() {
    XBPS_ARCH=$BASE_ARCH "${XBPS_INSTALL_CMD}" -r "$ROOTFS" \
        ${XBPS_REPOSITORY} -c "$XBPS_CACHEDIR" -yn $PACKAGE_LIST $INITRAMFS_PKGS
    [ $? -ne 0 ] && die "Missing required binary packages, exiting..."

    mount_pseudofs

    LANG=C XBPS_ARCH=$BASE_ARCH "${XBPS_INSTALL_CMD}" -U -r "$ROOTFS" \
        ${XBPS_REPOSITORY} -c "$XBPS_CACHEDIR" -y $PACKAGE_LIST $INITRAMFS_PKGS
    [ $? -ne 0 ] && die "Failed to install $PACKAGE_LIST"

    xbps-reconfigure -r "$ROOTFS" -f base-files >/dev/null 2>&1
    chroot "$ROOTFS" env -i xbps-reconfigure -f base-files

    # Enable choosen UTF-8 locale and generate it into the target rootfs.
    if [ -f "$ROOTFS"/etc/default/libc-locales ]; then
        sed -e "s/\#\(${LOCALE}.*\)/\1/g" -i "$ROOTFS"/etc/default/libc-locales
    fi
    chroot "$ROOTFS" env -i xbps-reconfigure -a

    # Cleanup and remove useless stuff.
    rm -rf "$ROOTFS"/var/cache/* "$ROOTFS"/run/* "$ROOTFS"/var/run/*
}

ignore_packages() {
	mkdir -p "$ROOTFS"/etc/xbps.d
	for pkg in $IGNORE_PKGS; do
		echo "ignorepkg=$pkg" >> "$ROOTFS"/etc/xbps.d/mklive-ignore.conf
	done
}

enable_services() {
    SERVICE_LIST="$*"
    for service in $SERVICE_LIST; do
        if ! [ -e $ROOTFS/etc/sv/$service ]; then
            die "service $service not in /etc/sv"
        fi
        ln -sf /etc/sv/$service $ROOTFS/etc/runit/runsvdir/default/
    done
}

copy_include_directories() {
    for includedir in "${INCLUDE_DIRS[@]}"; do
            info_msg "=> copying include directory '$includedir' ..."
	    find "$includedir" -mindepth 1 -maxdepth 1 -exec cp -rfpPv {} "$ROOTFS"/ \;

	    # Correct includedir permissions.
	    touch .includedir_list
	    find "$includedir" | sed 's|'"$includedir"'|'"$ROOTFS"'|g' | tee .includedir_list >/dev/null
	    chown root:root $(cat .includedir_list)
	    rm .includedir_list
    done
}

generate_initramfs() {
    local _args

    copy_dracut_files "$ROOTFS"
    copy_autoinstaller_files "$ROOTFS"
    
    # Apply Plymouth theme
    if [ -f "$ROOTFS/etc/plymouth/plymouthd.conf" ]; then
        chroot "$ROOTFS" plymouth-set-default-theme cereus_simply
    fi
        
    chroot "$ROOTFS" env -i /usr/bin/dracut -N --"${INITRAMFS_COMPRESSION}" \
        --add-drivers "ahci" --force-add "vmklive autoinstaller" --omit systemd "/boot/initrd" $KERNELVERSION
    [ $? -ne 0 ] && die "Failed to generate the initramfs"



    mv "$ROOTFS"/boot/initrd "$BOOT_DIR"
    cp "$ROOTFS"/boot/vmlinuz-$KERNELVERSION "$BOOT_DIR"/vmlinuz
}

cleanup_rootfs() {
    for f in ${INITRAMFS_PKGS}; do
        revdeps=$(xbps-query -r "$ROOTFS" -X $f)
        if [ -n "$revdeps" ]; then
            xbps-pkgdb -r "$ROOTFS" -m auto $f
        else
            xbps-remove -r "$ROOTFS" -Ry ${f} >/dev/null 2>&1
        fi
    done
    rm -r "$ROOTFS"/usr/lib/dracut/modules.d/01vmklive
    rm -r "$ROOTFS"/usr/lib/dracut/modules.d/01autoinstaller
}

generate_isolinux_boot() {
    cp -f "$SYSLINUX_DATADIR"/isolinux.bin "$ISOLINUX_DIR"
    cp -f "$SYSLINUX_DATADIR"/ldlinux.c32 "$ISOLINUX_DIR"
    cp -f "$SYSLINUX_DATADIR"/libcom32.c32 "$ISOLINUX_DIR"
    cp -f "$SYSLINUX_DATADIR"/vesamenu.c32 "$ISOLINUX_DIR"
    cp -f "$SYSLINUX_DATADIR"/libutil.c32 "$ISOLINUX_DIR"
    cp -f "$SYSLINUX_DATADIR"/chain.c32 "$ISOLINUX_DIR"
    cp -f "$SYSLINUX_DATADIR"/reboot.c32 "$ISOLINUX_DIR"
    cp -f "$SYSLINUX_DATADIR"/poweroff.c32 "$ISOLINUX_DIR"
    cp -f isolinux/isolinux.cfg.in "$ISOLINUX_DIR"/isolinux.cfg
    cp -f ${SPLASH_IMAGE} "$ISOLINUX_DIR"

    sed -i  -e "s|@@SPLASHIMAGE@@|$(basename "${SPLASH_IMAGE}")|" \
        -e "s|@@KERNVER@@|${KERNELVERSION}|" \
        -e "s|@@KEYMAP@@|${KEYMAP}|" \
        -e "s|@@ARCH@@|$BASE_ARCH|" \
        -e "s|@@LOCALE@@|${LOCALE}|" \
        -e "s|@@BOOT_TITLE@@|${BOOT_TITLE}|" \
        -e "s|@@BOOT_CMDLINE@@|${BOOT_CMDLINE}|" \
        "$ISOLINUX_DIR"/isolinux.cfg

    # include memtest86+
    cp -f "$CEREUSHOSTDIR"/boot/memtest.bin "$BOOT_DIR"
}

generate_grub_efi_boot() {
    cp -f grub/grub.cfg "$GRUB_DIR"
    cp -f grub/grub_cereus.cfg.in "$GRUB_DIR"/grub_cereus.cfg
    sed -i  -e "s|@@SPLASHIMAGE@@|$(basename "${SPLASH_IMAGE}")|" \
        -e "s|@@KERNVER@@|${KERNELVERSION}|" \
        -e "s|@@KEYMAP@@|${KEYMAP}|" \
        -e "s|@@ARCH@@|$BASE_ARCH|" \
        -e "s|@@BOOT_TITLE@@|${BOOT_TITLE}|" \
        -e "s|@@BOOT_CMDLINE@@|${BOOT_CMDLINE}|" \
        -e "s|@@LOCALE@@|${LOCALE}|" "$GRUB_DIR"/grub_cereus.cfg
    mkdir -p "$GRUB_DIR"/fonts
    cp -f "$GRUB_DATADIR"/unicode.pf2 "$GRUB_DIR"/fonts

    modprobe -q loop || :

    # Create EFI vfat image.
    truncate -s 32M "$GRUB_DIR"/efiboot.img >/dev/null 2>&1
    mkfs.vfat -F12 -S 512 -n "grub_uefi" "$GRUB_DIR/efiboot.img" >/dev/null 2>&1

    GRUB_EFI_TMPDIR="$(mktemp --tmpdir="$HOME" -d)"
    LOOP_DEVICE="$(losetup --show --find "${GRUB_DIR}"/efiboot.img)"
    mount -o rw,flush -t vfat "${LOOP_DEVICE}" "${GRUB_EFI_TMPDIR}" >/dev/null 2>&1

    cp -a "$IMAGEDIR"/boot "$CEREUSHOSTDIR"
    xbps-uchroot "$CEREUSHOSTDIR" grub-mkstandalone -- \
		 --directory="/usr/lib/grub/i386-efi" \
		 --format="i386-efi" \
		 --output="/tmp/bootia32.efi" \
		 "boot/grub/grub.cfg"
    if [ $? -ne 0 ]; then
        umount "$GRUB_EFI_TMPDIR"
        losetup --detach "${LOOP_DEVICE}"
        die "Failed to generate EFI loader"
    fi
    mkdir -p "${GRUB_EFI_TMPDIR}"/EFI/BOOT
    cp -f "$CEREUSHOSTDIR"/tmp/bootia32.efi "${GRUB_EFI_TMPDIR}"/EFI/BOOT/BOOTIA32.EFI
    xbps-uchroot "$CEREUSHOSTDIR" grub-mkstandalone -- \
		 --directory="/usr/lib/grub/x86_64-efi" \
		 --format="x86_64-efi" \
		 --output="/tmp/bootx64.efi" \
		 "boot/grub/grub.cfg"
    if [ $? -ne 0 ]; then
        umount "$GRUB_EFI_TMPDIR"
        losetup --detach "${LOOP_DEVICE}"
        die "Failed to generate EFI loader"
    fi
    cp -f "$CEREUSHOSTDIR"/tmp/bootx64.efi "${GRUB_EFI_TMPDIR}"/EFI/BOOT/BOOTX64.EFI
    umount "$GRUB_EFI_TMPDIR"
    losetup --detach "${LOOP_DEVICE}"
    rm -rf "$GRUB_EFI_TMPDIR"

    # include memtest86+
    cp -f "$VOIDHOSTDIR"/boot/memtest.efi "$BOOT_DIR"
}

generate_squashfs() {
    umount_pseudofs || exit 1

    # Find out required size for the rootfs and create an ext3fs image off it.
    ROOTFS_SIZE=$(du --apparent-size -sm "$ROOTFS"|awk '{print $1}')
    mkdir -p "$BUILDDIR/tmp/LiveOS"
    truncate -s "$((ROOTFS_SIZE+ROOTFS_SIZE))M" \
	    "$BUILDDIR"/tmp/LiveOS/ext3fs.img >/dev/null 2>&1
    mkdir -p "$BUILDDIR/tmp-rootfs"
    mkfs.ext3 -F -m1 "$BUILDDIR/tmp/LiveOS/ext3fs.img" >/dev/null 2>&1
    mount -o loop "$BUILDDIR/tmp/LiveOS/ext3fs.img" "$BUILDDIR/tmp-rootfs"
    cp -a "$ROOTFS"/* "$BUILDDIR"/tmp-rootfs/
    umount -f "$BUILDDIR/tmp-rootfs"
    mkdir -p "$IMAGEDIR/LiveOS"

    "$CEREUSHOSTDIR"/usr/bin/mksquashfs "$BUILDDIR/tmp" "$IMAGEDIR/LiveOS/squashfs.img" \
        -comp "${SQUASHFS_COMPRESSION}" || die "Failed to generate squashfs image"
    chmod 444 "$IMAGEDIR/LiveOS/squashfs.img"

    # Remove rootfs and temporary dirs, we don't need them anymore.
    rm -rf "$ROOTFS" "$BUILDDIR/tmp-rootfs" "$BUILDDIR/tmp"
}

generate_iso_image() {
    "$CEREUSHOSTDIR"/usr/bin/xorriso -as mkisofs \
        -iso-level 3 -rock -joliet \
        -max-iso9660-filenames -omit-period \
        -omit-version-number -relaxed-filenames -allow-lowercase \
        -volid "CEREUS_LIVE" \
        -eltorito-boot boot/isolinux/isolinux.bin \
        -eltorito-catalog boot/isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot -e boot/grub/efiboot.img -isohybrid-gpt-basdat -no-emul-boot \
        -isohybrid-mbr "$SYSLINUX_DATADIR"/isohdpfx.bin \
        -output "$OUTPUT_FILE" "$IMAGEDIR" || die "Failed to generate ISO image"
}

#
# main()
#
while getopts "a:b:r:c:C:T:Kk:l:i:I:S:s:o:p:g:v:Vh" opt; do
	case $opt in
		a) BASE_ARCH="$OPTARG";;
		b) BASE_SYSTEM_PKG="$OPTARG";;
		r) XBPS_REPOSITORY="--repository=$OPTARG $XBPS_REPOSITORY";;
		c) XBPS_CACHEDIR="$OPTARG";;
		g) IGNORE_PKGS="$IGNORE_PKGS $OPTARG" ;;
		K) readonly KEEP_BUILDDIR=1;;
		k) KEYMAP="$OPTARG";;
		l) LOCALE="$OPTARG";;
		i) INITRAMFS_COMPRESSION="$OPTARG";;
		I) INCLUDE_DIRS+=("$OPTARG");;
		S) SERVICE_LIST="$SERVICE_LIST $OPTARG";;
		s) SQUASHFS_COMPRESSION="$OPTARG";;
		o) OUTPUT_FILE="$OPTARG";;
		p) PACKAGE_LIST="$PACKAGE_LIST $OPTARG";;
		C) BOOT_CMDLINE="$OPTARG";;
		T) BOOT_TITLE="$OPTARG";;
		v) LINUX_VERSION="$OPTARG";;
		V) version; exit 0;;
		h) usage; exit 0;;
		*) usage >&2; exit 1;;
	esac
done
shift $((OPTIND - 1))

ARCH=$(xbps-uhelper arch)

XBPS_REPOSITORY="$XBPS_REPOSITORY --repository=https://repo-default.voidlinux.org/current \
 --repository=https://repo-default.voidlinux.org/current/musl \
 --repository=https://sourceforge.net/projects/cereus-linux/files/repos/cereus-core/${ARCH} \
 --repository=https://sourceforge.net/projects/cereus-linux/files/repos/cereus-extra/${ARCH}"
 
# Configure dracut to use overlayfs for the writable overlay.
BOOT_CMDLINE="$BOOT_CMDLINE rd.live.overlay.overlayfs=1 "

ARCH=$(xbps-uhelper arch)

# Set defaults
: ${BASE_ARCH:=$(xbps-uhelper arch 2>/dev/null || uname -m)}
: ${XBPS_CACHEDIR:="$(pwd -P)"/xbps-cachedir-${BASE_ARCH}}
: ${XBPS_HOST_CACHEDIR:="$(pwd -P)"/xbps-cachedir-${ARCH}}
: ${KEYMAP:=us}
: ${LOCALE:=en_US.UTF-8}
: ${INITRAMFS_COMPRESSION:=xz}
: ${SQUASHFS_COMPRESSION:=xz}
: ${BASE_SYSTEM_PKG:=base-cereus}
: ${BOOT_TITLE:="Cereus Linux"}

case $BASE_ARCH in
    x86_64*|i686*) ;;
    *) >&2 echo architecture $BASE_ARCH not supported by mklive.sh; exit 1;;
esac

# Required packages in the image for a working system.
PACKAGE_LIST="$BASE_SYSTEM_PKG $PACKAGE_LIST"

# Check for root permissions.
if [ "$(id -u)" -ne 0 ]; then
    die "Must be run as root, exiting..."
fi

trap 'error_out $? $LINENO' INT TERM 0

if [ -n "$ROOTDIR" ]; then
    BUILDDIR=$(mktemp --tmpdir="$ROOTDIR" -d)
else
    BUILDDIR=$(mktemp --tmpdir="$(pwd -P)" -d)
fi
BUILDDIR=$(readlink -f "$BUILDDIR")
IMAGEDIR="$BUILDDIR/image"
ROOTFS="$IMAGEDIR/rootfs"
CEREUSHOSTDIR="$BUILDDIR/cereus-host"
BOOT_DIR="$IMAGEDIR/boot"
ISOLINUX_DIR="$BOOT_DIR/isolinux"
GRUB_DIR="$BOOT_DIR/grub"
CURRENT_STEP=0
STEP_COUNT=10
[ "${#INCLUDE_DIRS[@]}" -gt 0 ] && STEP_COUNT=$((STEP_COUNT+1))
[ -n "${IGNORE_PKGS}" ] && STEP_COUNT=$((STEP_COUNT+1))

: ${SYSLINUX_DATADIR:="$CEREUSHOSTDIR"/usr/lib/syslinux}
: ${GRUB_DATADIR:="$CEREUSHOSTDIR"/usr/share/grub}
: ${SPLASH_IMAGE:=data/splash.png}
: ${XBPS_INSTALL_CMD:=xbps-install}
: ${XBPS_REMOVE_CMD:=xbps-remove}
: ${XBPS_QUERY_CMD:=xbps-query}
: ${XBPS_RINDEX_CMD:=xbps-rindex}
: ${XBPS_UHELPER_CMD:=xbps-uhelper}
: ${XBPS_RECONFIGURE_CMD:=xbps-reconfigure}

mkdir -p "$ROOTFS" "$CEREUSHOSTDIR" "$ISOLINUX_DIR" "$GRUB_DIR"

print_step "Synchronizing XBPS repository data..."
copy_xbps_keys "$ROOTFS"
copy_xbps_keys "$CEREUSHOSTDIR"
XBPS_ARCH=$BASE_ARCH $XBPS_INSTALL_CMD -r "$ROOTFS" ${XBPS_REPOSITORY} -S
XBPS_ARCH=$ARCH $XBPS_INSTALL_CMD -r "$CEREUSHOSTDIR" ${XBPS_REPOSITORY} -S

# Get linux version for ISO
# If linux version option specified use
if [ -n "$LINUX_VERSION" ]; then
    if ! echo "$LINUX_VERSION" | grep "linux[0-9._]\+"; then
        die "-v option must be in format linux<version>"
    fi

    _linux_series="$LINUX_VERSION"
    PACKAGE_LIST="$PACKAGE_LIST $LINUX_VERSION"
else # Otherwise find latest stable version from corresponding default linux meta-package
    if [ $BASE_ARCH = "i686" ]; then
        linux_pkg="linux-legacy-cereus"
    else
        linux_pkg="linux-default-cereus"
    fi
    _linux_series=$(XBPS_ARCH=$BASE_ARCH $XBPS_QUERY_CMD -r "$ROOTFS" ${XBPS_REPOSITORY:=-R} -x $linux_pkg | grep 'linux[0-9._]\+')
fi

_kver=$(XBPS_ARCH=$BASE_ARCH $XBPS_QUERY_CMD -r "$ROOTFS" ${XBPS_REPOSITORY:=-R} -p pkgver ${_linux_series})
KERNELVERSION=$($XBPS_UHELPER_CMD getpkgversion ${_kver})

if [ "$?" -ne "0" ]; then
    die "Failed to find kernel package version"
fi

: ${OUTPUT_FILE="cereus-beta-live-${BASE_ARCH}-${KERNELVERSION}-$(date +%Y.%m%.d).iso"}

print_step "Installing software to generate the image: ${REQUIRED_PKGS} ..."
install_prereqs

mkdir -p "$ROOTFS"/etc
[ -s data/motd ] && cp data/motd "$ROOTFS"/etc
[ -s data/issue ] && cp data/issue "$ROOTFS"/etc

if [ -n "$IGNORE_PKGS" ]; then
	print_step "Ignoring packages in the rootfs: ${IGNORE_PKGS} ..."
	ignore_packages
fi

print_step "Installing cereus pkgs into the rootfs: ${PACKAGE_LIST} ..."
install_packages

: ${DEFAULT_SERVICE_LIST:=agetty-tty1 agetty-tty2 agetty-tty3 agetty-tty4 agetty-tty5 agetty-tty6 udevd}
print_step "Enabling services: ${SERVICE_LIST} ..."
enable_services ${DEFAULT_SERVICE_LIST} ${SERVICE_LIST}

if [ "${#INCLUDE_DIRS[@]}" -gt 0 ];then
    print_step "Copying directory structures into the rootfs ..."
    copy_include_directories
fi

print_step "Generating initramfs image ($INITRAMFS_COMPRESSION)..."
generate_initramfs

print_step "Generating isolinux support for PC-BIOS systems..."
generate_isolinux_boot

print_step "Generating GRUB support for EFI systems..."
generate_grub_efi_boot

print_step "Cleaning up rootfs..."
cleanup_rootfs

print_step "Generating squashfs image ($SQUASHFS_COMPRESSION) from rootfs..."
generate_squashfs

print_step "Generating ISO image..."
generate_iso_image

hsize=$(du -sh "$OUTPUT_FILE"|awk '{print $1}')
info_msg "Created $(readlink -f "$OUTPUT_FILE") ($hsize) successfully."
