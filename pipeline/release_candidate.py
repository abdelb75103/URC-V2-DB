"""Prepare an isolated, source-bound dashboard candidate without activating it."""

from __future__ import annotations

import argparse
from collections import Counter
import csv
import hashlib
import json
import re
import unicodedata
from pathlib import Path

SCHEMA = "urc_candidate_20260915"
IRFU = {"leinster", "munster", "ulster", "connacht"}

IRFU_EXISTING_FAMILY_ALIASES = {
    "Hamstring strain": ("dx_hamstring_muscle_injury_f003473b56", "Hamstring muscle injury", 10),
    "Soleus Injury/ strain": ("dx_soleus_injury_5b8a0d0266", "Soleus injury", 8),
    "Ankle Pain/ Injury not otherwsie specified": ("dx_ankle_pain_de6b615afc", "Ankle pain", 6),
    "Ankle syndesmosis sprain": ("dx_ankle_syndesmosis_injury_757bf42431", "Ankle syndesmosis injury", 5),
    "Ankle lateral ligament sprain": ("dx_lateral_ankle_ligament_injury_d9a611a9cb", "Lateral ankle ligament injury", 5),
    "Calf/ gastroc haematoma": ("dx_calf_contusion_haematoma_1ed62efd4d", "Calf contusion/haematoma", 5),
    "Bruising/ haematoma iliac crest/ glut medius": ("dx_buttock_contusion_46ae636fd7", "Buttock contusion", 4),
    "Midfoot joint/ ligament sprain": ("dx_midfoot_injury_3332895405", "Midfoot injury", 4),
    "Ankle deltoid ligament sprain": ("dx_medial_ankle_ligament_injury_9add2aecee", "Medial ankle ligament injury", 4),
    "Calf muscle trigger points/ spasm": ("dx_gastrocnemius_trigger_points_spasm_0e2bdaca3b", "Gastrocnemius trigger points/spasm", 3),
    "ATFL/ CFL sprain": ("dx_lateral_ankle_ligament_injury_d9a611a9cb", "Lateral ankle ligament injury", 3),
    "Patellar tendinopathy (excl. Sinding Larsen Johannson syndrome see JTKP)": ("dx_patellar_tendon_injury_91ccd5f25c", "Patellar tendon injury", 3),
    "Thigh Soft Tissue Bruising/ Haematoma": ("dx_thigh_contusion_haematoma_6e95bc71b4", "Thigh contusion/haematoma", 3),
    "Wrist sprain/ jarring (radiocarpal joint)": ("dx_wrist_injury_d94414e2c6", "Wrist injury", 3),
    "Hand bruising/ haematoma": ("dx_hand_muscle_contusion_or_haematoma_1d004bb885", "Hand muscle contusion or haematoma", 3),
    "MCL injury knee": ("dx_mcl_injury_4a1ba1d5c9", "MCL injury", 3),
    "Hip and groin muscle spasm/ trigger points": ("dx_hip_and_groin_muscle_injury_7ccd814142", "Hip and groin muscle injury", 3),
    "Elbow medial ligament injury": ("dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6", "Elbow ulnar collateral ligament injury", 2),
    "Pectoralis major muscle injury": ("dx_pectoralis_major_injury_ae7aff3738", "Pectoralis major injury", 2),
    "Shoulder Soft Tissue Bruising/ Haematoma": ("dx_shoulder_muscle_contusion_7c8bce0320", "Shoulder muscle contusion", 2),
    "Hip and Groin Soft Tissue Bruising/ Haematoma": ("dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9", "Hip or groin soft tissue contusion or haematoma", 2),
    "Cervical nerve root compression/ stretch (proximal burner/ stinger)": ("dx_cervical_nerve_root_injury_fc81174c9d", "Cervical nerve root injury", 2),
    "Thumb MCP joint sprain (incl radial and ulnar collat ligs)": ("dx_thumb_mcp_injury_2b5c0aa20c", "Thumb MCP injury", 2),
    "Sprain of 1st MTP joint/ turf toe": ("dx_first_mtp_joint_sprain_3d3547b2db", "First MTP joint sprain", 2),
    "Adductor strain": ("dx_adductor_muscle_injury_97164c9b14", "Adductor muscle injury", 2),
    "Fracture lesser toes (2 - 5)": ("dx_foot_phalanx_fracture_674038ca61", "Foot phalanx fracture", 2),
    "Acute Shoulder Sprains/ Subluxation": ("dx_shoulder_joint_injury_28bd49eadd", "Shoulder joint injury", 2),
    "Cauliflower Ear ( Acute)": ("dx_cauliflower_ear_d6361b8000", "Cauliflower ear", 2),
    "Head / Facial Bruising/ Haematoma": ("dx_head_and_facial_contusion_74a20a767e", "Head and facial contusion", 2),
    "Cervical Spine Facet Joint injuries": ("dx_cervical_facet_joint_disorder_c3699c58d7", "Cervical facet joint disorder", 1),
    "Quadriceps Strain": ("dx_quadriceps_injury_82f2a4c482", "Quadriceps injury", 1),
    "Peroneal tendinopathy": ("dx_peroneal_injury_b0c8606ad2", "Peroneal injury", 1),
    "Adductor trigger points": ("dx_proximal_adductor_trigger_points_e0737a9324", "Proximal adductor trigger points", 1),
    "Head Pain/ Injury Not Otherwise Specified (Including headache)": ("dx_head_injury_unspecified_611d184685", "Head injury, unspecified", 1),
    "Wrist and Hand Soft Tissue Bruising/ Haematoma": ("dx_wrist_contusion_e9973933b6", "Wrist contusion", 1),
    "Quadriceps Soft Tissue Dysfunction": ("dx_quadriceps_injury_82f2a4c482", "Quadriceps injury", 1),
    "Tibialis posterior injuries": ("dx_tibialis_posterior_tendon_injury_8ddfcac54e", "Tibialis posterior tendon injury", 1),
    "Plantar fasciitis strain": ("dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b", "Plantar heel pain/fasciopathy", 1),
    "Achilles tendon injury": ("dx_achilles_tendon_injury_6983aa352e", "Achilles tendon injury", 1),
    "Maxillary fracture": ("dx_head_or_facial_fracture_3497d30cee", "Head or facial fracture", 1),
    "Triangular fibrocartilage complex tear": ("dx_wrist_fibrocartilage_injury_fddc60c8f6", "Wrist fibrocartilage injury", 1),
    "Acute PCL injury": ("dx_pcl_injury_4986df0532", "PCL injury", 1),
    "Lateral meniscal cyst": ("dx_meniscal_injury_b166306f7d", "Meniscal injury", 1),
    "Dental Injury": ("dx_dental_injury_b97b2afe75", "Dental injury", 1),
    "Other wrist pain NOS": ("dx_wrist_or_hand_pain_57c9958c78", "Wrist or hand pain", 1),
    "Post shoulder stabilisation": ("dx_postoperative_shoulder_condition_ee7c38fb4d", "Postoperative shoulder condition", 1),
    "Medial femoral condyle osteochondral injury": ("dx_knee_cartilage_injury_761df482b3", "Knee cartilage injury", 1),
    "Hip Joint Sprain": ("dx_hip_joint_sprain_6ee81972bd", "Hip joint sprain", 1),
    "Sprain 1st MTP jt with volar plate rupture": ("dx_first_mtp_joint_sprain_3d3547b2db", "First MTP joint sprain", 1),
    "Femoral Acetabular Impingment of hip joint": ("dx_femoroacetabular_impingement_76f8c7b5bc", "Femoroacetabular impingement", 1),
    "Bennett's fracture thumb - base 1st MC": ("dx_metacarpal_fracture_1e117e3ddc", "Metacarpal fracture", 1),
    "Adductor longus tendinopathy": ("dx_adductor_tendon_injury_ae39245d15", "Adductor tendon injury", 1),
    "Lateral hamstring tendinopathy": ("dx_hamstring_tendon_injury_f86b1dad5b", "Hamstring tendon injury", 1),
    "Wrist and Hand Joint Injury": ("dx_wrist_injury_d94414e2c6", "Wrist injury", 1),
    "Cervical facet joint arthritis": ("dx_cervical_facet_joint_disorder_c3699c58d7", "Cervical facet joint disorder", 1),
    "Foot Soft Tissue Bruising/ Haematoma": ("dx_foot_contusion_6c8a5bb721", "Foot contusion", 1),
    "Hip flexor muscle strain/ tear": ("dx_hip_flexor_injury_cedda9fa03", "Hip flexor injury", 1),
    "Acute Shoulder Dislocation": ("dx_shoulder_dislocation_2067688fdd", "Shoulder dislocation", 1),
    "Lumbar pain undiagnosed": ("dx_lumbar_spine_pain_2022547a07", "Lumbar spine pain", 1),
    "Knee Soft Tissue Bruising/ Haematoma": ("dx_knee_contusion_94058fe1a4", "Knee contusion", 1),
    "Shin laceration/ abrasion": ("dx_shin_abrasion_c327f2dfa3", "Shin abrasion", 1),
    "Dislocation of PIP or DIP joint(s) ": ("dx_finger_joint_dislocation_fa50126b94", "Finger joint dislocation", 1),
    "Knee cartilage injury with loose bodies": ("dx_knee_cartilage_injury_761df482b3", "Knee cartilage injury", 1),
    "Other Wrist and Hand Pain/ Injury not otherwise specified": ("dx_other_wrist_injury_not_otherwise_specified_9b197015b7", "Other Wrist Injury not otherwise specified", 1),
    "Nasal fracture": ("dx_nasal_fracture_a291a11f04", "Nasal fracture", 1),
    "Thumb CMC jt sprain": ("dx_thumb_cmc_joint_sprain_01a9a8af0e", "Thumb CMC joint sprain", 1),
    "1st MCP joint instability": ("dx_thumb_mcp_injury_2b5c0aa20c", "Thumb MCP injury", 1),
    "Dislocation of IP joint thumb": ("dx_thumb_ip_dislocation_a325ccd91d", "Thumb IP dislocation", 1),
    "Hamstring trigger points": ("dx_hamstring_cramp_spasm_ab47d7d2d7", "Hamstring cramp/spasm", 1),
}

IRFU_IDENTITY_LABELS = {
    "Anterior shin periostitis/ stress syndrome/ shin splints",
    "Finger joint sprain (PIP and DIP joints)",
    "Elbow Structural Abnormality",
    "Genitofemoral nerve entrapment",
    "Osteitis Pubis",
    "Popliteal artery entrapment",
    "Thoracic Outlet Syndrome",
}


def normalise_label(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", unicodedata.normalize("NFKC", value).casefold())


def stable_family_code(label: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", label.lower()).strip("_")[:64] or "diagnosis"
    digest = hashlib.sha256(normalise_label(label).encode()).hexdigest()[:10]
    return f"dx_{slug}_{digest}"


def irfu_diagnosis_mappings(directory: Path) -> list[dict[str, object]]:
    repo = Path(__file__).resolve().parents[1]
    evidence_path = repo / "docs/evidence/diagnosis-families/diagnosis_family_adjudication_v1.json"
    evidence = json.loads(evidence_path.read_text())
    families = json.loads((directory / "analysis_sources.json").read_text())[0]["sources"]["families"]
    inherited: dict[str, tuple[str, str]] = {}
    conflicting_keys: set[str] = set()
    accepted_families: set[tuple[str, str]] = set()
    for row in [*families, *evidence["rows"]]:
        label = row.get("source_label") or row.get("specific_diagnosis_source_label")
        code = row.get("family_code") or row.get("diagnosis_group_code")
        family_label = row.get("family_label") or row.get("diagnosis_group_label")
        if not label or not code or family_label == "Unknown diagnosis":
            continue
        if row.get("problem_type_scope") == "mixed" or row.get("row_filter_required"):
            continue
        if row in evidence["rows"] and not row.get("injury_metric_eligible"):
            continue
        family = (code, family_label)
        accepted_families.add(family)
        key = normalise_label(label)
        if key in conflicting_keys:
            continue
        if key in inherited and inherited[key] != family:
            inherited.pop(key)
            conflicting_keys.add(key)
            continue
        inherited[key] = family
    if any(alias[:2] not in accepted_families for alias in IRFU_EXISTING_FAMILY_ALIASES.values()):
        raise ValueError("an IRFU alias points to a diagnosis family that is not already accepted")

    mappings: list[dict[str, object]] = []
    for team in sorted(IRFU):
        source = directory / "intake" / team / f"{team}_injury_canonical_source.csv"
        with source.open(encoding="utf-8-sig", newline="") as stream:
            for row in csv.DictReader(stream):
                if (row["candidate_disposition"] != "candidate_included_pending_profile_approval"
                        or row["Problem type"] != "Injury"):
                    continue
                source_label = (row["Specific Diagnosis"] or row["Diagnosis"]).strip()
                pathology = row["Injury Tissue Type/s"].strip()
                body = row["Body Part"].strip()
                osics10 = row["Orchard Code"].strip().upper()
                if not source_label or not pathology or not osics10:
                    raise ValueError(f"IRFU diagnosis evidence is incomplete for {team} candidate row {row['candidate_source_row']}")
                alias = IRFU_EXISTING_FAMILY_ALIASES.get(source_label)
                if alias is None:
                    alias = IRFU_EXISTING_FAMILY_ALIASES.get(source_label + " ")
                family = alias[:2] if alias else None
                basis = "existing_family_alias"
                if family is None:
                    family = inherited.get(normalise_label(source_label))
                    basis = "inherited_diagnosis"
                if family is None:
                    if source_label not in IRFU_IDENTITY_LABELS:
                        raise ValueError(f"unadjudicated IRFU diagnosis label: {source_label}")
                    family = (stable_family_code(source_label), source_label)
                    basis = "candidate_identity_group"
                mappings.append({
                    "team_key": team,
                    "source_row": int(row["candidate_source_row"]),
                    "source_label": source_label,
                    "osics10_code": osics10,
                    "body_location": body,
                    "pathology": pathology,
                    "family_code": family[0],
                    "family_label": family[1],
                    "subtype_code": re.sub(r"[^a-z0-9]+", "_", source_label.lower()).strip("_") or "diagnosis",
                    "mapping_basis": basis,
                })
    if len(mappings) != 402 or len({(row["team_key"], row["source_row"]) for row in mappings}) != 402:
        raise ValueError("expected one diagnosis-family mapping for each of the 402 included IRFU injuries")
    alias_counts = Counter(row["source_label"] for row in mappings if row["mapping_basis"] == "existing_family_alias")
    if alias_counts != Counter({label.strip(): values[2] for label, values in IRFU_EXISTING_FAMILY_ALIASES.items()}):
        raise ValueError("IRFU existing-family alias coverage changed")
    basis_counts = Counter(row["mapping_basis"] for row in mappings)
    inherited_count = basis_counts["inherited_diagnosis"]
    if inherited_count != 256 or basis_counts["existing_family_alias"] != 139 or basis_counts["candidate_identity_group"] != 7:
        raise ValueError(f"IRFU diagnosis mapping partition changed: {dict(basis_counts)}")
    return mappings


def prepare(directory: Path, migration: Path) -> None:
    sources = json.loads((directory / "analysis_sources.json").read_text())[0]["sources"]
    typed = json.loads((directory / "intake/irfu_typed_rows.json").read_text())
    root = directory / "intake/v15_candidate_intake_root_manifest.json"
    params = []
    diagnosis_mappings = irfu_diagnosis_mappings(directory)
    mapping_output = directory / "irfu_diagnosis_family_mapping.json"
    mapping_output.write_text(json.dumps(diagnosis_mappings, indent=2, sort_keys=True) + "\n")
    params.extend({"kind": "diagnosis_mapping", "row": row} for row in diagnosis_mappings)
    params.extend({"kind": "injury_bridge", "row": row} for row in typed["bridge"])
    for kind, key in (("injury", "injuries"), ("illness", "illnesses")):
        rows = [r for r in sources[key] if r["season"] == "2025-26" and r["team_key"] not in IRFU]
        rows += typed[key]
        params.extend({"kind": kind, "row": r} for r in rows)
    for team, version in (("benetton", 3), ("edinburgh", 2)):
        path = directory / "intake" / team / f"exposure_intake_final_clean_v{version}.csv"
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        with path.open() as handle:
            for number, row in enumerate(csv.DictReader(handle), 2):
                params.append({"kind": "exposure", "row": {
                    "team_key": team, "file_sha256": digest, "source_row_number": number,
                    "player_uid": row["player_uid"], "grain": row["exposure_grain"],
                    "included": row["cleaning_action"] == "include",
                    "exclusion_reason": row["exclusion_reason"],
                    "exposure_date": row["cleaned_date"] or None,
                    "week_start": row["week_start_date"] or None,
                    "minutes": row["minutes_total_clean"] or None,
                    "distance_m": row["distance_total_m_clean"] or None,
                    "hsr_m": row["source_hsr_gt18_kmh" if team == "benetton" else "source_hsr_value"] or None,
                    "estimated": row.get("Actual/Estimated", "").lower() == "estimated",
                }})
    params.append({"kind": "provenance", "root_sha256": hashlib.sha256(root.read_bytes()).hexdigest(),
                   "baseline_sha256": hashlib.sha256((directory / "served_before.json").read_bytes()).hexdigest(),
                   "hsr_decision": "Abdel selected Benetton HSR >18 km/h and Edinburgh High Speed Running as actual source fields in this task. Preserve blank values and unspecified Edinburgh threshold.",
                   "rule_version": "urc_intake_candidate_20260915_v2",
                   "diagnosis_mapping_sha256": hashlib.sha256(mapping_output.read_bytes()).hexdigest(),
                   "typed_sha256": hashlib.sha256((directory / "intake/irfu_typed_rows.json").read_bytes()).hexdigest()})
    output = directory / "candidate_params.json"
    output.write_text(json.dumps(params, separators=(",", ":")) + "\n")
    sql = (Path(__file__).parent / "release_candidate.sql").read_text()
    # Reuse accepted SQL calculators with only their explicitly selected inputs rebound.
    names = set(sources["views"]) | set(sources["functions"]) | {
        "urc_canonical_injury_rows_v1", "urc_2025_26_canonical_injury_rows_v1",
        "urc_illness_profile_rows_v2", "diagnosis_family_base_team_payloads_v1",
        "diagnosis_family_base_league_payloads_v1",
    }
    def bind(definition: str) -> str:
        for name in sorted(names, key=len, reverse=True):
            for old_schema in ("analysis", "reporting"):
                definition = definition.replace(f"{old_schema}.{name}", f"{SCHEMA}.{name}")
        return definition
    order = ["urc_diagnosis_family_team_exposure_v1", "urc_diagnosis_family_team_subtypes_v1",
             "urc_diagnosis_family_team_families_v1", "urc_diagnosis_family_league_exposure_v1",
             "urc_diagnosis_family_league_subtypes_v1", "urc_diagnosis_family_league_families_v1",
             "urc_illness_team_profiles_v1", "urc_illness_league_profiles_v1", "urc_2025_26_setting_severity_v1"]
    cloned = []
    for name in order:
        cloned.append(f"create view {SCHEMA}.{name} as\n{bind(sources['views'][name])}\n")
    for definition in sources["functions"].values():
        cloned.append(bind(definition) + ";\n")
    sql = sql.replace("-- CLONED_CALCULATORS", "\n".join(cloned))
    sql = sql.replace("CANDIDATE_PARAMS_SHA256", hashlib.sha256(output.read_bytes()).hexdigest())
    migration.write_text(sql)
    print(json.dumps({"params": str(output), "rows": len(params), "migration": str(migration)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--migration", type=Path, required=True)
    args = parser.parse_args()
    prepare(args.directory, args.migration)
