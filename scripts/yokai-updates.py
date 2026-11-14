#!/usr/bin/env python3
"""User-owned update coordinator. Only explicit actions can build or activate.

The daemon owns durable state and one worker; the desktop is a disposable client.
Candidate checkouts contain working-tree bytes, including staged and untracked
configuration. Only managed lock files and optional CLI pins are promoted on activation.
"""

import argparse
import contextlib
import copy
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import socket
import socketserver
import stat
import struct
import subprocess
import sys
import tempfile
import threading
import time
import uuid


SOCKET_PATH = "/run/yokai-updates/control.sock"
ACTIONS = {"check", "prepare", "apply", "boot", "flatpak", "retry", "rollback"}
MANAGED = ("public/flake.lock", "private/flake.lock", "private/overlays/tools-pins.json")


def managed_files(root):
    return [name for name in MANAGED if name != "private/overlays/tools-pins.json"
            or (Path(root) / name).is_file()]


AUTOMATIONS = (("system-auto-update", "System"), ("tools-auto-update", "CLI tools"),
               ("flatpak-auto-update", "Flatpak"))
LOG_LIMIT = 96 * 1024
MAX_REQUEST = 8192


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def atomic_write(path, contents, mode=0o600):
    """Keep owner-only bytes and an intact prior version across interrupted writes."""
    path = Path(path)
    fd, temporary = tempfile.mkstemp(prefix=".write-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(contents)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def redact(text):
    text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
    text = re.sub(r"(?i)(https?://)[^\s/@:]+:[^\s/@]+@", r"\1[redacted]@", text)
    text = re.sub(r"\b(?:github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9_]+)\b", "[redacted]", text)
    text = re.sub(r"(?im)^.*(?:access-tokens\s*=|authorization\s*:|(?:password|token|secret)\s*=).*$",
                  "[credential line redacted]", text)
    return text


def error_summary(output, *, fallback=True):
    """Keep the causal diagnostic instead of Nix's trailing dependency cascade."""
    lines = redact(output).splitlines()
    cascade = re.compile(r"(?i)(?:error:\s*Cannot build|Reason:\s*.*dependenc|.*dependent derivations failed)")
    hash_errors = [index for index, line in enumerate(lines) if re.search(r"(?i)error:\s*hash mismatch", line)]
    assertions = [index for index, line in enumerate(lines) if "failed assertions" in line.lower()]
    errors = [index for index, line in enumerate(lines)
              if re.search(r"(?i)\b(?:error|fatal):", line) and not cascade.search(line)]
    # Nix starts evaluation traces with a bare `error:`; the actionable
    # diagnostic follows the context frames and may be far below that header.
    diagnostics = [index for index in errors
                   if re.search(r"(?i)\b(?:error|fatal):[^\S\n]*\S", lines[index])]
    matches = hash_errors or assertions or diagnostics or errors
    if matches:
        start = matches[0]
        block = []
        for line in lines[start:start + 16]:
            if block and (cascade.search(line) or re.search(r"(?i)\b(?:error|fatal):", line)):
                break
            block.append(line)
        return "\n".join(block).strip()[:2400]
    if not fallback:
        return ""
    useful = [line for line in lines if line.strip() and not cascade.search(line)]
    return "\n".join(useful[-10:])[-1800:] or "Command failed; see Details for the full build log."


def excluded(name):
    return (name in {".git", "__pycache__", ".direnv", ".cache"}
            or name == "result" or name.startswith("result-")
            or name.startswith(".write-") or name.endswith((".tmp", ".swp", "~"))
            or ".tmp." in name or (name.endswith(".lock") and name != "flake.lock"))


def source_entries(root):
    for tree in ("public", "private"):
        base = Path(root) / tree
        for directory, dirs, files in os.walk(base, followlinks=False):
            dirs[:] = sorted(name for name in dirs if not excluded(name))
            for name in sorted(files + [name for name in dirs if (Path(directory) / name).is_symlink()]):
                if not excluded(name):
                    yield Path(directory) / name


def fingerprint(root):
    digest = hashlib.sha256()
    root = Path(root)
    for path in source_entries(root):
        digest.update(str(path.relative_to(root)).encode() + b"\0")
        digest.update(str(stat.S_IMODE(path.lstat().st_mode)).encode() + b"\0")
        if path.is_symlink():
            digest.update(b"link\0" + os.readlink(path).encode())
        else:
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(128 * 1024), b""):
                    digest.update(chunk)
        digest.update(b"\0")
    return digest.hexdigest()


def copy_configuration(source, destination):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    for tree in ("public", "private"):
        shutil.copytree(source / tree, destination / tree, symlinks=True,
                        ignore=lambda _directory, names: [name for name in names if excluded(name)])
    # A source symlink must never make a candidate read mutable live bytes.
    for path in source_entries(destination):
        if not path.is_symlink():
            continue
        target = path.resolve(strict=True)
        if target.is_relative_to(source):
            path.unlink()
            path.symlink_to(destination / target.relative_to(source))
        elif not target.is_relative_to(destination) and not target.is_relative_to("/nix/store"):
            raise RuntimeError("Configuration symlink points outside its snapshot: " + str(path.relative_to(destination)))


def locked_inputs(root):
    inputs = {}
    for tree in ("public", "private"):
        path = Path(root) / tree / "flake.lock"
        if not path.exists():
            continue
        for name, node in json.loads(path.read_text()).get("nodes", {}).items():
            locked = node.get("locked", {})
            # desktop is a local snapshot, represented by its actual source inputs.
            if locked.get("type") == "path":
                continue
            revision = locked.get("rev") or locked.get("narHash")
            if revision:
                inputs[tree + "/" + name] = revision
    return inputs


def revision_changes(before, after):
    return [{"name": name, "from": before.get(name, ""), "to": after.get(name, "")}
            for name in sorted(before.keys() | after.keys()) if before.get(name) != after.get(name)]


def package_changes(summary):
    """Extract version sets from diff-closures, leaving size-only rows in Details."""
    changes = []
    for line in redact(summary).splitlines():
        match = re.fullmatch(r"\s*([^\s:]+):\s*(.+?)\s+(?:→|->)\s+(.+?)\s*", line)
        if not match:
            continue
        name, before, after = match.groups()
        after = re.sub(r",\s*[+-][0-9]+(?:\.[0-9]+)?\s+(?:B|[KMGTPEZY]iB)$", "", after)
        changes.append({"name": name, "from": before, "to": after})
    return changes


def selected_package_changes(before, after):
    return [{"name": name, "from": ", ".join(before.get(name, [])) or "∅",
             "to": ", ".join(after.get(name, [])) or "∅"}
            for name in sorted(before.keys() | after.keys()) if before.get(name) != after.get(name)]


class Coordinator:
    def __init__(self, config):
        self.config = config
        self.root = Path(config["configurationRoot"]).resolve()
        self.directory = Path(config["stateDirectory"]).expanduser()
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.directory, 0o700)
        for child in ("logs", "candidates", "gcroots"):
            (self.directory / child).mkdir(exist_ok=True, mode=0o700)
            os.chmod(self.directory / child, 0o700)
        self.mutex = threading.RLock()
        self.maintenance_state = threading.local()
        self.worker = None
        self.observed = {"automations": [], "generations": [], "restartRequired": False, "pendingBoot": False}
        self.observer_stop = threading.Event()
        self.secret_values = []
        self.state = {"schemaVersion": 2, "status": "idle", "busy": False, "stage": "", "operationId": None,
                      "startedAt": None, "lastChecked": None, "error": None, "available": False,
                      "lastCheckSuccessful": False, "checkErrors": {},
                      "changes": {"system": [], "tools": [], "flatpak": []},
                      "sourceChanges": [], "systemVersion": {"from": "", "to": ""},
                      "prepared": {"ready": False}, "history": [], "lastAction": None}
        state_path = self.directory / "state.json"
        if state_path.exists():
            os.chmod(state_path, 0o600)
            try:
                saved = json.loads(state_path.read_text())
                if saved.get("schemaVersion", 1) < 2:
                    saved["sourceChanges"] = saved.get("changes", {}).get("system", [])
                    saved.get("changes", {})["system"] = []
                    saved["lastCheckSuccessful"] = False
                    saved["schemaVersion"] = 2
                self.state.update(saved)
            except (OSError, ValueError, TypeError):
                self.state["error"] = "Saved update state could not be read; no prepared system is trusted."
                self.state["status"] = "failed"
        if self.state["busy"]:
            error = "Coordinator restarted during an operation; inspect Details and current generations before retrying."
            self.append_history(self.state.get("operationId") or uuid.uuid4().hex,
                                self.state.get("lastAction") or "unknown", "interrupted", error)
            self.state.update(status="failed", busy=False, stage="Interrupted", error=error, operationId=None)
        prepared = self.state.get("prepared", {})
        if prepared.get("ready") and not self.valid_closure(prepared.get("path", "")):
            prepared["ready"] = False
            self.state["error"] = "The prepared system is no longer available; prepare again."
        self.save()
        self.prune_state_files()

    def prune_state_files(self):
        retained = {row["id"] for row in self.state["history"]}
        active = self.state.get("operationId")
        if active:
            retained.add(active)
        for path in (self.directory / "logs").glob("*.log"):
            if path.stem not in retained:
                path.unlink()
        # Only an applicable candidate needs its snapshot and GC root retained.
        prepared = self.state["prepared"] if self.state["prepared"].get("ready") else {}
        for parent, key in (("candidates", "candidate"), ("gcroots", "gcroot")):
            for path in (self.directory / parent).iterdir():
                if str(path) != prepared.get(key) and re.fullmatch(r"[a-f0-9]{32}", path.name):
                    self.discard_candidate({key: str(path)})

    def save(self):
        atomic_write(self.directory / "state.json", json.dumps(self.state, ensure_ascii=False).encode())

    def snapshot(self):
        with self.mutex:
            result = copy.deepcopy(self.state)
            result.update(copy.deepcopy(self.observed))
            automatic = self.active_automation()
            if not self.state["busy"] and automatic:
                result.update(busy=True, status="automatic", stage="Automatic update · " + automatic["label"],
                              startedAt=automatic.get("lastRun"), operationId="automation:" + automatic["id"])
            result.pop("lastAction", None)
            prepared = result["prepared"]
            for internal in ("fingerprint", "candidate", "gcroot", "managed"):
                prepared.pop(internal, None)
            return result

    def active_automation(self):
        return next((row for row in self.observed["automations"]
                     if row["state"] in {"activating", "active", "deactivating"}), None)

    def update(self, **fields):
        with self.mutex:
            self.state.update(fields)
            self.save()

    def log_path(self, operation_id):
        if not re.fullmatch(r"[a-f0-9]{32}", operation_id):
            raise ValueError("Invalid operation ID")
        return self.directory / "logs" / (operation_id + ".log")

    def log(self, text, operation_id=None):
        operation_id = operation_id or self.state.get("operationId")
        if not operation_id:
            return
        path = self.log_path(operation_id)
        text = str(text)
        for secret in self.secret_values:
            text = text.replace(secret, "[redacted]")
        contents = path.read_bytes() if path.exists() else b""
        contents = (contents + redact(text).encode())[-LOG_LIMIT:]
        atomic_write(path, contents)

    def run(self, args, *, env=None, timeout=7200, record=True, stdout_only=False):
        """Stream bounded diagnostics without ever putting subprocess output on IPC stdout."""
        environment = os.environ.copy()
        environment.pop("NIXOS_MAINTENANCE_LOCKED", None)
        environment.update(HOME=self.config["home"], LC_ALL="C.UTF-8", NO_COLOR="1",
                           GIT_TERMINAL_PROMPT="0")
        if env:
            environment.update(env)
        process = subprocess.Popen([str(arg) for arg in args], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, env=environment, start_new_session=True)
        output = bytearray()
        stdout = bytearray()
        pending_log = {"stdout": bytearray(), "stderr": bytearray()}
        failure_excerpt = ""
        deadline = time.monotonic() + timeout
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ, "stdout")
                selector.register(process.stderr, selectors.EVENT_READ, "stderr")
                while selector.get_map():
                    if time.monotonic() > deadline:
                        raise TimeoutError("Command timed out: " + str(args[0]))
                    for key, _mask in selector.select(timeout=0.5):
                        chunk = os.read(key.fileobj.fileno(), 16384)
                        if not chunk:
                            selector.unregister(key.fileobj)
                            continue
                        output.extend(chunk)
                        del output[:-LOG_LIMIT]
                        if key.data == "stdout":
                            stdout.extend(chunk)
                            del stdout[:-LOG_LIMIT]
                        pending = pending_log[key.data]
                        pending.extend(chunk)
                        # Complete lines retain root errors across long cascades,
                        # and keep credential redaction intact across pipe reads.
                        if b"\n" in pending:
                            boundary = pending.rfind(b"\n") + 1
                            lines = pending[:boundary].decode(errors="replace")
                            failure_excerpt = error_summary(failure_excerpt + "\n" + lines, fallback=False)
                            if record:
                                self.log(lines)
                            del pending[:boundary]
                        del pending[:-LOG_LIMIT]
                code = process.wait(timeout=max(1, deadline - time.monotonic()))
        except BaseException:
            import signal
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise
        finally:
            process.stdout.close()
            process.stderr.close()
            for pending in pending_log.values():
                if pending:
                    lines = pending.decode(errors="replace")
                    failure_excerpt = error_summary(failure_excerpt + "\n" + lines, fallback=False)
                    if record:
                        self.log(lines)
        text = output.decode(errors="replace")
        if code:
            raise RuntimeError(str(args[0]) + " failed (exit " + str(code) + "): "
                               + error_summary(failure_excerpt + "\n" + text))
        return stdout.decode(errors="replace") if stdout_only else text

    @contextlib.contextmanager
    def maintenance(self):
        with (self.root / ".maintenance.lock").open("a") as stream:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError("Another maintenance job is running; retry after it finishes.") from None
            self.maintenance_state.held = True
            try:
                yield
            finally:
                self.maintenance_state.held = False

    @contextlib.contextmanager
    def nix_credentials(self):
        # gh output is deliberately never routed to the command logger or state.
        token = ""
        if shutil.which("gh"):
            try:
                response = subprocess.run(["gh", "auth", "token"], capture_output=True,
                                          text=True, timeout=10, check=False)
                if response.returncode == 0:
                    token = response.stdout.strip()
            except (OSError, subprocess.TimeoutExpired):
                pass
        # Credentials are ephemeral runtime data, never durable update state.
        runtime = Path(self.config.get("socketPath", SOCKET_PATH)).parent
        fd, path = tempfile.mkstemp(prefix=".nix-auth-", dir=runtime)
        try:
            if token and re.fullmatch(r"[A-Za-z0-9_]+", token):
                self.secret_values.append(token)
                with os.fdopen(fd, "w") as stream:
                    stream.write("access-tokens = github.com=" + token + "\n")
            else:
                os.close(fd)
            yield {"NIX_USER_CONF_FILES": path}
        finally:
            os.unlink(path)
            if token in self.secret_values:
                self.secret_values.remove(token)

    def candidate(self, operation_id):
        original = fingerprint(self.root)
        destination = self.directory / "candidates" / operation_id
        try:
            copy_configuration(self.root, destination)
            if fingerprint(self.root) != original:
                raise RuntimeError("Configuration changed while taking its snapshot; try again.")
            managed = {name: hashlib.sha256((self.root / name).read_bytes()).hexdigest() for name in managed_files(self.root)}
            return destination, original, managed
        except BaseException:
            shutil.rmtree(destination, ignore_errors=True)
            raise

    def wrapper(self, root, action, *args, env=None):
        environment = dict(env or {})
        environment["NIXOS_DESKTOP_DIR"] = str(Path(root) / "public")
        if getattr(self.maintenance_state, "held", False):
            environment["NIXOS_MAINTENANCE_LOCKED"] = "1"
        script = self.config["wrapper"] if Path(root) == self.root else Path(root) / "private/bin/nixos-config"
        return self.run(["bash", script, action, *args], env=environment, stdout_only=(action in {"build", "eval"}))

    def system_metadata(self, root, env=None):
        # Nix receives one expression argument. The username is a Nix string,
        # with interpolation escaped, and no whole-config JSON is requested.
        user = json.dumps(self.config["user"], ensure_ascii=False).replace("${", r"\${")
        expression = """c: let
          user = USER_LITERAL;
          users = c.home-manager.users or {};
          homePackages = if builtins.hasAttr user users
            then (builtins.getAttr user users).home.packages or [] else [];
          metadata = p: let parsed = builtins.parseDrvName p.name; in {
            name = p.pname or parsed.name;
            version = p.version or parsed.version;
          };
        in {
          systemVersion = c.system.nixos.version;
          packages = builtins.filter
            (p: builtins.isString p.name && p.name != "" && builtins.isString p.version && p.version != "")
            (builtins.map metadata (c.environment.systemPackages ++ homePackages));
        }""".replace("USER_LITERAL", user)
        output = self.wrapper(root, "eval", "config", "--apply", expression, "--json", env=env)
        metadata = json.loads(output)
        if not isinstance(metadata, dict) or not isinstance(metadata.get("systemVersion"), str) or not isinstance(metadata.get("packages"), list):
            raise RuntimeError("System package evaluation returned invalid metadata.")
        versions = {}
        for package in metadata["packages"]:
            if not isinstance(package, dict):
                raise RuntimeError("System package evaluation returned an invalid package.")
            name, version = package.get("name"), package.get("version")
            if isinstance(name, str) and name and isinstance(version, str) and version:
                versions.setdefault(name, set()).add(version)
        return {"systemVersion": metadata["systemVersion"],
                "packages": {name: sorted(values) for name, values in versions.items()}}

    def check_tools(self, root):
        pins_path = Path(root) / "private/overlays/tools-pins.json"
        if not pins_path.is_file():
            return []
        changes = json.loads(self.wrapper(root, "check-tools"))
        if not isinstance(changes, list) or any(
                not isinstance(row, dict) or any(not isinstance(row.get(key), str)
                                                for key in ("name", "from", "to"))
                for row in changes):
            raise RuntimeError("Host CLI update discovery returned invalid changes.")
        return changes

    def check_flatpak(self):
        output = self.run(["flatpak", "remote-ls", "--system", "--updates",
                           "--columns=application,name,version,branch,origin"], timeout=180, stdout_only=True)
        changes = []
        for line in output.splitlines():
            parts = line.split("\t")
            if len(parts) == 5 and parts[0]:
                changes.append(dict(zip(("id", "name", "version", "branch", "origin"), parts)))
        return changes

    def check(self, operation_id):
        # A later discovery can describe a different upstream revision from an
        # earlier build. Never leave Apply enabled against that different plan.
        self.update(prepared={**self.state["prepared"], "ready": False})
        errors = {}
        destination = None
        changes = {"system": [], "tools": [], "flatpak": []}
        sources = []
        system_version = {"from": "", "to": ""}
        try:
            destination, _source, _managed = self.candidate(operation_id)
            before = locked_inputs(destination)
            self.update(stage="Reading current selected package versions")
            try:
                with self.nix_credentials() as env:
                    baseline = self.system_metadata(destination, env)
                    system_version["from"] = baseline["systemVersion"]
                    self.update(stage="Checking system and application updates")
                    self.wrapper(destination, "update-inputs", env=env)
                    sources = revision_changes(before, locked_inputs(destination))
                    self.log("System source revisions:\n" + json.dumps(sources, ensure_ascii=False) + "\n")
                    candidate = self.system_metadata(destination, env)
                    system_version["to"] = candidate["systemVersion"]
                    changes["system"] = selected_package_changes(baseline["packages"], candidate["packages"])
            except Exception as error:
                errors["system"] = "System: " + redact(str(error))
            self.update(stage="Checking stable CLI versions")
            try:
                changes["tools"] = self.check_tools(destination)
            except Exception as error:
                errors["tools"] = "CLI tools: " + redact(str(error))
            self.update(stage="Checking Flatpak updates")
            try:
                changes["flatpak"] = self.check_flatpak()
            except Exception as error:
                errors["flatpak"] = "Flatpak: " + redact(str(error))
            self.update(changes=changes, sourceChanges=sources, systemVersion=system_version,
                        available=any(changes.values()) or bool(sources), lastChecked=now(),
                        lastCheckSuccessful=not errors, checkErrors=errors)
            if errors:
                raise RuntimeError("\n".join(errors.values()))
        finally:
            if destination:
                shutil.rmtree(destination, ignore_errors=True)

    @staticmethod
    def valid_closure(path):
        target = Path(path)
        return (bool(re.fullmatch(r"/nix/store/[a-z0-9]{32}-[^/]+", str(target)))
                and target.is_dir() and (target / "bin/switch-to-configuration").is_file()
                and os.access(target / "bin/switch-to-configuration", os.X_OK))

    def prepare(self, operation_id):
        destination, source, managed = self.candidate(operation_id)
        gcroot = self.directory / "gcroots" / operation_id
        succeeded = False
        try:
            before = locked_inputs(destination)
            pins_path = destination / "private/overlays/tools-pins.json"
            old_pins = json.loads(pins_path.read_text()) if pins_path.is_file() else {}
            with self.nix_credentials() as env:
                self.update(stage="Updating candidate system inputs")
                self.wrapper(destination, "update-inputs", env=env)
                self.update(stage="Preparing CLI packages")
                if old_pins:
                    self.run(["update-tools", "--flake", destination / "private"], env=env)
                self.update(stage="Building the candidate system")
                output = self.wrapper(destination, "build", env=env)
            paths = [line.strip() for line in output.splitlines()
                     if re.fullmatch(r"/nix/store/[a-z0-9]{32}-[^/\s]+", line.strip())]
            if len(paths) != 1 or not self.valid_closure(paths[0]):
                raise RuntimeError("Build did not produce exactly one valid NixOS system closure.")
            path = paths[0]
            self.update(stage="Protecting the prepared system from garbage collection")
            self.run(["nix-store", "--add-root", gcroot, "--indirect", "--realise", path])
            self.update(stage="Comparing system closures")
            try:
                summary = self.run(["nix", "store", "diff-closures", "/run/current-system", path],
                                   timeout=180, stdout_only=True)
                packages = package_changes(summary)
            except Exception as error:
                summary = "Closure diff unavailable: " + str(error)
                packages = []
                self.log(summary + "\n")
            new_pins = json.loads(pins_path.read_text()) if pins_path.is_file() else {}
            with self.mutex:
                changes = copy.deepcopy(self.state["changes"])
                changes["system"] = packages
                sources = revision_changes(before, locked_inputs(destination))
                changes["tools"] = revision_changes({key: value["version"] for key, value in old_pins.items()},
                                                     {key: value["version"] for key, value in new_pins.items()})
                old = self.state["prepared"]
                self.state.update(prepared={"ready": True, "path": path, "candidate": str(destination),
                                           "fingerprint": source, "managed": managed, "gcroot": str(gcroot),
                                           "changeSummary": redact(summary)[-24000:], "packageChanges": packages},
                                  changes=changes, sourceChanges=sources,
                                  available=any(changes.values()) or bool(sources))
                self.save()
            self.discard_candidate(old)
            succeeded = True
        finally:
            if not succeeded:
                shutil.rmtree(destination, ignore_errors=True)
                gcroot.unlink(missing_ok=True)

    def discard_candidate(self, prepared):
        # All persisted paths are constrained before deleting anything.
        for key, parent in (("candidate", "candidates"), ("gcroot", "gcroots")):
            value = prepared.get(key)
            if not value:
                continue
            path = Path(value)
            if path.parent == self.directory / parent and re.fullmatch(r"[a-f0-9]{32}", path.name):
                if key == "candidate":
                    shutil.rmtree(path, ignore_errors=True)
                else:
                    path.unlink(missing_ok=True)

    def activate(self, action):
        prepared = copy.deepcopy(self.state["prepared"])
        if not prepared.get("ready") or not self.valid_closure(prepared.get("path", "")):
            raise RuntimeError("Prepare a system before applying it.")
        if fingerprint(self.root) != prepared.get("fingerprint"):
            self.update(prepared={**prepared, "ready": False})
            raise RuntimeError("Configuration changed since preparation; prepare again before applying.")
        for name in managed_files(self.root):
            if hashlib.sha256((self.root / name).read_bytes()).hexdigest() != prepared["managed"][name]:
                raise RuntimeError("Managed lock or pins changed; prepare again before applying.")
        destination = Path(prepared["candidate"])
        if destination.parent != self.directory / "candidates":
            raise RuntimeError("Prepared snapshot is outside its state directory.")
        originals = {name: (self.root / name).read_bytes() for name in managed_files(self.root)}
        modes = {name: stat.S_IMODE((self.root / name).stat().st_mode) for name in managed_files(self.root)}
        replacements = {name: (destination / name).read_bytes() for name in managed_files(self.root)}
        self.update(stage="Promoting prepared input locks and tool pins")
        try:
            for name, contents in replacements.items():
                atomic_write(self.root / name, contents, modes[name])
            # The candidate's desktop lock points to its isolated public tree.
            # Refresh this local input against the promoted live public tree.
            self.wrapper(self.root, "lock")
        except BaseException:
            for name, contents in originals.items():
                atomic_write(self.root / name, contents, modes[name])
            raise
        # The guard is updated after our own promotion so an activation failure is retryable.
        prepared["fingerprint"] = fingerprint(self.root)
        prepared["managed"] = {name: hashlib.sha256((self.root / name).read_bytes()).hexdigest() for name in managed_files(self.root)}
        self.update(prepared=prepared, stage="Activating prepared system" if action == "apply" else "Preparing next boot")
        self.wrapper(self.root, "switch-built" if action == "apply" else "boot-built", prepared["path"])
        with self.mutex:
            changes = copy.deepcopy(self.state["changes"])
            changes["system"], changes["tools"] = [], []
            self.state.update(prepared={**prepared, "ready": False}, changes=changes,
                              sourceChanges=[], available=any(changes.values()))
            self.save()

    def rollback(self, generation):
        if type(generation) is not int or generation < 1:
            raise ValueError("Rollback requires a positive integer generation.")
        link = Path("/nix/var/nix/profiles") / ("system-" + str(generation) + "-link")
        if not link.is_symlink():
            raise RuntimeError("That system generation does not exist.")
        path = str(link.resolve())
        if not self.valid_closure(path):
            raise RuntimeError("That generation is not an available NixOS closure.")
        self.update(stage="Activating generation " + str(generation))
        self.wrapper(self.root, "switch-built", path)

    def append_history(self, operation_id, action, status, error=None, **fields):
        row = {"id": operation_id, "action": action, "status": status,
               "startedAt": self.state.get("startedAt"), "finishedAt": now(), "error": error, **fields}
        rows = [item for item in self.state["history"] if item["id"] != operation_id]
        self.state["history"] = sorted([row, *rows], key=lambda item: item.get("startedAt") or "", reverse=True)[:50]

    def start(self, action, generation=None):
        if action not in ACTIONS:
            return {"ok": False, "error": "Unknown action."}
        with self.mutex:
            if self.state["busy"]:
                return {"ok": False, "error": "An update operation is already running.", "snapshot": self.snapshot()}
            if self.active_automation():
                return {"ok": False, "error": "An automatic maintenance job is running.", "snapshot": self.snapshot()}
            if action == "retry":
                action = self.state.get("lastAction")
                if action not in ACTIONS - {"retry", "rollback"}:
                    return {"ok": False, "error": "No retryable operation. Select an action."}
            if action == "rollback" and (type(generation) is not int or generation < 1):
                return {"ok": False, "error": "Rollback requires a positive integer generation."}
            operation_id = uuid.uuid4().hex
            statuses = {"check": "checking", "prepare": "preparing", "apply": "applying", "boot": "booting",
                        "flatpak": "updating-flatpak", "rollback": "rolling-back"}
            self.state.update(status=statuses[action], busy=True, stage="Starting", startedAt=now(),
                              error=None, operationId=operation_id, lastAction=action)
            self.save()
            self.worker = threading.Thread(target=self.perform, args=(operation_id, action, generation), daemon=False)
            self.worker.start()
            return {"ok": True, "snapshot": self.snapshot()}

    def perform(self, operation_id, action, generation):
        error = None
        self.log("Started " + action + " at " + self.state["startedAt"] + "\n")
        try:
            if action == "flatpak":
                # This service acquires .maintenance.lock itself. Holding it here deadlocks.
                self.update(stage="Updating system Flatpak applications")
                self.run(["systemctl", "start", "flatpak-auto-update.service"])
                with self.mutex:
                    self.state["changes"]["flatpak"] = []
                    self.state["available"] = any(self.state["changes"].values()) or bool(self.state["sourceChanges"])
                    self.save()
            else:
                with self.maintenance():
                    if action == "check":
                        self.check(operation_id)
                    elif action == "prepare":
                        self.prepare(operation_id)
                    elif action in {"apply", "boot"}:
                        self.activate(action)
                    elif action == "rollback":
                        self.rollback(generation)
        except Exception as failure:
            error = redact(str(failure))[-6000:]
            self.log("\nFailed: " + error + "\n")
        finally:
            with self.mutex:
                self.append_history(operation_id, action, "failed" if error else "success", error)
                self.state.update(status="failed" if error else "idle", busy=False,
                                  stage="Failed" if error else "Complete", error=error, operationId=None)
                self.save()
                self.prune_state_files()
            self.refresh_observed()

    def properties(self, unit, fields):
        output = self.run(["systemctl", "--timestamp=unix", "show", unit, "--property=" + ",".join(fields)],
                          timeout=15, record=False, stdout_only=True)
        properties = dict(line.split("=", 1) for line in output.splitlines() if "=" in line)
        for field, value in properties.items():
            if value.startswith("@"):
                try:
                    properties[field] = datetime.datetime.fromtimestamp(float(value[1:]), datetime.timezone.utc).isoformat(timespec="seconds")
                except ValueError:
                    pass
        return properties

    def automation(self, unit, label):
        fields = ("ActiveState", "SubState", "Result", "ExecMainStatus", "ExecMainCode", "ExecMainStartTimestamp",
                  "ExecMainExitTimestamp", "InvocationID")
        try:
            service = self.properties(unit + ".service", fields)
            timer = self.properties(unit + ".timer", ("NextElapseUSecRealtime",))
            result = service.get("Result", "")
            active = service.get("ActiveState") in {"activating", "active", "deactivating"}
            exit_status = service.get("ExecMainStatus", "")
            # NixOS activation can reset Result/ActiveState while preserving the
            # invocation's actual exit status. That reset did not rerun the job.
            if not active and exit_status.isdigit() and int(exit_status) != 0 and result in {"", "success"}:
                result = "exit-code"
            failed = service.get("ActiveState") == "failed" or result not in {"", "success"}
            error = ("Service failed: " + result + " (exit " + service.get("ExecMainStatus", "?") + ")") if failed else None
            row = {"id": unit, "label": label, "state": service.get("ActiveState", "unknown"),
                   "result": result or None, "lastRun": service.get("ExecMainStartTimestamp") or None,
                   "nextRun": timer.get("NextElapseUSecRealtime") or None, "error": error}
            invocation = service.get("InvocationID")
            if invocation and row["lastRun"]:
                with self.mutex:
                    history_id = "automation:" + unit + ":" + invocation
                    previous = next((item for item in self.state["history"] if item["id"] == history_id), None)
                    if previous and previous["status"] == "failed" and not active:
                        failed = True
                        row["error"] = error = previous["error"] or error or "This invocation failed."
                        if row["result"] in {None, "success"}:
                            row["result"] = "exit-code"
                    if previous is None:
                        self.append_history(history_id, "automatic-" + unit.removesuffix("-auto-update"),
                                            "running" if active else "failed" if failed else "success", error,
                                            startedAt=row["lastRun"], finishedAt=service.get("ExecMainExitTimestamp") or None)
                        self.save()
                    else:
                        # Reconcile the recorded result with definitive exit metadata.
                        status = "running" if active else "failed" if failed else "success"
                        if previous["status"] != status or previous.get("error") != error:
                            previous.update(status=status, error=error,
                                            finishedAt=service.get("ExecMainExitTimestamp") or None)
                            self.save()
            return row
        except Exception as error:
            return {"id": unit, "label": label, "state": "unknown", "result": None,
                    "lastRun": None, "nextRun": None, "error": redact(str(error))[-1000:]}

    @staticmethod
    def generations():
        current = Path("/run/current-system").resolve()
        booted = Path("/run/booted-system").resolve()
        profile = Path("/nix/var/nix/profiles/system").resolve()
        rows = []
        for path in Path("/nix/var/nix/profiles").glob("system-*-link"):
            match = re.fullmatch(r"system-([0-9]+)-link", path.name)
            if match and path.is_symlink():
                target = path.resolve()
                rows.append({"number": int(match[1]), "current": target == current, "booted": target == booted,
                             "profile": target == profile,
                             "date": datetime.datetime.fromtimestamp(path.lstat().st_mtime, datetime.timezone.utc).isoformat(timespec="seconds")})
        return sorted(rows, key=lambda row: row["number"], reverse=True)[:50]

    @staticmethod
    def restart_required():
        # Rebuilding userspace changes the closure too; compare only boot artifacts.
        booted = Path("/run/booted-system")
        profile = Path("/nix/var/nix/profiles/system")
        return any((booted / name).resolve() != (profile / name).resolve()
                   for name in ("kernel", "initrd", "kernel-modules")
                   if (booted / name).exists() or (profile / name).exists())

    @staticmethod
    def pending_boot():
        return Path("/nix/var/nix/profiles/system").resolve() != Path("/run/current-system").resolve()

    def refresh_observed(self):
        automations = [self.automation(unit, label) for unit, label in AUTOMATIONS]
        try:
            generations = self.generations()
            restart = self.restart_required()
        except OSError:
            generations, restart = [], False
        with self.mutex:
            self.observed = {"automations": automations, "generations": generations, "restartRequired": restart,
                             "pendingBoot": self.pending_boot()}
            prepared = self.state["prepared"]
            if prepared.get("ready") and not self.state["busy"]:
                try:
                    changed = fingerprint(self.root) != prepared.get("fingerprint")
                except OSError:
                    changed = True
                if changed:
                    prepared["ready"] = False
                    self.state["error"] = "Configuration changed since preparation; prepare again."
                    self.save()
                    self.prune_state_files()

    def observe(self):
        while not self.observer_stop.wait(15):
            self.refresh_observed()

    def details(self, operation_id):
        if operation_id.startswith("automation:"):
            parts = operation_id.split(":")
            if len(parts) not in {2, 3} or parts[1] not in dict(AUTOMATIONS):
                return {"ok": False, "error": "Unknown automatic job."}
            arguments = ["journalctl", "--no-pager", "--output=short-iso", "--lines=300", "--unit=" + parts[1] + ".service"]
            if len(parts) == 3:
                if not re.fullmatch(r"[a-f0-9]{32}", parts[2]):
                    return {"ok": False, "error": "Invalid journal invocation ID."}
                arguments.append("_SYSTEMD_INVOCATION_ID=" + parts[2])
            try:
                log = self.run(arguments, timeout=15, record=False)
                return {"ok": True, "id": operation_id, "log": redact(log)[-LOG_LIMIT:]}
            except Exception as error:
                return {"ok": False, "error": redact(str(error))}
        try:
            path = self.log_path(operation_id)
            return {"ok": True, "id": operation_id, "log": path.read_text(errors="replace")[-LOG_LIMIT:]}
        except (OSError, ValueError) as error:
            return {"ok": False, "error": str(error)}

    def request(self, request):
        if not isinstance(request, dict):
            return {"ok": False, "error": "Expected a JSON object."}
        command = request.get("command")
        if command == "status":
            return self.snapshot()
        if command == "action":
            return self.start(request.get("action"), request.get("generation"))
        if command == "details" and isinstance(request.get("id"), str):
            return self.details(request["id"])
        return {"ok": False, "error": "Unknown command."}


class RequestHandler(socketserver.StreamRequestHandler):
    def handle(self):
        _pid, uid, _gid = struct.unpack("3i", self.request.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i")))
        if uid != self.server.allowed_uid:
            return
        self.request.settimeout(5)
        try:
            line = self.rfile.readline(MAX_REQUEST + 1)
            if len(line) > MAX_REQUEST:
                response = {"ok": False, "error": "Request too large."}
            else:
                response = self.server.coordinator.request(json.loads(line))
        except Exception as error:
            response = {"ok": False, "error": redact(str(error))[-2000:]}
        with contextlib.suppress(BrokenPipeError, ConnectionResetError):
            self.wfile.write(json.dumps(response, ensure_ascii=False).encode() + b"\n")


class ControlServer(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True

    def __init__(self, path, coordinator, uid):
        self.coordinator, self.allowed_uid = coordinator, uid
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        if path.exists():
            info = path.lstat()
            if not stat.S_ISSOCK(info.st_mode) or info.st_uid != uid:
                raise RuntimeError("Refusing to replace a control socket owned by another user or a non-socket.")
            # Do not steal an active daemon's socket.
            with socket.socket(socket.AF_UNIX) as probe:
                try:
                    probe.connect(str(path))
                except ConnectionRefusedError:
                    path.unlink()
                else:
                    raise RuntimeError("Update coordinator is already running.")
        super().__init__(str(path), RequestHandler)
        os.chmod(path, 0o600)


def client(request, path=SOCKET_PATH):
    try:
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(25)
            connection.connect(path)
            connection.sendall(json.dumps(request).encode() + b"\n")
            with connection.makefile("rb") as stream:
                return json.loads(stream.readline(2 * 1024 * 1024))
    except (OSError, ValueError) as error:
        return {"ok": False, "error": "Update coordinator unavailable: " + str(error)}


def serve(config, path, uid):
    directory = Path(config["stateDirectory"]).expanduser()
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(directory, 0o700)
    # Claim the daemon lifetime before reading or repairing durable worker state.
    # A second serve process must not mark the active daemon's job interrupted.
    with (directory / ".daemon.lock").open("a") as lock:
        os.fchmod(lock.fileno(), 0o600)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Update coordinator is already running.") from None
        coordinator = Coordinator(config)
        with ControlServer(config.get("socketPath", path), coordinator, uid) as server:
            coordinator.refresh_observed()
            observer = threading.Thread(target=coordinator.observe, daemon=True)
            observer.start()
            try:
                server.serve_forever(poll_interval=0.5)
            finally:
                coordinator.observer_stop.set()
                Path(server.server_address).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", default=SOCKET_PATH)
    commands = parser.add_subparsers(dest="command", required=True)
    serve_parser = commands.add_parser("serve")
    serve_parser.add_argument("--config", required=True)
    commands.add_parser("status")
    action = commands.add_parser("action")
    action.add_argument("action", choices=sorted(ACTIONS))
    action.add_argument("--generation", type=int)
    details = commands.add_parser("details")
    details.add_argument("--id", required=True)
    args = parser.parse_args()
    if args.command != "serve":
        request = {"command": args.command}
        if args.command == "action":
            request.update(action=args.action, generation=args.generation)
        elif args.command == "details":
            request["id"] = args.id
        result = client(request, args.socket)
        print(json.dumps(result, ensure_ascii=False))
        return 1 if result.get("ok") is False else 0
    with open(args.config) as stream:
        config = json.load(stream)
    uid = config.get("uid") or os.getuid()
    if os.getuid() != uid or uid == 0:
        raise RuntimeError("Run the coordinator as its configured desktop user, never root.")
    serve(config, args.socket, uid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
