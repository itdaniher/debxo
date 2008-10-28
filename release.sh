#!/bin/sh -e

# prepare a release
for f in *.packages; do
	desktop=$(echo $f | sed 's/\.packages//')
	mkdir -p ext3 jffs2
	./initchroot.sh --package-list ${f} \
			--local-apt-mirror "deb http://localhost:9999/debian lenny main contrib non-free
deb http://localhost:9999/security lenny/updates main contrib non-free" \
			debxo-${desktop}
	./mkjffs2.sh debxo-${desktop} jffs2/${desktop}.img
	./mkext3.sh debxo-${desktop} ext3/debxo-${desktop}.ext3.img
	gzip ext3/debxo-${desktop}.ext3.img
done
