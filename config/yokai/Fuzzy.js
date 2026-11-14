.pragma library

// Subsequence matching with bonuses for word starts and consecutive characters.
function score(query, value) {
    const needle = query.trim().toLocaleLowerCase();
    const text = String(value ?? "").toLocaleLowerCase();
    if (!needle) return 0;
    let previous = -1, total = 0;
    for (const character of needle) {
        if (/\s/.test(character)) continue;
        const position = text.indexOf(character, previous + 1);
        if (position < 0) return -1;
        total += 10;
        if (position === 0 || /[\s._/\-]/.test(text[position - 1])) total += 12;
        if (position === previous + 1) total += 8;
        total -= previous < 0 ? position * .1 : (position - previous - 1) * .4;
        previous = position;
    }
    return total + 1 / (1 + text.length);
}

// The same physical keys in US QWERTY and Russian layouts, including Shift.
function keyboardQueries(query) {
    const english = "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./"
        + "~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?";
    const russian = "ё1234567890-=йцукенгшщзхъ\\фывапролджэячсмитьбю."
        + "Ё!\"№;%:?*()_+ЙЦУКЕНГШЩЗХЪ/ФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,";
    function translate(source, target) {
        return Array.from(query, character => {
            const key = source.indexOf(character);
            return key < 0 ? character : target[key];
        }).join("");
    }
    return [query, translate(russian, english), translate(english, russian)]
        .filter((value, index, values) => values.indexOf(value) === index);
}

// Match quality outranks score bonuses, consistently across all search sources.
function matchQuality(query, value) {
    const needle = query.trim().toLocaleLowerCase();
    const text = String(value ?? "").trim().toLocaleLowerCase();
    if (!needle) return 0;
    if (needle === text) return 4;
    function boundary(character) {
        return /\s/.test(character) || ".,_/\\-:;()[]{}—–!?\"'@".includes(character);
    }
    let quality = 0;
    for (let position = text.indexOf(needle); position >= 0; position = text.indexOf(needle, position + 1)) {
        const left = position === 0 || boundary(text[position - 1]);
        const end = position + needle.length;
        if (left && (end === text.length || boundary(text[end]))) return 3;
        quality = Math.max(quality, left ? 2 : 1);
    }
    return quality;
}

function applicationMatch(query, app) {
    let best = {matchQuality: -1, score: -1};
    for (const value of [app.name, app.genericName, app.id, ...(app.keywords ?? []), (app.keywords ?? []).join(" ")]) {
        const valueScore = score(query, value);
        if (valueScore < 0) continue;
        const quality = matchQuality(query, value);
        if (quality > best.matchQuality || quality === best.matchQuality && valueScore > best.score)
            best = {matchQuality: quality, score: valueScore};
    }
    return best;
}

function matchesApplicationName(query, app) {
    const names = [app.name, String(app.id ?? "").replace(/\.desktop$/i, "")];
    return names.some(name => matchQuality(query, name) >= 2);
}

function rankedApplications(query, values) {
    const queries = keyboardQueries(query);
    return values.filter(app => !app.noDisplay)
        .map(app => {
            const matches = queries.map(value => applicationMatch(value, app));
            const quality = Math.max(...matches.map(match => match.matchQuality));
            const originalMatch = matches[0].matchQuality === quality;
            const bestScore = originalMatch ? matches[0].score
                : Math.max(...matches.filter(match => match.matchQuality === quality).map(match => match.score));
            return {kind: "app", id: app.id, title: app.name, description: app.genericName || app.comment || "",
                icon: app.icon, sourceLabel: "App", app: app, score: bestScore, matchQuality: quality, originalMatch: originalMatch,
                applicationNameMatch: queries.some(value => matchesApplicationName(value, app))};
        })
        .filter(result => result.score >= 0)
        .sort(compareResults);
}

function compareResults(a, b) {
    const ranking = Number(b.applicationNameMatch === true) - Number(a.applicationNameMatch === true)
        || (b.matchQuality ?? 0) - (a.matchQuality ?? 0)
        || Number(b.originalMatch) - Number(a.originalMatch) || b.score - a.score;
    if (ranking !== 0) return ranking;
    if (a.kind !== b.kind) return a.kind.localeCompare(b.kind);
    // Keep the browser helper's recency order when match scores tie.
    if (a.kind === "browser" && b.kind === "browser") return 0;
    return a.title.localeCompare(b.title) || String(a.id).localeCompare(String(b.id));
}

function applications(query, values) { return rankedApplications(query, values).map(result => result.app); }
