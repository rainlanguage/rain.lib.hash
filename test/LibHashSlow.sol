// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

library LibHashSlow {
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
