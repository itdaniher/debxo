#!/bin/sh
set -e

IMAGE_DEFAULT=
INTERACTIVE=yes
OUTPUT=${IMAGE_DEFAULT}.bootable

. functions.sh

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

cp ${IMAGE}.{dat,crc,img} ${OUTPUT}

mkdir -p ${OUTPUT}/boot

# create essential header required by OpenFirmware
cat <<EOF >${OUTPUT}/boot/olpc.fth
\ OLPC boot script

cr
." This is a debxo bootable install script." cr
cr
." `md5sum ${IMAGE}.img`" cr
." `md5sum ${IMAGE}.dat`" cr
." `md5sum ${IMAGE}.crc`" cr
cr
EOF

# create either an interactive or non-interactive section
case $INTERACTIVE in
	no)
		cat <<EOF >>${OUTPUT}/boot/olpc.fth

\ --no-interactive was used, so we do not prompt
." Erasing everything here and installing debxo ${IMAGE}" cr
EOF
		;;
	yes|*)
		cat <<EOF >>${OUTPUT}/boot/olpc.fth

\ --interactive was used, so we prompt before erasing
." Power off to abort, or" cr
." press Enter to erase everything here and install debxo ${IMAGE} ?"
begin
    key d =
until
EOF
		;;
esac

cat <<EOF >>${OUTPUT}/boot/olpc.fth

cr
." Starting"

\ erase the NAND flash and fill it with the image
update-nand u:\\${IMAGE}.img

\ boot from the NAND flash
boot n:\boot\olpc.fth
EOF

# TODO: avoid reflashing if already flashed
