import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import vm from "node:vm";
import test from "node:test";

const args = process.argv.slice(2);
assert(args.length === 0 || args.length === 2 && args[0] === "--source",
    "Usage: node update-status.js [--source UpdateStatus.js]");
const source = args[1] || fileURLToPath(new URL("../config/yokai/UpdateStatus.js", import.meta.url));
const status = vm.createContext({});
vm.runInContext(readFileSync(source, "utf8").replace(/^\.pragma library\s*/, ""), status);

const failed = {id: "system-auto-update", error: "Service failed: exit-code (exit 1)",
    state: "inactive", lastRun: "2026-11-08T21:15:00Z"};
const current = {current: true, date: "2026-11-10T11:15:43Z"};

test("a system installed after the failed run resolves the overview without rewriting history", () => {
    const original = JSON.stringify(failed);
    assert.equal(status.currentAutomaticFailure([failed], [current]), null);
    assert.equal(JSON.stringify(failed), original);
});

test("a failure after the installed generation still needs attention", () => {
    const recent = {...failed, lastRun: "2026-11-10T12:00:00Z"};
    assert.equal(status.currentAutomaticFailure([recent], [current]), recent);
});

test("rollback and unapplied generations cannot resolve failures", () => {
    const generations = [{current: false, date: current.date}, {current: true, date: "2026-11-07T00:00:00Z"}];
    assert.equal(status.currentAutomaticFailure([failed], generations), failed);
});

test("missing or invalid timestamps preserve the failure", () => {
    for (const generations of [[], [{current: true}], [{current: true, date: "invalid"}]])
        assert.equal(status.currentAutomaticFailure([failed], generations), failed);
    for (const lastRun of [null, "invalid"] ) {
        const unknown = {...failed, lastRun};
        assert.equal(status.currentAutomaticFailure([unknown], [current]), unknown);
    }
});

test("installing NixOS cannot resolve CLI or Flatpak failures", () => {
    for (const id of ["tools-auto-update", "flatpak-auto-update"]) {
        const job = {...failed, id};
        assert.equal(status.currentAutomaticFailure([failed, job], [current]), job);
    }
});

test("successful jobs do not become failures based on their age", () => {
    assert.equal(status.currentAutomaticFailure([{id: "system-auto-update", state: "inactive", error: null}], []), null);
});
