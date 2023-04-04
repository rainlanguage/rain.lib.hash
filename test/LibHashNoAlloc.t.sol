// SPDX-License-Identifier: CAL
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../src/LibHashNoAlloc.sol";

contract LibHashNoAllocTest is Test {
    function testHashNil() public {
        bytes32 hashNil_;
        assembly ("memory-safe") {
            hashNil_ := keccak256(0, 0)
        }
        assertEq(
            HASH_NIL,
            hashNil_
        );
        assertEq(
            HASH_NIL,
            keccak256("")
        );
    }

    function testHashBytes(bytes memory bytes_) public {
        assertEq(
            LibHashNoAlloc.hashBytes(bytes_),
            keccak256(bytes_)
        );
    }

    function testHashWords(uint256[] memory words_) public {

    }
}