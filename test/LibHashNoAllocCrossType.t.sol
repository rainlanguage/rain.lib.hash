// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibHashNoAlloc, HASH_NIL} from "../src/LibHashNoAlloc.sol";

/// Values of different types whose hashed bytes coincide hash identically.
/// Every assertion here holds because the library hashes raw memory with no
/// type, length or domain tag, and every hash is only comparable with hashes of
/// the same type. Any change that tags leaves, nodes or types breaks these
/// tests and the README "Security of composition" section with them.
contract LibHashNoAllocCrossTypeTest is Test {
    /// A `bytes` leaf whose content is two hashes is the node built from those
    /// hashes: `hashBytes(hash(c) then hash(d))` is `combineHashes(hash(c), hash(d))`.
    function testLeafNodeCollision(bytes memory c, bytes memory d) public pure {
        bytes32 hc = LibHashNoAlloc.hashBytes(c);
        bytes32 hd = LibHashNoAlloc.hashBytes(d);
        bytes memory leaf = abi.encodePacked(hc, hd);
        bytes32 node = LibHashNoAlloc.combineHashes(hc, hd);
        assertEq(LibHashNoAlloc.hashBytes(leaf), node);
        assertEq(node, keccak256(leaf));
    }

    /// The same `32n` bytes hash identically as `bytes`, `bytes32[]` and
    /// `uint256[]`.
    function testBytesWordsCollision(bytes32[] memory words) public pure {
        bytes memory raw = abi.encodePacked(words);
        uint256[] memory uints = new uint256[](words.length);
        for (uint256 i = 0; i < words.length; i++) {
            uints[i] = uint256(words[i]);
        }
        bytes32 expected = keccak256(raw);
        assertEq(LibHashNoAlloc.hashBytes(raw), expected);
        assertEq(LibHashNoAlloc.hashWords(words), expected);
        assertEq(LibHashNoAlloc.hashWords(uints), expected);
    }

    /// Two words hash identically as a static `bytes32[2]` region, a dynamic
    /// `bytes32[]`, the 64 raw bytes, and a `combineHashes` node.
    function testStaticDynamicNodeCollision(bytes32 a, bytes32 b) public pure {
        bytes32[2] memory fixedWords = [a, b];
        bytes32 fixedHash;
        assembly ("memory-safe") {
            fixedHash := keccak256(fixedWords, 0x40)
        }
        bytes32[] memory dynamicWords = new bytes32[](2);
        dynamicWords[0] = a;
        dynamicWords[1] = b;
        bytes32 expected = keccak256(abi.encodePacked(a, b));
        assertEq(fixedHash, expected);
        assertEq(LibHashNoAlloc.hashWords(dynamicWords), expected);
        assertEq(LibHashNoAlloc.hashBytes(abi.encodePacked(a, b)), expected);
        assertEq(LibHashNoAlloc.combineHashes(a, b), expected);
    }

    /// Known answer: the 64 bytes `1` then `2` hash to the same value through
    /// every entry point. The constant is `cast keccak` of those 64 bytes.
    function testWordsOneTwoKnownAnswer() public pure {
        bytes32 expected = 0xe90b7bceb6e7df5418fb78d8ee546e97c83a08bbccc01a0644d599ccd2a7c2e0;
        bytes32[] memory words = new bytes32[](2);
        words[0] = bytes32(uint256(1));
        words[1] = bytes32(uint256(2));
        uint256[] memory uints = new uint256[](2);
        uints[0] = 1;
        uints[1] = 2;
        assertEq(LibHashNoAlloc.hashBytes(abi.encodePacked(uint256(1), uint256(2))), expected);
        assertEq(LibHashNoAlloc.hashWords(words), expected);
        assertEq(LibHashNoAlloc.hashWords(uints), expected);
        assertEq(LibHashNoAlloc.combineHashes(bytes32(uint256(1)), bytes32(uint256(2))), expected);
    }

    /// Empty `bytes`, empty word lists of either type and `HASH_NIL` are all
    /// the hash of zero bytes.
    function testEmptyCollision() public pure {
        assertEq(HASH_NIL, keccak256(""));
        assertEq(LibHashNoAlloc.hashBytes(""), HASH_NIL);
        assertEq(LibHashNoAlloc.hashWords(new bytes32[](0)), HASH_NIL);
        assertEq(LibHashNoAlloc.hashWords(new uint256[](0)), HASH_NIL);
    }
}
