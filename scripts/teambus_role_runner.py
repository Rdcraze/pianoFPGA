#!/usr/bin/env python3

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import shlex
import signal
import sys
import textwrap
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

try:
    from mcp import ClientSession
    from mcp.client.streamable_http import streamable_http_client
except ImportError as exc:  # pragma: no cover - exercised by direct execution
    print(
        "Missing Python dependency: install the Model Context Protocol client package in the "
        "Python environment that runs this script.",
        file=sys.stderr,
    )
    print(f"Import error: {exc}", file=sys.stderr)
    sys.exit(2)


PLACEHOLDER_RE = re.compile(r"\$\{([A-Z0-9_]+)\}")
ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
RESUME_SESSION_RE = re.compile(r"\bcodex resume ([0-9a-fA-F-]{8,})\b")
DEFAULT_SERVER_URL = "http://127.0.0.1:8000/mcp"
DEFAULT_STATE_DIR = "tmp/runner-state"
DEFAULT_HEARTBEAT_INTERVAL_SECONDS = 45
DEFAULT_WAIT_TIMEOUT_SECONDS = 300
DEFAULT_STALE_AFTER_SECONDS = 180
DEFAULT_FAILURE_BACKOFF_SECONDS = 10
DEFAULT_TOOL_RETRY_ATTEMPTS = 4
DEFAULT_TOOL_RETRY_INITIAL_DELAY_SECONDS = 1.0
DEFAULT_TOOL_RETRY_MAX_DELAY_SECONDS = 8.0
DEFAULT_WAIT_MODE = "level"
DEFAULT_RESUME_PROMPT: Optional[str] = None
DEFAULT_EXEC_RESUME_SESSION_ID: Optional[str] = None
ALLOWED_ROLES = {"orchestrator", "manual-reader", "implementer", "verifier"}
TRANSIENT_TOOL_ERROR_PATTERNS = (
    "unhandled errors in a taskgroup",
    "stream closed",
    "broken resource",
    "closed resource",
    "connection refused",
    "connection reset",
    "server disconnected",
    "remote protocol",
    "connecterror",
    "readerror",
    "writeerror",
    "timeout",
    "timed out",
    "eof",
    "temporarily unavailable",
)


@dataclass
class RunnerState:
    agent_id: Optional[str]
    cursor: int
    wake_count: int
    last_wake: Optional[dict[str, Any]]
    last_codex_exit_code: Optional[int]
    interactive_session_id: Optional[str]
    exec_session_id: Optional[str]

    @classmethod
    def from_path(cls, path: Path) -> "RunnerState":
        if not path.exists():
            return cls(
                agent_id=None,
                cursor=0,
                wake_count=0,
                last_wake=None,
                last_codex_exit_code=None,
                interactive_session_id=None,
                exec_session_id=None,
            )
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return cls(
                agent_id=None,
                cursor=0,
                wake_count=0,
                last_wake=None,
                last_codex_exit_code=None,
                interactive_session_id=None,
                exec_session_id=None,
            )
        return cls(
            agent_id=payload.get("agent_id"),
            cursor=int(payload.get("cursor", 0) or 0),
            wake_count=int(payload.get("wake_count", 0) or 0),
            last_wake=payload.get("last_wake"),
            last_codex_exit_code=payload.get("last_codex_exit_code"),
            interactive_session_id=payload.get("interactive_session_id"),
            exec_session_id=payload.get("exec_session_id"),
        )

    def save(self, path: Path) -> None:
        payload = {
            "agent_id": self.agent_id,
            "cursor": self.cursor,
            "wake_count": self.wake_count,
            "last_wake": self.last_wake,
            "last_codex_exit_code": self.last_codex_exit_code,
            "interactive_session_id": self.interactive_session_id,
            "exec_session_id": self.exec_session_id,
            "updated_at": now_iso(),
        }
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    merged = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def expand_placeholders(value: Any, env: dict[str, str]) -> Any:
    if isinstance(value, dict):
        return {key: expand_placeholders(item, env) for key, item in value.items()}
    if isinstance(value, list):
        return [expand_placeholders(item, env) for item in value]
    if not isinstance(value, str):
        return value

    def replace(match: re.Match[str]) -> str:
        name = match.group(1)
        if name not in env:
            raise KeyError(name)
        return env[name]

    return PLACEHOLDER_RE.sub(replace, value)


def load_runner_config(config_path: Path, role: str, repo_root: Path) -> dict[str, Any]:
    raw = json.loads(config_path.read_text(encoding="utf-8"))
    if role not in raw.get("roles", {}):
        raise ValueError(f"role {role!r} not configured in {config_path}")

    env = dict(os.environ)
    env.setdefault("REPO_ROOT", str(repo_root))
    env.setdefault("TEAMBUS_URL", raw.get("server_url", DEFAULT_SERVER_URL))

    top_level = {
        "server_url": raw.get("server_url", DEFAULT_SERVER_URL),
        "state_dir": raw.get("state_dir", DEFAULT_STATE_DIR),
        "heartbeat_interval_seconds": raw.get(
            "heartbeat_interval_seconds", DEFAULT_HEARTBEAT_INTERVAL_SECONDS
        ),
        "wait_timeout_seconds": raw.get("wait_timeout_seconds", DEFAULT_WAIT_TIMEOUT_SECONDS),
        "stale_after_seconds": raw.get("stale_after_seconds", DEFAULT_STALE_AFTER_SECONDS),
        "wait_mode": raw.get("wait_mode", DEFAULT_WAIT_MODE),
        "resume_prompt": raw.get("resume_prompt", raw.get("interactive_resume_prompt", DEFAULT_RESUME_PROMPT)),
        "exec_resume_session_id": raw.get(
            "exec_resume_session_id", DEFAULT_EXEC_RESUME_SESSION_ID
        ),
        "tool_retry_attempts": raw.get("tool_retry_attempts", DEFAULT_TOOL_RETRY_ATTEMPTS),
        "tool_retry_initial_delay_seconds": raw.get(
            "tool_retry_initial_delay_seconds", DEFAULT_TOOL_RETRY_INITIAL_DELAY_SECONDS
        ),
        "tool_retry_max_delay_seconds": raw.get(
            "tool_retry_max_delay_seconds", DEFAULT_TOOL_RETRY_MAX_DELAY_SECONDS
        ),
        "failure_backoff_seconds": raw.get(
            "failure_backoff_seconds", DEFAULT_FAILURE_BACKOFF_SECONDS
        ),
        "replace_existing": raw.get("replace_existing", True),
        "codex": raw.get("codex", {}),
    }
    role_block = raw["roles"][role]
    merged = deep_merge(top_level, role_block)
    try:
        expanded = expand_placeholders(merged, env)
    except KeyError as exc:
        raise ValueError(
            f"missing environment variable {exc.args[0]!r} required by {config_path}"
        ) from exc

    codex = expanded.get("codex", {})
    codex.setdefault("bin", "codex")
    codex.setdefault("cd", str(repo_root))
    codex.setdefault("sandbox", "workspace-write")
    codex.setdefault("approval", "never")
    codex.setdefault("add_dirs", [])
    codex.setdefault("config_overrides", [])
    codex.setdefault("extra_args", [])
    expanded["codex"] = codex
    expanded["role"] = role
    wait_mode = str(expanded.get("wait_mode", DEFAULT_WAIT_MODE))
    if wait_mode not in {"level", "edge_only"}:
        raise ValueError(f"invalid wait_mode {wait_mode!r}; expected 'level' or 'edge_only'")
    expanded["wait_mode"] = wait_mode
    expanded["tool_retry_attempts"] = max(1, int(expanded.get("tool_retry_attempts", 1)))
    expanded["tool_retry_initial_delay_seconds"] = max(
        0.0, float(expanded.get("tool_retry_initial_delay_seconds", 0.0))
    )
    expanded["tool_retry_max_delay_seconds"] = max(
        expanded["tool_retry_initial_delay_seconds"],
        float(expanded.get("tool_retry_max_delay_seconds", expanded["tool_retry_initial_delay_seconds"])),
    )
    if expanded.get("resume_prompt") is None and expanded.get("interactive_resume_prompt") is not None:
        expanded["resume_prompt"] = expanded.get("interactive_resume_prompt")
    return expanded


def parse_tool_json(result: Any) -> dict[str, Any]:
    texts: list[str] = []
    for item in getattr(result, "content", []) or []:
        text = getattr(item, "text", None)
        if text:
            texts.append(text)
    if not texts:
        raise RuntimeError(f"unexpected teambus tool response: {result!r}")
    if len(texts) != 1:
        raise RuntimeError(f"expected a single teambus payload, got {len(texts)}")
    return json.loads(texts[0])


def find_latest_interactive_session_id(cwd: str, newer_than: Optional[float] = None) -> Optional[str]:
    sessions_root = Path.home() / ".codex" / "sessions"
    if not sessions_root.exists():
        return None
    target_cwd = str(Path(cwd).resolve())
    latest: Optional[tuple[float, str]] = None
    for path in sessions_root.rglob("*.jsonl"):
        try:
            stat = path.stat()
        except OSError:
            continue
        if newer_than is not None and stat.st_mtime < newer_than:
            continue
        try:
            with path.open(encoding="utf-8") as handle:
                first_line = handle.readline()
        except OSError:
            continue
        try:
            entry = json.loads(first_line)
        except json.JSONDecodeError:
            continue
        if entry.get("type") != "session_meta":
            continue
        payload = entry.get("payload") or {}
        if payload.get("originator") != "codex-tui":
            continue
        session_id = payload.get("id")
        session_cwd = payload.get("cwd")
        if not session_id or not session_cwd:
            continue
        try:
            normalized_session_cwd = str(Path(session_cwd).resolve())
        except OSError:
            normalized_session_cwd = session_cwd
        if normalized_session_cwd != target_cwd:
            continue
        candidate = (stat.st_mtime, session_id)
        if latest is None or candidate > latest:
            latest = candidate
    return latest[1] if latest else None


def find_latest_saved_session_id(cwd: str, newer_than: Optional[float] = None) -> Optional[str]:
    sessions_root = Path.home() / ".codex" / "sessions"
    if not sessions_root.exists():
        return None
    target_cwd = str(Path(cwd).resolve())
    latest: Optional[tuple[float, str]] = None
    for path in sessions_root.rglob("*.jsonl"):
        try:
            stat = path.stat()
        except OSError:
            continue
        if newer_than is not None and stat.st_mtime < newer_than:
            continue
        try:
            with path.open(encoding="utf-8") as handle:
                first_line = handle.readline()
        except OSError:
            continue
        try:
            entry = json.loads(first_line)
        except json.JSONDecodeError:
            continue
        if entry.get("type") != "session_meta":
            continue
        payload = entry.get("payload") or {}
        session_id = payload.get("id")
        session_cwd = payload.get("cwd")
        if not session_id or not session_cwd:
            continue
        try:
            normalized_session_cwd = str(Path(session_cwd).resolve())
        except OSError:
            normalized_session_cwd = session_cwd
        if normalized_session_cwd != target_cwd:
            continue
        candidate = (stat.st_mtime, session_id)
        if latest is None or candidate > latest:
            latest = candidate
    return latest[1] if latest else None


def interactive_session_exists(session_id: str, cwd: Optional[str] = None) -> bool:
    sessions_root = Path.home() / ".codex" / "sessions"
    if not sessions_root.exists():
        return False
    normalized_cwd: Optional[str] = None
    if cwd is not None:
        normalized_cwd = str(Path(cwd).resolve())
    for path in sessions_root.rglob("*.jsonl"):
        try:
            with path.open(encoding="utf-8") as handle:
                first_line = handle.readline()
        except OSError:
            continue
        try:
            entry = json.loads(first_line)
        except json.JSONDecodeError:
            continue
        if entry.get("type") != "session_meta":
            continue
        payload = entry.get("payload") or {}
        if payload.get("originator") != "codex-tui":
            continue
        if payload.get("id") != session_id:
            continue
        session_cwd = payload.get("cwd")
        if normalized_cwd is None:
            return True
        if not session_cwd:
            continue
        try:
            normalized_session_cwd = str(Path(session_cwd).resolve())
        except OSError:
            normalized_session_cwd = session_cwd
        if normalized_session_cwd == normalized_cwd:
            return True
    return False


def saved_session_exists(session_id: str, cwd: Optional[str] = None) -> bool:
    sessions_root = Path.home() / ".codex" / "sessions"
    if not sessions_root.exists():
        return False
    normalized_cwd: Optional[str] = None
    if cwd is not None:
        normalized_cwd = str(Path(cwd).resolve())
    for path in sessions_root.rglob("*.jsonl"):
        try:
            with path.open(encoding="utf-8") as handle:
                first_line = handle.readline()
        except OSError:
            continue
        try:
            entry = json.loads(first_line)
        except json.JSONDecodeError:
            continue
        if entry.get("type") != "session_meta":
            continue
        payload = entry.get("payload") or {}
        if payload.get("id") != session_id:
            continue
        if normalized_cwd is None:
            return True
        session_cwd = payload.get("cwd")
        if not session_cwd:
            continue
        try:
            normalized_session_cwd = str(Path(session_cwd).resolve())
        except OSError:
            normalized_session_cwd = session_cwd
        if normalized_session_cwd == normalized_cwd:
            return True
    return False


def extract_interactive_session_id_from_text(text: str) -> Optional[str]:
    normalized = text.replace("\r", "\n")
    stripped = ANSI_ESCAPE_RE.sub("", normalized)
    match = RESUME_SESSION_RE.search(stripped)
    if not match:
        return None
    return match.group(1)


def extract_interactive_session_id_from_log(path: Path) -> Optional[str]:
    if not path.exists():
        return None
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return None
    return extract_interactive_session_id_from_text(text)


def summarize_exception(exc: BaseException) -> str:
    messages: list[str] = []
    stack: list[BaseException] = [exc]
    seen: set[int] = set()
    while stack:
        current = stack.pop()
        ident = id(current)
        if ident in seen:
            continue
        seen.add(ident)
        text = str(current).strip()
        if text:
            messages.append(text)
        nested = getattr(current, "exceptions", None)
        if nested:
            stack.extend(item for item in nested if isinstance(item, BaseException))
        cause = getattr(current, "__cause__", None)
        if isinstance(cause, BaseException):
            stack.append(cause)
        context = getattr(current, "__context__", None)
        if isinstance(context, BaseException):
            stack.append(context)
    return " | ".join(messages) or exc.__class__.__name__


def is_retryable_tool_exception(exc: BaseException) -> bool:
    if isinstance(exc, (asyncio.CancelledError, KeyboardInterrupt, SystemExit)):
        return False
    if isinstance(exc, (TimeoutError, ConnectionError, OSError)):
        return True
    text = summarize_exception(exc).lower()
    return any(pattern in text for pattern in TRANSIENT_TOOL_ERROR_PATTERNS)


async def call_teambus_tool(
    server_url: str,
    tool_name: str,
    arguments: dict[str, Any],
    *,
    max_attempts: int = 1,
    initial_delay_seconds: float = 0.0,
    max_delay_seconds: float = 0.0,
) -> dict[str, Any]:
    attempt = 1
    delay = max(0.0, initial_delay_seconds)
    max_delay = max(delay, max_delay_seconds)
    while True:
        try:
            async with streamable_http_client(server_url) as (read_stream, write_stream, _):
                async with ClientSession(read_stream, write_stream) as session:
                    await session.initialize()
                    result = await session.call_tool(tool_name, arguments)
                    return parse_tool_json(result)
        except BaseException as exc:
            if not is_retryable_tool_exception(exc) or attempt >= max_attempts:
                raise
            summary = summarize_exception(exc)
            print(
                f"[teambus:{tool_name}] transient failure on attempt {attempt}/{max_attempts}: "
                f"{summary}; retrying in {delay:.1f}s",
                file=sys.stderr,
                flush=True,
            )
            await asyncio.sleep(delay)
            attempt += 1
            delay = min(max_delay, delay * 2 if delay > 0 else 1.0)


class RoleRunner:
    def __init__(self, config: dict[str, Any], args: argparse.Namespace) -> None:
        self.config = config
        self.args = args
        self.role = config["role"]
        self.server_url = config["server_url"]
        self.worktree = str(config["worktree"])
        self.agent_name = config["name"]
        self.replace_existing = bool(config.get("replace_existing", True))
        self.heartbeat_interval = int(config["heartbeat_interval_seconds"])
        self.wait_timeout = int(config["wait_timeout_seconds"])
        self.stale_after = int(config["stale_after_seconds"])
        self.wait_mode = str(config["wait_mode"])
        self.resume_prompt = config.get("resume_prompt")
        self.exec_resume_session_id = config.get("exec_resume_session_id")
        self.tool_retry_attempts = int(config["tool_retry_attempts"])
        self.tool_retry_initial_delay_seconds = float(config["tool_retry_initial_delay_seconds"])
        self.tool_retry_max_delay_seconds = float(config["tool_retry_max_delay_seconds"])
        self.failure_backoff = int(config["failure_backoff_seconds"])
        self.codex_config = config["codex"]
        self.state_dir = Path(config["state_dir"])
        self.state_path = self.state_dir / f"{self.role}.json"
        self.prompt_path = self.state_dir / f"{self.role}-last-prompt.txt"
        self.last_message_path = self.state_dir / f"{self.role}-last-message.txt"
        self.last_wake_path = self.state_dir / f"{self.role}-last-wake.json"
        self.interactive_log_path = self.state_dir / f"{self.role}-interactive.log"
        self.state = RunnerState.from_path(self.state_path)
        self.stop_event = asyncio.Event()
        self.startup_prompt: Optional[str] = None
        self._heartbeat_task: Optional[asyncio.Task[None]] = None
        self._heartbeat_status = "idle"
        self._heartbeat_note = "runner starting"

    async def call_teambus_tool(self, tool_name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        return await call_teambus_tool(
            self.server_url,
            tool_name,
            arguments,
            max_attempts=self.tool_retry_attempts,
            initial_delay_seconds=self.tool_retry_initial_delay_seconds,
            max_delay_seconds=self.tool_retry_max_delay_seconds,
        )

    async def register(self) -> None:
        payload = await self.call_teambus_tool(
            "register_agent",
            {
                "name": self.agent_name,
                "role": self.role,
                "worktree": self.worktree,
                "replace_existing": self.replace_existing and not self.args.no_replace_existing,
            },
        )
        if not payload.get("ok"):
            raise RuntimeError(f"register_agent failed: {payload}")
        agent = payload["agent"]
        self.state.agent_id = agent["agent_id"]
        self.startup_prompt = payload.get("startup_prompt", "")
        self.state.save(self.state_path)

    async def heartbeat_loop(self) -> None:
        while not self.stop_event.is_set():
            try:
                await self.send_heartbeat(self._heartbeat_status, self._heartbeat_note)
            except Exception as exc:  # pragma: no cover - operational resilience
                print(f"[{self.role}] heartbeat failed: {exc}", file=sys.stderr)
            try:
                await asyncio.wait_for(self.stop_event.wait(), timeout=self.heartbeat_interval)
            except asyncio.TimeoutError:
                continue

    async def send_heartbeat(self, status: str, note: str) -> None:
        if not self.state.agent_id:
            return
        payload = await self.call_teambus_tool(
            "heartbeat",
            {"agent_id": self.state.agent_id, "status": status, "note": note},
        )
        if not payload.get("ok"):
            raise RuntimeError(f"heartbeat failed: {payload}")

    async def wait_for_work(self) -> dict[str, Any]:
        if not self.state.agent_id:
            raise RuntimeError("agent_id missing before wait_for_work")
        return await self.call_teambus_tool(
            "wait_for_work",
            {
                "agent_id": self.state.agent_id,
                "timeout_seconds": self.wait_timeout,
                "stale_after_seconds": self.stale_after,
                "after_cursor": self.state.cursor,
                "mode": self.wait_mode,
            },
        )

    def set_status(self, status: str, note: str) -> None:
        self._heartbeat_status = status
        self._heartbeat_note = note[:240]

    def build_codex_prompt(self, wake: dict[str, Any]) -> str:
        startup_prompt = (self.startup_prompt or "").strip()
        wake_json = json.dumps(wake, indent=2, sort_keys=True)
        guidance = textwrap.dedent(
            f"""
            RUNNER CONTEXT

            You are a Codex agent being invoked by an external teambus role-runner.

            Registered role:
            - role: {self.role}
            - agent_id: {self.state.agent_id}
            - worktree: {self.worktree}
            - server_url: {self.server_url}

            External runner responsibilities:
            - heartbeats are sent by the runner
            - wait_for_work is handled by the runner
            - the runner is using wait_for_work mode: {self.wait_mode}
            - you should not call register_agent
            - you should not idle in a polling loop at the end of the turn

            Your job for this wake:
            - use teambus tools directly as the registered role
            - react to the wake reasons first
            - read only the specific teambus state needed for this wake
            - if a task is claimable, claim and work it
            - if unread messages are present, read and acknowledge/respond as needed
            - update teambus task status, messages, and artifacts before finishing
            - stop after handling the current wake; the external runner will wait for more work

            STARTUP PROMPT
            {startup_prompt}

            WAKE EVENT
            {wake_json}
            """
        ).strip()
        return guidance + "\n"

    def build_resume_prompt(self, wake: dict[str, Any]) -> Optional[str]:
        template = self.resume_prompt
        if not template:
            return None
        try:
            wake_path = self.last_wake_path.relative_to(Path(self.codex_config["cd"]))
        except ValueError:
            wake_path = self.last_wake_path
        reasons = ", ".join(wake.get("reasons", [])) or "unknown"
        rendered = str(template).format(
            role=self.role,
            agent_id=self.state.agent_id or "",
            wake_path=str(wake_path),
            wake_reasons=reasons,
            worktree=self.worktree,
            server_url=self.server_url,
        ).strip()
        if not rendered:
            return None
        return rendered + "\n"

    def resolve_exec_resume_session_id(self) -> Optional[str]:
        candidates: list[tuple[str, str]] = []
        if self.exec_resume_session_id:
            candidates.append(("configured", self.exec_resume_session_id))
        if self.state.exec_session_id and self.state.exec_session_id != self.exec_resume_session_id:
            candidates.append(("tracked non-interactive", self.state.exec_session_id))
        if self.state.interactive_session_id and self.state.interactive_session_id != self.exec_resume_session_id:
            candidates.append(("tracked interactive", self.state.interactive_session_id))
        for source, session_id in candidates:
            if saved_session_exists(session_id, cwd=self.codex_config["cd"]):
                return session_id
            print(
                f"[{self.role}] {source} session {session_id} is not present in the local saved-session store",
                file=sys.stderr,
                flush=True,
            )
        return None

    def save_wake(self, wake: dict[str, Any]) -> None:
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.last_wake_path.write_text(json.dumps(wake, indent=2, sort_keys=True), encoding="utf-8")

    def capture_interactive_session_id(self, started_at: float) -> None:
        session_id = find_latest_interactive_session_id(self.codex_config["cd"], newer_than=started_at)
        if not session_id:
            return
        self.persist_interactive_session_id(session_id)

    def persist_interactive_session_id(self, session_id: str) -> None:
        if session_id != self.state.interactive_session_id:
            print(f"[{self.role}] tracking interactive session {session_id}", flush=True)
        self.state.interactive_session_id = session_id
        self.state.save(self.state_path)

    def clear_interactive_session_id(self) -> None:
        if self.state.interactive_session_id:
            print(
                f"[{self.role}] clearing invalid interactive session {self.state.interactive_session_id}",
                flush=True,
            )
        self.state.interactive_session_id = None
        self.state.save(self.state_path)

    def capture_exec_session_id(self, started_at: float) -> None:
        session_id = find_latest_saved_session_id(self.codex_config["cd"], newer_than=started_at)
        if not session_id:
            return
        self.persist_exec_session_id(session_id)

    def persist_exec_session_id(self, session_id: str) -> None:
        if session_id != self.state.exec_session_id:
            print(f"[{self.role}] tracking non-interactive session {session_id}", flush=True)
        self.state.exec_session_id = session_id
        self.state.save(self.state_path)

    def build_codex_base_cmd(self) -> list[str]:
        cmd = [
            self.codex_config["bin"],
            "-a",
            self.codex_config["approval"],
            "-C",
            self.codex_config["cd"],
            "-s",
            self.codex_config["sandbox"],
        ]
        model = self.codex_config.get("model")
        if model:
            cmd += ["-m", model]
        for add_dir in self.codex_config.get("add_dirs", []):
            cmd += ["--add-dir", add_dir]
        for override in self.codex_config.get("config_overrides", []):
            cmd += ["-c", override]
        cmd += self.codex_config.get("extra_args", [])
        return cmd

    async def run_codex_once(self, wake: dict[str, Any]) -> int:
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.save_wake(wake)

        if self.args.interactive:
            launch_started_at = time.time()
            cmd = self.build_codex_base_cmd()
            use_transcript_wrapper = False
            if self.args.resume_session and self.state.interactive_session_id:
                if not interactive_session_exists(
                    self.state.interactive_session_id, cwd=self.codex_config["cd"]
                ):
                    print(
                        f"[{self.role}] saved session {self.state.interactive_session_id} no longer exists; "
                        f"falling back to promptless bootstrap",
                        file=sys.stderr,
                        flush=True,
                    )
                    self.clear_interactive_session_id()
                    use_transcript_wrapper = True
                else:
                    resume_prompt = self.build_resume_prompt(wake)
                    if resume_prompt:
                        self.prompt_path.write_text(resume_prompt, encoding="utf-8")
                        cmd += ["resume", self.state.interactive_session_id, resume_prompt]
                        print(
                            f"[{self.role}] resuming interactive Codex session "
                            f"{self.state.interactive_session_id} with a wake prompt",
                            flush=True,
                        )
                    else:
                        cmd += ["resume", self.state.interactive_session_id]
                        print(
                            f"[{self.role}] resuming interactive Codex session "
                            f"{self.state.interactive_session_id} without a prompt",
                            flush=True,
                        )
                    print(f"[{self.role}] wake payload saved to {self.last_wake_path}", flush=True)
            if self.args.resume_session and not self.state.interactive_session_id:
                use_transcript_wrapper = True
                print(
                    f"[{self.role}] no tracked saved interactive session; launching promptless Codex and "
                    f"capturing its session id for future resumes",
                    flush=True,
                )
                print(f"[{self.role}] wake payload saved to {self.last_wake_path}", flush=True)
            elif not self.args.resume_session:
                prompt = self.build_codex_prompt(wake)
                self.prompt_path.write_text(prompt, encoding="utf-8")
                cmd += [prompt]
                print(f"[{self.role}] launching interactive Codex", flush=True)
            if use_transcript_wrapper:
                self.interactive_log_path.unlink(missing_ok=True)
                wrapped_cmd = [
                    "script",
                    "-q",
                    "-e",
                    "-f",
                    "-c",
                    shlex.join(cmd),
                    str(self.interactive_log_path),
                ]
                print(
                    f"[{self.role}] capturing interactive transcript in {self.interactive_log_path}",
                    flush=True,
                )
                process = await asyncio.create_subprocess_exec(
                    *wrapped_cmd,
                    cwd=self.codex_config["cd"],
                )
            else:
                process = await asyncio.create_subprocess_exec(
                    *cmd,
                    cwd=self.codex_config["cd"],
                )
            await process.wait()
            if self.args.resume_session and not self.state.interactive_session_id:
                session_id = extract_interactive_session_id_from_log(self.interactive_log_path)
                if session_id and interactive_session_exists(session_id, cwd=self.codex_config["cd"]):
                    self.persist_interactive_session_id(session_id)
                else:
                    fallback_session_id = find_latest_interactive_session_id(
                        self.codex_config["cd"], newer_than=launch_started_at
                    )
                    if fallback_session_id:
                        self.persist_interactive_session_id(fallback_session_id)
                if not self.state.interactive_session_id:
                    print(
                        f"[{self.role}] warning: Codex did not save a resumable interactive session. "
                        f"On the first promptless bootstrap, send at least one message before exiting. "
                        f"Transcript: {self.interactive_log_path}",
                        file=sys.stderr,
                        flush=True,
                    )
            elif not self.args.resume_session:
                self.capture_interactive_session_id(launch_started_at)
            return int(process.returncode or 0)

        launch_started_at = time.time()
        cmd = self.build_codex_base_cmd()
        resume_session_id = self.resolve_exec_resume_session_id()
        if resume_session_id:
            prompt = self.build_resume_prompt(wake) or self.build_codex_prompt(wake)
            self.prompt_path.write_text(prompt, encoding="utf-8")
            cmd += ["exec", "resume", "-o", str(self.last_message_path), resume_session_id, "-"]
            print(
                f"[{self.role}] resuming non-interactive Codex session {resume_session_id}",
                flush=True,
            )
            print(f"[{self.role}] wake payload saved to {self.last_wake_path}", flush=True)
        else:
            prompt = self.build_codex_prompt(wake)
            self.prompt_path.write_text(prompt, encoding="utf-8")
            cmd += ["exec", "-o", str(self.last_message_path), "-"]

        print(f"[{self.role}] launching: {shlex.join(cmd)}", flush=True)
        process = await asyncio.create_subprocess_exec(
            *cmd,
            cwd=self.codex_config["cd"],
            stdin=asyncio.subprocess.PIPE,
        )
        _, _ = await process.communicate(prompt.encode("utf-8"))
        if not resume_session_id:
            self.capture_exec_session_id(launch_started_at)
        return int(process.returncode or 0)

    async def run(self) -> int:
        await self.register()
        self.set_status("idle", "runner online")
        await self.send_heartbeat(self._heartbeat_status, self._heartbeat_note)
        self._heartbeat_task = asyncio.create_task(self.heartbeat_loop())
        try:
            return await self.run_loop()
        finally:
            self.stop_event.set()
            if self._heartbeat_task:
                await asyncio.gather(self._heartbeat_task, return_exceptions=True)
            if self.state.agent_id:
                try:
                    await self.send_heartbeat("idle", "runner stopping")
                except Exception:
                    pass

    async def run_loop(self) -> int:
        while not self.stop_event.is_set():
            self.set_status("idle", f"waiting at cursor {self.state.cursor}")
            wake = await self.wait_for_work()
            cursor = int(wake.get("cursor", self.state.cursor) or self.state.cursor)
            self.state.cursor = cursor
            self.state.last_wake = wake
            self.state.save(self.state_path)
            self.save_wake(wake)

            if not wake.get("ok"):
                print(f"[{self.role}] wait_for_work failed: {wake}", file=sys.stderr)
                await asyncio.sleep(self.failure_backoff)
                if self.args.once:
                    return 1
                continue
            if not wake.get("woke"):
                if self.args.once:
                    print(f"[{self.role}] timed out without work", flush=True)
                    return 0
                continue

            self.state.wake_count += 1
            self.state.save(self.state_path)
            reasons = ",".join(wake.get("reasons", [])) or "unknown"
            print(f"[{self.role}] wake #{self.state.wake_count}: {reasons}", flush=True)

            if self.args.dry_run:
                print(json.dumps(wake, indent=2, sort_keys=True), flush=True)
                if self.args.once:
                    return 0
                continue

            self.set_status("working", f"processing wake #{self.state.wake_count}: {reasons}")
            exit_code = await self.run_codex_once(wake)
            self.state.last_codex_exit_code = exit_code
            self.state.save(self.state_path)
            self.set_status("idle", f"last codex exit code {exit_code}")
            if exit_code != 0:
                print(f"[{self.role}] codex exited with {exit_code}", file=sys.stderr)
                if self.args.once:
                    return exit_code
                await asyncio.sleep(self.failure_backoff)
            elif self.args.once:
                return 0
        return 0


def install_signal_handlers(stop_event: asyncio.Event) -> None:
    loop = asyncio.get_running_loop()

    def handle_signal() -> None:
        stop_event.set()

    for signame in ("SIGINT", "SIGTERM"):
        if hasattr(signal, signame):
            try:
                loop.add_signal_handler(getattr(signal, signame), handle_signal)
            except NotImplementedError:
                signal.signal(getattr(signal, signame), lambda *_: handle_signal())


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Persistent teambus role-runner for Codex agents")
    parser.add_argument("role", choices=sorted(ALLOWED_ROLES))
    parser.add_argument(
        "--config",
        default="runner/roles.json",
        help="Path to the JSON runner configuration file",
    )
    parser.add_argument("--server-url", help="Override the teambus MCP server URL")
    parser.add_argument("--once", action="store_true", help="Handle at most one wake cycle")
    parser.add_argument("--dry-run", action="store_true", help="Do not launch Codex; print wake payloads")
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Launch the interactive Codex TUI for each wake instead of codex exec",
    )
    parser.add_argument(
        "--resume-session",
        action="store_true",
        help="Interactive only: resume the last runner-tracked Codex TUI session without sending a prompt",
    )
    parser.add_argument(
        "--no-replace-existing",
        action="store_true",
        help="Fail instead of replacing an existing role binding",
    )
    parser.add_argument(
        "--validate-config",
        action="store_true",
        help="Print the effective role configuration and exit",
    )
    return parser


async def async_main(args: argparse.Namespace) -> int:
    repo_root = Path(__file__).resolve().parents[1]
    config_path = Path(args.config)
    if not config_path.is_absolute():
        config_path = (repo_root / config_path).resolve()
    config = load_runner_config(config_path, args.role, repo_root)
    if args.server_url:
        config["server_url"] = args.server_url
    if args.resume_session and not args.interactive:
        raise ValueError("--resume-session requires --interactive")

    if args.validate_config:
        print(json.dumps(config, indent=2, sort_keys=True))
        return 0

    runner = RoleRunner(config, args)
    install_signal_handlers(runner.stop_event)
    return await runner.run()


def main() -> int:
    parser = build_arg_parser()
    args = parser.parse_args()
    try:
        return asyncio.run(async_main(args))
    except KeyboardInterrupt:
        return 130
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
