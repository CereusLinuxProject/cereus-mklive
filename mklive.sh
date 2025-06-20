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

REQUIRED_PKGS=(base-files-cereus libgcc dash coreutils sed tar gawk squashfs-tools xorriso)
TARGET_PKGS=(base-files-cereus)
INITRAMFS_PKGS=(binutils xz device-mapper dhclient dracut-network openresolv)
PACKAGE_LIST=(jq)
IGNORE_PKGS=()
PLATFORMS=()
PROGNAME="$(basename "$0")"; readonly PROGNAME
declare -a INCLUDE_DIRS=()

die() {
    info_msg "ERROR: $*"
    error_out 1 $LINENO
}

print_step() {
    CURRENT_STEP=$((CURRENT_STEP+1))
    info_msg "[${CURRENT_STEP}/${STEP_COUNT}] $*"
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

	To generate a more complete live ISO image, use mkiso.sh.

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
	 -e <shell>         Default shell of the root user (must be absolute path).
	                    Set the live.shell kernel argument to change the default shell of anon.
	 -C "<arg> ..."     Add additional kernel command line arguments
	 -P "<platform> ..."
	                    Platforms to enable for aarch64 EFI ISO images (available: pinebookpro, x13s)
	 -T <title>         Modify the bootloader title (default: Cereus Linux)
	 -v linux<version>  Install a custom Linux version on ISO image (default: linux-default-cereus metapackage).
	                    Also accepts linux metapackages (like linux-legacy-cereus or linux-mainline-cereus).
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
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
	if ! XBPS_ARCH="$HOST_ARCH" "$XBPS_INSTALL_CMD" -r "$CEREUSHOSTDIR" ${HOST_REPOSITORIES[*]} \
		-c "$XBPS_HOST_CACHEDIR" -y "${REQUIRED_PKGS[@]}"; then
			die "Failed to install required software, exiting..."
    fi
}

install_target_pkgs() {
    # shellcheck disable=SC2086
    # shellcheck disable=SC2048
	if ! XBPS_ARCH=$TARGET_ARCH "$XBPS_INSTALL_CMD" -r "$CEREUSTARGETDIR" ${TARGET_REPOSITORIES[*]} \
		-c "$XBPS_HOST_CACHEDIR" -y "${TARGET_PKGS[@]}"; then
			die "Failed to install required software, exiting..."
	fi
}

post_install_packages() {
    # Cleanup and remove useless stuff.
    rm -rf "$ROOTFS"/var/cache/* "$ROOTFS"/run/* "$ROOTFS"/var/run/*

    # boot failure if disks have raid logical volumes and this isn't loaded
    for f in "$ROOTFS/usr/lib/modules/$KERNELVERSION/kernel/drivers/md/dm-raid.ko".*; do
        echo "dm-raid" > "$ROOTFS"/etc/modules-load.d/dm-raid.conf
        break
    done
}

install_packages() {
    # shellcheck disable=SC2086
    # shellcheck disable=SC2048
    if ! XBPS_ARCH=$TARGET_ARCH "${XBPS_INSTALL_CMD}" -r "$ROOTFS" \
        ${TARGET_REPOSITORIES[*]} -c "$XBPS_CACHEDIR" -yn "${PACKAGE_LIST[@]}" "${INITRAMFS_PKGS[@]}"; then
			die "Missing required binary packages, exiting..."
	fi

    mount_pseudofs

    # shellcheck disable=SC2086
    # shellcheck disable=SC2048
    if ! LANG=C XBPS_TARGET_ARCH=$TARGET_ARCH "${XBPS_INSTALL_CMD}" -U -r "$ROOTFS" \
        ${TARGET_REPOSITORIES[*]} -c "$XBPS_CACHEDIR" -y "${PACKAGE_LIST[@]}" "${INITRAMFS_PKGS[@]}"; then
			die "Failed to install ${PACKAGE_LIST[*]} ${INITRAMFS_PKGS[*]}"
	fi

    xbps-reconfigure -r "$ROOTFS" -f base-files-cereus >/dev/null 2>&1
    chroot "$ROOTFS" env -i xbps-reconfigure -f base-files-cereus

    # Enable choosen UTF-8 locale and generate it into the target rootfs.
    if [ -f "$ROOTFS"/etc/default/libc-locales ]; then
        sed -e "s/\#\(${LOCALE}.*\)/\1/g" -i "$ROOTFS"/etc/default/libc-locales
    fi

    if [ -f "$ROOTFS"/etc/calamares/modules/locale.conf ]; then
        case "$TARGET_ARCH" in
        x86_64|i686)
            LOCALES_FILE="libc-locales" ;;
        x86_64-musl)
            LOCALES_FILE="musl-locales" ;;
        esac
        sed -i "s/@@LOCALES_FILE@@/${LOCALES_FILE}/" "$ROOTFS"/etc/calamares/modules/locale.conf
    fi

    if XBPS_ARCH=$BASE_ARCH "$XBPS_QUERY_CMD" -r "$ROOTFS" dkms >/dev/null 2>&1; then
        # dkms modules alphabetically before dkms can't configure
        # if dkms hasn't configured beforehand to create /var/lib/dkms
        chroot "$ROOTFS" env -i xbps-reconfigure dkms
    fi

    chroot "$ROOTFS" env -i xbps-reconfigure -a

    if XBPS_ARCH=$BASE_ARCH "$XBPS_QUERY_CMD" -r "$ROOTFS" dash >/dev/null 2>&1; then
        # bash configures alphabetically before dash,
        # so if it's installed we should ensure it's /bin/sh
        chroot "$ROOTFS" env -i xbps-alternatives -s dash
    fi

    post_install_packages
}

ignore_packages() {
	mkdir -p "$ROOTFS"/etc/xbps.d
	for pkg in "${IGNORE_PKGS[@]}"; do
		echo "ignorepkg=$pkg" >> "$ROOTFS"/etc/xbps.d/mklive-ignore.conf
	done
}

enable_services() {
    SERVICE_LIST="$*"
    for service in $SERVICE_LIST; do
        if ! [ -e "$ROOTFS"/etc/sv/"$service" ]; then
            die "service $service not in /etc/sv"
        fi
        ln -sf /etc/sv/"$service" "$ROOTFS"/etc/runit/runsvdir/default/
    done
}

change_shell() {
    if ! chroot "$ROOTFS" chsh -s "$ROOT_SHELL" root; then
		die "Failed to change the shell for root"
	fi
}

copy_include_directories() {
    for includedir in "${INCLUDE_DIRS[@]}"; do
            info_msg "=> copying include directory '$includedir' ..."
	    find "$includedir" -mindepth 1 -maxdepth 1 -exec cp -rfpPv {} "$ROOTFS"/ \;

	    # Correct includedir permissions.
	    touch .includedir_list
	    find "$includedir" | sed 's|'"$includedir"'|'"$ROOTFS"'|g' | tee .includedir_list >/dev/null
        # Intentionally splitting
        # shellcheck disable=SC2046
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
        
    if ! chroot "$ROOTFS" env -i /usr/bin/dracut -N --"${INITRAMFS_COMPRESSION}" \
        --add-drivers "ahci" --force-add "vmklive autoinstaller" --omit systemd "/boot/initrd" "$KERNELVERSION"; then
			die "Failed to generate the initramfs"
	fi

    mv "$ROOTFS"/boot/initrd "$BOOT_DIR"
	case "$TARGET_ARCH" in
		i686*|x86_64*) cp "$ROOTFS/boot/vmlinuz-$KERNELVERSION" "$BOOT_DIR"/vmlinuz ;;
		aarch64*) cp "$ROOTFS/boot/vmlinux-$KERNELVERSION" "$BOOT_DIR"/vmlinux ;;
	esac
}

array_contains() {
    local -n arr="$1"
    local val="$2"
    printf '%s\0' "${arr[@]}" | grep -Fxqz "$val"
}

cleanup_rootfs() {
    for f in "${INITRAMFS_PKGS[@]}"; do
        # shellcheck disable=SC2086
        if ! array_contains PACKAGE_LIST $f; then
            revdeps=$(xbps-query -r "$ROOTFS" -X $f)
            if [ -n "$revdeps" ]; then
                xbps-pkgdb -r "$ROOTFS" -m auto $f
            else
                xbps-remove -r "$ROOTFS" -Ry ${f} >/dev/null 2>&1
            fi
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
    cp -f "${SPLASH_IMAGE}" "$ISOLINUX_DIR"

    sed -i  -e "s|@@SPLASHIMAGE@@|$(basename "${SPLASH_IMAGE}")|" \
        -e "s|@@KERNVER@@|${KERNELVERSION}|" \
        -e "s|@@KEYMAP@@|${KEYMAP}|" \
        -e "s|@@ARCH@@|$TARGET_ARCH|" \
        -e "s|@@LOCALE@@|${LOCALE}|" \
        -e "s|@@BOOT_TITLE@@|${BOOT_TITLE}|" \
        -e "s|@@BOOT_CMDLINE@@|${BOOT_CMDLINE}|" \
        "$ISOLINUX_DIR"/isolinux.cfg

    # include memtest86+
    if [ -e "$CEREUSTARGETDIR"/boot/memtest86+/memtest.bin ]; then
        cp "$CEREUSTARGETDIR"/boot/memtest86+/memtest.bin "$BOOT_DIR"
    fi
}

generate_grub_efi_boot() {
    cp -f grub/grub.cfg "$GRUB_DIR"
    cp -f "${SPLASH_IMAGE}" "$ISOLINUX_DIR"
    cp -f grub/grub_cereus.cfg.pre "$GRUB_DIR"/grub_cereus.cfg

    case "$TARGET_ARCH" in
        i686*|x86_64*) KERNEL_IMG=vmlinuz; WANT_MEMTEST=yes ;;
        aarch64*) KERNEL_IMG=vmlinux; WANT_MEMTEST=no ;;
    esac

    write_entry() {
        local entrytitle="$1" id="$2" cmdline="$3" dtb="$4" hotkey="$5"
        cat << EOF >> "$GRUB_DIR"/grub_cereus.cfg
menuentry "${entrytitle}" --id "${id}" ${hotkey:+--hotkey $hotkey} {
    set gfxpayload="keep"
    linux (\${cereuslive})/boot/${KERNEL_IMG} \\
        root=live:CDLABEL=CEREUS_LIVE ro init=/sbin/init \\
        rd.luks=0 rd.md=0 rd.dm=0 loglevel=4 gpt add_efi_memmap \\
        vconsole.unicode=1 vconsole.keymap=${KEYMAP} locale.LANG=${LOCALE} ${cmdline}
    initrd (\${cereuslive})/boot/initrd
EOF
        if [ -n "${dtb}" ]; then
            # shellcheck disable=SC2016
            printf '    devicetree (${cereuslive})/boot/dtbs/%s\n' "${dtb}" >> "$GRUB_DIR"/grub_cereus.cfg
        fi
        printf '}\n' >> "$GRUB_DIR"/grub_cereus.cfg
    }

    write_entries() {
        local title_sfx="$1" id_sfx="$2" cmdline="$3" dtb="$4"

        ENTRY_TITLE="${BOOT_TITLE} ${KERNELVERSION} ${title_sfx}(${TARGET_ARCH})"

        write_entry "${ENTRY_TITLE}" "linux${id_sfx}" \
            "$BOOT_CMDLINE $cmdline" "$dtb"
        write_entry "${ENTRY_TITLE} (RAM)" "linuxram${id_sfx}" \
            "rd.live.ram $BOOT_CMDLINE $cmdline" "$dtb"
        write_entry "${ENTRY_TITLE} (graphics disabled)" "linuxnogfx${id_sfx}" \
            "nomodeset $BOOT_CMDLINE $cmdline" "$dtb"
        write_entry "${ENTRY_TITLE} with speech" "linuxa11y${id_sfx}" \
            "live.accessibility live.autologin $BOOT_CMDLINE $cmdline" "$dtb" 's'
        write_entry "${ENTRY_TITLE} with speech (RAM)" "linuxa11yram${id_sfx}" \
            "live.accessibility live.autologin rd.live.ram $BOOT_CMDLINE $cmdline" "$dtb" 'r'
        write_entry "${ENTRY_TITLE} with speech (graphics disabled)" "linuxa11ynogfx${id_sfx}" \
            "live.accessibility live.autologin nomodeset $BOOT_CMDLINE $cmdline" "$dtb" 'g'

    }

    write_entries

    for platform in "${PLATFORMS[@]}"; do
        (
            # shellcheck source=platforms/x13s.sh
            # shellcheck source=platforms/pinebookpro.sh
            . "platforms/${platform}.sh"

            if [ -n "$PLATFORM_DTB" ]; then
                mkdir -p "${BOOT_DIR}/dtbs/${PLATFORM_DTB%/*}"
                cp "${ROOTFS}/boot/dtbs/dtbs-${KERNVER}"*/"${PLATFORM_DTB}" "${BOOT_DIR}/dtbs/${PLATFORM_DTB}"
            fi

            printf 'submenu "%s" --id platform-%s {\n' \
                "${BOOT_TITLE} for ${PLATFORM_NAME:-$platform} >" "${platform}" >> "$GRUB_DIR"/grub_cereus.cfg
            write_entries "for ${PLATFORM_NAME:-$platform} " "-$platform" "$PLATFORM_CMDLINE" "${PLATFORM_DTB}"
            printf '}\n' >> "$GRUB_DIR"/grub_cereus.cfg
        )
    done

    if [ "$WANT_MEMTEST" = yes ]; then
        cat << 'EOF' >> "$GRUB_DIR"/grub_cereus.cfg
    if [ "${grub_platform}" == "efi" ]; then
        menuentry "Run Memtest86+ (RAM test)" --id memtest {
            set gfxpayload="keep"
            linux (${cereuslive})/boot/memtest.efi
        }
    else
        menuentry "Run Memtest86+ (RAM test)" --id memtest {
            set gfxpayload="keep"
            linux (${cereuslive})/boot/memtest.bin
        }
    fi
EOF
    fi

    cat << 'EOF' >> "$GRUB_DIR"/grub_cereus.cfg
if [ "${grub_platform}" == "efi" ]; then
    menuentry 'UEFI Firmware Settings' --hotkey f --id uefifw {
        fwsetup
    }
fi

menuentry "System restart" --hotkey b --id restart {
    echo "System rebooting..."
    reboot
}

menuentry "System shutdown" --hotkey p --id poweroff {
    echo "System shutting down..."
    halt
}
EOF
    cat grub/grub_cereus.cfg.post >> "$GRUB_DIR"/grub_cereus.cfg

    sed -i -e "s|@@SPLASHIMAGE@@|$(basename "${SPLASH_IMAGE}")|" "$GRUB_DIR"/grub_cereus.cfg

    mkdir -p "$GRUB_DIR"/fonts

    cp -f "$GRUB_DATADIR"/unicode.pf2 "$GRUB_DIR"/fonts

    modprobe -q loop || :

    # Create EFI vfat image.
    truncate -s 32M "$GRUB_DIR"/efiboot.img >/dev/null 2>&1
    mkfs.vfat -F12 -S 512 -n "grub_uefi" "$GRUB_DIR/efiboot.img" >/dev/null 2>&1

    GRUB_EFI_TMPDIR="$(mktemp --tmpdir="$BUILDDIR" -dt grub-efi.XXXXX)"
    LOOP_DEVICE="$(losetup --show --find "${GRUB_DIR}"/efiboot.img)"
    mount -o rw,flush -t vfat "${LOOP_DEVICE}" "${GRUB_EFI_TMPDIR}" >/dev/null 2>&1

	build_grub_image() {
		local GRUB_ARCH="$1" EFI_ARCH="$2"
		if ! xbps-uchroot "$CEREUSTARGETDIR" grub-mkstandalone -- \
			 --directory="/usr/lib/grub/${GRUB_ARCH}-efi" \
			 --format="${GRUB_ARCH}-efi" \
			 --output="/tmp/boot${EFI_ARCH,,}.efi" \
			 "boot/grub/grub.cfg"; then
                umount "$GRUB_EFI_TMPDIR"
                losetup --detach "${LOOP_DEVICE}"
                die "Failed to generate EFI loader"
		fi
		mkdir -p "${GRUB_EFI_TMPDIR}"/EFI/BOOT
		cp -f "$CEREUSTARGETDIR/tmp/boot${EFI_ARCH,,}.efi" "${GRUB_EFI_TMPDIR}/EFI/BOOT/BOOT${EFI_ARCH^^}.EFI"
	}

    cp -a "$IMAGEDIR"/boot "$CEREUSTARGETDIR"

    case "$TARGET_ARCH" in
		i686*|x86_64*)
			# XXX: why are both built on both arches?
			build_grub_image i386 ia32
			build_grub_image x86_64 x64
			# include memtest86+
			if [ -e "$CEREUSTARGETDIR"/boot/memtest86+/memtest.efi ]; then
				cp "$CEREUSTARGETDIR"/boot/memtest86+/memtest.efi "$BOOT_DIR"
			fi
			;;
		aarch64*)
			build_grub_image arm64 aa64
            ;;
    esac
    umount "$GRUB_EFI_TMPDIR"
    losetup --detach "${LOOP_DEVICE}"
    rm -rf "$GRUB_EFI_TMPDIR"
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
    local bootloader n
    XORRISO_ARGS=(
        -iso-level 3 -rock -joliet -joliet-long -max-iso9660-filenames -omit-period
        -omit-version-number -relaxed-filenames -allow-lowercase
        -volid CEREUS_LIVE
    )

    if [ "$IMAGE_TYPE" = hybrid ]; then
        XORRISO_ARGS+=(-isohybrid-mbr "$SYSLINUX_DATADIR"/isohdpfx.bin)
    fi

    n=1
    for bootloader in "${BOOTLOADERS[@]}"; do
        if (( n > 1 )); then
            XORRISO_ARGS+=(-eltorito-alt-boot)
        fi

        case "${bootloader}" in
            grub)
                XORRISO_ARGS+=(
                    -e boot/grub/efiboot.img -no-emul-boot
                    -isohybrid-gpt-basdat -isohybrid-apm-hfsplus
                )
                ;;
            syslinux)
                XORRISO_ARGS+=(
                    -eltorito-boot boot/isolinux/isolinux.bin
                    -eltorito-catalog boot/isolinux/boot.cat
                    -no-emul-boot -boot-load-size 4 -boot-info-table
                )
                ;;
        esac

        n=$(( n + 1 ))
    done

    XORRISO_ARGS+=(
        -output "$OUTPUT_FILE" "$IMAGEDIR"
    )

    "$CEREUSHOSTDIR"/usr/bin/xorriso -as mkisofs "${XORRISO_ARGS[@]}" || die "Failed to generate ISO image"
}

#
# main()
#
while getopts "a:b:r:c:C:T:Kk:l:i:I:S:e:s:o:p:g:v:P:Vh" opt; do
	# shellcheck disable=SC2206
	case $opt in
		a) TARGET_ARCH="$OPTARG";;
		b) BASE_SYSTEM_PKG="$OPTARG";;
		r) TARGET_REPOSITORIES+=(--repository=$OPTARG);;
		c) XBPS_CACHEDIR="$OPTARG";;
		g) IGNORE_PKGS+=($OPTARG) ;;
		K) readonly KEEP_BUILDDIR=1;;
		k) KEYMAP="$OPTARG";;
		l) LOCALE="$OPTARG";;
		i) INITRAMFS_COMPRESSION="$OPTARG";;
		I) INCLUDE_DIRS+=("$OPTARG");;
		S) SERVICE_LIST="$SERVICE_LIST $OPTARG";;
		e) ROOT_SHELL="$OPTARG";;
		s) SQUASHFS_COMPRESSION="$OPTARG";;
		o) OUTPUT_FILE="$OPTARG";;
		p) PACKAGE_LIST+=($OPTARG);;
		P) PLATFORMS+=($OPTARG) ;;
		C) BOOT_CMDLINE="$OPTARG";;
		T) BOOT_TITLE="$OPTARG";;
		v) LINUX_VERSION="$OPTARG";;
		V) version; exit 0;;
		h) usage; exit 0;;
		*) usage >&2; exit 1;;
	esac
done
shift $((OPTIND - 1))
 
# Configure dracut to use overlayfs for the writable overlay.
BOOT_CMDLINE="$BOOT_CMDLINE rd.live.overlay.overlayfs=1 "

HOST_ARCH=$(xbps-uhelper arch)

# Set defaults
: "${TARGET_ARCH:=$(xbps-uhelper arch 2>/dev/null || uname -m)}"
: "${XBPS_CACHEDIR:="$(pwd -P)"/xbps-cachedir-${TARGET_ARCH}}"
: "${XBPS_HOST_CACHEDIR:="$(pwd -P)"/xbps-cachedir-${HOST_ARCH}}"
: "${KEYMAP:=us}"
: "${LOCALE:=en_US.UTF-8}"
: "${INITRAMFS_COMPRESSION:=xz}"
: "${SQUASHFS_COMPRESSION:=xz}"
: "${BASE_SYSTEM_PKG:=base-cereus}"
: "${BOOT_TITLE:="Cereus Linux"}"
: "${LINUX_VERSION:=linux-default-cereus}"

XBPS_TARGET_ARCH="$TARGET_ARCH" register_binfmt

# Set repositories for mklive
set_repos

case "$TARGET_ARCH" in
	x86_64*|i686*)
		BOOTLOADERS=(syslinux grub)
		IMAGE_TYPE='hybrid'
		TARGET_PKGS+=(syslinux grub-i386-efi grub-x86_64-efi memtest86+)
        PLATFORMS=() # arm only
		;;
	aarch64*)
		BOOTLOADERS=(grub)
		IMAGE_TYPE='efi'
		TARGET_PKGS+=(grub-arm64-efi)
        # shellcheck source=platforms/x13s.sh
        # shellcheck source=platforms/pinebookpro.sh
        for platform in "${PLATFORMS[@]}"; do
            if [ -r "platforms/${platform}.sh" ]; then
                . "platforms/${platform}.sh"
            else
                die "unknown platform: ${platform}"
            fi
            PACKAGE_LIST+=("${PLATFORM_PKGS[@]}")
            unset PLATFORM_PKGS PLATFORM_CMDLINE PLATFORM_DTB
        done

		;;
    *) >&2 echo "architecture $TARGET_ARCH not supported by mklive.sh"; exit 1;;
esac

# Required packages in the image for a working system.
PACKAGE_LIST+=("$BASE_SYSTEM_PKG")

# Check for root permissions.
if [ "$(id -u)" -ne 0 ]; then
    die "Must be run as root, exiting..."
fi

trap 'error_out $? $LINENO' INT TERM 0

if [ -n "$ROOTDIR" ]; then
    BUILDDIR=$(mktemp --tmpdir="$ROOTDIR" -dt mklive-build.XXXXX)
else
    BUILDDIR=$(mktemp --tmpdir="$(pwd -P)" -dt mklive-build.XXXXX)
fi
BUILDDIR=$(readlink -f "$BUILDDIR")
IMAGEDIR="$BUILDDIR/image"
ROOTFS="$IMAGEDIR/rootfs"
CEREUSHOSTDIR="$BUILDDIR/cereus-host"
CEREUSTARGETDIR="$BUILDDIR/cereus-target"
BOOT_DIR="$IMAGEDIR/boot"
ISOLINUX_DIR="$BOOT_DIR/isolinux"
GRUB_DIR="$BOOT_DIR/grub"
CURRENT_STEP=0
STEP_COUNT=10
[ "${IMAGE_TYPE}" = hybrid ] && STEP_COUNT=$((STEP_COUNT+1))
[ "${#INCLUDE_DIRS[@]}" -gt 0 ] && STEP_COUNT=$((STEP_COUNT+1))
[ "${#IGNORE_PKGS[@]}" -gt 0 ] && STEP_COUNT=$((STEP_COUNT+1))
[ -n "$ROOT_SHELL" ] && STEP_COUNT=$((STEP_COUNT+1))

: "${SYSLINUX_DATADIR:="$CEREUSTARGETDIR"/usr/lib/syslinux}"
: "${GRUB_DATADIR:="$CEREUSTARGETDIR"/usr/share/grub}"
: "${SPLASH_IMAGE:=data/splash.png}"
: "${XBPS_INSTALL_CMD:=xbps-install}"
: "${XBPS_REMOVE_CMD:=xbps-remove}"
: "${XBPS_QUERY_CMD:=xbps-query}"
: "${XBPS_RINDEX_CMD:=xbps-rindex}"
: "${XBPS_UHELPER_CMD:=xbps-uhelper}"
: "${XBPS_RECONFIGURE_CMD:=xbps-reconfigure}"

mkdir -p "$ROOTFS" "$CEREUSHOSTDIR" "$CEREUSTARGETDIR" "$GRUB_DIR" "$ISOLINUX_DIR"

print_step "Synchronizing XBPS repository data..."
copy_xbps_keys "$ROOTFS"
# shellcheck disable=SC2048
# shellcheck disable=SC2086
XBPS_ARCH=$TARGET_ARCH $XBPS_INSTALL_CMD -r "$ROOTFS" ${TARGET_REPOSITORIES[*]} -S
copy_xbps_keys "$CEREUSHOSTDIR"
# shellcheck disable=SC2048
# shellcheck disable=SC2086
XBPS_ARCH=$HOST_ARCH $XBPS_INSTALL_CMD -r "$CEREUSHOSTDIR" ${HOST_REPOSITORIES[*]} -S
copy_xbps_keys "$CEREUSTARGETDIR"
# shellcheck disable=SC2086
# shellcheck disable=SC2048
XBPS_ARCH=$TARGET_ARCH $XBPS_INSTALL_CMD -r "$CEREUSTARGETDIR" ${TARGET_REPOSITORIES[*]} -S

# Get the default kernel metapackage for the target arch
case "$TARGET_ARCH" in
    i686) DEFAULT_KERNEL_METAPKG="linux-legacy-cereus";;
    x86_64*) DEFAULT_KERNEL_METAPKG="linux-default-cereus";;
esac

# Get linux version for ISO
# If linux version option specified use
shopt -s extglob
case "$LINUX_VERSION" in
    linux+([0-9.]))
        IGNORE_PKGS+=("$DEFAULT_KERNEL_METAPKG")
        PACKAGE_LIST+=("$LINUX_VERSION" linux-base)
    ;;
    linux-@(default|legacy|mainline)-cereus)
        if [ "$LINUX_VERSION" != "$DEFAULT_KERNEL_METAPKG" ]; then
            IGNORE_PKGS+=("$DEFAULT_KERNEL_METAPKG")
        fi
        PACKAGE_LIST+=("$LINUX_VERSION")
        # shellcheck disable=SC2030
        # shellcheck disable=SC2086
        # shellcheck disable=SC2048
        LINUX_VERSION="$(XBPS_ARCH=$TARGET_ARCH $XBPS_QUERY_CMD -r "$ROOTFS" ${TARGET_REPOSITORIES[*]:=-R} -x "$LINUX_VERSION" | grep 'linux[0-9._]\+')"
	;;
    linux-@(mainline|lts))
        IGNORE_PKGS+=("$DEFAULT_KERNEL_METAPKG")
        PACKAGE_LIST+=("$LINUX_VERSION")
        # shellcheck disable=SC2030
        # shellcheck disable=SC2031
        # shellcheck disable=SC2086
        # shellcheck disable=SC2048
        LINUX_VERSION="$(XBPS_ARCH=$TARGET_ARCH $XBPS_QUERY_CMD -r "$ROOTFS" ${TARGET_REPOSITORIES[*]:=-R} -x "$LINUX_VERSION" | grep 'linux[0-9._]\+')"
        ;;
    linux-asahi)
        IGNORE_PKGS+=(linux)
        PACKAGE_LIST+=(linux-asahi linux-base)
        ;;
    linux)
        IGNORE_PKGS+=("$DEFAULT_KERNEL_METAPKG")
        # shellcheck disable=SC2030
        # shellcheck disable=SC2031
        # shellcheck disable=SC2086
        # shellcheck disable=SC2048
        LINUX_VERSION="$(XBPS_ARCH=$TARGET_ARCH $XBPS_QUERY_CMD -r "$ROOTFS" ${TARGET_REPOSITORIES[*]:=-R} -x linux | grep 'linux[0-9._]\+')"
        ;;
    *)
        die "-v option must be in format linux<version> or linux-<series>"
        ;;
esac
shopt -u extglob

# shellcheck disable=SC2030
# shellcheck disable=SC2031
# shellcheck disable=SC2086
# shellcheck disable=SC2048
_kver="$(XBPS_ARCH=$TARGET_ARCH $XBPS_QUERY_CMD -r "$ROOTFS" ${TARGET_REPOSITORIES[*]:=-R} -p pkgver $LINUX_VERSION)"
if ! KERNELVERSION=$($XBPS_UHELPER_CMD getpkgversion "${_kver}"); then
    die "Failed to find kernel package version"
fi

if [ "$LINUX_VERSION" = linux-asahi ]; then
    KERNELVERSION="${KERNELVERSION%%_*}-asahi_${KERNELVERSION##*_}"
fi

: "${OUTPUT_FILE="cereus-beta-live-${TARGET_ARCH}-${KERNELVERSION}-$(date -u +%Y.%m.%d).iso"}"

print_step "Installing software to generate the image: ${REQUIRED_PKGS[*]} ..."
install_prereqs "${REQUIRED_PKGS[@]}"

print_step "Installing software to generate the image: ${TARGET_PKGS[*]} ..."
install_target_pkgs "${TARGET_PKGS[@]}"

mkdir -p "$ROOTFS"/etc
[ -s data/motd ] && cp data/motd "$ROOTFS"/etc
[ -s data/issue ] && cp data/issue "$ROOTFS"/etc

if [ "${#IGNORE_PKGS[@]}" -gt 0 ]; then
	print_step "Ignoring packages in the rootfs: ${IGNORE_PKGS[*]} ..."
	ignore_packages
fi

print_step "Installing cereus pkgs into the rootfs: ${PACKAGE_LIST[*]} ..."
install_packages

: "${DEFAULT_SERVICE_LIST:=agetty-tty1 agetty-tty2 agetty-tty3 agetty-tty4 agetty-tty5 agetty-tty6 udevd}"
print_step "Enabling services: ${SERVICE_LIST} ..."
# shellcheck disable=SC2086
enable_services ${DEFAULT_SERVICE_LIST} ${SERVICE_LIST}

if [ -n "$ROOT_SHELL" ]; then
    print_step "Changing the root shell ..."
    change_shell
fi

if [ "${#INCLUDE_DIRS[@]}" -gt 0 ];then
    print_step "Copying directory structures into the rootfs ..."
    copy_include_directories
fi

print_step "Generating initramfs image ($INITRAMFS_COMPRESSION)..."
generate_initramfs

if [ "$IMAGE_TYPE" = hybrid ]; then
    print_step "Generating isolinux support for PC-BIOS systems..."
    generate_isolinux_boot
fi

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
