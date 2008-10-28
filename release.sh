#!/bin/sh -e

# prepare a release
for f in *.packages; do
	desktop=$(echo $f | sed 's/\.packages//')
	./initchroot.sh --package-list ${f} \
			--local-apt-mirror "deb http://localhost:9999/debian lenny main contrib non-free
deb http://localhost:9999/security lenny/updates main contrib non-free" \
			debxo-${desktop}
	./mkjffs2.sh debxo-${desktop} ${desktop}.img
	./mkext3.sh debxo-${desktop} debxo-${desktop}.ext3.img
	gzip debxo-${desktop}.ext3.img

	mkdir -p ext3 jffs2
	mv debxo-${desktop}.ext3.img.gz ext3
	mv ${desktop}.img ${desktop}.dat jffs2
done
