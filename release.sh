#!/bin/bash -e

# prepare a release
for f in configs/debxo-*; do
	desktop=$(basename $f | sed 's/debxo-//')
	./mkchroot.sh --config-type debxo-${desktop} \
			--local-apt-mirror "deb http://localhost:9999/debian squeeze main contrib non-free
deb http://localhost:9999/security squeeze/updates main contrib non-free
deb http://localhost:9999/backports squeeze-backports main contrib non-free" \
			debxo-${desktop}
	./mkubifs.sh --config-type debxo-${desktop} debxo-${desktop} ${desktop}.img
	./mkext3.sh --config-type debxo-${desktop} debxo-${desktop} \
			debxo-${desktop}.ext3.img
	gzip debxo-${desktop}.ext3.img

	mkdir -p ext3 nand
	mv debxo-${desktop}.ext3.img.gz ext3
	mv ${desktop}.img ${desktop}.dat nand
done
