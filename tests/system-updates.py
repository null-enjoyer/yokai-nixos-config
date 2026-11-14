"""Exercise the update coordinator in isolated checkouts, without real updates."""

import contextlib
import importlib.util
import json
import os
from pathlib import Path
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/yokai-updates.py"
if len(sys.argv) > 2 and sys.argv[1] == "--script":
    SCRIPT = Path(sys.argv[2])
    del sys.argv[1:3]
spec = importlib.util.spec_from_file_location("yokai_updates", SCRIPT)
updates = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updates)
STORE_PATH = "/nix/store/" + "a" * 32 + "-test-system"


class FakeCoordinator(updates.Coordinator):
    def __init__(self, config):
        self.commands = []
        self.fail_tools = False
        self.fail_flatpak = False
        self.fail_inputs = False
        self.fail_lock = False
        self.fail_metadata = False
        self.keep_package_versions = False
        super().__init__(config)

    @staticmethod
    def valid_closure(path):
        return path == STORE_PATH

    @contextlib.contextmanager
    def nix_credentials(self):
        yield {}

    def run(self, args, **_kwargs):
        args = [str(arg) for arg in args]
        self.commands.append(args)
        if args[0] == "bash":
            tree = Path(args[1]).parents[2]
            if args[2] == "update-inputs":
                if self.fail_inputs:
                    raise RuntimeError("upstream unavailable")
                lock = tree / "public/flake.lock"
                value = json.loads(lock.read_text())
                value["nodes"]["nixpkgs"]["locked"]["rev"] = "new-revision"
                lock.write_text(json.dumps(value))
                private = tree / "private/flake.lock"
                private.write_text(json.dumps({"nodes": {"desktop": {"locked": {"type": "path", "path": str(tree / "public")}}}}))
            elif args[2] == "check-tools":
                return json.dumps([{"name": n, "from": "1.0.0", "to": "2.0.0"} for n in ["claude-code", "codex"]])
            elif args[2] == "build":
                return STORE_PATH + "\n"
            elif args[2] == "eval":
                if self.fail_metadata:
                    raise RuntimeError("selected package evaluation failed")
                self.assert_machine_stdout = _kwargs.get("stdout_only")
                updated = json.loads((tree / "public/flake.lock").read_text())["nodes"]["nixpkgs"]["locked"]["rev"] == "new-revision"
                version = "2.0.0" if updated and not self.keep_package_versions else "1.0.0"
                return json.dumps({"systemVersion": "26.11.20261016.new" if updated else "26.11.20261010.old",
                                   "packages": [{"name": "example", "version": version},
                                                {"name": "example", "version": version},
                                                {"name": "unversioned", "version": ""},
                                                {"name": "null-version", "version": None}]})
            elif args[2] == "lock":
                if self.fail_lock:
                    raise RuntimeError("lock refresh failed")
                private = tree / "private/flake.lock"
                private.write_text(json.dumps({"nodes": {"desktop": {"locked": {"type": "path", "path": str(tree / "public")}}}}))
            return ""
        if args[0] == "update-tools":
            pins = Path(args[2]) / "overlays/tools-pins.json"
            value = json.loads(pins.read_text())
            value["codex"]["version"] = "2.0.0"
            pins.write_text(json.dumps(value))
            if self.fail_tools:
                raise RuntimeError("Codex package preparation failed")
            return ""
        if args[0] == "nix-store":
            Path(args[2]).symlink_to(STORE_PATH)
            return STORE_PATH + "\n"
        if args[:3] == ["nix", "store", "diff-closures"]:
            return "codex: 1.0.0 -> 2.0.0\n"
        if args[0] == "flatpak":
            return "org.example.App\tExample\t2.0\tstable\tflathub\n"
        if args[:2] == ["systemctl", "start"]:
            if self.fail_flatpak:
                raise RuntimeError("Flatpak service failed")
            return ""
        if args[0] == "journalctl":
            return "fetch https://user:password@example.org ghp_12345678901234567890\n"
        raise AssertionError("Unexpected command: " + repr(args))

    def refresh_observed(self):
        pass


class UpdateChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="yokai-updates-check-")
        self.addCleanup(self.temporary.cleanup)
        base = Path(self.temporary.name)
        self.root = base / "source"
        for name in ("public", "private/overlays", "private/bin"):
            (self.root / name).mkdir(parents=True)
        (self.root / "public/flake.lock").write_text(json.dumps({"nodes": {"nixpkgs": {"locked": {"rev": "old-revision", "type": "github"}}}}))
        (self.root / "private/flake.lock").write_text(json.dumps({"nodes": {"desktop": {"locked": {"type": "path", "path": str(self.root / "public")}}}}))
        (self.root / "private/overlays/tools-pins.json").write_text(json.dumps({"codex": {"version": "1.0.0", "srcHash": "old"}, "claude-code": {"version": "1.0.0", "srcHash": "old"}}))
        (self.root / "private/bin/nixos-config").write_text("#!/bin/bash\n")
        (self.root / "public/flake.nix").write_text("# staged/untracked working-tree bytes\n")
        self.config = {"configurationRoot": str(self.root), "home": str(base), "user": "test",
                       "uid": os.getuid(), "stateDirectory": str(base / "state"),
                       "wrapper": str(self.root / "private/bin/nixos-config"),
                       "socketPath": str(base / "control.sock")}
        self.coordinator = FakeCoordinator(self.config)

    def managed(self):
        return {name: (self.root / name).read_bytes() for name in updates.MANAGED}

    def perform(self, action, **options):
        result = self.coordinator.start(action, **options)
        self.assertTrue(result["ok"], result)
        self.coordinator.worker.join(timeout=5)
        self.assertFalse(self.coordinator.worker.is_alive())
        return self.coordinator.snapshot()

    def test_check_uses_host_discovery_without_building_or_touching_live_locks(self):
        original = self.managed()
        snapshot = self.perform("check")
        self.assertEqual(snapshot["status"], "idle")
        self.assertEqual(snapshot["changes"]["system"], [{"name": "example", "from": "1.0.0", "to": "2.0.0"}])
        self.assertEqual(snapshot["sourceChanges"], [{"name": "public/nixpkgs", "from": "old-revision", "to": "new-revision"}])
        self.assertEqual(snapshot["systemVersion"], {"from": "26.11.20261010.old", "to": "26.11.20261016.new"})
        self.assertTrue(self.coordinator.assert_machine_stdout)
        self.assertEqual(len(snapshot["changes"]["tools"]), 2)
        self.assertEqual(snapshot["changes"]["flatpak"][0]["id"], "org.example.App")
        self.assertEqual(sum(command[0] == "bash" and command[2] == "check-tools" for command in self.coordinator.commands), 1)
        self.assertEqual(self.managed(), original)
        self.assertFalse(any(command[0] == "update-tools" or "build" in command or "start" in command for command in self.coordinator.commands))
        self.assertEqual(list((self.coordinator.directory / "candidates").iterdir()), [])

    def test_source_only_changes_remain_available_without_inventing_package_bumps(self):
        self.coordinator.keep_package_versions = True
        with patch.object(self.coordinator, "check_tools", return_value=[]), patch.object(self.coordinator, "check_flatpak", return_value=[]):
            snapshot = self.perform("check")
        self.assertEqual(snapshot["changes"]["system"], [])
        self.assertTrue(snapshot["sourceChanges"])
        self.assertTrue(snapshot["available"])
        self.assertTrue(snapshot["lastCheckSuccessful"])
        snapshot = self.perform("flatpak")
        self.assertTrue(snapshot["available"])

    def test_selected_package_version_sets_deduplicate_and_show_additions_and_removals(self):
        metadata = self.coordinator.system_metadata(self.root)
        self.assertEqual(metadata["packages"], {"example": ["1.0.0"]})
        self.assertEqual(updates.selected_package_changes({"example": ["1.0", "1.1"], "removed": ["1"]},
                                                         {"example": ["1.1", "2.0"], "added": ["3"]}), [
            {"name": "added", "from": "∅", "to": "3"},
            {"name": "example", "from": "1.0, 1.1", "to": "1.1, 2.0"},
            {"name": "removed", "from": "1", "to": "∅"},
        ])

    def test_package_eval_failure_cannot_report_system_up_to_date(self):
        self.coordinator.fail_metadata = True
        with patch.object(self.coordinator, "check_tools", return_value=[]), patch.object(self.coordinator, "check_flatpak", return_value=[]):
            snapshot = self.perform("check")
        self.assertFalse(snapshot["lastCheckSuccessful"])
        self.assertIn("selected package evaluation failed", snapshot["checkErrors"]["system"])
        self.assertEqual(snapshot["changes"]["system"], [])

    def test_package_expression_escapes_nix_interpolation_and_evaluates_only_metadata(self):
        self.coordinator.config["user"] = 'test${builtins.abort "unsafe"}'
        self.coordinator.system_metadata(self.root)
        command = self.coordinator.commands[-1]
        expression = command[command.index("--apply") + 1]
        self.assertIn(r'test\${builtins.abort \"unsafe\"}', expression)
        self.assertEqual(command[3], "config")
        self.assertIn("c.environment.systemPackages", expression)
        self.assertIn("home.packages", expression)
        self.assertEqual(command[-1], "--json")

    def test_failed_prepare_preserves_live_pins_and_reports_actual_failure(self):
        original = self.managed()
        self.coordinator.fail_tools = True
        snapshot = self.perform("prepare")
        self.assertEqual(snapshot["status"], "failed")
        self.assertIn("Codex package preparation failed", snapshot["error"])
        self.assertFalse(snapshot["prepared"]["ready"])
        self.assertEqual(self.managed(), original)
        self.assertFalse(any(command[0] == "bash" and command[2] == "build" for command in self.coordinator.commands))
        self.assertEqual(list((self.coordinator.directory / "candidates").iterdir()), [])

    def test_failed_check_stays_uncertified_after_unrelated_flatpak_success(self):
        self.coordinator.fail_inputs = True
        with patch.object(self.coordinator, "check_tools", return_value=[]):
            checked = self.perform("check")
        self.assertFalse(checked["lastCheckSuccessful"])
        self.assertIn("system", checked["checkErrors"])
        snapshot = self.perform("flatpak")
        self.assertEqual(snapshot["status"], "idle")
        self.assertFalse(snapshot["available"])
        self.assertFalse(snapshot["lastCheckSuccessful"])
        self.assertIn("system", snapshot["checkErrors"])

    def test_discovery_invalidates_a_different_previously_built_plan(self):
        self.assertTrue(self.perform("prepare")["prepared"]["ready"])
        with patch.object(self.coordinator, "check_tools", return_value=[{"name": "codex", "from": "1.0.0", "to": "3.0.0"}]):
            snapshot = self.perform("check")
        self.assertFalse(snapshot["prepared"]["ready"])
        self.assertEqual(snapshot["changes"]["tools"][0]["to"], "3.0.0")
        self.assertTrue(snapshot["lastCheckSuccessful"])

    def test_real_pipe_reader_separates_build_stdout_from_diagnostic_store_paths(self):
        program = "import sys; print('  /nix/store/" + "b" * 32 + "-dependency.drv', file=sys.stderr); print('" + STORE_PATH + "')"
        output = updates.Coordinator.run(self.coordinator, [sys.executable, "-c", program],
                                         stdout_only=True, record=False, timeout=5)
        self.assertEqual(output, STORE_PATH + "\n")

    def test_command_logs_redact_credentials_split_between_pipe_reads(self):
        operation_id = "d" * 32
        self.coordinator.state["operationId"] = operation_id
        program = "import os,time; os.write(2,b'ghp_abcdefgh'); time.sleep(0.05); os.write(2,b'ijklmnopqrst\\n')"
        updates.Coordinator.run(self.coordinator, [sys.executable, "-c", program], timeout=5)
        details = self.coordinator.details(operation_id)
        self.assertTrue(details["ok"])
        self.assertNotIn("abcdefgh", details["log"])
        self.assertIn("[redacted]", details["log"])

    def test_nonzero_process_keeps_root_hash_error_before_long_dependency_cascade(self):
        root_error = ("error: hash mismatch in fixed-output derivation '/nix/store/example-package.drv':\n"
                      "  specified: sha256-OLD\n  got: sha256-NEW\n")
        # Separate pipe writes ensure the root error has left run's output tail.
        program = ("import os,time; os.write(2," + repr(root_error.encode()) + "); time.sleep(0.03); "
                   "cascade=''.join(\"error: Cannot build '/nix/store/dependent-\"+str(i)+'-'+('x'*700)+\".drv'\\nReason: 1 dependency failed.\\n\" for i in range(200)); "
                   "os.write(2,cascade.encode()); raise SystemExit(1)")
        with self.assertRaises(RuntimeError) as raised:
            updates.Coordinator.run(self.coordinator, [sys.executable, "-c", program], timeout=5, record=False)
        summary = str(raised.exception)
        self.assertIn("hash mismatch", summary)
        self.assertIn("specified: sha256-OLD", summary)
        self.assertIn("got: sha256-NEW", summary)
        self.assertNotIn("Cannot build", summary)
        self.assertLess(len(summary), 3000)

    def test_assertion_summary_keeps_actionable_text_and_redacts_credentials(self):
        output = ("evaluation progress\nerror:\n       Failed assertions:\n"
                  "       - The option programs.git.userName can no longer be used.\n"
                  "       - Use programs.git.settings.user.name instead.\n"
                  "error: Cannot build '/nix/store/home-manager-generation.drv'\n")
        summary = updates.error_summary(output)
        self.assertIn("Failed assertions", summary)
        self.assertIn("programs.git.settings.user.name", summary)
        self.assertNotIn("Cannot build", summary)
        generic = updates.error_summary("error: fetch failed for https://user:password@example.org/file\n"
                                        "error: Cannot build '/nix/store/dependent.drv'\n")
        self.assertIn("fetch failed", generic)
        self.assertNotIn("password", generic)

    def test_evaluation_summary_keeps_cause_after_long_context_trace(self):
        context = "error:\n" + "       … while evaluating an option\n" * 40
        cause = "       error: brave has been removed from nixpkgs\n"
        # Exercise incremental summaries as well as the final output summary.
        program = ("import os,time; os.write(2," + repr(context.encode()) + "); "
                   "time.sleep(0.03); os.write(2," + repr(cause.encode()) + "); "
                   "raise SystemExit(1)")
        with self.assertRaises(RuntimeError) as raised:
            updates.Coordinator.run(self.coordinator, [sys.executable, "-c", program],
                                    timeout=5, record=False)
        self.assertIn("brave has been removed", str(raised.exception))
        self.assertNotIn("while evaluating", str(raised.exception))

    def test_wrapper_lock_bypass_requires_thread_ownership_of_shared_lock(self):
        with patch.object(self.coordinator, "run", return_value="") as run:
            self.coordinator.wrapper(self.root, "lock")
            self.assertNotIn("NIXOS_MAINTENANCE_LOCKED", run.call_args.kwargs["env"])
            with self.coordinator.maintenance():
                self.coordinator.wrapper(self.root, "lock")
                self.assertEqual(run.call_args.kwargs["env"]["NIXOS_MAINTENANCE_LOCKED"], "1")
            self.coordinator.wrapper(self.root, "lock")
            self.assertNotIn("NIXOS_MAINTENANCE_LOCKED", run.call_args.kwargs["env"])

    def test_prepare_and_apply_without_private_cli_tools(self):
        (self.root / "private/overlays/tools-pins.json").unlink()
        self.assertEqual(self.coordinator.check_tools(self.root), [])
        self.assertTrue(self.perform("prepare")["prepared"]["ready"])
        self.assertFalse(any(command[0] == "update-tools" for command in self.coordinator.commands))
        self.assertEqual(self.perform("apply")["status"], "idle")

    def test_prepare_builds_once_roots_closure_and_preserves_working_tree(self):
        original = self.managed()
        snapshot = self.perform("prepare")
        self.assertTrue(snapshot["prepared"]["ready"])
        self.assertEqual(snapshot["prepared"]["packageChanges"], [{"name": "codex", "from": "1.0.0", "to": "2.0.0"}])
        self.assertEqual(self.managed(), original)
        self.assertEqual(sum(command[0] == "bash" and command[2] == "build" for command in self.coordinator.commands), 1)
        self.assertEqual(sum(command[0] == "nix-store" for command in self.coordinator.commands), 1)
        internal = self.coordinator.state["prepared"]
        self.assertTrue(Path(internal["gcroot"]).is_symlink())
        self.assertEqual((Path(internal["candidate"]) / "public/flake.nix").read_bytes(), (self.root / "public/flake.nix").read_bytes())
        self.assertNotIn("fingerprint", snapshot["prepared"])

    def test_completed_activation_releases_candidate_and_gcroot(self):
        for action in ("apply", "boot"):
            with self.subTest(action=action):
                self.perform("prepare")
                prepared = dict(self.coordinator.state["prepared"])
                self.assertEqual(self.perform(action)["status"], "idle")
                self.assertFalse(Path(prepared["gcroot"]).is_symlink())
                self.assertFalse(Path(prepared["candidate"]).exists())

    def test_restart_prunes_unusable_candidate_but_keeps_ready_candidate(self):
        self.perform("prepare")
        prepared = dict(self.coordinator.state["prepared"])
        self.coordinator = FakeCoordinator(self.config)
        self.assertTrue(Path(prepared["gcroot"]).is_symlink())
        self.assertTrue(Path(prepared["candidate"]).is_dir())
        self.coordinator.state["prepared"]["ready"] = False
        self.coordinator.save()
        self.coordinator = FakeCoordinator(self.config)
        self.assertFalse(Path(prepared["gcroot"]).is_symlink())
        self.assertFalse(Path(prepared["candidate"]).exists())

    def test_observer_releases_root_when_source_changes(self):
        self.perform("prepare")
        prepared = dict(self.coordinator.state["prepared"])
        (self.root / "public/flake.nix").write_text("# different configuration\n")
        with patch.object(self.coordinator, "automation", return_value={}), \
             patch.object(self.coordinator, "generations", return_value=[]), \
             patch.object(self.coordinator, "restart_required", return_value=False), \
             patch.object(self.coordinator, "pending_boot", return_value=False):
            updates.Coordinator.refresh_observed(self.coordinator)
        self.assertFalse(self.coordinator.state["prepared"]["ready"])
        self.assertFalse(Path(prepared["gcroot"]).is_symlink())
        self.assertFalse(Path(prepared["candidate"]).exists())

    def test_diff_closures_version_sets_additions_removals_and_size_only_rows(self):
        summary = ("acpi-call: 2020-04-07-5.8.16 → 2020-04-07-5.8.18\n"
                   "bluez-qt: +12.6 KiB\n"
                   "dolphin: 20.08.1 → 20.08.2, +13.9 KiB\n"
                   "kdeconnect: 20.08.2 → ∅, -6597.8 KiB\n"
                   "kdeconnect-kde: ∅ → 20.08.2, +6599.7 KiB\n"
                   "libfoo: 1.2, 1.3 → 1.4, 1.5, +1.0 MiB\n"
                   "empty-version: ε → 1.0\n"
                   "codex: 1.0.0 -> 2.0.0\n")
        self.assertEqual(updates.package_changes(summary), [
            {"name": "acpi-call", "from": "2020-04-07-5.8.16", "to": "2020-04-07-5.8.18"},
            {"name": "dolphin", "from": "20.08.1", "to": "20.08.2"},
            {"name": "kdeconnect", "from": "20.08.2", "to": "∅"},
            {"name": "kdeconnect-kde", "from": "∅", "to": "20.08.2"},
            {"name": "libfoo", "from": "1.2, 1.3", "to": "1.4, 1.5"},
            {"name": "empty-version", "from": "ε", "to": "1.0"},
            {"name": "codex", "from": "1.0.0", "to": "2.0.0"},
        ])

    def test_source_changed_refuses_apply_before_any_promotion_or_activation(self):
        self.perform("prepare")
        original = self.managed()
        (self.root / "public/flake.nix").write_text("# changed since snapshot\n")
        snapshot = self.perform("apply")
        self.assertEqual(snapshot["status"], "failed")
        self.assertIn("changed since preparation", snapshot["error"])
        self.assertFalse(snapshot["prepared"]["ready"])
        self.assertEqual(self.managed(), original)
        self.assertFalse(any("switch-built" in command or "lock" in command for command in self.coordinator.commands))

    def test_apply_canonicalizes_private_lock_and_activates_exact_built_closure(self):
        self.perform("prepare")
        snapshot = self.perform("apply")
        self.assertEqual(snapshot["status"], "idle")
        self.assertFalse(snapshot["prepared"]["ready"])
        self.assertEqual(snapshot["changes"]["system"], [])
        self.assertEqual(snapshot["changes"]["tools"], [])
        self.assertFalse(snapshot["available"])
        desktop = json.loads((self.root / "private/flake.lock").read_text())["nodes"]["desktop"]["locked"]["path"]
        self.assertEqual(desktop, str(self.root / "public"))
        self.assertEqual(self.coordinator.commands[-1], ["bash", self.config["wrapper"], "switch-built", STORE_PATH])
        self.assertEqual(sum(command[0] == "bash" and command[2] == "build" for command in self.coordinator.commands), 1)

    def test_failed_canonicalization_restores_all_managed_bytes(self):
        self.perform("prepare")
        original = self.managed()
        self.coordinator.fail_lock = True
        snapshot = self.perform("boot")
        self.assertEqual(snapshot["status"], "failed")
        self.assertEqual(self.managed(), original)
        self.assertTrue(snapshot["prepared"]["ready"])
        self.assertFalse(any("boot-built" in command for command in self.coordinator.commands))

    def test_flatpak_failure_is_independent_and_does_not_acquire_maintenance_lock(self):
        self.perform("prepare")
        prepared = self.coordinator.snapshot()["prepared"]
        self.coordinator.fail_flatpak = True
        with patch.object(self.coordinator, "maintenance", side_effect=AssertionError("would deadlock")):
            snapshot = self.perform("flatpak")
        self.assertEqual(snapshot["status"], "failed")
        self.assertIn("Flatpak service failed", snapshot["error"])
        self.assertEqual(snapshot["prepared"], prepared)
        self.assertEqual(self.coordinator.commands[-1], ["systemctl", "start", "flatpak-auto-update.service"])

    def test_busy_allowlist_and_generation_validation(self):
        started, release = threading.Event(), threading.Event()

        def blocking_check(_operation):
            started.set()
            release.wait(timeout=5)

        with patch.object(self.coordinator, "check", blocking_check):
            first = self.coordinator.start("check")
            self.assertTrue(started.wait(timeout=2))
            try:
                self.assertTrue(first["ok"])
                self.assertFalse(self.coordinator.start("prepare")["ok"])
                self.assertFalse(self.coordinator.start("reboot")["ok"])
                self.assertFalse(self.coordinator.start("/tmp/anything")["ok"])
            finally:
                release.set()
                self.coordinator.worker.join(timeout=5)
        for generation in ("1", "../../etc", 0, -1, True, None):
            self.assertFalse(self.coordinator.start("rollback", generation)["ok"])

    def test_automatic_job_drives_busy_without_overwriting_owned_worker_state(self):
        automatic = {"id": "tools-auto-update", "label": "CLI tools", "state": "activating",
                     "lastRun": "2026-10-16T06:50:21+00:00"}
        self.coordinator.observed["automations"] = [automatic]
        snapshot = self.coordinator.snapshot()
        self.assertTrue(snapshot["busy"])
        self.assertEqual(snapshot["stage"], "Automatic update · CLI tools")
        self.assertEqual(snapshot["startedAt"], automatic["lastRun"])
        self.assertEqual(snapshot["operationId"], "automation:tools-auto-update")
        self.assertFalse(self.coordinator.start("prepare")["ok"])
        self.assertFalse(self.coordinator.state["busy"])
        self.assertIsNone(self.coordinator.state["lastAction"])
        self.coordinator.state.update(busy=True, stage="Building candidate", operationId="e" * 32,
                                      startedAt="2026-10-16T06:49:00+00:00", status="preparing")
        owned = self.coordinator.snapshot()
        self.assertEqual(owned["operationId"], "e" * 32)
        self.assertEqual(owned["stage"], "Building candidate")
        self.assertEqual(owned["status"], "preparing")
        self.coordinator.state.update(busy=False, stage="", operationId=None, status="idle")
        automatic["state"] = "inactive"
        self.assertFalse(self.coordinator.snapshot()["busy"])
        self.assertIsNone(self.coordinator.snapshot()["operationId"])

    def test_shared_timer_lock_prevents_snapshot_and_mutation(self):
        original = self.managed()
        with self.coordinator.maintenance():
            snapshot = self.perform("prepare")
        self.assertEqual(snapshot["status"], "failed")
        self.assertIn("Another maintenance job", snapshot["error"])
        self.assertEqual(self.managed(), original)
        self.assertEqual(self.coordinator.commands, [])

    def test_restart_recovers_interrupted_worker_and_caps_durable_history(self):
        self.coordinator.state.update(busy=True, status="preparing", operationId="b" * 32,
                                      startedAt=updates.now(), lastAction="prepare")
        for index in range(70):
            self.coordinator.append_history(format(index, "032x"), "check", "success")
        self.coordinator.save()
        restarted = FakeCoordinator(self.config)
        snapshot = restarted.snapshot()
        self.assertFalse(snapshot["busy"])
        self.assertEqual(snapshot["status"], "failed")
        self.assertEqual(len(snapshot["history"]), 50)
        self.assertTrue(any(row["status"] == "interrupted" for row in snapshot["history"]))
        self.assertEqual(stat.S_IMODE((restarted.directory / "state.json").stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(restarted.directory.stat().st_mode), 0o700)

    def test_failed_automatic_job_is_visible_without_prior_coordinator_history(self):
        def properties(unit, _fields):
            if unit.endswith(".timer"):
                return {"NextElapseUSecRealtime": "2026-10-17T02:01:37+00:00"}
            return {"ActiveState": "failed", "Result": "exit-code", "ExecMainStatus": "1",
                    "ExecMainStartTimestamp": "2026-10-16T06:50:21+00:00",
                    "ExecMainExitTimestamp": "2026-10-16T06:50:37+00:00", "InvocationID": "c" * 32}

        with patch.object(self.coordinator, "properties", properties):
            row = self.coordinator.automation("tools-auto-update", "CLI tools")
        self.assertEqual(row["state"], "failed")
        self.assertEqual(row["result"], "exit-code")
        self.assertIn("exit 1", row["error"])
        self.assertEqual(row["nextRun"], "2026-10-17T02:01:37+00:00")
        history = self.coordinator.snapshot()["history"]
        self.assertEqual(history[0]["status"], "failed")
        self.assertTrue(history[0]["id"].startswith("automation:tools-auto-update:"))
        details = self.coordinator.details(history[0]["id"])
        self.assertTrue(details["ok"])
        self.assertNotIn("password", details["log"])
        self.assertNotIn("ghp_", details["log"])

    def test_activation_reset_cannot_hide_or_rewrite_failed_automatic_invocation(self):
        metadata = {"ActiveState": "inactive", "Result": "success", "ExecMainStatus": "1", "ExecMainCode": "1",
                    "ExecMainStartTimestamp": "2026-10-16T06:50:21+00:00",
                    "ExecMainExitTimestamp": "2026-10-16T06:50:37+00:00", "InvocationID": "f" * 32}
        history_id = "automation:tools-auto-update:" + "f" * 32
        self.coordinator.append_history(history_id, "automatic-tools", "success")

        def properties(unit, _fields):
            return {"NextElapseUSecRealtime": "2026-10-17T02:01:37+00:00"} if unit.endswith(".timer") else metadata

        with patch.object(self.coordinator, "properties", properties):
            row = self.coordinator.automation("tools-auto-update", "CLI tools")
            self.assertEqual(row["result"], "exit-code")
            self.assertIn("exit 1", row["error"])
            self.assertEqual(self.coordinator.snapshot()["history"][0]["status"], "failed")
            # Even a later metadata reset cannot turn the same known invocation
            # into a successful new run; its InvocationID has not changed.
            metadata["ExecMainStatus"] = "0"
            reset = self.coordinator.automation("tools-auto-update", "CLI tools")
            self.assertIn("exit 1", reset["error"])
            self.assertEqual(reset["result"], "exit-code")
            self.assertEqual(self.coordinator.snapshot()["history"][0]["status"], "failed")

    def test_socket_permissions_same_uid_and_json_protocol(self):
        path = self.config["socketPath"]
        with updates.ControlServer(path, self.coordinator, os.getuid()) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                self.assertEqual(stat.S_IMODE(Path(path).stat().st_mode), 0o600)
                self.assertEqual(updates.client({"command": "status"}, path)["status"], "idle")
                self.assertFalse(updates.client({"command": "action", "action": "reboot"}, path)["ok"])
                self.assertFalse(updates.client({"command": "details", "id": "../../etc/passwd"}, path)["ok"])
                with socket.socket(socket.AF_UNIX) as connection:
                    connection.connect(path)
                    connection.sendall(b"x" * (updates.MAX_REQUEST + 1) + b"\n")
                    response = json.loads(connection.recv(4096))
                    self.assertIn("large", response["error"])
                server.allowed_uid = os.getuid() + 1
                self.assertFalse(updates.client({"command": "status"}, path)["ok"])
            finally:
                server.shutdown()
                thread.join(timeout=2)

    @unittest.skipIf(os.getuid() == 0, "The coordinator deliberately refuses a root daemon")
    def test_daemon_process_start_client_roundtrip_and_duplicate_ownership(self):
        base = Path(self.temporary.name)
        fake_bin = base / "bin"
        fake_bin.mkdir()
        systemctl = fake_bin / "systemctl"
        systemctl.write_text("#!" + sys.executable + "\nimport sys\nassert 'show' in sys.argv, sys.argv\nprint('ActiveState=inactive\\nResult=success')\n")
        systemctl.chmod(0o755)
        config_path = base / "config.json"
        # Dynamic user IDs are normal in NixOS modules; null resolves to daemon uid.
        config_path.write_text(json.dumps({**self.config, "uid": None}))
        # Stub only host profile observations; main, state, server, subprocess
        # metadata queries and the independent client are the actual entrypoints.
        bootstrap = ("import importlib.util,sys; s=importlib.util.spec_from_file_location('coordinator',sys.argv[1]); "
                     "m=importlib.util.module_from_spec(s); s.loader.exec_module(m); "
                     "m.Coordinator.generations=staticmethod(lambda: []); "
                     "m.Coordinator.restart_required=staticmethod(lambda: False); "
                     "m.Coordinator.pending_boot=staticmethod(lambda: False); "
                     "sys.argv=sys.argv[1:]; sys.exit(m.main())")
        command = [sys.executable, "-c", bootstrap, str(SCRIPT), "serve", "--config", str(config_path)]
        environment = {**os.environ, "PATH": str(fake_bin)}
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)
        try:
            deadline = time.monotonic() + 5
            snapshot = {}
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    stdout, stderr = process.communicate()
                    self.fail("Daemon exited before readiness: " + stderr.decode() + stdout.decode())
                snapshot = updates.client({"command": "status"}, self.config["socketPath"])
                if snapshot.get("status") == "idle":
                    break
                time.sleep(0.02)
            self.assertEqual(snapshot.get("status"), "idle", snapshot)
            self.assertEqual(len(snapshot["automations"]), 3)
            client = subprocess.run([sys.executable, str(SCRIPT), "--socket", self.config["socketPath"], "status"],
                                    capture_output=True, text=True, timeout=5)
            self.assertEqual(client.returncode, 0, client.stderr)
            self.assertEqual(json.loads(client.stdout)["status"], "idle")
            duplicate = subprocess.run(command, capture_output=True, text=True, env=environment, timeout=5)
            self.assertNotEqual(duplicate.returncode, 0)
            self.assertIn("already running", duplicate.stderr)
            self.assertEqual(updates.client({"command": "status"}, self.config["socketPath"])["status"], "idle")
        finally:
            process.terminate()
            process.communicate(timeout=5)

    def test_snapshot_symlinks_and_artifacts_are_consistent(self):
        (self.root / "public/.git").mkdir()
        (self.root / "public/.git/index").write_text("do not copy")
        (self.root / "public/result").symlink_to("/nix/store/fake")
        (self.root / "public/current.lock").write_text("not a configuration file")
        (self.root / "private/link.nix").symlink_to(self.root / "public/flake.nix")
        destination = Path(self.temporary.name) / "snapshot"
        updates.copy_configuration(self.root, destination)
        self.assertFalse((destination / "public/.git").exists())
        self.assertFalse((destination / "public/result").is_symlink())
        self.assertFalse((destination / "public/current.lock").exists())
        self.assertEqual((destination / "private/link.nix").resolve(), destination / "public/flake.nix")
        self.assertEqual((destination / "private/link.nix").read_bytes(), (self.root / "public/flake.nix").read_bytes())


if __name__ == "__main__":
    unittest.main()
