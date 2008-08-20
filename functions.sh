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

check_for_cmds()
{
	for cmd in $@; do
		which $cmd >/dev/null || {
			echo "Missing required command '$cmd'!" 1>&2
			return 1
		}
	done

	return 0
}

# @mntpt - path to mounted root directory
# @fstype - the root filesystem type (in a form that 'mount' understands)
create_fstab()
{
	mntpt="$1"
	fstype="$2"

	if [ "${fstype}" = "jffs2" ]; then
		r=mtd0
	else
		r="LABEL=OLPCRoot"
	fi

	cat >${mntpt}/etc/fstab<<EOF
${r} / ${fstype} defaults,noatime 1 1
devpts /dev/pts devpts gid=5,mode=620 0 0
tmpfs /dev/shm tmpfs defaults,size=15% 0 0
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
none /ofw promfs defaults 0 0
EOF
}

# @mntpt - path to mounted root directory
# @fstype - the root filesystem type (in a form that 'mount' understands)
create_ofwboot()
{
	mntpt="$1"
	fstype="$2"

	if [ "${fstype}" = "jffs2" ]; then
		r=mtd0
		rfs="rootfstype=jffs2"
		dev=nand
	else
		r=/dev/sda1
		rfs=""
		dev=disk
	fi

	cat >${mntpt}/boot/olpc.fth<<EOF
\\ OLPC boot script

" ro root=${r} ${rfs} fbcon=font:SUN12x22" to boot-file
game-key-mask h# 80 and if
	\\ boot from backup kernel
	" ${dev}:\\vmlinuz.old" to boot-device
else
	\\ boot from regular kernel
	" ${dev}:\\vmlinuz" to boot-device
then
boot
EOF
}
