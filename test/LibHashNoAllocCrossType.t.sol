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

    function slice(bytes memory data, uint256 start, uint256 end) internal pure returns (bytes memory) {
        bytes memory out = new bytes(end - start);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = data[start + i];
        }
        return out;
    }

    function testCompositionSeparatesPackedCollision(bytes memory s, uint256 i, uint256 j) public pure {
        uint256 n = s.length;
        vm.assume(n > 0);
        uint256 x = i % (n + 1);
        uint256 y = j % n;
        if (y >= x) {
            y = y + 1;
        }

        bytes memory leftX = slice(s, 0, x);
        bytes memory rightX = slice(s, x, n);
        bytes memory leftY = slice(s, 0, y);
        bytes memory rightY = slice(s, y, n);

        assertEq(abi.encodePacked(leftX, rightX), s);
        assertEq(abi.encodePacked(leftY, rightY), s);

        assertTrue(keccak256(abi.encode(leftX, rightX)) != keccak256(abi.encode(leftY, rightY)));

        bytes32 composedX =
            LibHashNoAlloc.combineHashes(LibHashNoAlloc.hashBytes(leftX), LibHashNoAlloc.hashBytes(rightX));
        bytes32 composedY =
            LibHashNoAlloc.combineHashes(LibHashNoAlloc.hashBytes(leftY), LibHashNoAlloc.hashBytes(rightY));
        assertTrue(composedX != composedY);
    }

    function testCompositionSeparatesAbcDef() public pure {
        assertEq(abi.encodePacked(bytes("abc"), bytes("def")), abi.encodePacked(bytes("ab"), bytes("cdef")));
        assertTrue(
            keccak256(abi.encode(bytes("abc"), bytes("def"))) != keccak256(abi.encode(bytes("ab"), bytes("cdef")))
        );

        // keccak256("abc"), keccak256("def"), keccak256("ab"), keccak256("cdef").
        bytes32 hashAbc = 0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45;
        bytes32 hashDef = 0x34607c9bbfeb9c23509680f04363f298fdb0b5f9abe327304ecd1daca08cda9c;
        bytes32 hashAb = 0x67fad3bfa1e0321bd021ca805ce14876e50acac8ca8532eda8cbf924da565160;
        bytes32 hashCdef = 0xf97c40c9cdc009ac73cff1d514c11857db9ab190abd825bbcd5ad0b64185e180;
        assertEq(LibHashNoAlloc.hashBytes("abc"), hashAbc);
        assertEq(LibHashNoAlloc.hashBytes("def"), hashDef);
        assertEq(LibHashNoAlloc.hashBytes("ab"), hashAb);
        assertEq(LibHashNoAlloc.hashBytes("cdef"), hashCdef);

        // keccak256 of each pair of the hashes above concatenated.
        bytes32 composedAbcDef = 0x7383ca1a5e9358bfdeb8ed45f93766b2d3b60ad70d2489697d5b284570655c7f;
        bytes32 composedAbCdef = 0x598e38d92add51cae619e07a954bc21a719abfc1dfc0beeeb0efeb5ffaee3612;
        assertEq(LibHashNoAlloc.combineHashes(hashAbc, hashDef), composedAbcDef);
        assertEq(LibHashNoAlloc.combineHashes(hashAb, hashCdef), composedAbCdef);
        assertTrue(composedAbcDef != composedAbCdef);
    }

    function testSingletonWordListIsItsWord(bytes32 x) public pure {
        bytes32[] memory words = new bytes32[](1);
        words[0] = x;
        uint256[] memory uints = new uint256[](1);
        uints[0] = uint256(x);
        bytes32[1] memory staticWord = [x];
        bytes32 staticHash;
        assembly ("memory-safe") {
            staticHash := keccak256(staticWord, 0x20)
        }

        bytes32 expected = keccak256(abi.encodePacked(x));
        assertEq(LibHashNoAlloc.hashWords(words), expected);
        assertEq(LibHashNoAlloc.hashWords(uints), expected);
        assertEq(LibHashNoAlloc.hashBytes(abi.encodePacked(x)), expected);
        assertEq(staticHash, expected);
        assertTrue(expected != LibHashNoAlloc.combineHashes(HASH_NIL, expected));
    }
}
