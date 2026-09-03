// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibHashNoAlloc, HASH_NIL, HASH_WORDS_MAX_LENGTH, HashWordsLengthOverflow} from "../src/LibHashNoAlloc.sol";
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

    function testHashBytesGas0() public pure {
        LibHashNoAlloc.hashBytes("");
    }

    function testHashBytesGasSlow0() public pure {
        LibHashSlow.hashBytesSlow("");
    }

    function testHashBytesGas1() public pure {
        LibHashNoAlloc.hashBytes(new bytes(0x200));
    }

    function testHashBytesGasSlow1() public pure {
        LibHashSlow.hashBytesSlow(new bytes(0x200));
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

    function testHashWordsGas0() public pure {
        LibHashNoAlloc.hashWords(new bytes32[](0));
    }

    function testHashWordsGasSlow0() public pure {
        LibHashSlow.hashWordsSlow(new bytes32[](0));
    }

    function testHashWordsGas1() public pure {
        LibHashNoAlloc.hashWords(new bytes32[](20));
    }

    function testHashWordsGasSlow1() public pure {
        LibHashSlow.hashWordsSlow(new bytes32[](20));
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

    function testCombineHashesGas0() public pure {
        LibHashNoAlloc.combineHashes(bytes32(uint256(1)), bytes32(uint256(2)));
    }

    function testCombineHashesGasSlow0() public pure {
        LibHashSlow.combineHashesSlow(bytes32(uint256(1)), bytes32(uint256(2)));
    }

    /// Forges a `bytes32[]` whose length word is `length` with no elements
    /// allocated behind it, then hashes it. External so the revert is
    /// observable from a call frame.
    function forgedHashWords(uint256 length) external pure returns (bytes32) {
        bytes32[] memory words;
        assembly ("memory-safe") {
            words := mload(0x40)
            mstore(words, length)
            mstore(0x40, add(words, 0x20))
        }
        return LibHashNoAlloc.hashWords(words);
    }

    /// `forgedHashWords` for the `uint256[]` overload.
    function forgedHashWordsUint256(uint256 length) external pure returns (bytes32) {
        uint256[] memory words;
        assembly ("memory-safe") {
            words := mload(0x40)
            mstore(words, length)
            mstore(0x40, add(words, 0x20))
        }
        return LibHashNoAlloc.hashWords(words);
    }

    /// `forgedHashWords` against the reference implementation.
    function forgedHashWordsSlow(uint256 length) external pure returns (bytes32) {
        bytes32[] memory words;
        assembly ("memory-safe") {
            words := mload(0x40)
            mstore(words, length)
            mstore(0x40, add(words, 0x20))
        }
        return LibHashSlow.hashWordsSlow(words);
    }

    function testHashWordsMaxLength() public pure {
        assertEq(HASH_WORDS_MAX_LENGTH, 2 ** 251 - 1);
        unchecked {
            assertEq(HASH_WORDS_MAX_LENGTH * 0x20, type(uint256).max - 0x1f);
            assertEq((HASH_WORDS_MAX_LENGTH + 1) * 0x20, 0);
        }
    }

    /// 2^251 words is the smallest length whose byte size wraps, to exactly 0.
    function testHashWordsLengthWrapsToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(HashWordsLengthOverflow.selector, 2 ** 251));
        this.forgedHashWords(2 ** 251);
    }

    function testHashWordsUint256LengthWrapsToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(HashWordsLengthOverflow.selector, 2 ** 251));
        this.forgedHashWordsUint256(2 ** 251);
    }

    function testHashWordsLengthOverflowReverts(uint256 length) public {
        length = bound(length, HASH_WORDS_MAX_LENGTH + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(HashWordsLengthOverflow.selector, length));
        this.forgedHashWords(length);
    }

    function testHashWordsUint256LengthOverflowReverts(uint256 length) public {
        length = bound(length, HASH_WORDS_MAX_LENGTH + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(HashWordsLengthOverflow.selector, length));
        this.forgedHashWordsUint256(length);
    }

    /// The largest accepted length passes the guard: `keccak256` then fails
    /// on memory expansion (out of gas, no return data), not on the guard.
    function testHashWordsMaxLengthPassesGuard() public {
        (bool success, bytes memory data) =
            address(this).call{gas: 1_000_000}(abi.encodeCall(this.forgedHashWords, (HASH_WORDS_MAX_LENGTH)));
        assertTrue(!success);
        assertEq(data.length, 0);
        (success, data) =
            address(this).call{gas: 1_000_000}(abi.encodeCall(this.forgedHashWordsUint256, (HASH_WORDS_MAX_LENGTH)));
        assertTrue(!success);
        assertEq(data.length, 0);
    }

    /// Neither `hashWords` nor the reference implementation yields a hash for
    /// a length word whose byte size wraps.
    function testHashWordsLengthOverflowMatchesReference() public {
        (bool fast,) = address(this).call{gas: 1_000_000}(abi.encodeCall(this.forgedHashWords, (2 ** 251)));
        (bool slow,) = address(this).call{gas: 1_000_000}(abi.encodeCall(this.forgedHashWordsSlow, (2 ** 251)));
        assertTrue(!fast);
        assertTrue(!slow);
    }
}
