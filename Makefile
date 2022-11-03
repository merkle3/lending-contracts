.PHONY: test snapshot

test:
	forge test -vvv

snapshot:
	forge snapshot

cov: lcov.info
lcov.info: 
	forge coverage --report lcov