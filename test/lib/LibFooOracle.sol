// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// The struct README.md hashes in "The pattern", folds a list of in "Handling
/// pointers" and lays out in "Memory layout": a 4-word region, one word per
/// member whatever the member's type.
struct Foo {
    uint256 a;
    address b;
    uint256[] c;
    bytes d;
}

/// The README's hash of one `Foo`, steps A to E, from builtins only.
library LibFooOracle {
    /// A is the first two words, B the word list `c`, C combines A and B, D the
    /// bytes `d`, E combines C and D.
    function hashFoo(Foo memory foo) internal pure returns (bytes32) {
        bytes32 hashA = keccak256(abi.encode(foo.a, foo.b));
        bytes32 hashB = keccak256(abi.encodePacked(foo.c));
        bytes32 hashC = keccak256(abi.encodePacked(hashA, hashB));
        bytes32 hashD = keccak256(foo.d);
        return keccak256(abi.encodePacked(hashC, hashD));
    }
}
