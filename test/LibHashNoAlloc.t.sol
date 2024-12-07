// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {LibHashNoAlloc, HASH_NIL} from "../src/LibHashNoAlloc.sol";
import {LibHashSlow} from "./LibHashSlow.sol";

contract LibHashNoAllocTest is Test {
    function testHashNil() public pure {
        bytes32 hashNil_;
        assembly ("memory-safe") {
            hashNil_ := keccak256(0, 0)
        }
        assertEq(HASH_NIL, hashNil_);
        assertEq(HASH_NIL, keccak256(""));
    }

    function testHashBytes(bytes memory bytes_) public pure {
        assertEq(LibHashNoAlloc.hashBytes(bytes_), LibHashSlow.hashBytesSlow(bytes_));
    }

    function testHashBytesEmpty() public pure {
        assertEq(LibHashNoAlloc.hashBytes(""), HASH_NIL);
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

    function testHashWords(bytes32[] memory words_) public pure {
        assertEq(LibHashNoAlloc.hashWords(words_), LibHashSlow.hashWordsSlow(words_));
    }

    function testHashWordsUint256(uint256[] memory words_) public pure {
        assertEq(LibHashNoAlloc.hashWords(words_), LibHashSlow.hashWordsSlow(words_));
    }

    function testHashWordsEmpty() public pure {
        assertEq(LibHashNoAlloc.hashWords(new bytes32[](0)), HASH_NIL);
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

    function testCombineHashes(bytes32 a_, bytes32 b_) public pure {
        assertEq(LibHashNoAlloc.combineHashes(a_, b_), LibHashSlow.combineHashesSlow(a_, b_));
    }

    function testCombineHashesGas0() public pure {
        LibHashNoAlloc.combineHashes(bytes32(uint256(1)), bytes32(uint256(2)));
    }

    function testCombineHashesGasSlow0() public pure {
        LibHashSlow.combineHashesSlow(bytes32(uint256(1)), bytes32(uint256(2)));
    }
}
