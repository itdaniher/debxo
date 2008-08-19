#!/usr/bin/perl -w

use strict;
use String::CRC32;

my ($crc, $buf);
while (read(STDIN, $buf, 0x20000) eq 0x20000) {
	$crc = crc32($buf);
	printf("%08lx\n", $crc);
}

