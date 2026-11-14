import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import vm from "node:vm";
import test from "node:test";

const args = process.argv.slice(2);
assert(args.length === 0 || args.length === 2 && args[0] === "--source",
    "Usage: node search-ranking.js [--source Fuzzy.js]");
const source = args[1] || fileURLToPath(new URL("../config/yokai/Fuzzy.js", import.meta.url));
const fuzzy = vm.createContext({});
vm.runInContext(readFileSync(source, "utf8").replace(/^\.pragma library\s*/, ""), fuzzy);

test("Cyrillic exact names outrank website bonuses and unrelated fuzzy apps", () => {
    const rows = [
        {kind: "browser", id: "website", title: "Example website error", matchQuality: 0, score: 113.6294, originalMatch: false},
        {kind: "app", id: "weak", title: "Weak match", matchQuality: 1, score: 500, originalMatch: true},
        {kind: "telegram", id: "contact", title: "Тест", matchQuality: 4, score: 84.2, originalMatch: true},
    ];
    assert.equal(rows.sort(fuzzy.compareResults)[0].id, "contact");
});

test("application names outrank browser history, including prefixes and alternate layouts", () => {
    const app = {id: "brave-browser.desktop", name: "Brave Web Browser", genericName: "Web Browser"};
    const page = {kind: "browser", id: "brave-site", title: "Brave Leo AI | Brave",
        matchQuality: 4, score: 500, originalMatch: true};
    for (const query of ["brave", "BRAVE", "икфму", "bra"]) {
        const application = fuzzy.rankedApplications(query, [app])[0];
        assert.equal(application.applicationNameMatch, true, query);
        assert.equal([page, application].sort(fuzzy.compareResults)[0].app, app, query);
    }
});

test("launcher IDs identify applications without treating the desktop suffix as a name", () => {
    const app = {id: "org.gnome.Nautilus.desktop", name: "Files"};
    assert.equal(fuzzy.rankedApplications("nautilus", [app])[0].applicationNameMatch, true);
    assert.equal(fuzzy.rankedApplications("desktop", [app])[0].applicationNameMatch, false);
});

test("generic names, keywords and fuzzy app matches do not receive name priority", () => {
    const apps = [
        {id: "sync.desktop", name: "Syncthing", genericName: "Brave", keywords: ["brave"]},
        {id: "example.desktop", name: "Bureau archive viewer"},
    ];
    const applications = fuzzy.rankedApplications("brave", apps);
    assert.equal(applications.length, 2);
    assert(applications.every(row => row.applicationNameMatch === false));
    const page = {kind: "browser", id: "brave-site", title: "brave.com",
        matchQuality: 4, score: 500, originalMatch: true};
    assert.equal(applications.concat(page).sort(fuzzy.compareResults)[0].id, page.id);
    assert.equal(fuzzy.matchesApplicationName("brave.com", {name: "Brave Web Browser", id: "brave-browser.desktop"}), false);
});

test("word boundaries distinguish full words, prefixes, substrings and subsequences", () => {
    for (const [value, quality] of [[" Тест ", 4], ["Пример, Тест [work]", 3], ["Тестовый", 2], ["Подтест", 1], ["Т...е...с...т", 0]]) {
        assert(fuzzy.score("Тест", value) >= 0);
        assert.equal(fuzzy.matchQuality("Тест", value), quality, value);
    }
    assert.equal(fuzzy.matchQuality("ghost", "ghostty"), 2);
    assert.equal(fuzzy.matchQuality("ozon", "ozon.ru"), 3);
});

test("direct queries win ties with alternate layouts while converted exact names remain findable", () => {
    const app = {id: "example.desktop", name: "Тест", keywords: []};
    const result = fuzzy.rankedApplications("Ntcn", [app])[0];
    assert.equal(result.matchQuality, 4);
    assert.equal(result.originalMatch, false);
    assert.equal(result.app, app);
    const rows = [{kind: "browser", id: "converted", title: "Converted", matchQuality: 3, score: 400, originalMatch: false},
        {kind: "telegram", id: "direct", title: "Direct", matchQuality: 3, score: 40, originalMatch: true}];
    assert.equal(rows.sort(fuzzy.compareResults)[0].id, "direct");
});

test("application matching keeps multi-keyword queries and filters hidden/nonmatching entries", () => {
    const app = {id: "example.desktop", name: "Example", keywords: ["remote", "control"]};
    assert.equal(fuzzy.rankedApplications("remote control", [app])[0].app, app);
    assert.equal(fuzzy.rankedApplications("qzxv", [app]).length, 0);
    assert.equal(fuzzy.rankedApplications("", [{...app, noDisplay: true}]).length, 0);
});

test("equal browser matches preserve the provider's recency order", () => {
    const rows = ["recent", "older"].map(id => ({kind: "browser", id, title: id, matchQuality: 3, score: 80, originalMatch: true}));
    assert.deepEqual(rows.sort(fuzzy.compareResults).map(row => row.id), ["recent", "older"]);
});
