#!/bin/bash -e
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
		r=mtd:root
	else
		r="LABEL=${IMG_LABEL}"
	fi

	echo "${r} / ${fstype} defaults,noatime 1 1" >${mntpt}/etc/fstab
	if [ "${fstype}" = "jffs2" ]; then
		echo "mtd:boot /boot jffs2 defaults,noatime 1 1" >>${mntpt}/etc/fstab
	fi

	cat >>${mntpt}/etc/fstab<<EOF
proc /proc proc defaults 0 0
none /ofw promfs defaults 0 0
tmpfs /var/cache/apt/cache tmpfs defaults 0 0
EOF
}

# @mntpt - path to mounted root directory
# @fstype - the root filesystem type (in a form that 'mount' understands)
create_ofwboot()
{
	mntpt="$1"
	fstype="$2"

	if [ "${fstype}" = "jffs2" ]; then
		r="mtd:root"
		rfs="rootfstype=jffs2"
	else
		r="LABEL=${IMG_LABEL}"
		rfs=""
	fi

	cat >${mntpt}/boot/olpc.fth<<EOF
\\ OLPC boot script

\\ fetch the /chosen/bootpath property
" /chosen" find-package  if                       ( phandle )
  " bootpath" rot  get-package-property  0=  if   ( propval\$ )
    get-encoded-string                            ( bootpath\$ )
    [char] \ left-parse-string  2nip              ( dn\$ )

    \ store the first part of bootpath (up to the '\\') in \$DN
    dn-buf place                                  ( )
  then
then

" ro root=${r} ${rfs} video=lxfb fbcon=font:SUN12x22" to boot-file
game-key-mask h# 80 and if
	\\ boot from backup kernel
	" \${DN}\\vmlinuz.old" expand\$ to boot-device
	" \${DN}\\initrd.img.old" expand\$ to ramdisk
else
	\\ boot from regular kernel
	" \${DN}\\vmlinuz" expand\$ to boot-device
	" \${DN}\\initrd.img" expand\$ to ramdisk
then
dcon-unfreeze
boot
EOF
}

start_logging()
{
    logpipe="$1".pipe
    trap "rm -f $logpipe" 0
    mknod $logpipe p
    tee "$1".log <$logpipe &
    trap "kill $!; rm -f $logpipe" 0
    exec >$logpipe 2>&1
}
