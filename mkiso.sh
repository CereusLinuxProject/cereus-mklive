#!/bin/bash

set -eu

. ./lib.sh

PROGNAME=$(basename "$0")
ARCH=$(uname -m)
IMAGES="base xfce lxqt cinnamon plasma fluxbox i3wm lxde"
TRIPLET=
SU_PKG=sudo
DATE=$(date -u +%Y.%m.%d)

usage() {
	cat <<-EOH
	Usage: $PROGNAME [options ...] [-- mklive options ...]

	Wrapper script around mklive.sh for several standard flavors of live images.
	Adds cereus-installer and other helpful utilities to the generated images.

	OPTIONS
	 -a <arch>     Set architecture (or platform) in the image
	 -b <variant>  One of base, lxqt, xfce, cinnamon, plasma, fluxbox, or i3wm
	               (default: base). May be specified multiple times to build multiple variants
	 -d <date>     Override the datestamp on the generated image (YYYY.MM.DD format)
	 -t <arch-date-variant>
	               Equivalent to setting -a, -b, and -d
	 -r <repo>     Use this XBPS repository. May be specified multiple times
	 -h            Show this help and exit
	 -s            Set the privilege scalation package, one of sudo or doas (default: sudo).
	 -V            Show version and exit

	Other options can be passed directly to mklive.sh by specifying them after the --.
	See mklive.sh -h for more details.
	EOH
}

while getopts "a:b:d:t:hr:s:V" opt; do
case $opt in
    a) ARCH="$OPTARG";;
    b) IMAGES="$OPTARG";;
    d) DATE="$OPTARG";;
    r) ADDITIONAL_REPO+=("-r $OPTARG");;
    t) TRIPLET="$OPTARG";;
    s) SU_PKG="$OPTARG";;
    V) version; exit 0;;
    h) usage; exit 0;;
    *) usage >&2; exit 1;;
esac
done
shift $((OPTIND - 1))

case "$SU_PKG" in
    sudo) SU_PKG="sudo";;
    doas) SU_PKG="opendoas";;
    *) echo "SU_PKG: Invalid option $SU_PKG"; exit 1;;
esac

INCLUDEDIR=$(mktemp -d)
trap "cleanup" INT TERM

cleanup() {
    rm -rf "$INCLUDEDIR"
}

include_installer() {
    if [ -x installer.sh ]; then
        MKLIVE_VERSION="$(PROGNAME='' version)"
        installer=$(mktemp)
        sed "s/@@MKLIVE_VERSION@@/${MKLIVE_VERSION}/" installer.sh > "$installer"
        install -Dm755 "$installer" "$INCLUDEDIR"/usr/bin/cereus-installer
        rm "$installer"
    else
        echo installer.sh not found >&2
        exit 1
    fi
}

setup_pipewire() {
    PKGS="$PKGS pipewire alsa-pipewire"
    case "$ARCH" in
        asahi*)
            PKGS="$PKGS asahi-audio"
            SERVICES="$SERVICES speakersafetyd"
            ;;
    esac
    mkdir -p "$INCLUDEDIR"/etc/xdg/autostart
    ln -sf /usr/share/applications/pipewire.desktop "$INCLUDEDIR"/etc/xdg/autostart/
    mkdir -p "$INCLUDEDIR"/etc/pipewire/pipewire.conf.d
    ln -sf /usr/share/examples/wireplumber/10-wireplumber.conf "$INCLUDEDIR"/etc/pipewire/pipewire.conf.d/
    ln -sf /usr/share/examples/pipewire/20-pipewire-pulse.conf "$INCLUDEDIR"/etc/pipewire/pipewire.conf.d/
    mkdir -p "$INCLUDEDIR"/etc/alsa/conf.d
    ln -sf /usr/share/alsa/alsa.conf.d/50-pipewire.conf "$INCLUDEDIR"/etc/alsa/conf.d
    ln -sf /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf "$INCLUDEDIR"/etc/alsa/conf.d
}

build_variant() {
    variant="$1"
    shift
    IMG=cereus-beta-live-${ARCH}-${variant}-${DATE}.iso

    CEREUS_INCLUDEDIR="$PWD/includedir"
    A11Y_PKGS=(espeakup void-live-audio brltty)
    PKGS+=(dialog cryptsetup lvm2 mdadm void-docs-browse nano rsync zstd cereus-repo-core cereus-repo-extra chrony tmux xtools-minimal "${A11Y_PKGS[*]}" "$SU_PKG")
    FONTS=(font-misc-misc terminus-font dejavu-fonts-ttf)
    # Not required for now, but leaving here just in case
    # shellcheck disable=SC2034
    WAYLAND_PKGS=("$GFX_WL_PKGS" "${FONTS[*]}" orca)
    XORG_PKGS=("${FONTS[*]}" xorg-minimal xorg-input-drivers xorg-video-drivers-cereus setxkbmap xauth orca)
    SERVICES=(sshd chronyd)

    # el-cheapo installer is unsupported on arm because arm doesn't install a kernel by default
    # and to work around that would add too much complexity to it
    # thus everyone should just do a chroot install anyways
    WANT_INSTALLER=no
    case "$ARCH" in
        x86_64*|i686*)
            PKGS+=(grub-i386-efi grub-x86_64-efi)
            XORG_PKGS+=(xorg-video-drivers xf86-video-intel)
            WAYLAND_PKGS+=(mesa-dri)
            WANT_INSTALLER=yes
            TARGET_ARCH="$ARCH"
            ;;
        aarch64*)
            PKGS+=(grub-arm64-efi)
            XORG_PKGS+=(xorg-video-drivers)
            WAYLAND_PKGS+=(mesa-dri)
            TARGET_ARCH="$ARCH"
            ;;
        asahi*)
            PKGS+=(asahi-base asahi-scripts grub-arm64-efi)
            XORG_PKGS+=(mesa-asahi-dri)
            WAYLAND_PKGS+=(mesa-asahi-dri)
            # Intentionally unused but preserved just in case
            # shellcheck disable=SC2034
            KERNEL_PKG="linux-asahi"
            # shellcheck disable=SC2034
            TARGET_ARCH="aarch64${ARCH#asahi}"
            if [ "$variant" = xfce ]; then
                # Not implemented yet
                info_msg "xfce is not supported on asahi, switching to xfce-wayland"
                variant="xfce-wayland"
            fi
            ;;
    esac

# Default common base packages among all editions, except the base one.
    CEREUS_BASEPKGS+=(calamares-cereus simple-scan fastfetch htop nano void-repo-nonfree accountsservice gparted htop mpv mypaint xtools broadcom-wl-dkms hardinfo timeshift psmisc ntfs-3g xz unrar unzip zip otter-browser cups cups-browsed)

    # Add kernel headers in order to DKMS work properly
    if [ "${ARCH}" = "i686" ]; then
        CEREUS_BASEPKGS+=(linux-legacy-cereus-headers)
    else
        CEREUS_BASEPKGS+=(linux-default-cereus-headers)
    fi

case ${ARCH} in
    x86_64)
        PKGS+=(void-repo-{multilib{,-nonfree},nonfree}) ;;
    *-musl)
        PKGS+=(void-repo-nonfree) ;;
    i686)
        PKGS+=(void-repo-nonfree) ;;
esac

    LIGHTDM_SESSION=''

    # Append them only if the variant is not base
    if [ "$variant" != base ]; then
        PKGS+=("${CEREUS_BASEPKGS[*]}" "${XORG_PKGS[*]}")
    fi

    case "$variant" in
        base)
            SERVICES+=(dhcpcd wpa_supplicant acpid)
	;;
        lxqt)
            PKGS+=(cereus-lxqt-presets lightdm lightdm-gtk-greeter-cereus lightdm-gtk-greeter-settings-cereus cereus-lightdm-presets qlipper strawberry galculator-gtk3 qpdfview FeatherPad)
            SERVICES=(acpid dbus elogind bluetoothd NetworkManager polkitd cupsd cups-browsed lightdm)
            LIGHTDM_SESSION=lxqt
        ;;
        xfce)
            PKGS+=(cereus-xfce-presets lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings cereus-lightdm-presets evince xarchiver blueman rhythmbox galculator-gtk3 qt5ct qt6ct)
            SERVICES=(acpid dbus elogind lightdm bluetoothd NetworkManager polkitd cupsd cups-browsed)
            LIGHTDM_SESSION=xfce
        ;;
        # WIP
        cinnamon)
            PKGS+=(lightdm lightdm-gtk-greeter-cereus lightdm-gtk-greeter-settings-cereus cinnamon gnome-keyring colord tilix gvfs-afc gvfs-mtp gvfs-smb udisks2 blueman eog gnome-screenshot qt5ct rhythmbox xed-xapps xdg-user-dirs evince galculator-gtk3 nemo clipit xviewer)
            SERVICES+=(acpid dbus elogind lightdm bluetoothd NetworkManager polkitd cupsd cups-browsed)
            LIGHTDM_SESSION=cinnamon
        ;;
        plasma)
            PKGS+=(kde5 konsole dolphin sddm print-manager ark strawberry kate5 kcalc udisks2 okular spectacle)
            SERVICES=(acpid dbus elogind bluetoothd NetworkManager polkitd cupsd cups-browsed sddm)
        ;;
        # UNOFFICIAL EDITIONS (INCOMPLETE)
        fluxbox)
            PKGS+=(fluxbox tint2 lightdm-gtk3-greeter-cereus lightdm-gtk-greeter-settings-cereus pasystray rofi udevil xfce4-notifyd xfce4-pulseaudio-plugin ksuperkey xed-xapps audacious rxvt-unicode lxappearance qt5ct playerctl nitrogen blueman betterlockscreen clipit lxqt-policykit ksuperkey flameshot brillo skippy-xd pavucontrol nemo nemo-emblems nemo-fileroller nemo-image-converter nemo-preview nemo-python nemo-compare nemo-audio-tab galculator-gtk3 fbmenugen sierra-dark-fluxbox-theme arandr xidlehook picom picom-manager)
            SERVICES+=(acpid dbus bluetoothd NetworkManager polkitd cupsd cups-browsed)
            ;;
        i3wm)
            PKGS+=(lightdm-gtk3-greeter-cereus lightdm-gtk-greeter-settings-cereus i3)
            SERVICES+=(acpid dbus bluetoothd NetworkManager polkitd cupsd cups-browsed emptty)
            ;;
        lxde)
            PKGS+=(lxde lightdm-gtk3-greeter-cereus lightdm-gtk-greeter-settings-cereus gvfs-afc gvfs-mtp gvfs-smb udisks)
            SERVICES=(acpid dbus bluetoothd NetworkManager polkitd cupsd cups-browsed emptty)
            ;;
        *)
            >&2 echo "Unknown variant $variant"
            exit 1
        ;;
    esac

  if [ -n "$LIGHTDM_SESSION" ]; then
        mkdir -p "$INCLUDEDIR"/etc/lightdm
        echo "$LIGHTDM_SESSION" > "$INCLUDEDIR"/etc/lightdm/.session
    fi


    if [ "$WANT_INSTALLER" = yes ]; then
        include_installer
    else
        mkdir -p "$INCLUDEDIR"/usr/bin
        printf "#!/bin/sh\necho 'cereus-installer is not supported on this live image'\n" > "$INCLUDEDIR"/usr/bin/cereus-installer
        chmod 755 "$INCLUDEDIR"/usr/bin/cereus-installer
    fi

    if [ "$variant" != base ]; then
        setup_pipewire
    fi

    # Intentionally unquotting repositories variables
    # shellcheck disable=SC2086
    ./mklive.sh -a "$TARGET_ARCH" -o "$IMG" -p "${PKGS[*]}" -S "${SERVICES[*]}" -I "$INCLUDEDIR" -I "$CEREUS_INCLUDEDIR/${variant}" "${ADDITIONAL_REPO[*]}" "$@"

	cleanup
}

if [ ! -x mklive.sh ]; then
    echo mklive.sh not found >&2
    exit 1
fi

if [ -n "$TRIPLET" ]; then
    IFS=: read -r ARCH DATE VARIANT _ < <( echo "$TRIPLET" | sed -Ee 's/^(.+)-([0-9rc]+)-(.+)$/\1:\2:\3/' )
    build_variant "$VARIANT" "$@"
else
    for image in $IMAGES; do
        build_variant "$image" "$@"
    done
fi
