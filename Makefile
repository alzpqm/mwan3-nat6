VERSION := $(shell sed -n '1p' VERSION)

.PHONY: check test

check:
	@test -n "$(VERSION)"
	@sh -n openwrt/mwan3-nat6/files/usr/nft-nat6.sh
	@sh tests/test-package.sh
	@sh tests/test-nft-nat6.sh
	@sh tests/test-luci-backend.sh
	@sh tests/test-comparison.sh
	@echo "mwan3 nat6 $(VERSION): checks passed"

test: check
