#!/bin/sh -e

# prepare a release
for f in *.packages; do
	desktop=$(echo $f | sed 's/\.packages//')
	./initchroot.sh debxo-${desktop}
	./mkjffs2.sh debxo-${desktop} ${desktop}.img
	./mkext3.sh debxo-${desktop} debxo-${desktop}.ext3.img
	gzip debxo-${desktop}.ext3.img
done
