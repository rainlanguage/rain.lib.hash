// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

/// `audit/mutation-test-scans.json` is appended by hand, and two automated
/// consumers trust the SHAs it records: the audit skill's Pass-2 gate and the
/// org health scanner. Neither rejects a malformed file loudly, so this pins
/// the shape of every record instead.
///
/// `testsAfterCommit` is required here but is repo-local: other rain ledgers
/// (raindex's, for one) do not carry the field, so this test is not portable
/// as written.
contract MutationLedgerTest is Test {
    string constant LEDGER = "audit/mutation-test-scans.json";
    string constant TOOL = "adversarial-mutation-test";

    function isHex40(string memory s) internal pure returns (bool) {
        bytes memory b = bytes(s);
        if (b.length != 40) {
            return false;
        }
        for (uint256 i = 0; i < 40; i++) {
            bytes1 c = b[i];
            bool digit = c >= 0x30 && c <= 0x39;
            bool lower = c >= 0x61 && c <= 0x66;
            if (!digit && !lower) {
                return false;
            }
        }
        return true;
    }

    /// `YYYY-MM-DDTHH:MM:SSZ` exactly, where `d` in the mask is any digit.
    function isUtcTimestamp(string memory s) internal pure returns (bool) {
        bytes memory b = bytes(s);
        bytes memory mask = bytes("dddd-dd-ddTdd:dd:ddZ");
        if (b.length != mask.length) {
            return false;
        }
        for (uint256 i = 0; i < mask.length; i++) {
            if (mask[i] == "d") {
                if (b[i] < 0x30 || b[i] > 0x39) {
                    return false;
                }
            } else if (b[i] != mask[i]) {
                return false;
            }
        }
        return true;
    }

    function testLedgerRecordShape() external view {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/", LEDGER));

        // A trailing comma or any other syntax error makes the cheatcode
        // revert; a bare object has no `[0]`.
        assertTrue(vm.keyExistsJson(json, "[0]"), "ledger must be a non-empty array");

        uint256 i = 0;
        while (vm.keyExistsJson(json, string.concat("[", vm.toString(i), "]"))) {
            string memory p = string.concat("[", vm.toString(i), "]");
            assertEq(vm.parseJsonString(json, string.concat(p, ".tool")), TOOL, string.concat(p, ".tool"));
            assertTrue(isHex40(vm.parseJsonString(json, string.concat(p, ".commit"))), string.concat(p, ".commit"));
            assertTrue(
                isHex40(vm.parseJsonString(json, string.concat(p, ".testsAfterCommit"))),
                string.concat(p, ".testsAfterCommit")
            );
            assertTrue(
                isUtcTimestamp(vm.parseJsonString(json, string.concat(p, ".timestamp"))), string.concat(p, ".timestamp")
            );
            i++;
        }
    }
}
