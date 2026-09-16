// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibHashNoAlloc, HASH_NIL} from "../src/LibHashNoAlloc.sol";
import {Foo, LibFooOracle} from "./lib/LibFooOracle.sol";

/// The `Foo[]` fold README.md "Handling pointers" and "Nil hash prefix"
/// describe: an accumulator seeded with the nil hash, into which each item's
/// hash is combined by writing the pair to scratch space and hashing it. The
/// oracle for every assertion is built from `keccak256`, `abi.encode` and
/// `abi.encodePacked` only, its seed included, so the seed is checked against
/// `HASH_NIL` rather than shared with it. The side under test is
/// `LibHashNoAlloc.combineHashes` standing in for "write both to scratch and
/// hash", or the hand-written Yul below for the whole fold.
contract HashPatternFoldTest is Test {
    /// The README fold: start from the nil hash, then for each item write
    /// the accumulator and the item's hash to scratch and hash the pair.
    function foldPattern(Foo[] memory foos) internal pure returns (bytes32) {
        bytes32 acc = HASH_NIL;
        for (uint256 i = 0; i < foos.length; i++) {
            acc = LibHashNoAlloc.combineHashes(acc, LibFooOracle.hashFoo(foos[i]));
        }
        return acc;
    }

    /// The same fold with builtins only: the pair in scratch is the packed
    /// concatenation of the accumulator then the item's hash.
    function foldOracle(Foo[] memory foos) internal pure returns (bytes32) {
        bytes32 expected = keccak256("");
        for (uint256 i = 0; i < foos.length; i++) {
            expected = keccak256(abi.encodePacked(expected, LibFooOracle.hashFoo(foos[i])));
        }
        return expected;
    }

    /// The first `n` items of `pool` as a `Foo[]`.
    function take(Foo[4] memory pool, uint256 n) internal pure returns (Foo[] memory) {
        Foo[] memory foos = new Foo[](n);
        for (uint256 i = 0; i < n; i++) {
            foos[i] = pool[i];
        }
        return foos;
    }

    /// The README's step-by-step letters over `foos_[0]` and `foos_[1]`: N is
    /// the nil hash, A the hash of `foos_[0]`, B the hash of N then A, C the
    /// hash of `foos_[1]`, D the hash of B then C. B is the fold of the first
    /// item alone and D the fold of both.
    function testFoldPrefixIsStepwiseCombine(Foo memory foo0, Foo memory foo1) public pure {
        Foo[] memory foos = new Foo[](2);
        foos[0] = foo0;
        foos[1] = foo1;

        bytes32 n = HASH_NIL;
        bytes32 a = LibFooOracle.hashFoo(foos[0]);
        bytes32 b = LibHashNoAlloc.combineHashes(n, a);
        bytes32 c = LibFooOracle.hashFoo(foos[1]);
        bytes32 d = LibHashNoAlloc.combineHashes(b, c);

        Foo[] memory first = new Foo[](1);
        first[0] = foo0;
        assertEq(b, foldOracle(first));
        assertEq(b, foldPattern(first));
        assertEq(d, foldOracle(foos));
        assertEq(d, foldPattern(foos));
    }

    /// Every length from 0 to 4: the scratch-space fold equals the builtin
    /// fold.
    function testFoldEqualsPackedConcatFold(Foo[4] memory pool) public pure {
        for (uint256 n = 0; n <= 4; n++) {
            Foo[] memory foos = take(pool, n);
            assertEq(foldPattern(foos), foldOracle(foos));
        }
    }

    /// README "Nil hash prefix": an empty `Foo[]` folds to the nil hash, the
    /// hash of no bytes.
    function testFoldEmptyIsNilHash() public pure {
        Foo[] memory foos = new Foo[](0);
        assertEq(foldPattern(foos), keccak256(""));
    }

    /// README "Nil hash prefix": `[x]` folds to `hash(nil + hash(x))`, which
    /// is not `hash(x)`.
    function testFoldSingletonIsNotItem(Foo memory x) public pure {
        Foo[] memory foos = new Foo[](1);
        foos[0] = x;
        bytes32 hashX = LibFooOracle.hashFoo(x);
        bytes32 folded = foldPattern(foos);
        assertEq(folded, keccak256(abi.encodePacked(keccak256(""), hashX)));
        assertNotEq(folded, hashX);
    }

    /// The pattern side here shares no code with the oracle, so a wrong item
    /// hash, dereference offset or scratch clobber between the item hash and
    /// the accumulator write fails here.
    function testYulFoldMatchesBuiltins(Foo[4] memory pool) public pure {
        for (uint256 n = 0; n <= 4; n++) {
            Foo[] memory foos = take(pool, n);
            bytes32 acc;
            assembly ("memory-safe") {
                acc := keccak256(0, 0)
                for { let i := 0 } lt(i, mload(foos)) { i := add(i, 1) } {
                    let foo_ := mload(add(foos, mul(add(i, 1), 0x20)))

                    mstore(0, keccak256(foo_, 0x40))

                    let deref_ := mload(add(foo_, 0x40))
                    mstore(0x20, keccak256(add(deref_, 0x20), mul(mload(deref_), 0x20)))

                    mstore(0, keccak256(0, 0x40))

                    deref_ := mload(add(foo_, 0x60))
                    mstore(0x20, keccak256(add(deref_, 0x20), mload(deref_)))

                    let e := keccak256(0, 0x40)

                    mstore(0, acc)
                    mstore(0x20, e)
                    acc := keccak256(0, 0x40)
                }
            }
            assertEq(acc, foldOracle(foos));
        }
    }
}
