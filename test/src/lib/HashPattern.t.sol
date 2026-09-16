// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {Foo, LibFooOracle} from "../../lib/LibFooOracle.sol";
import {LibMemorySnapshot} from "../../lib/LibMemorySnapshot.sol";
import {LibHashNoAlloc} from "../../../src/lib/LibHashNoAlloc.sol";

/// The assembly of README.md "The pattern", which states the pattern in prose
/// and points here for the code. Each example is checked against a plain
/// Solidity implementation of what that prose says it computes, plus the
/// memory-layout claims the prose makes about the types the examples cover,
/// read back with `mload`. The oracles use neither the library nor the
/// assembly under test.
contract HashPatternTest is Test {
    /// "Hashing contiguous words": a `Foo` is the 4 words `a`, `b` and the
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

    /// "Hashing contiguous words" for a static array: a `bytes32[3]` is its 3
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
    function testFooListIsWordList(uint8 length8) public pure {
        uint256 length = length8;
        Foo[] memory foos = new Foo[](length);
        uint256 ptr;
        assembly ("memory-safe") {
            ptr := foos
        }
        assertEq(LibMemorySnapshot.wordAt(ptr, 0), length);

        for (uint256 i = 0; i < length; i++) {
            Foo memory foo = foos[i];
            uint256 fooPointer;
            assembly ("memory-safe") {
                fooPointer := foo
            }
            assertEq(LibMemorySnapshot.wordAt(ptr, (i + 1) * 0x20), fooPointer);
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
    function testHashBytesExampleIsKeccakOfBytes(bytes memory baz) public pure {
        assertEq(hashBytesExample(baz), keccak256(baz));
    }

    /// "It is the same for `string` and `bytes`": the same example over a
    /// `string` is `keccak256` of the string's bytes.
    function testHashStringExampleIsKeccakOfBytes(string memory baz) public pure {
        assertEq(hashBytesExample(bytes(baz)), keccak256(bytes(baz)));
    }

    /// "We MUST respect the true length": `hex"01"` and `hex"0100"` occupy the
    /// same single data word, `0x01` followed by 31 zero bytes (1 and 2 bytes,
    /// both zero-padded to 0x20), so a hash over the allocated word collides;
    /// the example hashes only the `length` bytes and does tell them apart.
    function testBytesTrueLength() public pure {
        bytes memory one = hex"01";
        bytes memory two = hex"0100";
        uint256 wordOne;
        uint256 wordTwo;
        bytes32 roundedOne;
        bytes32 roundedTwo;
        assembly ("memory-safe") {
            wordOne := mload(add(one, 0x20))
            wordTwo := mload(add(two, 0x20))
            roundedOne := keccak256(add(one, 0x20), 0x20)
            roundedTwo := keccak256(add(two, 0x20), 0x20)
        }
        assertEq(wordOne, uint256(bytes32(bytes1(0x01))));
        assertEq(wordTwo, wordOne);
        assertEq(roundedOne, roundedTwo);

        bytes32 hashOne = hashBytesExample(one);
        bytes32 hashTwo = hashBytesExample(two);
        assertNotEq(hashOne, hashTwo);
        assertEq(hashOne, keccak256(hex"01"));
        assertEq(hashTwo, keccak256(hex"0100"));
    }

    /// "Handling pointers": the prose steps A to E over `Foo`, as
    /// `LibFooOracle.hashFoo` spells them out.
    function testStructWithPointersHashesAsNestedNodes(uint256 a, address b, uint256[] memory c, bytes memory d)
        public
        pure
    {
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

            // Hash C and D, already in scratch, to produce the final hash E
            hash := keccak256(0, 0x40)
        }

        assertEq(hash, LibFooOracle.hashFoo(foo));
    }

    /// The README "Handling pointers" steps A to E over one `Foo`, built from
    /// the library's primitives rather than from the builtin oracle.
    function hashFooWithLibrary(Foo memory foo) internal pure returns (bytes32) {
        bytes32 hashA = LibHashNoAlloc.hashBytes(abi.encode(foo.a, foo.b));
        bytes32 hashB = LibHashNoAlloc.hashWords(foo.c);
        bytes32 hashC = LibHashNoAlloc.combineHashes(hashA, hashB);
        bytes32 hashD = LibHashNoAlloc.hashBytes(foo.d);
        return LibHashNoAlloc.combineHashes(hashC, hashD);
    }

    /// README "Handling pointers": a pointer "is not even deterministic", so
    /// two `Foo`s with equal members at different addresses hash apart as a raw
    /// region, which holds their pointer words, and together under the steps
    /// that follow the pointers.
    function testEqualFoosDifferByRegionAndAgreeByComposition(
        uint256 a,
        address b,
        uint256[] memory c,
        bytes memory d
    ) public pure {
        Foo memory first = Foo(a, b, c, d);
        uint256[] memory copiedWords = new uint256[](c.length);
        for (uint256 index = 0; index < c.length; index++) {
            copiedWords[index] = c[index];
        }
        Foo memory second = Foo(a, b, copiedWords, bytes.concat(d));

        bytes32 firstRegion;
        bytes32 secondRegion;
        assembly ("memory-safe") {
            firstRegion := keccak256(first, 0x80)
            secondRegion := keccak256(second, 0x80)
        }
        assertNotEq(firstRegion, secondRegion);
        assertEq(hashFooWithLibrary(first), hashFooWithLibrary(second));
        assertEq(hashFooWithLibrary(first), LibFooOracle.hashFoo(first));
    }

    /// README "single byte values `bytes1[]`" are a word list: the `length`
    /// left-aligned words after the prefix are what the library hashes.
    function testBytes1ArrayHashesAsItsWords(bytes1[] memory singleBytes) public pure {
        bytes32[] memory words;
        assembly ("memory-safe") {
            words := singleBytes
        }
        assertEq(LibHashNoAlloc.hashWords(words), keccak256(abi.encodePacked(singleBytes)));
    }
}
