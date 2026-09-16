// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {Foo} from "../../lib/LibFooOracle.sol";

/// The cost bullet in LibHashNoAlloc's title block says `abi.encode` of a
/// struct with one or two dynamic typed fields costs several hundred gas when
/// those fields are empty and over 1k once they hold a handful of words. Both
/// ends are measured here on the README's `Foo`, by gasleft() delta around the
/// encode alone. Each encoded length is asserted against the length the ABI
/// spec gives for that value, so the measured window provably contains the
/// encoding.
contract AbiEncodeGasTest is Test {
    /// Gas spent on `abi.encode(foo)` alone, and the length it produced.
    function encodeGas(Foo memory foo) internal view returns (uint256, uint256) {
        uint256 gasBefore = gasleft();
        bytes memory encoded = abi.encode(foo);
        uint256 gasUsed = gasBefore - gasleft();
        return (gasUsed, encoded.length);
    }

    /// `Foo` with both dynamic fields empty: one word of outer offset, 4 head
    /// words, then a length word each for `c` and `d` with no tail.
    function testEncodeFooCostsHundredsOfGasWhenEmpty() public view {
        (uint256 gasUsed, uint256 length) = encodeGas(Foo(1, address(2), new uint256[](0), ""));
        assertEq(length, 0x20 + 4 * 0x20 + 0x20 + 0x20);
        assertGt(gasUsed, 100);
        assertLt(gasUsed, 1000);
    }

    /// `Foo` with 8 words in `c` and 64 bytes in `d`: the empty encoding plus
    /// 8 words of `c` and 2 words of `d`.
    function testEncodeFooCostsOverOneThousandGasAtEightWords() public view {
        (uint256 gasUsed, uint256 length) = encodeGas(Foo(1, address(2), new uint256[](8), new bytes(64)));
        assertEq(length, 0x20 + 4 * 0x20 + 0x20 + 8 * 0x20 + 0x20 + 2 * 0x20);
        assertGt(gasUsed, 1000);
    }
}
