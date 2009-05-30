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

IMG_NAME=""
ROOT_DIR=""

. ./functions.sh

CONFIG_TYPE=generic

# @img - fs image to attach loop device to
# @offset - if the image is partitioned, the offset to attach at
#
# sets $LOOP_DEV with the path of the newly attached loop device
attach_loop()
{
	img="$1"
	offset="$2"

	LOOP_DEV=$(losetup -f)

	if [ "$offset" != "" ]; then
		losetup -o "$offset" "$LOOP_DEV" "$img"
	else
		losetup "$LOOP_DEV" "$img"
	fi
}

# @dev - the loop device to detach
detach_loop()
{
	losetup -d "$1"
}

# @img - image name to create
create_bootable_img()
{
	img="$1"

	# get the total size by summing all the partition sizes (listed in fstab comments)
	partition_sizes=`grep '^LABEL=' configs/${CONFIG_TYPE}/fstab-ext3 | \
			sed 's/.*#[[:space:]]\+\([0-9]\+\)$/\1/' | xargs echo | tr ' ' +`
	size=$(($partition_sizes))

	# there's some partition overhead; pad the image so that parted doesn't whine
	overhead=`echo | awk "{ printf(\"%d\n\", 0.014 * $size); }"`
	size=$((size + overhead))

	# first, create a sparse image
	minus_size=$(($size * 6 / 100))
	size=$(($size - $minus_size))
	dd if=/dev/zero of=$img bs=1M count=1 seek=$(($size - 1))

	# fill in the partition table
	parted -s "$img" "mklabel msdos"
	prior=0
	grep '^LABEL=' configs/${CONFIG_TYPE}/fstab-ext3 | \
			sed 's/.*#[[:space:]]\+\([0-9]\+\)$/\1/' | while read s; do
		end=$((prior + s))
		parted -s "$img" "mkpart primary ext2 $prior $end"
		prior=$end
	done
	parted -s "$img" "set 1 boot on"
}

# @img - image name
# @mntpt - path to mounted root directory
grub_install()
{
	img="$1"
	mntpt="$2"

	mkdir -p ${mntpt}/boot/grub
	cp /usr/lib/grub/i386-pc/stage[12] ${mntpt}/boot/grub
	cp /usr/lib/grub/i386-pc/e2fs_stage1_5 ${mntpt}/boot/grub

	cat >${mntpt}/boot/grub/menu.lst<<EOF
default 0
timeout 5
color cyan/blue white/blue
EOF
	label=`sed -ne 's/^LABEL=\(.\+\)[[:space:]]\+\/[[:space:]]\+.*/\1/p' configs/${CONFIG_TYPE}/fstab-ext3`
	prefix=
	grep -q ' ${mntpt}/boot ' /proc/mounts && prefix=/boot
	for kern in ${mntpt}/boot/vmlinuz-*; do
		v=$(basename $kern | sed 's/vmlinuz-//')
		cat >>${mntpt}/boot/grub/menu.lst<<EOF

title		Debian GNU/Linux, kernel ${v}
root		(hd0,0)
kernel		${prefix}/vmlinuz-${v} root=LABEL=${label} ro
initrd		${prefix}/initrd.img-${v}
boot
EOF
	done

	# grub-install is pretty broken, so we do this manually
	geom=`parted -s "$img" "unit chs" "print" | sed -ne 's/geometry: \([0-9]\+\),\([0-9]\+\),\([0-9]\+\)/:\1 \2 \3:/p' | cut -d: -f2`
	grub --device-map=/dev/null <<EOF
device (hd0) $img
geometry (hd0) $geom
root (hd0,0)
setup (hd0)
EOF

}

# @img - image to create a filesystem on
# @root_dir - root directory to populate the fs with
mk_ext3_fs()
{
	img="$1"
	root_dir="$2"

	# create root mount point
	mount_point_root=$(mktemp)
	rm -f $mount_point_root
	mkdir $mount_point_root

	i=1
	sed -ne 's/^LABEL=//p' configs/${CONFIG_TYPE}/fstab-ext3 | \
			while read name mntpt fstype extra; do
		partition_start=$(parted -m -s "$img" "unit B" "print" | grep "^$i" | cut -d: -f2 | cut -dB -f1)
		partition_size=$(parted -m -s "$img" "unit B" "print" | grep "^$i" | cut -d: -f4 | cut -dB -f1)
		bs=1024
	
		# create the filesystems/swap
		attach_loop "$img" "$partition_start"
		if [ "$fstype" = "ext3" ]; then
			mke2fs -q -b $bs -L "$name" -m0 -j "$LOOP_DEV" $((partition_size / bs))
			tune2fs -c0 -i0 "$LOOP_DEV"	# XXX: this is from OLPC days; do we still want this?
		elif [ "$fstype" = "ext2" ]; then
			mke2fs -q -b $bs -L "$name" -m0 "$LOOP_DEV" $((partition_size / bs))
			tune2fs -c0 -i0 "$LOOP_DEV"
		elif [ "$fstype" = "swap" ]; then
			mkswap -L "$name" "$LOOP_DEV" $((partition_size / bs))
		fi
		detach_loop "$LOOP_DEV"

		# mount the root partition if it's found
		if [ "$mntpt" = "/" ]; then
			mount "$img" "${mount_point_root}" -o loop,offset=$partition_start -t $fstype
		fi

		i=$((i + 1))
	done

	# mount the rest of the partitions (working around /boot coming before /)
	sed -ne 's/^LABEL=//p' configs/${CONFIG_TYPE}/fstab-ext3 | \
			while read name mntpt fstype extra; do

		# / is already mounted
		if [ "$mntpt" = "/" ]; then
			continue
		fi

		# if $mntpt doesn't start with '/', don't mount it
		if [ "${mntpt##/}" = "$mntpt" ]; then
			continue
		fi

		# parted 1.8 added --machine for easier parsing; however,
		# debian still has 1.7 in unstable.
		partition_start=$(parted -s "$img" "unit B" "print" | sed -ne "s/^ $i[[:space:]]\+//p" | cut -dB -f1)
	
		[ -d "${mount_point_root}${mntpt}" ] || mkdir -p "${mount_point_root}${mntpt}"
		mount "$img" "${mount_point_root}${mntpt}" -o loop,offset=$partition_start -t $fstype
	done
	
	# populate the filesystem
	cp -ra "$root_dir"/* "$mount_point_root" || true
	grub_install "$img" "$mount_point_root"

	# umount the filesystem
	sed -ne 's/^LABEL=//p' configs/${CONFIG_TYPE}/fstab-ext3 | \
			while read name mntpt fstype extra; do

		# don't unmount / yet
		if [ "$mntpt" = "/" ]; then
			continue
		fi

		# if $mntpt doesn't start with '/', it's not mounted
		if [ "${mntpt##/}" = "$mntpt" ]; then
			continue
		fi

		umount "${mount_point_root}${mntpt}"
	done

	umount "${mount_point_root}"
	rmdir "${mount_point_root}" 
}

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
		ROOT_DIR="$1"
		shift
		if [ "$#" = "1" ]; then
			IMG_NAME="$1"
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
if [ "$IMG_NAME" = "" ]; then
	echo "" 1>&2
	echo "*** No image name specified!" 1>&2
	usage
fi
if [ ! -d "$ROOT_DIR" ]; then
	echo "" 1>&2
	echo "*** Unable to find root directory!" 1>&2
	usage
fi

check_for_cmds losetup parted mke2fs tune2fs grub || exit 1

# create image's /etc/fstab
if [ ! -f ./configs/${CONFIG_TYPE}/fstab-ext3 ]; then
	echo "*** Unable to find fstab-ext3!" 1>&2
	exit 1
fi
sed 's/[[:space:]]#.*//' ./configs/${CONFIG_TYPE}/fstab-ext3 > ${ROOT_DIR}/etc/fstab

# TODO: this needs to go into an OFW package; here it's a hack
# create image's /boot/olpc.fth
if [ -f ./configs/${CONFIG_TYPE}/olpc.fth-ext3 ]; then
	cp ./configs/${CONFIG_TYPE}/olpc.fth-ext3 ${ROOT_DIR}/boot/olpc.fth
fi

create_bootable_img ${IMG_NAME}
mk_ext3_fs ${IMG_NAME} ${ROOT_DIR}

#mount ${IMG_NAME}.ext3 $MOUNT_POINT -o loop,offset=$OS_PART1_BEGIN -t ext3
#cp -r "$ROOT_DIR"/* $MOUNT_POINT
#umount $MOUNT_POINT
