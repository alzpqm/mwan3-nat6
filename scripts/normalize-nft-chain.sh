#!/bin/sh

set -eu

if [ "$#" -ne 1 ] || [ ! -r "$1" ]; then
	printf '%s\n' "usage: $0 NFT_CHAIN_DUMP" >&2
	exit 2
fi

LC_ALL=C awk '
{
	line = $0
	gsub(/counter packets [0-9][0-9]* bytes [0-9][0-9]*/,
		"counter packets <dynamic> bytes <dynamic>", line)
	print line
}
' "$1"
