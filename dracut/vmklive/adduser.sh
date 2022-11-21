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

# Create new user and remove password. We'll use autologin by default.
chroot ${NEWROOT} groupadd autologin
chroot ${NEWROOT} useradd -m -c $USERNAME -G audio,video,wheel,network,autologin -s $USERSHELL $USERNAME
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
    echo "permit nopass :${USERNAME}" > "$NEWROOT/etc/doas.conf"
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
