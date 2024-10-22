<!-- DO NOT EDIT, generated by make README.md -->

# The Cereus Linux live image/rootfs generator and installer

<a href="https://codeberg.org/cereus-linux/mklive">
    <img alt="Get it on Codeberg" src="https://get-it-on.codeberg.org/get-it-on-white-on-black.png" height="60">
</a>

This repository is based on [void-mklive](https://github.com/void-linux/void-mklive). 

Not all the utilities available here are actually used by us (hence, they aren't adapted for Cereus): *mkplatformfs.sh*, *mkimage.sh*, *mknet.sh*, and *release.sh*. The main reason is our distribution is currently only focused in desktop usage and that we aren't relying in CI at the moment. However, this might (or not) change in the future.

The source code is mainly hosted on [Codeberg](https://codeberg.org/cereus-linux/mklive) with a mirror available on [GitHub](https://github.com/CereusLinuxProject/cereus-mklive). **Issues and pull requests should be made in Codeberg**.

## Overview

This repository contains several utilities:

* [*mklive.sh*](#mklivesh) - The Cereus Linux live image generator for x86.
* [*build-x86-images.sh*](#build-x86-imagessh) - Wrapper script to generate bootable
  and installable live images for x86.
* [*mkrootfs.sh*](#mkrootfssh) - The Cereus Linux rootfs generator for all platforms.
* *installer.sh* - The Cereus Linux el-cheapo installer for x86.

The following utilities are inherited from *void-mklive* but are unused at the moment:

* [*mkplatformfs.sh*](#mkplatformfssh) - The Void Linux filesystem tool to produce
  a rootfs for a particular platform.
* [*mkimage.sh*](#mkimagesh) - The Void Linux image generator for ARM platforms.
* [*mknet.sh*](#mknetsh) - Script to generate netboot tarballs for Void.
* *release.sh* - interacts with GitHub CI to generate and sign images for releases.

### Workflow

#### Generating x86 live ISOs

To generate a live ISO like the officially-published ones, use
[*build-x86-images.sh*](#build-x86-imagessh). To generate a more basic live ISO
(which does not include things like `cereus-installer`), use [*mklive.sh*](#mklivesh).

#### Generating ROOTFS tarballs

ROOTFS tarballs contain a basic Cereus Linux root filesystem without a kernel.
These can be useful for doing a [chroot install](https://docs.voidlinux.org/installation/guides/chroot.html)
or for [chroots and containers](https://docs.voidlinux.org/config/containers-and-vms/chroot.html).

Use [*mkrootfs.sh*](#mkrootfssh) to generate a Cereus Linux ROOTFS.

## Dependencies

Note that *cereus-mklive* is not guaranteed to work on distributions other than Cereus/Void
Linux, or in containers.

* Compression type for the initramfs image (by default: liblz4 for lz4, xz)
* xbps>=0.45
* qemu-user-static binaries (for mkrootfs)
* bash

## Kernel Command-line Parameters

`cereus-mklive`-based live images support several kernel command-line arguments
that can change the behavior of the live system:

- `live.autologin` will skip the initial login screen on `tty1`.
- `live.user` will change the username of the non-root user from the default
  `cereus`. The password remains `cereus`.
- `live.shell` sets the default shell for the non-root user in the live environment.
- `live.accessibility` enables accessibility features like the console screenreader
  `espeakup` in the live environment.
- `console` can be set to `ttyS0`, `hvc0`, or `hvsi0` to enable `agetty` on that
  serial console.
- `locale.LANG` will set the `LANG` environment variable. Defaults to `en_US.UTF-8`.
- `vconsole.keymap` will set the console keymap. Defaults to `us`.

### Examples:

- `live.autologin live.user=foo live.shell=/bin/bash` would create the user `foo`
  with the default shell `/bin/bash` on boot, and log them in automatically on `tty1`
- `live.shell=/bin/bash` would set the default shell for the `anon` user to `/bin/bash`
- `console=ttyS0 vconsole.keymap=cf` would enable `ttyS0` and set the keymap in
  the console to `cf`
- `locale.LANG=fr_CA.UTF-8` would set the live system's language to `fr_CA.UTF-8`

## Usage
### build-x86-images.sh

```
Usage: build-x86-images.sh [options ...] [-- mklive options ...]

Wrapper script around mklive.sh for several standard flavors of live images.
Adds cereus-installer and other helpful utilities to the generated images.

OPTIONS
 -a <arch>     Set XBPS_ARCH in the image
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
```

### mklive.sh

```
Usage: mklive.sh [options]

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
```

### mkrootfs.sh

```
Usage: mkrootfs.sh [options] <arch>

Generate a Cereus Linux ROOTFS tarball for the specified architecture.

Supported architectures:
 i686, i686-musl, x86_64, x86_64-musl,
 armv5tel, armv5tel-musl, armv6l, armv6l-musl, armv7l, armv7l-musl
 aarch64, aarch64-musl,
 mipsel, mipsel-musl,
 ppc, ppc-musl, ppc64le, ppc64le-musl, ppc64, ppc64-musl

OPTIONS
 -b <system-pkg>  Set an alternative base-system package (default: base-cereustrap)
 -c <cachedir>    Set XBPS cache directory (default: ./xbps-cachedir-<arch>)
 -C <file>        Full path to the XBPS configuration file
 -r <repo>        Use this XBPS repository. May be specified multiple times
 -o <file>        Filename to write the ROOTFS to (default: automatic)
 -x <num>         Number of threads to use for image compression (default: dynamic)
 -h               Show this help and exit
 -V               Show version and exit
```

