const profile = document.getElementById("profile");
const status = document.getElementById("status");
const connect = document.getElementById("connect");

async function connectProfile() {
    if (!profile.value) return;
    await chrome.storage.local.set({profileDirectory: profile.value});
    await chrome.runtime.sendMessage({type: "sync"});
    status.textContent = "Syncing browser history…";
}

async function loadProfiles() {
    try {
        const response = await chrome.runtime.sendMessage({type: "profiles"});
        if (!response.ok) throw new Error(response.error);
        const stored = await chrome.storage.local.get("profileDirectory");
        profile.replaceChildren(new Option("Choose a profile", ""));
        for (const item of response.profiles) profile.add(new Option(item.name, item.directory));
        profile.value = stored.profileDirectory || "";
        connect.disabled = false;
        status.textContent = profile.value ? "Checking history…" : "Choose the profile used by this browser window.";
        // The desktop bootstrap opens this page in the explicitly selected profile.
        const selected = new URLSearchParams(location.hash.slice(1)).get("connect");
        if (selected && response.profiles.some(item => item.directory === selected)) {
            profile.value = selected;
            await connectProfile();
            history.replaceState(null, "", location.pathname);
        }
    } catch (error) {
        status.textContent = error.message || "YŌKAI is not connected. Try again shortly.";
    }
}

document.getElementById("settings").addEventListener("submit", event => {
    event.preventDefault();
    connectProfile().catch(() => { status.textContent = "History could not be connected. Try again shortly."; });
});
document.getElementById("refresh").addEventListener("click", () => {
    if (connect.disabled) loadProfiles();
    else chrome.runtime.sendMessage({type: "sync"});
});
setInterval(async () => {
    try {
        const state = await chrome.runtime.sendMessage({type: "status"});
        if (state.error) status.textContent = state.error;
        else if (state.syncing) status.textContent = "Syncing browser history…";
        else if (state.updatedAt) status.textContent = `${state.count.toLocaleString()} pages available in desktop search.`;
    } catch (_) { status.textContent = "YŌKAI is not connected. Try again shortly."; }
}, 2000);
loadProfiles();
