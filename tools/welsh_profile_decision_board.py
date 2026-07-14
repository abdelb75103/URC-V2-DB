#!/usr/bin/env python3
"""Local-only decision board for the four Welsh Step 0 profiles."""

from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import os
import tempfile
from datetime import UTC, datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock, Thread
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "intake" / "2024-25"
TEAMS = ("cardiff", "dragons", "ospreys", "scarlets")
HTML = Path(__file__).with_name("welsh_profile_decision_board.html")
STATE = DATA / "wales" / "decision_selections.json"
STATE_LOCK = Lock()
MAX_REQUEST_BYTES = 16_384

ARTIFACT_NAMES = (
    "mechanical_evidence.v1.json",
    "source_to_canonical_mapping.v2.draft.json",
    "source_adapter_plan.v1.draft.json",
    "team_intake_profile.v2.draft.json",
)

# EDITABLE DECISION REGISTER
# The compiler profiles may be rewritten while this board is being prepared.
# Keep genuinely new Welsh scientific questions here and make the completed
# profile envelopes match these IDs exactly.
DECISIONS = [
    {
        "id": "DRAGONS-2024-25-ADJ-002-PROBLEM-TYPE",
        "team": "Dragons",
        "finding": "Body Part explicitly labels 46 rows as Medical_illness. This is direct cohort evidence, but the mapping has not previously been approved for Welsh intake data.",
        "question": "How should the 46 Dragons rows labelled Medical_illness be classified for problem type?",
        "choices": [
            {
                "value": "medical_illness_to_illness",
                "label": "Classify as illness",
                "description": "Classify the explicit Medical_illness label as illness. Classify other rows as injury only where retained injury evidence supports it; otherwise use Unknown.",
                "recommended": True,
            },
            {
                "value": "medical_illness_to_unknown",
                "label": "Keep problem type Unknown",
                "description": "Leave problem type Unknown for all 46 Medical_illness rows, preserving the explicit source label for audit.",
                "recommended": False,
            },
            {
                "value": "manual_row_review",
                "label": "Review every row",
                "description": "Hold the mapping and review all 46 rows individually before assigning problem type.",
                "recommended": False,
            },
        ],
    },
    {
        "id": "OSPREYS-2024-25-ADJ-001-PROBLEM-TYPE",
        "team": "Ospreys",
        "finding": "Body Part explicitly labels 34 rows as Medical_illness. This is direct cohort evidence, but the mapping has not previously been approved for Welsh intake data.",
        "question": "How should the 34 Ospreys rows labelled Medical_illness be classified for problem type?",
        "choices": [
            {
                "value": "medical_illness_to_illness",
                "label": "Classify as illness",
                "description": "Classify the explicit Medical_illness label as illness. Classify other rows as injury only where retained injury evidence supports it; otherwise use Unknown.",
                "recommended": True,
            },
            {
                "value": "medical_illness_to_unknown",
                "label": "Keep problem type Unknown",
                "description": "Leave problem type Unknown for all 34 Medical_illness rows, preserving the explicit source label for audit.",
                "recommended": False,
            },
            {
                "value": "manual_row_review",
                "label": "Review every row",
                "description": "Hold the mapping and review all 34 rows individually before assigning problem type.",
                "recommended": False,
            },
        ],
    },
    {
        "id": "SCARLETS-2024-25-ADJ-001-PROBLEM-TYPE",
        "team": "Scarlets",
        "finding": "Body Part explicitly labels 46 rows as Medical_illness. This is direct cohort evidence, but the mapping has not previously been approved for Welsh intake data.",
        "question": "How should the 46 Scarlets rows labelled Medical_illness be classified for problem type?",
        "choices": [
            {
                "value": "medical_illness_to_illness",
                "label": "Classify as illness",
                "description": "Classify the explicit Medical_illness label as illness. Classify other rows as injury only where retained injury evidence supports it; otherwise use Unknown.",
                "recommended": True,
            },
            {
                "value": "medical_illness_to_unknown",
                "label": "Keep problem type Unknown",
                "description": "Leave problem type Unknown for all 46 Medical_illness rows, preserving the explicit source label for audit.",
                "recommended": False,
            },
            {
                "value": "manual_row_review",
                "label": "Review every row",
                "description": "Hold the mapping and review all 46 rows individually before assigning problem type.",
                "recommended": False,
            },
        ],
    },
]

FIXED_APPLICATIONS = [
    {
        "id": "WALES-EVID-001",
        "team": "Dragons",
        "title": "Broken Orchard codes limit taxonomy evidence",
        "finding": "All 200 populated Orchard Code cells contain #REF!. The broken codes cannot support an alternative clinical mapping.",
        "application": "Use explicit Body Part labels only where they directly support an IOC body bucket. Keep tissue or pathology Unknown unless corrected retained evidence is supplied.",
        "review_trigger": "A corrected export will change the evidence fingerprint, clear stale selections, and require review of this application.",
    }
]

INFERRED = [
    {
        "id": "WALES-INFER-001",
        "decision": "Use locator-tested restoration",
        "basis": "Accepted Stormers restoration answer",
        "application": "Restore omitted source fields only through tested workbook, sheet, and physical-row locators. Never restore raw identifiers.",
    },
    {
        "id": "WALES-INFER-002",
        "decision": "Keep source duration precedence",
        "basis": "Accepted Bulls, Sharks, and Stormers duration answers",
        "application": "Preserve valid nonnegative source Days Injured. Do not preserve impossible negative or Excel-serial artifacts. Use calendar derivation only when source duration is missing or invalid and the required dates are valid; otherwise treat the duration as censored or Unknown.",
    },
    {
        "id": "WALES-INFER-003",
        "decision": "Require explicit match scope evidence",
        "basis": "Accepted Bulls, Lions, Sharks, and Stormers match-scope answers",
        "application": "Classify URC only from explicit competition evidence or an audited fixture link. Do not treat every game as URC.",
    },
    {
        "id": "WALES-INFER-004",
        "decision": "Remove direct identifiers at the boundary",
        "basis": "Accepted Sharks and Stormers privacy answers",
        "application": "Do not carry DOB, names, or re-identification values into canonical intake evidence.",
    },
    {
        "id": "WALES-INFER-005",
        "decision": "Include unlabeled exposure as unknown",
        "basis": "Accepted South African decision-board direction",
        "application": "Do not exclude exposure solely because match or training labels are blank. Preserve setting as unknown.",
    },
    {
        "id": "WALES-INFER-006",
        "decision": "Use frozen exposure validity rules",
        "basis": "Accepted Bulls and Lions outlier answers",
        "application": "Do not introduce a Welsh team or device threshold. Audit any rows excluded by the frozen bounds.",
    },
    {
        "id": "WALES-INFER-007",
        "decision": "Audit exact duplicate exclusions",
        "basis": "Accepted Stormers duplicate answer",
        "application": "Exclude only exact copies with lineage and a controlled reason. Retain non-identical repeated rows.",
    },
    {
        "id": "WALES-INFER-008",
        "decision": "Accept provisional physical-row locators",
        "basis": "Accepted Sharks and Stormers provenance answers",
        "application": "Apply the prior provisional-locator decision, not a new scientific question. Cardiff and Dragons upstream preparer, timestamp, codebook, and secure-source metadata remain unavailable and must be recorded as such.",
    },
    {
        "id": "WALES-INFER-009",
        "decision": "Use row-level IOC evidence",
        "basis": "Accepted South African and Italian taxonomy answers",
        "application": "Map only evidence-supported values to one frozen IOC bucket. Preserve source values and leave unsupported body or pathology specificity Unknown.",
    },
]


def artifact_inventory() -> dict[str, dict[str, str | bool | None]]:
    """Return the exact evidence files and checksums bound to this board."""
    inventory = {}
    for team in TEAMS:
        for name in ARTIFACT_NAMES:
            path = DATA / team / name
            key = f"{team}/{name}"
            inventory[key] = {
                "present": path.is_file(),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None,
            }
    return inventory


def evidence_fingerprint() -> str:
    payload = {
        "decisions": DECISIONS,
        "fixed_applications": FIXED_APPLICATIONS,
        "inferred": INFERRED,
        "artifacts": artifact_inventory(),
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def empty_state(fingerprint: str) -> dict:
    return {
        "evidence_fingerprint": fingerprint,
        "updated_at": None,
        "selections": {},
        "note": "",
    }


def load_state() -> dict:
    current_fingerprint = evidence_fingerprint()
    if not STATE.exists():
        return empty_state(current_fingerprint)

    state = json.loads(STATE.read_text(encoding="utf-8"))
    if not isinstance(state, dict):
        raise ValueError("saved decision state must be a JSON object")
    if state.get("evidence_fingerprint") != current_fingerprint:
        fresh = empty_state(current_fingerprint)
        fresh["invalidated_previous_state"] = True
        fresh["invalidated_previous_updated_at"] = state.get("updated_at")
        return fresh

    valid = {
        item["id"]: {choice["value"] for choice in item["choices"]}
        for item in DECISIONS
    }
    selections = state.get("selections")
    if not isinstance(selections, dict):
        selections = {}
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
    current_fingerprint = evidence_fingerprint()
    if state.get("evidence_fingerprint") != current_fingerprint:
        raise ValueError("evidence changed while saving; reload the board")
    state["updated_at"] = datetime.now(UTC).isoformat()
    fd, temporary_name = tempfile.mkstemp(
        dir=STATE.parent, prefix=".wales-decisions-", suffix=".json"
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(state, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        if evidence_fingerprint() != current_fingerprint:
            raise ValueError("evidence changed while saving; reload the board")
        os.replace(temporary_name, STATE)
        directory_fd = os.open(STATE.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


def api_state() -> dict:
    artifacts = artifact_inventory()
    missing = [key for key, item in artifacts.items() if not item["present"]]
    return {
        "decisions": DECISIONS,
        "fixed_applications": FIXED_APPLICATIONS,
        "inferred": INFERRED,
        "artifact_status": {
            "expected": len(artifacts),
            "present": len(artifacts) - len(missing),
            "missing": missing,
        },
        **load_state(),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "WelshDecisionBoard/1"

    def send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        path = urlsplit(self.path).path
        try:
            if path == "/":
                body = HTML.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.send_header("X-Content-Type-Options", "nosniff")
                self.end_headers()
                self.wfile.write(body)
            elif path == "/api/state":
                self.send_json(api_state())
            elif path == "/api/health":
                self.send_json({"ok": True, "service": "welsh-profile-decision-board"})
            elif path == "/favicon.ico":
                self.send_response(204)
                self.end_headers()
            else:
                self.send_json({"ok": False, "error": "not found"}, 404)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            self.send_json({"ok": False, "error": str(exc)}, 500)

    def do_POST(self) -> None:
        path = urlsplit(self.path).path
        if path not in {"/api/select", "/api/note"}:
            self.send_json({"ok": False, "error": "not found"}, 404)
            return
        try:
            port = self.server.server_port
            allowed_hosts = {f"127.0.0.1:{port}", f"localhost:{port}"}
            host = self.headers.get("Host")
            if host not in allowed_hosts:
                self.send_json({"ok": False, "error": "invalid host"}, 403)
                return
            origin = self.headers.get("Origin")
            if origin is not None and origin != f"http://{host}":
                self.send_json({"ok": False, "error": "invalid origin"}, 403)
                return
            content_type = self.headers.get("Content-Type", "").split(";", 1)[0].strip().casefold()
            if content_type != "application/json":
                self.send_json({"ok": False, "error": "content type must be application/json"}, 415)
                return
            size = int(self.headers.get("Content-Length", "0"))
            if size <= 0 or size > MAX_REQUEST_BYTES:
                raise ValueError("request body size is invalid")
            payload = json.loads(self.rfile.read(size))
            if not isinstance(payload, dict):
                raise ValueError("request body must be a JSON object")

            with STATE_LOCK:
                state = load_state()
                if path == "/api/note":
                    note = payload.get("note")
                    if not isinstance(note, str) or len(note) > 5000:
                        raise ValueError("note must be text no longer than 5000 characters")
                    state["note"] = note
                else:
                    decision = next(
                        item for item in DECISIONS if item["id"] == payload["decision_id"]
                    )
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
                state.pop("invalidated_previous_state", None)
                state.pop("invalidated_previous_updated_at", None)
                save_state(state)
            self.send_json({"ok": True, **state})
        except (KeyError, ValueError, StopIteration, json.JSONDecodeError) as exc:
            self.send_json({"ok": False, "error": str(exc)}, 400)
        except OSError as exc:
            self.send_json({"ok": False, "error": str(exc)}, 500)

    def log_message(self, format: str, *args) -> None:
        return


def smoke_test_api() -> None:
    global STATE
    original_state_path = STATE
    with tempfile.TemporaryDirectory() as temporary_directory:
        STATE = Path(temporary_directory) / "decision_selections.json"
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            connection = http.client.HTTPConnection(
                "127.0.0.1", server.server_port, timeout=5
            )
            connection.request("GET", "/api/health")
            response = connection.getresponse()
            assert response.status == 200
            assert json.loads(response.read())["ok"] is True

            connection.request("GET", "/api/state")
            response = connection.getresponse()
            payload = json.loads(response.read())
            assert response.status == 200
            assert payload["evidence_fingerprint"] == evidence_fingerprint()
            assert payload["decisions"] == DECISIONS
            assert payload["fixed_applications"] == FIXED_APPLICATIONS

            attack_body = json.dumps(
                {
                    "decision_id": DECISIONS[0]["id"],
                    "choice": DECISIONS[0]["choices"][0]["value"],
                }
            )
            connection.request(
                "POST",
                "/api/select",
                body=attack_body,
                headers={
                    "Content-Type": "text/plain",
                    "Origin": "https://attacker.invalid",
                },
            )
            response = connection.getresponse()
            rejected = json.loads(response.read())
            assert 400 <= response.status < 500 and rejected["ok"] is False
            assert not STATE.exists()

            body = json.dumps(
                {
                    "decision_id": DECISIONS[0]["id"],
                    "choice": DECISIONS[0]["choices"][0]["value"],
                }
            )
            connection.request(
                "POST",
                "/api/select",
                body=body,
                headers={
                    "Content-Type": "application/json",
                    "Origin": f"http://127.0.0.1:{server.server_port}",
                },
            )
            response = connection.getresponse()
            saved = json.loads(response.read())
            assert response.status == 200 and saved["ok"] is True
            assert STATE.is_file()
            assert load_state()["selections"][DECISIONS[0]["id"]]["choice"] == DECISIONS[0]["choices"][0]["value"]
            connection.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)
            STATE = original_state_path


def check() -> None:
    assert HTML.is_file()
    ids = [item["id"] for item in DECISIONS + FIXED_APPLICATIONS + INFERRED]
    assert len(ids) == len(set(ids))
    assert DECISIONS
    assert all(len(item["choices"]) == 3 for item in DECISIONS)
    assert all(sum(bool(choice["recommended"]) for choice in item["choices"]) == 1 for item in DECISIONS)
    assert all(item["team"].casefold() in TEAMS for item in DECISIONS)
    visible_text = HTML.read_text(encoding="utf-8") + json.dumps(
        DECISIONS + FIXED_APPLICATIONS + INFERRED
    )
    assert "—" not in visible_text and "–" not in visible_text
    baseline_fingerprint = evidence_fingerprint()
    assert len(baseline_fingerprint) == 64
    original_application = INFERRED[0]["application"]
    try:
        INFERRED[0]["application"] = f"{original_application} Fingerprint regression probe."
        assert evidence_fingerprint() != baseline_fingerprint
    finally:
        INFERRED[0]["application"] = original_application
    assert evidence_fingerprint() == baseline_fingerprint
    loaded = load_state()
    assert loaded["evidence_fingerprint"] == evidence_fingerprint()
    smoke_test_api()

    missing = [key for key, value in artifact_inventory().items() if not value["present"]]
    pending_profiles = []
    for team in TEAMS:
        profile_path = DATA / team / "team_intake_profile.v2.draft.json"
        if not profile_path.is_file():
            pending_profiles.append(f"{team}: missing profile draft")
            continue
        profile = json.loads(profile_path.read_text(encoding="utf-8"))
        expected = {item["id"] for item in DECISIONS if item["team"].casefold() == team}
        actual = set(profile.get("unresolved_adjudication_ids") or [])
        if profile.get("ai_review_status") == "completed":
            assert actual == expected, (team, expected, actual)
        elif actual == expected:
            pending_profiles.append(f"{team}: IDs match, AI review still in progress")
        else:
            pending_profiles.append(f"{team}: compiler profile IDs still in progress")

    warnings = []
    if missing:
        warnings.append(f"{len(missing)} expected evidence files not present yet")
    if pending_profiles:
        warnings.append(f"{len(pending_profiles)} profile drafts still in progress")
    suffix = f"; {'; '.join(warnings)}" if warnings else ""
    print(
        f"PASS: {len(DECISIONS)} new decisions, {len(INFERRED)} inferred decisions, "
        f"and API smoke test{suffix}"
    )
    for warning in pending_profiles:
        print(f"WARNING: {warning}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8767)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        check()
    else:
        print(f"Welsh decision board: http://127.0.0.1:{args.port}")
        ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
