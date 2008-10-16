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

ROOT_SIZE="2048"
IMG_LABEL="DebXO"
IMG_NAME=""
ROOT_DIR=""

. functions.sh

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

# @img - fs image to mount
# @type - fs type to mount
# @offset - if the image is partitioned, the offset to mount at
#
# sets $MOUNT_POINT with the path of the newly created (and mounted) dir
mk_mount()
{
	img="$1"
	type="$2"
	offset="$3"

	if [ "$offset" != "" ]; then
		offset=",offset=$offset"
	fi

	MOUNT_POINT=$(mktemp)
	rm -f $MOUNT_POINT
	mkdir $MOUNT_POINT

	mount "$img" "$MOUNT_POINT" -o loop$offset -t "$type"
}

# @mntpt - directory to umount and delete
rm_mount()
{
	umount "$1"
	rmdir "$1"
}

# @img - image name to create
# @size - image size
create_bootable_img()
{
	img="$1"
	size="$2"

	# first, create a sparse image
	minus_size=$(($size * 6 / 100))
	size=$(($size - $minus_size))
	dd if=/dev/zero of=$img bs=1M count=1 seek=$(($size - 1))

	# fill in the partition table
	parted -s "$img" "mklabel msdos"
	parted -s "$img" "mkpart primary ext2 0 -1"
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

title		$IMG_LABEL
root		(hd0,0)
kernel		/vmlinuz root=LABEL=${IMG_LABEL} ro
boot
EOF

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
# @label - fs label
# @root_dir - root directory to populate the fs with
mk_ext3_fs()
{
	img="$1"
	label="$2"
	root_dir="$3"

	# parted 1.8 added --machine for easier parsing; however,
	# debian still has 1.7 in unstable.
	partition_start=$(parted -s "$img" "unit B" "print" | sed -ne 's/^ 1[[:space:]]\+//p' | cut -dB -f1)

	# create the filesystem
	attach_loop "$img" "$partition_start"
	mke2fs -q -L "$label" -m0 -j "$LOOP_DEV"
	tune2fs -c0 -i0 "$LOOP_DEV"
	detach_loop "$LOOP_DEV"

	# populate the filesystem
	mk_mount "$img" "ext3" "$partition_start"
	cp -ra "$root_dir"/* "$MOUNT_POINT" || true
	create_fstab "$MOUNT_POINT" "ext3"
	grub_install "$img" "$MOUNT_POINT"
	rm_mount "$MOUNT_POINT"
}

usage()
{
	echo "" 1>&2
	echo "Usage: $0 [<options>] <root directory> <img>" 1>&2
	echo "" 1>&2
	echo "Options:" 1>&2
	echo "  -l <label>    Image label" 1>&2
	echo "  -s <size>     Root filesystem size (in MB)" 1>&2
	echo "" 1>&2
	exit 1
}

while test $# != 0
do
	case $1 in
	-l)
		IMG_LABEL=$2
		shift
		;;
	-s)
		ROOT_SIZE=$2
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
create_fstab ${ROOT_DIR} ext3
create_ofwboot ${ROOT_DIR} ext3

create_bootable_img ${IMG_NAME} ${ROOT_SIZE}
mk_ext3_fs ${IMG_NAME} ${IMG_LABEL} ${ROOT_DIR}

#mount ${IMG_NAME}.ext3 $MOUNT_POINT -o loop,offset=$OS_PART1_BEGIN -t ext3
#cp -r "$ROOT_DIR"/* $MOUNT_POINT
#umount $MOUNT_POINT
