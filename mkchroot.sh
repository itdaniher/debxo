#!/bin/bash -e
#
# Copyright © 2008-2009  Andres Salomon <dilinger@collabora.co.uk>
#
# This file is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

. ./functions.sh

# load & set default values
CONFIG_TYPE=generic
. ./configs/${CONFIG_TYPE}/variables
. ./configs/${CONFIG_TYPE}/hooks
BASE_PLIST="./configs/${CONFIG_TYPE}/packages"
LOCAL_APT_MIRROR=

usage()
{
	echo "" 1>&2
	echo "Usage: $0 [<options>] <root directory>" 1>&2
	echo "" 1>&2
	echo "Options:" 1>&2
	echo "  --config-type <config>    directory name in configs/ to use" 1>&2
	echo "  --local-apt-mirror <srcs> sources.list for local mirror" 1>&2
	echo "" 1>&2
	exit 1
}

while test $# != 0
do
	case $1 in
	--config-type)
		CONFIG_TYPE=$2
		[ -d ./configs/${CONFIG_TYPE} ] || {
			echo "Error: can't find directory './configs/${CONFIG_TYPE}/'!" 1>&2
			exit 2
		}
		shift
		;;
	--local-apt-mirror)
		LOCAL_APT_MIRROR="$2"
		shift
		;;
	*)
		if [ "$#" != "1" ]; then
			echo "Unknown option $1" 1>&2
			usage
		else
			ROOT_DIR="$1"
		fi
		;;
	esac
	shift
done

if [ "$ROOT_DIR" = "" ]; then
	echo "" 1>&2
	echo "*** No root directory specified!" 1>&2
	usage
fi

if [ -d "${ROOT_DIR}" ]; then
	echo "" 1>&2
	echo "*** ${ROOT_DIR} already exists!" 1>&2
	usage
fi

if [ "$UID" != "0" ]; then
	echo "" 1>&2
	echo "*** $0 must be run with root privs!" 1>&2
	exit 1
fi

start_logging $ROOT_DIR

# load config-specific values
. ./configs/${CONFIG_TYPE}/variables
. ./configs/${CONFIG_TYPE}/hooks
PLIST="./configs/${CONFIG_TYPE}/packages"

if [ -z "${LOCAL_APT_MIRROR}" ]; then
    LOCAL_APT_MIRROR="${APT_SOURCES}"
fi

# parse apt mirror
MIRROR=$(printf "${LOCAL_APT_MIRROR}\n" | awk '/deb /{print $2}' | head -n1)
DIST=$(printf "${LOCAL_APT_MIRROR}\n" | awk '/deb /{print $3}' | head -n1)

# create chroot
debootstrap --arch ${IMG_ARCH} ${DIST} ${ROOT_DIR} ${MIRROR}
mount -t proc proc ${ROOT_DIR}/proc
mount -t devpts devpts ${ROOT_DIR}/dev/pts

# allow daemons to be installed without breaking
mv ${ROOT_DIR}/sbin/start-stop-daemon ${ROOT_DIR}/sbin/start-stop-daemon.REAL
cat >${ROOT_DIR}/sbin/start-stop-daemon<<EOF
#!/bin/sh
echo
echo "Warning: Fake start-stop-daemon called, doing nothing"
EOF
chmod 755 ${ROOT_DIR}/sbin/start-stop-daemon

# set up hostname stuff
echo "${IMG_HOSTNAME}" > ${ROOT_DIR}/etc/hostname
cat >${ROOT_DIR}/etc/hosts<<EOF
127.0.0.1 localhost.localdomain localhost
127.0.0.1 ${IMG_HOSTNAME}

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts
EOF

# add local network interface
cat >>${ROOT_DIR}/etc/network/interfaces<<EOF

auto lo
iface lo inet loopback
EOF

# set the default locale
echo "${IMG_LOCALE}" >${ROOT_DIR}/etc/locale.gen

# run any customizations necessary pre-package install
customize_chroot_hook "$ROOT_DIR"

# initialize apt
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_PRIORITY=critical
printf "${LOCAL_APT_MIRROR}\n" >${ROOT_DIR}/etc/apt/sources.list
(chroot ${ROOT_DIR} aptitude update)

# generic packages are always installed
(chroot ${ROOT_DIR} aptitude install -y `grep --invert-match '^#' ${BASE_PLIST}`)

# install the rest of the packages
(chroot ${ROOT_DIR} aptitude install -y `grep --invert-match '^#' ${PLIST}`)

# post-install customization hook
package_configure_hook "${ROOT_DIR}"

# add default user
(chroot ${ROOT_DIR} passwd -l root)
rm -rf ${ROOT_DIR}/home/*; 	# i have no idea what's adding this crap...
(chroot ${ROOT_DIR} useradd -s /bin/bash --create-home ${DEFUSER})
(chroot ${ROOT_DIR} passwd -d ${DEFUSER})
(chroot ${ROOT_DIR} adduser ${DEFUSER} cdrom)
(chroot ${ROOT_DIR} adduser ${DEFUSER} audio)
(chroot ${ROOT_DIR} adduser ${DEFUSER} video)
(chroot ${ROOT_DIR} adduser ${DEFUSER} plugdev)
(chroot ${ROOT_DIR} adduser ${DEFUSER} netdev)
(chroot ${ROOT_DIR} adduser ${DEFUSER} powerdev)
(chroot ${ROOT_DIR} adduser ${DEFUSER} floppy)
echo "${DEFUSER} ALL=(ALL) NOPASSWD: ALL" >> ${ROOT_DIR}/etc/sudoers

# override sources.list with shipping version
printf "${APT_SOURCES}\n" >${ROOT_DIR}/etc/apt/sources.list
(chroot ${ROOT_DIR} aptitude update)

# done, clean up
mv ${ROOT_DIR}/sbin/start-stop-daemon.REAL ${ROOT_DIR}/sbin/start-stop-daemon
(chroot ${ROOT_DIR} aptitude clean)
umount ${ROOT_DIR}/proc
umount ${ROOT_DIR}/dev/pts

# custom cleanup stuff
cleanup_chroot_hook "${ROOT_DIR}"
