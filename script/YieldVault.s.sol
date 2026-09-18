// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/YieldVault.sol";
import "../test/mocks/MockERC20.sol";

contract DeployYieldVault is Script {
    function run() external returns (YieldVault vault, MockERC20 asset) {
        vm.startBroadcast();

        asset = new MockERC20("Mock USD", "mUSD", 18);
        address feeRecipient = msg.sender;
        uint256 feeBps = 1000; // 10%

        vault = new YieldVault(
            IERC20(address(asset)),
            "Vault Yield Share",
            "vyUSD",
            feeRecipient,
            feeBps
        );

        vm.stopBroadcast();
    }
}
