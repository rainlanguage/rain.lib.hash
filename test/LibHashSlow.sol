// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.18;

library LibHashSlow {
    function hashBytesSlow(bytes memory data_) internal pure returns (bytes32 hash_) {
        return keccak256(data_);
    }

    function hashWordsSlow(bytes32[] memory words_) internal pure returns (bytes32 hash_) {
        return keccak256(abi.encodePacked(words_));
    }

    function hashWordsSlow(uint256[] memory words_) internal pure returns (bytes32 hash_) {
        return keccak256(abi.encodePacked(words_));
    }

    function combineHashesSlow(bytes32 a_, bytes32 b_) internal pure returns (bytes32 hash_) {
        return keccak256(abi.encodePacked(a_, b_));
    }
}
