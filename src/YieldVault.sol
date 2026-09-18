// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title YieldVault
 * @notice ERC-4626 tokenized vault providing secure share/asset accounting,
 * virtual offset inflation attack defense, reentrancy guards, zero-share deposit rejection,
 * and a documented performance fee mechanism on recognized yield.
 */
contract YieldVault is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MAX_FEE_BPS = 3_000; // 30% maximum fee

    address public feeRecipient;
    uint256 public feeBasisPoints; // e.g., 1000 = 10%
    uint256 public lastReportedTotalAssets;

    // Custom errors
    error ZeroShares();
    error ZeroAssets();
    error ZeroAddress();
    error ExcessiveFee(uint256 feeBps, uint256 maxBps);
    error ExceedsMaxWithdraw(uint256 requested, uint256 maxAllowed);
    error ExceedsMaxRedeem(uint256 requested, uint256 maxAllowed);

    // Events
    event YieldHarvested(uint256 grossYield, uint256 feeAssets, uint256 feeShares);
    event FeeParametersUpdated(address indexed feeRecipient, uint256 feeBasisPoints);

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address feeRecipient_,
        uint256 feeBasisPoints_
    ) ERC4626(asset_) ERC20(name_, symbol_) Ownable(msg.sender) {
        if (feeRecipient_ == address(0)) revert ZeroAddress();
        if (feeBasisPoints_ > MAX_FEE_BPS) revert ExcessiveFee(feeBasisPoints_, MAX_FEE_BPS);

        feeRecipient = feeRecipient_;
        feeBasisPoints = feeBasisPoints_;
    }

    /**
     * @notice Virtual offset of 3 decimal places to mitigate donation / share inflation attacks
     */
    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
    }

    /**
     * @notice Deposit assets into the vault, enforcing non-zero shares and reentrancy protection
     */
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAssets();
        shares = super.deposit(assets, receiver);
        if (shares == 0) revert ZeroShares();
        lastReportedTotalAssets = totalAssets();
    }

    /**
     * @notice Mint exact shares from deposited assets
     */
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroShares();
        assets = super.mint(shares, receiver);
        if (assets == 0) revert ZeroAssets();
        lastReportedTotalAssets = totalAssets();
    }

    /**
     * @notice Withdraw assets by burning shares, rejecting over-withdrawals
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAssets();
        uint256 maxAllowed = maxWithdraw(owner);
        if (assets > maxAllowed) revert ExceedsMaxWithdraw(assets, maxAllowed);

        shares = super.withdraw(assets, receiver, owner);
        lastReportedTotalAssets = totalAssets();
    }

    /**
     * @notice Redeem shares for underlying assets, rejecting over-redemptions
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroShares();
        uint256 maxAllowed = maxRedeem(owner);
        if (shares > maxAllowed) revert ExceedsMaxRedeem(shares, maxAllowed);

        assets = super.redeem(shares, receiver, owner);
        lastReportedTotalAssets = totalAssets();
    }

    /**
     * @notice Harvest and recognize external yield added to the vault, accruing performance fee
     * @param yieldAmount Amount of new underlying asset transferred in as yield
     */
    function harvestYield(uint256 yieldAmount) external nonReentrant returns (uint256 feeAssets, uint256 feeShares) {
        if (yieldAmount == 0) revert ZeroAssets();

        // Pull yield tokens from caller into vault
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), yieldAmount);

        if (feeBasisPoints > 0 && feeRecipient != address(0)) {
            feeAssets = (yieldAmount * feeBasisPoints) / BPS_DENOMINATOR;
            if (feeAssets > 0) {
                // Compute shares for feeAssets before fee shares dilute pool
                feeShares = previewDeposit(feeAssets);
                if (feeShares > 0) {
                    _mint(feeRecipient, feeShares);
                }
            }
        }

        lastReportedTotalAssets = totalAssets();
        emit YieldHarvested(yieldAmount, feeAssets, feeShares);
    }

    /**
     * @notice Update performance fee parameters
     */
    function setFeeParameters(address newRecipient, uint256 newFeeBps) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        if (newFeeBps > MAX_FEE_BPS) revert ExcessiveFee(newFeeBps, MAX_FEE_BPS);

        feeRecipient = newRecipient;
        feeBasisPoints = newFeeBps;
        emit FeeParametersUpdated(newRecipient, newFeeBps);
    }
}
