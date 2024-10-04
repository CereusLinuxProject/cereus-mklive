#!/bin/sh

set -eu

. ./lib.sh

PROGNAME=$(basename "$0")
ARCH=$(uname -m)
IMAGES="base xfce lxqt cinnamon plasma fluxbox i3wm lxde"
TRIPLET=
REPO=
ARCH_PKGS=
REPO_NONFREE=
REPO_MULTILIB=
REPO_MULTILIB_NONFREE=
SU_PKG=sudo
DATE=$(date +%Y.%m.%d)

usage() {
	cat <<-EOH
	Usage: $PROGNAME [options ...] [-- mklive options ...]

	Wrapper script around mklive.sh for several standard flavors of live images.
	Adds cereus-installer and other helpful utilities to the generated images.

	OPTIONS
	 -a <arch>     Set XBPS_ARCH in the image
	 -b <variant>  One of base, xfce, lxqt cinnamon, plasma, fluxbox i3wm, or lxqt
	               (default: base). May be specified multiple times to build multiple variants
	 -d <date>     Override the datestamp on the generated image (YYYY.MM.DD format)
	 -t <arch-date-variant>
	               Equivalent to setting -a, -b, and -d
	 -r <repo>     Use this XBPS repository. May be specified multiple times
	 -h            Show this help and exit
	 -s	       Set the privilege scalation package, one of sudo or doas (default: sudo).
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
    r) REPO="-r $OPTARG $REPO";;
    t) TRIPLET="$OPTARG";;
    s) SU_PKG="$OPTARG";;
    V) version; exit 0;;
    h) usage; exit 0;;
    *) usage >&2; exit 1;;
esac
done
shift $((OPTIND - 1))

case $SU_PKG in
    sudo) SU_PKG="sudo";;
    doas) SU_PKG="opendoas";;
    *) echo "SU_PKG: Invalid option $SU_PKG"; exit 1;;
esac

INCLUDEDIR=$(mktemp -d)
trap "cleanup" INT TERM

cleanup() {
    rm -rf "$INCLUDEDIR"
}

setup_pipewire() {
    PKGS="$PKGS pipewire alsa-pipewire"
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
    CEREUS_INCLUDEDIR="$PWD/includedir"
    IMG=cereus-beta-live-${ARCH}-${variant}-${DATE}.iso
    GRUB_PKGS="grub-cereus-i386-efi grub-cereus-x86_64-efi"
    A11Y_PKGS="espeakup void-live-audio brltty"
    ARCH_PKGS=""
    PKGS="dialog cryptsetup lvm2 mdadm void-docs-browse nano rsync zstd cereus-repo-core cereus-repo-extra chrony xtools-minimal $A11Y_PKGS $SU_PKG $GRUB_PKGS"
    XORG_PKGS="xorg-minimal xorg-input-drivers xorg-video-drivers-cereus setxkbmap xauth font-misc-misc terminus-font dejavu-fonts-ttf orca"
    SERVICES="sshd chronyd"

# Declare base repositories url
    #VOID_REPO="https://repo-default.voidlinux.org/current"
    VOID_REPO="https://mirrors.servercentral.com/voidlinux/current"
    CEREUS_REPO="https://sourceforge.net/projects/cereus-linux/files/repos"
    REPO_EXTRA="${CEREUS_REPO}/cereus-extra/${ARCH}"
    REPO_CORE="${CEREUS_REPO}/cereus-core/${ARCH}"

# Default common themes among all editions
    THEMES_PKGS="Graphite-kvantum-theme-black Graphite-gtk-theme-black Tela-icon-theme-green Graphite-color-schemes-black Graphite-cursors"

# Default common base packages among all editions, except the base one.
    CEREUS_BASEPKGS="$ARCH_PKGS calamares-cereus simple-scan fastfetch htop nano void-repo-nonfree accountsservice gparted hplip-gui htop mpv mypaint xtools broadcom-wl-dkms hardinfo timeshift psmisc breeze ntfs-3g touchegg-gce xz unrar unzip zip otter-browser qt5ct cups cups-browsed"

    # Add kernel headers in order to DKMS work properly
    if [ "${ARCH}" = "i686" ]; then
        CEREUS_BASEPKGS="${CEREUS_BASEPKGS} linux-legacy-cereus-headers"
    else
        CEREUS_BASEPKGS="${CEREUS_BASEPKGS} linux-default-cereus-headers"
    fi

# Change locale.conf for calamares depending on target libc and set specific arch pkgs
case ${ARCH} in
    x86_64)
        ARCH_PKGS="void-repo-multilib"
        REPO_NONFREE="${VOID_REPO}/nonfree"
        REPO_MULTILIB="${VOID_REPO}/multilib"
        REPO_MULTILIB_NONFREE="${VOID_REPO}/multilib/nonfree"
        sed -i 's/musl/libc/g' ${CEREUS_INCLUDEDIR}/*/etc/calamares/modules/locale.conf;;
    *-musl)
        REPO_NONFREE="${VOID_REPO}/musl/nonfree"
        sed -i 's/libc/musl/g' ${CEREUS_INCLUDEDIR}/*/etc/calamares/modules/locale.conf;;
    i686)
        REPO_NONFREE="${VOID_REPO}/nonfree"
        sed -i 's/musl/libc/g' ${CEREUS_INCLUDEDIR}/*/etc/calamares/modules/locale.conf;;
esac
    LIGHTDM_SESSION=''

    case $variant in
        base) 
            SERVICES="$SERVICES dhcpcd wpa_supplicant acpid"
	;;
        xfce)
            PKGS="$PKGS $XORG_PKGS $THEMES_PKGS $ARCH_PKGS $CEREUS_BASEPKGS cereus-xfce-presets lightdm lightdm-gtk3-greeter-cereus lightdm-gtk-greeter-settings-cereus cereus-lightdm-presets evince xarchiver blueman rhythmbox galculator-gtk3 blesh-git"
            SERVICES="$SERVICES acpid dbus elogind lightdm bluetoothd NetworkManager polkitd cupsd cups-browsed touchegg"
            LIGHTDM_SESSION=xfce
        ;;
        cinnamon)
            PKGS="$PKGS $XORG_PKGS $THEMES_PKGS $ARCH_PKGS $CEREUS_BASEPKGS lightdm lightdm-gtk3-greeter-cereus lightdm-gtk-greeter-settings-cereus cinnamon gnome-keyring colord tilix gvfs-afc gvfs-mtp gvfs-smb udisks2 blueman eog gnome-screenshot qt5ct rhythmbox xed-xapps xdg-user-dirs evince galculator-gtk3 nemo{,-emblems,-extensions,-fileroller,-image-converter,-preview,-python,-terminal,compare,audio-tab} clipit xviewer"
            SERVICES="$SERVICES acpid dbus elogind lightdm bluetoothd NetworkManager polkitd cupsd cups-browsed touchegg"
            LIGHTDM_SESSION=cinnamon
        ;;
        plasma)
            PKGS="$PKGS $XORG_PKGS $THEMES_PKGS $ARCH_PKGS $CEREUS_BASEPKGS kde5 konsole dolphin sddm print-manager ark strawberry kate5 kcalc udisks2 okular spectacle"
            SERVICES="$SERVICES acpid dbus elogind bluetoothd NetworkManager polkitd cupsd cups-browsed touchegg sddm"
        ;;
        lxqt)
            PKGS="$PKGS $XORG_PKGS $THEMES_PKGS $ARCH_PKGS $CEREUS_BASEPKGS cereus-lxqt-presets lightdm lightdm-gtk3-greeter-cereus lightdm-gtk-greeter-settings-cereus cereus-lightdm-presets qlipper strawberry galculator-gtk3 qpdfview FeatherPad blesh"
            SERVICES="$SERVICES acpid dbus elogind bluetoothd NetworkManager polkitd cupsd cups-browsed touchegg lightdm"
            LIGHTDM_SESSION=lxqt
        ;;
        # UNOFFICIAL EDITIONS
        fluxbox)
            PKGS="$PKGS $XORG_PKGS $THEMES_PKGS $ARCH_PKGS $CEREUS_BASEPKGS fluxbox tint2 lightdm-gtk3-greeter-cereus lightdm-gtk-greeter-settings-cereus pasystray rofi udevil xfce4-notifyd xfce4-pulseaudio-plugin ksuperkey xed-xapps audacious rxvt-unicode lxappearance qt5ct playerctl nitrogen blueman betterlockscreen clipit lxqt-policykit ksuperkey flameshot brillo skippy-xd pavucontrol nemo nemo-emblems nemo-fileroller nemo-image-converter nemo-preview nemo-python nemo-compare nemo-audio-tab galculator-gtk3 fbmenugen sierra-dark-fluxbox-theme arandr xidlehook picom picom-manager"
            SERVICES="$SERVICES acpid dbus bluetoothd NetworkManager polkitd cupsd cups-browsed touchegg"
            ;;
        # Still incomplete
        i3wm)
            PKGS="$PKGS $XORG_PKGS $THEMES_PKGS $ARCH_PKGS $CEREUS_BASEPKGS lightdm-gtk3-greeter-cereus lightdm-gtk-greeter-settings-cereus i3-gaps"
            SERVICES="$SERVICES acpid dbus bluetoothd NetworkManager polkitd cupsd cups-browsed touchegg emptty"
            ;;
        lxde)
            PKGS="$PKGS $XORG_PKGS $THEMES_PKGS $ARCH_PKGS $CEREUS_BASEPKGS lxde lightdm-gtk3-greeter-cereus lightdm-gtk-greeter-settings-cereus gvfs-afc gvfs-mtp gvfs-smb udisks2"
            SERVICES="$SERVICES acpid dbus bluetoothd NetworkManager polkitd cupsd cups-browsed touchegg emptty"
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

    if [ "$variant" != base ]; then
        setup_pipewire
    fi

    DEFAULT_REPOS="-r "${REPO_CORE}" -r "${REPO_EXTRA}" -r "${REPO_NONFREE}" -r "${REPO_MULTILIB}" -r "${REPO_MULTILIB_NONFREE}""
    echo "${DEFAULT_REPOS}"
    ./mklive.sh -a "$ARCH" -o "$IMG" -p "$PKGS" -S "$SERVICES" -I "$INCLUDEDIR" -I "$CEREUS_INCLUDEDIR/${variant}" ${DEFAULT_REPOS} ${REPO} "$@"

	cleanup
}

if [ ! -x mklive.sh ]; then
    echo mklive.sh not found >&2
    exit 1
fi

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

if [ -n "$TRIPLET" ]; then
    VARIANT="${TRIPLET##*-}"
    REST="${TRIPLET%-*}"
    DATE="${REST##*-}"
    ARCH="${REST%-*}"
    build_variant "$VARIANT" "$@"
else
    for image in $IMAGES; do
        build_variant "$image" "$@"
    done
fi
