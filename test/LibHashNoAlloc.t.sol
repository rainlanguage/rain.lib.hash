// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibHashNoAlloc, HASH_NIL} from "../src/LibHashNoAlloc.sol";
import {LibHashSlow} from "./LibHashSlow.sol";

/// Each library function against the `LibHashSlow` builtin oracle, the
/// `HASH_NIL` identities for every empty input, that no function changes the
/// free memory pointer at `0x40` or the zero slot at `0x60`, and that the word
/// and combine hashes cost less than encoding the same data then hashing it.
contract LibHashNoAllocTest is Test {
    /// `HASH_NIL` is the hash of no bytes at all: `keccak256` over an empty
    /// range, and the builtin hash of the empty string.
    function testHashNil() public pure {
        bytes32 hashNil;
        assembly ("memory-safe") {
            hashNil := keccak256(0, 0)
        }
        assertEq(HASH_NIL, hashNil);
        assertEq(HASH_NIL, keccak256(""));
    }

    /// `hashBytes` of any bytes is the builtin hash of those same bytes.
    function testHashBytes(bytes memory bs) public pure {
        assertEq(LibHashNoAlloc.hashBytes(bs), LibHashSlow.hashBytesSlow(bs));
    }

    /// `hashBytes` of empty bytes is `HASH_NIL`.
    function testHashBytesEmpty() public pure {
        assertEq(LibHashNoAlloc.hashBytes(""), HASH_NIL);
    }

    /// `hashBytes` leaves `0x40` and `0x60` unchanged, and hashes `"abc"` to a
    /// fixed value.
    function testHashBytesNoAlloc() public pure {
        bytes memory data = "abc";
        uint256 freeMemoryPointerBefore;
        uint256 zeroSlotBefore;
        assembly ("memory-safe") {
            freeMemoryPointerBefore := mload(0x40)
            zeroSlotBefore := mload(0x60)
        }
        bytes32 hash = LibHashNoAlloc.hashBytes(data);
        uint256 freeMemoryPointerAfter;
        uint256 zeroSlotAfter;
        assembly ("memory-safe") {
            freeMemoryPointerAfter := mload(0x40)
            zeroSlotAfter := mload(0x60)
        }
        assertEq(freeMemoryPointerAfter, freeMemoryPointerBefore);
        assertEq(zeroSlotAfter, zeroSlotBefore);
        assertEq(hash, bytes32(0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45));
    }

    /// `hashWords` of a `bytes32[]` is the hash of the packed words, with the
    /// length word excluded.
    function testHashWords(bytes32[] memory words) public pure {
        assertEq(LibHashNoAlloc.hashWords(words), LibHashSlow.hashWordsSlow(words));
    }

    /// The `uint256[]` overload hashes the same packed words as the `bytes32[]`
    /// one.
    function testHashWordsUint256(uint256[] memory words) public pure {
        assertEq(LibHashNoAlloc.hashWords(words), LibHashSlow.hashWordsSlow(words));
    }

    /// `hashWords` of an empty `uint256[]` is `HASH_NIL`.
    function testHashWordsUint256Empty() public pure {
        assertEq(LibHashNoAlloc.hashWords(new uint256[](0)), HASH_NIL);
    }

    /// `hashWords` over a `uint256[]` leaves `0x40` and `0x60` unchanged, and
    /// hashes `[1, 2]` to a fixed value.
    function testHashWordsUint256NoAlloc() public pure {
        uint256[] memory words = new uint256[](2);
        words[0] = 1;
        words[1] = 2;
        uint256 freeMemoryPointerBefore;
        uint256 zeroSlotBefore;
        assembly ("memory-safe") {
            freeMemoryPointerBefore := mload(0x40)
            zeroSlotBefore := mload(0x60)
        }
        bytes32 hash = LibHashNoAlloc.hashWords(words);
        uint256 freeMemoryPointerAfter;
        uint256 zeroSlotAfter;
        assembly ("memory-safe") {
            freeMemoryPointerAfter := mload(0x40)
            zeroSlotAfter := mload(0x60)
        }
        assertEq(freeMemoryPointerAfter, freeMemoryPointerBefore);
        assertEq(zeroSlotAfter, zeroSlotBefore);
        assertEq(hash, bytes32(0xe90b7bceb6e7df5418fb78d8ee546e97c83a08bbccc01a0644d599ccd2a7c2e0));
    }

    /// `hashWords` of an empty `bytes32[]` is `HASH_NIL`.
    function testHashWordsEmpty() public pure {
        assertEq(LibHashNoAlloc.hashWords(new bytes32[](0)), HASH_NIL);
    }

    /// `hashWords` over a `bytes32[]` leaves `0x40` and `0x60` unchanged, and
    /// hashes `[1, 2]` to the same fixed value as the `uint256[]` overload.
    function testHashWordsNoAlloc() public pure {
        bytes32[] memory words = new bytes32[](2);
        words[0] = bytes32(uint256(1));
        words[1] = bytes32(uint256(2));
        uint256 freeMemoryPointerBefore;
        uint256 zeroSlotBefore;
        assembly ("memory-safe") {
            freeMemoryPointerBefore := mload(0x40)
            zeroSlotBefore := mload(0x60)
        }
        bytes32 hash = LibHashNoAlloc.hashWords(words);
        uint256 freeMemoryPointerAfter;
        uint256 zeroSlotAfter;
        assembly ("memory-safe") {
            freeMemoryPointerAfter := mload(0x40)
            zeroSlotAfter := mload(0x60)
        }
        assertEq(freeMemoryPointerAfter, freeMemoryPointerBefore);
        assertEq(zeroSlotAfter, zeroSlotBefore);
        assertEq(hash, bytes32(0xe90b7bceb6e7df5418fb78d8ee546e97c83a08bbccc01a0644d599ccd2a7c2e0));
    }

    /// Measures both hashes of the same words by gasleft() delta so the
    /// comparison is independent of the test contract's dispatcher. Both
    /// results are asserted equal so neither hash can be optimised away, and
    /// the no-alloc delta must at least cover a KECCAK256 (30 gas) so the
    /// window provably contains the hash.
    function checkHashWordsCheaperThanSlow(bytes32[] memory words) internal view {
        uint256 gasBefore = gasleft();
        bytes32 hash = LibHashNoAlloc.hashWords(words);
        uint256 gasNoAlloc = gasBefore - gasleft();
        gasBefore = gasleft();
        bytes32 hashSlow = LibHashSlow.hashWordsSlow(words);
        uint256 gasSlow = gasBefore - gasleft();
        assertEq(hash, hashSlow);
        assertGe(gasNoAlloc, 30);
        assertLt(gasNoAlloc, gasSlow);
    }

    /// Hashing an arbitrary `bytes32[]` in place costs less than packing the
    /// same words into a fresh allocation then hashing it.
    function testHashWordsGas(bytes32[] memory words) public view {
        checkHashWordsCheaperThanSlow(words);
    }

    /// The saving holds at the shortest input, an empty array, where the
    /// encoding allocates a copy of no words at all.
    function testHashWordsGasEmpty() public view {
        checkHashWordsCheaperThanSlow(new bytes32[](0));
    }

    /// `combineHashes(a, b)` is the hash of the two hashes packed in order.
    function testCombineHashes(bytes32 a, bytes32 b) public pure {
        assertEq(LibHashNoAlloc.combineHashes(a, b), LibHashSlow.combineHashesSlow(a, b));
    }

    /// `combineHashes` hashes through scratch space: `0x40` and `0x60` are
    /// unchanged, and `(1, 2)` hashes to a fixed value.
    function testCombineHashesNoAlloc() public pure {
        uint256 freeMemoryPointerBefore;
        uint256 zeroSlotBefore;
        assembly ("memory-safe") {
            freeMemoryPointerBefore := mload(0x40)
            zeroSlotBefore := mload(0x60)
        }
        bytes32 hash = LibHashNoAlloc.combineHashes(bytes32(uint256(1)), bytes32(uint256(2)));
        uint256 freeMemoryPointerAfter;
        uint256 zeroSlotAfter;
        assembly ("memory-safe") {
            freeMemoryPointerAfter := mload(0x40)
            zeroSlotAfter := mload(0x60)
        }
        assertEq(freeMemoryPointerAfter, freeMemoryPointerBefore);
        assertEq(zeroSlotAfter, zeroSlotBefore);
        assertEq(hash, bytes32(0xe90b7bceb6e7df5418fb78d8ee546e97c83a08bbccc01a0644d599ccd2a7c2e0));
    }

    /// Combining two hashes in scratch space costs less than packing them into
    /// a fresh 64 byte allocation then hashing it. Same gasleft() delta
    /// comparison as checkHashWordsCheaperThanSlow.
    function testCombineHashesGas() public view {
        bytes32 a = bytes32(uint256(1));
        bytes32 b = bytes32(uint256(2));
        uint256 gasBefore = gasleft();
        bytes32 hash = LibHashNoAlloc.combineHashes(a, b);
        uint256 gasNoAlloc = gasBefore - gasleft();
        gasBefore = gasleft();
        bytes32 hashSlow = LibHashSlow.combineHashesSlow(a, b);
        uint256 gasSlow = gasBefore - gasleft();
        assertEq(hash, hashSlow);
        assertGe(gasNoAlloc, 30);
        assertLt(gasNoAlloc, gasSlow);
    }
}
