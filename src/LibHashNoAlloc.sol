// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev The keccak256 hash of the empty byte string, i.e. hash of no data.
bytes32 constant HASH_NIL = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;

/// @title LibHashNoAlloc
/// @notice When producing hashes of just about anything that isn't already bytes
/// the common suggestions look something like `keccak256(abi.encode(...))` or
/// `keccak256(abi.encodePacked(...))` with the main differentiation being
/// whether dynamic data types are being hashed. If they are then there is a hash
/// collision risk in the packed case as `"abc" + "def"` and `"ab" + "cdef"` will
/// pack and therefore hash to the same values, the suggested fix commonly being
/// to use abi.encode, which includes the lengths disambiguating dynamic data.
/// Something like `3"abc" + 3"def"` with the length prefixes won't collide with
/// `2"ab" + 4"cdef"` but note that ABI provides neither a strong guarantee to
/// be collision resitant on inputs (as far as I know, it's a coincidence that
/// this works), nor an efficient solution.
///
/// - Abi encoding is a complex algorithm that is easily 1k+ gas for simple
///   structs with just one or two dynamic typed fields.
/// - Abi encoding requires allocating and copying all the data plus a header to
///   a new region of memory, which gives it non-linearly increasing costs due to
///   memory expansion.
/// - Abi encoding can't easily be reproduced offchain without specialised tools,
///   it's not simply a matter of length prefixing some byte string and hashing
///   with keccak256, the heads and tails all need to be produced recursively
///   https://docs.soliditylang.org/en/develop/abi-spec.html#formal-specification-of-the-encoding
///
/// Consider that `hash(hash("abc") + hash("def"))` won't collide with
/// `hash(hash("ab") + hash("cdef"))`. It should be easier to convince ourselves
/// this is true for all possible pairs of byte strings than it is to convince
/// ourselves that the ABI serialization is never ambigious. Inductively we can
/// scale this to all possible data structures that are ordered compositions of
/// byte strings. Even better, the native behaviour of `keccak256` in the EVM
/// requires no additional allocation of memory. Worst case scenario is that we
/// want to hash several hashes together like `hash(hash0, hash1, ...)`, in which
/// case we can write the words after the free memory pointer, hash them, but
/// leave the pointer. This way we pay for memory expansion but can re-use that
/// region of memory for subsequent logic, which may effectively make the
/// expansion free as we would have needed to pay for it anyway. Given that hash
/// checks often occur early in real world logic due to
/// checks-effects-interactions, this is not an unreasonable assumption to call
/// this kind of expansion "no alloc".
///
/// One problem is that the gas saving for trivial abi encoding,
/// e.g. ~1-3 uint256 values, can be lost by the overhead of jumps and stack
/// manipulation due to function calls.
///
/// ```
/// struct Foo {
///   uint256 a;
///   address b;
///   uint32 c;
/// }
/// ```
/// The simplest way to hash `Foo` is to just hash it (crazy, i know!).
///
/// ```
/// assembly ("memory-safe") {
///   hash_ := keccak256(foo_, 0x60)
/// }
/// ```
/// Every struct field is 0x20 bytes in memory so 3 fields = 0x60 bytes to hash
/// always, with the exception of dynamic types. This costs about 70 gas vs.
/// about 350 gas for an abi encoding based approach.
library LibHashNoAlloc {
    /// Hash bytes without allocating memory.
    /// @param data The bytes to hash.
    /// @return hash The keccak256 hash of the bytes.
    function hashBytes(bytes memory data) internal pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            hash := keccak256(add(data, 0x20), mload(data))
        }
    }

    /// Hash an array of bytes32 words without allocating memory.
    /// @param words The words to hash.
    /// @return hash The keccak256 hash of the words.
    function hashWords(bytes32[] memory words) internal pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            hash := keccak256(add(words, 0x20), mul(mload(words), 0x20))
        }
    }

    /// Hash an array of uint256 words without allocating memory.
    /// @param words The words to hash.
    /// @return hash The keccak256 hash of the words.
    function hashWords(uint256[] memory words) internal pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            hash := keccak256(add(words, 0x20), mul(mload(words), 0x20))
        }
    }

    /// Combine two hashes into one by hashing their concatenation.
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
