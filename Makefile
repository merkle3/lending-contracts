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

# run the forge script to deploy on eth
deploy.local:
	forge script script/deployeth.s.sol:DeployEth --fork-url http://localhost:8545 --broadcast

fork:
	anvil --fork-url ${FORK_URL}