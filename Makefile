VERSION := $(shell sed -n '1p' VERSION)

.PHONY: check test

check:
	@test -n "$(VERSION)"
	@sh -n openwrt/mwan3-nat6/files/usr/nft-nat6.sh
	@sh tests/test-package.sh
	@sh tests/test-nft-nat6.sh
	@sh tests/test-watch.sh
	@sh tests/test-luci-backend.sh
	@sh tests/test-localization.sh
	@sh tests/test-comparison.sh
	@sh tests/test-live-chain-normalize.sh
	@sh tests/test-source-manifest.sh
	@sh tests/test-openwrt-install-gate.sh
	@sh tests/test-openwrt-post-reboot-gate.sh
	@echo "mwan3 nat6 $(VERSION): checks passed"

test: check
