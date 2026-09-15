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
/// prose says it computes, plus the memory-layout claims that prose makes
/// about the types the examples cover, read back with `mload`. The only
/// deviation from the README is that each result is assigned to a Solidity
/// variable instead of a Yul `let` so that it can be asserted. The oracles use
/// neither the library nor the assembly under test.
contract HashPatternTest is Test {
    /// "Hashing contigious words": a `Foo` is the 4 words `a`, `b` and the
    /// pointers to `c` and `d`, so the hash is the hash of exactly those 4
    /// words. The pointer values come from the compiler, not from offsets into
    /// the struct.
    function testHashContiguousWords(uint256 a, address b, uint256[] memory c, bytes memory d) public pure {
        Foo memory foo = Foo(a, b, c, d);
        bytes32 hash;
        assembly ("memory-safe") {
            hash := keccak256(foo, 0x80)
        }

        uint256 cPointer;
        uint256 dPointer;
        assembly ("memory-safe") {
            cPointer := c
            dPointer := d
        }
        assertEq(hash, keccak256(abi.encode(a, b, cPointer, dPointer)));
    }

    /// "Hashing contigious words" for a static array: a `bytes32[3]` is its 3
    /// words with no length prefix, so the word at the pointer is element 0
    /// and hashing the 3 words hashes the elements packed.
    function testHashStaticBytes32Array(bytes32[3] memory arr) public pure {
        bytes32 hash;
        bytes32 first;
        assembly ("memory-safe") {
            hash := keccak256(arr, 0x60)
            first := mload(arr)
        }
        assertEq(first, arr[0]);
        assertEq(hash, keccak256(abi.encodePacked(arr)));
    }

    /// The same for a `uint256[4]`: 4 words, no length prefix.
    function testHashStaticUint256Array(uint256[4] memory arr) public pure {
        bytes32 hash;
        uint256 first;
        assembly ("memory-safe") {
            hash := keccak256(arr, 0x80)
            first := mload(arr)
        }
        assertEq(first, arr[0]);
        assertEq(hash, keccak256(abi.encodePacked(arr)));
    }

    /// "Lists of pointers like `Foo[]`" are word lists: a length prefix then
    /// one word per element, each word the pointer to that element's `Foo`.
    /// `new Foo[](length)` allocates the 0x20 + length * 0x20 list first and
    /// then one 0x80 zero-initialised `Foo` per element, so the first `Foo`
    /// starts exactly where the list ends.
    function testFooListIsWordList(uint8 length8) public pure {
        uint256 length = length8;
        uint256 fmpBefore;
        assembly ("memory-safe") {
            fmpBefore := mload(0x40)
        }
        Foo[] memory foos = new Foo[](length);
        uint256 ptr;
        uint256 fmpAfter;
        uint256 len;
        assembly ("memory-safe") {
            ptr := foos
            fmpAfter := mload(0x40)
            len := mload(foos)
        }
        assertEq(ptr, fmpBefore);
        assertEq(len, length);
        assertEq(fmpAfter - ptr, 0x20 + length * 0x20 + length * 0x80);

        for (uint256 i = 0; i < length; i++) {
            Foo memory foo = foos[i];
            uint256 fooPointer;
            uint256 word;
            assembly ("memory-safe") {
                fooPointer := foo
                word := mload(add(foos, mul(add(i, 1), 0x20)))
            }
            assertEq(word, fooPointer);
            if (i == 0) {
                assertEq(fooPointer, ptr + 0x20 + length * 0x20);
            }
        }
    }

    /// "Hashing dynamic length list of words": the `length` words after the
    /// length prefix, i.e. the packed words without the prefix.
    function testHashWordList(uint256[] memory bar) public pure {
        bytes32 hash;
        assembly ("memory-safe") {
            // Assume bar is some dynamic length list of words
            hash := keccak256(
                // Skip the length prefix
                add(bar, 0x20),
                // Read the length prefix and multiply by 0x20 to know how many _words_
                // to hash
                mul(mload(bar), 0x20)
            )
        }
        assertEq(hash, keccak256(abi.encodePacked(bar)));
    }

    /// The "Hashing dynamic length byte strings" example over `bytes`.
    function hashBytesExample(bytes memory baz) internal pure returns (bytes32) {
        bytes32 hash;
        assembly ("memory-safe") {
            // Assume baz is some bytes/string
            hash := keccak256(
                // Skip the length prefix
                add(baz, 0x20),
                // Read the length prefix to know how many _bytes_ to hash
                mload(baz)
            )
        }
        return hash;
    }

    /// "Hashing dynamic length byte strings": the `length` bytes after the
    /// length prefix, i.e. `keccak256` of the bytes themselves.
    function testHashBytes(bytes memory baz) public pure {
        assertEq(hashBytesExample(baz), keccak256(baz));
    }

    /// "It is the same for `string` and `bytes`": the same example over a
    /// `string` is `keccak256` of the string's bytes.
    function testHashString(string memory baz) public pure {
        bytes32 hash;
        assembly ("memory-safe") {
            // Assume baz is some bytes/string
            hash := keccak256(
                // Skip the length prefix
                add(baz, 0x20),
                // Read the length prefix to know how many _bytes_ to hash
                mload(baz)
            )
        }
        assertEq(hash, keccak256(bytes(baz)));
    }

    /// "We MUST respect the true length": `hex"01"` and `hex"0100"` occupy the
    /// same single data word (1 and 2 bytes, both zero-padded to 0x20), so a
    /// hash over the allocated word would not tell them apart; the example
    /// hashes only the `length` bytes and does.
    function testBytesTrueLength() public pure {
        bytes memory one = hex"01";
        bytes memory two = hex"0100";
        uint256 wordOne;
        uint256 wordTwo;
        assembly ("memory-safe") {
            wordOne := mload(add(one, 0x20))
            wordTwo := mload(add(two, 0x20))
        }
        assertEq(wordOne, wordTwo);

        bytes32 hashOne = hashBytesExample(one);
        bytes32 hashTwo = hashBytesExample(two);
        assertTrue(hashOne != hashTwo);
        assertEq(hashOne, keccak256(hex"01"));
        assertEq(hashTwo, keccak256(hex"0100"));
    }

    /// "Handling pointers": the prose steps A to E over `Foo`. A is the first
    /// two words, B is the word list `c`, C combines A and B, D is the bytes
    /// `d`, E combines C and D.
    function testHandlingPointers(uint256 a, address b, uint256[] memory c, bytes memory d) public pure {
        Foo memory foo = Foo(a, b, c, d);
        bytes32 hash;
        assembly ("memory-safe") {
            // hash foo.a and foo.b together to produce hash A
            // store A in scratch
            mstore(0, keccak256(foo, 0x40))

            // Follow the pointer to hash foo.c into B
            let deref := mload(add(foo, 0x40))
            // Store B in scratch
            mstore(0x20, keccak256(add(deref, 0x20), mul(mload(deref), 0x20)))

            // Hash A and B to produce C which can be stored direct in scratch
            mstore(0, keccak256(0, 0x40))

            // Follow the pointer to hash foo.d
            deref := mload(add(foo, 0x60))
            // Store D in scratch
            mstore(0x20, keccak256(add(deref, 0x20), mload(deref)))

            // Write C and D to scratch to produce the final hash E
            hash := keccak256(0, 0x40)
        }

        bytes32 hashA = keccak256(abi.encode(a, b));
        bytes32 hashB = keccak256(abi.encodePacked(c));
        bytes32 hashC = keccak256(abi.encodePacked(hashA, hashB));
        bytes32 hashD = keccak256(d);
        bytes32 hashE = keccak256(abi.encodePacked(hashC, hashD));
        assertEq(hash, hashE);
    }
}
