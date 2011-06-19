#!/bin/bash -e

# prepare a release
for f in configs/debxo-*; do
	desktop=$(basename $f | sed 's/debxo-//')
	./mkchroot.sh --config-type debxo-${desktop} \
			--local-apt-mirror "deb http://localhost:9999/debian squeeze main contrib non-free
deb http://localhost:9999/security squeeze/updates main contrib non-free
deb http://localhost:9999/backports squeeze-backports main contrib non-free" \
			debxo-${desktop}
	[ -f ./configs/debxo-${desktop}/fstab-ubifs ] && ./mkubifs.sh --config-type debxo-${desktop} debxo-${desktop} ${desktop}.img
	[ -f ./configs/debxo-${desktop}/fstab-ext3 ] && ./mkext3.sh --config-type debxo-${desktop} debxo-${desktop} \
			debxo-${desktop}.ext3.img
	[ -f debxo-${desktop}.ext3.img ] && gzip debxo-${desktop}.ext3.img

	mkdir -p ext3 nand
	[ -f debxo-${desktop}.ext3.img.gz ] && mv debxo-${desktop}.ext3.img.gz ext3
	[ -f ${desktop}.img ] && mv ${desktop}.img ${desktop}.dat nand
done
