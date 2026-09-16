// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibHashNoAlloc, HASH_NIL} from "../../../src/lib/LibHashNoAlloc.sol";
import {Foo, LibFooOracle} from "../../lib/LibFooOracle.sol";

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

    function take(Foo[4] memory pool, uint256 count) internal pure returns (Foo[] memory) {
        Foo[] memory foos = new Foo[](count);
        for (uint256 i = 0; i < count; i++) {
            foos[i] = pool[i];
        }
        return foos;
    }

    function testFoldPrefixIsStepwiseCombine(Foo memory foo0, Foo memory foo1) public pure {
        Foo[] memory foos = new Foo[](2);
        foos[0] = foo0;
        foos[1] = foo1;

        bytes32 nilHash = HASH_NIL;
        bytes32 hashFoo0 = LibFooOracle.hashFoo(foos[0]);
        bytes32 foldOne = LibHashNoAlloc.combineHashes(nilHash, hashFoo0);
        bytes32 hashFoo1 = LibFooOracle.hashFoo(foos[1]);
        bytes32 foldTwo = LibHashNoAlloc.combineHashes(foldOne, hashFoo1);

        Foo[] memory first = new Foo[](1);
        first[0] = foo0;
        assertEq(foldOne, foldOracle(first));
        assertEq(foldOne, foldPattern(first));
        assertEq(foldTwo, foldOracle(foos));
        assertEq(foldTwo, foldPattern(foos));
    }

    /// Every length from 0 to 4: the scratch-space fold equals the builtin
    /// fold.
    function testFoldEqualsPackedConcatFold(Foo[4] memory pool) public pure {
        for (uint256 count = 0; count <= 4; count++) {
            Foo[] memory foos = take(pool, count);
            assertEq(foldPattern(foos), foldOracle(foos));
        }
    }

    /// README "Nil hash prefix": an empty `Foo[]` folds to the nil hash, the
    /// hash of no bytes.
    function testFoldEmptyIsNilHash() public pure {
        Foo[] memory foos = new Foo[](0);
        assertEq(foldPattern(foos), keccak256(""));
    }

    function testFoldSingletonIsNotItem(Foo memory item) public pure {
        Foo[] memory foos = new Foo[](1);
        foos[0] = item;
        bytes32 hashItem = LibFooOracle.hashFoo(item);
        bytes32 folded = foldPattern(foos);
        assertEq(folded, keccak256(abi.encodePacked(keccak256(""), hashItem)));
        assertNotEq(folded, hashItem);
    }

    /// The pattern side here shares no code with the oracle, so a wrong item
    /// hash, dereference offset or scratch clobber between the item hash and
    /// the accumulator write fails here.
    function testYulFoldMatchesBuiltins(Foo[4] memory pool) public pure {
        for (uint256 count = 0; count <= 4; count++) {
            Foo[] memory foos = take(pool, count);
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
