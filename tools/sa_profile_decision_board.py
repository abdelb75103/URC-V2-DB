#!/usr/bin/env python3
"""Local-only decision board for the South African Step 0 profiles."""

from __future__ import annotations

import argparse
import json
import os
import re
import tempfile
from datetime import UTC, datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data/intake/2024-25"
TEAMS = ("bulls", "lions", "sharks", "stormers")
HTML = Path(__file__).with_name("sa_profile_decision_board.html")
STATE = DATA / "south_africa/decision_selections.json"
STATE_LOCK = Lock()


def safe_text(value: str) -> str:
    return value.replace("—", "-").replace("–", "-")


def choices(issue: str) -> list[dict[str, str | bool]]:
    text = issue.casefold()
    # ponytail: keyword routing keeps 39 one-off decisions out of a hand-maintained config.
    routes = (
        (("wrist/hand", "broad tissue", "pathology", "row-level separation", "taxonomy rules"), ("Keep Unknown", "Approve code rule", "Manual review")),
        (("match type", "urc/non-urc", "competition"), ("Keep unknown", "Use audited fixture link", "Manual review")),
        (("duration", "days-injured", "date difference", "calendar", "precedence", "conflicts"), ("Keep source duration", "Use date difference", "Review conflicts")),
        (("issue resolved", "fit-for-selection"), ("Return date only", "Return and fit date", "Manual review")),
        (("closed/open", "fit-status"), ("Keep status Unknown", "Derive from return date", "Manual review")),
        (("ghost row", "fully blank", "template"), ("Exclude with audit reason", "Retain for review", "Defer")),
        (("duplicate", "silently merging"), ("Retain all rows", "Approve exact duplicate exclusion", "Manual review")),
        (("total distance", "restoration"), ("Approve locator-tested adapter", "Leave distance missing", "Manual review")),
        (("timestamp-derived", "exposure minutes", "h:mm:ss"), ("Approve tested conversion", "Leave duration missing", "Manual review")),
        (("outlier", "device/vendor", "threshold"), ("Use frozen rules only", "Add device review", "Defer")),
        (("preparer", "provenance", "source locator", "locators", "audit-boundary metadata"), ("Block until supplied", "Accept provisional locators", "Defer")),
        (("dob", "pseudonym", "identifier"), ("Confirm boundary first", "Remove field in adapter", "Manual review")),
        (("coverage", "begins", "reporting gap"), ("Accept and report gap", "Seek missing data", "Defer")),
        (("contact", "suffix"), ("Approve exact suffix rule", "Keep Unknown", "Manual review")),
        (("problem type", "injury inference"), ("Keep Unknown", "Approve evidence rule", "Manual review")),
        (("season", "january-april", "pre-window"), ("Exclude outside window", "Include in season", "Manual review")),
        (("missing session date", "without session dates"), ("Exclude with audit reason", "Recover dates", "Manual review")),
    )
    labels = next((labels for needles, labels in routes if any(n in text for n in needles)), None)
    labels = labels or ("Use safe default", "Manual review", "Defer")
    return [
        {"value": label.casefold().replace(" ", "_"), "label": label, "recommended": i == 0}
        for i, label in enumerate(labels)
    ]


def load_decisions() -> list[dict]:
    decisions = []
    for team_key in TEAMS:
        profile_path = DATA / team_key / "team_intake_profile.json"
        profile = json.loads(profile_path.read_text())
        items = profile.get("unresolved_adjudications")
        if not items:
            markdown = profile_path.with_suffix(".md").read_text()
            items = [
                {"id": match.group(1), "issue": match.group(2)}
                for match in re.finditer(r"`([^`]+-ADJ-[^`]+)`\s*[-—–]\s*(.+)", markdown)
            ]
        for item in items:
            issue = safe_text(item.get("issue") or item["question"])
            decisions.append(
                {"id": item["id"], "team": profile["team"], "issue": issue, "choices": choices(issue)}
            )
    return decisions


def load_state() -> dict:
    if not STATE.exists():
        return {"updated_at": None, "selections": {}, "note": ""}
    return json.loads(STATE.read_text())


def save_state(state: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    state["updated_at"] = datetime.now(UTC).isoformat()
    fd, name = tempfile.mkstemp(dir=STATE.parent, prefix=".decisions-", suffix=".json")
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(state, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(name, STATE)
    finally:
        if os.path.exists(name):
            os.unlink(name)


class Handler(BaseHTTPRequestHandler):
    def send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path == "/":
            body = HTML.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/favicon.ico":
            self.send_response(204)
            self.end_headers()
        elif self.path == "/api/state":
            self.send_json({"decisions": load_decisions(), **load_state()})
        else:
            self.send_error(404)

    def do_POST(self) -> None:
        if self.path not in ("/api/select", "/api/note"):
            self.send_error(404)
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(size))
            if self.path == "/api/note":
                note = payload.get("note")
                if not isinstance(note, str) or len(note) > 5000:
                    raise ValueError("note must be text no longer than 5000 characters")
                with STATE_LOCK:
                    state = load_state()
                    state["note"] = note
                    save_state(state)
                self.send_json({"ok": True, **state})
                return
            decision = next(item for item in load_decisions() if item["id"] == payload["decision_id"])
            valid = {item["value"] for item in decision["choices"]}
            if payload["choice"] is not None and payload["choice"] not in valid:
                raise ValueError("invalid choice")
            with STATE_LOCK:
                state = load_state()
                if payload["choice"] is None:
                    state["selections"].pop(decision["id"], None)
                else:
                    state["selections"][decision["id"]] = {
                        "team": decision["team"],
                        "issue": decision["issue"],
                        "choice": payload["choice"],
                        "selected_at": datetime.now(UTC).isoformat(),
                    }
                save_state(state)
            self.send_json({"ok": True, **state})
        except (KeyError, ValueError, StopIteration, json.JSONDecodeError) as exc:
            self.send_json({"ok": False, "error": str(exc)}, 400)

    def log_message(self, format: str, *args) -> None:
        return


def check() -> None:
    decisions = load_decisions()
    assert len(decisions) == len({item["id"] for item in decisions})
    assert decisions and all(len(item["choices"]) == 3 for item in decisions)
    print(f"PASS: {len(decisions)} decisions across {len(TEAMS)} teams")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        check()
    else:
        print(f"Decision board: http://127.0.0.1:{args.port}")
        ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
