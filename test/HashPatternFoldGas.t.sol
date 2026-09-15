// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {HASH_NIL} from "../src/LibHashNoAlloc.sol";

/// The struct README.md "Handling pointers" folds a list of.
struct Foo {
    uint256 a;
    address b;
    uint256[] c;
    bytes d;
}

/// The gas bands README.md "Handling pointers" states for the nil-seeded
/// `Foo[]` fold against `keccak256(abi.encode(foos_))`, measured by `gasleft()`
/// delta in each regime the prose names. The bands are the README's own words;
/// a compiler or EVM change that moves a measurement out of its band fails here
/// and the README is corrected with it.
contract HashPatternFoldGasTest is Test {
    /// The README's hash of one `Foo`, steps A to E, in the README's assembly.
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

    /// The README fold: nil hash seed, each item's hash combined through
    /// scratch space.
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

    /// `n` distinct `Foo`s with `words` words in `c` and `size` bytes in `d`.
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

    /// `gasleft()` deltas of the fold and of `keccak256(abi.encode(list))` over
    /// a fresh list. Both digests are asserted non-zero so neither hash can be
    /// optimised away.
    ///
    /// External, and called as `this.measure`, so that every reading starts
    /// from the same empty memory. Encoding pays memory expansion for the
    /// buffer it allocates, and expansion is quadratic in the high-water mark,
    /// so a reading taken after another one in the same call frame is charged
    /// for the earlier list as well and the two are not comparable.
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

    /// The fold costs between `low`% and `high`% of encoding.
    function assertFoldPercentWithin(uint256 n, uint256 words, uint256 size, uint256 low, uint256 high) internal view {
        (uint256 gasFold, uint256 gasEncode) = this.measure(n, words, size);
        assertGe(gasFold * 100, gasEncode * low);
        assertLe(gasFold * 100, gasEncode * high);
    }

    /// "with `c` and `d` empty the fold already costs slightly less than
    /// encoding": strictly less, and only slightly, so a band that had swung
    /// the other way would fail here too.
    function testFoldCostsSlightlyLessForEmptyElements() public view {
        (uint256 gasFold, uint256 gasEncode) = this.measure(4, 0, 0);
        assertLt(gasFold, gasEncode);
        assertGe(gasFold * 100, gasEncode * 75);
    }

    /// "with a handful of words in each it costs about half".
    function testFoldCostsAboutHalfForHandfulOfWords() public view {
        assertFoldPercentWithin(4, 5, 100, 40, 60);
    }

    /// "with a kilobyte of words per element it costs about a fifth".
    function testFoldCostsAboutAFifthForKilobyteOfWords() public view {
        assertFoldPercentWithin(4, 32, 0, 15, 25);
    }

    /// "the fraction keeps falling as the word lists grow": four kilobytes of
    /// words per element is a smaller fraction of encoding than one kilobyte.
    function testFoldFractionFallsAsWordsGrow() public view {
        (uint256 fold1k, uint256 encode1k) = this.measure(4, 32, 0);
        (uint256 fold4k, uint256 encode4k) = this.measure(4, 128, 0);
        assertLt(fold4k * encode1k, fold1k * encode4k);
    }

    /// "with a kilobyte of `bytes` per element it still costs about two
    /// thirds, because encoding copies `bytes` in bulk but copies a word list
    /// one word at a time".
    function testFoldCostsAboutTwoThirdsForKilobyteOfBytes() public view {
        assertFoldPercentWithin(4, 0, 1024, 55, 80);
    }
}
