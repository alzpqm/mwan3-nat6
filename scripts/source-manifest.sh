#!/bin/sh

set -eu

PROJECT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

for required in .github openwrt scripts tests .gitignore \
	AGGREGATION_COMPARISON.md CHANGELOG.md LICENSE Makefile NAT6_HANDOFF.md \
	README.md VERSION; do
	[ -e "$required" ] || {
		printf '%s\n' "source-manifest: missing release path: $required" >&2
		exit 1
	}
done

{
	find .github openwrt scripts tests -type f -print
	printf '%s\n' .gitignore AGGREGATION_COMPARISON.md CHANGELOG.md LICENSE \
		Makefile NAT6_HANDOFF.md README.md VERSION
} | LC_ALL=C sort | while IFS= read -r file; do
	if mode="$(stat -f '%Lp' "$file" 2>/dev/null)"; then
		:
	elif mode="$(stat -c '%a' "$file" 2>/dev/null)"; then
		:
	else
		printf '%s\n' "source-manifest: cannot read mode: $file" >&2
		exit 1
	fi
	hash_line="$(sha256sum "$file")"
	hash="${hash_line%% *}"
	case "$hash" in
		*[!0-9a-f]*|'')
			printf '%s\n' "source-manifest: invalid SHA-256 output: $file" >&2
			exit 1
			;;
	esac
	[ "${#hash}" -eq 64 ] || {
		printf '%s\n' "source-manifest: invalid SHA-256 length: $file" >&2
		exit 1
	}
	printf '%s %s %s\n' "$mode" "$hash" "$file"
done
