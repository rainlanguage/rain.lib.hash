// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {HashHarness} from "./HashHarness.sol";

contract AuditedSourceIsCurrentTest is Test {
    function testHarnessRuntimeCodeMatchesAuditedSourceRecord() external view {
        assertEq(
            keccak256(type(HashHarness).runtimeCode),
            vm.parseJsonBytes32(vm.readFile("audit/audited-source.json"), ".harnessRuntimeCodeHash"),
            "src/ or the compile settings moved past every revision listed in audit/audited-source.json: get a new audit or mutation scan against this code, add its commit to auditedCommits, and recompute harnessRuntimeCodeHash"
        );
    }
}
