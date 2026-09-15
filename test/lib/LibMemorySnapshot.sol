// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// The memory reads the suites measure with. Each is a single `mload` that
/// allocates nothing, so a pair of reads taken around the code under test
/// measures only that code.
library LibMemorySnapshot {
    /// The free memory pointer.
    function freeMemoryPointer() internal pure returns (uint256) {
        uint256 fmp;
        assembly ("memory-safe") {
            fmp := mload(0x40)
        }
        return fmp;
    }

    /// The zero slot.
    function zeroSlot() internal pure returns (uint256) {
        uint256 slot;
        assembly ("memory-safe") {
            slot := mload(0x60)
        }
        return slot;
    }

    /// The word at byte `offset` of the memory at `pointer`.
    function wordAt(uint256 pointer, uint256 offset) internal pure returns (uint256) {
        uint256 w;
        assembly ("memory-safe") {
            w := mload(add(pointer, offset))
        }
        return w;
    }

    /// The memory a `bytes` or `string` of `length` bytes occupies: the length
    /// word plus the data rounded up to whole words.
    function wordAlignedAllocation(uint256 length) internal pure returns (uint256) {
        return 0x20 + ((length + 0x1f) & ~uint256(0x1f));
    }
}
