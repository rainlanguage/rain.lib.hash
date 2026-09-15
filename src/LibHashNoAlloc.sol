// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev The keccak256 hash of the empty byte string, i.e. hash of no data.
/// `hashBytes` of empty bytes and `hashWords` of an empty array of either type
/// both evaluate to it.
bytes32 constant HASH_NIL = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;

/// @title LibHashNoAlloc
/// @notice Reference implementation of the no-allocation hashing pattern
/// specified in this repo's README ("The pattern" and "Security of
/// composition", https://github.com/rainlanguage/rain.lib.hash#the-pattern).
/// Every function hashes raw memory with no type, length or domain tag; hashes
/// are only comparable with hashes of values of the same type, and each
/// function's notes below list what collides across types.
///
/// The functions taking a memory reference read the length word the type
/// guarantees; a reference whose length word does not describe its allocation
/// is a memory-safety violation by the caller and, like all such violations,
/// undefined.
library LibHashNoAlloc {
    /// Hash bytes. Solidity's own `keccak256(data)` already compiles to this
    /// same `keccak256(add(data, 0x20), mload(data))` with no allocation, so
    /// this saves nothing over it and exists only so `bytes` hash through the
    /// same API as words.
    /// Hashes the `mload(data)` bytes starting at `data + 0x20`.
    /// Only the raw bytes are hashed, with no type or length tag. For `data` of
    /// length `32n` the result equals `hashWords` over those `n` words, and for
    /// `data` equal to the 64 bytes of `a` followed by `b` it equals
    /// `combineHashes(a, b)`: a `bytes` leaf whose content is two hashes is
    /// indistinguishable from the node built from those hashes.
    /// @param data The bytes to hash.
    /// @return hash The keccak256 hash of the bytes.
    function hashBytes(bytes memory data) internal pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            hash := keccak256(add(data, 0x20), mload(data))
        }
    }

    /// Hash an array of bytes32 words without allocating memory.
    /// Hashes the `mload(words) * 0x20` bytes starting at `words + 0x20`.
    /// The length word is not hashed: the result is the hash of the `32n` raw
    /// bytes of the `n` words, so it equals `hashBytes` over those bytes and the
    /// `uint256[]` overload over the same words, and for `n` = 2 it equals
    /// `combineHashes(words[0], words[1])`. An empty array hashes to `HASH_NIL`.
    /// @param words The words to hash.
    /// @return hash The keccak256 hash of the words.
    function hashWords(bytes32[] memory words) internal pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            hash := keccak256(add(words, 0x20), mul(mload(words), 0x20))
        }
    }

    /// Hash an array of uint256 words without allocating memory.
    /// Hashes the `mload(words) * 0x20` bytes starting at `words + 0x20`.
    /// Identical to the `bytes32[]` overload over the same words, including its
    /// equalities with `hashBytes` and `combineHashes`.
    /// @param words The words to hash.
    /// @return hash The keccak256 hash of the words.
    function hashWords(uint256[] memory words) internal pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            hash := keccak256(add(words, 0x20), mul(mload(words), 0x20))
        }
    }

    /// Combine two hashes into one by hashing their concatenation.
    /// The result is the hash of the raw 64 bytes of `a` followed by `b`, so it
    /// equals `hashBytes` over those 64 bytes and `hashWords` over `[a, b]`. A
    /// node is distinguishable from a leaf only by the type of the position it
    /// fills in a composition, never by its hash.
    /// @param a The first hash.
    /// @param b The second hash.
    /// @return hash The combined hash.
    function combineHashes(bytes32 a, bytes32 b) internal pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            mstore(0, a)
            mstore(0x20, b)
            hash := keccak256(0, 0x40)
        }
    }
}
