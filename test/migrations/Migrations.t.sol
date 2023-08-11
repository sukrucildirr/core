// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import 'forge-std/Test.sol';
import {ForkManagement} from 'test/helpers/ForkManagement.sol';
import {LegacyCollectNFT} from 'contracts/misc/LegacyCollectNFT.sol';
import {LensHub} from 'contracts/LensHub.sol';
import {FollowNFT} from 'contracts/FollowNFT.sol';
import {TransparentUpgradeableProxy} from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {ModuleGlobals} from 'contracts/misc/ModuleGlobals.sol';
import {LensHandles} from 'contracts/namespaces/LensHandles.sol';
import {TokenHandleRegistry} from 'contracts/namespaces/TokenHandleRegistry.sol';
import {Types} from 'contracts/libraries/constants/Types.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {IERC721Enumerable} from '@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol';
import {LensHubInitializable} from 'contracts/misc/LensHubInitializable.sol';
import 'test/Constants.sol';
import 'test/base/BaseTest.t.sol';

contract MigrationsTest is BaseTest {
    TestAccount firstAccount;

    TestAccount secondAccount;

    uint256 followTokenIdV1;

    function beforeUpgrade() internal override {
        firstAccount = _loadAccountAs('FIRST_ACCOUNT');

        secondAccount = _loadAccountAs('SECOND_ACCOUNT');

        vm.prank(firstAccount.owner);
        followTokenIdV1 = IOldHub(address(hub)).follow(_toUint256Array(secondAccount.profileId), _toBytesArray(''))[0];
    }

    function testCannotMigrateFollowIfAlreadyFollowing() public {
        vm.prank(firstAccount.owner);
        uint256 followTokenIdV2 = hub.follow(
            firstAccount.profileId,
            _toUint256Array(secondAccount.profileId),
            _toUint256Array(0),
            _toBytesArray('')
        )[0];

        assertTrue(hub.isFollowing(firstAccount.profileId, secondAccount.profileId));

        FollowNFT followNFT = FollowNFT(hub.getProfile(secondAccount.profileId).followNFT);

        uint256 followTokenV1FollowerProfileId = followNFT.getFollowerProfileId(followTokenIdV1);
        uint256 followTokenV2FollowerProfileId = followNFT.getFollowerProfileId(followTokenIdV2);
        uint256 followTokenIdUsedByFirstAccount = followNFT.getFollowTokenId(firstAccount.profileId);
        uint256 originalFollowTimestampTokenV1 = followNFT.getOriginalFollowTimestamp(followTokenIdV1);
        uint256 originalFollowTimestampTokenV2 = followNFT.getOriginalFollowTimestamp(followTokenIdV2);

        assertEq(followTokenV1FollowerProfileId, 0);
        assertEq(followTokenV2FollowerProfileId, firstAccount.profileId);
        assertEq(followTokenIdUsedByFirstAccount, followTokenIdV2);
        assertEq(originalFollowTimestampTokenV1, 0);
        assertEq(originalFollowTimestampTokenV2, block.timestamp);

        hub.batchMigrateFollows({
            followerProfileIds: _toUint256Array(firstAccount.profileId),
            idsOfProfileFollowed: _toUint256Array(secondAccount.profileId),
            followTokenIds: _toUint256Array(followTokenIdV1)
        });

        // Migration did not take effect as it was already following, values are the same as before.
        assertEq(followNFT.getFollowerProfileId(followTokenIdV1), followTokenV1FollowerProfileId);
        assertEq(followNFT.getFollowerProfileId(followTokenIdV2), followTokenV2FollowerProfileId);
        assertEq(followNFT.getFollowTokenId(firstAccount.profileId), followTokenIdUsedByFirstAccount);
        assertEq(followNFT.getOriginalFollowTimestamp(followTokenIdV1), originalFollowTimestampTokenV1);
        assertEq(followNFT.getOriginalFollowTimestamp(followTokenIdV2), originalFollowTimestampTokenV2);
    }

    function testCannotMigrateFollowIfBlocked() public {
        vm.prank(secondAccount.owner);
        hub.setBlockStatus(secondAccount.profileId, _toUint256Array(firstAccount.profileId), _toBoolArray(true));

        FollowNFT followNFT = FollowNFT(hub.getProfile(secondAccount.profileId).followNFT);

        uint256 followTokenV1FollowerProfileId = followNFT.getFollowerProfileId(followTokenIdV1);
        uint256 followTokenIdUsedByFirstAccount = followNFT.getFollowTokenId(firstAccount.profileId);
        uint256 originalFollowTimestampTokenV1 = followNFT.getOriginalFollowTimestamp(followTokenIdV1);

        assertEq(followTokenV1FollowerProfileId, 0);
        assertEq(followTokenIdUsedByFirstAccount, 0);
        assertEq(originalFollowTimestampTokenV1, 0);

        hub.batchMigrateFollows({
            followerProfileIds: _toUint256Array(firstAccount.profileId),
            idsOfProfileFollowed: _toUint256Array(secondAccount.profileId),
            followTokenIds: _toUint256Array(followTokenIdV1)
        });

        // Migration did not take effect as it was already following, values are the same as before.
        assertEq(followNFT.getFollowerProfileId(followTokenIdV1), followTokenV1FollowerProfileId);
        assertEq(followNFT.getFollowTokenId(firstAccount.profileId), followTokenIdUsedByFirstAccount);
        assertEq(followNFT.getOriginalFollowTimestamp(followTokenIdV1), originalFollowTimestampTokenV1);
    }

    function testCannotMigrateFollowIfSelfFollow() public {
        FollowNFT followNFT = FollowNFT(hub.getProfile(secondAccount.profileId).followNFT);
        vm.prank(firstAccount.owner);
        followNFT.transferFrom(firstAccount.owner, secondAccount.owner, followTokenIdV1);
        assertEq(followNFT.ownerOf(followTokenIdV1), secondAccount.owner);

        uint256 followTokenV1FollowerProfileId = followNFT.getFollowerProfileId(followTokenIdV1);
        uint256 followTokenIdUsedByFirstAccount = followNFT.getFollowTokenId(firstAccount.profileId);
        uint256 originalFollowTimestampTokenV1 = followNFT.getOriginalFollowTimestamp(followTokenIdV1);

        assertEq(followTokenV1FollowerProfileId, 0);
        assertEq(followTokenIdUsedByFirstAccount, 0);
        assertEq(originalFollowTimestampTokenV1, 0);

        hub.batchMigrateFollows({
            followerProfileIds: _toUint256Array(secondAccount.profileId),
            idsOfProfileFollowed: _toUint256Array(secondAccount.profileId),
            followTokenIds: _toUint256Array(followTokenIdV1)
        });

        // Migration did not take effect as it was already following, values are the same as before.
        assertEq(followNFT.getFollowerProfileId(followTokenIdV1), followTokenV1FollowerProfileId);
        assertEq(followNFT.getFollowTokenId(firstAccount.profileId), followTokenIdUsedByFirstAccount);
        assertEq(followNFT.getOriginalFollowTimestamp(followTokenIdV1), originalFollowTimestampTokenV1);
    }
}

contract MigrationsTestHardcoded is Test, ForkManagement {
    using stdJson for string;

    uint256 internal constant LENS_PROTOCOL_PROFILE_ID = 1;
    uint256 internal constant ENUMERABLE_GET_FIRST_PROFILE = 0;

    address owner = address(0x087E4);

    uint256[] followerProfileIds = new uint256[](10);

    function loadBaseAddresses(string memory targetEnv) internal virtual {
        console.log('targetEnv:', targetEnv);

        hubProxyAddr = json.readAddress(string(abi.encodePacked('.', targetEnv, '.LensHubProxy')));
        console.log('hubProxyAddr:', hubProxyAddr);

        hub = LensHub(hubProxyAddr);

        console.log('Hub:', address(hub));

        // address followNFTAddr = hub.getFollowNFTImpl();
        address legacyCollectNFTAddr = hub.getCollectNFTImpl();

        address hubImplAddr = address(uint160(uint256(vm.load(hubProxyAddr, PROXY_IMPLEMENTATION_STORAGE_SLOT))));
        console.log('Found hubImplAddr:', hubImplAddr);

        proxyAdmin = address(uint160(uint256(vm.load(hubProxyAddr, ADMIN_SLOT))));

        legacyCollectNFT = LegacyCollectNFT(legacyCollectNFTAddr);
        hubAsProxy = TransparentUpgradeableProxy(payable(address(hub)));
        moduleGlobals = ModuleGlobals(json.readAddress(string(abi.encodePacked('.', targetEnv, '.ModuleGlobals'))));

        governance = hub.getGovernance();
        modulesGovernance = moduleGlobals.getGovernance();
    }

    function setUp() public override {
        super.setUp();

        // This should be tested only on Fork
        if (!fork) return;

        loadBaseAddresses(forkEnv);

        // Precompute needed addresses.
        address lensHandlesAddress = computeCreateAddress(deployer, 0);
        address tokenHandleRegistryAddress = computeCreateAddress(deployer, 1);

        console.log('lensHandlesAddress:', lensHandlesAddress);
        console.log('tokenHandleRegistryAddress:', tokenHandleRegistryAddress);

        vm.startPrank(deployer);

        lensHandles = new LensHandles(owner, address(hub), HANDLE_GUARDIAN_COOLDOWN);
        assertEq(address(lensHandles), lensHandlesAddress);

        tokenHandleRegistry = new TokenHandleRegistry(address(hub), lensHandlesAddress);
        assertEq(address(tokenHandleRegistry), tokenHandleRegistryAddress);

        followNFT = new FollowNFT(address(hub));

        // TODO: Last 3 addresses are for the follow modules for migration purposes.
        hubImpl = new LensHubInitializable({
            moduleGlobals: address(0),
            followNFTImpl: address(followNFT),
            collectNFTImpl: address(legacyCollectNFT),
            lensHandlesAddress: lensHandlesAddress,
            tokenHandleRegistryAddress: tokenHandleRegistryAddress,
            legacyFeeFollowModule: address(0),
            legacyProfileFollowModule: address(0),
            newFeeFollowModule: address(0),
            tokenGuardianCooldown: PROFILE_GUARDIAN_COOLDOWN
        });

        vm.stopPrank();

        // TODO: This can be moved and split
        uint256 idOfProfileFollowed = 8;
        address followNFTAddress = IOldHub(address(hub)).getProfile(idOfProfileFollowed).followNFT;
        for (uint256 i = 0; i < 10; i++) {
            uint256 followTokenId = i + 1;
            address followerOwner = IERC721(followNFTAddress).ownerOf(followTokenId);
            uint256 followerProfileId = IERC721Enumerable(address(hub)).tokenOfOwnerByIndex(
                followerOwner,
                ENUMERABLE_GET_FIRST_PROFILE
            );
            followerProfileIds[i] = followerProfileId;
        }

        // TODO: Upgrade can be moved to a separate function
        vm.prank(proxyAdmin);
        hubAsProxy.upgradeTo(address(hubImpl));
    }

    function testProfileMigration() public onlyFork {
        uint256[] memory profileIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            profileIds[i] = i + 1;
        }
        hub.batchMigrateProfiles(profileIds);
    }

    function testFollowMigration() public onlyFork {
        uint256 idOfProfileFollowed = 8;

        uint256[] memory idsOfProfileFollowed = new uint256[](10);
        uint256[] memory followTokenIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            uint256 followTokenId = i + 1;

            idsOfProfileFollowed[i] = idOfProfileFollowed;
            followTokenIds[i] = followTokenId;
        }

        hub.batchMigrateFollows(followerProfileIds, idsOfProfileFollowed, followTokenIds);
    }

    function testFollowMigration_byHubFollow() public onlyFork {
        uint256 followerProfileId = 8;

        uint256[] memory idsOfProfilesToFollow = new uint256[](1);
        idsOfProfilesToFollow[0] = 92973;

        bytes[] memory datas = new bytes[](1);
        datas[0] = '';

        uint256[] memory followTokenIds = new uint256[](1);
        followTokenIds[0] = 1;

        vm.prank(hub.ownerOf(followerProfileId));
        hub.follow(followerProfileId, idsOfProfilesToFollow, followTokenIds, datas);

        address targetFollowNFT = hub.getProfile(idsOfProfilesToFollow[0]).followNFT;

        vm.prank(hub.ownerOf(followerProfileId));
        FollowNFT(targetFollowNFT).unwrap(followTokenIds[0]);
    }
}
