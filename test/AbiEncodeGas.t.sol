// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {Foo} from "./lib/LibFooOracle.sol";

contract AbiEncodeGasTest is Test {
    function encodeGas(Foo memory foo) internal view returns (uint256, uint256) {
        uint256 gasBefore = gasleft();
        bytes memory encoded = abi.encode(foo);
        uint256 gasUsed = gasBefore - gasleft();
        return (gasUsed, encoded.length);
    }

    function testEncodeFooCostsHundredsOfGasWhenEmpty() public view {
        (uint256 gasUsed, uint256 length) = encodeGas(Foo(1, address(2), new uint256[](0), ""));
        assertEq(length, 0x20 + 4 * 0x20 + 0x20 + 0x20);
        assertGt(gasUsed, 100);
        assertLt(gasUsed, 1000);
    }

    function testEncodeFooCostsOverOneThousandGasAtEightWords() public view {
        (uint256 gasUsed, uint256 length) = encodeGas(Foo(1, address(2), new uint256[](8), new bytes(64)));
        assertEq(length, 0x20 + 4 * 0x20 + 0x20 + 8 * 0x20 + 0x20 + 2 * 0x20);
        assertGt(gasUsed, 1000);
    }
}
