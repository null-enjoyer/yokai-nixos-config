import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import vm from "node:vm";
import test from "node:test";

const source = process.argv[2];
const logic = vm.createContext({});
vm.runInContext(readFileSync(source, "utf8").replace(/^\.pragma library\s*/, ""), logic);
const settings = {enabled: true, intervalMinutes: 1};

test("one reminder appears after the interval and expires without a backlog", () => {
    let clock = logic.reset(1000, settings);
    clock = logic.tick(clock, 60000, settings, false);
    assert.equal(clock.shownAt, 0);
    clock = logic.tick(clock, 61000, settings, false);
    assert.equal(clock.shownAt, 61000);
    clock = logic.tick(clock, 80000, settings, false);
    assert.equal(clock.shownAt, 61000);
    clock = logic.tick(clock, 81000, settings, false);
    assert.equal(clock.shownAt, 0);
    assert.equal(clock.dueAt, 141000);
});

test("blocking an app hides an existing reminder and gives a fresh interval afterwards", () => {
    let clock = logic.tick(logic.reset(1000, settings), 61000, settings, false);
    assert(clock.shownAt);
    clock = logic.tick(clock, 62000, settings, true);
    assert.equal(clock.shownAt, 0);
    clock = logic.tick(clock, 120000, settings, true);
    clock = logic.tick(clock, 121000, settings, false);
    assert.equal(clock.dueAt, 180000);
    assert.equal(clock.shownAt, 0);
});

test("disabled reminders and interval changes cannot leave an overdue popup", () => {
    const clock = logic.tick(logic.reset(1000, settings), 61000, settings, false);
    const off = logic.tick(clock, 62000, {...settings, enabled: false}, false);
    assert.equal(off.shownAt, 0);
    const changed = logic.tick(clock, 62000, {...settings, intervalMinutes: 10}, false);
    assert.equal(changed.dueAt, 662000);
    assert.equal(changed.shownAt, 0);
});

test("temporary presentation deferral preserves an elapsed deadline until the screen is available", () => {
    let clock = logic.reset(1000, settings);
    clock = logic.tick(clock, 59000, settings, false);
    clock = logic.tick(clock, 62000, settings, false, true);
    assert.equal(clock.shownAt, 0);
    assert.equal(clock.dueAt, 61000);
    clock = logic.tick(clock, 64000, settings, false);
    assert.equal(clock.shownAt, 64000);
});

test("suspend and clock changes restart the interval instead of showing immediately", () => {
    const clock = logic.reset(100000, settings);
    for (const now of [1000, 200000]) {
        const next = logic.tick(clock, now, settings, false);
        assert.equal(next.dueAt, now + 60000);
        assert.equal(next.shownAt, 0);
    }
});

test("snoozing uses a separate deadline without changing the configured interval", () => {
    let clock = logic.reset(1000, settings, 5);
    for (let now = 2000; now < 301000; now += 1000)
        clock = logic.tick(clock, now, settings, false);
    assert.equal(clock.shownAt, 0);
    clock = logic.tick(clock, 301000, settings, false);
    assert.equal(clock.shownAt, 301000);
    assert.equal(clock.intervalMinutes, 1);
});

test("application exclusions match literal classes or wildcards on any mapped window", () => {
    assert(logic.matchesApp("sample.game", "SAMPLE.GAME"));
    assert(!logic.matchesApp("sample.game", "sampleXgame"));
    assert(logic.matchesApp("game-*", "game-client"));
    assert(logic.matchesApp("app[1]", "app[1]"));
    assert(!logic.matchesApp("app[1]", "app1"));
    const clients = [{class: "editor", focusHistoryID: 0},
        {class: "game-client", mapped: true, focusHistoryID: 2}];
    assert.equal(logic.blockingApp(clients, ["game-*"]), "game-client");
    assert.equal(logic.blockingApp([{class: "game-client", mapped: false}], ["game-*"]), "");
    assert.equal(logic.blockingApp([{class: "", initialClass: "game-client"}], ["game-*"]), "game-client");
});
