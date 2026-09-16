// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibHashNoAlloc, HASH_NIL} from "../../../src/lib/LibHashNoAlloc.sol";
import {LibHashSlow, HASH_ABC, HASH_WORDS_ONE_TWO} from "../../lib/LibHashSlow.sol";
import {LibMemorySnapshot} from "../../lib/LibMemorySnapshot.sol";

/// @dev Static gas of one KECCAK256 opcode.
uint256 constant KECCAK256_BASE_GAS = 30;

/// @dev Gas KECCAK256 charges per 32 byte word of input.
uint256 constant KECCAK256_WORD_GAS = 6;

contract LibHashNoAllocTest is Test {
    /// Gas a KECCAK256 over `byteLength` bytes costs, excluding any memory
    /// expansion, which no function under test pays.
    function keccak256Gas(uint256 byteLength) internal pure returns (uint256) {
        return KECCAK256_BASE_GAS + KECCAK256_WORD_GAS * ((byteLength + 0x1f) / 0x20);
    }

    /// Equal hashes keep either call from being optimised away. The floor is
    /// the KECCAK256 cost of exactly these bytes, but tens of gas of call
    /// overhead sit in the window too, so meeting the floor does not prove the
    /// hash is inside it; `testHashWordsGasPerWord` proves that.
    function assertNoAllocCheaperThanSlow(
        bytes32 hash,
        uint256 gasNoAlloc,
        bytes32 hashSlow,
        uint256 gasSlow,
        uint256 byteLength
    ) internal pure {
        assertEq(hash, hashSlow);
        assertGe(gasNoAlloc, keccak256Gas(byteLength));
        assertLt(gasNoAlloc, gasSlow);
    }

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

    function testHashBytes(bytes memory data) public pure {
        assertEq(LibHashNoAlloc.hashBytes(data), LibHashSlow.hashBytesSlow(data));
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

    /// `hashBytes` claims to save nothing over the builtin. Equal gas deltas
    /// and an unmoved free memory pointer are that claim, and a solc that began
    /// copying before hashing would break it.
    function checkHashBytesCostsTheSameAsBuiltin(bytes memory data) internal view {
        uint256 freeMemoryPointerBefore;
        assembly ("memory-safe") {
            freeMemoryPointerBefore := mload(0x40)
        }
        uint256 gasBefore = gasleft();
        bytes32 hash = LibHashNoAlloc.hashBytes(data);
        uint256 gasNoAlloc = gasBefore - gasleft();
        gasBefore = gasleft();
        bytes32 hashBuiltin = keccak256(data);
        uint256 gasBuiltin = gasBefore - gasleft();
        uint256 freeMemoryPointerAfter;
        assembly ("memory-safe") {
            freeMemoryPointerAfter := mload(0x40)
        }
        assertEq(hash, hashBuiltin);
        assertEq(freeMemoryPointerAfter, freeMemoryPointerBefore);
        assertGe(gasNoAlloc, keccak256Gas(data.length));
        assertEq(gasNoAlloc, gasBuiltin);
    }

    function testHashBytesCostsTheSameAsBuiltin(bytes memory data) public view {
        checkHashBytesCostsTheSameAsBuiltin(data);
    }

    /// Long enough that a per-word copy would be unmissable in the gas delta.
    function testHashBytesCostsTheSameAsBuiltinLong() public view {
        checkHashBytesCostsTheSameAsBuiltin(new bytes(4096));
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
    /// comparison is independent of the test contract's dispatcher.
    function checkHashWordsCheaperThanSlow(bytes32[] memory words) internal view {
        uint256 gasBefore = gasleft();
        bytes32 hash = LibHashNoAlloc.hashWords(words);
        uint256 gasNoAlloc = gasBefore - gasleft();
        gasBefore = gasleft();
        bytes32 hashSlow = LibHashSlow.hashWordsSlow(words);
        uint256 gasSlow = gasBefore - gasleft();
        assertNoAllocCheaperThanSlow(hash, gasNoAlloc, hashSlow, gasSlow, words.length * 0x20);
    }

    function testHashWordsGas(bytes32[] memory words) public view {
        checkHashWordsCheaperThanSlow(words);
    }

    function testHashWordsGasEmpty() public view {
        checkHashWordsCheaperThanSlow(new bytes32[](0));
    }

    /// The NatSpec quantifies the saving at one and two words, which the
    /// fuzzer is not guaranteed to sample.
    function testHashWordsGasOneWord() public view {
        bytes32[] memory words = new bytes32[](1);
        words[0] = bytes32(uint256(1));
        checkHashWordsCheaperThanSlow(words);
    }

    function testHashWordsGasTwoWords() public view {
        bytes32[] memory words = new bytes32[](2);
        words[0] = bytes32(uint256(1));
        words[1] = bytes32(uint256(2));
        checkHashWordsCheaperThanSlow(words);
    }

    /// Same comparison for the `uint256[]` overload, which is the one importers
    /// call and which no gas assertion covered.
    function checkHashWordsUint256CheaperThanSlow(uint256[] memory words) internal view {
        uint256 gasBefore = gasleft();
        bytes32 hash = LibHashNoAlloc.hashWords(words);
        uint256 gasNoAlloc = gasBefore - gasleft();
        gasBefore = gasleft();
        bytes32 hashSlow = LibHashSlow.hashWordsSlow(words);
        uint256 gasSlow = gasBefore - gasleft();
        assertNoAllocCheaperThanSlow(hash, gasNoAlloc, hashSlow, gasSlow, words.length * 0x20);
    }

    function testHashWordsUint256Gas(uint256[] memory words) public view {
        checkHashWordsUint256CheaperThanSlow(words);
    }

    function testHashWordsUint256GasEmpty() public view {
        checkHashWordsUint256CheaperThanSlow(new uint256[](0));
    }

    /// The KECCAK256 is the only length dependent cost in the window, so the
    /// window's slope is exactly the hash's slope only if the hash is in it.
    function testHashWordsGasPerWord(uint8 shorter, uint8 extra) public view {
        bytes32[] memory shortWords = new bytes32[](shorter);
        bytes32[] memory longWords = new bytes32[](uint256(shorter) + uint256(extra));

        uint256 gasBefore = gasleft();
        bytes32 hashShort = LibHashNoAlloc.hashWords(shortWords);
        uint256 gasShort = gasBefore - gasleft();
        gasBefore = gasleft();
        bytes32 hashLong = LibHashNoAlloc.hashWords(longWords);
        uint256 gasLong = gasBefore - gasleft();

        assertEq(hashShort, LibHashSlow.hashWordsSlow(shortWords));
        assertEq(hashLong, LibHashSlow.hashWordsSlow(longWords));
        assertEq(gasLong - gasShort, KECCAK256_WORD_GAS * uint256(extra));
    }

    /// The NatSpec puts un-inlined call overhead at tens of gas, well under the
    /// saving over abi encoding at one or two words. Nothing else measures the
    /// library against `abi.encode`, and 100 gas is an order of magnitude over
    /// the overhead being discounted.
    function checkSavingExceedsCallOverhead(bytes32[] memory words) internal view {
        uint256 gasBefore = gasleft();
        bytes32 hash = LibHashNoAlloc.hashWords(words);
        uint256 gasNoAlloc = gasBefore - gasleft();
        gasBefore = gasleft();
        bytes32 hashEncode = keccak256(abi.encode(words));
        uint256 gasEncode = gasBefore - gasleft();
        assertTrue(hash != hashEncode);
        assertGe(gasNoAlloc, keccak256Gas(words.length * 0x20));
        assertGt(gasEncode - gasNoAlloc, 100);
    }

    function testHashWordsSavingExceedsCallOverhead(bytes32 a, bytes32 b) public view {
        bytes32[] memory one = new bytes32[](1);
        one[0] = a;
        checkSavingExceedsCallOverhead(one);

        bytes32[] memory two = new bytes32[](2);
        two[0] = a;
        two[1] = b;
        checkSavingExceedsCallOverhead(two);
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

    /// Same gasleft() delta comparison as checkHashWordsCheaperThanSlow, over
    /// the fixed 64 bytes combineHashes hashes through scratch space.
    function testCombineHashesGas() public view {
        bytes32 a = bytes32(uint256(1));
        bytes32 b = bytes32(uint256(2));
        uint256 gasBefore = gasleft();
        bytes32 hash = LibHashNoAlloc.combineHashes(a, b);
        uint256 gasNoAlloc = gasBefore - gasleft();
        gasBefore = gasleft();
        bytes32 hashSlow = LibHashSlow.combineHashesSlow(a, b);
        uint256 gasSlow = gasBefore - gasleft();
        assertNoAllocCheaperThanSlow(hash, gasNoAlloc, hashSlow, gasSlow, 0x40);
    }
}
