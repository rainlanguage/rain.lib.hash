// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

/// The struct README.md "Memory layout" describes: a 4-word region, one word
/// per member whatever the member's type.
struct Foo {
    uint256 a;
    address b;
    uint256[] c;
    bytes d;
}

/// A struct whose second member is a struct: `inner` is one word of the
/// `Outer`, the pointer to a `Foo`.
struct Outer {
    uint256 x;
    Foo inner;
}

/// A struct whose second member is an `Outer`: three levels of struct
/// nesting, one pointer word per level.
struct Outermost {
    uint256 y;
    Outer mid;
}

/// A three-value enum: in memory its values are the words 0, 1 and 2.
enum Colour {
    Red,
    Green,
    Blue
}

/// One member per family of sub-word type the README describes. Each member
/// is a full word, so the nth member is the word at byte offset n * 0x20.
struct SubWord {
    bool flag;
    address addr;
    uint32 u;
    Colour colour;
    int8 i;
    bytes4 b;
}

/// How Solidity lays out struct members, nested structs, dynamic members and
/// `new` byte allocations in memory: each fact is read back
/// from memory with `mload` and checked against the word Solidity's own type
/// conversions produce for the same value.
contract MemoryLayoutTest is Test {
    /// Values for the members a test is not reading. Each is a distinct
    /// non-zero word, so a read at the wrong offset does not match the word
    /// expected for the member under test.
    address constant ADDR = address(0x1111111111111111111111111111111111111111);
    uint32 constant U = 0x22222222;
    int8 constant I = -3;
    bytes4 constant B = 0x44444444;

    /// The word at byte `offset` of the struct's memory.
    function word(SubWord memory s, uint256 offset) internal pure returns (uint256 w) {
        assembly ("memory-safe") {
            w := mload(add(s, offset))
        }
    }

    /// Every sub-word member occupies a full word: six members allocate six
    /// words.
    function testSubWordMembersOccupyFullWords() public pure {
        uint256 fmpBefore;
        assembly ("memory-safe") {
            fmpBefore := mload(0x40)
        }
        SubWord memory s = SubWord(true, ADDR, U, Colour.Green, I, B);
        uint256 ptr;
        uint256 fmpAfter;
        assembly ("memory-safe") {
            ptr := s
            fmpAfter := mload(0x40)
        }
        assertEq(ptr, fmpBefore);
        assertEq(fmpAfter - ptr, 6 * 0x20);
    }

    /// `bool` is right-aligned and zero-padded: `true` is the word 1, `false`
    /// the word 0.
    function testBoolIsZeroPadded(bool x) public pure {
        SubWord memory s = SubWord(x, ADDR, U, Colour.Green, I, B);
        assertEq(word(s, 0x00), uint256(x ? 1 : 0));
    }

    /// `address` is right-aligned and zero-padded: the word is the `uint160`
    /// value.
    function testAddressIsZeroPadded(address x) public pure {
        SubWord memory s = SubWord(true, x, U, Colour.Green, I, B);
        assertEq(word(s, 0x20), uint256(uint160(x)));
    }

    /// Unsigned integers are right-aligned and zero-padded: the word is the
    /// `uint256` value.
    function testUnsignedIntIsZeroPadded(uint32 x) public pure {
        SubWord memory s = SubWord(true, ADDR, x, Colour.Green, I, B);
        assertEq(word(s, 0x40), uint256(x));
    }

    /// Enums are right-aligned and zero-padded: the word is the value's
    /// `uint8`.
    function testEnumIsZeroPadded() public pure {
        for (uint8 v = 0; v <= uint8(type(Colour).max); v++) {
            Colour c = Colour(v);
            SubWord memory s = SubWord(true, ADDR, U, c, I, B);
            assertEq(word(s, 0x60), uint256(uint8(c)));
        }
    }

    /// Signed integers are right-aligned and sign-extended: the word is
    /// `uint256(int256(x))`, not the zero-padded `uint256(uint8(x))`.
    function testSignedIntIsSignExtended(int8 x) public pure {
        SubWord memory s = SubWord(true, ADDR, U, Colour.Green, x, B);
        assertEq(word(s, 0x80), uint256(int256(x)));
    }

    /// The README's example: `int8(-1)` is `0xff…ff`, not `0x00…ff`.
    function testInt8MinusOneIsAllOnes() public pure {
        SubWord memory s = SubWord(true, ADDR, U, Colour.Green, -1, B);
        uint256 w = word(s, 0x80);
        assertEq(w, type(uint256).max);
        assertTrue(w != uint256(uint8(int8(-1))));
    }

    /// `bytesN` is left-aligned and zero-padded on the right: the word is
    /// `uint256(bytes32(x))`, not the right-aligned `uint256(uint32(x))`.
    function testFixedBytesIsLeftAligned(bytes4 x) public pure {
        SubWord memory s = SubWord(true, ADDR, U, Colour.Green, I, x);
        assertEq(word(s, 0xa0), uint256(bytes32(x)));
    }

    /// The README's example: `bytes4(0x01020304)` is `0x01020304` followed by
    /// 28 zero bytes, not `0x00…01020304`.
    function testBytes4ExampleIsLeftAligned() public pure {
        SubWord memory s = SubWord(true, ADDR, U, Colour.Green, I, bytes4(0x01020304));
        uint256 w = word(s, 0xa0);
        assertEq(w, uint256(0x01020304) << 224);
        assertTrue(w != uint256(uint32(0x01020304)));
    }

    /// A `Foo` is a 4-word region: `uint256`, `address`, `uint256[]` and
    /// `bytes` are each one word of the struct.
    function testFooIsFourWords() public pure {
        uint256[] memory c = new uint256[](0);
        bytes memory d = "";
        uint256 fmpBefore;
        assembly ("memory-safe") {
            fmpBefore := mload(0x40)
        }
        // c and d are already allocated, so the struct is the only allocation
        // between fmpBefore and fmpAfter.
        Foo memory f = Foo(1, address(2), c, d);
        uint256 ptr;
        uint256 fmpAfter;
        assembly ("memory-safe") {
            ptr := f
            fmpAfter := mload(0x40)
        }
        assertEq(ptr, fmpBefore);
        assertEq(fmpAfter - ptr, 0x80);
    }

    /// `bytes1[]` is a list of words: a length prefix then one full word per
    /// element, each element left-aligned like any `bytesN`.
    function testBytes1ArrayIsWordList() public pure {
        uint256 fmpBefore;
        assembly ("memory-safe") {
            fmpBefore := mload(0x40)
        }
        bytes1[] memory arr = new bytes1[](3);
        arr[0] = 0x01;
        arr[1] = 0x02;
        arr[2] = 0x03;
        uint256 ptr;
        uint256 fmpAfter;
        uint256 len;
        uint256 w0;
        uint256 w1;
        uint256 w2;
        assembly ("memory-safe") {
            ptr := arr
            fmpAfter := mload(0x40)
            len := mload(arr)
            w0 := mload(add(arr, 0x20))
            w1 := mload(add(arr, 0x40))
            w2 := mload(add(arr, 0x60))
        }
        assertEq(ptr, fmpBefore);
        assertEq(len, 3);
        assertEq(fmpAfter - ptr, 0x20 + 3 * 0x20);
        assertEq(w0, uint256(bytes32(bytes1(0x01))));
        assertEq(w1, uint256(bytes32(bytes1(0x02))));
        assertEq(w2, uint256(bytes32(bytes1(0x03))));
    }

    /// A struct member of struct type is one pointer word: an `Outer` is 2
    /// words, and its second word is the pointer Solidity holds for the `Foo`,
    /// not the `Foo`'s 4 words inlined.
    function testNestedStructIsOnePointerWord(uint256 x) public pure {
        Foo memory inner = Foo(1, ADDR, new uint256[](0), "");
        uint256 fmpBefore;
        assembly ("memory-safe") {
            fmpBefore := mload(0x40)
        }
        Outer memory outer = Outer(x, inner);
        uint256 ptr;
        uint256 fmpAfter;
        uint256 innerPtr;
        uint256 w0;
        uint256 w1;
        assembly ("memory-safe") {
            ptr := outer
            fmpAfter := mload(0x40)
            innerPtr := inner
            w0 := mload(outer)
            w1 := mload(add(outer, 0x20))
        }
        assertEq(ptr, fmpBefore);
        assertEq(fmpAfter - ptr, 0x40);
        assertEq(w0, x);
        assertEq(w1, innerPtr);
    }

    /// Nesting depth does not change the rule: an `Outermost` holding an
    /// `Outer` holding a `Foo` is 2 words at each level, and the pointer word
    /// at each level is the pointer to the next struct down.
    function testDeeplyNestedStructIsOnePointerWordPerLevel(uint256 x, uint256 y) public pure {
        Foo memory inner = Foo(1, ADDR, new uint256[](0), "");
        uint256 fmp0;
        assembly ("memory-safe") {
            fmp0 := mload(0x40)
        }
        Outer memory mid = Outer(x, inner);
        uint256 fmp1;
        assembly ("memory-safe") {
            fmp1 := mload(0x40)
        }
        Outermost memory outermost = Outermost(y, mid);
        uint256 fmp2;
        uint256 outermostPtr;
        uint256 midPtr;
        uint256 innerPtr;
        uint256 w1;
        uint256 midW1;
        assembly ("memory-safe") {
            fmp2 := mload(0x40)
            outermostPtr := outermost
            midPtr := mid
            innerPtr := inner
            w1 := mload(add(outermost, 0x20))
            // Follow the pointer word to the `Outer` and read its pointer word.
            midW1 := mload(add(w1, 0x20))
        }
        assertEq(midPtr, fmp0);
        assertEq(fmp1 - midPtr, 0x40);
        assertEq(outermostPtr, fmp1);
        assertEq(fmp2 - outermostPtr, 0x40);
        assertEq(w1, midPtr);
        assertEq(midW1, innerPtr);
    }

    /// `uint256[]` and `bytes` members are pointer words: the third and fourth
    /// words of a `Foo` are the pointers Solidity holds for `c` and `d`, not
    /// their contents.
    function testDynamicMembersArePointerWords(uint256[] memory c, bytes memory d) public pure {
        Foo memory f = Foo(1, ADDR, c, d);
        uint256 cPtr;
        uint256 dPtr;
        uint256 w2;
        uint256 w3;
        assembly ("memory-safe") {
            cPtr := c
            dPtr := d
            w2 := mload(add(f, 0x40))
            w3 := mload(add(f, 0x60))
        }
        assertEq(w2, cPtr);
        assertEq(w3, dPtr);
    }

    /// `new bytes(n)` allocates whole words: `new bytes(1)` moves
    /// the free memory pointer by 0x40 and `new bytes(33)` by 0x60 (the length
    /// word plus the length rounded up to a multiple of 0x20), while the
    /// length word stays 1 and 33.
    function testBytesAllocationRoundsUpToWords() public pure {
        uint256 fmp0;
        assembly ("memory-safe") {
            fmp0 := mload(0x40)
        }
        bytes memory one = new bytes(1);
        uint256 fmp1;
        uint256 onePtr;
        uint256 oneLen;
        assembly ("memory-safe") {
            fmp1 := mload(0x40)
            onePtr := one
            oneLen := mload(one)
        }
        bytes memory thirtyThree = new bytes(33);
        uint256 fmp2;
        uint256 thirtyThreePtr;
        uint256 thirtyThreeLen;
        assembly ("memory-safe") {
            fmp2 := mload(0x40)
            thirtyThreePtr := thirtyThree
            thirtyThreeLen := mload(thirtyThree)
        }
        assertEq(onePtr, fmp0);
        assertEq(fmp1 - onePtr, 0x40);
        assertEq(oneLen, 1);
        assertEq(thirtyThreePtr, fmp1);
        assertEq(fmp2 - thirtyThreePtr, 0x60);
        assertEq(thirtyThreeLen, 33);
    }

    /// The same rounding for any length: `new bytes(n)` moves the free memory
    /// pointer by 0x20 plus `n` rounded up to a multiple of 0x20, and the
    /// length word is `n`.
    function testBytesAllocationRoundsUpToWordsForAnyLength(uint16 n) public pure {
        uint256 fmpBefore;
        assembly ("memory-safe") {
            fmpBefore := mload(0x40)
        }
        bytes memory b = new bytes(n);
        uint256 fmpAfter;
        uint256 ptr;
        uint256 len;
        assembly ("memory-safe") {
            fmpAfter := mload(0x40)
            ptr := b
            len := mload(b)
        }
        assertEq(ptr, fmpBefore);
        assertEq(fmpAfter - ptr, 0x20 + ((uint256(n) + 0x1f) / 0x20) * 0x20);
        assertEq(len, n);
    }

    /// `new string(n)` allocates exactly as `new bytes(n)` does: the same
    /// rounded-up free memory pointer movement and the same length word.
    function testNewStringAllocatesLikeNewBytes(uint16 n) public pure {
        uint256 fmp0;
        assembly ("memory-safe") {
            fmp0 := mload(0x40)
        }
        bytes memory b = new bytes(n);
        uint256 fmp1;
        assembly ("memory-safe") {
            fmp1 := mload(0x40)
        }
        string memory s = new string(n);
        uint256 fmp2;
        uint256 bPtr;
        uint256 sPtr;
        uint256 bLen;
        uint256 sLen;
        assembly ("memory-safe") {
            fmp2 := mload(0x40)
            bPtr := b
            sPtr := s
            bLen := mload(b)
            sLen := mload(s)
        }
        assertEq(bPtr, fmp0);
        assertEq(sPtr, fmp1);
        assertEq(fmp1 - bPtr, 0x20 + ((uint256(n) + 0x1f) / 0x20) * 0x20);
        assertEq(fmp2 - sPtr, fmp1 - bPtr);
        assertEq(bLen, n);
        assertEq(sLen, n);
    }

    /// `string` has the layout of `bytes` with the same content: the same
    /// length word, the same bytes after it, and the same free memory pointer
    /// movement. Each copy is made by the builtin `concat` for its type.
    function testStringLayoutIsBytesLayout(bytes memory content) public pure {
        uint256 fmp0;
        assembly ("memory-safe") {
            fmp0 := mload(0x40)
        }
        bytes memory b = bytes.concat(content);
        uint256 fmp1;
        assembly ("memory-safe") {
            fmp1 := mload(0x40)
        }
        string memory s = string.concat(string(content));
        uint256 fmp2;
        uint256 bPtr;
        uint256 sPtr;
        uint256 bLen;
        uint256 sLen;
        assembly ("memory-safe") {
            fmp2 := mload(0x40)
            bPtr := b
            sPtr := s
            bLen := mload(b)
            sLen := mload(s)
        }
        assertEq(bPtr, fmp0);
        assertEq(sPtr, fmp1);
        assertEq(bLen, content.length);
        assertEq(sLen, content.length);
        assertEq(fmp2 - sPtr, fmp1 - bPtr);
        // The words after the length prefix, the last one masked to the bytes
        // within the length.
        for (uint256 i = 0; i < content.length; i += 0x20) {
            uint256 contentWord;
            uint256 bWord;
            uint256 sWord;
            assembly ("memory-safe") {
                contentWord := mload(add(add(content, 0x20), i))
                bWord := mload(add(add(b, 0x20), i))
                sWord := mload(add(add(s, 0x20), i))
            }
            uint256 remaining = content.length - i;
            if (remaining < 0x20) {
                uint256 mask = type(uint256).max << (8 * (0x20 - remaining));
                contentWord &= mask;
                bWord &= mask;
                sWord &= mask;
            }
            assertEq(bWord, contentWord);
            assertEq(sWord, bWord);
        }
    }
}
