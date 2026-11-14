.pragma library

function currentAutomaticFailure(jobs, generations) {
    const current = generations.find(generation => generation.current);
    const installedAt = Date.parse(current?.date || "");
    return jobs.find(job => {
        if (job.state !== "failed" && !job.error) return false;
        // A later installed system supersedes an earlier failed system update.
        // CLI and Flatpak jobs have separate outcomes; keep their errors visible.
        if (job.id === "system-auto-update" && Date.parse(job.lastRun || "") < installedAt)
            return false;
        return true;
    }) || null;
}
