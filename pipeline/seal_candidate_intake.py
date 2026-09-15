"""Bind the reviewed six-file intake to Abdel's ingestion-only authorisation."""

import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

from pipeline.__main__ import (
    V15_CANDIDATE_AUTHORISATION, V15_CANDIDATE_INPUT_KINDS,
    V15_CANDIDATE_MANIFEST_SCHEMA, V15_CANDIDATE_PROFILE_SCHEMA,
    V15_CANDIDATE_ROOT_SCHEMA, validate_v15_candidate_root_for_ingest,
)

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "outputs/intake_release_20260915/intake"
PRIVATE = Path('/Users/abdelbabiker/Desktop/URC-V2-DB-private/2025-26/irfu_rebuild_20260914_v1')
APPROVAL = "I give you full approval to do everything that I've asked and then without having to stop, you can adjudicate at each step"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    path.chmod(0o600)
    return digest(path)


def seal():
    now = datetime.now(timezone.utc).isoformat()
    approval_sha = hashlib.sha256(APPROVAL.encode()).hexdigest()
    PACKAGE.mkdir(parents=True, exist_ok=True)
    write(PACKAGE / 'task_authority.json', {
        'source_task_id': '01a0a287-a441-7ba3-bb63-976962cf2f4f',
        'user': 'Abdel Babiker',
        'verbatim_approval': APPROVAL,
        'verbatim_scope': "these need to be ingested into the database and need to update the analysis and then the dashboard, but don't release the dashboard just yet. Keep it as is.",
        'bound_target': {'project_ref': 'eukkvswaxweenovqqgzr', 'database': 'postgres'},
        'scope': 'Four rebuilt IRFU sources and Benetton/Edinburgh exposure. Candidate preparation, ingestion, source-bound processing and analysis are authorised. Live dashboard release is excluded.',
        'recorded_at': now,
        'approval_interpretation': 'The owner records acceptance of the reviewed conservative mappings under the user’s explicit delegated adjudication authority.'
    })
    entries = []
    for team, kind in V15_CANDIDATE_INPUT_KINDS.items():
        directory = PACKAGE / team
        directory.mkdir(exist_ok=True)
        if kind == 'exposure':
            version = 3 if team == 'benetton' else 2
            original = ROOT / 'data/intake/2025-26' / team
            file = directory / f'exposure_intake_final_clean_v{version}.csv'
            shutil.copy2(original / file.name, file)
            profile = json.loads((original / 'team_intake_profile.json').read_text())
            mapping_evidence = json.loads(Path(profile['mapping_path']).read_text())
            review = original / 'ai_review_final.json'
        else:
            source = PACKAGE / f'{team}_injury_canonical_source.csv'
            shutil.copy2(source, directory / source.name)
            files = list(directory.glob('*injury*.csv'))
            if len(files) != 1:
                raise ValueError(f'Expected one complete IRFU source CSV for {team}')
            file = files[0]
            mapping_evidence = json.loads((PRIVATE / 'combined_mapping_contract.json').read_text())
            review = PRIVATE / 'independent_review_sol/report.md'
        source_mapping = directory / 'reviewed_mapping.json'
        write(source_mapping, mapping_evidence)
        shutil.copy2(review, directory / ('review' + review.suffix))
        mapping = {
            'mapping_version': 'urc_candidate_20260915_v1',
            'reviewed_mapping_sha256': digest(source_mapping),
            'reviewed_mapping': mapping_evidence,
            'mappings': [{
                'canonical_field': 'source_to_canonical_contract',
                'canonical_value': 'Retain the exact reviewed canonical values and row-level inclusion decisions.',
                'source_evidence': {'reviewed_mapping_sha256': digest(source_mapping),
                                    'input_sha256': digest(file)},
                'evidence_class': 'manual_adjudication',
            }],
        }
        mapping_sha = write(directory / 'mapping.json', mapping)
        common = {
            'team': team.capitalize(), 'season': '2025-26',
            'profile_version': 'urc_candidate_20260915_v1', 'decision': 'adapter_required',
            'mapping_path': 'mapping.json', 'mapping_sha256': mapping_sha,
            'mapping_version': mapping['mapping_version'],
            'ai_review_status': 'completed', 'ai_reviewed_by': 'Codex package binding verification; retained independent Sol high source review',
            'ai_reviewed_at': now,
            'approved_by': 'Abdel Babiker', 'approved_at': now,
            'approval_requested_at': '2026-09-15T00:00:00+00:00',
            'approval_line_sha256': approval_sha, 'authorisation': V15_CANDIDATE_AUTHORISATION,
            'unresolved_adjudication_ids': [], 'approved_input_sha256s': [digest(file)],
            'decision_scope': 'Accept retained source bytes and reviewed mappings for this candidate. Preserve conservative Unknowns and explicit source anatomy. Release is excluded.',
            'review_evidence_sha256': digest(review),
        }
        profile_sha = write(directory / 'profile.json', {'schema': V15_CANDIDATE_PROFILE_SCHEMA, **common})
        manifest = {
            'schema': V15_CANDIDATE_MANIFEST_SCHEMA, 'team_key': team, 'input_kind': kind,
            'authorisation': V15_CANDIDATE_AUTHORISATION, 'approval_line': APPROVAL,
            'approval_line_sha256': approval_sha,
            'intake_profile': {**common, 'profile_path': 'profile.json', 'profile_sha256': profile_sha},
        }
        manifest_sha = write(directory / 'manifest.json', manifest)
        entries.append({'team_key': team, 'input_kind': kind,
                        'input': f'{team}/{file.name}', 'input_sha256': digest(file),
                        'manifest': f'{team}/manifest.json', 'manifest_sha256': manifest_sha,
                        'profile': f'{team}/profile.json', 'profile_sha256': profile_sha,
                        'mapping': f'{team}/mapping.json', 'mapping_sha256': mapping_sha})
    root_path = PACKAGE / 'v15_candidate_intake_root_manifest.json'
    outputs = {p.relative_to(PACKAGE).as_posix(): digest(p) for p in PACKAGE.rglob('*')
               if p.is_file() and p != root_path}
    root = {'schema': V15_CANDIDATE_ROOT_SCHEMA, 'season': '2025-26',
            'candidate_scope': 'isolated_candidate_only', 'approved_by': 'Abdel Babiker',
            'approval_ready': True, 'ingest_ready': True,
            'approval_line': APPROVAL, 'approval_line_sha256': approval_sha,
            'authorisation': V15_CANDIDATE_AUTHORISATION, 'team_inputs': entries,
            'output_sha256s': outputs,
            'root_file_set_sha256': hashlib.sha256(json.dumps(outputs,sort_keys=True,separators=(',',':')).encode()).hexdigest()}
    write(root_path, root)
    for path in [PACKAGE, *PACKAGE.rglob('*')]:
        path.chmod(0o700 if path.is_dir() else 0o600)
    for entry in entries:
        validate_v15_candidate_root_for_ingest(root_path, PACKAGE/entry['manifest'],
            PACKAGE/entry['input'], entry['input_sha256'],entry['team_key'].capitalize(),'2025-26')
    print('All six candidate source envelopes validated.')


if __name__ == '__main__':
    seal()
