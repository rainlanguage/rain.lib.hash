// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibHashNoAlloc, HASH_NIL} from "../src/LibHashNoAlloc.sol";

/// The struct README.md "Handling pointers" hashes, and folds a list of.
struct Foo {
    uint256 a;
    address b;
    uint256[] c;
    bytes d;
}

/// The `Foo[]` fold README.md "Handling pointers" and "Nil hash prefix"
/// describe: an accumulator seeded with the nil hash, into which each item's
/// hash is combined by writing the pair to scratch space and hashing it. The
/// oracle for every assertion is built from `keccak256`, `abi.encode` and
/// `abi.encodePacked` only; `LibHashNoAlloc.combineHashes` stands in for
/// "write both to scratch and hash" on the side under test.
contract ReadmeFoldTest is Test {
    /// The README's hash of one `Foo`, steps A to E: A is the first two
    /// words, B the word list `c`, C combines A and B, D the bytes `d`, E
    /// combines C and D.
    function hashFoo(Foo memory foo) internal pure returns (bytes32) {
        bytes32 hashA = keccak256(abi.encode(foo.a, foo.b));
        bytes32 hashB = keccak256(abi.encodePacked(foo.c));
        bytes32 hashC = keccak256(abi.encodePacked(hashA, hashB));
        bytes32 hashD = keccak256(foo.d);
        return keccak256(abi.encodePacked(hashC, hashD));
    }

    /// The README fold: start from the nil hash, then for each item write
    /// the accumulator and the item's hash to scratch and hash the pair.
    function foldReadme(Foo[] memory foos) internal pure returns (bytes32 acc) {
        acc = HASH_NIL;
        for (uint256 i = 0; i < foos.length; i++) {
            acc = LibHashNoAlloc.combineHashes(acc, hashFoo(foos[i]));
        }
    }

    /// The same fold with builtins only: the pair in scratch is the packed
    /// concatenation of the accumulator then the item's hash.
    function foldOracle(Foo[] memory foos) internal pure returns (bytes32 expected) {
        expected = HASH_NIL;
        for (uint256 i = 0; i < foos.length; i++) {
            expected = keccak256(abi.encodePacked(expected, hashFoo(foos[i])));
        }
    }

    /// The first `n` items of `pool` as a `Foo[]`.
    function take(Foo[4] memory pool, uint256 n) internal pure returns (Foo[] memory foos) {
        foos = new Foo[](n);
        for (uint256 i = 0; i < n; i++) {
            foos[i] = pool[i];
        }
    }

    /// The README's step-by-step letters over `foos_[0]` and `foos_[1]`: N is
    /// the nil hash, A the hash of `foos_[0]`, B the hash of N then A, C the
    /// hash of `foos_[1]`, D the hash of B then C. B is the fold of the first
    /// item alone and D the fold of both.
    function testReadmeFoldLetters(Foo memory foo0, Foo memory foo1) public pure {
        Foo[] memory foos = new Foo[](2);
        foos[0] = foo0;
        foos[1] = foo1;

        bytes32 n = HASH_NIL;
        bytes32 a = hashFoo(foos[0]);
        bytes32 b = LibHashNoAlloc.combineHashes(n, a);
        bytes32 c = hashFoo(foos[1]);
        bytes32 d = LibHashNoAlloc.combineHashes(b, c);

        Foo[] memory first = new Foo[](1);
        first[0] = foo0;
        assertEq(b, foldOracle(first));
        assertEq(b, foldReadme(first));
        assertEq(d, foldOracle(foos));
        assertEq(d, foldReadme(foos));
    }

    /// Every length from 0 to 4: the scratch-space fold equals the builtin
    /// fold.
    function testReadmeFoldMatchesBuiltins(Foo[4] memory pool) public pure {
        for (uint256 n = 0; n <= 4; n++) {
            Foo[] memory foos = take(pool, n);
            assertEq(foldReadme(foos), foldOracle(foos));
        }
    }

    /// README "Nil hash prefix": an empty `Foo[]` folds to the nil hash, the
    /// hash of no bytes.
    function testReadmeFoldEmptyIsNilHash() public pure {
        Foo[] memory foos = new Foo[](0);
        assertEq(foldReadme(foos), keccak256(""));
        assertEq(foldReadme(foos), HASH_NIL);
    }

    /// README "Nil hash prefix": `[x]` folds to `hash(nil + hash(x))`, which
    /// is not `hash(x)`.
    function testReadmeFoldSingletonIsNotItem(Foo memory x) public pure {
        Foo[] memory foos = new Foo[](1);
        foos[0] = x;
        bytes32 hashX = hashFoo(x);
        bytes32 folded = foldReadme(foos);
        assertEq(folded, keccak256(abi.encodePacked(HASH_NIL, hashX)));
        assertTrue(folded != hashX);
    }
}
