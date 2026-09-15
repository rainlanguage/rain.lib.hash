// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibHashNoAlloc} from "../src/LibHashNoAlloc.sol";
import {LibHashSlow} from "./LibHashSlow.sol";

/// Pins the "no alloc" promise of every LibHashNoAlloc function as a memory
/// property rather than a digest: canaries planted at the free memory pointer
/// (and in scratch for the in-place hashers) survive the call, the free memory
/// pointer and zero slot are unchanged, and a digest of every byte from 0x40 to
/// 0x100 past the free memory pointer, excluding only the two snapshot structs
/// the harness fills, is unchanged. The guard word sits between the decoded
/// input and those structs so a write one word past the input lands on a word
/// the snapshot covers rather than on the snapshot itself. Everything is read
/// back in assembly before any assertion runs because the assertions allocate.
contract LibHashNoAllocMemoryTest is Test {
    struct Snapshot {
        uint256 fmp;
        uint256 zeroSlot;
        uint256 scratch0;
        uint256 scratch1;
        uint256 canary0;
        uint256 canary1;
        uint256 guard;
        bytes32 regionBelow;
        bytes32 regionAbove;
    }

    uint256 constant SNAPSHOT_SIZE = 0x120;

    /// Plants `canary` in the guard word and at the free memory pointer, and
    /// `~canary` at the next word and, when `plantScratch` is set, in the
    /// scratch space too, then fills `pre`. `guard`, `pre` and `post` are
    /// allocated by the caller in that order before planting, so the harness
    /// allocates nothing across the call under test.
    function plant(
        Snapshot memory pre,
        Snapshot memory post,
        bytes32[1] memory guard,
        uint256 canary,
        bool plantScratch
    ) internal pure {
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(guard, canary)
            mstore(fmp, canary)
            mstore(add(fmp, 0x20), not(canary))
            if plantScratch {
                mstore(0, canary)
                mstore(0x20, not(canary))
            }
        }
        read(pre, pre, post, guard);
    }

    /// Reads the free memory pointer, zero slot, scratch, the guard word, the
    /// two canary words at the free memory pointer, and digests of 0x40 up to
    /// `pre` and of the end of `post` up to fmp + 0x100, into `snapshot`.
    function read(Snapshot memory snapshot, Snapshot memory pre, Snapshot memory post, bytes32[1] memory guard)
        internal
        pure
    {
        uint256 fmp;
        uint256 zeroSlot;
        uint256 scratch0;
        uint256 scratch1;
        uint256 canary0;
        uint256 canary1;
        uint256 guardWord;
        bytes32 regionBelow;
        bytes32 regionAbove;
        assembly ("memory-safe") {
            fmp := mload(0x40)
            zeroSlot := mload(0x60)
            scratch0 := mload(0)
            scratch1 := mload(0x20)
            canary0 := mload(fmp)
            canary1 := mload(add(fmp, 0x20))
            guardWord := mload(guard)
            regionBelow := keccak256(0x40, sub(pre, 0x40))
            let above := add(post, SNAPSHOT_SIZE)
            regionAbove := keccak256(above, sub(add(fmp, 0x100), above))
        }
        snapshot.fmp = fmp;
        snapshot.zeroSlot = zeroSlot;
        snapshot.scratch0 = scratch0;
        snapshot.scratch1 = scratch1;
        snapshot.canary0 = canary0;
        snapshot.canary1 = canary1;
        snapshot.guard = guardWord;
        snapshot.regionBelow = regionBelow;
        snapshot.regionAbove = regionAbove;
    }

    function assertUntouched(Snapshot memory pre, Snapshot memory post, uint256 canary) internal pure {
        assertEq(post.fmp, pre.fmp, "fmp");
        assertEq(post.zeroSlot, pre.zeroSlot, "zero slot");
        assertEq(post.guard, canary, "guard after input");
        assertEq(post.canary0, canary, "canary at fmp");
        assertEq(post.canary1, ~canary, "canary at fmp + 0x20");
        assertEq(post.regionBelow, pre.regionBelow, "0x40..snapshots");
        assertEq(post.regionAbove, pre.regionAbove, "snapshots..fmp+0x100");
    }

    function assertScratchUntouched(Snapshot memory post, uint256 canary) internal pure {
        assertEq(post.scratch0, canary, "scratch 0x00");
        assertEq(post.scratch1, ~canary, "scratch 0x20");
    }

    function testHashBytesTouchesNoMemory(bytes memory data, uint256 canary) public pure {
        bytes32[1] memory guard;
        Snapshot memory pre;
        Snapshot memory post;
        plant(pre, post, guard, canary, true);
        bytes32 hash = LibHashNoAlloc.hashBytes(data);
        read(post, pre, post, guard);
        assertUntouched(pre, post, canary);
        assertScratchUntouched(post, canary);
        assertEq(hash, LibHashSlow.hashBytesSlow(data));
    }

    function testHashWordsTouchesNoMemory(bytes32[] memory words, uint256 canary) public pure {
        bytes32[1] memory guard;
        Snapshot memory pre;
        Snapshot memory post;
        plant(pre, post, guard, canary, true);
        bytes32 hash = LibHashNoAlloc.hashWords(words);
        read(post, pre, post, guard);
        assertUntouched(pre, post, canary);
        assertScratchUntouched(post, canary);
        assertEq(hash, LibHashSlow.hashWordsSlow(words));
    }

    function testHashWordsUint256TouchesNoMemory(uint256[] memory words, uint256 canary) public pure {
        bytes32[1] memory guard;
        Snapshot memory pre;
        Snapshot memory post;
        plant(pre, post, guard, canary, true);
        bytes32 hash = LibHashNoAlloc.hashWords(words);
        read(post, pre, post, guard);
        assertUntouched(pre, post, canary);
        assertScratchUntouched(post, canary);
        assertEq(hash, LibHashSlow.hashWordsSlow(words));
    }

    function testCombineHashesTouchesOnlyScratch(bytes32 a, bytes32 b, uint256 canary) public pure {
        bytes32[1] memory guard;
        Snapshot memory pre;
        Snapshot memory post;
        plant(pre, post, guard, canary, false);
        bytes32 hash = LibHashNoAlloc.combineHashes(a, b);
        read(post, pre, post, guard);
        assertUntouched(pre, post, canary);
        assertEq(post.scratch0, uint256(a), "scratch 0x00 holds a");
        assertEq(post.scratch1, uint256(b), "scratch 0x20 holds b");
        assertEq(hash, LibHashSlow.combineHashesSlow(a, b));
    }
}
