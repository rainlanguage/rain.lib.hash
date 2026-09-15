// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibHashNoAlloc, HASH_NIL} from "../src/LibHashNoAlloc.sol";
import {LibHashSlow, HASH_ABC, HASH_WORDS_ONE_TWO} from "./LibHashSlow.sol";
import {LibMemorySnapshot} from "./lib/LibMemorySnapshot.sol";

contract LibHashNoAllocTest is Test {
    function testHashNil() public pure {
        bytes32 hashNil;
        assembly ("memory-safe") {
            hashNil := keccak256(0, 0)
        }
        assertEq(HASH_NIL, hashNil);
        assertEq(HASH_NIL, keccak256(""));
    }

    /// Each known answer is the builtin's hash of the preimage its name states,
    /// so a mistyped constant fails here and names which side is wrong.
    function testKnownAnswersAreBuiltinKeccak() public pure {
        assertEq(HASH_ABC, keccak256("abc"));
        assertEq(HASH_WORDS_ONE_TWO, keccak256(abi.encodePacked(uint256(1), uint256(2))));
    }

    function testHashBytes(bytes memory bs) public pure {
        assertEq(LibHashNoAlloc.hashBytes(bs), LibHashSlow.hashBytesSlow(bs));
    }

    function testHashBytesNoAlloc() public pure {
        bytes memory data = "abc";
        uint256 freeMemoryPointerBefore = LibMemorySnapshot.freeMemoryPointer();
        uint256 zeroSlotBefore = LibMemorySnapshot.zeroSlot();
        bytes32 hash = LibHashNoAlloc.hashBytes(data);
        uint256 freeMemoryPointerAfter = LibMemorySnapshot.freeMemoryPointer();
        uint256 zeroSlotAfter = LibMemorySnapshot.zeroSlot();
        assertEq(freeMemoryPointerAfter, freeMemoryPointerBefore);
        assertEq(zeroSlotAfter, zeroSlotBefore);
        assertEq(hash, HASH_ABC);
    }

    function testHashWords(bytes32[] memory words) public pure {
        assertEq(LibHashNoAlloc.hashWords(words), LibHashSlow.hashWordsSlow(words));
    }

    function testHashWordsUint256(uint256[] memory words) public pure {
        assertEq(LibHashNoAlloc.hashWords(words), LibHashSlow.hashWordsSlow(words));
    }

    function testHashWordsUint256NoAlloc() public pure {
        uint256[] memory words = new uint256[](2);
        words[0] = 1;
        words[1] = 2;
        uint256 freeMemoryPointerBefore = LibMemorySnapshot.freeMemoryPointer();
        uint256 zeroSlotBefore = LibMemorySnapshot.zeroSlot();
        bytes32 hash = LibHashNoAlloc.hashWords(words);
        uint256 freeMemoryPointerAfter = LibMemorySnapshot.freeMemoryPointer();
        uint256 zeroSlotAfter = LibMemorySnapshot.zeroSlot();
        assertEq(freeMemoryPointerAfter, freeMemoryPointerBefore);
        assertEq(zeroSlotAfter, zeroSlotBefore);
        assertEq(hash, HASH_WORDS_ONE_TWO);
    }

    function testHashWordsNoAlloc() public pure {
        bytes32[] memory words = new bytes32[](2);
        words[0] = bytes32(uint256(1));
        words[1] = bytes32(uint256(2));
        uint256 freeMemoryPointerBefore = LibMemorySnapshot.freeMemoryPointer();
        uint256 zeroSlotBefore = LibMemorySnapshot.zeroSlot();
        bytes32 hash = LibHashNoAlloc.hashWords(words);
        uint256 freeMemoryPointerAfter = LibMemorySnapshot.freeMemoryPointer();
        uint256 zeroSlotAfter = LibMemorySnapshot.zeroSlot();
        assertEq(freeMemoryPointerAfter, freeMemoryPointerBefore);
        assertEq(zeroSlotAfter, zeroSlotBefore);
        assertEq(hash, HASH_WORDS_ONE_TWO);
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

    function testHashWordsGas(bytes32[] memory words) public view {
        checkHashWordsCheaperThanSlow(words);
    }

    function testHashWordsGasEmpty() public view {
        checkHashWordsCheaperThanSlow(new bytes32[](0));
    }

    function testCombineHashes(bytes32 a, bytes32 b) public pure {
        assertEq(LibHashNoAlloc.combineHashes(a, b), LibHashSlow.combineHashesSlow(a, b));
    }

    function testCombineHashesNoAlloc() public pure {
        uint256 freeMemoryPointerBefore = LibMemorySnapshot.freeMemoryPointer();
        uint256 zeroSlotBefore = LibMemorySnapshot.zeroSlot();
        bytes32 hash = LibHashNoAlloc.combineHashes(bytes32(uint256(1)), bytes32(uint256(2)));
        uint256 freeMemoryPointerAfter = LibMemorySnapshot.freeMemoryPointer();
        uint256 zeroSlotAfter = LibMemorySnapshot.zeroSlot();
        assertEq(freeMemoryPointerAfter, freeMemoryPointerBefore);
        assertEq(zeroSlotAfter, zeroSlotBefore);
        assertEq(hash, HASH_WORDS_ONE_TWO);
    }

    /// Same gasleft() delta comparison as checkHashWordsCheaperThanSlow.
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
