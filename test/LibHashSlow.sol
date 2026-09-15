// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

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

    /// `abi.encodePacked` copies the `32n` bytes of the `n` words, without the
    /// length word, to a fresh allocation, then hashes it.
    function hashWordsSlow(bytes32[] memory words) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(words));
    }

    /// The `uint256[]` case of the same copy-then-hash.
    function hashWordsSlow(uint256[] memory words) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(words));
    }

    /// `abi.encodePacked` allocates the 64 bytes of `a` followed by `b`, then
    /// hashes them, where `combineHashes` hashes the same two words in scratch
    /// space.
    function combineHashesSlow(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(a, b));
    }
}
