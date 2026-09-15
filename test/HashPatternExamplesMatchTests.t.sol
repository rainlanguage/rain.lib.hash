// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test, Vm} from "forge-std-1.16.1/src/Test.sol";

/// The `Foo` README.md "The pattern" hashes; its layout decides the literals
/// the README examples carry.
struct Foo {
    uint256 a;
    address b;
    uint256[] c;
    bytes d;
}

/// The Yul examples README.md "The pattern" prints are the ones the pattern
/// tests execute, and the sizes and offsets their literals carry are the
/// compiler's layout of the types they hash. README.md is read as the
/// canonical text; the test sources are read and searched for each example.
contract HashPatternExamplesMatchTestsTest is Test {
    uint256 constant NOT_FOUND = type(uint256).max;

    /// Whitespace-free, lowercase, with Yul `let` removed so a README `let x :=`
    /// matches a test `x :=` that assigns a Solidity variable instead.
    function normalize(string memory s) internal pure returns (string memory) {
        s = vm.replace(s, " ", "");
        s = vm.replace(s, "\t", "");
        s = vm.replace(s, "\n", "");
        s = vm.toLowercase(s);
        return vm.replace(s, "let", "");
    }

    /// Every fenced ```solidity block of README.md, fence lines excluded.
    function readmeSolidityBlocks() internal view returns (string[] memory blocks) {
        string[] memory segments = vm.split(vm.readFile("README.md"), "```solidity\n");
        blocks = new string[](segments.length - 1);
        for (uint256 i = 1; i < segments.length; i++) {
            blocks[i - 1] = vm.split(segments[i], "\n```")[0];
        }
    }

    /// The hex literal Solidity prints for a byte count below 0x100.
    function hexLiteral(uint256 n) internal pure returns (string memory) {
        return vm.toString(abi.encodePacked(uint8(n)));
    }

    /// Every README `assembly` example appears, normalized, in the pattern
    /// tests, so the tests execute the text the README shows.
    function testAssemblyExamplesAppearInPatternTests() public view {
        string memory patternTests = normalize(vm.readFile("test/HashPattern.t.sol"));
        string[] memory blocks = readmeSolidityBlocks();
        uint256 assemblyBlocks = 0;
        for (uint256 i = 0; i < blocks.length; i++) {
            if (vm.indexOf(blocks[i], "assembly") == 0) {
                assemblyBlocks++;
                assertTrue(vm.indexOf(patternTests, normalize(blocks[i])) != NOT_FOUND, blocks[i]);
            }
        }
        assertEq(assemblyBlocks, 4);
    }

    /// The README `struct Foo` is the `Foo` that every test file declaring a
    /// `Foo` declares. The files are found rather than listed, so a new one
    /// cannot drift unwatched.
    function testStructFooAppearsInEveryFooTest() public view {
        string[] memory blocks = readmeSolidityBlocks();
        string memory structBlock;
        for (uint256 i = 0; i < blocks.length; i++) {
            if (vm.indexOf(blocks[i], "struct Foo") == 0) {
                structBlock = blocks[i];
            }
        }
        assertTrue(bytes(structBlock).length > 0);
        string memory needle = normalize(structBlock);
        Vm.DirEntry[] memory entries = vm.readDir("test");
        uint256 fooFiles = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].isDir) continue;
            string memory source = normalize(vm.readFile(entries[i].path));
            if (vm.indexOf(source, "structfoo{") == NOT_FOUND) continue;
            fooFiles++;
            assertTrue(vm.indexOf(source, needle) != NOT_FOUND, entries[i].path);
        }
        assertEq(fooFiles, 4);
    }

    /// The `0x80` in `keccak256(foo_, 0x80)` is the size the compiler gives a
    /// `Foo`, and the `0x40` and `0x60` the "Handling pointers" example reads
    /// `c` and `d` at are the offsets the compiler stores them at.
    function testExampleLiteralsAreCompilerLayout() public view {
        uint256[] memory c = new uint256[](0);
        bytes memory d = "";
        Foo memory foo_ = Foo(1, address(2), c, d);
        uint256 size;
        uint256 cOffset = NOT_FOUND;
        uint256 dOffset = NOT_FOUND;
        assembly ("memory-safe") {
            size := sub(mload(0x40), foo_)
            for { let off := 0 } lt(off, size) { off := add(off, 0x20) } {
                let w := mload(add(foo_, off))
                if eq(w, c) { cOffset := off }
                if eq(w, d) { dOffset := off }
            }
        }
        string memory readme = vm.readFile("README.md");
        assertTrue(vm.contains(readme, string.concat("keccak256(foo_, ", hexLiteral(size), ")")));
        assertTrue(vm.contains(readme, string.concat("keccak256(foo_, ", hexLiteral(cOffset), ")")));
        assertTrue(vm.contains(readme, string.concat("mload(add(foo_, ", hexLiteral(cOffset), "))")));
        assertTrue(vm.contains(readme, string.concat("mload(add(foo_, ", hexLiteral(dOffset), "))")));
        assertTrue(
            vm.contains(readme, string.concat("a `Foo` is ALWAYS 4 words, i.e. ", hexLiteral(size), " bytes long"))
        );
    }
}
