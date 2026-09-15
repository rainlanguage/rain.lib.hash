// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibHashNoAlloc, HASH_NIL} from "../src/LibHashNoAlloc.sol";

/// @title HashHarness
/// @notice Gives `src/LibHashNoAlloc.sol` a compiled form to hash. Every
/// function and constant the library exports is reachable externally here, so
/// nothing in `src/` can change what it computes without changing this
/// contract's runtime code. Pinned by `audit/audited-source.json`. The pin also
/// covers the compile settings in `foundry.toml`, which are part of what the
/// audits read. Never deployed; the library is consumed as source.
contract HashHarness {
    function hashNil() external pure returns (bytes32) {
        return HASH_NIL;
    }

    function hashBytes(bytes memory data) external pure returns (bytes32) {
        return LibHashNoAlloc.hashBytes(data);
    }

    function hashWordsBytes32(bytes32[] memory words) external pure returns (bytes32) {
        return LibHashNoAlloc.hashWords(words);
    }

    function hashWordsUint256(uint256[] memory words) external pure returns (bytes32) {
        return LibHashNoAlloc.hashWords(words);
    }

    function combineHashes(bytes32 a, bytes32 b) external pure returns (bytes32) {
        return LibHashNoAlloc.combineHashes(a, b);
    }
}
