include .env
.PHONY: test snapshot integration

test:
	forge test -vvv --no-match-path test/*.integration.sol

integration:
	forge test -vvv --match-path test/*.integration.sol --fork-url ${FORK_URL}

snapshot:
	forge snapshot

cov: lcov.info
lcov.info: 
	forge coverage --report lcov