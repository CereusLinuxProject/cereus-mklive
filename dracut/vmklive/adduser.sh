#!/bin/sh -x
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

echo cereus-live > ${NEWROOT}/etc/hostname

AUTOLOGIN=$(getarg live.autologin)
USERNAME=$(getarg live.user)
USERSHELL=$(getarg live.shell)

[ -z "$USERNAME" ] && USERNAME=cereus
[ -x $NEWROOT/bin/bash -a -z "$USERSHELL" ] && USERSHELL=/bin/bash
[ -z "$USERSHELL" ] && USERSHELL=/bin/sh

# Create /etc/default/live.conf to store USER.
echo "USERNAME=$USERNAME" >> ${NEWROOT}/etc/default/live.conf
chmod 644 ${NEWROOT}/etc/default/live.conf

if ! grep -q ${USERSHELL} ${NEWROOT}/etc/shells ; then
    echo ${USERSHELL} >> ${NEWROOT}/etc/shells
fi

# Create new user and remove password.
chroot ${NEWROOT} useradd -m -c $USERNAME -G audio,video,wheel -s $USERSHELL $USERNAME

# If emptty is installed create also nopasswdlogin group
if [ -f ${NEWROOT}/usr/bin/emptty ]; then
    chroot ${NEWROOT} groupadd nopasswdlogin
    chroot ${NEWROOT} usermod -aG nopasswdlogin $USERNAME
fi

chroot ${NEWROOT} passwd -d $USERNAME >/dev/null 2>&1

# Setup default root/user password (cereus).
chroot ${NEWROOT} sh -c 'echo "root:cereus" | chpasswd -c SHA512'
chroot ${NEWROOT} sh -c "echo "$USERNAME:cereus" | chpasswd -c SHA512"

# Enable sudo permission by default.
if [ -f ${NEWROOT}/etc/sudoers ]; then
    echo "${USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL" > "${NEWROOT}/etc/sudoers.d/99-cereus-live"
fi

# Enable doas permission by default.
if [ -f ${NEWROOT}/usr/bin/doas ]; then
    echo "permit nopass :wheel 
permit nopass :root" > "$NEWROOT/etc/doas.conf"
fi

if [ -d ${NEWROOT}/etc/polkit-1 ]; then
    # If polkit is installed allow users in the wheel group to run anything.
    cat > ${NEWROOT}/etc/polkit-1/rules.d/cereus-live.rules <<_EOF
polkit.addAdminRule(function(action, subject) {
    return ["unix-group:wheel"];
});

polkit.addRule(function(action, subject) {
    if (subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
_EOF
    chroot ${NEWROOT} chown polkitd:polkitd /etc/polkit-1/rules.d/cereus-live.rules
fi

if [ -n "$AUTOLOGIN" ]; then
        sed -i "s,GETTY_ARGS=\"--noclear\",GETTY_ARGS=\"--noclear -a $USERNAME\",g" ${NEWROOT}/etc/sv/agetty-tty1/conf
fi

# Override default XFCE wallpaper
XFCE_DEFAULT_WALLPAPER="${NEWROOT}/usr/share/backgrounds/xfce/xfce-shapes.svg"
if [ -e $XFCE_DEFAULT_WALLPAPER ]; then
    mv $XFCE_DEFAULT_WALLPAPER ${NEWROOT}/usr/share/backgrounds/xfce/xfce4-shapes.svg
    ln -frs ${NEWROOT}/usr/share/backgrounds/svg/wallpaper4.svg $XFCE_DEFAULT_WALLPAPER
fi

# Determine SU_CMD (unused)
if [ -e ${NEWROOT}/usr/bin/doas ]; then
    SU_CMD=doas
elif [ -e ${NEWROOT}/usr/bin/sudo ]; then
    SU_CMD=sudo
fi

# Enable Calamares for autostart
if [ -e ${NEWROOT}/usr/bin/calamares ]; then
    install -Dm 644 ${NEWROOT}/usr/share/applications/calamares.desktop ${NEWROOT}/etc/xdg/autostart/
fi

#chown $USERNAME:$USERNAME ${NEWROOT}/home/$USERNAME/Desktop/calamares.desktop
#$SU_CMD -u $USERNAME dbus-launch gio set ${NEWROOT}/home/$USERNAME/Desktop/calamares.desktop -t string metadata::trusted "true"
