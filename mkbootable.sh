#!/bin/bash
#
# mkbootable.sh, make a bootable file set from a jffs2 image
# Copyright © 2008  James Cameron <quozl@laptop.org>
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
#

# Using an image produced by mkjffs2.sh,
# produces a tree of files suitable for erasing and loading an XO,
# typical usage is to mount USB storage and then populate the storage,
# for example:
#
# mount /dev/sdz1 /mnt
# ./mkbootable --output /mnt gnome
# umount /mnt

set -e

IMAGE_DEFAULT=
INTERACTIVE=yes
OUTPUT=${IMAGE_DEFAULT}.bootable

. ./functions.sh

images()
{
	echo "Available images:" 1>&2
	echo -n "  " 1>&2
	ls *.img | cut -f1 -d. | tr '\n' ' ' 1>&2
}

usage()
{
	echo "" 1>&2
	echo "Usage: $0 [<options>] <image-name>" 1>&2
	echo "" 1>&2
	echo "Options:" 1>&2
	echo "  --no-interactive    in the generated media, during boot, do not prompt" 1>&2
	echo "  --output dir        directory in which to create the structure" 1>&2
	echo "" 1>&2
	echo "Argument:" 1>&2
	echo "  <image-name>       an image name, default $IMAGE_DEFAULT" 1>&2
	echo "" 1>&2
	images
	echo "" 1>&2
	exit 1
}

if test $# == 0; then
	usage
fi

IMAGE="$IMAGE_DEFAULT"
while test $# != 0
do
	case $1 in
	--no-interactive)
		INTERACTIVE=no
		;;
	--interactive)
		INTERACTIVE=yes
		;;
	--output)
		OUTPUT=$2
		shift
		;;
	*)
		if [ "$#" != "1" ]; then
			echo "Unknown option $1" 1>&2
			usage
		else
			IMAGE="$1"
			if [ "${OUTPUT}" == "" ]; then
				OUTPUT=${IMAGE}.bootable
			fi
		fi
		;;
	esac
	shift
done

if ! test -f ${IMAGE}.img; then
	echo "*** No such image ${IMAGE}"
	exit 1
fi

if ! test -d ${OUTPUT}; then
	mkdir ${OUTPUT}
fi

cp ${IMAGE}.{dat,img} ${OUTPUT}

mkdir -p ${OUTPUT}/boot

# create essential header required by OpenFirmware
cat <<EOF >${OUTPUT}/boot/olpc.fth
\ OLPC boot script

visible
clear-screen
cr
." This is a xodist bootable install script for the OLPC XO-1." cr
cr
." Checksums:" cr
."     `md5sum ${IMAGE}.img`" cr
."     `md5sum ${IMAGE}.dat`" cr
cr
EOF

# create either an interactive or non-interactive section
case $INTERACTIVE in
	no)
		cat <<EOF >>${OUTPUT}/boot/olpc.fth

\ --no-interactive was used, so we do not prompt
." Erasing everything here and installing ${IMAGE}" cr
EOF
		;;
	yes|*)
		cat <<EOF >>${OUTPUT}/boot/olpc.fth

\ --interactive was used, so we prompt before erasing
." Type yes then enter to erase everything here and install ${IMAGE} ? "
cursor-on
key  lcc  dup emit  ascii y = not  [if] cr abort [then]
key  lcc  dup emit  ascii e = not  [if] cr abort [then]
key  lcc  dup emit  ascii s = not  [if] cr abort [then]
key       dup emit  d       = not  [if] cr abort [then]

EOF
		;;
esac

cat <<EOF >>${OUTPUT}/boot/olpc.fth

cr
." Starting"

\ erase the NAND flash and fill it with the image
\ boot from the NAND flash
: update-and-boot
  " update-nand u:\\${IMAGE}.img" evaluate
  " boot n:\boot\olpc.fth" evaluate
;

update-and-boot
EOF

# TODO: avoid reflashing if already flashed
