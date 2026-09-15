// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibHashNoAlloc, HASH_NIL} from "../src/LibHashNoAlloc.sol";
import {LibHashSlow} from "./LibHashSlow.sol";

contract LibHashNoAllocTest is Test {
    function testHashNil() public pure {
        bytes32 hashNil;
        assembly ("memory-safe") {
            hashNil := keccak256(0, 0)
        }
        assertEq(HASH_NIL, hashNil);
        assertEq(HASH_NIL, keccak256(""));
    }

    function testHashBytes(bytes memory bs) public pure {
        assertEq(LibHashNoAlloc.hashBytes(bs), LibHashSlow.hashBytesSlow(bs));
    }

    function testHashBytesEmpty() public pure {
        assertEq(LibHashNoAlloc.hashBytes(""), HASH_NIL);
    }

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

    function testHashWords(bytes32[] memory words) public pure {
        assertEq(LibHashNoAlloc.hashWords(words), LibHashSlow.hashWordsSlow(words));
    }

    function testHashWordsUint256(uint256[] memory words) public pure {
        assertEq(LibHashNoAlloc.hashWords(words), LibHashSlow.hashWordsSlow(words));
    }

    function testHashWordsUint256Empty() public pure {
        assertEq(LibHashNoAlloc.hashWords(new uint256[](0)), HASH_NIL);
    }

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

    function testHashWordsEmpty() public pure {
        assertEq(LibHashNoAlloc.hashWords(new bytes32[](0)), HASH_NIL);
    }

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
