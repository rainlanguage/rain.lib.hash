// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {Foo} from "../../lib/LibFooOracle.sol";
import {LibMemorySnapshot} from "../../lib/LibMemorySnapshot.sol";

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

/// A one-field struct: a reference type that is exactly one word wide.
struct One {
    uint256 v;
}

/// Three reference members that are each exactly one word wide. Each is one
/// pointer word of the `OneWordRefs`, so it is 4 words like `Foo`.
struct OneWordRefs {
    uint256 x;
    uint256[1] arr;
    One one;
    bytes32[1] barr;
}

/// A static array member wider than one word: one pointer word, not two
/// inlined words.
struct WithStaticArray {
    uint256 x;
    uint256[2] arr;
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
    uint32 constant FILL_UINT = 0x22222222;
    int8 constant FILL_INT = -3;
    bytes4 constant FILL_BYTES = 0x44444444;

    /// The word at byte `offset` of the struct's memory.
    function word(SubWord memory subWord, uint256 offset) internal pure returns (uint256) {
        uint256 ptr;
        assembly ("memory-safe") {
            ptr := subWord
        }
        return LibMemorySnapshot.wordAt(ptr, offset);
    }

    /// The free memory pointer, the pointer to `b` and its length word.
    function bytesLayout(bytes memory b) internal pure returns (uint256, uint256, uint256) {
        uint256 ptr;
        assembly ("memory-safe") {
            ptr := b
        }
        return (LibMemorySnapshot.freeMemoryPointer(), ptr, LibMemorySnapshot.wordAt(ptr, 0));
    }

    /// Every sub-word member occupies a full word: six members allocate six
    /// words.
    function testSubWordMembersOccupyFullWords() public pure {
        uint256 fmpBefore = LibMemorySnapshot.freeMemoryPointer();
        SubWord memory subWord = SubWord(true, ADDR, FILL_UINT, Colour.Green, FILL_INT, FILL_BYTES);
        uint256 fmpAfter = LibMemorySnapshot.freeMemoryPointer();
        uint256 ptr;
        assembly ("memory-safe") {
            ptr := subWord
        }
        assertEq(ptr, fmpBefore);
        assertEq(fmpAfter - ptr, 6 * 0x20);
    }

    /// `bool` is right-aligned and zero-padded: `true` is the word 1, `false`
    /// the word 0.
    function testBoolIsZeroPadded(bool flag) public pure {
        SubWord memory subWord = SubWord(flag, ADDR, FILL_UINT, Colour.Green, FILL_INT, FILL_BYTES);
        assertEq(word(subWord, 0x00), uint256(flag ? 1 : 0));
    }

    /// `address` is right-aligned and zero-padded: the word is the `uint160`
    /// value.
    function testAddressIsZeroPadded(address addr) public pure {
        SubWord memory subWord = SubWord(true, addr, FILL_UINT, Colour.Green, FILL_INT, FILL_BYTES);
        assertEq(word(subWord, 0x20), uint256(uint160(addr)));
    }

    /// Unsigned integers are right-aligned and zero-padded: the word is the
    /// `uint256` value.
    function testUnsignedIntIsZeroPadded(uint32 unsigned) public pure {
        SubWord memory subWord = SubWord(true, ADDR, unsigned, Colour.Green, FILL_INT, FILL_BYTES);
        assertEq(word(subWord, 0x40), uint256(unsigned));
    }

    /// Enums are right-aligned and zero-padded: the word is the value's
    /// `uint8`.
    function testEnumIsZeroPadded() public pure {
        for (uint8 colourValue = 0; colourValue <= uint8(type(Colour).max); colourValue++) {
            Colour colour = Colour(colourValue);
            SubWord memory subWord = SubWord(true, ADDR, FILL_UINT, colour, FILL_INT, FILL_BYTES);
            assertEq(word(subWord, 0x60), uint256(uint8(colour)));
        }
    }

    /// Signed integers are right-aligned and sign-extended: the word is
    /// `uint256(int256(x))`, not the zero-padded `uint256(uint8(x))`.
    function testSignedIntIsSignExtended(int8 signed) public pure {
        SubWord memory subWord = SubWord(true, ADDR, FILL_UINT, Colour.Green, signed, FILL_BYTES);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(word(subWord, 0x80), uint256(int256(signed)));
    }

    /// The README's example: `int8(-1)` is `0xff…ff`, not `0x00…ff`.
    function testInt8MinusOneIsAllOnes() public pure {
        SubWord memory subWord = SubWord(true, ADDR, FILL_UINT, Colour.Green, -1, FILL_BYTES);
        uint256 memoryWord = word(subWord, 0x80);
        assertEq(memoryWord, type(uint256).max);
    }

    /// `bytesN` is left-aligned and zero-padded on the right: the word is
    /// `uint256(bytes32(x))`, not the right-aligned `uint256(uint32(x))`.
    function testFixedBytesIsLeftAligned(bytes4 fixedBytes) public pure {
        SubWord memory subWord = SubWord(true, ADDR, FILL_UINT, Colour.Green, FILL_INT, fixedBytes);
        assertEq(word(subWord, 0xa0), uint256(bytes32(fixedBytes)));
    }

    /// The README's example: `bytes4(0x01020304)` is `0x01020304` followed by
    /// 28 zero bytes, not `0x00…01020304`.
    function testBytes4ExampleIsLeftAligned() public pure {
        SubWord memory subWord = SubWord(true, ADDR, FILL_UINT, Colour.Green, FILL_INT, bytes4(0x01020304));
        uint256 memoryWord = word(subWord, 0xa0);
        assertEq(memoryWord, uint256(0x01020304) << 224);
    }

    /// A `Foo` is a 4-word region: `uint256`, `address`, `uint256[]` and
    /// `bytes` are each one word of the struct.
    function testFooIsFourWords() public pure {
        uint256[] memory c = new uint256[](0);
        bytes memory d = "";
        // c and d are already allocated, so the struct is the only allocation
        // between fmpBefore and fmpAfter.
        uint256 fmpBefore = LibMemorySnapshot.freeMemoryPointer();
        Foo memory foo = Foo(1, address(2), c, d);
        uint256 fmpAfter = LibMemorySnapshot.freeMemoryPointer();
        uint256 ptr;
        assembly ("memory-safe") {
            ptr := foo
        }
        assertEq(ptr, fmpBefore);
        assertEq(fmpAfter - ptr, 0x80);
    }

    /// `bytes1[]` is a list of words: a length prefix then one full word per
    /// element, each element left-aligned like any `bytesN`.
    function testBytes1ArrayIsWordList() public pure {
        uint256 fmpBefore = LibMemorySnapshot.freeMemoryPointer();
        bytes1[] memory arr = new bytes1[](3);
        arr[0] = 0x01;
        arr[1] = 0x02;
        arr[2] = 0x03;
        uint256 fmpAfter = LibMemorySnapshot.freeMemoryPointer();
        uint256 ptr;
        assembly ("memory-safe") {
            ptr := arr
        }
        assertEq(ptr, fmpBefore);
        assertEq(LibMemorySnapshot.wordAt(ptr, 0), 3);
        assertEq(fmpAfter - ptr, 0x20 + 3 * 0x20);
        assertEq(LibMemorySnapshot.wordAt(ptr, 0x20), uint256(bytes32(bytes1(0x01))));
        assertEq(LibMemorySnapshot.wordAt(ptr, 0x40), uint256(bytes32(bytes1(0x02))));
        assertEq(LibMemorySnapshot.wordAt(ptr, 0x60), uint256(bytes32(bytes1(0x03))));
    }

    /// A struct member of struct type is one pointer word: an `Outer` is 2
    /// words, and its second word is the pointer Solidity holds for the `Foo`,
    /// not the `Foo`'s 4 words inlined.
    function testNestedStructIsOnePointerWord(uint256 x) public pure {
        Foo memory inner = Foo(1, ADDR, new uint256[](0), "");
        uint256 fmpBefore = LibMemorySnapshot.freeMemoryPointer();
        Outer memory outer = Outer(x, inner);
        uint256 fmpAfter = LibMemorySnapshot.freeMemoryPointer();
        uint256 ptr;
        uint256 innerPtr;
        assembly ("memory-safe") {
            ptr := outer
            innerPtr := inner
        }
        assertEq(ptr, fmpBefore);
        assertEq(fmpAfter - ptr, 0x40);
        assertEq(LibMemorySnapshot.wordAt(ptr, 0), x);
        assertEq(LibMemorySnapshot.wordAt(ptr, 0x20), innerPtr);
    }

    function testDeeplyNestedStructIsOnePointerWordPerLevel(uint256 x, uint256 y) public pure {
        Foo memory inner = Foo(1, ADDR, new uint256[](0), "");
        uint256 fmp0 = LibMemorySnapshot.freeMemoryPointer();
        Outer memory mid = Outer(x, inner);
        uint256 fmp1 = LibMemorySnapshot.freeMemoryPointer();
        Outermost memory outermost = Outermost(y, mid);
        uint256 fmp2 = LibMemorySnapshot.freeMemoryPointer();
        uint256 outermostPtr;
        uint256 midPtr;
        uint256 innerPtr;
        assembly ("memory-safe") {
            outermostPtr := outermost
            midPtr := mid
            innerPtr := inner
        }
        uint256 w1 = LibMemorySnapshot.wordAt(outermostPtr, 0x20);
        // Follow the pointer word to the `Outer` and read its pointer word.
        uint256 midW1 = LibMemorySnapshot.wordAt(w1, 0x20);
        assertEq(midPtr, fmp0);
        assertEq(fmp1 - midPtr, 0x40);
        assertEq(outermostPtr, fmp1);
        assertEq(fmp2 - outermostPtr, 0x40);
        assertEq(w1, midPtr);
        assertEq(midW1, innerPtr);

        // Reusing dead locals; two more would be stack-too-deep.
        assembly ("memory-safe") {
            w1 := mload(outermost)
            midW1 := mload(midPtr)
        }
        assertEq(w1, y);
        assertEq(midW1, x);
    }

    function testNewFooArrayAllocatesListThenElements(uint8 length) public pure {
        uint256 n = length;
        uint256 fmpBefore;
        assembly ("memory-safe") {
            fmpBefore := mload(0x40)
        }
        Foo[] memory foos = new Foo[](n);
        uint256 ptr;
        uint256 fmpAfter;
        assembly ("memory-safe") {
            ptr := foos
            fmpAfter := mload(0x40)
        }
        assertEq(ptr, fmpBefore);
        assertEq(fmpAfter - ptr, 0x20 + n * 0x20 + n * 0x80);

        for (uint256 i = 0; i < n; i++) {
            Foo memory foo = foos[i];
            uint256 fooPointer;
            uint256 w0;
            uint256 w1;
            uint256 w2;
            uint256 w3;
            assembly ("memory-safe") {
                fooPointer := foo
                w0 := mload(foo)
                w1 := mload(add(foo, 0x20))
                w2 := mload(add(foo, 0x40))
                w3 := mload(add(foo, 0x60))
            }
            assertEq(fooPointer, ptr + 0x20 + n * 0x20 + i * 0x80);
            assertEq(w0, 0);
            assertEq(w1, 0);
            assertEq(w2, 0x60);
            assertEq(w3, 0x60);
            assertEq(foo.c.length, 0);
            assertEq(foo.d.length, 0);
        }
    }

    /// `uint256[]` and `bytes` members are pointer words: the third and fourth
    /// words of a `Foo` are the pointers Solidity holds for `c` and `d`, not
    /// their contents.
    function testDynamicMembersArePointerWords(uint256[] memory c, bytes memory d) public pure {
        Foo memory foo = Foo(1, ADDR, c, d);
        uint256 fooPtr;
        uint256 cPtr;
        uint256 dPtr;
        assembly ("memory-safe") {
            fooPtr := foo
            cPtr := c
            dPtr := d
        }
        assertEq(LibMemorySnapshot.wordAt(fooPtr, 0x40), cPtr);
        assertEq(LibMemorySnapshot.wordAt(fooPtr, 0x60), dPtr);
    }

    /// Reference members that are exactly one word wide are still pointer
    /// words: an `OneWordRefs` is 4 words, and words 1 to 3 are the pointers
    /// Solidity holds for the `uint256[1]`, the one-field `One` and the
    /// `bytes32[1]`, not the single values 7, 8 and 9 they hold.
    function testOneWordReferenceMembersArePointerWords(uint256 x) public pure {
        uint256[1] memory arr = [uint256(7)];
        One memory one = One(8);
        bytes32[1] memory barr = [bytes32(uint256(9))];
        // Scratch for the words read back, allocated before the struct so the
        // struct is the only allocation between the two free memory pointer
        // reads.
        uint256[4] memory w;
        uint256[3] memory p;
        uint256 fmpBefore;
        assembly ("memory-safe") {
            fmpBefore := mload(0x40)
        }
        OneWordRefs memory s = OneWordRefs(x, arr, one, barr);
        uint256 ptr;
        uint256 size;
        assembly ("memory-safe") {
            ptr := s
            size := sub(mload(0x40), s)
            mstore(p, arr)
            mstore(add(p, 0x20), one)
            mstore(add(p, 0x40), barr)
            mstore(w, mload(s))
            mstore(add(w, 0x20), mload(add(s, 0x20)))
            mstore(add(w, 0x40), mload(add(s, 0x40)))
            mstore(add(w, 0x60), mload(add(s, 0x60)))
        }
        assertEq(ptr, fmpBefore);
        assertEq(size, 0x80);
        assertEq(w[0], x);
        assertEq(w[1], p[0]);
        assertEq(w[2], p[1]);
        assertEq(w[3], p[2]);
        assertNotEq(w[1], 7);
        assertNotEq(w[2], 8);
        assertNotEq(w[3], 9);
    }

    /// A static array member is one pointer word whatever its length: a
    /// `WithStaticArray` is 2 words and its second word is the pointer
    /// Solidity holds for the `uint256[2]`, not the array's 2 words inlined.
    function testStaticArrayMemberIsPointerWord(uint256 x, uint256[2] memory arr) public pure {
        uint256 fmpBefore;
        assembly ("memory-safe") {
            fmpBefore := mload(0x40)
        }
        WithStaticArray memory s = WithStaticArray(x, arr);
        uint256 ptr;
        uint256 size;
        uint256 arrPtr;
        uint256 w0;
        uint256 w1;
        assembly ("memory-safe") {
            ptr := s
            size := sub(mload(0x40), s)
            arrPtr := arr
            w0 := mload(s)
            w1 := mload(add(s, 0x20))
        }
        assertEq(ptr, fmpBefore);
        assertEq(size, 0x40);
        assertEq(w0, x);
        assertEq(w1, arrPtr);
    }

    /// `new bytes(n)` allocates whole words: `new bytes(1)` moves
    /// the free memory pointer by 0x40 and `new bytes(33)` by 0x60 (the length
    /// word plus the length rounded up to a multiple of 0x20), while the
    /// length word stays 1 and 33.
    function testBytesAllocationRoundsUpToWords() public pure {
        uint256 fmp0 = LibMemorySnapshot.freeMemoryPointer();
        bytes memory one = new bytes(1);
        (uint256 fmp1, uint256 onePtr, uint256 oneLen) = bytesLayout(one);
        bytes memory thirtyThree = new bytes(33);
        (uint256 fmp2, uint256 thirtyThreePtr, uint256 thirtyThreeLen) = bytesLayout(thirtyThree);
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
    function testBytesAllocationRoundsUpToWordsForAnyLength(uint16 length) public pure {
        uint256 fmpBefore = LibMemorySnapshot.freeMemoryPointer();
        bytes memory allocated = new bytes(length);
        (uint256 fmpAfter, uint256 ptr, uint256 len) = bytesLayout(allocated);
        assertEq(ptr, fmpBefore);
        assertEq(fmpAfter - ptr, LibMemorySnapshot.wordAlignedAllocation(length));
        assertEq(len, length);
    }

    /// `new string(n)` allocates exactly as `new bytes(n)` does: the same
    /// rounded-up free memory pointer movement and the same length word.
    function testNewStringAllocatesLikeNewBytes(uint16 length) public pure {
        uint256 fmp0 = LibMemorySnapshot.freeMemoryPointer();
        bytes memory allocatedBytes = new bytes(length);
        uint256 fmp1 = LibMemorySnapshot.freeMemoryPointer();
        string memory allocatedString = new string(length);
        (uint256 fmp2, uint256 stringPtr, uint256 stringLen) = bytesLayout(bytes(allocatedString));
        (, uint256 bytesPtr, uint256 bytesLen) = bytesLayout(allocatedBytes);
        assertEq(bytesPtr, fmp0);
        assertEq(stringPtr, fmp1);
        assertEq(fmp1 - bytesPtr, LibMemorySnapshot.wordAlignedAllocation(length));
        assertEq(fmp2 - stringPtr, fmp1 - bytesPtr);
        assertEq(bytesLen, length);
        assertEq(stringLen, length);
    }

    /// `string` has the layout of `bytes` with the same content: the same
    /// length word, the same bytes after it, and the same free memory pointer
    /// movement. Each copy is made by the builtin `concat` for its type.
    function testStringLayoutIsBytesLayout(bytes memory content) public pure {
        uint256 fmp0 = LibMemorySnapshot.freeMemoryPointer();
        bytes memory allocatedBytes = bytes.concat(content);
        uint256 fmp1 = LibMemorySnapshot.freeMemoryPointer();
        string memory allocatedString = string.concat(string(content));
        (uint256 fmp2, uint256 stringPtr, uint256 stringLen) = bytesLayout(bytes(allocatedString));
        (, uint256 bytesPtr, uint256 bytesLen) = bytesLayout(allocatedBytes);
        assertEq(bytesPtr, fmp0);
        assertEq(stringPtr, fmp1);
        assertEq(bytesLen, content.length);
        assertEq(stringLen, content.length);
        assertEq(fmp2 - stringPtr, fmp1 - bytesPtr);
        checkDataWordsAreContent(content, bytesPtr, stringPtr);
    }

    /// The words after the length prefix of the copies at `bytesPtr` and
    /// `stringPtr` are `content`'s words, the last one masked to the bytes
    /// within the length. A separate frame so the caller's locals do not
    /// overflow the stack.
    function checkDataWordsAreContent(bytes memory content, uint256 bytesPtr, uint256 stringPtr) internal pure {
        (, uint256 contentPtr,) = bytesLayout(content);
        for (uint256 i = 0; i < content.length; i += 0x20) {
            uint256 contentWord = LibMemorySnapshot.wordAt(contentPtr, 0x20 + i);
            uint256 bytesWord = LibMemorySnapshot.wordAt(bytesPtr, 0x20 + i);
            uint256 stringWord = LibMemorySnapshot.wordAt(stringPtr, 0x20 + i);
            uint256 remaining = content.length - i;
            if (remaining < 0x20) {
                uint256 mask = type(uint256).max << (8 * (0x20 - remaining));
                contentWord &= mask;
                bytesWord &= mask;
                stringWord &= mask;
            }
            assertEq(bytesWord, contentWord);
            assertEq(stringWord, bytesWord);
        }
    }
}
