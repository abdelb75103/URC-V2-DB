#!/usr/bin/env python3
"""Local-only decision board for the Benetton and Zebre Step 0 profiles."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from datetime import UTC, datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "intake" / "2024-25"
HTML = Path(__file__).with_name("italian_profile_decision_board.html")
STATE = DATA / "italy" / "decision_selections.json"
STATE_LOCK = Lock()

DECISIONS = [
    {
        "id": "BENETTON-2024-25-ADJ-001-TAXONOMY-CONFLICTS",
        "team": "Benetton",
        "finding": "Seven body-location rows and two tissue/pathology rows contain direct conflicts between the explicit source label and OSIICS code. Automatic code precedence would silently change Ankle, Foot, Arm, Head/Face, or Neck evidence; two Muscle rows also point to different coded pathologies.",
        "question": "How should the 9 Benetton taxonomy-conflict rows be resolved?",
        "choices": [
            {
                "value": "manual_row_evidence_review",
                "label": "Review row evidence",
                "description": "Review retained diagnosis/code/label evidence row by row; keep any unresolved body or pathology value Unknown.",
                "recommended": True,
            },
            {
                "value": "prefer_explicit_source_label",
                "label": "Prefer source label",
                "description": "Use the explicit Body Part or tissue label whenever it conflicts with the OSIICS code, with an audited override.",
                "recommended": False,
            },
            {
                "value": "prefer_osiics_code",
                "label": "Prefer OSIICS code",
                "description": "Use the OSIICS code whenever it conflicts with the explicit source label, preserving the disagreement in audit.",
                "recommended": False,
            },
        ],
    },
    {
        "id": "ZEBRE-2024-25-ADJ-001-PROBLEM-TYPE",
        "team": "Zebre",
        "finding": "Thirty of 133 rows are explicitly labelled Medical. Their problem type, occasion, contact, and recurrence fields are blank, while the generic Orchard-code fallback would currently call every row an injury.",
        "question": "How should the 30 Medical rows be classified for the injury/illness cohort?",
        "choices": [
            {
                "value": "medical_to_illness",
                "label": "Medical → illness",
                "description": "Classify Medical as illness; classify non-Medical rows as injury only when retained injury evidence supports it; otherwise Unknown.",
                "recommended": True,
            },
            {
                "value": "medical_to_unknown",
                "label": "Medical → Unknown",
                "description": "Leave all Medical rows unclassified and keep only evidence-supported non-Medical injury rows.",
                "recommended": False,
            },
            {
                "value": "manual_row_review",
                "label": "Manual row review",
                "description": "Hold the profile at adjudication and review all 30 Medical rows individually before assigning problem type.",
                "recommended": False,
            },
        ],
    }
]

INFERRED = [
    {"id": "ITALY-INFER-001", "decision": "Use locator-tested restoration", "basis": "Prior Stormers restoration approval", "application": "Restore raw dates and omitted source metrics row-for-row; never restore raw identifiers."},
    {"id": "ITALY-INFER-002", "decision": "Keep source duration precedence", "basis": "Prior Bulls, Sharks, and Stormers duration decisions", "application": "Preserve source Days Injured; use calendar difference only when duration is missing and both dates are valid."},
    {"id": "ITALY-INFER-003", "decision": "Use explicit competition or audited fixture link", "basis": "Prior Bulls, Lions, Sharks, and Stormers match-scope decisions", "application": "Do not treat every game as URC."},
    {"id": "ITALY-INFER-004", "decision": "Remove DOB", "basis": "Prior Sharks and Stormers privacy decisions", "application": "Blank Benetton DOB before intake; Zebre DOB is already blank."},
    {"id": "ITALY-INFER-005", "decision": "Include unlabeled exposure as unknown", "basis": "Abdel's South African decision-board note", "application": "Do not exclude exposure merely because match/training labels are blank."},
    {"id": "ITALY-INFER-006", "decision": "Use frozen exposure validity rules", "basis": "Prior Bulls and Lions outlier decisions", "application": "Do not add a team/device threshold; audit rows excluded by the frozen bounds."},
    {"id": "ITALY-INFER-007", "decision": "Audit exact duplicate exclusions", "basis": "Prior Stormers duplicate decision", "application": "Exclude only exact copies with lineage and reason; retain non-identical repeated rows."},
    {"id": "ITALY-INFER-008", "decision": "Accept provisional physical-row locators", "basis": "Prior Sharks and Stormers provenance decisions", "application": "Record missing upstream metadata and bind evidence to workbook checksum, sheet, and physical row."},
    {"id": "ITALY-INFER-009", "decision": "Use row-level IOC evidence", "basis": "Prior Bulls, Lions, Sharks, and Stormers taxonomy decisions", "application": "Map supported OSIICS/code evidence to one frozen IOC bucket; preserve source multi-values and leave unsupported specificity Unknown."},
]


def evidence_fingerprint() -> str:
    """Bind selections to the exact questions and profiling evidence reviewed."""
    artifacts = {}
    for team in ("benetton", "zebre"):
        for name in (
            "mechanical_evidence.v1.json",
            "source_to_canonical_mapping.v2.draft.json",
            "source_adapter_plan.v1.draft.json",
            "team_intake_profile.v2.draft.json",
        ):
            path = DATA / team / name
            artifacts[f"{team}/{name}"] = hashlib.sha256(path.read_bytes()).hexdigest()
    payload = {"decisions": DECISIONS, "artifacts": artifacts}
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def load_state() -> dict:
    current_fingerprint = evidence_fingerprint()
    if not STATE.exists():
        return {"evidence_fingerprint": current_fingerprint, "updated_at": None, "selections": {}, "note": ""}
    state = json.loads(STATE.read_text())
    if state.get("evidence_fingerprint") != current_fingerprint:
        return {
            "evidence_fingerprint": current_fingerprint,
            "updated_at": None,
            "selections": {},
            "note": "",
            "invalidated_previous_state": True,
        }
    valid = {
        item["id"]: {choice["value"] for choice in item["choices"]}
        for item in DECISIONS
    }
    selections = state.get("selections") if isinstance(state.get("selections"), dict) else {}
    state["selections"] = {
        decision_id: selection
        for decision_id, selection in selections.items()
        if decision_id in valid
        and isinstance(selection, dict)
        and selection.get("choice") in valid[decision_id]
    }
    if not isinstance(state.get("note"), str):
        state["note"] = ""
    state["evidence_fingerprint"] = current_fingerprint
    return state


def save_state(state: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    state["updated_at"] = datetime.now(UTC).isoformat()
    fd, name = tempfile.mkstemp(dir=STATE.parent, prefix=".italy-decisions-", suffix=".json")
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
        elif self.path == "/api/state":
            self.send_json({"decisions": DECISIONS, "inferred": INFERRED, **load_state()})
        elif self.path == "/favicon.ico":
            self.send_response(204)
            self.end_headers()
        else:
            self.send_error(404)

    def do_POST(self) -> None:
        if self.path not in {"/api/select", "/api/note"}:
            self.send_error(404)
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(size))
            with STATE_LOCK:
                state = load_state()
                if self.path == "/api/note":
                    note = payload.get("note")
                    if not isinstance(note, str) or len(note) > 5000:
                        raise ValueError("note must be text no longer than 5000 characters")
                    state["note"] = note
                else:
                    decision = next(item for item in DECISIONS if item["id"] == payload["decision_id"])
                    valid = {item["value"] for item in decision["choices"]}
                    choice = payload.get("choice")
                    if choice is not None and choice not in valid:
                        raise ValueError("invalid choice")
                    if choice is None:
                        state["selections"].pop(decision["id"], None)
                    else:
                        state["selections"][decision["id"]] = {
                            "team": decision["team"],
                            "question": decision["question"],
                            "choice": choice,
                            "selected_at": datetime.now(UTC).isoformat(),
                        }
                save_state(state)
            self.send_json({"ok": True, **state})
        except (KeyError, ValueError, StopIteration, json.JSONDecodeError) as exc:
            self.send_json({"ok": False, "error": str(exc)}, 400)

    def log_message(self, format: str, *args) -> None:
        return


def check() -> None:
    ids = [item["id"] for item in DECISIONS + INFERRED]
    assert len(ids) == len(set(ids))
    assert len(DECISIONS) == 2 and all(len(item["choices"]) == 3 for item in DECISIONS)
    assert all(sum(choice["recommended"] for choice in item["choices"]) == 1 for item in DECISIONS)
    for team in ("benetton", "zebre"):
        profile = json.loads((DATA / team / "team_intake_profile.v2.draft.json").read_text())
        expected = set(profile["unresolved_adjudication_ids"])
        actual = {item["id"] for item in DECISIONS if item["team"].casefold() == team}
        assert expected == actual, (team, expected, actual)
    assert len(evidence_fingerprint()) == 64
    loaded = load_state()
    assert loaded["evidence_fingerprint"] == evidence_fingerprint()
    print(f"PASS: {len(DECISIONS)} new decisions and {len(INFERRED)} inferred decisions")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        check()
    else:
        print(f"Italian decision board: http://127.0.0.1:{args.port}")
        ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
