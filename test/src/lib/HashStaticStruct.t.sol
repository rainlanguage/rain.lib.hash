// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibMemorySnapshot} from "../../lib/LibMemorySnapshot.sol";

/// The struct the LibHashNoAlloc NatSpec hashes in its example: three static
/// members, the last of them sub-word.
struct Header {
    uint256 a;
    address b;
    uint32 c;
}

/// Every claim the LibHashNoAlloc NatSpec makes about hashing a static struct
/// in place: its `keccak256(header, 0x60)` example, the 3-word size the 0x60
/// comes from, and that `abi.encode` allocates a length word plus those three
/// words and costs more on its own than the whole in-place hash. The oracles
/// are `abi.encode` and the free memory pointer; neither is the assembly under
/// test.
contract HashStaticStructTest is Test {
    /// Hashing the three words where they already sit gives the hash of the ABI
    /// encoding of the same three values, and of the struct itself: every
    /// member is static, so the encoding is those three words with no head or
    /// tail. A sub-word member is a full word in both.
    function testStaticStructInPlaceHashIsAbiEncodeHash(uint256 a, address b, uint32 c) public pure {
        Header memory header = Header(a, b, c);
        bytes32 hash;
        assembly ("memory-safe") {
            hash := keccak256(header, 0x60)
        }
        assertEq(hash, keccak256(abi.encode(a, b, c)));
        assertEq(hash, keccak256(abi.encode(header)));
    }

    /// Where the 0x60 comes from: a `Header` is allocated at the free memory
    /// pointer and bumps it by exactly three words, whatever its members hold.
    function testStaticStructIsThreeWords(uint256 a, address b, uint32 c) public pure {
        uint256 fmpBefore = LibMemorySnapshot.freeMemoryPointer();
        Header memory header = Header(a, b, c);
        uint256 fmpAfter = LibMemorySnapshot.freeMemoryPointer();
        uint256 pointer;
        assembly ("memory-safe") {
            pointer := header
        }
        assertEq(pointer, fmpBefore);
        assertEq(fmpAfter - pointer, 0x60);
    }

    /// The in-place hash allocates nothing, `abi.encode` of the same struct
    /// allocates 0x80 for a 0x60 encoding because of the `bytes` length word,
    /// and the encoding step alone costs more gas than the whole in-place hash.
    /// The floor on the in-place measurement fails if the hash is optimised
    /// away instead of being cheap.
    function testEncodingAloneCostsMoreThanInPlaceHash(uint256 a, address b, uint32 c) public view {
        Header memory header = Header(a, b, c);
        uint256 fmp0 = LibMemorySnapshot.freeMemoryPointer();

        uint256 gasBefore = gasleft();
        bytes32 hash;
        assembly ("memory-safe") {
            hash := keccak256(header, 0x60)
        }
        uint256 gasInPlace = gasBefore - gasleft();
        uint256 fmp1 = LibMemorySnapshot.freeMemoryPointer();

        gasBefore = gasleft();
        bytes memory encoded = abi.encode(header);
        uint256 gasEncodeOnly = gasBefore - gasleft();
        uint256 fmp2 = LibMemorySnapshot.freeMemoryPointer();

        assertEq(fmp1, fmp0);
        assertEq(fmp2 - fmp1, LibMemorySnapshot.wordAlignedAllocation(0x60));
        assertEq(encoded.length, 0x60);
        assertEq(keccak256(encoded), hash);
        assertGe(gasInPlace, 30);
        assertGt(gasEncodeOnly, gasInPlace);
    }
}
