.pragma library

function reset(now, settings, delayMinutes) {
    return {
        dueAt: now + (delayMinutes ?? settings.intervalMinutes) * 60000,
        lastTick: now,
        shownAt: 0,
        intervalMinutes: settings.intervalMinutes,
        enabled: settings.enabled
    };
}

function tick(clock, now, settings, blocked, deferred = false) {
    if (deferred) return clock;
    const interrupted = now < clock.lastTick || now - clock.lastTick > 60000;
    const changed = clock.intervalMinutes !== settings.intervalMinutes || clock.enabled !== settings.enabled;
    if (!clock.dueAt || !settings.enabled || blocked || interrupted || changed)
        return reset(now, settings);
    if (clock.shownAt && now - clock.shownAt >= 20000)
        return reset(now, settings);
    return Object.assign({}, clock, {
        lastTick: now,
        shownAt: clock.shownAt || (now >= clock.dueAt ? now : 0)
    });
}

function matchesApp(pattern, app) {
    if (!pattern || !app) return false;
    const expression = Array.from(pattern, character => {
        if (character === "*") return ".*";
        if (character === "?") return ".";
        return character.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }).join("");
    return new RegExp("^" + expression + "$", "i").test(app);
}

function blockingApp(clients, excludedApps) {
    const client = clients.find(client => client.mapped !== false && excludedApps.some(pattern =>
        matchesApp(pattern, client.class) || matchesApp(pattern, client.initialClass)));
    return client?.class || client?.initialClass || "";
}
