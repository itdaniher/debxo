#!/bin/sh -e
#
# Copyright © 2008  Andres Salomon <dilinger@queued.net>
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

DIST=lenny
DEFUSER=olpc
PLIST=gnome.packages
MIRROR=http://http.us.debian.org/debian/
OTHERMIRROR=

. functions.sh

usage()
{
	echo "" 1>&2
	echo "Usage: $0 [<options>] <root directory>" 1>&2
	echo "" 1>&2
	echo "Options:" 1>&2
	echo "  --distribution <name>     Which distribution to use" 1>&2
	echo "  --user <user>             Username for default user" 1>&2
	echo "  --package-list <list>     File containing package list" 1>&2
	echo "  --mirror <url>            Main Mirror URL prefix" 1>&2
	echo "  --othermirror <line>      An additional sources.list line" 1>&2
	echo "" 1>&2
	exit 1
}

while test $# != 0
do
	case $1 in
	--distribution)
		DIST=$2
		shift
		if [ -z "${OTHERMIRROR}" ]; then
		    OTHERMIRROR="deb http://security.debian.org/ ${DIST}/updates main contrib non-free"
		fi
		;;
	--user)
		DEFUSER=$2
		shift
		;;
	--package-list)
		PLIST=$2
		[ -f ${PLIST} ] || {
			echo "Error: can't find file '${PLIST}'!" 1>&2
			exit 2
		}
		shift
		;;
	--mirror)
		MIRROR=$2
		shift
		;;
	--othermirror)
		OTHERMIRROR=$2
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

check_for_cmds debootstrap || exit 1

if [ -z "${OTHERMIRROR}" ]; then
    OTHERMIRROR="deb http://security.debian.org/ ${DIST}/updates main contrib non-free"
fi

# create chroot
debootstrap --arch i386 ${DIST} ${ROOT_DIR} ${MIRROR}
mkdir ${ROOT_DIR}/ofw
mkdir ${ROOT_DIR}/var/cache/apt/cache
chroot_internal_mounts ${ROOT_DIR}

# allow daemons to be installed without breaking
mv ${ROOT_DIR}/sbin/start-stop-daemon ${ROOT_DIR}/sbin/start-stop-daemon.REAL
cat >${ROOT_DIR}/sbin/start-stop-daemon<<EOF
#!/bin/sh
echo
echo "Warning: Fake start-stop-daemon called, doing nothing"
EOF
chmod 755 ${ROOT_DIR}/sbin/start-stop-daemon

# set up apt (working around #314334)
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_PRIORITY=critical
cat >${ROOT_DIR}/etc/apt/apt.conf<<EOF
Acquire::Pdiffs "false";
APT::Install-Recommends "false";
Dir {
	Cache "var/cache/apt/" {
		srcpkgcache "cache/srcpkgcache.bin";
		pkgcache "cache/pkgcache.bin";
	};
};
EOF
cat >${ROOT_DIR}/etc/apt/sources.list<<EOF
deb ${MIRROR} ${DIST} main contrib non-free
${OTHERMIRROR}
EOF
(chroot ${ROOT_DIR} aptitude update)

# set up base system and base packages
echo "en_US.UTF-8 UTF-8" >${ROOT_DIR}/etc/locale.gen
(chroot ${ROOT_DIR} aptitude install -y `cat base.packages`)

k="http://lunge.mit.edu/~dilinger/debxo-0.2/initramfs-tools_0.92l.2_all.deb 
 http://lunge.mit.edu/~dilinger/debxo-0.2/ofw-config_0.1_all.deb 
 http://lunge.mit.edu/~dilinger/debxo-0.3/linux-2.6.25.15_2.6.25.15-145_i386.deb"
mkdir -p cache
for i in $k; do
	pkg=$(basename ${i})
	wget --continue -O cache/${pkg} ${i}
	cp cache/${pkg} ${ROOT_DIR}/${pkg} 
	(chroot ${ROOT_DIR} dpkg -i /${pkg})
	rm -f ${ROOT_DIR}/${pkg}
done

# ensure certain modules get loaded during boot
cat >>${ROOT_DIR}/etc/modules<<EOF
lxfb
fbcon
olpc_dcon
scx200_acb
i8042
EOF

echo "debxo" > ${ROOT_DIR}/etc/hostname
cat >${ROOT_DIR}/etc/hosts<<EOF
127.0.0.1 localhost.localdomain localhost
127.0.0.1 debxo

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts
EOF

# install packages
(chroot ${ROOT_DIR} aptitude install -y `cat ${PLIST}`)

# configure X
if [ -d ${ROOT_DIR}/etc/X11 ]; then
    cat >${ROOT_DIR}/etc/X11/xorg.conf<<EOF
# xorg.conf (X.Org X Window System server configuration file)

Section "Monitor"
	Identifier "Configured Monitor"
	HorizSync 30-67
	VertRefresh 48-52
	DisplaySize 152 114
	Mode "1200x900"
		DotClock 57.275
		HTimings 1200 1208 1216 1240
		VTimings 900 905 908 912
		Flags "-HSync" "-VSync"
	EndMode
EndSection

Section "Screen"
	Identifier "Default Screen"
	Monitor "Configured Monitor"
EndSection
EOF
fi

# configure kdm, kde
if [ -d ${ROOT_DIR}/etc/kde3/kdm ]; then
    sed --in-place "s/AllowNullPasswd=false/AllowNullPasswd=true/;s/#AutoLoginEnable=true/AutoLoginEnable=true/;s/#AutoLoginUser=fred/AutoLoginUser=${DEFUSER}/" ${ROOT_DIR}/etc/kde3/kdm/kdmrc
fi

# configure gdm, gnome
if [ -d ${ROOT_DIR}/etc/gdm ]; then
    sed -i "s_\[daemon\]_\[daemon\]\n\nGreeter=/usr/lib/gdm/gdmlogin\n\nAutomaticLoginEnable=true\n\nAutomaticLogin=${DEFUSER}_" ${ROOT_DIR}/etc/gdm/gdm.conf
fi
if [ -d ${ROOT_DIR}/etc/gconf/2 ]; then
    cat >${ROOT_DIR}/etc/gconf/2/local-defaults.path<<EOF
# DebXO defaults (customized for the XO-1's display
xml:readonly:/etc/gconf/debxo.xml.defaults
EOF
    mkdir -p ${ROOT_DIR}/etc/gconf/debxo.xml.defaults
    cp %gconf-tree.xml ${ROOT_DIR}/etc/gconf/debxo.xml.defaults/
fi

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

# add local network interface
cat >>${ROOT_DIR}/etc/network/interfaces<<EOF

auto lo
iface lo inet loopback
EOF

# configure sugar
if [ -d ${ROOT_DIR}/usr/share/sugar ]; then
    # #?
    ln -sf /usr/share/activities/ ${ROOT_DIR}/usr/share/sugar
    cat >> ${ROOT_DIR}/home/${DEFUSER}/.Xsession <<- EOF
matchbox-window-manager -use_titlebar no &
sugar
EOF
fi

# done, clean up
mv ${ROOT_DIR}/sbin/start-stop-daemon.REAL ${ROOT_DIR}/sbin/start-stop-daemon
(chroot ${ROOT_DIR} aptitude clean)
chroot_internal_umounts ${ROOT_DIR}
