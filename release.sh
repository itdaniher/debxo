#!/bin/sh -e

# prepare a release
for f in *.packages; do
	desktop=$(echo $f | sed 's/\.packages//')
	mkdir -p ext3 jffs2
	./initchroot.sh --package-list ${f} debxo-${desktop}
	./mkjffs2.sh debxo-${desktop} jffs2/${desktop}.img
	./mkext3.sh debxo-${desktop} ext3/debxo-${desktop}.ext3.img
	gzip ext3/debxo-${desktop}.ext3.img
done
