const HOST = "info.nullflare.yokai_browser";
const MAX_HISTORY_ITEMS = 100000;
const CHUNK_SIZE = 150;
const CHUNK_BYTES = 512 * 1024;
let nativePort = null;
let settings = {};
let syncing = false;
let syncAgain = false;
let syncTimer = null;
let initializingSettings = null;
let optionsOpened = false;
let status = {connected: false, syncing: false, count: 0, error: ""};
const pending = new Map();

async function loadSettings() {
    initializingSettings ??= (async () => {
        const stored = await chrome.storage.local.get("sourceId");
        if (!stored.sourceId) await chrome.storage.local.set({sourceId: crypto.randomUUID()});
    })();
    await initializingSettings;
    settings = await chrome.storage.local.get(["sourceId", "profileDirectory"]);
}

function disconnect(port) {
    if (nativePort !== port) return;
    nativePort = null;
    status.connected = false;
    status.error = "YŌKAI is not connected. It will retry automatically.";
    for (const request of pending.values()) {
        clearTimeout(request.timer);
        request.reject(new Error(status.error));
    }
    pending.clear();
}

function connect() {
    if (nativePort) return nativePort;
    const port = chrome.runtime.connectNative(HOST);
    nativePort = port;
    port.onDisconnect.addListener(() => {
        // Read lastError so Chrome does not report an unhandled native failure.
        void chrome.runtime.lastError;
        disconnect(port);
    });
    port.onMessage.addListener(message => {
        if (nativePort !== port) return;
        if (message.type === "open") {
            openPage(message, port);
            return;
        }
        const request = pending.get(message.requestId);
        if (!request) return;
        pending.delete(message.requestId);
        clearTimeout(request.timer);
        if (message.ok) {
            status.connected = true;
            status.error = "";
            request.resolve(message);
        } else request.reject(new Error(message.error || "Browser history could not be connected."));
    });
    return port;
}

function request(type, values = {}) {
    const port = connect();
    const requestId = crypto.randomUUID();
    return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
            pending.delete(requestId);
            reject(new Error("YŌKAI did not respond. Try again shortly."));
        }, 15000);
        pending.set(requestId, {resolve, reject, timer});
        try {
            port.postMessage({...values, type, requestId});
        } catch (error) {
            clearTimeout(timer);
            pending.delete(requestId);
            reject(error);
        }
    });
}

async function openPage(message, port) {
    try {
        const url = new URL(message.url);
        if (!["https:", "http:"].includes(url.protocol) || !url.hostname || url.username || url.password)
            throw new Error("This address cannot be opened.");
        const tab = await chrome.tabs.create({url: url.href, active: true});
        const window = await chrome.windows.get(tab.windowId);
        await chrome.windows.update(tab.windowId, {focused: true, ...(window.state === "minimized" ? {state: "normal"} : {})});
        port.postMessage({type: "opened", requestId: message.requestId, ok: true});
    } catch (error) {
        try { port.postMessage({type: "opened", requestId: message.requestId, ok: false, error: "The page could not be opened."}); }
        catch (_) { /* The native connection may have closed during navigation. */ }
    }
}

function historyItem(item) {
    try {
        const url = new URL(item.url);
        if (!["https:", "http:"].includes(url.protocol) || !url.hostname || url.username || url.password || item.url.length > 8192)
            return null;
        url.pathname = "/" + url.pathname.split("/").filter(Boolean).slice(0, 3).join("/");
        url.search = "";
        url.hash = "";
        const title = Array.from(String(item.title || "").toWellFormed()).slice(0, 1024).join("");
        return {url: url.href, title,
            lastVisitTime: item.lastVisitTime || 0, visitCount: item.visitCount || 0};
    } catch (_) { return null; }
}

function normalizedHistory(history) {
    const pages = new Map();
    for (const raw of history) {
        const item = historyItem(raw);
        if (!item) continue;
        const previous = pages.get(item.url);
        if (!previous) { pages.set(item.url, item); continue; }
        const newest = item.lastVisitTime > previous.lastVisitTime
            || item.lastVisitTime === previous.lastVisitTime && item.visitCount > previous.visitCount;
        pages.set(item.url, {...(newest ? item : previous),
            lastVisitTime: Math.max(item.lastVisitTime, previous.lastVisitTime),
            visitCount: Math.max(item.visitCount, previous.visitCount)});
    }
    return [...pages.values()];
}

function* historyChunks(items) {
    const encoder = new TextEncoder();
    let chunk = [], bytes = 0;
    for (const item of items) {
        const size = encoder.encode(JSON.stringify(item)).byteLength + 1;
        if (chunk.length && (chunk.length >= CHUNK_SIZE || bytes + size > CHUNK_BYTES)) {
            yield chunk;
            chunk = [];
            bytes = 0;
        }
        chunk.push(item);
        bytes += size;
    }
    if (chunk.length) yield chunk;
}

async function syncHistory() {
    if (syncing) { syncAgain = true; return; }
    syncing = true;
    status.syncing = true;
    try {
        await loadSettings();
        if (!settings.profileDirectory) return;
        const source = {...settings};
        const profiles = (await request("profiles")).profiles;
        const profile = profiles.find(item => item.directory === source.profileDirectory);
        if (!profile) throw new Error("Choose the browser profile again.");
        const snapshotId = crypto.randomUUID();
        const history = await chrome.history.search({text: "", startTime: 0, maxResults: MAX_HISTORY_ITEMS});
        const items = normalizedHistory(history);
        await request("begin", {sourceId: source.sourceId, profileDirectory: profile.directory,
            name: profile.name, snapshotId});
        for (const chunk of historyChunks(items)) {
            await request("chunk", {sourceId: source.sourceId, snapshotId, items: chunk});
        }
        await request("commit", {sourceId: source.sourceId, snapshotId});
        status.count = items.length;
        status.updatedAt = Date.now();
        status.error = "";
    } catch (error) {
        status.error = error.message || "Browser history could not be synced.";
    } finally {
        syncing = false;
        status.syncing = false;
        if (syncAgain) { syncAgain = false; scheduleSync(0); }
    }
}

function scheduleSync(delay = 3000) {
    if (syncTimer) clearTimeout(syncTimer);
    syncTimer = setTimeout(() => { syncTimer = null; syncHistory(); }, delay);
}

async function initializeProfile() {
    await loadSettings();
    if (!settings.profileDirectory && !optionsOpened) {
        optionsOpened = true;
        try { await chrome.runtime.openOptionsPage(); }
        catch (_) { optionsOpened = false; }
    }
    scheduleSync(0);
}

chrome.runtime.onMessage.addListener((message, sender, respond) => {
    if (sender.id !== chrome.runtime.id) return false;
    if (message.type === "status") {
        respond({...status, profileDirectory: settings.profileDirectory || ""});
        return false;
    }
    if (message.type === "profiles") {
        request("profiles").then(result => respond(result), () => respond({ok: false, error: "YŌKAI is not connected. Try again shortly."}));
        return true;
    }
    if (message.type === "sync") {
        scheduleSync(0);
        respond({ok: true});
    }
    return false;
});
chrome.history.onVisited.addListener(() => scheduleSync());
chrome.history.onVisitRemoved.addListener(() => scheduleSync());
chrome.storage.onChanged.addListener((changes, area) => {
    if (area === "local" && changes.profileDirectory) scheduleSync(0);
});
chrome.action.onClicked.addListener(() => chrome.runtime.openOptionsPage());
chrome.runtime.onStartup.addListener(() => initializeProfile());
chrome.runtime.onInstalled.addListener(() => initializeProfile());
chrome.alarms.onAlarm.addListener(alarm => { if (alarm.name === "history-sync") scheduleSync(0); });
chrome.alarms.create("history-sync", {periodInMinutes: 1});
loadSettings().then(() => scheduleSync(0));
