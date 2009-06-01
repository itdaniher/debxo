#!/bin/bash -e

# prepare a release
for f in configs/debxo-*; do
	desktop=$(basename $f | sed 's/debxo-//')
	./mkchroot.sh --config-type debxo-${desktop} \
			--local-apt-mirror "deb http://localhost:9999/debian lenny main contrib non-free
deb http://localhost:9999/security lenny/updates main contrib non-free" \
			debxo-${desktop}
	./mkjffs2.sh debxo-${desktop} ${desktop}.img
	./mkext3.sh --config-type debxo-${desktop} debxo-${desktop} \
			debxo-${desktop}.ext3.img
	gzip debxo-${desktop}.ext3.img

	mkdir -p ext3 jffs2
	mv debxo-${desktop}.ext3.img.gz ext3
	mv ${desktop}.img ${desktop}.dat jffs2
done
