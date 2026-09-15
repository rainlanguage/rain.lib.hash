// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {HASH_NIL} from "../src/LibHashNoAlloc.sol";

struct Foo {
    uint256 a;
    address b;
    uint256[] c;
    bytes d;
}

/// The gas bands asserted here are the ones README.md "Handling pointers"
/// states.
contract HashPatternFoldGasTest is Test {
    function hashFoo(Foo memory foo_) internal pure returns (bytes32) {
        bytes32 e;
        assembly ("memory-safe") {
            mstore(0, keccak256(foo_, 0x40))
            let deref_ := mload(add(foo_, 0x40))
            mstore(0x20, keccak256(add(deref_, 0x20), mul(mload(deref_), 0x20)))
            mstore(0, keccak256(0, 0x40))
            deref_ := mload(add(foo_, 0x60))
            mstore(0x20, keccak256(add(deref_, 0x20), mload(deref_)))
            e := keccak256(0, 0x40)
        }
        return e;
    }

    function fold(Foo[] memory foos_) internal pure returns (bytes32) {
        bytes32 acc = HASH_NIL;
        for (uint256 i = 0; i < foos_.length; i++) {
            bytes32 item = hashFoo(foos_[i]);
            assembly ("memory-safe") {
                mstore(0, acc)
                mstore(0x20, item)
                acc := keccak256(0, 0x40)
            }
        }
        return acc;
    }

    function foos(uint256 n, uint256 words, uint256 size) internal pure returns (Foo[] memory) {
        Foo[] memory list = new Foo[](n);
        for (uint256 i = 0; i < n; i++) {
            uint256[] memory c = new uint256[](words);
            for (uint256 j = 0; j < words; j++) {
                c[j] = i + j + 1;
            }
            bytes memory d = new bytes(size);
            for (uint256 j = 0; j < size; j++) {
                d[j] = bytes1(uint8(i + j + 1));
            }
            list[i] = Foo(i + 1, address(uint160(i + 2)), c, d);
        }
        return list;
    }

    /// Called externally so each reading starts from empty memory; expansion is
    /// quadratic in the high-water mark, so readings sharing a frame are not
    /// comparable. The digests are asserted so neither hash is optimised away.
    function measure(uint256 n, uint256 words, uint256 size) external view returns (uint256, uint256) {
        Foo[] memory list = foos(n, words, size);
        uint256 before = gasleft();
        bytes32 folded = fold(list);
        uint256 gasFold = before - gasleft();
        before = gasleft();
        bytes32 encoded = keccak256(abi.encode(list));
        uint256 gasEncode = before - gasleft();
        assertTrue(folded != bytes32(0));
        assertTrue(encoded != bytes32(0));
        return (gasFold, gasEncode);
    }

    function assertFoldPercentWithin(uint256 n, uint256 words, uint256 size, uint256 low, uint256 high) internal view {
        (uint256 gasFold, uint256 gasEncode) = this.measure(n, words, size);
        assertGe(gasFold * 100, gasEncode * low);
        assertLe(gasFold * 100, gasEncode * high);
    }

    function testFoldCostsSlightlyLessForEmptyElements() public view {
        (uint256 gasFold, uint256 gasEncode) = this.measure(4, 0, 0);
        assertLt(gasFold, gasEncode);
        assertGe(gasFold * 100, gasEncode * 75);
    }

    function testFoldCostsAboutHalfForHandfulOfWords() public view {
        assertFoldPercentWithin(4, 5, 100, 40, 60);
    }

    function testFoldCostsAboutAFifthForKilobyteOfWords() public view {
        assertFoldPercentWithin(4, 32, 0, 15, 25);
    }

    function testFoldFractionFallsAsWordsGrow() public view {
        (uint256 fold1k, uint256 encode1k) = this.measure(4, 32, 0);
        (uint256 fold4k, uint256 encode4k) = this.measure(4, 128, 0);
        assertLt(fold4k * encode1k, fold1k * encode4k);
    }

    function testFoldCostsAboutTwoThirdsForKilobyteOfBytes() public view {
        assertFoldPercentWithin(4, 0, 1024, 55, 80);
    }
}
