// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

/// The struct that README.md "The pattern" hashes in its examples.
struct Foo {
    uint256 a;
    address b;
    uint256[] c;
    bytes d;
}

/// Every Yul example in README.md "The pattern", reproduced verbatim and
/// checked against a plain Solidity implementation of what its surrounding
/// prose says it computes. The only deviation from the README is that each
/// result is assigned to a Solidity variable instead of a Yul `let` so that it
/// can be asserted. The oracles use neither the library nor the assembly under
/// test.
contract ReadmeExamplesTest is Test {
    /// "Hashing contigious words": a `Foo` is the 4 words `a`, `b` and the
    /// pointers to `c` and `d`, so the hash is the hash of exactly those 4
    /// words. The pointer values come from the compiler, not from offsets into
    /// the struct.
    function testReadmeHashContiguousWords(uint256 a, address b, uint256[] memory c, bytes memory d) public pure {
        Foo memory foo_ = Foo(a, b, c, d);
        bytes32 hash_;
        assembly ("memory-safe") {
            hash_ := keccak256(foo_, 0x80)
        }

        uint256 cPointer;
        uint256 dPointer;
        assembly ("memory-safe") {
            cPointer := c
            dPointer := d
        }
        assertEq(hash_, keccak256(abi.encode(a, b, cPointer, dPointer)));
    }

    /// "Hashing dynamic length list of words": the `length` words after the
    /// length prefix, i.e. the packed words without the prefix.
    function testReadmeHashWordList(uint256[] memory bar_) public pure {
        bytes32 hash_;
        assembly ("memory-safe") {
            // Assume bar_ is some dynamic length list of words
            hash_ := keccak256(
                // Skip the length prefix
                add(bar_, 0x20),
                // Read the length prefix and multiply by 0x20 to know how many _words_
                // to hash
                mul(mload(bar_), 0x20)
            )
        }
        assertEq(hash_, keccak256(abi.encodePacked(bar_)));
    }

    /// "Hashing dynamic length byte strings": the `length` bytes after the
    /// length prefix, i.e. `keccak256` of the bytes themselves.
    function testReadmeHashBytes(bytes memory baz_) public pure {
        bytes32 hash_;
        assembly ("memory-safe") {
            // Assume baz_ is some bytes/string
            hash_ := keccak256(
                // Skip the length prefix
                add(baz_, 0x20),
                // Read the length prefix to know how many _bytes_ to hash
                mload(baz_)
            )
        }
        assertEq(hash_, keccak256(baz_));
    }

    /// "Handling pointers": the prose steps A to E over `Foo`. A is the first
    /// two words, B is the word list `c`, C combines A and B, D is the bytes
    /// `d`, E combines C and D.
    function testReadmeHandlingPointers(uint256 a, address b, uint256[] memory c, bytes memory d) public pure {
        Foo memory foo_ = Foo(a, b, c, d);
        bytes32 e;
        assembly ("memory-safe") {
            // hash foo_.a and foo_.b together to produce hash A
            // store A in scratch
            mstore(0, keccak256(foo_, 0x40))

            // Follow the pointer to hash foo_.c into B
            let deref_ := mload(add(foo_, 0x40))
            // Store B in scratch
            mstore(0x20, keccak256(add(deref_, 0x20), mul(mload(deref_), 0x20)))

            // Hash A and B to produce C which can be stored direct in scratch
            mstore(0, keccak256(0, 0x40))

            // Follow the pointer to hash foo_.d
            deref_ := mload(add(foo_, 0x60))
            // Store D in scratch
            mstore(0x20, keccak256(add(deref_, 0x20), mload(deref_)))

            // Write C and D to scratch to produce the final hash E
            e := keccak256(0, 0x40)
        }

        bytes32 hashA = keccak256(abi.encode(a, b));
        bytes32 hashB = keccak256(abi.encodePacked(c));
        bytes32 hashC = keccak256(abi.encodePacked(hashA, hashB));
        bytes32 hashD = keccak256(d);
        bytes32 hashE = keccak256(abi.encodePacked(hashC, hashD));
        assertEq(e, hashE);
    }
}
