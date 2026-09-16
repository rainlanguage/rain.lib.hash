// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev `keccak256` of the 3 bytes `abc`.
bytes32 constant HASH_ABC = 0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45;

/// @dev `keccak256` of the 64 bytes that are the word `1` then the word `2`.
bytes32 constant HASH_WORDS_ONE_TWO = 0xe90b7bceb6e7df5418fb78d8ee546e97c83a08bbccc01a0644d599ccd2a7c2e0;

/// Builtin-only reference for every `LibHashNoAlloc` function, so equality
/// against it pins the value each one computes without reusing its assembly.
/// "Slow" is about allocation: the `hashWordsSlow` and `combineHashesSlow`
/// bodies copy their data into a fresh `abi.encodePacked` buffer before
/// hashing it, which is the cost the `gasleft()` deltas in
/// `LibHashNoAlloc.t.sol` measure against. `hashBytesSlow` does not, so it is a
/// value oracle only.
library LibHashSlow {
    /// The builtin `keccak256` over the bytes, which allocates nothing.
    /// `LibHashNoAlloc.hashBytes` compiles to the same hash of the same range,
    /// so this pins its value and there is no saving to measure against it.
    function hashBytesSlow(bytes memory data) internal pure returns (bytes32) {
        return keccak256(data);
    }

    function hashWordsSlow(bytes32[] memory words) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(words));
    }

    function hashWordsSlow(uint256[] memory words) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(words));
    }

    function combineHashesSlow(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(a, b));
    }
}
