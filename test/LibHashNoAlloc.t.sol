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
        assembly ("memory-safe") {
            freeMemoryPointerBefore := mload(0x40)
        }
        bytes32 hash = LibHashNoAlloc.hashBytes(data);
        uint256 freeMemoryPointerAfter;
        assembly ("memory-safe") {
            freeMemoryPointerAfter := mload(0x40)
        }
        assertEq(freeMemoryPointerAfter, freeMemoryPointerBefore);
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

    function testHashWordsUint256NoAlloc() public pure {
        uint256[] memory words = new uint256[](2);
        words[0] = 1;
        words[1] = 2;
        uint256 freeMemoryPointerBefore;
        assembly ("memory-safe") {
            freeMemoryPointerBefore := mload(0x40)
        }
        bytes32 hash = LibHashNoAlloc.hashWords(words);
        uint256 freeMemoryPointerAfter;
        assembly ("memory-safe") {
            freeMemoryPointerAfter := mload(0x40)
        }
        assertEq(freeMemoryPointerAfter, freeMemoryPointerBefore);
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
        assembly ("memory-safe") {
            freeMemoryPointerBefore := mload(0x40)
        }
        bytes32 hash = LibHashNoAlloc.hashWords(words);
        uint256 freeMemoryPointerAfter;
        assembly ("memory-safe") {
            freeMemoryPointerAfter := mload(0x40)
        }
        assertEq(freeMemoryPointerAfter, freeMemoryPointerBefore);
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
        assembly ("memory-safe") {
            freeMemoryPointerBefore := mload(0x40)
        }
        bytes32 hash = LibHashNoAlloc.combineHashes(bytes32(uint256(1)), bytes32(uint256(2)));
        uint256 freeMemoryPointerAfter;
        assembly ("memory-safe") {
            freeMemoryPointerAfter := mload(0x40)
        }
        assertEq(freeMemoryPointerAfter, freeMemoryPointerBefore);
        assertEq(hash, bytes32(0xe90b7bceb6e7df5418fb78d8ee546e97c83a08bbccc01a0644d599ccd2a7c2e0));
    }

    function testCombineHashesGas0() public pure {
        LibHashNoAlloc.combineHashes(bytes32(uint256(1)), bytes32(uint256(2)));
    }

    function testCombineHashesGasSlow0() public pure {
        LibHashSlow.combineHashesSlow(bytes32(uint256(1)), bytes32(uint256(2)));
    }
}
