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
	echo "  --help                    display this help screen" 1>&2
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
	--help|-h)
		usage
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

	mkfs.jffs2 -n -e128KiB -r ${root_dir} -o ${out}.pre
	sumtool -n -p -e 128KiB -i ${out}.pre -o ${out}
	rm -f ${out}.pre
}

partition_map()
{
	cat >${IMG_NAME}<<EOF
data:  ${DAT_NAME}
erase-all
EOF

	# partition size map
	printf "partitions:" >> ${IMG_NAME}
	sed -ne 's/^mtd://p' configs/${CONFIG_TYPE}/fstab-jffs2 | \
			while read name mntpt fstype extra; do
		size=$(echo $extra | sed -ne 's/.*[[:space:]]\+#[[:space:]]\+//p')
		if [ "${size}" = "" ]; then
			size="-1"
		else
			# size in fstab is in MB; convert to 128KiB chunks (in hex)
			# MB * (1024/128)
			size=$((size * 8))
			size=`printf "%x\n" $size`
		fi
		printf "  $name $size" >> ${IMG_NAME}
	done
	printf "\n" >> ${IMG_NAME}

	# individual partitions
	sed -ne 's/^mtd://p' configs/${CONFIG_TYPE}/fstab-jffs2 | \
			while read name mntpt fstype extra; do
		cat >>${IMG_NAME}<<EOF
set-partition: ${name}
mark-pending: 0
EOF
		# sha256 summing for data
		eblocks=$((`stat --printf "%s\n" _${name}.img` / (128*1024)))
		for b in $(seq 0 $(($eblocks - 1))); do
			sha=$(dd status=noxfer bs=128KiB skip=$b count=1 if=_${name}.img 2>/dev/null \
					| sha256sum | cut -d\  -f1)
			echo "eblock: `printf '%x' $b` sha256 $sha" >> ${IMG_NAME}
		done
		cat >>${IMG_NAME}<<EOF
cleanmarkers
mark-complete: 0
EOF
	done
}

# move separate partitions out of the way
sed -ne 's/^mtd://p' configs/${CONFIG_TYPE}/fstab-jffs2 | \
		while read name mntpt fstype extra; do
	if [ "$mntpt" = "/" ]; then
		continue
	fi

	mv ${ROOT_DIR}/${mntpt} "_${name}"
	mkdir ${ROOT_DIR}/${mntpt}
done

# create partitions
sed -ne 's/^mtd://p' configs/${CONFIG_TYPE}/fstab-jffs2 | \
		while read name mntpt fstype extra; do
	if [ "$mntpt" = "/" ]; then
		create_jffs2 ${ROOT_DIR} "_${name}.img"

	else
		create_jffs2 "_${name}" "_${name}.img"
	fi
done

# move separate partitions back into the chroot
sed -ne 's/^mtd://p' configs/${CONFIG_TYPE}/fstab-jffs2 | \
		while read name mntpt fstype extra; do
	if [ "$mntpt" = "/" ]; then
		continue
	fi

	rmdir ${ROOT_DIR}/${mntpt}
	mv "_${name}" ${ROOT_DIR}/${mntpt}
done

# partition map is used by OFW for partition layout and sha256 checksums
partition_map

# concat partitions, finish up
rm -f ${DAT_NAME}
sed -ne 's/^mtd://p' configs/${CONFIG_TYPE}/fstab-jffs2 | \
		while read name mntpt fstype extra; do
	cat "_${name}.img" >> ${DAT_NAME}
	rm -f "_${name}.img"
done

exit 0
