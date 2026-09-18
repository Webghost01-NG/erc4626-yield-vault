// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/YieldVault.sol";
import "./mocks/MockERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract YieldVaultTest is Test {
    YieldVault public vault;
    MockERC20 public asset;

    address public owner = makeAddr("owner");
    address public feeRecipient = makeAddr("feeRecipient");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public attacker = makeAddr("attacker");

    uint256 public constant INITIAL_BALANCE = 1_000_000 ether;
    uint256 public constant FEE_BPS = 1000; // 10%

    function setUp() public {
        asset = new MockERC20("USD Coin", "USDC", 18);

        vm.prank(owner);
        vault = new YieldVault(
            IERC20(address(asset)),
            "Yield Vault USD",
            "yUSDC",
            feeRecipient,
            FEE_BPS
        );

        asset.mint(alice, INITIAL_BALANCE);
        asset.mint(bob, INITIAL_BALANCE);
        asset.mint(attacker, INITIAL_BALANCE);
        asset.mint(owner, INITIAL_BALANCE);

        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(attacker);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(owner);
        asset.approve(address(vault), type(uint256).max);
    }

    function test_FirstDepositAndVirtualOffset() public {
        uint256 depositAmt = 100 ether;
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmt, alice);

        // Due to _decimalsOffset() = 3, shares = assets * 10^3 initially
        assertEq(shares, depositAmt * 1000);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), depositAmt);
    }

    function test_MultipleDepositorsAndProportionalShares() public {
        uint256 depositAmt = 500 ether;

        vm.prank(alice);
        uint256 aliceShares = vault.deposit(depositAmt, alice);

        vm.prank(bob);
        uint256 bobShares = vault.deposit(depositAmt, bob);

        // Without yield, equal deposits yield identical shares
        assertEq(aliceShares, bobShares);
        assertEq(vault.totalAssets(), depositAmt * 2);
    }

    function test_YieldGainsAndPerformanceFee() public {
        uint256 depositAmt = 1_000 ether;
        vm.prank(alice);
        vault.deposit(depositAmt, alice);

        // Simulate 200 ether yield harvested
        uint256 yieldAmt = 200 ether;
        vm.prank(owner);
        (uint256 feeAssets, uint256 feeShares) = vault.harvestYield(yieldAmt);

        // 10% fee on 200 ether = 20 ether
        assertEq(feeAssets, 20 ether);
        assertTrue(feeShares > 0);
        assertEq(vault.balanceOf(feeRecipient), feeShares);

        // Total assets is now deposit + yield
        assertEq(vault.totalAssets(), depositAmt + yieldAmt);

        // Bob deposits after yield: shares should be fewer per asset
        vm.prank(bob);
        uint256 bobShares = vault.deposit(depositAmt, bob);
        assertTrue(bobShares < vault.balanceOf(alice));
    }

    function test_RoundingBoundariesInVaultFavor() public {
        // Vault rounding invariants:
        // previewDeposit: rounds down assets -> shares
        // previewMint: rounds up shares -> assets
        // previewWithdraw: rounds up assets -> shares
        // previewRedeem: rounds down shares -> assets

        vm.prank(alice);
        vault.deposit(1_000 ether, alice);

        // Add some asymmetric yield
        vm.prank(owner);
        vault.harvestYield(333 ether);

        uint256 assetsIn = 7 ether;
        uint256 sharesOut = vault.previewDeposit(assetsIn);
        uint256 assetsNeededToMintShares = vault.previewMint(sharesOut);
        assertTrue(assetsNeededToMintShares <= assetsIn + 1);

        uint256 sharesIn = 1_000;
        uint256 assetsRedeemed = vault.previewRedeem(sharesIn);
        uint256 sharesBurnedForAssets = vault.previewWithdraw(assetsRedeemed);
        assertTrue(sharesBurnedForAssets <= sharesIn + 1);
    }

    function test_InflationAttackResistance() public {
        // Attacker attempts the classic ERC4626 share inflation / donation attack
        // Step 1: Attacker deposits 1 wei
        vm.prank(attacker);
        vault.deposit(1, attacker);

        // Step 2: Attacker donates 1,000 ether directly to the vault to inflate share value
        vm.prank(attacker);
        bool donated = asset.transfer(address(vault), 1_000 ether);
        assertTrue(donated);

        // Step 3: Honest victim deposits 100 ether
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(100 ether, alice);

        // Because of _decimalsOffset() = 3 (1,000 virtual shares),
        // Alice receives meaningful non-zero shares and attacker cannot steal her deposit
        assertTrue(aliceShares > 0);

        // Alice can redeem back her assets close to what she deposited (retaining ~99.5% despite massive 1,000 ether inflation attempt)
        vm.prank(alice);
        uint256 redeemedAssets = vault.redeem(aliceShares, alice, alice);
        assertApproxEqAbs(redeemedAssets, 100 ether, 1 ether);
    }

    function test_ZeroAmountReverts() public {
        vm.startPrank(alice);

        vm.expectRevert(YieldVault.ZeroAssets.selector);
        vault.deposit(0, alice);

        vm.expectRevert(YieldVault.ZeroShares.selector);
        vault.mint(0, alice);

        vm.expectRevert(YieldVault.ZeroAssets.selector);
        vault.withdraw(0, alice, alice);

        vm.expectRevert(YieldVault.ZeroShares.selector);
        vault.redeem(0, alice, alice);

        vm.stopPrank();
    }

    function test_OverWithdrawalAndOverRedeemReverts() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(100 ether, alice);

        // Over-withdrawal
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(YieldVault.ExceedsMaxWithdraw.selector, 101 ether, 100 ether)
        );
        vault.withdraw(101 ether, alice, alice);

        // Over-redeem
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(YieldVault.ExceedsMaxRedeem.selector, shares + 1, shares)
        );
        vault.redeem(shares + 1, alice, alice);
    }

    function test_FeeParameterControls() public {
        // Excessive fee (> 30%)
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.ExcessiveFee.selector, 3500, 3000));
        vault.setFeeParameters(feeRecipient, 3500);

        // Zero address fee recipient
        vm.prank(owner);
        vm.expectRevert(YieldVault.ZeroAddress.selector);
        vault.setFeeParameters(address(0), 1000);

        // Unauthorized caller
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vault.setFeeParameters(feeRecipient, 500);

        // Valid update
        vm.prank(owner);
        vault.setFeeParameters(alice, 2000);
        assertEq(vault.feeRecipient(), alice);
        assertEq(vault.feeBasisPoints(), 2000);
    }

    function testFuzz_DepositAndRedeem(uint128 depositAmount) public {
        vm.assume(depositAmount >= 1000 && depositAmount <= 100_000 ether);

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        vm.prank(alice);
        uint256 assetsReceived = vault.redeem(shares, alice, alice);

        // Assets received must never exceed deposited amount (no free assets created)
        assertTrue(assetsReceived <= depositAmount);
        // Due to rounding in vault favor, received is at most 1 wei less
        assertApproxEqAbs(assetsReceived, depositAmount, 2);
    }
}
