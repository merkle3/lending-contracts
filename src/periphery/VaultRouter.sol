// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IERC4626} from './../generics/IERC4626.sol';
import {Multicall} from './../generics/Multicall.sol';
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "../libraries/FixedPointMathLib.sol";

// a router for investing / withdrawing ERC4626 vaults safely
contract VaultRouter is Ownable, Multicall, Pausable {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    // bips router fee (100 = 1%)
    uint routerFeeBips = 0; // no fee by default
    address feeRecipient = 0x0000000000000000000000000000000000000000;

    constructor() {
        // register owner
        transferOwnership(msg.sender);

        // set fee recipient
        feeRecipient = msg.sender;

        // set router fee
        emit FeeRecipientChanged(msg.sender);
    }

    /// events
    event VaultDeposit(address indexed vault, address indexed token, uint256 amount);
    event VaultWithdraw(address indexed vault, address indexed token, uint256 amount);

    // utility events
    event RouterFeeChanged(uint256 routerFeeBips);
    event FeeRecipientChanged(address feeRecipient);

    // ------- ASSET BASED ROUTES -------

    /// @notice Deposit `assets` of underlying token into `vault` and receive `shares` of Vault shares.
    /// @param _vault The address of the Vault to deposit into.
    /// @param assets The amount of underlying token to deposit.
    /// @param receiver The address to receive the Vault shares.
    /// @param minShares The minimum amount of Vault shares to receive.
    /// @param expiry The expiry of the Vault shares.
    /// @return shares The amount of Vault shares received.
    function deposit(address _vault, uint256 assets, address receiver, uint minShares, uint expiry) public virtual whenNotPaused returns(uint256 shares) {
        require(block.timestamp < expiry, "VaultRouter: deposit expired");

        IERC4626 vault = IERC4626(_vault);

        // transfer the assets to the router
        ERC20 token = ERC20(vault.asset());

        // make sure we don't deposit too much
        require(assets <= vault.maxDeposit(receiver), "VaultRouter: deposit too large");

        // transfer to the router
        token.safeTransferFrom(msg.sender, address(this), assets);

        // ---------- FEE PART ---------
        // calculate router fee
        uint256 routerFee = getRouterFeeForAmount(assets);

        if(routerFee > 0) {
            // send fee 
            sendRouterFee(address(token), routerFee);
        }

        // remove fee from assets
        assets = assets - routerFee;
        // ---------- FEE PART ---------

        // approve the vault for the amount to deposit
        token.safeApprove(_vault, assets);

        // deposit the assets
        shares = vault.deposit(assets, receiver);

        // eventing
        emit VaultDeposit(_vault, address(token), assets);

        // make sure we got enough shares
        require(shares >= minShares, "VaultRouter: not enough shares");
    }

    /// @notice Redeem `shares` of Vault shares from `vault` and receive `assets` of underlying token.
    /// @param _vault The address of the Vault to redeem from.
    /// @param shares The amount of Vault shares to redeem.
    /// @param receiver The address to receive the underlying token.
    /// @param minShares The minimum amount of Vault shares to redeem.
    /// @param expiry The expiry of the widthdrawal.
    /// @return shares The amount of vault shares withdrawn.
    function withdraw(address _vault, uint256 assets, address receiver, uint minShares, uint expiry) public virtual whenNotPaused returns(uint256 shares) {
        require(block.timestamp < expiry, "VaultRouter: withdraw expired");

        IERC4626 vault = IERC4626(_vault);

        // make sure we don't withdraw too much
        require(assets <= vault.maxWithdraw(receiver), "VaultRouter: withdraw too large");

        // the vault asset
        ERC20 token = ERC20(vault.asset());

        // withdraw the assets
        shares = vault.withdraw(assets, address(this), msg.sender);

        // make sure we got enough shares
        require(shares >= minShares, "VaultRouter: not enough shares");

        // eventing
        emit VaultWithdraw(_vault, address(token), assets);

        // send the assets to the user
        token.safeTransfer(receiver, assets);
    }

    // ------- SHARES BASED ROUTES -------

    /// @notice Mints `shares` Vault shares to `receiver` by depositing exactly `assets` of underlying tokens.
    /// @param _vault The address of the vault to deposit to
    /// @param shares The number of shares to mint
    /// @param receiver The address to receive the shares
    /// @param maxAssets maximum amount of underlying asset to use.
    /// @param expiry The expiry time of the transaction
    /// @return assets The amount of underlying tokens deposited
    function mint(address _vault, uint256 shares,  address receiver, uint maxAssets, uint expiry) public virtual whenNotPaused returns(uint256 assets) {
        require(block.timestamp < expiry, "VaultRouter: mint expired");

        IERC4626 vault = IERC4626(_vault);

        // make sure we don't exceed the mint ceiling
        require(shares <= vault.maxMint(receiver), "VaultRouter: exceeds max mint");

        // transfer the shares to the router
        ERC20 token = ERC20(vault.asset());

        // figure out how much of the underlying asset we need
        assets = vault.previewMint(shares);

        // check the max assets
        require(assets <= maxAssets, "VaultRouter: maxAssets exceeded");

        // transfer to the router
        token.safeTransferFrom(msg.sender, address(this), assets);

        // ---------- FEE PART ---------
        // calculate router fee
        uint256 routerFee = getRouterFeeForAmount(assets);

        if(routerFee > 0) {
            // send fee 
            sendRouterFee(address(token), routerFee);
        }

        // remove fee from assets
        assets = assets - routerFee;
        // ---------- FEE PART ---------

        // approve the vault for the amount to mint
        token.safeApprove(_vault, assets);

        // mint the shares
        assets = vault.mint(shares, receiver);

        // eventing
        emit VaultDeposit(_vault, address(token), assets);
    }
    
    /// @notice allows the router to redeem shares for underlying assets
    /// @param _vault the vault to redeem from
    /// @param shares the number of shares to redeem
    /// @param minAssets the minimum number of assets to redeem
    /// @param expiry the expiry time of the transaction
    /// @return assets the number of assets redeemed
    function redeem(address _vault, uint256 shares, uint minAssets, uint expiry) public virtual whenNotPaused returns(uint256 assets) {
        require(block.timestamp < expiry, "VaultRouter: redeem expired");

        IERC4626 vault = IERC4626(_vault);

        // make sure we can redeem that many shares
        require(shares <= vault.maxRedeem(msg.sender), "VaultRouter: exceeds max redeem");

        // the vault asset
        ERC20 token = ERC20(vault.asset());

        // redeem the assets
        assets = vault.redeem(shares, address(this), msg.sender);

        // check the min assets
        if (assets < minAssets) {
            revert("VaultRouter: redeem amount less than minAssets");
        }

        // send the assets to the user
        token.safeTransfer(msg.sender, assets);

        // eventing
        emit VaultWithdraw(_vault, address(token), assets);
    }

    /// ------ UTILTY FUNCTIONS --------
    
    /// @notice pause the contract
    function pause() external onlyOwner {
        _pause();
    }
    /// @notice unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice update the router fee
    /// @param _routerFeeBips the new router fee
    function setRouterFee(uint _routerFeeBips) onlyOwner external {
        routerFeeBips = _routerFeeBips;

        emit RouterFeeChanged(routerFeeBips);
    }

    /// @notice update the fee recipient
    /// @param _feeRecipient the new fee recipient
    function setFeeRecipient(address _feeRecipient) onlyOwner external {
        feeRecipient = _feeRecipient;

        emit FeeRecipientChanged(_feeRecipient);
    }

    /// @notice get the fee amount for a given amount
    /// @param amount the amount to calculate the fee for
    /// @return fee the fee amount
    function getRouterFeeForAmount(uint256 amount) internal view returns(uint256 fee) {
        // calculate the fee
        fee = amount.mulDivDown(routerFeeBips, 10000);
    }
    
    /// @notice send the router fee to the fee recipient
    /// @param token the token to send
    /// @param feeAmount the amount to send
    function sendRouterFee(address token, uint256 feeAmount) internal {
        ERC20(token).safeTransfer(feeRecipient, feeAmount);
    }
}