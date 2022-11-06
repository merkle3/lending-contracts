// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {SqrtPriceMath} from "@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import {PoolAddress} from "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import {ERC721Enumerable} from "../interfaces/ERC721Enumerable.sol";
import {IAssetClass} from "../interfaces/IAssetClass.sol";
import {IController} from "../interfaces/IController.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {Multicall} from "../utils/Multicall.sol";
import {IMerkleCallback} from "../interfaces/IMerkleCallback.sol";
import {BytesLib} from '../libraries/BytesLib.sol';

contract UniswapV3 is
    IAssetClass,
    ERC721Enumerable,
    IERC721Receiver,
    Ownable,
    Multicall,
    Pausable
{
    // safe math library
    using SafeMath for uint256;
    using Address for address;
    using BytesLib for bytes;

    // uniswapv3 addresses
    INonfungiblePositionManager constant UniswapNftManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address constant UNISWAP_V3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    // activated pools, that can be deposited and borrowed
    // against
    mapping(address => bool) public activatedPools;

    // oracles for pricing a token
    mapping(address => address) public oracles;

    // scale up for some tokens
    mapping(address => uint256) tokenScaleFactor;

    // minimum deposit in usd
    // default to $200
    uint256 public minDeposit = 200 * 10**8;

    // when a new pool is actived
    event ActivatePool(address pool);

    // when a pool is deactivated
    event PausePool(address pool);

    constructor(
        address _controller
    ) ERC721("Merkle Uniswap V3 Position", "mUNI3") {
        // register owner
        transferOwnership(msg.sender);

        // register controller
        controller = IController(_controller);
    }

    /// ----- POOL MANAGEMENT -----

    // set the scale factor an asset
    function setScaleFactor(address token, uint256 factor) external onlyOwner {
        tokenScaleFactor[token] = factor;
    }

    function setOracle(address token, address oracle) external onlyOwner {
        // set the oracle
        oracles[token] = oracle;
    }

    // activate a new pool. This means that the pool can now be used as collateral
    function activatePool(address poolAddress) external onlyOwner {
        // make sure it's not already activated
        require(!activatedPools[poolAddress], "pool already activated");

        // get the pool 
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        // require that oracles are set
        require(
            oracles[pool.token0()] != address(0),
            "oracle for token0 not set"
        );

        // for both tokens
        require(
            oracles[pool.token1()] != address(0),
            "oracle for token1 not set"
        );

        // require that scale factor are set
        require(
            tokenScaleFactor[pool.token0()] != 0,
            "scale factor for token0 not set"
        );

        // for both tokens
        require(
            tokenScaleFactor[pool.token1()] != 0,
            "scale factor for token1 not set"
        ); 

        // activate the pool
        activatedPools[poolAddress] = true;

        // events
        emit ActivatePool(poolAddress);
    }

    // pause a pool, this will prevent new assets from being deposited
    // TODO: should we still count assets that are deposited as collateral?
    function pausePool(address poolAddress) external onlyOwner {
        // only deactivate active pools
        require(activatedPools[poolAddress], "pool not activated");

        // pause the pool
        activatedPools[poolAddress] = false;

        // events
        emit PausePool(poolAddress);
    }

    // a method for the protocol to collect fees
    function collectFee(address token) external onlyOwner {
        // send all to the fee collector
        IERC20(token).transfer(
            msg.sender,
            IERC20(token).balanceOf(address(this))
        );
    }

    // get the amount of token that a user could withdraw
    // from the position, that isn't part of the positions.
    // These are the fees that the position has generated in uniswap v3.
    function getCollectableTokens(uint256 tokenId)
        public
        view
        returns (uint128 tokensOwed0, uint128 tokensOwed1)
    {
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            tokensOwed0,
            tokensOwed1
        ) = UniswapNftManager.positions(tokenId);
    }

    // get the amount of tokens a position is made of
    function getPositionTokens(uint256 tokenId)
        public
        view
        returns (
            address,
            address,
            uint256,
            uint256
        )
    {
        uint256 amount0 = 0;
        uint256 amount1 = 0;

        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = UniswapNftManager.positions(tokenId);

        // get the address of the pool
        address poolAddress = PoolAddress.computeAddress(
            UNISWAP_V3_FACTORY,
            PoolAddress.getPoolKey(token0, token1, fee)
        );

        // get the slot 0 of the pool
        (uint160 sqrtPriceX96, int24 poolTick, , , , , ) = IUniswapV3Pool(
            poolAddress
        ).slot0();

        // compute the amount of token0 we would get
        // if we liquidated this position right now
        if (poolTick < tickLower) {
            // we are under the position
            amount0 = SqrtPriceMath.getAmount0Delta(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity,
                false
            );
        } else if (poolTick < tickUpper) {
            // we are in the middle of the position
            amount0 = SqrtPriceMath.getAmount0Delta(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity,
                false
            );
        } else {
            // if we are above the position then everything
            // is in the second token
        }

        // compute the amount of token1 we would get
        // if we liquidated this position right now
        if (poolTick < tickLower) {
            // we are below the bottom of the position
            // then everything is in the first token
            amount1 = 0;
        } else if (poolTick < tickUpper) {
            // we are in the middle of the position
            amount1 = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtRatioAtTick(tickLower),
                sqrtPriceX96,
                liquidity,
                false
            );
        } else {
            // we are above the position
            amount1 = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity,
                false
            );
        }

        return (token0, token1, amount0, amount1);
    }
    
    // get the value in USD of a position
    function getAssetValueUsd(uint256 tokenId) public view returns (uint256) {
        // get the composition of a position
        (
            address token0,
            address token1,
            uint256 amount0,
            uint256 amount1
        ) = this.getPositionTokens(tokenId);

        // get the fees not in the position
        (uint128 collectibleAmount0, uint128 collectibleAmount1) = this
            .getCollectableTokens(tokenId);

        // add them up
        amount0 = amount0.add(collectibleAmount0);
        amount1 = amount1.add(collectibleAmount1);

        // get oracles
        uint256 totalUsd = 0;

        // calculate the amount of token0 in USD
        if (amount0 > 0) {
            AggregatorV3Interface token0Aggr = AggregatorV3Interface(
                oracles[token0]
            );

            (, int256 rate, , , ) = token0Aggr.latestRoundData();

            totalUsd += amount0 * tokenScaleFactor[token0] * uint256(rate);
        }

        // calculate the amount of token1 in USD
        if (amount1 > 0) {
            AggregatorV3Interface token1Aggr = AggregatorV3Interface(
                oracles[token1]
            );

            (, int256 rate, , , ) = token1Aggr.latestRoundData();

            totalUsd += amount1 * tokenScaleFactor[token1] * uint256(rate);
        }

        // chain link quotes are 8 decimals, which is the precision of USDC
        // this token is 18 decimals, so we divide by 1e18 to keep 8 decimals
        return totalUsd / 1e18;
    }

    // returns the total amount of collateral a borrower has 
    // in UniswapV3 positions.
    function getCollateralUsd(address borrower)
        public
        view
        override
        returns (uint256)
    {
        // get total collateral
        uint256 totalCollateral = 0;

        // number of uniswapv3 positions held
        uint256 numberOfAssets = this.balanceOf(borrower);

        // infinite loop
        for (uint256 i = 0; i < numberOfAssets; i++) {
            // get position
            uint256 tokenId = this.tokenOfOwnerByIndex(borrower, i);

            // we calculate the value in usd of this position
            uint256 value = this.getAssetValueUsd(tokenId);

            // don't count anything under the minimum value
            if (value < minDeposit) {
                continue;
            }

            // add it to the total collateral
            totalCollateral += value;
        }

        // we return the total colleral, in USD
        return totalCollateral;
    }

    // deposits a uniswapv3 positions into this 
    // asset class
    function mint(
        // the borrower to receive the asset
        address receiver,
        // the token id to deposit
        uint256 tokenId,
        // callback for the borrower callback (if any)
        bytes memory callback
    ) public whenNotPaused returns (bool) {
        // get the current owner of the position
        address owner = UniswapNftManager.ownerOf(tokenId); // save SLOADs

        // make sure we havn't issued a token for this token before
        if (msg.sender != address(this)) {
            require(owner != address(this), "Position already locked");
        }

        // check that the pool is activated
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = UniswapNftManager.positions(tokenId);

        // get the address of the pool
        address poolAddress = PoolAddress.computeAddress(
            UNISWAP_V3_FACTORY,
            PoolAddress.getPoolKey(token0, token1, fee)
        );

        // check that the pool is activated
        require(activatedPools[poolAddress], "PNA");

        // require that the asset meets the minimum
        require(
            this.getAssetValueUsd(tokenId) >= minDeposit,
            "MINIMUM_DEPOSIT"
        );

        // move it from the manager
        UniswapNftManager.transferFrom(owner, address(this), tokenId);

        // check that we own the nft
        require(UniswapNftManager.ownerOf(tokenId) == address(this), "PNO");

        // mint it to the borrower
        _safeMint(receiver, tokenId);

        // callback
        if (receiver.isContract()) {
            try
                IMerkleCallback(receiver).onMerkleMint(
                    msg.sender,
                    tokenId,
                    receiver,
                    callback
                )
            returns (bytes4 retval) {
                require(
                    retval == IMerkleCallback.onMerkleMint.selector,
                    "ERC721: mint from non IMerkleCallback implementer"
                );
            } catch {
                revert("ERC721: mint from non IMerkleCallback implementer");
            }
        }

        // emit event
        emit Deposit(owner, receiver, tokenId);

        return true;
    }

    // withdraws a uniswapv3 positions from this asset class
    function withdraw(
        // the borrower to receive the asset
        address receiver,
        // the token id to deposit
        uint256 tokenId,
        // callback for the burn callback (if any)
        bytes memory callback
    ) public returns (bool) {
        // get the current owner of the position
        address owner = this.ownerOf(tokenId); // save SLOADs

        // check that caller is authorized
        require(
            isApprovedForAll(owner, msg.sender) ||
                getApproved(tokenId) == msg.sender ||
                owner == msg.sender,
            "Not approved to withdraw"
        );

        // burn the token
        _burn(tokenId);

        // call the callback
        if (receiver.isContract()) {
            // call the callback if it's a contract
            try
                IMerkleCallback(receiver).onMerkleBurn(
                    msg.sender,
                    tokenId,
                    callback
                )
            returns (bytes4 retval) {
                require(
                    retval == IMerkleCallback.onMerkleBurn.selector,
                    "ERC721: burn from non IMerkleCallback implementer"
                );
            } catch {
                revert("ERC721: burn from non IMerkleCallback implementer");
            }
        }

        // require that user is healthy
        require(
            IController(controller).isHealthy(msg.sender),
            "Account is unhealthy"
        );

        // emit withdraw
        emit Withdraw(msg.sender, receiver, owner, tokenId);

        // move it back to the manager
        UniswapNftManager.safeTransferFrom(address(this), receiver, tokenId);

        return true;
    }

    // don't allow transfers of asset class
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        // burning and minting is allowed, but no transfers
        require(
            from == address(0) || to == address(0),
            "Transfer of asset collaterals are prohibited"
        );

        // make sure the position is tracked by enumerable
        super._beforeTokenTransfer(from, to, tokenId);
    }

    // allow stacker to re-invest their fees automatically
    function increateLiquidity(
        INonfungiblePositionManager.IncreaseLiquidityParams memory params
    ) public {
        // only owner of position can collect fees
        require(
            ownerOf(params.tokenId) == msg.sender,
            "Only owner can collect fees"
        );

        // increase liquidity
        UniswapNftManager.increaseLiquidity(params);
    }

    // receive NFTs
    function onERC721Received(
        address /*operator*/,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        // uniswap v3 position manager
        require(
            msg.sender == 0xC36442b4a4522E871399CD717aBDD847Ab11FE88,
            "Wrong sender"
        );

        // deposit the nft
        this.mint(from, tokenId, data);

        return IERC721Receiver.onERC721Received.selector;
    }

    // supporst interface
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // liquidation functions, can only be called by the controller
    // during a sell of assets to cover debt
    function liquidate(
        address borrower,
        address liquidator,
        bytes memory data
    ) public override onlyController {
        // cast the bytes in a token id
        uint256 tokenId = data.toUint256(0);

        // make sure the owner is the borrower
        require(ownerOf(tokenId) == borrower, "Position not minted by owner");

        // move it to the buyer
        UniswapNftManager.safeTransferFrom(address(this), liquidator, tokenId);

        // burn the position in our system
        _burn(tokenId);
    }
}
