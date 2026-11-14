// Exercise the actual MV3 worker against browser APIs and a framed-host peer.
// No browser, user profiles, native-messaging hosts, or network connections are used.
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import vm from "node:vm";
import {fileURLToPath} from "node:url";
import test from "node:test";
import {spawnSync} from "node:child_process";

const args = process.argv.slice(2);
assert(args.length === 0 || (args.length === 2 && args[0] === "--source"),
    "Usage: node browser-extension.js [--source background.js]");
const sourcePath = args[1] || fileURLToPath(new URL("../config/yokai/browser-extension/background.js", import.meta.url));
const worker = readFileSync(sourcePath, "utf8");
const plain = value => JSON.parse(JSON.stringify(value));

function event() {
    const listeners = [];
    return {
        addListener(listener) { listeners.push(listener); },
        emit(...values) { return listeners.map(listener => listener(...values)); },
    };
}

async function flush() {
    // The mock APIs resolve only through microtasks. This bound covers several
    // protocol rounds and fails assertions instead of hanging on a lost reply.
    for (let index = 0; index < 100; index++) await Promise.resolve();
}

function browser({stored = {}, history = [], pauseInitialization = false} = {}) {
    const storage = {...stored};
    const writes = [];
    const messages = [];
    const ports = [];
    const searches = [];
    const tabs = [];
    const windows = [];
    const alarms = [];
    const optionsPages = [];
    const timers = new Map();
    const initializingReads = [];
    let clock = 0;
    let timerId = 0;
    let uuidId = 0;
    const peer = {hold: "", fail: "", windowState: "minimized", pauseNavigation: false};
    peer.finishInitialization = () => initializingReads.forEach(resolve => resolve());
    const chrome = {
        storage: {
            onChanged: event(),
            local: {
                async get(keys) {
                    const result = Object.fromEntries((Array.isArray(keys) ? keys : [keys])
                        .filter(key => Object.hasOwn(storage, key)).map(key => [key, storage[key]]));
                    if (pauseInitialization && keys === "sourceId")
                        await new Promise(resolve => initializingReads.push(resolve));
                    return result;
                },
                async set(values) {
                    writes.push(plain(values));
                    const changes = Object.fromEntries(Object.entries(values)
                        .map(([key, newValue]) => [key, {oldValue: storage[key], newValue}]));
                    Object.assign(storage, values);
                    chrome.storage.onChanged.emit(changes, "local");
                },
            },
        },
        runtime: {
            id: "test-extension", onMessage: event(), onStartup: event(), onInstalled: event(),
            async openOptionsPage() {
                optionsPages.push({sourceId: storage.sourceId, profileDirectory: storage.profileDirectory || ""});
            },
            connectNative(host) {
                assert.equal(host, "info.nullflare.yokai_browser");
                const port = {
                    onMessage: event(), onDisconnect: event(),
                    postMessage(message) {
                        assert(!port.disconnected, "Message sent on a disconnected native port");
                        const value = plain(message);
                        messages.push({port, value});
                        if (value.type === "opened" || peer.hold === value.type) return;
                        queueMicrotask(() => reply(port, value));
                    },
                    disconnect() { port.disconnected = true; port.onDisconnect.emit(); },
                };
                ports.push(port);
                return port;
            },
        },
        history: {
            onVisited: event(), onVisitRemoved: event(),
            async search(query) { searches.push(plain(query)); return history; },
        },
        tabs: {async create(options) {
            tabs.push(plain(options));
            if (peer.pauseNavigation) await new Promise(resolve => { peer.finishNavigation = resolve; });
            return {windowId: 7};
        }},
        windows: {
            async get(id) { assert.equal(id, 7); return {state: peer.windowState}; },
            async update(id, options) { windows.push({id, ...plain(options)}); },
        },
        action: {onClicked: event()},
        alarms: {
            onAlarm: event(),
            create(name, options) { alarms.push({name, ...plain(options)}); },
        },
    };
    function reply(port, message) {
        port.onMessage.emit({type: message.type, requestId: message.requestId,
            ok: peer.fail !== message.type,
            ...(peer.fail === message.type ? {error: "Synthetic host failure"} : {}),
            ...(message.type === "profiles" ? {profiles: [
                {directory: "Default", name: "Personal"}, {directory: "Profile 1", name: "Work"},
            ]} : {}),
        });
    }
    vm.runInNewContext(worker, {
        chrome, URL, TextEncoder, console,
        crypto: {randomUUID() { return `00000000-0000-4000-8000-${String(++uuidId).padStart(12, "0")}`; }},
        setTimeout(callback, delay) {
            const id = ++timerId;
            timers.set(id, {callback, due: clock + delay});
            return id;
        },
        clearTimeout(id) { timers.delete(id); },
    }, {filename: sourcePath, timeout: 1000});
    return {
        chrome, storage, writes, messages, ports, searches, tabs, windows, alarms, optionsPages, peer, history,
        reply,
        async advance(milliseconds = 0) {
            await flush();
            clock += milliseconds;
            for (let count = 0; count < 100; count++) {
                const next = [...timers.entries()].find(([, timer]) => timer.due <= clock);
                if (!next) { await flush(); return; }
                timers.delete(next[0]);
                next[1].callback();
                await flush();
            }
            throw new Error("Worker exceeded the bounded timer drain");
        },
        status() {
            let value;
            chrome.runtime.onMessage.emit({type: "status"}, {id: chrome.runtime.id},
                response => { value = plain(response); });
            assert(value, "Worker did not answer its status API");
            return value;
        },
        protocol() { return messages.map(item => item.value); },
    };
}

test("history snapshots preserve the selected profile and filter unsafe addresses", async () => {
    const history = Array.from({length: 151}, (_, index) => ({
        url: `https://example.org/${index}`, title: "A".repeat(1100), lastVisitTime: index, visitCount: 2,
    }));
    history.push({url: "http://example.org/plain"}, {url: "javascript:alert(1)"},
        {url: "file:///etc/passwd"}, {url: "https://user:secret@example.org/"},
        {url: "not a URL"}, {url: "https://example.org/" + "x".repeat(8192)});
    const instance = browser({stored: {profileDirectory: "Profile 1"}, history});
    instance.peer.hold = "begin";
    await instance.advance();
    assert.deepEqual(instance.protocol().map(item => item.type), ["profiles", "begin"],
        "Chunks must wait for the host to acknowledge begin");
    const begin = instance.protocol()[1];
    assert.equal(begin.profileDirectory, "Profile 1");
    assert.equal(begin.name, "Work");
    assert.equal(begin.sourceId, instance.storage.sourceId);
    instance.peer.hold = "chunk";
    instance.reply(instance.ports[0], begin);
    await flush();
    assert.deepEqual(instance.protocol().map(item => item.type), ["profiles", "begin", "chunk"],
        "Each chunk must be acknowledged before sending the next chunk");
    instance.reply(instance.ports[0], instance.protocol().at(-1));
    await flush();
    assert.deepEqual(instance.protocol().map(item => item.type), ["profiles", "begin", "chunk", "chunk"],
        "Commit must wait for the final chunk acknowledgement");
    instance.peer.hold = "";
    instance.reply(instance.ports[0], instance.protocol().at(-1));
    await flush();
    const protocol = instance.protocol();
    assert.deepEqual(protocol.map(item => item.type), ["profiles", "begin", "chunk", "chunk", "commit"]);
    const items = protocol.filter(item => item.type === "chunk").flatMap(item => item.items);
    assert.equal(items.length, 152);
    assert(items.some(item => item.url === "http://example.org/plain"));
    assert(items.every(item => /^https?:\/\//.test(item.url) && !item.url.includes("user:secret")));
    assert.equal(items[0].title.length, 1024);
    for (const message of protocol.slice(1)) {
        assert.equal(message.sourceId, begin.sourceId);
        assert.equal(message.snapshotId, begin.snapshotId);
    }
    assert.equal(new Set(protocol.map(item => item.requestId)).size, protocol.length);
    assert.equal(instance.searches[0].startTime, 0);
    assert.equal(instance.status().count, 152);
    assert(instance.status().updatedAt);
    assert.equal(instance.status().error, "");
});

test("history sync strips query and fragments, bounds paths, and merges page variants", async () => {
    const instance = browser({stored: {profileDirectory: "Default"}, history: [
        {url: "https://example.org/a/b/c/new?secret=one#fragment", title: "Newest", lastVisitTime: 200, visitCount: 2},
        {url: "https://example.org/a/b/c/old?secret=two", title: "Older", lastVisitTime: 100, visitCount: 9},
        {url: "https://example.org/a/b/c/", title: "Middle", lastVisitTime: 150, visitCount: 3},
        {url: "https://example.org/?private=yes#fragment", title: "Home"},
        {url: "https://example.org/one/a%2Fb/three/four?private=yes", title: "Encoded slash"},
    ]});
    await instance.advance();
    const items = instance.protocol().filter(message => message.type === "chunk").flatMap(message => message.items);
    assert.equal(items.length, 3);
    const page = items.find(item => item.url === "https://example.org/a/b/c");
    assert.equal(page.title, "Newest");
    assert.equal(page.lastVisitTime, 200);
    assert.equal(page.visitCount, 9);
    assert(items.some(item => item.url === "https://example.org/"));
    assert(items.some(item => item.url === "https://example.org/one/a%2Fb/three"));
    assert(items.every(item => !item.url.includes("?") && !item.url.includes("#")));
});

test("unconfigured workers avoid history reads and persist only one source identity", async () => {
    const instance = browser({pauseInitialization: true});
    instance.chrome.runtime.onStartup.emit();
    instance.chrome.runtime.onInstalled.emit();
    instance.chrome.history.onVisited.emit();
    await instance.advance(3000);
    assert.equal(instance.status().syncing, true, "The startup sync should overlap the initial settings read");
    instance.peer.finishInitialization();
    await instance.advance();
    assert.equal(instance.ports.length, 0);
    assert.equal(instance.searches.length, 0);
    assert.equal(instance.writes.filter(item => item.sourceId).length, 1);
    const restarted = browser({stored: instance.storage});
    await restarted.advance();
    assert.equal(restarted.writes.length, 0);
    assert.equal(restarted.storage.sourceId, instance.storage.sourceId);
});

test("installation and startup open internal setup once after settings are ready", async () => {
    const instance = browser({pauseInitialization: true, history: [{url: "https://example.org/"}]});
    instance.chrome.runtime.onInstalled.emit({reason: "install"});
    instance.chrome.runtime.onStartup.emit();
    await flush();
    assert.equal(instance.optionsPages.length, 0, "Setup must wait for initial settings");
    assert.equal(instance.searches.length, 0);
    instance.peer.finishInitialization();
    await instance.advance();
    assert.deepEqual(instance.optionsPages, [{sourceId: instance.storage.sourceId, profileDirectory: ""}]);
    assert(instance.storage.sourceId, "The setup page must open after identity initialization");
    assert.equal(instance.searches.length, 0, "Unconfigured startup must not read browser history");
    instance.chrome.runtime.onInstalled.emit({reason: "update"});
    instance.chrome.runtime.onStartup.emit();
    await instance.advance();
    assert.equal(instance.optionsPages.length, 1, "Overlapping/repeated events must not open duplicate setup pages");
    await instance.chrome.storage.local.set({profileDirectory: "Profile 1"});
    await instance.advance();
    assert.equal(instance.searches.length, 1, "Choosing a profile should start the first snapshot");
    assert.equal(instance.status().count, 1);

    const configured = browser({stored: {profileDirectory: "Profile 1", sourceId: instance.storage.sourceId}});
    configured.chrome.runtime.onInstalled.emit({reason: "update"});
    configured.chrome.runtime.onStartup.emit();
    await configured.advance();
    assert.equal(configured.optionsPages.length, 0, "Configured profiles should not reopen setup");
    assert.equal(configured.status().error, "");
});

test("large addresses and Unicode titles stay below the native-message byte limit", async () => {
    // Fewer than 150 entries can already exceed the local bridge's 1 MiB frame
    // limit: URL character counts do not capture UTF-8 title bytes.
    const history = Array.from({length: 130}, (_, index) => ({
        url: `https://example.org/${index}/${"x".repeat(7950)}`,
        title: "字".repeat(1024),
    }));
    const instance = browser({stored: {profileDirectory: "Profile 1"}, history});
    await instance.advance();
    const chunks = instance.protocol().filter(message => message.type === "chunk");
    assert(chunks.length > 1, "Large entries must split by encoded bytes, not only entry count");
    for (const chunk of chunks) {
        assert(Buffer.byteLength(JSON.stringify(chunk), "utf8") < 1024 * 1024,
            "A native chunk exceeded the bridge's 1 MiB framing limit");
    }
    assert.deepEqual(chunks.flatMap(chunk => chunk.items).map(item => ({url: item.url, title: item.title})), history,
        "Byte-based chunking must preserve every entry, its order, and its Unicode title");
    assert.equal(instance.status().count, history.length);
    assert.equal(instance.status().error, "");
    assert.equal(instance.protocol().at(-1).type, "commit");
});

test("title truncation preserves emoji and repairs invalid UTF-16 before Python relaying", async () => {
    const boundaryTitle = "a".repeat(1023) + "😀";
    const instance = browser({stored: {profileDirectory: "Profile 1"}, history: [
        {url: "https://example.org/emoji", title: boundaryTitle + "trim this suffix"},
        {url: "https://example.org/invalid", title: "Page \ud800 title \udc00"},
    ]});
    await instance.advance();
    const chunk = instance.protocol().find(message => message.type === "chunk");
    assert(chunk, "The snapshot did not send its titles");
    assert.equal(chunk.items[0].title, boundaryTitle, "Truncation must retain the entire boundary emoji");
    assert.equal(chunk.items[1].title, "Page � title �", "Unpaired surrogates must become replacement characters");
    for (const item of chunk.items) {
        assert(Array.from(item.title).length <= 1024);
        assert.equal(item.title, item.title.toWellFormed());
    }
    // The bridge decodes JSON then encodes its relay with ensure_ascii=False.
    // A split emoji survives JSON.parse but fails this strict UTF-8 operation.
    const relay = spawnSync("python3", ["-c", "import json, sys; data = json.load(sys.stdin); " +
        "sys.stdout.buffer.write(json.dumps(data, ensure_ascii=False).encode('utf-8'))"],
        {input: JSON.stringify(chunk), encoding: "utf8", timeout: 5000});
    assert.equal(relay.status, 0, relay.stderr || String(relay.error || "Python relay failed"));
    assert.deepEqual(JSON.parse(relay.stdout).items, chunk.items);
    assert.equal(instance.status().count, 2);
    assert.equal(instance.status().error, "");
});

test("bursts coalesce and history deletion replaces the entire snapshot", async () => {
    const instance = browser({stored: {profileDirectory: "Profile 1"}, history: [{url: "https://example.org/old"}]});
    await instance.advance();
    const sourceId = instance.storage.sourceId;
    instance.messages.length = 0;
    for (let index = 0; index < 20; index++) instance.chrome.history.onVisited.emit();
    await instance.advance(3000);
    assert.deepEqual(instance.protocol().map(item => item.type), ["profiles", "begin", "chunk", "commit"]);
    assert.equal(instance.writes.filter(item => item.sourceId).length, 1);
    assert.equal(instance.protocol()[1].sourceId, sourceId);
    instance.history.length = 0;
    instance.messages.length = 0;
    instance.chrome.history.onVisitRemoved.emit({allHistory: true, urls: []});
    await instance.advance(3000);
    assert.deepEqual(instance.protocol().map(item => item.type), ["profiles", "begin", "commit"]);
    assert.equal(instance.searches.length, 3);
    assert.equal(instance.status().count, 0);
});

test("native navigation opens a tab, restores focus, and replies on its originating port", async () => {
    const instance = browser({stored: {profileDirectory: "Profile 1"}});
    await instance.advance();
    const port = instance.ports[0];
    port.onMessage.emit({type: "open", requestId: "navigation", url: "https://example.org/page"});
    await flush();
    assert.deepEqual(instance.tabs, [{url: "https://example.org/page", active: true}]);
    assert.deepEqual(instance.windows, [{id: 7, focused: true, state: "normal"}]);
    assert.deepEqual(instance.messages.at(-1), {port, value: {type: "opened", requestId: "navigation", ok: true}});
    port.onMessage.emit({type: "open", requestId: "unsafe", url: "file:///etc/passwd"});
    await flush();
    assert.equal(instance.tabs.length, 1);
    assert.equal(instance.messages.at(-1).value.requestId, "unsafe");
    assert.equal(instance.messages.at(-1).value.ok, false);
});

test("failed commits leave the last committed status intact", async () => {
    const instance = browser({stored: {profileDirectory: "Profile 1"}, history: [{url: "https://example.org/old"}]});
    await instance.advance();
    const previous = instance.status();
    instance.history.push({url: "https://example.org/new"});
    instance.peer.fail = "commit";
    instance.chrome.alarms.onAlarm.emit({name: "history-sync"});
    await instance.advance();
    assert.equal(instance.status().count, previous.count);
    assert.equal(instance.status().updatedAt, previous.updatedAt);
    assert.equal(instance.status().syncing, false);
    assert.equal(instance.status().error, "Synthetic host failure");
});

test("navigation cannot accidentally acknowledge a newly reconnected native peer", async () => {
    const instance = browser({stored: {profileDirectory: "Profile 1"}});
    await instance.advance();
    const originalPort = instance.ports[0];
    instance.peer.pauseNavigation = true;
    originalPort.onMessage.emit({type: "open", requestId: "old-navigation", url: "https://example.org/"});
    await flush();
    originalPort.disconnect();
    let profiles;
    instance.chrome.runtime.onMessage.emit({type: "profiles"}, {id: instance.chrome.runtime.id},
        response => { profiles = response; });
    await flush();
    assert.equal(instance.ports.length, 2);
    assert.equal(profiles.ok, true);
    instance.peer.finishNavigation();
    await flush();
    assert.equal(instance.tabs.length, 1);
    assert(!instance.messages.some(item => item.port === instance.ports[1] && item.value.type === "opened"),
        "The new peer must never receive an acknowledgement for the old connection");
});

test("disconnect rejects an in-flight snapshot and the next alarm reconnects", async () => {
    const instance = browser({stored: {profileDirectory: "Profile 1"}, history: [{url: "https://example.org/"}]});
    instance.peer.hold = "chunk";
    await instance.advance();
    assert.deepEqual(instance.protocol().map(item => item.type), ["profiles", "begin", "chunk"]);
    assert.equal(instance.status().syncing, true);
    instance.ports[0].disconnect();
    await flush();
    assert.equal(instance.status().syncing, false);
    assert(instance.status().error.includes("not connected"));
    assert(!instance.protocol().some(item => item.type === "commit"));
    instance.peer.hold = "";
    instance.chrome.alarms.onAlarm.emit({name: "history-sync"});
    await instance.advance();
    assert.equal(instance.ports.length, 2);
    assert.equal(instance.status().connected, true);
    assert.equal(instance.status().error, "");
    assert.equal(instance.status().count, 1);
});
