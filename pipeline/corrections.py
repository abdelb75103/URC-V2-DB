"""Audited, SQL-defined row-correction command handlers.

This module deliberately contains no injury, exposure, or dashboard formula.
It constructs a typed proposal, asks the versioned database functions for its
candidate, and persists only the evidence that a reviewer has inspected.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import uuid
from pathlib import Path
from typing import Any

from pipeline.__main__ import (
    SqlParams,
    assert_public_payload_is_publishable,
    clean_text,
    diff_json_documents,
    query_sql,
    run_provenance,
    run_sql,
    sha256_json,
    write_team_dashboard_parity_exports,
    write_json_atomic,
)


_ROOT = Path(__file__).resolve().parent.parent
_CONTENT_REPORTING = (_ROOT / "content" / "reporting").resolve()
_DYNAMIC_MIGRATION = (
    _ROOT
    / "supabase"
    / "migrations"
    / "20260727010000_dynamic_row_correction_pipeline_hardening.sql"
)
_DYNAMIC_MIGRATION_VERSION = "20260727010000"
_DYNAMIC_MIGRATION_NAME = "dynamic_row_correction_pipeline_hardening"
_BATCH_MIGRATION = (
    _ROOT
    / "supabase"
    / "migrations"
    / "20260803163430_dynamic_row_correction_batch_v7_hardening.sql"
)
_BATCH_MIGRATION_VERSION = "20260803163430"
_BATCH_MIGRATION_NAME = "dynamic_row_correction_batch_v7_hardening"
_ALLOWED_FIELDS = {
    "eligibility",
    "days_injured",
    "body_location_code",
    "injury_type_code",
    "diagnosis_code",
}
_SHA256 = re.compile(r"^[0-9a-f]{64}$")


def _error(message: str) -> None:
    raise SystemExit(f"row correction: {message}")


def _required_text(args: argparse.Namespace, name: str) -> str:
    value = clean_text(str(getattr(args, name, "") or ""))
    if not value:
        _error(f"--{name.replace('_', '-')} is required")
    return value


def _audit_provenance(operator: str) -> dict[str, str]:
    """Return the reproducible identity required for every audited command.

    The SQL procedures persist this object with their own run rows.  The
    operator is explicit rather than inherited from the shell so review is
    attributable even when a local environment variable is stale.
    """
    provenance = run_provenance()
    code_version = clean_text(provenance.get("code_version"))
    dependency_lock_hash = clean_text(provenance.get("dependency_lock_hash"))
    if (
        not code_version
        or not _SHA256.fullmatch(dependency_lock_hash)
        or not _DYNAMIC_MIGRATION.is_file()
    ):
        _error("Git, dependency-lock, or migration provenance is unavailable")
    migration_sha256 = hashlib.sha256(_DYNAMIC_MIGRATION.read_bytes()).hexdigest()
    registered = query_sql(
        "select statements "
        "from supabase_migrations.schema_migrations "
        f"where version = '{_DYNAMIC_MIGRATION_VERSION}' "
        f"and name = '{_DYNAMIC_MIGRATION_NAME}'"
    )
    expected_statement = f"migration_sha256={migration_sha256}"
    if (
        len(registered) != 1
        or registered[0].get("statements") != [expected_statement]
    ):
        _error(
            "local correction migration SHA does not match the registered "
            "live implementation"
        )
    return {
        "code_version": code_version,
        "dependency_lock_hash": dependency_lock_hash,
        "migration_sha256": migration_sha256,
        "operator": operator,
    }


def _batch_audit_provenance(operator: str) -> dict[str, str]:
    provenance = run_provenance()
    code_version = clean_text(provenance.get("code_version"))
    dependency_lock_hash = clean_text(provenance.get("dependency_lock_hash"))
    if (
        not code_version
        or not _SHA256.fullmatch(dependency_lock_hash)
        or not _BATCH_MIGRATION.is_file()
    ):
        _error("Git, dependency-lock, or batch migration provenance is unavailable")
    migration_sha256 = hashlib.sha256(_BATCH_MIGRATION.read_bytes()).hexdigest()
    registered = query_sql(
        "select statements from supabase_migrations.schema_migrations "
        f"where version = '{_BATCH_MIGRATION_VERSION}' "
        f"and name = '{_BATCH_MIGRATION_NAME}'"
    )
    if (
        len(registered) != 1
        or registered[0].get("statements") != [f"migration_sha256={migration_sha256}"]
    ):
        _error(
            "local correction batch migration SHA does not match the registered "
            "live implementation"
        )
    return {
        "code_version": code_version,
        "dependency_lock_hash": dependency_lock_hash,
        "migration_sha256": migration_sha256,
        "operator": operator,
    }


def _verified_evidence(args: argparse.Namespace, field: str = "evidence_file") -> tuple[Path, str]:
    path = Path(_required_text(args, field))
    if not path.is_file():
        _error(f"{field.replace('_', '-')} not found")
    return path, hashlib.sha256(path.read_bytes()).hexdigest()


def _read_json_file(path: Path, label: str) -> object:
    if not path.is_file():
        _error(f"{label} not found")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        _error(f"{label} is not valid JSON")
        raise AssertionError("unreachable") from exc


def _parse_json_value(value: object, label: str) -> object:
    if not isinstance(value, str):
        return value
    try:
        return json.loads(value, parse_constant=lambda token: (_ for _ in ()).throw(ValueError(token)))
    except (json.JSONDecodeError, ValueError) as exc:
        _error(f"--{label.replace('_', '-')} must be valid JSON")
        raise AssertionError("unreachable") from exc


def _is_content_reporting(path: Path) -> bool:
    resolved = path.resolve()
    return resolved == _CONTENT_REPORTING or _CONTENT_REPORTING in resolved.parents


def _require_private_output(path_value: object, label: str) -> Path:
    raw_path = clean_text(str(path_value or ""))
    if not raw_path:
        _error(f"--{label.replace('_', '-')} is required")
    path = Path(raw_path)
    if not path.is_absolute():
        path = _ROOT / path
    if _is_content_reporting(path):
        _error(f"{label.replace('_', '-')} must stay outside content/reporting")
    try:
        ignored = subprocess.run(
            ["git", "check-ignore", "--quiet", "--", str(path)],
            cwd=_ROOT,
            check=False,
            capture_output=True,
        ).returncode == 0
    except OSError as exc:
        _error(f"cannot verify Git-ignored {label.replace('_', '-')} path: {exc}")
        raise AssertionError("unreachable") from exc
    if not ignored:
        _error(f"{label.replace('_', '-')} must be Git-ignored")
    return path


def _read_proposal(path_value: object) -> tuple[dict[str, Any], str, Path, dict[str, Any]]:
    path = Path(clean_text(str(path_value or "")))
    if not path.is_file():
        _error("proposal file not found")
    raw = _read_json_file(path, "proposal file")
    if not isinstance(raw, dict):
        _error("proposal file must contain an object")
    proposal = raw.get("proposal")
    proposal_hash = clean_text(str(raw.get("proposal_hash") or ""))
    if not isinstance(proposal, dict) or not _SHA256.fullmatch(proposal_hash):
        _error("proposal file has no valid proposal and canonical proposal hash")
    _validate_proposal_shape(proposal)
    if clean_text(str(proposal.get("proposal_hash") or "")) != proposal_hash:
        _error("proposal file has inconsistent proposal hashes")
    return proposal, proposal_hash, path, raw


def _validate_proposal_shape(proposal: dict[str, Any]) -> None:
    required = {
        "season",
        "source_row_id",
        "field_name",
        "expected_value",
        "new_value",
        "reason",
        "evidence_sha256",
        "operator",
        "rule_version",
        "source_row_sha256",
        "row_fingerprint",
        "correction_set_hash_before",
        "correction_set_hash_after",
        "predecessor_bundle",
        "affected_team_before_sha256",
        "affected_team_after_sha256",
        "affected_league_before_sha256",
        "affected_league_after_sha256",
        "unchanged_team_hashes",
        "proposal_hash",
        "code_version",
        "dependency_lock_hash",
        "migration_sha256",
    }
    missing = required - set(proposal)
    if missing:
        _error("proposal is missing required fields")
    if clean_text(str(proposal["field_name"])) not in _ALLOWED_FIELDS:
        _error("proposal field is not eligible for a row correction")
    if not _SHA256.fullmatch(clean_text(str(proposal["evidence_sha256"]))):
        _error("proposal evidence hash is invalid")
    for name in (
        "source_row_sha256",
        "row_fingerprint",
        "correction_set_hash_before",
        "correction_set_hash_after",
        "affected_team_before_sha256",
        "affected_team_after_sha256",
        "affected_league_before_sha256",
        "affected_league_after_sha256",
        "proposal_hash",
        "dependency_lock_hash",
        "migration_sha256",
    ):
        if not _SHA256.fullmatch(clean_text(str(proposal[name]))):
            _error(f"proposal {name.replace('_', ' ')} is invalid")
    if not clean_text(str(proposal["code_version"])):
        _error("proposal code version is invalid")
    predecessor = proposal["predecessor_bundle"]
    if (
        not isinstance(predecessor, dict)
        or not clean_text(str(predecessor.get("release_id") or ""))
        or not clean_text(str(predecessor.get("release_label") or ""))
        or not _SHA256.fullmatch(
            clean_text(str(predecessor.get("bundle_sha256") or ""))
        )
    ):
        _error("proposal predecessor bundle binding is invalid")
    _unchanged_team_hashes(proposal["unchanged_team_hashes"])
    try:
        uuid.UUID(clean_text(str(proposal["source_row_id"])))
    except ValueError as exc:
        _error("proposal source row identity is invalid")
        raise AssertionError("unreachable") from exc
    supersedes = proposal.get("supersedes_correction_id")
    if supersedes not in (None, ""):
        try:
            uuid.UUID(clean_text(str(supersedes)))
        except ValueError as exc:
            _error("proposal superseded correction identity is invalid")
            raise AssertionError("unreachable") from exc


def _proposal_from_args(args: argparse.Namespace) -> dict[str, Any]:
    evidence_path, evidence_sha256 = _verified_evidence(args)
    field_name = _required_text(args, "field_name")
    if field_name not in _ALLOWED_FIELDS:
        _error(
            "--field-name must be one of "
            + ", ".join(sorted(_ALLOWED_FIELDS))
        )
    source_row_id = _required_text(args, "source_row_id")
    try:
        uuid.UUID(source_row_id)
    except ValueError as exc:
        _error("--source-row-id must be a UUID")
        raise AssertionError("unreachable") from exc
    supersedes = clean_text(str(getattr(args, "supersedes_correction_id", "") or ""))
    if supersedes:
        try:
            uuid.UUID(supersedes)
        except ValueError as exc:
            _error("--supersedes-correction-id must be a UUID")
            raise AssertionError("unreachable") from exc
    if not hasattr(args, "expected_value") or not hasattr(args, "new_value"):
        _error("--expected-value and --new-value are required (JSON null is allowed)")
    operator = _required_text(args, "operator")
    proposal: dict[str, Any] = {
        "season": _required_text(args, "season"),
        "source_row_id": source_row_id,
        "field_name": field_name,
        "expected_value": _parse_json_value(getattr(args, "expected_value", None), "expected_value"),
        "new_value": _parse_json_value(getattr(args, "new_value", None), "new_value"),
        "reason": _required_text(args, "reason"),
        "evidence_sha256": evidence_sha256,
        "operator": operator,
        "rule_version": _required_text(args, "rule_version"),
        **_audit_provenance(operator),
    }
    if supersedes:
        proposal["supersedes_correction_id"] = supersedes
    return proposal


def _one_json_row(sql: str, params: list[object], label: str) -> dict[str, Any]:
    rows = query_sql(sql, params)
    if len(rows) != 1 or not isinstance(rows[0].get(label), dict):
        _error(f"database did not return one {label.replace('_', ' ')}")
    return rows[0][label]


def _proposal_hash(proposal: dict[str, Any]) -> str:
    params = SqlParams()
    rows = query_sql(
        "select analysis.row_correction_proposal_hash_v1("
        f"{params.jsonb(proposal)}) as proposal_hash",
        params.values,
    )
    value = clean_text(str(rows[0].get("proposal_hash") or "")) if len(rows) == 1 else ""
    if not _SHA256.fullmatch(value):
        _error("database returned an invalid canonical proposal hash")
    return value


def _preview(proposal: dict[str, Any]) -> dict[str, Any]:
    # query_sql is deliberately the only database boundary for previews.
    params = SqlParams()
    return _one_json_row(
        "select to_jsonb(preview) as preview "
        f"from analysis.row_correction_preview_v2({params.jsonb(proposal)}) preview",
        params.values,
        "preview",
    )


def _assert_legacy_v2_is_available() -> None:
    rows = query_sql(
        "select to_regprocedure("
        "'analysis.assert_legacy_row_correction_v2_available()'"
        ") is not null as batch_v3_installed"
    )
    if len(rows) != 1 or not isinstance(rows[0].get("batch_v3_installed"), bool):
        _error("could not verify the installed correction workflow version")
    if rows[0]["batch_v3_installed"]:
        _error(
            "single-row correction V2 is disabled after batch V3 installation; "
            "use correction-batch-propose with a one-item manifest"
        )


def _preview_value(preview: dict[str, Any], *names: str) -> object:
    for name in names:
        if name in preview:
            return preview[name]
    _error("database preview is missing a required correction contract value")
    raise AssertionError("unreachable")


def _safe_changed_paths(preview: dict[str, Any]) -> dict[str, list[str]]:
    team_before = _preview_value(preview, "affected_team_before", "team_before")
    team_after = _preview_value(preview, "affected_team_after", "team_after")
    league_before = _preview_value(preview, "affected_league_before", "league_before")
    league_after = _preview_value(preview, "affected_league_after", "league_after")
    for label, payload in (
        ("affected team before payload", team_before),
        ("affected team after payload", team_after),
        ("affected league before payload", league_before),
        ("affected league after payload", league_after),
    ):
        assert_public_payload_is_publishable(payload, label)
    return {
        "team": [entry["path"] for entry in diff_json_documents(team_before, team_after)],
        "league": [entry["path"] for entry in diff_json_documents(league_before, league_after)],
    }


def _public_subject(subject: object) -> dict[str, object]:
    if not isinstance(subject, dict):
        _error("database preview subject must be an object")
    # The full subject, including its row identity and fingerprint, remains in
    # the database audit trail and private proposal. It is never echoed into a
    # preview artifact or terminal output.
    allowed = ("team_key", "season", "field_name", "current_effective_value")
    return {key: subject[key] for key in allowed if key in subject}


def _subject_binding(subject: object, source_row_id: object) -> dict[str, str]:
    if not isinstance(subject, dict):
        _error("database preview subject must be an object")
    if clean_text(str(subject.get("source_row_id") or "")) != clean_text(str(source_row_id)):
        _error("database preview subject does not bind the requested source row")
    source_row_sha256 = clean_text(str(subject.get("source_row_sha256") or ""))
    row_fingerprint = clean_text(str(subject.get("row_fingerprint") or ""))
    if not _SHA256.fullmatch(source_row_sha256) or not _SHA256.fullmatch(row_fingerprint):
        _error("database preview has incomplete immutable source-row evidence")
    return {
        "source_row_sha256": source_row_sha256,
        "row_fingerprint": row_fingerprint,
    }


def _proposal_preview_binding(
    preview: dict[str, Any], source_row_id: object
) -> dict[str, Any]:
    binding: dict[str, Any] = _subject_binding(
        _preview_value(preview, "subject"), source_row_id
    )
    for name in (
        "correction_set_hash_before",
        "correction_set_hash_after",
        "affected_team_before_sha256",
        "affected_team_after_sha256",
        "affected_league_before_sha256",
        "affected_league_after_sha256",
    ):
        value = clean_text(str(_preview_value(preview, name) or ""))
        if not _SHA256.fullmatch(value):
            _error(f"database preview has invalid {name.replace('_', ' ')}")
        binding[name] = value
    predecessor = _preview_value(preview, "predecessor_bundle")
    if (
        not isinstance(predecessor, dict)
        or not clean_text(str(predecessor.get("release_id") or ""))
        or not clean_text(str(predecessor.get("release_label") or ""))
        or not _SHA256.fullmatch(
            clean_text(str(predecessor.get("bundle_sha256") or ""))
        )
    ):
        _error("database preview has incomplete predecessor bundle evidence")
    binding["predecessor_bundle"] = predecessor
    binding["unchanged_team_hashes"] = _unchanged_team_hashes(
        _preview_value(preview, "unchanged_team_hashes")
    )
    return binding


def _unchanged_team_hashes(value: object) -> list[dict[str, Any]]:
    if not isinstance(value, list) or len(value) not in {15, 16}:
        _error("database preview must prove 15 reused or 16 unchanged team hashes")
    if any(
        not isinstance(row, dict)
        or not clean_text(str(row.get("team_key") or ""))
        or not _SHA256.fullmatch(clean_text(str(row.get("payload_sha256") or "")))
        for row in value
    ):
        _error("database preview has invalid unchanged team hash evidence")
    return value


def _public_preview(preview: dict[str, Any], proposal_hash: str) -> dict[str, Any]:
    changed_paths = _safe_changed_paths(preview)
    required = {
        "subject": _public_subject(_preview_value(preview, "subject")),
        "affected_team_before_sha256": _preview_value(
            preview, "affected_team_before_sha256", "team_before_sha256"
        ),
        "affected_team_after_sha256": _preview_value(
            preview, "affected_team_after_sha256", "team_after_sha256"
        ),
        "affected_league_before_sha256": _preview_value(
            preview, "affected_league_before_sha256", "league_before_sha256"
        ),
        "affected_league_after_sha256": _preview_value(
            preview, "affected_league_after_sha256", "league_after_sha256"
        ),
        "unchanged_team_hashes": _unchanged_team_hashes(
            _preview_value(preview, "unchanged_team_hashes")
        ),
        "correction_set_hash_before": _preview_value(preview, "correction_set_hash_before"),
        "correction_set_hash_after": _preview_value(preview, "correction_set_hash_after"),
        "predecessor_bundle": _preview_value(preview, "predecessor_bundle"),
    }
    # The preview itself is stored only in ignored local output. Keep stdout
    # concise and never print source-row or correction identifiers.
    return {
        "schema_version": "urc_row_correction_preview_v1",
        "proposal_hash": proposal_hash,
        "preview": required,
        "affected_team_before": _preview_value(
            preview, "affected_team_before", "team_before"
        ),
        "affected_team_after": _preview_value(
            preview, "affected_team_after", "team_after"
        ),
        "affected_league_before": _preview_value(
            preview, "affected_league_before", "league_before"
        ),
        "affected_league_after": _preview_value(
            preview, "affected_league_after", "league_after"
        ),
        "changed_paths": changed_paths,
    }


def _served_state(season: str) -> dict[str, Any]:
    """Capture both database surfaces the site serves, without a timestamp waiver."""
    stored_bundle, stored_metadata = _current_correction_aware_bundle_snapshot(
        season
    )
    params = SqlParams()
    rows = query_sql(
        f"""
        with team_projection as (
          select source.team_key, to_jsonb(team_row) as dashboard
          from reporting.latest_team_dashboard_v5 source
          cross join lateral (
            select source.team, source.season, source.generated_at,
              source.analysis_window, source.method, source.coverage,
              source.headline, source.setting_split, source.setting_metrics,
              source.monthly, source.body_locations, source.injury_types,
              source.injury_profiles, source.injury_type_families,
              source.severity_distribution, source.contact_distribution,
              source.prior_season,
              source.limitations
          ) team_row
          where source.season = {params.text(season)}
        ), league_projection as (
          select to_jsonb(league_row) as dashboard
          from (
            select team, season, generated_at, analysis_window, method,
              coverage, headline, setting_split, setting_metrics, monthly,
              body_locations, injury_types, injury_profiles,
              injury_type_families, severity_distribution,
              contact_distribution, prior_season,
              limitations
            from reporting.latest_league_dashboard_v5
            where season = {params.text(season)}
          ) league_row
        )
        select (select dashboard from league_projection) as league,
          coalesce((select jsonb_agg(jsonb_build_object(
            'team_key', team_key, 'dashboard', dashboard
          ) order by team_key) from team_projection), '[]'::jsonb) as teams
        """,
        params.values,
    )
    if len(rows) != 1 or not isinstance(rows[0].get("league"), dict):
        _error("no served correction-aware league projection exists")
    teams = rows[0].get("teams")
    if not isinstance(teams, list) or len(teams) != 16:
        _error("served correction-aware projection is not a complete 16-team snapshot")
    stored_params = SqlParams()
    stored_rows = query_sql(
        f"""
        with current_bundle as (
          select release_id
          from reporting.latest_approved_dashboard_bundle_v4
          where season = {stored_params.text(season)}
        ), team_payloads as (
          select payload.team_key, payload.dashboard_payload, payload.payload_sha256
          from reporting.dashboard_bundle_team_payloads_v1 payload
          join current_bundle current on current.release_id = payload.bundle_release_id
        )
        select league.payload_sha256 as league_payload_sha256,
          coalesce(jsonb_object_agg(team.team_key, team.payload_sha256 order by team.team_key),
            '{{}}'::jsonb) as team_payload_sha256s,
          encode(extensions.digest(convert_to(jsonb_build_object(
            'schema_version', 'urc_dashboard_bundle_v2',
            'season', {stored_params.text(season)},
            'league', league.dashboard_payload,
            'teams', coalesce((select jsonb_agg(jsonb_build_object(
              'team_key', team.team_key, 'dashboard', team.dashboard_payload
            ) order by team.team_key) from team_payloads team), '[]'::jsonb)
          )::text, 'UTF8'), 'sha256'), 'hex') as database_bundle_sha256
        from current_bundle current
        join reporting.dashboard_bundle_league_payloads_v1 league
          on league.release_id = current.release_id
        left join team_payloads team on true
        group by league.payload_sha256, league.dashboard_payload
        """,
        stored_params.values,
    )
    if len(stored_rows) != 1 or not _SHA256.fullmatch(clean_text(str(stored_rows[0].get("database_bundle_sha256") or ""))):
        _error("stored V2 bundle hashes are incomplete")
    team_hashes = stored_rows[0].get("team_payload_sha256s")
    if not isinstance(team_hashes, dict) or len(team_hashes) != 16:
        _error("stored V2 team payload hashes are incomplete")
    served_v3 = {"league": rows[0]["league"], "teams": teams}
    return {
        "schema_version": "urc_served_correction_baseline_v1",
        "season": season,
        "served_v3": served_v3,
        "served_v3_sha256": sha256_json(served_v3),
        "stored_v2": {
            "release_label": stored_metadata["release_label"],
            "approved_at": stored_metadata["approved_at"],
            "bundle_sha256": stored_metadata["bundle_sha256"],
            "database_bundle_sha256": stored_rows[0]["database_bundle_sha256"],
            "league_payload_sha256": stored_rows[0].get("league_payload_sha256"),
            "team_payload_sha256s": team_hashes,
            "bundle": stored_bundle,
        },
    }


def _current_correction_aware_bundle_snapshot(
    season: str,
) -> tuple[dict[str, Any], dict[str, Any]]:
    params = SqlParams()
    rows = query_sql(
        f"""
        select
          release.id::text as release_id,
          release.release_label,
          release.approved_at,
          jsonb_build_object(
            'schema_version', 'urc_dashboard_bundle_v2',
            'season', bundle.season,
            'league', league.dashboard_payload,
            'teams', coalesce((
              select jsonb_agg(jsonb_build_object(
                'team_key', team.team_key,
                'dashboard', team.dashboard_payload
              ) order by team.team_key)
              from reporting.dashboard_bundle_team_payloads_v1 team
              where team.bundle_release_id = bundle.release_id
            ), '[]'::jsonb)
          ) as bundle,
          analysis.row_correction_bundle_hash_v1(bundle.release_id)
            as bundle_sha256
        from reporting.latest_approved_dashboard_bundle_v4 bundle
        join reporting.aggregate_releases release
          on release.id = bundle.release_id
        join reporting.dashboard_bundle_league_payloads_v1 league
          on league.release_id = bundle.release_id
        where bundle.season = {params.text(season)}
        """,
        params.values,
    )
    if len(rows) != 1 or not isinstance(rows[0].get("bundle"), dict):
        _error("no unique correction-aware approved dashboard bundle exists")
    bundle = rows[0]["bundle"]
    teams = bundle.get("teams")
    if not isinstance(teams, list) or len(teams) != 16:
        _error("correction-aware dashboard bundle is not a complete 16-team snapshot")
    bundle_sha256 = clean_text(str(rows[0].get("bundle_sha256") or ""))
    if not _SHA256.fullmatch(bundle_sha256):
        _error("correction-aware dashboard bundle hash is invalid")
    return bundle, {
        "release_id": clean_text(str(rows[0].get("release_id") or "")),
        "release_label": clean_text(str(rows[0].get("release_label") or "")),
        "approved_at": rows[0].get("approved_at"),
        "bundle_sha256": bundle_sha256,
    }


def capture_served_baseline(args: argparse.Namespace) -> None:
    season = _required_text(args, "season")
    output = _require_private_output(getattr(args, "output", ""), "output")
    baseline = _served_state(season)
    assert_public_payload_is_publishable(baseline["served_v3"], "served V3 baseline")
    assert_public_payload_is_publishable(baseline["stored_v2"]["bundle"], "stored V2 baseline")
    write_json_atomic(output, baseline)
    print(json.dumps({
        "status": "captured_served_baseline",
        "season": season,
        "output_path": str(output),
        "served_v3_sha256": baseline["served_v3_sha256"],
        "stored_v2_bundle_sha256": baseline["stored_v2"]["bundle_sha256"],
    }, indent=2))


def verify_served_baseline(args: argparse.Namespace) -> None:
    baseline_path = Path(_required_text(args, "baseline_file"))
    baseline = _read_json_file(baseline_path, "baseline file")
    if not isinstance(baseline, dict):
        _error("baseline file must contain an object")
    season = _required_text(args, "season")
    if baseline.get("schema_version") != "urc_served_correction_baseline_v1" or baseline.get("season") != season:
        _error("baseline file does not bind this season")
    current = _served_state(season)
    diffs = diff_json_documents(baseline, current)
    if diffs:
        paths = ", ".join(str(entry["path"]) for entry in diffs[:10])
        _error(f"served baseline changed ({paths})")
    print(json.dumps({
        "status": "served_baseline_verified",
        "season": season,
        "served_v3_sha256": current["served_v3_sha256"],
        "stored_v2_bundle_sha256": current["stored_v2"]["bundle_sha256"],
    }, indent=2))


def correction_propose(args: argparse.Namespace) -> None:
    """Create a read-only proposal binding old/new typed values, source_row_sha256,
    correction_set_sha256 evidence, and the canonical proposal_hash.

    Approval is intentionally absent. The named reviewer is supplied only to
    correction_apply after the proposal and its downstream impact are read.
    """
    _assert_legacy_v2_is_available()
    output = _require_private_output(getattr(args, "output", ""), "output")
    proposal = _proposal_from_args(args)
    preview = _preview(proposal)
    proposal.update(
        _proposal_preview_binding(preview, proposal["source_row_id"])
    )
    proposal_hash = _proposal_hash(proposal)
    proposal["proposal_hash"] = proposal_hash
    public_preview = _public_preview(preview, proposal_hash)
    subject_binding = {
        "source_row_sha256": proposal["source_row_sha256"],
        "row_fingerprint": proposal["row_fingerprint"],
    }
    write_json_atomic(output, {
        "schema_version": "urc_row_correction_proposal_v1",
        "proposal": proposal,
        "proposal_hash": proposal_hash,
        "subject_binding": subject_binding,
        "evidence_file": str(Path(_required_text(args, "evidence_file")).resolve()),
        "preview": public_preview,
    })
    print(json.dumps({
        "status": "proposal_created",
        "season": proposal["season"],
        "proposal_hash": proposal_hash,
        "output_path": str(output),
        "changed_paths": public_preview["changed_paths"],
    }, indent=2))


def _batch_preview(proposal: dict[str, Any]) -> dict[str, Any]:
    params = SqlParams()
    return _one_json_row(
        "select to_jsonb(preview) as preview "
        f"from analysis.row_correction_preview_v5({params.jsonb(proposal)}) preview",
        params.values,
        "preview",
    )


def _batch_items_from_manifest(
    args: argparse.Namespace,
) -> tuple[list[dict[str, Any]], dict[str, str]]:
    manifest_path = Path(_required_text(args, "manifest"))
    manifest = _read_json_file(manifest_path, "batch manifest")
    if not isinstance(manifest, dict) or not isinstance(manifest.get("items"), list):
        _error("batch manifest must contain an items array")
    if not manifest["items"]:
        _error("batch manifest must contain at least one item")
    items: list[dict[str, Any]] = []
    evidence_files: dict[str, str] = {}
    seen: set[tuple[str, str]] = set()
    for index, raw in enumerate(manifest["items"]):
        if not isinstance(raw, dict):
            _error(f"batch manifest item {index + 1} must be an object")
        source_row_id = clean_text(str(raw.get("source_row_id") or ""))
        field_name = clean_text(str(raw.get("field_name") or ""))
        try:
            uuid.UUID(source_row_id)
        except ValueError as exc:
            _error(f"batch manifest item {index + 1} has an invalid source row UUID")
            raise AssertionError("unreachable") from exc
        if field_name not in _ALLOWED_FIELDS:
            _error(f"batch manifest item {index + 1} has an unsupported field")
        if (source_row_id, field_name) in seen:
            _error("batch manifest repeats a source-row field")
        seen.add((source_row_id, field_name))
        if "expected_value" not in raw or "new_value" not in raw:
            _error(f"batch manifest item {index + 1} needs expected_value and new_value")
        evidence_path = Path(clean_text(str(raw.get("evidence_file") or "")))
        if not evidence_path.is_file():
            _error(f"batch manifest item {index + 1} evidence file not found")
        evidence_sha256 = hashlib.sha256(evidence_path.read_bytes()).hexdigest()
        reason = clean_text(str(raw.get("reason") or ""))
        rule_version = clean_text(str(raw.get("rule_version") or ""))
        if not reason or not rule_version:
            _error(f"batch manifest item {index + 1} needs reason and rule_version")
        item: dict[str, Any] = {
            "source_row_id": source_row_id,
            "field_name": field_name,
            "expected_value": raw["expected_value"],
            "new_value": raw["new_value"],
            "reason": reason,
            "rule_version": rule_version,
            "evidence_sha256": evidence_sha256,
        }
        supersedes = clean_text(str(raw.get("supersedes_correction_id") or ""))
        if supersedes:
            try:
                uuid.UUID(supersedes)
            except ValueError as exc:
                _error(
                    f"batch manifest item {index + 1} has an invalid superseded correction UUID"
                )
                raise AssertionError("unreachable") from exc
            item["supersedes_correction_id"] = supersedes
        items.append(item)
        evidence_files[f"{source_row_id}:{field_name}"] = str(evidence_path.resolve())
    return items, evidence_files


def _batch_subject_bindings(
    preview: dict[str, Any], items: list[dict[str, Any]]
) -> tuple[str, list[dict[str, str]]]:
    subjects = preview.get("subjects")
    if not isinstance(subjects, list) or len(subjects) != len(items):
        _error("database batch preview did not return every source-row subject")
    by_key = {
        (clean_text(str(subject.get("source_row_id") or "")), clean_text(str(subject.get("field_name") or ""))): subject
        for subject in subjects
        if isinstance(subject, dict)
    }
    bindings: list[dict[str, str]] = []
    teams: set[str] = set()
    for item in items:
        key = (item["source_row_id"], item["field_name"])
        subject = by_key.get(key)
        if not isinstance(subject, dict):
            _error("database batch preview subject does not bind a requested item")
        source_sha = clean_text(str(subject.get("source_row_sha256") or ""))
        fingerprint = clean_text(str(subject.get("row_fingerprint") or ""))
        team_key = clean_text(str(subject.get("team_key") or ""))
        if not _SHA256.fullmatch(source_sha) or not _SHA256.fullmatch(fingerprint) or not team_key:
            _error("database batch preview subject evidence is incomplete")
        teams.add(team_key)
        item["source_row_sha256"] = source_sha
        item["row_fingerprint"] = fingerprint
        bindings.append({
            "source_row_id": item["source_row_id"],
            "field_name": item["field_name"],
            "source_row_sha256": source_sha,
            "row_fingerprint": fingerprint,
        })
    if len(teams) != 1:
        _error("correction batch must contain rows from exactly one team")
    return teams.pop(), bindings


def _batch_downstream_binding(preview: dict[str, Any]) -> dict[str, Any]:
    binding: dict[str, Any] = {}
    for name in (
        "correction_set_hash_before",
        "correction_set_hash_after",
        "affected_team_before_sha256",
        "affected_team_after_sha256",
        "affected_league_before_sha256",
        "affected_league_after_sha256",
    ):
        value = clean_text(str(preview.get(name) or ""))
        if not _SHA256.fullmatch(value):
            _error(f"database batch preview has invalid {name.replace('_', ' ')}")
        binding[name] = value
    predecessor = preview.get("predecessor_bundle")
    if not isinstance(predecessor, dict) or not _SHA256.fullmatch(
        clean_text(str(predecessor.get("bundle_sha256") or ""))
    ):
        _error("database batch preview has incomplete predecessor evidence")
    binding["predecessor_bundle"] = predecessor
    binding["unchanged_team_hashes"] = _unchanged_team_hashes(
        preview.get("unchanged_team_hashes")
    )
    return binding


def correction_batch_propose(args: argparse.Namespace) -> None:
    output = _require_private_output(getattr(args, "output", ""), "output")
    operator = _required_text(args, "operator")
    items, evidence_files = _batch_items_from_manifest(args)
    proposal: dict[str, Any] = {
        "season": _required_text(args, "season"),
        "items": items,
        **_batch_audit_provenance(operator),
    }
    preview = _batch_preview(proposal)
    team_key, subject_bindings = _batch_subject_bindings(preview, items)
    proposal["team_key"] = team_key
    proposal.update(_batch_downstream_binding(preview))
    proposal_hash = _proposal_hash(proposal)
    proposal["proposal_hash"] = proposal_hash
    public_subjects = [
        {
            key: subject.get(key)
            for key in ("team_key", "season", "field_name", "current_effective_value")
            if key in subject
        }
        for subject in preview["subjects"]
    ]
    public_preview = {
        "schema_version": "urc_row_correction_batch_preview_v3",
        "proposal_hash": proposal_hash,
        "subjects": public_subjects,
        "affected_team_before_sha256": preview["affected_team_before_sha256"],
        "affected_team_after_sha256": preview["affected_team_after_sha256"],
        "affected_league_before_sha256": preview["affected_league_before_sha256"],
        "affected_league_after_sha256": preview["affected_league_after_sha256"],
        "unchanged_team_hashes": proposal["unchanged_team_hashes"],
        "changed_paths": _safe_changed_paths(preview),
    }
    write_json_atomic(output, {
        "schema_version": "urc_row_correction_batch_proposal_v3",
        "proposal": proposal,
        "proposal_hash": proposal_hash,
        "subject_bindings": subject_bindings,
        "evidence_files": evidence_files,
        "preview": public_preview,
    })
    print(json.dumps({
        "status": "correction_batch_proposal_created",
        "season": proposal["season"],
        "team_key": team_key,
        "item_count": len(items),
        "proposal_hash": proposal_hash,
        "output_path": str(output),
        "changed_paths": public_preview["changed_paths"],
    }, indent=2))


def _read_batch_proposal(path_value: object) -> tuple[dict[str, Any], dict[str, Any], Path]:
    path = Path(clean_text(str(path_value or "")))
    raw = _read_json_file(path, "batch proposal file")
    if not isinstance(raw, dict) or raw.get("schema_version") != "urc_row_correction_batch_proposal_v3":
        _error("batch proposal file has an invalid schema")
    proposal = raw.get("proposal")
    proposal_hash = clean_text(str(raw.get("proposal_hash") or ""))
    if not isinstance(proposal, dict) or not isinstance(proposal.get("items"), list):
        _error("batch proposal file has no proposal items")
    if proposal.get("proposal_hash") != proposal_hash or not _SHA256.fullmatch(proposal_hash):
        _error("batch proposal file has inconsistent proposal hashes")
    return proposal, raw, path


def _pending_batch_candidate(proposal_hash: str, season: str) -> dict[str, Any]:
    params = SqlParams()
    rows = query_sql(
        "select to_jsonb(candidate) as candidate "
        "from analysis.row_correction_pending_candidate_data_v3("
        f"{params.text(season)}) candidate "
        f"where candidate.proposal_hash = {params.text(proposal_hash)}",
        params.values,
    )
    if len(rows) != 1 or not isinstance(rows[0].get("candidate"), dict):
        _error("database has no unique pending candidate for this batch")
    return rows[0]["candidate"]


def correction_batch_apply(args: argparse.Namespace) -> None:
    proposal, envelope, _ = _read_batch_proposal(getattr(args, "proposal_file", ""))
    proposal_hash = clean_text(str(proposal["proposal_hash"]))
    if _proposal_hash(proposal) != proposal_hash:
        _error("batch proposal hash does not match its canonical database hash")
    evidence_files = envelope.get("evidence_files")
    if not isinstance(evidence_files, dict):
        _error("batch proposal has no evidence-file map")
    evidence_by_item: dict[str, str] = {}
    for item in proposal["items"]:
        key = f"{item['source_row_id']}:{item['field_name']}"
        path = Path(clean_text(str(evidence_files.get(key) or "")))
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != item["evidence_sha256"]:
            _error("batch evidence file is missing or changed")
        try:
            evidence_by_item[key] = path.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            _error("batch evidence files must be UTF-8 text")
            raise AssertionError("unreachable") from exc
    current_preview = _batch_preview(proposal)
    current_items = [dict(item) for item in proposal["items"]]
    team_key, bindings = _batch_subject_bindings(current_preview, current_items)
    if team_key != proposal.get("team_key") or bindings != envelope.get("subject_bindings"):
        _error("batch source-row binding changed after review")
    expected_downstream = {
        key: proposal[key] for key in _batch_downstream_binding(current_preview)
    }
    if expected_downstream != _batch_downstream_binding(current_preview):
        _error("batch correction-set or downstream preview binding changed")
    reviewer = _required_text(args, "reviewer")
    params = SqlParams()
    run_sql(
        "select audit.apply_row_correction_batch_v8("
        f"{params.jsonb(proposal)}, {params.jsonb(evidence_by_item)}, "
        f"{params.text(reviewer)})",
        params.values,
    )
    candidate = _pending_batch_candidate(proposal_hash, clean_text(str(proposal["season"])))
    unchanged_count, no_dashboard_impact = _validate_pending_candidate_hashes(candidate)
    print(json.dumps({
        "status": "correction_batch_applied_no_dashboard_impact" if no_dashboard_impact else "correction_batch_applied",
        "season": proposal["season"],
        "item_count": len(proposal["items"]),
        "proposal_hash": proposal_hash,
        "draft_bundle_sha256": candidate.get("draft_bundle_sha256"),
        "unchanged_team_count": unchanged_count,
        "promotion_required": True,
    }, indent=2))


def _pending_candidate(proposal_hash: str, season: str) -> dict[str, Any]:
    params = SqlParams()
    rows = query_sql(
        "select to_jsonb(candidate) as candidate "
        "from analysis.row_correction_pending_candidate_data_v2("
        f"{params.text(season)}) candidate "
        f"where candidate.season = {params.text(season)} "
        f"and candidate.proposal_hash = {params.text(proposal_hash)}",
        params.values,
    )
    if len(rows) != 1 or not isinstance(rows[0].get("candidate"), dict):
        _error("database has no unique pending candidate for this proposal")
    return rows[0]["candidate"]


def _candidate_has_no_dashboard_impact(candidate: dict[str, Any]) -> bool:
    predecessor = candidate.get("predecessor_bundle")
    draft_bundle_sha256 = clean_text(str(candidate.get("draft_bundle_sha256") or ""))
    predecessor_sha256 = (
        clean_text(str(predecessor.get("bundle_sha256") or ""))
        if isinstance(predecessor, dict)
        else ""
    )
    if not _SHA256.fullmatch(draft_bundle_sha256) or not _SHA256.fullmatch(predecessor_sha256):
        _error("pending candidate has incomplete bundle hash evidence")
    return draft_bundle_sha256 == predecessor_sha256


def _validate_pending_candidate_hashes(candidate: dict[str, Any]) -> tuple[int, bool]:
    unchanged = candidate.get("unchanged_team_hashes")
    if not isinstance(unchanged, list) or len(unchanged) not in {15, 16}:
        _error("pending candidate must prove 15 reused teams or 16 unchanged teams")
    if any(
        not isinstance(row, dict)
        or not clean_text(str(row.get("team_key") or ""))
        or not _SHA256.fullmatch(clean_text(str(row.get("payload_sha256") or "")))
        for row in unchanged
    ):
        _error("pending candidate has invalid unchanged team hash evidence")
    no_dashboard_impact = _candidate_has_no_dashboard_impact(candidate)
    expected_count = 16 if no_dashboard_impact else 15
    if len(unchanged) != expected_count:
        _error("pending candidate changed-team count contradicts its bundle hash")
    return len(unchanged), no_dashboard_impact


def _rollback_details(
    args: argparse.Namespace, *, target_release_label: str, prefix: str = ""
) -> dict[str, str]:
    def field(name: str) -> str:
        if prefix:
            return f"{prefix}{name}"
        return "rollback_release_label" if name == "release_label" else name

    rollback_release_label = _required_text(args, field("release_label"))
    if rollback_release_label == target_release_label:
        _error("rollback release label must differ from the target release label")
    _, evidence_sha256 = _verified_evidence(args, field("evidence_file"))
    operator = _required_text(args, field("operator"))
    provenance = _audit_provenance(operator)
    return {
        "target_release_label": target_release_label,
        "rollback_release_label": rollback_release_label,
        "reviewer": _required_text(args, field("reviewer")),
        "reason": _required_text(args, field("reason")),
        "evidence_sha256": evidence_sha256,
        "operator": operator,
        "code_version": provenance["code_version"],
        "dependency_lock_hash": provenance["dependency_lock_hash"],
    }


def _run_correction_rollback(
    details: dict[str, str], *, automatic_recovery: bool = False
) -> None:
    params = SqlParams()
    rollback_function = (
        "reporting.rollback_row_correction_bundle_recovery_v2"
        if automatic_recovery
        else "reporting.rollback_row_correction_bundle_v1"
    )
    run_sql(
        f"select {rollback_function}("
        f"{params.text(details['target_release_label'])}, "
        f"{params.text(details['rollback_release_label'])}, "
        f"{params.text(details['reviewer'])}, "
        f"{params.text(details['reason'])}, "
        f"{params.text(details['evidence_sha256'])}, "
        f"{params.text(details['operator'])}, "
        f"{params.text(details['code_version'])}, "
        f"{params.text(details['dependency_lock_hash'])})",
        params.values,
    )


def _assert_release_label_available(release_label: str, purpose: str) -> None:
    params = SqlParams()
    rows = query_sql(
        "select exists ("
        "select 1 from reporting.aggregate_releases release "
        f"where release.release_label = {params.text(release_label)}"
        ") as occupied",
        params.values,
    )
    if len(rows) != 1 or rows[0].get("occupied") is not False:
        _error(f"{purpose} release label is already in use")


def _promoted_release_identity(
    *, season: str, release_label: str, expected_bundle_sha256: str
) -> str:
    params = SqlParams()
    rows = query_sql(
        "select context.release_id::text as release_id, "
        "analysis.row_correction_bundle_hash_v1(context.release_id) as bundle_sha256 "
        "from reporting.dashboard_bundle_context_v1 context "
        "join reporting.aggregate_releases release on release.id = context.release_id "
        f"where context.season = {params.text(season)} "
        f"and release.release_label = {params.text(release_label)} "
        "and release.status = 'approved'",
        params.values,
    )
    if len(rows) != 1:
        _error("promoted correction is not the unique approved release")
    release_id = clean_text(str(rows[0].get("release_id") or ""))
    bundle_sha256 = clean_text(str(rows[0].get("bundle_sha256") or ""))
    if not release_id or bundle_sha256 != expected_bundle_sha256:
        _error("promoted release identity or bundle hash differs from reviewed candidate")
    return release_id


def _refresh_promoted_exports(
    *, season: str, release_label: str, candidate: dict[str, Any]
) -> None:
    expected_bundle = candidate.get("bundle")
    expected_bundle_sha256 = clean_text(str(candidate.get("draft_bundle_sha256") or ""))
    if not isinstance(expected_bundle, dict) or not _SHA256.fullmatch(expected_bundle_sha256):
        _error("pending candidate has no exact bundle for release closeout")
    assert_public_payload_is_publishable(expected_bundle, "correction release candidate")
    release_id = _promoted_release_identity(
        season=season,
        release_label=release_label,
        expected_bundle_sha256=expected_bundle_sha256,
    )
    write_team_dashboard_parity_exports(
        season,
        expected_release_label=release_label,
        expected_release_id=release_id,
        expected_bundle=expected_bundle,
    )


def _refresh_current_exports_after_rollback(season: str) -> None:
    bundle, metadata = _current_correction_aware_bundle_snapshot(season)
    write_team_dashboard_parity_exports(
        season,
        expected_release_label=clean_text(str(metadata["release_label"])),
        expected_release_id=clean_text(str(metadata["release_id"])),
        expected_bundle=bundle,
    )


def correction_apply(args: argparse.Namespace) -> None:
    _assert_legacy_v2_is_available()
    proposal, stored_hash, _, envelope = _read_proposal(getattr(args, "proposal_file", ""))
    canonical_hash = _proposal_hash(proposal)
    if canonical_hash != stored_hash:
        _error("proposal file hash does not match its canonical database hash")
    evidence_path = Path(clean_text(str(getattr(args, "evidence_file", "") or envelope.get("evidence_file") or "")))
    if not evidence_path.is_file():
        _error("evidence file for proposal is not available")
    if hashlib.sha256(evidence_path.read_bytes()).hexdigest() != proposal["evidence_sha256"]:
        _error("evidence file hash differs from the proposal")
    stored_binding = envelope.get("subject_binding")
    current_preview = _preview(proposal)
    current_binding = _proposal_preview_binding(
        current_preview, proposal["source_row_id"]
    )
    expected_binding = {
        key: proposal[key]
        for key in current_binding
    }
    if stored_binding != {
        "source_row_sha256": proposal["source_row_sha256"],
        "row_fingerprint": proposal["row_fingerprint"],
    }:
        _error("proposal envelope source binding is inconsistent")
    if expected_binding != current_binding:
        _error("source-row, correction-set, or downstream preview binding changed")
    # The evidence text is deliberately passed only to the audited SQL
    # procedure. It is never emitted to the terminal or written into Git.
    try:
        evidence_text = evidence_path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        _error("evidence file must be UTF-8 text for the audited apply procedure")
        raise AssertionError("unreachable") from exc
    reviewer = _required_text(args, "reviewer")
    params = SqlParams()
    run_sql(
        "select audit.apply_row_correction_v2("
        f"{params.jsonb(proposal)}, {params.text(evidence_text)}, "
        f"{params.text(reviewer)})",
        params.values,
    )
    candidate = _pending_candidate(canonical_hash, clean_text(str(proposal["season"])))
    candidate_hash = clean_text(str(candidate.get("proposal_hash") or ""))
    if candidate_hash != canonical_hash:
        _error("applied correction is not bound to the pending candidate proposal hash")
    correction_set_hash = clean_text(str(candidate.get("correction_set_hash") or ""))
    draft_bundle_hash = clean_text(str(candidate.get("draft_bundle_sha256") or ""))
    if not _SHA256.fullmatch(correction_set_hash) or not _SHA256.fullmatch(draft_bundle_hash):
        _error("applied correction has incomplete stored set or draft bundle hash")
    no_dashboard_impact = _candidate_has_no_dashboard_impact(candidate)
    print(json.dumps({
        "status": (
            "correction_applied_no_dashboard_impact"
            if no_dashboard_impact else "correction_applied"
        ),
        "season": proposal["season"],
        "proposal_hash": canonical_hash,
        "correction_set_hash": correction_set_hash,
        "draft_bundle_sha256": draft_bundle_hash,
        "metric_change_detected": not no_dashboard_impact,
        "promotion_required": True,
        "release_required": True,
    }, indent=2))


def correction_release(args: argparse.Namespace) -> None:
    """Promote, then recover if the exact release-bound parity closeout fails."""
    _assert_legacy_v2_is_available()
    preflight = bool(getattr(args, "preflight", False))
    preflight_file = clean_text(str(getattr(args, "preflight_file", "") or ""))
    reviewer = clean_text(str(getattr(args, "reviewer", "") or ""))
    release_label = clean_text(str(getattr(args, "release_label", "") or ""))
    if preflight and preflight_file:
        _error("--preflight cannot be combined with --preflight-file")
    if preflight:
        output = _require_private_output(getattr(args, "output", ""), "output")
        proposal, proposal_hash, _, _ = _read_proposal(getattr(args, "proposal_file", ""))
        if _proposal_hash(proposal) != proposal_hash:
            _error("proposal file hash does not match its canonical database hash")
        candidate = _pending_candidate(proposal_hash, clean_text(str(proposal["season"])))
        unchanged_count, no_dashboard_impact = _validate_pending_candidate_hashes(candidate)
        public_candidate = dict(candidate)
        if "subject" in public_candidate:
            public_candidate["subject"] = _public_subject(public_candidate["subject"])
        public_candidate["unchanged_team_hashes"] = candidate["unchanged_team_hashes"]
        write_json_atomic(output, {
            "schema_version": "urc_row_correction_release_preflight_v1",
            "proposal_hash": proposal_hash,
            "season": proposal["season"],
            "candidate": public_candidate,
        })
        print(json.dumps({
            "status": "correction_release_preflight",
            "season": proposal["season"],
            "proposal_hash": proposal_hash,
            "output_path": str(output),
            "draft_bundle_sha256": candidate.get("draft_bundle_sha256"),
            "metric_change_detected": not no_dashboard_impact,
            "promotion_required": True,
            "release_required": True,
            "unchanged_team_count": unchanged_count,
        }, indent=2))
        return
    if not preflight_file or not reviewer or not release_label:
        _error("promotion requires --preflight-file, --reviewer, and --release-label")
    reviewed_path = Path(preflight_file)
    reviewed = _read_json_file(reviewed_path, "release preflight file")
    if not isinstance(reviewed, dict):
        _error("release preflight file must contain an object")
    proposal_hash = clean_text(str(reviewed.get("proposal_hash") or ""))
    if reviewed.get("schema_version") != "urc_row_correction_release_preflight_v1" or not _SHA256.fullmatch(proposal_hash):
        _error("release preflight file is not a valid correction preflight")
    candidate = reviewed.get("candidate")
    if not isinstance(candidate, dict):
        _error("release preflight file does not prove 15 unchanged team hashes")
    _validate_pending_candidate_hashes(candidate)
    season = clean_text(str(reviewed.get("season") or ""))
    if not season:
        _error("release preflight file has no season")
    current_candidate = _pending_candidate(proposal_hash, season)
    public_current = dict(current_candidate)
    if "subject" in public_current:
        public_current["subject"] = _public_subject(public_current["subject"])
    _validate_pending_candidate_hashes(public_current)
    if diff_json_documents(candidate, public_current):
        _error("pending correction candidate changed after preflight")
    rollback = _rollback_details(
        args, target_release_label=release_label, prefix="rollback_"
    )
    _assert_release_label_available(release_label, "correction promotion")
    _assert_release_label_available(
        rollback["rollback_release_label"], "automatic rollback"
    )
    params = SqlParams()
    run_sql(
        "select reporting.promote_row_correction_v2("
        f"{params.text(proposal_hash)}, {params.text(reviewer)}, {params.text(release_label)})",
        params.values,
    )
    try:
        _refresh_promoted_exports(
            season=season, release_label=release_label, candidate=current_candidate
        )
    except BaseException:
        try:
            # The recovery-only successor allocates a UUID-suffixed label if a
            # concurrent release claimed the reviewed rollback label after
            # preflight. Explicit rollback retains exact-label V1 semantics.
            _run_correction_rollback(rollback, automatic_recovery=True)
        except BaseException as rollback_exc:
            raise RuntimeError(
                "correction promotion succeeded but parity closeout failed and "
                "the recorded predecessor rollback also failed"
            ) from rollback_exc
        try:
            _refresh_current_exports_after_rollback(season)
        except BaseException as refresh_exc:
            raise RuntimeError(
                "correction promotion was rolled back after parity closeout "
                "failed, but restored parity exports could not be refreshed"
            ) from refresh_exc
        raise
    print(json.dumps({
        "status": "correction_released",
        "proposal_hash": proposal_hash,
        "release_label": release_label,
    }, indent=2))


def correction_batch_release(args: argparse.Namespace) -> None:
    """Preflight or promote one immutable same-team correction batch."""
    preflight = bool(getattr(args, "preflight", False))
    preflight_file = clean_text(str(getattr(args, "preflight_file", "") or ""))
    if preflight and preflight_file:
        _error("--preflight cannot be combined with --preflight-file")
    if preflight:
        output = _require_private_output(getattr(args, "output", ""), "output")
        proposal, _, _ = _read_batch_proposal(getattr(args, "proposal_file", ""))
        proposal_hash = clean_text(str(proposal["proposal_hash"]))
        if _proposal_hash(proposal) != proposal_hash:
            _error("batch proposal hash does not match its canonical database hash")
        candidate = _pending_batch_candidate(
            proposal_hash, clean_text(str(proposal["season"]))
        )
        unchanged_count, no_dashboard_impact = _validate_pending_candidate_hashes(candidate)
        write_json_atomic(output, {
            "schema_version": "urc_row_correction_batch_release_preflight_v3",
            "proposal_hash": proposal_hash,
            "season": proposal["season"],
            "item_count": len(proposal["items"]),
            "candidate": candidate,
        })
        print(json.dumps({
            "status": "correction_batch_release_preflight",
            "season": proposal["season"],
            "item_count": len(proposal["items"]),
            "proposal_hash": proposal_hash,
            "output_path": str(output),
            "draft_bundle_sha256": candidate.get("draft_bundle_sha256"),
            "metric_change_detected": not no_dashboard_impact,
            "unchanged_team_count": unchanged_count,
        }, indent=2))
        return

    reviewer = _required_text(args, "reviewer")
    release_label = _required_text(args, "release_label")
    reviewed = _read_json_file(Path(preflight_file), "batch release preflight file")
    if not isinstance(reviewed, dict) or reviewed.get("schema_version") != "urc_row_correction_batch_release_preflight_v3":
        _error("batch release preflight file has an invalid schema")
    proposal_hash = clean_text(str(reviewed.get("proposal_hash") or ""))
    season = clean_text(str(reviewed.get("season") or ""))
    candidate = reviewed.get("candidate")
    if not _SHA256.fullmatch(proposal_hash) or not season or not isinstance(candidate, dict):
        _error("batch release preflight is incomplete")
    _validate_pending_candidate_hashes(candidate)
    current_candidate = _pending_batch_candidate(proposal_hash, season)
    _validate_pending_candidate_hashes(current_candidate)
    if diff_json_documents(candidate, current_candidate):
        _error("pending correction batch changed after preflight")
    rollback = _rollback_details(
        args, target_release_label=release_label, prefix="rollback_"
    )
    _assert_release_label_available(release_label, "correction batch promotion")
    _assert_release_label_available(
        rollback["rollback_release_label"], "automatic rollback"
    )
    params = SqlParams()
    run_sql(
        "select reporting.promote_row_correction_batch_v8("
        f"{params.text(proposal_hash)}, {params.text(reviewer)}, "
        f"{params.text(release_label)})",
        params.values,
    )
    try:
        _refresh_promoted_exports(
            season=season, release_label=release_label, candidate=current_candidate
        )
    except BaseException:
        try:
            _run_correction_rollback(rollback, automatic_recovery=True)
        except BaseException as rollback_exc:
            raise RuntimeError(
                "correction batch promotion succeeded but parity closeout failed "
                "and predecessor rollback also failed"
            ) from rollback_exc
        try:
            _refresh_current_exports_after_rollback(season)
        except BaseException as refresh_exc:
            raise RuntimeError(
                "correction batch promotion was rolled back, but restored parity "
                "exports could not be refreshed"
            ) from refresh_exc
        raise
    print(json.dumps({
        "status": "correction_batch_released",
        "proposal_hash": proposal_hash,
        "release_label": release_label,
    }, indent=2))


def correction_rollback(args: argparse.Namespace) -> None:
    """Call reporting.rollback_row_correction_bundle_v1 through run_sql and
    refresh exports from the exact restored bundle.
    """
    release_label = _required_text(args, "release_label")
    details = _rollback_details(args, target_release_label=release_label)
    _run_correction_rollback(details)
    season_params = SqlParams()
    rows = query_sql(
        "select context.season "
        "from reporting.aggregate_releases release "
        "join reporting.dashboard_bundle_context_v1 context "
        "on context.release_id = release.id "
        f"where release.release_label = {season_params.text(release_label)}",
        season_params.values,
    )
    if len(rows) != 1 or not clean_text(str(rows[0].get("season") or "")):
        _error("rolled-back correction release has no unique season")
    _refresh_current_exports_after_rollback(
        clean_text(str(rows[0]["season"]))
    )
    print(json.dumps({"status": "correction_rollback_promoted", "release_label": release_label}, indent=2))
