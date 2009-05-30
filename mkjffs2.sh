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

CONFIG_TYPE=generic

usage()
{
	echo "" 1>&2
	echo "Usage: $0 [<options>] <root directory> <img>" 1>&2
	echo "" 1>&2
	echo "Options:" 1>&2
	echo "  --config-type <config>    directory name in configs/ to use" 1>&2
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
	*)
		if [ "$#" != "2" ]; then
			echo "Unknown option $1" 1>&2
			usage
		else
			ROOT_DIR=$1
			IMG_NAME=$2
			shift
		fi
		;;
	esac
	shift
done

if [ "${IMG_NAME}" == "${IMG_NAME/.img/.dat}" ]; then
	DAT_NAME=${IMG_NAME}.dat
else
	DAT_NAME=${IMG_NAME/.img/.dat}
fi

if [ ! -d "${ROOT_DIR}" ]; then
	echo "" 1>&2
	echo "*** Unable to find root directory!" 1>&2
	usage
fi

check_for_cmds mkfs.jffs2 sumtool || exit 1

# create image's /etc/fstab
if [ ! -f ./configs/${CONFIG_TYPE}/fstab-jffs2 ]; then
	echo "*** Unable to find fstab-jffs2!" 1>&2
	exit 1
fi
sed 's/[[:space:]]#.*//' ./configs/${CONFIG_TYPE}/fstab-jffs2 > ${ROOT_DIR}/etc/fstab

# TODO: this needs to go into an OFW package; here it's a hack
# create image's /boot/olpc.fth
if [ -f ./configs/${CONFIG_TYPE}/olpc.fth-jffs2 ]; then
	cp ./configs/${CONFIG_TYPE}/olpc.fth-jffs2 ${ROOT_DIR}/boot/olpc.fth
fi

create_jffs2()
{
	root_dir="$1"
	out="$2"

	# XXX:  do we want to switch to lzo?  (mkfs.jffs2 -X lzo)
	mkfs.jffs2 -n -e128KiB -r ${root_dir} -o ${out}.pre
	sumtool -n -p -e 128KiB -i ${out}.pre -o ${out}
	rm -f ${out}.pre
}

do_sha256()
{
	f=$1
	eblocks=$((`stat --printf "%s\n" $f` / (128*1024)))
	for b in $(seq 0 $(($eblocks - 1))); do
		sha=$(dd status=noxfer bs=128KiB skip=$b count=1 if=$f 2>/dev/null | sha256sum | cut -d\  -f1)
		echo "eblock: `printf '%x' $b` sha256 $sha" >> ${IMG_NAME}
	done
}

partition_map()
{
	# 0x190 * 128KiB = 50MiB boot, and the rest for root
	cat >${IMG_NAME}<<EOF
data:  ${DAT_NAME}
erase-all
partitions:  boot 190  root -1
set-partition: boot 
mark-pending: 0
EOF
	do_sha256 "_boot.img"
	cat >>${IMG_NAME}<<EOF
cleanmarkers
mark-complete: 0
set-partition: root
mark-pending: 0
EOF
	do_sha256 "_root.img"
	cat >>${IMG_NAME}<<EOF
cleanmarkers
mark-complete: 0
EOF
}

# create the boot partition
ln -s . ${ROOT_DIR}/boot/boot
create_jffs2 ${ROOT_DIR}/boot _boot.img
rm -f ${ROOT_DIR}/boot/boot

# create the root partition
mv ${ROOT_DIR}/boot _boot
mkdir ${ROOT_DIR}/boot
create_jffs2 ${ROOT_DIR} _root.img
rmdir ${ROOT_DIR}/boot
mv _boot ${ROOT_DIR}/boot

# concat partitions, finish up
partition_map
cat _boot.img _root.img > ${DAT_NAME}
rm -f _boot.img _root.img
