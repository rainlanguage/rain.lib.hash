// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {VmSafe} from "forge-std-1.16.1/src/Vm.sol";

/// @title CompilerVersionSpreadTest
/// @notice `foundry.toml` is the single compiler version the repo is built and
/// tested at. Every other statement of a compiler version -- the pragma of each
/// `.sol` file, and every Solidity documentation citation in the sources and the
/// README -- has to name that same version, and every citation of another repo
/// has to name an immutable ref rather than a branch that moves under it.
contract CompilerVersionSpreadTest is Test {
    function solcPin() internal view returns (string memory) {
        return vm.parseTomlString(vm.readFile("foundry.toml"), ".profile.default.solc");
    }

    function pragmaLineOf(string memory path) internal view returns (string memory) {
        string[] memory lines = vm.split(vm.readFile(path), "\n");
        for (uint256 i = 0; i < lines.length; i++) {
            if (vm.indexOf(lines[i], "pragma solidity ") == 0) {
                return lines[i];
            }
        }
        revert(string.concat("no pragma in ", path));
    }

    function checkPragmas(string memory dir, string memory solc) internal view returns (uint256) {
        bytes32 pinned = keccak256(bytes(string.concat("pragma solidity ", solc, ";")));
        bytes32 floating = keccak256(bytes(string.concat("pragma solidity ^", solc, ";")));
        VmSafe.DirEntry[] memory entries = vm.readDir(dir, 8);
        uint256 checked = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].isDir || !vm.contains(entries[i].path, ".sol")) {
                continue;
            }
            string memory line = pragmaLineOf(entries[i].path);
            bytes32 actual = keccak256(bytes(line));
            assertTrue(
                actual == pinned || actual == floating,
                string.concat(entries[i].path, " states `", line, "` against solc ", solc)
            );
            checked++;
        }
        return checked;
    }

    function checkSolidityDocs(string memory path, string memory solc) internal view {
        string[] memory cited = vm.split(vm.readFile(path), "docs.soliditylang.org/en/");
        for (uint256 i = 1; i < cited.length; i++) {
            assertEq(
                vm.indexOf(cited[i], string.concat("v", solc, "/")),
                0,
                string.concat(path, " cites Solidity docs that are not v", solc)
            );
        }
    }

    function testPragmasStateTheSolcPin() external view {
        string memory solc = solcPin();
        assertGt(checkPragmas("src", solc), 0, "no sol under src");
        assertGt(checkPragmas("test", solc), 0, "no sol under test");
    }

    function testSolidityDocsCitationsNameTheSolcPin() external view {
        string memory solc = solcPin();
        checkSolidityDocs("README.md", solc);
        checkSolidityDocs("src/LibHashNoAlloc.sol", solc);
    }

    function testForeignSourceCitationsAreImmutable() external view {
        string memory readme = vm.readFile("README.md");
        assertFalse(vm.contains(readme, "/blob/main/"), "README cites a blob on a moving branch");
        assertFalse(vm.contains(readme, "/blob/master/"), "README cites a blob on a moving branch");
    }
}
