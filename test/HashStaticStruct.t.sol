// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

/// The struct the LibHashNoAlloc NatSpec hashes in its example: three static
/// members, the last of them sub-word.
struct Header {
    uint256 a;
    address b;
    uint32 c;
}

/// Every claim the LibHashNoAlloc NatSpec makes about hashing a static struct
/// in place: its `keccak256(header_, 0x60)` example, the 3-word size the 0x60
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
        Header memory header_ = Header(a, b, c);
        bytes32 hash_;
        assembly ("memory-safe") {
            hash_ := keccak256(header_, 0x60)
        }
        assertEq(hash_, keccak256(abi.encode(a, b, c)));
        assertEq(hash_, keccak256(abi.encode(header_)));
    }

    /// Where the 0x60 comes from: a `Header` is allocated at the free memory
    /// pointer and bumps it by exactly three words, whatever its members hold.
    function testStaticStructIsThreeWords(uint256 a, address b, uint32 c) public pure {
        uint256 fmpBefore;
        assembly ("memory-safe") {
            fmpBefore := mload(0x40)
        }
        Header memory header_ = Header(a, b, c);
        uint256 pointer;
        uint256 fmpAfter;
        assembly ("memory-safe") {
            pointer := header_
            fmpAfter := mload(0x40)
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
        Header memory header_ = Header(a, b, c);
        uint256 fmp0;
        assembly ("memory-safe") {
            fmp0 := mload(0x40)
        }

        uint256 gasBefore = gasleft();
        bytes32 hash_;
        assembly ("memory-safe") {
            hash_ := keccak256(header_, 0x60)
        }
        uint256 gasInPlace = gasBefore - gasleft();
        uint256 fmp1;
        assembly ("memory-safe") {
            fmp1 := mload(0x40)
        }

        gasBefore = gasleft();
        bytes memory encoded = abi.encode(header_);
        uint256 gasEncodeOnly = gasBefore - gasleft();
        uint256 fmp2;
        assembly ("memory-safe") {
            fmp2 := mload(0x40)
        }

        assertEq(fmp1, fmp0);
        assertEq(fmp2 - fmp1, 0x80);
        assertEq(encoded.length, 0x60);
        assertEq(keccak256(encoded), hash_);
        assertGe(gasInPlace, 30);
        assertGt(gasEncodeOnly, gasInPlace);
    }
}
