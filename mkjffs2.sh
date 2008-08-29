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

. functions.sh

usage()
{
	echo "" 1>&2
	echo "Usage: $0 <root directory> <img>" 1>&2
	echo "" 1>&2
	exit 1
}

if [ "$#" != "2" ]; then
	usage
fi

ROOT_DIR=$1
IMG_NAME=$2

if [ "${IMG_NAME}" == "${IMG_NAME/.img/.crc}" ]; then
    CRC_NAME=${IMG_NAME}.crc
else
    CRC_NAME=${IMG_NAME/.img/.crc}
fi

if [ ! -d "${ROOT_DIR}" ]; then
	echo "" 1>&2
	echo "*** Unable to find root directory!" 1>&2
	usage
fi

check_for_cmds mkfs.jffs2 sumtool || exit 1
create_fstab ${ROOT_DIR} jffs2
create_ofwboot ${ROOT_DIR} jffs2

mkfs.jffs2 -n -e128KiB -r ${ROOT_DIR} -o ${IMG_NAME}.pre
sumtool -n -p -e 128KiB -i ${IMG_NAME}.pre -o ${IMG_NAME}
rm -f ${IMG_NAME}.pre
./crcimg.pl < ${IMG_NAME} > ${CRC_NAME}
