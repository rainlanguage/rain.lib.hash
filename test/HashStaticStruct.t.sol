// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

struct Header {
    uint256 a;
    address b;
    uint32 c;
}

contract HashStaticStructTest is Test {
    function testStaticStructInPlaceHashIsAbiEncodeHash(uint256 a, address b, uint32 c) public pure {
        Header memory header_ = Header(a, b, c);
        bytes32 hash_;
        assembly ("memory-safe") {
            hash_ := keccak256(header_, 0x60)
        }
        assertEq(hash_, keccak256(abi.encode(a, b, c)));
        assertEq(hash_, keccak256(abi.encode(header_)));
    }

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
