begin;

-- Add one governed injury and illness presentation over the exact approved
-- 2024-25 and 2025-26 immutable bundles. Source rows and release rows remain
-- unchanged. Canonical families replace only the diagnosis dimension. The
-- current 1,545-row 2025-26 cohort supplies setting severity and the qualified
-- preliminary_monthly_rates; every other injury section remains unchanged.
-- Separate illness rows supply Overall illness_profiles and illness_summary.

do $$
begin
  if not exists (
    select 1
    from reporting.latest_approved_dashboard_bundle_v4 latest
    join reporting.aggregate_releases release on release.id = latest.release_id
    join reporting.dashboard_bundle_league_payloads_v1 payload
      on payload.release_id = latest.release_id
    where latest.season = '2024-25'
      and latest.release_id = '0f0def1e-021f-471f-979f-6d73d98859c4'::uuid
      and release.release_label = 'urc-2024-25-v5-a80040f6afaa-a1'
      and payload.payload_sha256 =
        '4517f50bdf03688c087a34062071d97bd635576011e02f6f8ca5d1dc69a156ae'
      and (select count(*) from reporting.dashboard_bundle_team_payloads_v1 team
        where team.bundle_release_id = latest.release_id) = 16
  ) or not exists (
    select 1
    from reporting.latest_approved_league_bundle_v6 latest
    join reporting.aggregate_releases release on release.id = latest.release_id
    join audit.pipeline_runs run on run.id = release.pipeline_run_id
    join reporting.league_release_payloads_v6 payload
      on payload.release_id = latest.release_id
    where latest.season = '2025-26'
      and latest.release_id = 'f1d9c2cc-f70c-4dcc-a18d-3f2dc92d4cfc'::uuid
      and release.release_label = 'urc-2025-26-v6-b2bae1158257-a2'
      and run.output_hash =
        'b2bae1158257976b8e7da2385a7df065a2cd621492017bfb192a293ac16a1f41'
      and payload.payload_sha256 =
        '4eafb2dc32d155c69d968e833a354c145e08e0f13356b300234cefc1e2889c05'
      and (select count(*) from reporting.team_dashboard_payloads_v2 team
        where team.bundle_release_id = latest.release_id) = 16
  ) then
    raise exception 'Diagnosis-family successor approved bundle identity drift';
  end if;
end;
$$;

create table audit.urc_diagnosis_family_adjudication_evidence_v1 (
  adjudication_version text primary key check (
    adjudication_version = 'urc_diagnosis_family_adjudication_v1'
  ),
  ledger_sha256 text not null check (ledger_sha256 = 'cd319a12ab9fd73885c4e851bda11c2c277603a5e74665bd68bcb472738139dd'),
  mapping_rows_sha256 text not null check (mapping_rows_sha256 = '196f9c6765dfe83b2b205614aa61b4f5c3d53a85bc32983dabb1bdfdb5910f8e'),
  complete_ledger_sha256 text not null check (complete_ledger_sha256 = '7f3666de1309157843bade735bf79c4b30c39c75cc1542ef96f3254d5a840af5'),
  illness_inventory_sha256 text not null check (
    illness_inventory_sha256 = '6708f730cfa0faac40799b3eeafb99edd0e3e2e3c9a25de245daaaca1da3ef8d'
  ),
  illness_mapping_rows_sha256 text not null check (
    illness_mapping_rows_sha256 = '8c195664f215ab59dc52f0cceaee7cfe0d08b7d839f6475d088dbc0827c7c9f4'
  ),
  illness_ledger_sha256 text not null check (
    illness_ledger_sha256 = '32e6b9622da98723f8702294e1becc0e39f50a12872aeac6fa93c37c30cd1c92'
  ),
  specific_diagnosis_evidence_sha256 text not null check (
    specific_diagnosis_evidence_sha256 = 'a43ba36a7f67ecd208112d702bcc058de947b00d721399e9e0ad26d23f3ac167'
  ),
  accepted_2024_workbook_sha256 text not null check (
    accepted_2024_workbook_sha256 =
      '4f1db130f9f5aff23c3473eb2ab64a467f739a0b6ac7e4f170ca0383d9072b73'
  ),
  accepted_by text not null check (accepted_by = 'Abdel Babiker'),
  accepted_on date not null check (accepted_on = date '2026-09-01')
);

insert into audit.urc_diagnosis_family_adjudication_evidence_v1 values (
  'urc_diagnosis_family_adjudication_v1', 'cd319a12ab9fd73885c4e851bda11c2c277603a5e74665bd68bcb472738139dd', '196f9c6765dfe83b2b205614aa61b4f5c3d53a85bc32983dabb1bdfdb5910f8e',
  '7f3666de1309157843bade735bf79c4b30c39c75cc1542ef96f3254d5a840af5', '6708f730cfa0faac40799b3eeafb99edd0e3e2e3c9a25de245daaaca1da3ef8d', '8c195664f215ab59dc52f0cceaee7cfe0d08b7d839f6475d088dbc0827c7c9f4',
  '32e6b9622da98723f8702294e1becc0e39f50a12872aeac6fa93c37c30cd1c92', 'a43ba36a7f67ecd208112d702bcc058de947b00d721399e9e0ad26d23f3ac167',
  '4f1db130f9f5aff23c3473eb2ab64a467f739a0b6ac7e4f170ca0383d9072b73',
  'Abdel Babiker', date '2026-09-01'
);

create table audit.urc_2024_25_diagnosis_family_source_rows_v1 (
  adjudication_version text not null references
    audit.urc_diagnosis_family_adjudication_evidence_v1(adjudication_version)
    default 'urc_diagnosis_family_adjudication_v1',
  source_row integer not null check (source_row > 1),
  source_row_sha256 text not null check (source_row_sha256 ~ '^[0-9a-f]{64}$'),
  source_label text not null,
  subtype_code text not null,
  family_code text not null,
  family_label text not null,
  review_status text not null,
  primary key (adjudication_version, source_row),
  unique (adjudication_version, source_row_sha256)
);

insert into audit.urc_2024_25_diagnosis_family_source_rows_v1 (
  source_row, source_row_sha256, source_label, subtype_code,
  family_code, family_label, review_status
)
values
  ('5', '32837f7fc5e2092cce58e9c4cc5e033df26d0b0c1fb0288f29a94cafeadf4613', 'Cervical disc Injury', 'subtype_cervical_disc_injury_13c8608a7d', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury', 'accepted_deterministic'),
  ('7', 'ba4caf4dc497523a4152e707157ba047fb60e8f8f83980f95e4e742695c36117', 'Plantar fascia rupture', 'subtype_plantar_fascia_rupture_dbe62f4d0b', 'dx_plantar_fascia_rupture_dbe62f4d0b', 'Plantar fascia rupture', 'accepted_deterministic'),
  ('8', '3bd0717d8ef6a89df3b9186ea949127d0a1e29d694100fef9ea1ff270e0e43cb', 'Grade 2 MCL tear knee', 'subtype_grade_2_mcl_tear_knee_843dc46804', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('9', '804810e0e8ad519c54658a499bae6b968409ecf2aa3517de5b37130fac17dcf6', 'Lumbar pain non-specific', 'subtype_lumbar_pain_non_specific_29a75fb1e1', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('10', '44d428f27c992e29b30320509d73502f31683820dfd31eba56a2b0baa34281dd', 'Semimembranosis/tendinosis strain (grade 1 - 2)', 'subtype_semimembranosis_tendinosis_strain_grade_1_2_83548c8a09', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('11', 'bb2a5aee74ff05041a61a13dd8b5c183a54fe9713423caae6520c17454a1f1ff', 'Knee MCL contusion', 'subtype_knee_mcl_contusion_e9be973f04', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('12', 'cc5f26bad533bcb5a1cb488ebc029a26eb732fc8ec7579fbf7ecb0057a22e87e', 'Whiplash/neck sprain', 'subtype_whiplash_neck_sprain_3597569aa7', 'dx_neck_sprain_or_whiplash_404e63fe9e', 'Neck sprain or whiplash', 'accepted_deterministic'),
  ('13', '8f1396387829dba1bd16e645ee59860a49e31ed910167b4a80c074720fb1d69f', 'Oblique abdominal muscle strain', 'subtype_oblique_abdominal_muscle_strain_5ee059726e', 'dx_abdominal_muscle_strain_or_spasm_8848453dde', 'Abdominal muscle strain or spasm', 'accepted_deterministic'),
  ('15', 'e22a07ab8d6a2b18819f25f09da5d680003e976b42adee1d6997e1a3b450f44a', 'Iliopsoas muscle strain or tear', 'subtype_iliopsoas_muscle_strain_or_tear_d24256c96f', 'dx_iliopsoas_muscle_injury_f4c389b8cc', 'Iliopsoas muscle injury', 'accepted_deterministic'),
  ('21', '1bee36323c4d45cfa8d21877a647ee86463a80b777dfb397f101a0263949a793', 'Achilles tendon rupture', 'subtype_achilles_tendon_rupture_6b59cc3783', 'dx_achilles_tendon_rupture_6b59cc3783', 'Achilles tendon rupture', 'accepted_deterministic'),
  ('22', '006de652caf4763df41c360bf744405dc48a640e9046555c28f18d53c969dd90', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('23', '715ea15e1c2ba8cde588e24e90b4e6ce89606548fe1659c7664c6773b6806259', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('24', '2a0a68f2543b46b91a47026cf377f6e36bceb1bd7abc6676cae3339c606c169a', 'Distal biceps tendon rupture', 'subtype_distal_biceps_tendon_rupture_a28ef09d0b', 'dx_biceps_tendon_injury_cbd11d2125', 'Biceps tendon injury', 'accepted_deterministic'),
  ('25', '64677c81cf20ce00fcce834700f763444917decc50dcf6c38265e096b0827e8c', 'Distal biceps tendon rupture', 'subtype_distal_biceps_tendon_rupture_a28ef09d0b', 'dx_biceps_tendon_injury_cbd11d2125', 'Biceps tendon injury', 'accepted_deterministic'),
  ('26', 'd82c3876f44efae35596f4fc003d7e4ca4983de7fd0b16382ce7989c8dc972d0', 'Fractured humeral condyle(s)', 'subtype_fractured_humeral_condyle_s_3187e13e14', 'dx_humeral_condyle_fracture_86595a3e03', 'Humeral condyle fracture', 'accepted_deterministic'),
  ('27', '527fcb3e584091073666ec3747bfb245b508999d6f1633a9f047e8d0b0323375', 'Mid/distal plantar fasciitis', 'subtype_mid_distal_plantar_fasciitis_0161a8fbf8', 'dx_plantar_fascia_injury_ec4d3703e9', 'Plantar fascia injury', 'accepted_deterministic'),
  ('29', 'ab3c8e723ea9bec089e952cc87c1afa813c541cf0173a2bb0ffde72717bcc350', 'Knee medial collateral ligament (MCL) injury', 'subtype_knee_medial_collateral_ligament_mcl_injury_9cce43fa53', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('30', '4e92f6d6743dd0e20aa8bbdb6669da93f52530cfde979868ed60dc60778d5ddd', 'Stump trauma thigh', 'subtype_stump_trauma_thigh_2a343d143e', 'dx_thigh_stump_trauma_1f598a2ab0', 'Thigh stump trauma', 'accepted_deterministic'),
  ('31', '0b213460f9c9638e14e52194b7e23a4e30251e0bb050bbcc471c26d2902e5bf6', 'Knee posterolateral complex (PLC) strain or tear', 'subtype_knee_posterolateral_complex_plc_strain_or_tear_036571cdc7', 'dx_knee_posterolateral_corner_injury_a4c4c64579', 'Knee posterolateral corner injury', 'accepted_deterministic'),
  ('32', 'cf05e18cf640ef3015d6dc54404de7ca786c21e37610657dc5f952af48c589aa', 'Distal biceps tendon rupture', 'subtype_distal_biceps_tendon_rupture_a28ef09d0b', 'dx_biceps_tendon_injury_cbd11d2125', 'Biceps tendon injury', 'accepted_deterministic'),
  ('35', '8082544483a9563a4ddb2ec11c5ed682ed82b9b23455331b18611e77e8356422', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('36', 'a663a9fc6ea07f7982c1550d7b51d71106dadb91c194335eaef46aa87c99d71e', 'Anterior peronealtalar ligament sprain', 'subtype_anterior_peronealtalar_ligament_sprain_a6916c365f', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('39', '7c3feab7f852f8b1d5345d26ad94989227129c7d578ced21070d276f54e2f57b', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('41', '0f985d50906a1ae5c2f3e4644d060f99f1c3e4d1c1d6118bf901fc0124ceacf4', 'Adductor origin tendinopathy', 'subtype_adductor_origin_tendinopathy_75ee0d21d5', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'accepted_deterministic'),
  ('43', '5711188fd930d37b0db3bf4bb4ce5b5acbb950b88d41745d8762f2059cd1d61c', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('44', 'e129d3fb7a3d5ba31f895807d1bf470f58a9cfd11c79b2e2815f9ae7722f168e', 'Lateral malleolus fracture', 'subtype_lateral_malleolus_fracture_83cb1eb192', 'dx_lateral_malleolus_fracture_83cb1eb192', 'Lateral malleolus fracture', 'accepted_deterministic'),
  ('55', '5e029c8e0782b856fd11bde973b91779af0d01f335dcbe9ed8e273901dda3f8e', 'Sprain medial collateral (deltoid) ligament ankle', 'subtype_sprain_medial_collateral_deltoid_ligament_ankle_ba23692ed8', 'dx_medial_ankle_ligament_injury_9add2aecee', 'Medial ankle ligament injury', 'accepted_deterministic'),
  ('56', '4f3145c916047443ab2ad96bc613fe47125b02fb85e77415d66a714024358e87', 'Anterior talofibular and calcaneofibular ligament sprain', 'subtype_anterior_talofibular_and_calcaneofibular_ligament_sprain_b3a64a632d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('57', 'e0b61c476cbc49d9d44e33bec6a1fc9a4cc4ae37eeb68c03787001101f8bca76', 'Medial hamstring insertion tendonitis/pes anserinus bursitis', 'subtype_medial_hamstring_insertion_tendonitis_pes_anserinus_bursitis_9e25705afb', 'dx_hamstring_tendon_injury_f86b1dad5b', 'Hamstring tendon injury', 'accepted_deterministic'),
  ('58', '79f578f203911f2e2125ab553c00c56f9e009fab5570e7e5598803af8dbc2477', 'Sprain lateral collateral ligament ankle', 'subtype_sprain_lateral_collateral_ligament_ankle_96d9293f86', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('59', 'ac87fff915744a336a86e9c043149a03e36ffd908bd7d17fa45caebf770a61a0', 'Quadriceps strain or tear', 'subtype_quadriceps_strain_or_tear_17ff226482', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('60', 'd45200a57ca3a497605b51bb872260432833505e64f7bd1b48624e63b95adc3f', 'Sartorius tendon strain', 'subtype_sartorius_tendon_strain_479dcdf678', 'dx_sartorius_injury_3dfafe7e54', 'Sartorius injury', 'accepted_deterministic'),
  ('64', '6c55f2b9517e6158072b6648bedcca88c4f79c15f47a6f10d81f1ab6b5d6427e', 'Gastrocnemius muscle injury or strain', 'subtype_gastrocnemius_muscle_injury_or_strain_367914bc2d', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'accepted_deterministic'),
  ('65', '0d6b2a5046d7ee83d9cc7dd462ce3a64a08ed2fcbce52c401c1dad4d9c43f34e', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('66', '03df3ad54c71e1a50661ceac8da25d73ead78fadec4d0ba3a1ec1ffa98aaf81f', 'Sprained ulnar collateral ligament (Skier''s) thumb', 'subtype_sprained_ulnar_collateral_ligament_skier_s_thumb_9625d9031b', 'dx_thumb_ucl_injury_00b846b6dd', 'Thumb UCL injury', 'accepted_deterministic'),
  ('67', 'e249c144c3145306397ed8707a6e99ef2f9271ceae0d83454cbe63192bc436ca', 'Cheek abrasion', 'subtype_cheek_abrasion_80d9386363', 'dx_cheek_abrasion_80d9386363', 'Cheek abrasion', 'accepted_deterministic'),
  ('68', 'f816db6c95a04d13af4e0feeacaac7162093a5f3cc39320731b6a25e20cfbe97', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('69', '13f89b00db03cff2fc86694997a2d98957e9f0036afd2bc2fd90b4807f85c72f', 'Buttock Soft Tissue Bruising/Haematoma', 'subtype_buttock_soft_tissue_bruising_haematoma_21fdd2d181', 'dx_buttock_contusion_46ae636fd7', 'Buttock contusion', 'accepted_deterministic'),
  ('70', 'eb993a40e4a2aa50a0ae5772036cc8927f7b979d7eed688ae31d696d830b51da', 'Knee Pain/Injury Not otherwise specified', 'subtype_knee_pain_injury_not_otherwise_specified_f2690253b3', 'dx_knee_pain_609ce718bc', 'Knee pain', 'accepted_deterministic'),
  ('71', 'd364c055245c88e02edcbc46d1e6a7996b945652446f4e9b2ff53dcdd0992542', 'Grade 1 MCL tear knee', 'subtype_grade_1_mcl_tear_knee_6a8ace9800', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('72', 'c65833445d3ae8ac9a60cb0e93b2b0504f85d29004c9afc46831f07497601c3a', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('73', '2d0f5bd09f19bb16e5215d55f55ceb11d02050a9bfa534d006dc560087712204', 'Acute shoulder subluxation', 'subtype_acute_shoulder_subluxation_705b818f24', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('74', 'bba97e4ca8675ea881cfe445db949f0c56df2fe8250b459d7015986c5ee799f4', 'Thoracic facet joint sprain', 'subtype_thoracic_facet_joint_sprain_205cac3c00', 'dx_thoracic_facet_joint_disorder_519c2ae5a8', 'Thoracic facet joint disorder', 'accepted_deterministic'),
  ('75', 'c4557eaadae798f56bf7096fa3c229a79f5adc21b3879986f5c39aacb9ef8032', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('76', '6050d63bd4e8342dafffbcec9741a65e66e4ed1fa8fedc3a5ea3f09b1051beeb', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('77', 'a6e85207408a4ec2753515b8633051046648cfcfe4a5c62a125646bc51d42e8e', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('78', '75e3e23434ac0d20f420eab01e27dab8d17325b30766581bc1ed403596cf8a6f', 'Patellar Tendon Injury', 'subtype_patellar_tendon_injury_c88ba5aba6', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'accepted_deterministic'),
  ('79', '5a408cd8efa0dd46f53d3519a1d8ad483a282071e83ca8d8dda56bcd935bb44b', 'Knee Sprains/Ligament Injuries', 'subtype_knee_sprains_ligament_injuries_bc9c2670dd', 'dx_knee_ligament_injury_unspecified_7ab630d44d', 'Knee ligament injury, unspecified', 'accepted_deterministic'),
  ('80', 'e0bfaf2072d552ae2d2806b8bd39df363163b67427e0e199f63895ef0ce74474', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('81', '1823d9ccded7d658f4625d1645754279d31b4281dff314f533347d50ff9fcf23', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('82', '24f0d2981356eb0e8b1934a079cde662840b09b9812cd108a79794c54ace565f', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('83', '17f7f0f09a1cecf1e1726296dcb59916c4d87b3fbfee28670a9c1b520ea5110f', 'Ankle contusion/haematoma', 'subtype_ankle_contusion_haematoma_dda81acafa', 'dx_ankle_contusion_beb9f51162', 'Ankle contusion', 'accepted_deterministic'),
  ('84', 'b34a9d9811812fc138e07f21c5e644fcb52ba07e446d24cd996698d121751c0f', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('85', '29c340bb1a6de9af9edac14a1f7256d589304cc28ab37395764842d536da677a', 'Grade 3 hamstring strain', 'subtype_grade_3_hamstring_strain_6183bcd886', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('86', '6139dfd763d84d270a58a6b2f320e9ec9a9c15322b3af1b601ab3a5802a6161d', 'Back referred hamstring tightness', 'subtype_back_referred_hamstring_tightness_6fbd78d98a', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'accepted_deterministic'),
  ('87', 'b31dc0ffb5c6a6fd612e39c840e83e89fb84a77a2fc18ab38beed3c3591e95a8', 'Rectus femoris strain', 'subtype_rectus_femoris_strain_5670ca194b', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('88', '96de1c0f83e34251e8b64ac85f787e9fc01fa2a06fcd1ee47e0349f8bb07ac1f', 'Knee contusion/haematoma (extraarticular)', 'subtype_knee_contusion_haematoma_extraarticular_19a33609a2', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('89', 'dc7d74010331984de50a17cbda191bf9baebcf138bc82a28dd81c1c0d6bfeaf1', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('97', '55aae612bff3cdc9a092259fb39f5c0c52936acc634233a6463a2d2fa7bbd494', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('105', 'fc15096bb3dce1e471db2330addc6095941253458fcb12f3b9a179db9a5cf656', 'Sprained/jarred wrist joint', 'subtype_sprained_jarred_wrist_joint_7ec711f5b5', 'dx_wrist_injury_d94414e2c6', 'Wrist injury', 'accepted_deterministic'),
  ('106', '963bbb5f74cd8ae9ec556aeb626f52425fd849d080bd05cbbaad3e555c997b78', 'Nose fracture', 'subtype_nose_fracture_7b8a158870', 'dx_nasal_fracture_a291a11f04', 'Nasal fracture', 'accepted_deterministic'),
  ('107', 'f2d3aea96381fa30c734da333e67972a443479e531eb85647447efe2732a6157', 'Knee ligament sprain involving the ACL, PCL or a collateral ligament', 'subtype_knee_ligament_sprain_involving_the_acl_pcl_or_a_collateral_ligament_16caf2de61', 'dx_knee_ligament_sprain_involving_the_acl_pcl_or_a_collateral_ligament_16caf2de61', 'Knee ligament sprain involving the ACL, PCL or a collateral ligament', 'identity_group'),
  ('108', '376637cf1032d8350d1fa0581eac7a7fae91d2015be59a8eff1f73a71ceffed5', 'Knee Sprains/Ligament Injuries', 'subtype_knee_sprains_ligament_injuries_bc9c2670dd', 'dx_knee_ligament_injury_unspecified_7ab630d44d', 'Knee ligament injury, unspecified', 'accepted_deterministic'),
  ('109', 'd85ce4dd274740173c6c2dc62fac4ff48812c79008182e7bd9489d5de78ad573', 'Pectoralis major muscle strain', 'subtype_pectoralis_major_muscle_strain_5887d37d12', 'dx_pectoral_muscle_injury_981511cfe1', 'Pectoral muscle injury', 'accepted_deterministic'),
  ('110', '52ae15a6b7f92da5891f1f96cbe8847b93cc885ff5b624ea4e6cb76f8c5a24d6', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('111', '264a5eb57da2f0f1dc4a178e3968f76fbf6f3d68a9e891288fe442e56692d8c2', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('112', '651571a016fa08e338b1ecdc8a1006181c01cd761ce95b4d8b81c4958b008fcb', 'Quadriceps strain or tear', 'subtype_quadriceps_strain_or_tear_17ff226482', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('113', '223ef238143d338b9b1107c7b00cff004e251314c9aa79fab62c28fd779bf48f', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('114', '72b0d305da09ca7391128137dec62d85a9b40a5c44f854652348f6e9070fb787', 'Biceps haematoma', 'subtype_biceps_haematoma_9e45c72a18', 'dx_biceps_muscle_injury_3a5679b9a5', 'Biceps muscle injury', 'accepted_deterministic'),
  ('115', '7f72b5b99f06833362296329f7b5c45ce0a0bd0fb90fdd36cd36f380ea7c4aed', 'Sprain lateral collateral ligament ankle', 'subtype_sprain_lateral_collateral_ligament_ankle_96d9293f86', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('116', 'ee777cd114442a72ce9dff0f33e078404e12e701e36227bc3d94ebabf0a0e9a3', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('117', '9267789a62dddf69b1266251a0eb025f9d423d3a9c8ddd72acac27d0b9fefcb2', 'Shin abrasion', 'subtype_shin_abrasion_c327f2dfa3', 'dx_shin_abrasion_c327f2dfa3', 'Shin abrasion', 'accepted_deterministic'),
  ('118', '6b2c03033ea9b46e34fcb539496202252798315d96fcdbfd59731c2fdac501ae', 'Cervical nerve root compression/stretch', 'subtype_cervical_nerve_root_compression_stretch_6f650f0242', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('119', '16f8922a6ab43bc6ad5d9561221859768b5447c976835360e6a77d31105126e2', 'Pectoralis major muscle strain', 'subtype_pectoralis_major_muscle_strain_5887d37d12', 'dx_pectoral_muscle_injury_981511cfe1', 'Pectoral muscle injury', 'accepted_deterministic'),
  ('120', '61cdbd6dd3a688899c24b8ce925da81cacb2cd24ff832e6569fc84d40ea04a34', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('121', '76dbef83bc935d118c0b991ac895ccbd3ae1529efda19272305bc2bb0cfcc26f', 'Costochondral joint instability', 'subtype_costochondral_joint_instability_5683c80b63', 'dx_costochondral_joint_instability_5683c80b63', 'Costochondral joint instability', 'accepted_deterministic'),
  ('122', 'e85d674fedbb8324c7e0c8315121c5ced63023bb3b0621a642cdf7f0bf85d31d', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('123', 'fa1b761f652cceb5fb01d0284b83168d4b5f08534caad0b9fafc1541f62791c7', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('124', 'ca84b8b1d60d5674d3021980b4f665d27561ac606c5ffedc511ffdb1043dae8c', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('125', 'a1e10dc0cf9fd0a9d4def81f6bbe606122c3cc03fe1176aaf437b3f5660d4895', 'A/C Joint instability/recurrent sprains', 'subtype_a_c_joint_instability_recurrent_sprains_ed3ae2521a', 'dx_acromioclavicular_joint_chronic_instability_299408db68', 'Acromioclavicular joint chronic instability', 'accepted_deterministic'),
  ('126', '11609a8447262dbc2bb8c70c4550f69e2fb58c9a862f610f393fa73848b3e500', 'Piriformis syndrome (with sciatic nerve impingement)', 'subtype_piriformis_syndrome_with_sciatic_nerve_impingement_31b07271c8', 'dx_piriformis_syndrome_d562318818', 'Piriformis syndrome', 'accepted_deterministic'),
  ('127', 'c6a181ef2614e2091b6dc2abf0b2ff02e22fb41742649ef75f739942b04d1f82', 'Fifth metacarpal fracture', 'subtype_fifth_metacarpal_fracture_709a70bfc3', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture', 'accepted_deterministic'),
  ('128', '6eb93b330cc7ffb8d201efd47c26f8c3f069aa9acc9144975df0b4c31fc7f33a', 'Rectus femoris strain', 'subtype_rectus_femoris_strain_5670ca194b', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('129', '9e8005ffc773aa1d6970c19db9d9aeede001c1d295278e87e80b58a150159df7', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('130', 'b988ad2586adf791d3422a37535fa92b3dc3b92425ec614b509d65f0bb647c70', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('131', '45423bad35744c6209584b0ae8aa3c2c4c373a4024266dae1272af7b6b29b477', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('132', 'ca50325fe041d5e33e554cd9e8d47b68ea8df1ef84c31b2859f273c99268fdaa', 'Lacerated knee', 'subtype_lacerated_knee_9e6fcc291a', 'dx_knee_wound_7498252643', 'Knee wound', 'accepted_deterministic'),
  ('133', '0c261214e9b275dacc834aad98a62e5f797a93e8b479ecad2af039b8df6a7314', 'Hip flexor muscle strain', 'subtype_hip_flexor_muscle_strain_3e1d987aae', 'dx_hip_flexor_injury_cedda9fa03', 'Hip flexor injury', 'accepted_deterministic'),
  ('134', 'ee8bb442eedb1b0d2da8d8c86d0d71a664ea287db4887660acf2a363c3b6480b', 'Lumbar functional movement disorder', 'subtype_lumbar_functional_movement_disorder_5db92a4b02', 'dx_lumbar_functional_disorder_54b3525e5c', 'Lumbar functional disorder', 'accepted_deterministic'),
  ('135', '2ad20afc24b8f61ccff80d3c75ede9f5ca5b57c2b10f1d10860341715ea96231', 'Patellofemoral osteochondral injury', 'subtype_patellofemoral_osteochondral_injury_95dab31c6f', 'dx_patellofemoral_injury_a6e2fe370a', 'Patellofemoral injury', 'accepted_deterministic'),
  ('136', 'd734597608927eaee9b6f83ee369b910305deb52dba4b1de50181c2bbc41e511', 'Sprain medial collateral (deltoid) ligament ankle', 'subtype_sprain_medial_collateral_deltoid_ligament_ankle_ba23692ed8', 'dx_medial_ankle_ligament_injury_9add2aecee', 'Medial ankle ligament injury', 'accepted_deterministic'),
  ('137', '67343820d1e7ae4fa830845926a3c8bd839cc0ccbe9ba5359904cf3f8b4f519d', 'ACL or PCL sprain of the knee', 'subtype_acl_or_pcl_sprain_of_the_knee_251aa299df', 'dx_acl_or_pcl_sprain_of_the_knee_251aa299df', 'ACL or PCL sprain of the knee', 'identity_group'),
  ('138', 'f4397fab335835466d09be07fc45530b04e6c7b059ab795e0941460a9c02ca49', 'ACL strain/rupture with chondral/meniscal injury', 'subtype_acl_strain_rupture_with_chondral_meniscal_injury_daad2589e2', 'dx_acl_injury_4b8eb47e96', 'ACL injury', 'accepted_deterministic'),
  ('139', '2a40ccbc7d7788e69eb4973b62366531b19e87d66eeec7f9f606d1189eb764ed', 'Anterior talofibular and calcaneofibular ligament sprain', 'subtype_anterior_talofibular_and_calcaneofibular_ligament_sprain_b3a64a632d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('140', '0025a5797cc917b900431eadabda583e8c6db8f11446b7bd2d3e812a67eb9a31', 'Iliotibial band haematoma', 'subtype_iliotibial_band_haematoma_8b35949b9e', 'dx_iliotibial_band_haematoma_8b35949b9e', 'Iliotibial band haematoma', 'accepted_deterministic'),
  ('141', '3b1b8b7aaa89033878c7b22ff181966a4e0031f56db811ba1ba6b6ab0ac895cf', 'Lumbar functional movement disorder', 'subtype_lumbar_functional_movement_disorder_5db92a4b02', 'dx_lumbar_functional_disorder_54b3525e5c', 'Lumbar functional disorder', 'accepted_deterministic'),
  ('142', '596fe392c1cf2e2ab0eeb5ce47c99ad577de9f5fd9ee6b77d29bcd4188623b3c', 'Lumbar functional movement disorder', 'subtype_lumbar_functional_movement_disorder_5db92a4b02', 'dx_lumbar_functional_disorder_54b3525e5c', 'Lumbar functional disorder', 'accepted_deterministic'),
  ('143', '1b85104c68da09c20a84e65f7ee53503889fb708b1ce2fe4f0221721a8cd89e4', 'Lumbar functional scoliosis', 'subtype_lumbar_functional_scoliosis_9c2f899865', 'dx_lumbar_functional_scoliosis_9c2f899865', 'Lumbar functional scoliosis', 'accepted_deterministic'),
  ('144', 'da8f53ec5cc4e3101df921032bdddab59177e3aaaafc2273a3b3a7c19d1e537e', 'Ankle synovitis/Impingement/Bursitis', 'subtype_ankle_synovitis_impingement_bursitis_518a389deb', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis', 'accepted_deterministic'),
  ('145', '8398d13c3636d88634bbf196b44b07a1ac8cf1a001b43c895585d41f8667addb', 'Lumbar functional movement disorder', 'subtype_lumbar_functional_movement_disorder_5db92a4b02', 'dx_lumbar_functional_disorder_54b3525e5c', 'Lumbar functional disorder', 'accepted_deterministic'),
  ('146', '99facaf70ce68483c7fd775b12866834ce5eecacdcf2a7e843582fb437de5436', 'Eyebrow laceration requiring suturing', 'subtype_eyebrow_laceration_requiring_suturing_88ac45fb54', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('147', '1bfc36c45afee702ee0ee581ebfa20af7f2f47230b6633412a78b0ac7687d0fb', 'Dislocated elbow', 'subtype_dislocated_elbow_6dacb5f24d', 'dx_elbow_dislocation_6303e22e17', 'Elbow dislocation', 'accepted_deterministic'),
  ('148', '179a62f38fe0c4e1fb8cf4eb819a346de3803d4a315696acb6b859fcf0b040f9', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('149', 'e397b38426580b8e9519140f133d78b36064a03088117ab61a46242812424d81', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('175', '35ce82aa6a902059dec1233a811563735caf379f904dfcc8aa4e96d18ef53d50', 'Back referred hamstring tightness', 'subtype_back_referred_hamstring_tightness_6fbd78d98a', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'accepted_deterministic'),
  ('176', 'c496ab9eae4727b1314193231f23dc798ca54eb18b8bb46382115f35b8f970d0', 'Hip/Groin Pain Not otherwise specified', 'subtype_hip_groin_pain_not_otherwise_specified_742fb1cd99', 'dx_hip_and_groin_pain_27531edcc3', 'Hip and groin pain', 'accepted_deterministic'),
  ('177', 'ac91ac1fc7eec4763a21bb46a77779831c741f256a90f088920330307922b91e', 'Bennett''s fracture/dislocation thumb', 'subtype_bennett_s_fracture_dislocation_thumb_3a25210b48', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture', 'accepted_deterministic'),
  ('178', 'a3087b9b1ccf963161c74283defcf762f999aa7024efedc7f587b5253658c195', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('179', '49f28e6cf2ef8fb55d12fb6e31667f7ec55cdda7d3f948de0ed64c4fd616cc49', 'Knee medial collateral ligament (MCL) injury', 'subtype_knee_medial_collateral_ligament_mcl_injury_9cce43fa53', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('180', '3cdf523dd1458978c13e69bbbf0f4358985ab7a43f404b5a8e3c489ef37d8d27', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('181', '8190625dc8be32d8cfeb8bbfdcb5e2518910f63df317da99515b4e7821f497a6', 'Traction injury to foot', 'subtype_traction_injury_to_foot_c7acd051ef', 'dx_foot_traction_injury_7a520b8998', 'Foot traction injury', 'accepted_deterministic'),
  ('183', '0240050c1a30391f4d8bbaf0fa796a1b59c867063c16dfda8599fb6e769eea4a', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('185', '2f811361363d2fdbda79d589b85db4a0fd7ff53759d56e9178b8d2c311bc6da4', 'ACL rupture', 'subtype_acl_rupture_f84927fab2', 'dx_acl_injury_4b8eb47e96', 'ACL injury', 'accepted_deterministic'),
  ('186', 'c6b0b33bfcc5c34478711422a3d499e46b0dfc8a8390cb69b7fce920c8b919d8', 'Dislocated elbow', 'subtype_dislocated_elbow_6dacb5f24d', 'dx_elbow_dislocation_6303e22e17', 'Elbow dislocation', 'accepted_deterministic'),
  ('187', '7b8fab7711464895df76cae5bb9f96a1719f402f7bcb82db7650e5edaccc7552', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('188', 'b9e5648e1ed7e449add69451f9b1b569072635c211028dad7472f1314f5268ed', 'Concussion with Criteria 1 video signs', 'subtype_concussion_with_criteria_1_video_signs_624c97508a', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('193', '948a8a97a8f44d7216e392f3da837c5ae19ac6e81b09299486252fe1c67fe904', 'Cervical nerve root compression/stretch', 'subtype_cervical_nerve_root_compression_stretch_6f650f0242', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('197', '413f30c68659205fcb438aa8aa88e60c29f58f17a1305064c8941ac063946514', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('198', '9882389879d7de1c7d35bcbb0704b06851525271587d2d2ddb3be31ab25d7851', 'Other Ankle Pain/Injury not otherwise specified', 'subtype_other_ankle_pain_injury_not_otherwise_specified_3d735e2c86', 'dx_ankle_pain_de6b615afc', 'Ankle pain', 'accepted_deterministic'),
  ('199', '6a3ef2b53b220f1912ee59bc08051b8c755ef752817949c76b8a84faf42bac3d', 'Dislocated patella', 'subtype_dislocated_patella_26b8cc45c3', 'dx_patellar_dislocation_0c3c5e687e', 'Patellar dislocation', 'accepted_deterministic'),
  ('200', 'e401b61d2f4223558d86bc4393eb188960bdcc2742fade64f97692fda8a3aa3d', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('202', '8f19dddc5cd33ac0a9013e12f3b6c8bb32f8424cdead6dc08076ec5c63c70b94', 'Lateral ligaments rupture (grade 3 injury)', 'subtype_lateral_ligaments_rupture_grade_3_injury_c5dc81b2fd', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('203', 'c4d1e1aa5075eb82f3d752ae26b905b3239b4c49ad367840ba4f8f159db27c62', 'Foot Pain/Injury Not otherwise specified', 'subtype_foot_pain_injury_not_otherwise_specified_949eb48abd', 'dx_foot_pain_116521a908', 'Foot pain', 'accepted_deterministic'),
  ('209', 'd33cf1730cfab8b0386ca5339261a66f84a86d08e8472c1e709763d78d71f45d', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('210', '2183bff1f55081fa41833156896650bdb455f451333c67d5c69cebb3243ca9b9', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('211', 'eb8bcc51371ab61eccea1078a9ad29ae44ff71b114c56f038cd73d92e139fbf3', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('221', '24970ad9e06ab8c8c087f8914720efe66b478b9497a4c19747cf8f5e6b8bcc6e', 'Lumbar Spine muscle and Tendon Strain/Spasm/Trigger Points', 'subtype_lumbar_spine_muscle_and_tendon_strain_spasm_trigger_points_0af31940e8', 'dx_lumbar_spine_muscle_and_tendon_strain_spasm_trigger_points_0af31940e8', 'Lumbar Spine muscle and Tendon Strain/Spasm/Trigger Points', 'identity_group'),
  ('224', '3eb2a0fc27a1e8cefa4bee00ef4b9d82db9c7681c5ec6ef76ffe2c55b05368e0', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('225', '701db25df19b0df197ce6426a7d4d9be49864b4611d8e22e40a43b92db3f4484', 'Shoulder pain undiagnosed', 'subtype_shoulder_pain_undiagnosed_17d9bbee64', 'dx_shoulder_pain_738e4b93f7', 'Shoulder pain', 'accepted_deterministic'),
  ('226', '4f239558d29b6ae2e19be6e7729111f626944180ad30c1bcda4dfc345dffee9a', 'Other Stress/Overuse Injury Hip and Groin', 'subtype_other_stress_overuse_injury_hip_and_groin_a42c390491', 'dx_hip_and_groin_overuse_injury_71c787dc38', 'Hip and groin overuse injury', 'accepted_deterministic'),
  ('228', '3e7b49ec11a1a86a6b48323fa1d3586ef734368f4339d3d87eeb75959b85c842', 'Internal impingement of the shoulder', 'subtype_internal_impingement_of_the_shoulder_1f3a49d1f1', 'dx_shoulder_impingement_c2f2a634b4', 'Shoulder impingement', 'accepted_deterministic'),
  ('229', '2d8866ff322921cd04743890bdba125d032df5d633e4eb1528f4a7353523fb31', 'Cervical Disc sprain', 'subtype_cervical_disc_sprain_98da6e06ba', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury', 'accepted_deterministic'),
  ('230', 'e46cc57c4c3b3895bad6222105bf02145742e2b9a1bce441aee41cd8e3e61f79', 'Sprained/jarred wrist joint', 'subtype_sprained_jarred_wrist_joint_7ec711f5b5', 'dx_wrist_injury_d94414e2c6', 'Wrist injury', 'accepted_deterministic'),
  ('232', '973d1edb65590fd2ac23f585ff7d3a66b3f7c5d4907ddf8301d9e5deb6b9cb76', 'Back referred hamstring tightness', 'subtype_back_referred_hamstring_tightness_6fbd78d98a', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'accepted_deterministic'),
  ('233', 'fe065240d22b1a9535eedd65a86b9c0fbf05ac533bd1439594fd1517fdefde66', 'Inferior tibiofibular syndesmosis sprain', 'subtype_inferior_tibiofibular_syndesmosis_sprain_0545fce188', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'accepted_deterministic'),
  ('234', 'd3dde69f259e0a8747f3de27a14f6c55071162dee1da6612ebb4befeb0fa61b6', 'Finger extensor tendon injury (incl mallet finger +/- avulsion fracture distal phalanx)', 'subtype_finger_extensor_tendon_injury_incl_mallet_finger_avulsion_fracture_distal_phalanx_62e86d0854', 'dx_finger_extensor_tendon_injury_mallet_finger_36d86ff004', 'Finger extensor tendon injury/mallet finger', 'accepted_deterministic'),
  ('235', 'b164bfe3601fab4b7d470ecbaa85bee0e07b011b4684e6088354d61ddc298d97', 'Rotator cuff haematoma', 'subtype_rotator_cuff_haematoma_f01ff453b0', 'dx_rotator_cuff_injury_0744f75c4c', 'Rotator cuff injury', 'accepted_deterministic'),
  ('236', '04d667dab45da0a45fda3fd9602ede5e035cce199486bb55e6b6e5bf8f74a064', 'Inferior tibiofibular syndesmosis sprain', 'subtype_inferior_tibiofibular_syndesmosis_sprain_0545fce188', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'accepted_deterministic'),
  ('237', '284b1c4dc008897fabff7c57dc6acc7280384d2f5af8b95c65cfd8e27f489e6c', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('238', '2aeea0610a557a58e86396e1110278daa0d50a1b46d1d3c26bef3361800c206a', 'Ear laceration', 'subtype_ear_laceration_b7278cc10a', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('240', 'bfc642cce9733a53e66ff5fad3414a4021f12dbdc116f028bfe6dbafa82134ef', 'Dislocation of MCP joint finger(s)', 'subtype_dislocation_of_mcp_joint_finger_s_44e87a594b', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'accepted_deterministic'),
  ('241', 'e9cc5cea501a25463bad6d11c69616b5b99665d4558b8fc9ddd4ff4213334a33', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('242', '4b25de2b44c278a6cece5e0e8953573cde43ffce427a617f9f9d3c2dd7db1076', 'Unspecified or multiple adductor tendinopathy', 'subtype_unspecified_or_multiple_adductor_tendinopathy_0c38808167', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'accepted_deterministic'),
  ('243', '3123266579ebc2ade9c291a5a2e1a020604c7a56d1463bdbaedac22e09ca8012', 'Bruising/haematoma iliac crest/gluteus medius', 'subtype_bruising_haematoma_iliac_crest_gluteus_medius_0d84299fc3', 'dx_buttock_contusion_46ae636fd7', 'Buttock contusion', 'accepted_deterministic'),
  ('244', '18e793ea51ac4dc326913736755d8e64dd37af9615eaeb17117748b0e9eb5f62', 'Piriformis trigger points', 'subtype_piriformis_trigger_points_ac83e20726', 'dx_piriformis_trigger_points_ac83e20726', 'Piriformis trigger points', 'identity_group'),
  ('245', '1cc716af8244dfe339b5c80426a733404a7beee5e898e3c67e4fef4de7b0dc6d', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('246', '58076baa37d3b0f2a826aef732ec39c79ccbe20ec14e76796147c199f706be4b', 'Glenohumeral joint sprain with chondral/labral damage (incl SLAP tear)', 'subtype_glenohumeral_joint_sprain_with_chondral_labral_damage_incl_slap_tear_1eb5055b90', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('247', '413632cb89b17d518d22260c43eea086b0a3b0eff3756ebcae62a854aebced72', 'Gastrocnemius muscle injury or strain', 'subtype_gastrocnemius_muscle_injury_or_strain_367914bc2d', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'accepted_deterministic'),
  ('248', '7f337e407ee2a0fdfdde14aef38b5c54969715fdf48cc1e7ccb0cb7b2b985027', 'Midfoot joint/ligament sprain (incl Lisfranc)', 'subtype_midfoot_joint_ligament_sprain_incl_lisfranc_282c947645', 'dx_midfoot_injury_3332895405', 'Midfoot injury', 'accepted_deterministic'),
  ('249', '25657fc970d7a18bbce7097d244942a85ef1410e4d811f2b8f9e0dc1c14f1436', 'Semimembranosis/tendinosis strain (grade 1 - 2)', 'subtype_semimembranosis_tendinosis_strain_grade_1_2_83548c8a09', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('250', 'f3d652308b570e7d1064f4fee587040e43c513aef33c0e0dbde58ff458370786', 'Back referred hamstring tightness', 'subtype_back_referred_hamstring_tightness_6fbd78d98a', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'accepted_deterministic'),
  ('252', '1001e06245ae8ccb3fab3f7fc9bffb304c1d10b7692d5cd27f1614955897426c', 'Sprained superior tibiofibular joint', 'subtype_sprained_superior_tibiofibular_joint_438afb80a7', 'dx_superior_tibiofibular_joint_sprain_b52d941096', 'Superior tibiofibular joint sprain', 'accepted_deterministic'),
  ('253', 'fda6711719c92b4b0c6e8cd6f91eb787d284c88725f356db18afc307e6ce1362', 'Other foot soft tissue bruising/haematoma not elsewhere specified', 'subtype_other_foot_soft_tissue_bruising_haematoma_not_elsewhere_specified_1175637973', 'dx_foot_contusion_6c8a5bb721', 'Foot contusion', 'accepted_deterministic'),
  ('254', '31b647798eb714935f593b277c936a0b2780a47ddb8e1945a027dc2a3b042efb', 'Rectus femoris strain', 'subtype_rectus_femoris_strain_5670ca194b', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('255', 'cd737c028d3f86a2c7b93a8cdca30632cc24189092dd7cb542b37244cfc02163', 'Fracture posterior malleolus', 'subtype_fracture_posterior_malleolus_6f6b6abea3', 'dx_posterior_malleolus_fracture_5a4d097409', 'Posterior malleolus fracture', 'accepted_deterministic'),
  ('256', '9d1d050711f41cd762c67dcd56361aadf083143fa8e894daa77a856a12666136', 'Internal impingement of the shoulder', 'subtype_internal_impingement_of_the_shoulder_1f3a49d1f1', 'dx_shoulder_impingement_c2f2a634b4', 'Shoulder impingement', 'accepted_deterministic'),
  ('257', 'b69ac7db6487a5bb1bba5320d64894e16063f0132a2faefef2f94a80597b8f2f', 'Hamstring tendinopathy with ischial bursitis', 'subtype_hamstring_tendinopathy_with_ischial_bursitis_aac6575ce0', 'dx_hamstring_tendon_injury_f86b1dad5b', 'Hamstring tendon injury', 'accepted_deterministic'),
  ('258', '3c1a5bf09e804026c0ae2ffc359199ece543dd01b9264a80f693f2a7ce09a1fe', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('259', 'd057ffa0cd1fe0a785d552976e73b0a2ebf9ab39222fa925ac7d197b818bac8c', 'Lumbar disc injury with S1 nerve root injury', 'subtype_lumbar_disc_injury_with_s1_nerve_root_injury_e6e87e0789', 'dx_lumbar_disc_injury_a2189aa3a0', 'Lumbar disc injury', 'accepted_deterministic'),
  ('260', '2d4867f8e592651eae03423d2dd8313afafd6518f4bbfd11c302af3e65824c7f', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('261', '2780bda7b6260e5845b5193d26b2c3e9f7f91c50f6ece0b00c26fa49485346fa', 'Unspecified or multiple adductor tendinopathy', 'subtype_unspecified_or_multiple_adductor_tendinopathy_0c38808167', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'accepted_deterministic'),
  ('262', '65eb619661db658021a0a3c41c2a2fa6b80e335ce030b686564599bdbede06bf', 'Ankle multiple ligaments sprain', 'subtype_ankle_multiple_ligaments_sprain_7b65bb0881', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('264', 'f90b64d2b0fb65160f4956d3962cff72eba8ffa6ca016474ffb0848f7fc48eb8', 'Lateral hamstring trigger points', 'subtype_lateral_hamstring_trigger_points_ea90bfdf92', 'dx_lateral_hamstring_trigger_points_ea90bfdf92', 'Lateral hamstring trigger points', 'identity_group'),
  ('265', '621a414852172782756c3e94d007eacacd3c6a1369a65a78d517e38e4da7c1a3', 'Knee peripheral nerve injury', 'subtype_knee_peripheral_nerve_injury_018317e58f', 'dx_knee_nerve_injury_3155d49308', 'Knee nerve injury', 'accepted_deterministic'),
  ('266', '4123ac156519c706d29d3a7d59f5329c8f7c9e1fee5c3716aecd7cf1985b1bd4', 'Chronic thoracic functional pain', 'subtype_chronic_thoracic_functional_pain_3fccab80ba', 'dx_thoracic_spine_pain_9ec9a9f2e5', 'Thoracic spine pain', 'accepted_deterministic'),
  ('267', 'a352eefa574c909f0c0d390aa040423f91b4f718b516fc0a4258a1b0b2692bd5', 'Disc prolapse/disruption', 'subtype_disc_prolapse_disruption_100f0c1c3f', 'dx_spinal_disc_injury_e3b980b6b8', 'Spinal disc injury', 'accepted_deterministic'),
  ('268', '76e6fcd474ea988bda50d9234aca4016e963114e16ec7d99e87131b43df0607f', 'Midfoot joint/ligament sprain (incl Lisfranc)', 'subtype_midfoot_joint_ligament_sprain_incl_lisfranc_282c947645', 'dx_midfoot_injury_3332895405', 'Midfoot injury', 'accepted_deterministic'),
  ('269', '31dbfc9a8aae636871a58c04de6e8e76bf4da68ebbd4959317f32f8549113522', 'Semimembranosis/tendinosis strain (grade 1 - 2)', 'subtype_semimembranosis_tendinosis_strain_grade_1_2_83548c8a09', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('270', '79950881593a9a65b387a661dc7f455337407a079fd9054dd1d3efd324deaeb0', 'Sprain lateral collateral ligament ankle', 'subtype_sprain_lateral_collateral_ligament_ankle_96d9293f86', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('272', '2b876e5108e7050b718b017fcd8fc760a08b0bb891bdda7e15d70da47361804b', 'Proximal adductor trigger points', 'subtype_proximal_adductor_trigger_points_e0737a9324', 'dx_proximal_adductor_trigger_points_e0737a9324', 'Proximal adductor trigger points', 'identity_group'),
  ('273', 'b9762e458f73afda33db92509aad4ca6335b8b36a0ba4d1ddf56e05f0e2f767d', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('274', '78f37b223246f29d2561a4f69b781f2c7104b26978832d306374c171e944d8f5', 'Achilles paratenonopathy', 'subtype_achilles_paratenonopathy_567b7c4104', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('276', 'a0eb949dd28d71f3785805ec172b84692c326ad859df78d9e4b6f494a9514519', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('277', '07e7f3c3a9f04a5cbee6b7d44716682bbf13ed0c433172c75d7fbca1476b2569', 'Achilles paratenonopathy', 'subtype_achilles_paratenonopathy_567b7c4104', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('279', 'ae3a01dea391fb6b8461ba04b6894b7b5353067235b598856c667afe28de002d', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('280', '3af3503db27e6ff74c06cdbcd12deae193b310c4dc17ae285f2e9472d1ca126a', 'Foot pain undiagnosed', 'subtype_foot_pain_undiagnosed_9427f60898', 'dx_foot_pain_116521a908', 'Foot pain', 'accepted_deterministic'),
  ('281', 'feff7be715cf709def4b986be7610b99d8dbe88e8215b31972963957720aa421', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('282', '7aae85cb1d2b4ae0dc77701e0b502841bb48c058e80d020f203644158476afb5', 'Insertional Patellar tendon pathology, incl intratendon ossicle', 'subtype_insertional_patellar_tendon_pathology_incl_intratendon_ossicle_478ba481d8', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'accepted_deterministic'),
  ('283', '8f6a28ad317142dcb8c95b251247b58f70358f70b235d83b25b15df080faca11', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('284', 'cf9be6eb5afd174fffff615ad5933c506eade25beb62f51454f2ed2c6a36271d', 'Chronic lumbar functional pain', 'subtype_chronic_lumbar_functional_pain_f5137cab5d', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('285', '96fe4ed7847ed9c650fd24fe041dcd6b79f72998ba90419540719169ee4f0a5c', 'Chronic lumbar functional pain', 'subtype_chronic_lumbar_functional_pain_f5137cab5d', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('286', 'b3b65aee0b5aa88db94b408db9806939d3f3c557d5c356c4f78c4f50d5ee20e5', 'Lower leg muscle haematoma', 'subtype_lower_leg_muscle_haematoma_ee2865c913', 'dx_lower_leg_muscle_haematoma_ee2865c913', 'Lower leg muscle haematoma', 'accepted_deterministic'),
  ('287', '92ad4b8b82a316f2308f7d8fdda90314f6858314c3be9f16205c5d54fb8a8465', 'Complication of knee laceration or abrasion, including infection', 'subtype_complication_of_knee_laceration_or_abrasion_including_infection_3c043658d5', 'dx_wound_infection_complication_5415c9f38d', 'Wound infection/complication', 'accepted_deterministic'),
  ('288', '97849bbc837cc651aac50ba8bc5c8b34e406e92e7a93d489ef052f08d9159162', 'Hamstring tendon injury', 'subtype_hamstring_tendon_injury_f86b1dad5b', 'dx_hamstring_tendon_injury_f86b1dad5b', 'Hamstring tendon injury', 'accepted_deterministic'),
  ('289', '155ffaf3d40a4068d1c5fad5e2353e2f6c79d9af8301577fde59d8c9a67889fb', 'Plantar heel pain (fasciitis/strain/calcaneal spur)', 'subtype_plantar_heel_pain_fasciitis_strain_calcaneal_spur_7ea3631a44', 'dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b', 'Plantar heel pain/fasciopathy', 'accepted_deterministic'),
  ('291', 'c3f8ba7e46838d4ebd1fa96a87d2edc4d9f9b33a6a1e101b4b2d7cbe6e02886a', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('292', '5eb0b78b6c43fd345e8661fe56319c1873b8782c37ba492ca66fbe6dc65b7bca', 'Proximal adductor trigger points', 'subtype_proximal_adductor_trigger_points_e0737a9324', 'dx_proximal_adductor_trigger_points_e0737a9324', 'Proximal adductor trigger points', 'identity_group'),
  ('293', 'ee8a79990f1bf5d16cd4e0997176ed6d945d8dc1b1529a20bac532240b67fda2', 'Cervical Spine Instability', 'subtype_cervical_spine_instability_87f1adf4cc', 'dx_cervical_spine_instability_658367d444', 'Cervical spine instability', 'accepted_deterministic'),
  ('294', '1ec4a921999ef598177d1ac4f2c1e4706f604bb4a89f3a6004bcaf38ab0ba04a', 'Sprain lateral collateral ligament ankle', 'subtype_sprain_lateral_collateral_ligament_ankle_96d9293f86', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('295', 'c2f9765f5178c01c2302dd73faea42c9f8130a56511b5bca66a37c553eae8f79', 'contusion/haematoma, hip region', 'subtype_contusion_haematoma_hip_region_ffc578cee0', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma', 'accepted_deterministic'),
  ('296', 'f07103cafe6c25b4c58f8e5d09a8d182358c8007dcb5844fb289fb85d3d4a51c', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('297', '667414a2ac6f065166588844c08029604bc1ee45eb981699f41dcbec580b9dd8', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('298', 'e312da631ddb31ebaa258a71c3c82dece0271fbbbcef5583d1625744aeb8322c', 'Abdominal oblique muscle strain', 'subtype_abdominal_oblique_muscle_strain_5b04cf0a3c', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury', 'accepted_deterministic'),
  ('300', '12a42b50f82bc18b378094161c57291d0f13cca7d65b181ca44a777cc3ed0cc0', 'Medial Tibial Stress Syndrome (''shin splints'')', 'subtype_medial_tibial_stress_syndrome_shin_splints_95e1a13bce', 'dx_medial_tibial_stress_syndrome_shin_splints_651f7c8df6', 'Medial tibial stress syndrome/shin splints', 'accepted_deterministic'),
  ('301', 'c31aab9edbe4fa7c837603bede674e7a8cd36dc0e5c3d341bdf15262fe9b1aef', 'Middle phalanx fracture little finger', 'subtype_middle_phalanx_fracture_little_finger_92d1a61d2d', 'dx_little_finger_middle_phalanx_fracture_4f9d2f371a', 'Little finger middle phalanx fracture', 'accepted_deterministic'),
  ('302', '180eb690e49ede30d2d5006d0509318bf8cff597749147e9f67ed4854872394f', 'Lumbar pain with hamstring referral', 'subtype_lumbar_pain_with_hamstring_referral_c859c82cf8', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('303', 'edbddb8e8eaa312c5c9f5f443986dec1f909798ef18fc4962609136f43b97482', 'Epistaxis', 'subtype_epistaxis_671a1d1cf3', 'dx_epistaxis_671a1d1cf3', 'Epistaxis', 'accepted_deterministic'),
  ('304', '10144b722204e6edb6966e824cc90632339389f9824c8443b8ece10cb18be010', 'Rectus femoris strain', 'subtype_rectus_femoris_strain_5670ca194b', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('306', 'c8844dce2020acae6599a25c19c7e5538cc23ab9a5320e23cfa660390a28640f', 'Chronic thoracic functional pain', 'subtype_chronic_thoracic_functional_pain_3fccab80ba', 'dx_thoracic_spine_pain_9ec9a9f2e5', 'Thoracic spine pain', 'accepted_deterministic'),
  ('307', 'e81ee91a5b1dfbbad1cef2980b8447e0fe44121818a0a684bfb2d58f32ebb384', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('308', 'bbf7fb543a7c1695de4243dc89fed29a6d1cfb2a0b3d3155d49c81162b70ea89', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('309', '1e9fda2b05c30ff49e2ac85c1aff9ce877940cc94e63f5bd3aa92d7468aeeb28', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('310', '281e456765844649a9a1e749e4b9be07000547bd940ec7c80649d3c8981c1df8', 'Distal quadricep haematoma', 'subtype_distal_quadricep_haematoma_01c745cc46', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('311', '871ad50ec4257a6b6a3932c02e0827500822a6dfb456d03e002ca8d65b75a1b3', 'Arthritis of midfoot', 'subtype_arthritis_of_midfoot_ea720a8251', 'dx_midfoot_arthritis_881bf0b51b', 'Midfoot arthritis', 'accepted_deterministic'),
  ('312', '6cd95553b86788f2e16d96ad55d1e6c2ebf071ec3ac42b692e8840e3f99eda5b', 'Hip Joint Inflammation/Synovitis/Other Biomechanical Lesion', 'subtype_hip_joint_inflammation_synovitis_other_biomechanical_lesion_b7683e426f', 'dx_hip_joint_injury_07aa18de20', 'Hip joint injury', 'accepted_deterministic'),
  ('313', '9b95ff2584354f38f0c4e2b076720872fcf5875de938f8f0c45c0683a1dc0036', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('314', 'f8fa9497047a3c975a1d1ce0d072823726c123edac281294ee605e08f85b64b4', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('315', 'b17f5e625e91d4db61b4fb3a36bc6817bb8ec7db0afdddc08a518e93f0e5092c', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('316', 'b7096680d68bc1bddc18012f4b9c57f50a94f1a4d590b90d93e10d668025a24f', 'Rectus femoris strain', 'subtype_rectus_femoris_strain_5670ca194b', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('317', '615f18a77b0ece70c3c91626602351777cea0f1aaee357ab3f0cf3b19c5f7993', 'Hip Joint Inflammation/Synovitis/Other Biomechanical Lesion', 'subtype_hip_joint_inflammation_synovitis_other_biomechanical_lesion_b7683e426f', 'dx_hip_joint_injury_07aa18de20', 'Hip joint injury', 'accepted_deterministic'),
  ('318', '3a3b3be9c51e0cf989ce91326d5414b407272b7f55b0d9a1fca4e0ff383fb971', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('319', '6d16ea4d181c46d518d270e310f037b4c3874d753cd96b9cbcc43a2dbb198bc9', 'Ankle synovitis/Impingement/Bursitis', 'subtype_ankle_synovitis_impingement_bursitis_518a389deb', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis', 'accepted_deterministic'),
  ('320', '31910169ac0da4d8047ecad763020d7d38870558dec3a880f8ceef4f980f59f1', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('321', '2d73fab4ffd9d621f2caf73ba0866502db6bec662e059bc7cb32ee19409d7c99', 'Dislocated shoulder', 'subtype_dislocated_shoulder_24b9571112', 'dx_shoulder_dislocation_2067688fdd', 'Shoulder dislocation', 'accepted_deterministic'),
  ('322', 'a935c45767f3bb86f3cd89e0e0454e49b8fc6040700d565761014e2bd0a81197', 'Complication of knee laceration or abrasion, including infection', 'subtype_complication_of_knee_laceration_or_abrasion_including_infection_3c043658d5', 'dx_wound_infection_complication_5415c9f38d', 'Wound infection/complication', 'accepted_deterministic'),
  ('323', '9ef07e13f860fd563bb1237e91370c6db43da5cf432b8a866677737824830cb4', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('324', 'a1d3c0a8ebc05d5ede364d2cea977f3cfd566f1fe44a7d501cfe6080489ee55d', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('326', '97612bcd84465e13216432e259148bd89f5635e62b6bc622c99eb85438e171d1', 'Rectus femoris strain', 'subtype_rectus_femoris_strain_5670ca194b', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('327', '4c15ae08051855896836ff1ef644e33738904c7b087d974a90ea804d17a53f51', 'Dislocated patella', 'subtype_dislocated_patella_26b8cc45c3', 'dx_patellar_dislocation_0c3c5e687e', 'Patellar dislocation', 'accepted_deterministic'),
  ('328', '0edb1f1bba24a56ea066006a09db2b2e5b44a793b422512b0e33a28d3a3e27f1', 'Back referred hamstring tightness', 'subtype_back_referred_hamstring_tightness_6fbd78d98a', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'accepted_deterministic'),
  ('330', '573f6381e7826b758b6ff7a76b7ff4cfa333056f518bcb60a5d25ffe5b0a9f3e', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('331', 'cc959415c0102d08f0683ca39ec0dc65ccf2b2101128e51b27e82c65c7448b41', 'Patellar tendinopathy', 'subtype_patellar_tendinopathy_3ea4d4d1bf', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'accepted_deterministic'),
  ('332', 'd21efa9d18ff69a674e5de71d760ee0ac6c7b753d47e29a17ab55adcbe8be6c4', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('333', '0fa0429b7a3d716cdf6c78038e2f78be2242c2336e5cf128262e7dbe37215478', 'Rectus femoris strain', 'subtype_rectus_femoris_strain_5670ca194b', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('334', 'b0930142b46b0d2ef9676083fb6865b062005a90ab868bbfc895c5fc597a7459', 'Sprain lateral collateral ligament ankle', 'subtype_sprain_lateral_collateral_ligament_ankle_96d9293f86', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('335', '5181dc0525cdd6b97108a6f28082d1ca18026166b51b764afc4ea4bd3872fc64', 'Tibialis posterior tendinopathy', 'subtype_tibialis_posterior_tendinopathy_521e81b1a1', 'dx_tibialis_posterior_tendon_injury_8ddfcac54e', 'Tibialis posterior tendon injury', 'accepted_deterministic'),
  ('388', 'ea11e429e3b9abe1e0784d9ad46fe83f9908b376381e88585f52c221f1f35ae8', 'Lateral gastrocnemius strain', 'subtype_lateral_gastrocnemius_strain_26ac8b9d04', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'accepted_deterministic'),
  ('393', '004292e8a3d96ebd32e9f7eac8d9f0468fbd2171f0aae1ea46be96659790e85d', 'Elbow sprain or jarring injury', 'subtype_elbow_sprain_or_jarring_injury_bc7b7216af', 'dx_elbow_sprain_16dd0e91eb', 'Elbow sprain', 'accepted_deterministic'),
  ('396', '1bd34423845cda898c9733df721206777d67504166caf71681de5f69b8c987ae', 'Contusion or haematoma of the thigh', 'subtype_contusion_or_haematoma_of_the_thigh_7b6847aafb', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('397', '90b7c71d7c518692efedfe6912bfe5090f09da778872b7106be0f27ed8f719ae', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('398', 'b74230c6e9209b32c6ba36f7157762683a9c93930e83ad60b069a18e39102494', 'Wrist fibrocartilage tear', 'subtype_wrist_fibrocartilage_tear_aead44491e', 'dx_wrist_fibrocartilage_injury_fddc60c8f6', 'Wrist fibrocartilage injury', 'accepted_deterministic'),
  ('400', '178af18707c162506f1db8098a6c765c9724ee0f7322859580f53368134a45d3', 'Grade 3 lateral ankle ligament rupture', 'subtype_grade_3_lateral_ankle_ligament_rupture_510bf242a2', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('401', 'a069dcd43a6e7385e9c1155303ed85f5529bef97e1886364b74f1a1daac6ef17', 'Unspecified or multiple adductor tendon injury', 'subtype_unspecified_or_multiple_adductor_tendon_injury_5e4c014762', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'accepted_deterministic'),
  ('402', '0fbb5bd3d2ce95e509371db8ce663db3f0b2c34a67e0f474ecccba6583ce96f6', 'Acromioclavicular joint sprain', 'subtype_acromioclavicular_joint_sprain_0e20c4521f', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('403', 'beeab91b0baa713df379693e70c95d161f0f543603ee605f04fc17650ff9288f', 'Lumbar contusion or haematoma', 'subtype_lumbar_contusion_or_haematoma_38a96fdddd', 'dx_lumbar_soft_tissue_contusion_125139d685', 'Lumbar soft tissue contusion', 'accepted_deterministic'),
  ('405', '25f6b4b0febcb6f69a2be13aea7e5f2b937592ab5f8ab59bc49823af023de125', 'Lateral meniscal tear', 'subtype_lateral_meniscal_tear_8f122c7931', 'dx_meniscal_injury_b166306f7d', 'Meniscal injury', 'accepted_deterministic'),
  ('408', '0a415204b08693dc6e9aa27e4514a7d42c981c23153e9534c342e5f77deadca2', 'Rectus femoris strain', 'subtype_rectus_femoris_strain_5670ca194b', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('409', '6eda97cec766d176ae34f8d3b91ccfc0592820f21e4522800e04705866d72691', 'Adductor magnus tendon strain', 'subtype_adductor_magnus_tendon_strain_468986470b', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'accepted_deterministic'),
  ('411', 'a4ee8303bdf7c6b745a28d663e0b8c7611347a80e068e7858c01fd664338aed4', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('412', 'd554edba20cf5515dd08372f1100a7a5f7a3fe869d4d06d2a215f18c50a52c7f', 'Lumbar soreness or muscle spasm', 'subtype_lumbar_soreness_or_muscle_spasm_d5cbfcf03b', 'dx_lumbar_soreness_or_muscle_spasm_d5cbfcf03b', 'Lumbar soreness or muscle spasm', 'identity_group'),
  ('413', '0d3b71fd2f97475a710abe17a0e57a22c7f8107bcd6dd1cfc61abb9f0d249630', 'Cervical spinal canal stenosis', 'subtype_cervical_spinal_canal_stenosis_15786dee1f', 'dx_cervical_spinal_canal_stenosis_15786dee1f', 'Cervical spinal canal stenosis', 'accepted_deterministic'),
  ('415', 'edf064d612d11cbcea1f1cdb80ef1125eb05edc5dc3ef7ce55e7d56901310f74', 'Other hip/groin bruising or haematoma', 'subtype_other_hip_groin_bruising_or_haematoma_a84d440f90', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma', 'accepted_deterministic'),
  ('419', '12d31fbc0788df45ebc1a8060ed9e271320dff7f2bacf7a5add8c0e79188d5b1', 'Abdominal oblique muscle strain', 'subtype_abdominal_oblique_muscle_strain_5b04cf0a3c', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury', 'accepted_deterministic'),
  ('422', 'eba3ddf0825494dce181e08416c7738b28a03e1869aebd0d1e12d472c61455eb', 'Sacroiliac joint injury or pain', 'subtype_sacroiliac_joint_injury_or_pain_1dda22b9c3', 'dx_sacroiliac_joint_disorder_69fe12ec92', 'Sacroiliac joint disorder', 'accepted_deterministic'),
  ('426', '3b8294777e5432e722aa94a2248a69eec4c345b37b674aa08220ffcdd43d8901', 'Abdominal oblique muscle strain', 'subtype_abdominal_oblique_muscle_strain_5b04cf0a3c', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury', 'accepted_deterministic'),
  ('428', 'c26e66e16803bf2007decac3ecae00aa9dee69dd04bad1320413d89002706b26', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('431', '03e6e31824293685740adb681c53a6322b2a90993b7991192af62c4c20145008', 'Thigh soft tissue bruising or haematoma, not otherwise specified', 'subtype_thigh_soft_tissue_bruising_or_haematoma_not_otherwise_specified_ce967619c0', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('432', '9c4317246315000fff4c675d083274f44a283ab50c0b6a5ad1e56d98757af2c9', 'Complication of proximal or distal interphalangeal joint dislocation', 'subtype_complication_of_proximal_or_distal_interphalangeal_joint_dislocation_d5abed3dd6', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'accepted_deterministic'),
  ('433', 'bd2f64b704940ce5204000b11ff52325b3ec889b57149f91a8b20ca936e41280', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('443', '4a39b8a7f0b3604a3519db6fac2b6f6d0a0be6c9c24a700834fdea5d5e3681ed', 'Bone contusion of the knee', 'subtype_bone_contusion_of_the_knee_5959d5ecf3', 'dx_knee_bone_contusion_ba129fc033', 'Knee bone contusion', 'accepted_deterministic'),
  ('444', '95d62703c3413ab0966799badbce78d8cd0575f70dc9a222af074163607627ca', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('454', '58603e21290d822294304e9dfa1725a03d181735b936e82d0dbef92b561dff77', 'Glenohumeral joint sprain with chondral or labral damage', 'subtype_glenohumeral_joint_sprain_with_chondral_or_labral_damage_5027b687b2', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('456', '8669e0823da04469a9233f37f0bd2ef38f4e35c54b5f4227ce595ee519ed44bb', 'Calcaneofibular ligament sprain', 'subtype_calcaneofibular_ligament_sprain_246839c949', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('457', '76fdc1e904d96cc0500b4234ecdb8cd9287abecbf7b537805ff4b4d0cd6b469f', 'PLC injury with chondral or meniscal injury', 'subtype_plc_injury_with_chondral_or_meniscal_injury_cfe4066c89', 'dx_knee_posterolateral_corner_injury_a4c4c64579', 'Knee posterolateral corner injury', 'accepted_deterministic'),
  ('458', 'e2c7922524a5a9a0a0fd2a6ecc952c44a072535ec359efd036b2f3b75603abb9', 'Lateral hamstring trigger points', 'subtype_lateral_hamstring_trigger_points_ea90bfdf92', 'dx_lateral_hamstring_trigger_points_ea90bfdf92', 'Lateral hamstring trigger points', 'identity_group'),
  ('468', '4d74001da43a9e6425217e61688c611bf69896eed3c2d85e05d3a7d7f6a7c044', 'Ankle osteochondrosis', 'subtype_ankle_osteochondrosis_0b34b510e3', 'dx_ankle_osteochondrosis_0b34b510e3', 'Ankle osteochondrosis', 'accepted_deterministic'),
  ('469', 'a0fa69f5d64c59bd429acb26ac52507a40f276d2d9ba1f5a7488a3e2916f4195', 'Medial collateral ligament strain or rupture with chondral or meniscal damage of the knee', 'subtype_medial_collateral_ligament_strain_or_rupture_with_chondral_or_meniscal_damage_of_the_knee_b182d1fa72', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('470', 'd24864148c40dd326b8dd0dff304247d0ee91496398096645b1625bd863b5dd3', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('471', '0becfbf23420e31ee73c5d4cd6d31614bca1116b29bb29dee74ace171ab191b7', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('472', '9c9f07fa55cb3b7f2b47385ad39ccaa7430c263bf60a05422b81e741c38581c5', 'Head or facial fracture', 'subtype_head_or_facial_fracture_3497d30cee', 'dx_head_or_facial_fracture_3497d30cee', 'Head or facial fracture', 'accepted_deterministic'),
  ('473', '099da26bc8b7aeb44ea395c3a7363ee96fbe978b12a0003739dc5f4332b09bea', 'Acromioclavicular joint sprain', 'subtype_acromioclavicular_joint_sprain_0e20c4521f', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('474', '73a10178a08cf2c5103604e66ccb99ce38ceb092daacde814c732d5fcdb501bb', 'Ulnar collateral ligament strain or tear of the elbow', 'subtype_ulnar_collateral_ligament_strain_or_tear_of_the_elbow_88b7a1984e', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury', 'accepted_deterministic'),
  ('478', '3fa343e98b0489027f08a507fcba4b9ed2905d34654b35d444ddbbfec685ff34', 'Finger flexor tenosynovitis or tendinopathy', 'subtype_finger_flexor_tenosynovitis_or_tendinopathy_fe8b52c602', 'dx_finger_flexor_tendon_injury_93dca2c764', 'Finger flexor tendon injury', 'accepted_deterministic'),
  ('482', '8f5e9a266c82d95ae3c31b39a9a1d2b97ac6c0079333de1ccf5d4e0210944320', 'Adductor longus tendon strain', 'subtype_adductor_longus_tendon_strain_c1fa29e878', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'accepted_deterministic'),
  ('484', '5ed46ccda322f4ce5206ecd21b97edb44a826382abb58d4087f1d30c37cd0305', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('485', 'd6474a38f6eed60d477a5f1a9d772961ea2f8d2db5ee999ef29fb87bb3818cc8', 'Rectus abdominis trigger points or spasm', 'subtype_rectus_abdominis_trigger_points_or_spasm_0e179cf857', 'dx_rectus_abdominis_trigger_points_or_spasm_0e179cf857', 'Rectus abdominis trigger points or spasm', 'identity_group'),
  ('486', '4c41edd94f55f09808a20cc28a1dcd9c540fea0333f3aeb0257d1de3c11b62c5', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('487', 'd82dd65b8e55e6d68ef8f42aea9cc9e82f5e18ae6f7e5b1baf0f24e8ffb11f38', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('488', '289341186e95660283db982979bf2bed042f0a0824f160c8d09d10db7646c0d1', 'Glenohumeral joint sprain with chondral or labral damage', 'subtype_glenohumeral_joint_sprain_with_chondral_or_labral_damage_5027b687b2', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('489', 'b8aa894672d83c2f067572d10b0094f145e90b8798ccafde821ec5f4b42ad645', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('490', 'c36222720060ecb5475fb7a578a5d0fdd0e970d187654be86583059b1359f6e5', 'Hamstring tendon injury', 'subtype_hamstring_tendon_injury_f86b1dad5b', 'dx_hamstring_tendon_injury_f86b1dad5b', 'Hamstring tendon injury', 'accepted_deterministic'),
  ('491', '7cd00b5fb81d2d19acbde11cda762249b263921e0859ea8f3c73f23d3faae5ff', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('492', '9aee35a98d006908a738db2837a99adaa41a7dd5cae8fbbd3c55f518a554630e', 'Distal biceps tendon rupture', 'subtype_distal_biceps_tendon_rupture_a28ef09d0b', 'dx_biceps_tendon_injury_cbd11d2125', 'Biceps tendon injury', 'accepted_deterministic'),
  ('495', '97263bed643d3514d3ffb98921cdb2a400bcc9acfb38c366b0f30f94be161d94', 'Lower leg pain, undiagnosed', 'subtype_lower_leg_pain_undiagnosed_b7965e156e', 'dx_lower_leg_pain_64d4d83c4b', 'Lower leg pain', 'accepted_deterministic'),
  ('497', '07afc39ab0a47742b175b93911e30b1807353d825cbbc81c4e0ccde610e949ed', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('498', '5a8478cf221d426b2a3c759f16538436c0077b67920447359f352f15eebc6049', 'Knee osteoarthritis', 'subtype_knee_osteoarthritis_088b6b8911', 'dx_knee_osteoarthritis_088b6b8911', 'Knee osteoarthritis', 'accepted_deterministic'),
  ('499', '0244d092e7160cab078ff27c3390d2992bf7dbc3ce2d14341b6539c5c9a3a38a', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('500', '9c55452f85e16f6ba02479bf5e405921864284d741b0000915bdc2ef6c6f9605', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('502', '4b7eb504fc58ed70f928fa677bfb1e4691cb7fcdb6f60bb9763dd812f7a11abe', 'Sports hernia or abdominal tendinopathy', 'subtype_sports_hernia_or_abdominal_tendinopathy_f75d7edd39', 'dx_sports_hernia_or_abdominal_tendinopathy_f75d7edd39', 'Sports hernia or abdominal tendinopathy', 'identity_group'),
  ('503', '3b780f0e8f960619e3b58b20c2216f2c116d8e35d5d2c165db8836f9be48ef3f', 'Sports hernia or abdominal tendinopathy', 'subtype_sports_hernia_or_abdominal_tendinopathy_f75d7edd39', 'dx_sports_hernia_or_abdominal_tendinopathy_f75d7edd39', 'Sports hernia or abdominal tendinopathy', 'identity_group'),
  ('505', '5bba4b49e7c66c4c13605e163685d3cdd17286bc56847f4565987cee30a7418c', 'Acute anterior internal impingement', 'subtype_acute_anterior_internal_impingement_71a3111af6', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis', 'accepted_deterministic'),
  ('509', 'ba3b21fe9d806b643765bce4ea1ce5076cab10d32ebb408656855d42d25c3058', 'Unspecified or multiple adductor tendon injury', 'subtype_unspecified_or_multiple_adductor_tendon_injury_5e4c014762', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'accepted_deterministic'),
  ('510', '71a43b157b9eadfe205857914a9f6e7eebdb0f3fa3ea35e358d311db0c919b53', 'Grade 3 lateral ankle ligament rupture', 'subtype_grade_3_lateral_ankle_ligament_rupture_510bf242a2', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('511', '8d6fdf50723fdd8eb913b5e283346afc5f4076e2a0435c8dccc40740901cdbe8', 'Lateral hamstring trigger points', 'subtype_lateral_hamstring_trigger_points_ea90bfdf92', 'dx_lateral_hamstring_trigger_points_ea90bfdf92', 'Lateral hamstring trigger points', 'identity_group'),
  ('512', '02c5506f5ff668fd537127cb04b8227c23a298d30ed663787736408acb559c32', 'Sportsman''s hernia', 'subtype_sportsman_s_hernia_c9eeb6b61d', 'dx_sports_hernia_ad99f8552f', 'Sports hernia', 'accepted_deterministic'),
  ('514', '08be9dee5d7a985618ac8052149e9896c703f2834753f92e0cd6ab2c8529fc68', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('515', '52c0d4ba949f99b957c9549f2f268ff960a70e997a949154dad5227fa3c9506e', 'Grade 3 hamstring strain', 'subtype_grade_3_hamstring_strain_6183bcd886', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('516', 'bcfadd072104c77ee24c1902e34c0735e6689e7e9b8ef74710c73e630b70848a', 'Anterior talofibular ligament sprain', 'subtype_anterior_talofibular_ligament_sprain_f8c3b9037d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('518', 'fc37670e5c2fff021361f005f13f8fb4906efc503f9971978230f72692f9d76a', 'Cervical nerve root compression or stretch injury', 'subtype_cervical_nerve_root_compression_or_stretch_injury_31f98c0ce9', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('520', '3a1c1274597911d28afb84d8f1d4343ebc56e8d27d215b0c7fc85f977b986530', 'Calf contusion or haematoma', 'subtype_calf_contusion_or_haematoma_8c5a27a266', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('521', 'ac221b7558eb97260da316b4f3b75d017b571d72a2bf0d0de158a518ba1e6e37', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('523', '1c1aec75ae4eb767a1c89000801c6e4406a0b5acfb48b1f72ce029bb3f2d992c', 'Nerve entrapment in the thigh', 'subtype_nerve_entrapment_in_the_thigh_51c9764ad5', 'dx_thigh_nerve_entrapment_cf6619a0d0', 'Thigh nerve entrapment', 'accepted_deterministic'),
  ('524', 'dddb74c7ad6fd91132de97385e8ed3c13552e2810b1d34de8118a10ae8deb1e1', 'Anterior talofibular ligament sprain', 'subtype_anterior_talofibular_ligament_sprain_f8c3b9037d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('525', '2922df62e0e133a7fd17cc7334ffbcac8509969e71e9f20ce9fee03df3f99296', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('526', '386ba9339d5bb1c56b005b9bc6205e99cab713313ef8011944b3527832e18984', 'Hip joint sprain or jarring injury', 'subtype_hip_joint_sprain_or_jarring_injury_d7c763b23f', 'dx_hip_joint_sprain_6ee81972bd', 'Hip joint sprain', 'accepted_deterministic'),
  ('528', '77a079cee6879408387adf3640555dd9dbeb6047376f9d75ef54a9eff3386400', 'Sternoclavicular joint sprain', 'subtype_sternoclavicular_joint_sprain_6316623d10', 'dx_sternoclavicular_joint_sprain_6316623d10', 'Sternoclavicular joint sprain', 'accepted_deterministic'),
  ('529', 'fc761f453a2cc7a64a39369250eef1aabcf39374068ed58cc5a2141ee8db7726', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('530', '6c606677cdf0270112f98cd5cfbbe74a3c355205670d61294bd23fc8b3fffddb', 'Medial gastrocnemius strain', 'subtype_medial_gastrocnemius_strain_bae661fc6e', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'accepted_deterministic'),
  ('531', 'cf57e99c4af7495ee70842541ea96947839393336d0df060b43196c5b21ffd13', 'Pectoralis major muscle strain', 'subtype_pectoralis_major_muscle_strain_5887d37d12', 'dx_pectoral_muscle_injury_981511cfe1', 'Pectoral muscle injury', 'accepted_deterministic'),
  ('535', '0600a3aabc3e8a87bd272ea48f53385f0a9fa520cc8d59814e97ff542f37e7f0', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('536', 'cfb320dec0b63d885bc6b9d5265e6f9f6270d9f60c84d30143a0e2b585ef3352', 'Ulnar styloid fracture', 'subtype_ulnar_styloid_fracture_fe63bab748', 'dx_ulnar_styloid_fracture_fe63bab748', 'Ulnar styloid fracture', 'accepted_deterministic'),
  ('539', 'ad8d807ca13ee5d54b3d7c7d1b2237955e61ee20b1d45495f5642c3b0209d781', 'Patellar tendinopathy', 'subtype_patellar_tendinopathy_3ea4d4d1bf', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'accepted_deterministic'),
  ('540', '886a66afade99c7e4461fc1f1c1ca4dc74d6c0da8f2d509260cbef10cfe48342', 'Patellar tendinopathy', 'subtype_patellar_tendinopathy_3ea4d4d1bf', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'accepted_deterministic'),
  ('576', '8e57cc86431fe3e3bb76dbb7be717bf3ecb4f7245e04f4b51496101c667b2dba', 'Glenohumeral joint sprains', 'subtype_glenohumeral_joint_sprains_0aefa97c55', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('577', '6e53b38d72e8ed93966cd47e64e985d0c352fc38f42f7716101ed67d51413a58', 'Quadriceps strain or tear', 'subtype_quadriceps_strain_or_tear_17ff226482', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('578', '75353cdadafd21c973d409e3ab3c57f18d0ace02ea98dc57358ffa6bd8877f33', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('579', '8ceaa54e3b69fcca842806ca4eabe42c7d6434d1384a6f92dbc03eef7ea67771', 'Rectus femoris strain', 'subtype_rectus_femoris_strain_5670ca194b', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('580', '8cee4da8661a9cd7f5ee027ac4d1f386aae6a4ad0164a4293baf8ff4b2cf0f9d', 'Elbow hyperextension +/- strain anterior elbow structures', 'subtype_elbow_hyperextension_strain_anterior_elbow_structures_2510e40065', 'dx_elbow_injury_7100f71f81', 'Elbow injury', 'accepted_deterministic'),
  ('585', '5be5be31becdc0ab28234f9c0599b2d2492ee5617b02df27d035c220536b2612', 'Biceps muscle strain', 'subtype_biceps_muscle_strain_9122d2b9c0', 'dx_biceps_muscle_injury_3a5679b9a5', 'Biceps muscle injury', 'accepted_deterministic'),
  ('586', '5bf98c52facaf2248db92676b62684b4010ef8f26f515495209a4240c9e119e3', 'Grade 1 A/C joint sprain', 'subtype_grade_1_a_c_joint_sprain_1ad80c156f', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('587', '723fb8071c64d4064eb210728924553a6d686109d111ea8fcf2e02488778974a', 'Forearm muscle soreness', 'subtype_forearm_muscle_soreness_347a7be337', 'dx_forearm_muscle_soreness_347a7be337', 'Forearm muscle soreness', 'identity_group'),
  ('588', '2ea53028dac437b813a3382d59d6a9bc08d5579ee2e8c6faef7ea528b78bb56c', 'Mid/distal plantar fasciitis', 'subtype_mid_distal_plantar_fasciitis_0161a8fbf8', 'dx_plantar_fascia_injury_ec4d3703e9', 'Plantar fascia injury', 'accepted_deterministic'),
  ('591', 'cb61fce2383ac5fe7160137c6a45c7f8c488281d188b7274cb0201b7198b3ebf', 'Knee abrasion', 'subtype_knee_abrasion_72b0fd7a46', 'dx_knee_wound_7498252643', 'Knee wound', 'accepted_deterministic'),
  ('592', '7cc4f235d7c677656c9f630b47c2d1fa6561ea4a50e72f9f538b39035f591bed', 'Elbow abrasion superficial', 'subtype_elbow_abrasion_superficial_cf7a703ca2', 'dx_elbow_abrasion_fca1398b6d', 'Elbow abrasion', 'accepted_deterministic'),
  ('593', '966f46369adc500027213978e677e3f9d0644399d8651bad47f4a07649468ed1', 'Wrist and Hand Laceration/Abrasion', 'subtype_wrist_and_hand_laceration_abrasion_05f303c991', 'dx_hand_wrist_laceration_or_abrasion_35c31d7555', 'Hand/wrist laceration or abrasion', 'accepted_deterministic'),
  ('594', '17814538fda17b304a51f986ed323d2995973abfa1fa1c04c32d0dea333c213a', 'Disc prolapse/disruption', 'subtype_disc_prolapse_disruption_100f0c1c3f', 'dx_spinal_disc_injury_e3b980b6b8', 'Spinal disc injury', 'accepted_deterministic'),
  ('595', 'd50bb595e24afc5e932a5f1085b97b7554c39b09c4d4999c08191eef99e251d6', 'MCP joint dislocation little finger', 'subtype_mcp_joint_dislocation_little_finger_0f5416a79b', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'accepted_deterministic'),
  ('597', '3e61479ba1e0229b599be635493fc931c54f455939110f4c471f1426673047f6', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('598', '3b3a698b51de4ebeaaa3feeb17a81055a34c38fe63fcff63c386d501fabc76c5', 'contusion/haematoma, hip region', 'subtype_contusion_haematoma_hip_region_ffc578cee0', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma', 'accepted_deterministic'),
  ('599', '2ca495a8b76fb61b2102545a886d8ba58c78bca4301ccefe0058db5d8d7c6809', 'Other stress/Overuse Injuries to Thigh', 'subtype_other_stress_overuse_injuries_to_thigh_a3cb236c2f', 'dx_thigh_overuse_injury_3d503881d3', 'Thigh overuse injury', 'accepted_deterministic'),
  ('600', '9e2ac4051d459c7298dc72cfe7efc21429304a588744934d7de210d1346fae09', 'Knee abrasion', 'subtype_knee_abrasion_72b0fd7a46', 'dx_knee_wound_7498252643', 'Knee wound', 'accepted_deterministic'),
  ('604', 'cf1abb76a433a5a155c07db862c6554fa4ca7e71f7ad13d3e744e8b2bd4f299d', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('610', 'f5868e17631f6d22fec8fee8948e904c886915a88c4d0e3a027d6006fada8058', 'Cervical disc Injury', 'subtype_cervical_disc_injury_13c8608a7d', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury', 'accepted_deterministic'),
  ('611', '02f1dfcd7c382c33ce74b1d7307a01e04d7f5d547b541d1ca0ede69c636f3069', 'Other Ankle Pain/Injury not otherwise specified', 'subtype_other_ankle_pain_injury_not_otherwise_specified_3d735e2c86', 'dx_ankle_pain_de6b615afc', 'Ankle pain', 'accepted_deterministic'),
  ('612', 'c1510f70464cfdf5e659a7272db18b4c1d25e3bf5deab8e1fca1f97ec8976648', 'Metacarpophalangeal joint sprain', 'subtype_metacarpophalangeal_joint_sprain_103ce7f526', 'dx_finger_mcp_injury_6c586feb13', 'Finger MCP injury', 'accepted_deterministic'),
  ('613', '409e80e0929b2d03a92964108d3e672b69715d7add9d6698e81cbedc9dccc915', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('614', '16fb06d3314f1c1277584a78fa50ebd4e1471af32e6b72b7910689cfd520310f', 'Grade 1 A/C joint sprain', 'subtype_grade_1_a_c_joint_sprain_1ad80c156f', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('615', '71d3d530a906d22cbd7228a49b0c8a25987825452a178eb956a52ca8705db2e7', 'Lower Leg Laceration', 'subtype_lower_leg_laceration_ed4f2ec77f', 'dx_lower_leg_laceration_5e3fbc19d5', 'Lower leg laceration', 'accepted_deterministic'),
  ('616', '10931c0f4a8633c42159196d80d0e1b1bc262077a35f86cd109aef33db07c99c', 'Elbow abrasion superficial', 'subtype_elbow_abrasion_superficial_cf7a703ca2', 'dx_elbow_abrasion_fca1398b6d', 'Elbow abrasion', 'accepted_deterministic'),
  ('617', 'e1e46218cb5c21d18aafcdd603723a78770d0f6c0af034790ef4e4d74e34a488', 'Knee abrasion', 'subtype_knee_abrasion_72b0fd7a46', 'dx_knee_wound_7498252643', 'Knee wound', 'accepted_deterministic'),
  ('618', 'eda962e9bd42ca8ac0f6458d4d0e84149720eda5a9be822344ed1a617b0cae21', 'PIP joint dislocation middle finger', 'subtype_pip_joint_dislocation_middle_finger_7a862b7a80', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'accepted_deterministic'),
  ('619', 'b873578b5818c97208eed7393760adc59b9f56dae676f1861f0625596d338bb6', 'Rectus femoris rupture', 'subtype_rectus_femoris_rupture_41699ce0cb', 'dx_rectus_femoris_muscle_rupture_8741b14c71', 'Rectus femoris muscle rupture', 'accepted_deterministic'),
  ('620', '2fd65618d1feeaa2d3ca1e62c3343fcd10d2f8c776ca270b3f9701bc2156b9cb', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('621', 'c071f429e661c460d92d76242a0a2c350c761a898c4de20c70083d676fbafcfe', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('622', '7d79411e2d4f6a4c4b7486c568856d1da5f5c22454b0511529d78673c41dc7e7', 'Anterior talofibular ligament sprain', 'subtype_anterior_talofibular_ligament_sprain_f8c3b9037d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('624', 'e2cad80f014612874c589cc2cb6dec8f3d649ab7a7acf5696937f7232d5c7501', 'Head/facial laceration', 'subtype_head_facial_laceration_850da462e6', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('625', '119a94e81869fbb4d02904a2edfa29d3391ec6b0c502219df4ed158559173fcc', 'Head/facial laceration', 'subtype_head_facial_laceration_850da462e6', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('626', 'c397bdb034bd1596124bdc151fda2241b2276723a0036d4b209b0bece36a7b1e', 'Concussion with Criteria 1 video signs', 'subtype_concussion_with_criteria_1_video_signs_624c97508a', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('633', 'f16cea8ab559cd4de3ba00bf6d169b0b93eedd50cc1afed14c54b349f7eff035', 'Quadriceps tendinopathy +/- suprapatellar bursitis', 'subtype_quadriceps_tendinopathy_suprapatellar_bursitis_e80ae339d0', 'dx_quadriceps_tendon_injury_08ea99efaf', 'Quadriceps tendon injury', 'accepted_deterministic'),
  ('634', '3f94b2c27ef4649ff312d07e1ce636d6da2a58d191dfdbf1ed9152216f72cde9', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('635', '1772b60dfea2ae249b1e67ee2af78d012119adffcf2a56f4e6b3e888c5202c7c', 'MCP joint dislocation little finger', 'subtype_mcp_joint_dislocation_little_finger_0f5416a79b', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'accepted_deterministic'),
  ('636', 'e66e0ca2ec07adb672ae3d53c60e7156bc9cc9abe0b199df74b626cc750cc6c1', 'Knee Pain/Injury Not otherwise specified', 'subtype_knee_pain_injury_not_otherwise_specified_f2690253b3', 'dx_knee_pain_609ce718bc', 'Knee pain', 'accepted_deterministic'),
  ('638', '8f7d944f66787ef171a066f8323fe31fdb283f9a477c11fbf09c2d0529300fb7', 'Neck pain undiagnosed', 'subtype_neck_pain_undiagnosed_3e98145efc', 'dx_neck_pain_58ed6a0781', 'Neck pain', 'accepted_deterministic'),
  ('639', '430b5452897d5aa5d884686ea62128d7e9cedac3ab2f7d2331f4ba3bf0171e4b', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('644', 'e90549baeb9b2aeaadc1714d7565462e1f9a1ad02b7b0e05c61546db68ae20df', 'Bruised ribs/chest wall', 'subtype_bruised_ribs_chest_wall_0c223ac8bd', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('645', 'cdd1559478ea4fb6cbe307d65a5c14c9bfdfe3f7384f90f4295f28ea75e1f157', 'PIP joint dislocation little finger', 'subtype_pip_joint_dislocation_little_finger_e9c08ade1f', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'accepted_deterministic'),
  ('646', 'ba6b5c41c639084a88ad433fc570c19a76343c0a62d31ad096d41cc84285e686', 'Grade 1 MCL tear knee', 'subtype_grade_1_mcl_tear_knee_6a8ace9800', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('648', '4d181c0a1c2372aca50780b714fac78583d49485f71356323f5dc53b959812dc', 'Shin abrasion', 'subtype_shin_abrasion_c327f2dfa3', 'dx_shin_abrasion_c327f2dfa3', 'Shin abrasion', 'accepted_deterministic'),
  ('649', 'd2a73414a40cf3d88603cec2d84a254e149fb0d400df958450cb16048ba8001c', 'Infection as complication of lower leg laceration/abrasion', 'subtype_infection_as_complication_of_lower_leg_laceration_abrasion_fbe0f0818a', 'dx_wound_infection_complication_5415c9f38d', 'Wound infection/complication', 'accepted_deterministic'),
  ('652', '83a6df19100b09dae56640e7511a47419c99b7907a33be432e50febd27d32651', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('654', '224bf78a2a3c1a133534ab7822e50056529b3f29c1b6dacff9fdcdf487cc25c0', 'Wrist fibrocartilage tear', 'subtype_wrist_fibrocartilage_tear_aead44491e', 'dx_wrist_fibrocartilage_injury_fddc60c8f6', 'Wrist fibrocartilage injury', 'accepted_deterministic'),
  ('655', '28a375565d4f8ae5da7a1a0a15b7504dbb090dff548f61f10133ddc5cef941fd', 'Ankle Pain/Injury undiagnosed', 'subtype_ankle_pain_injury_undiagnosed_00a809c59b', 'dx_ankle_pain_de6b615afc', 'Ankle pain', 'accepted_deterministic'),
  ('656', '58e245e26cc8f09af48b5bfff578db4c5dae26b4d1ecd25a4392d7bee4cd78e4', 'Nerve entrapment in thigh', 'subtype_nerve_entrapment_in_thigh_699b99d5e4', 'dx_thigh_nerve_entrapment_cf6619a0d0', 'Thigh nerve entrapment', 'accepted_deterministic'),
  ('657', '6e25aa893838690ff2ce4a323442391d5c5f9774d965082bd077037a1b3a8b67', 'Fracture 3rd metatarsal', 'subtype_fracture_3rd_metatarsal_d36823ca6d', 'dx_metatarsal_fracture_40b473e6c8', 'Metatarsal fracture', 'accepted_deterministic'),
  ('662', '3f2d55c8ed736c3a3404acb32d6fcb1f87a7bf0ff3bb226a1dc9838b3b8e44ce', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('664', '7a497d3770481249ce8f08c30256a3f2b82e0f441403eec45e053c3c2f5f50b0', 'Gastrocnemius muscle injury or strain', 'subtype_gastrocnemius_muscle_injury_or_strain_367914bc2d', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'accepted_deterministic'),
  ('665', '92fab5e70d310ad522f6f25e1bab4d23c8764ddba56709cfafdf96015b2d7714', 'Knee contusion/haematoma (extraarticular)', 'subtype_knee_contusion_haematoma_extraarticular_19a33609a2', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('666', '5f66ff66b1d34f09faca0fc7855adaecadc12bf7ccf93eaff399e3655a0b5aee', 'Shoulder Pain/Injury not otherwise specified', 'subtype_shoulder_pain_injury_not_otherwise_specified_18170edcc8', 'dx_shoulder_pain_738e4b93f7', 'Shoulder pain', 'accepted_deterministic'),
  ('667', 'cb513a5bb36f5e70045d612edef57f97d914df17172da580ed4914740997a90d', 'Ankle anterior impingement', 'subtype_ankle_anterior_impingement_3a5b67cd15', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis', 'accepted_deterministic'),
  ('668', 'ad59c3d9bcd9378dc275a7bdb0f2f246cb193f193c818b31934932c72b901e21', 'Grade 1 A/C joint sprain', 'subtype_grade_1_a_c_joint_sprain_1ad80c156f', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('669', '1d4ff5d363e1699000719426de3e2cff9243000f779481df4472f65b775409a9', 'Elbow abrasion superficial', 'subtype_elbow_abrasion_superficial_cf7a703ca2', 'dx_elbow_abrasion_fca1398b6d', 'Elbow abrasion', 'accepted_deterministic'),
  ('670', '62625059ffe9d8d7e03e3f4c735ad929f3b7d2b48a18c990d3b73c65a4142cbb', 'Midfoot joint/ligament sprain (incl Lisfranc)', 'subtype_midfoot_joint_ligament_sprain_incl_lisfranc_282c947645', 'dx_midfoot_injury_3332895405', 'Midfoot injury', 'accepted_deterministic'),
  ('671', 'cb5b4c75ed667405e261919072ed25d58fcbc4e905c821175108491059848d6a', 'Calf laceration/abrasion', 'subtype_calf_laceration_abrasion_72a78a404f', 'dx_lower_leg_laceration_5e3fbc19d5', 'Lower leg laceration', 'accepted_deterministic'),
  ('674', 'c2c389d9fca1c1f072c149fde94c5c3d0c1f879edb4ef4cbd8981b3a53f11b02', 'Other stress/Overuse Injuries to Thigh', 'subtype_other_stress_overuse_injuries_to_thigh_a3cb236c2f', 'dx_thigh_overuse_injury_3d503881d3', 'Thigh overuse injury', 'accepted_deterministic'),
  ('690', '80d1cc261d708b34647fed67108ee2a29c759573ac3ad398bc52d044a7aee649', 'Concussion in a player with a concerning history', 'subtype_concussion_in_a_player_with_a_concerning_history_1cae645d5b', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('691', 'b6cc2b9d75fbf36404ab6700c58e5378339afe2809e59d8b25ca1a47fac35d80', 'Fracture 3rd metacarpal', 'subtype_fracture_3rd_metacarpal_e6bbb1583a', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture', 'accepted_deterministic'),
  ('693', '47f207d985b41da04c961824a70080b04fbf3e9ec4cfac925694c1ff3a0de08b', 'Eyebrow laceration requiring suturing', 'subtype_eyebrow_laceration_requiring_suturing_88ac45fb54', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('694', 'b408586787cf8d16f07cd8fc73c83461da0f2b37ef913fe19a536ce62d6911e9', 'Finger joint dislocation with volar plate injury', 'subtype_finger_joint_dislocation_with_volar_plate_injury_8d7d04812b', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'accepted_deterministic'),
  ('695', 'eaf21c02e53de7d1341c4a6d76dd47d5b0232f92630aaec954512d0b7a97ba10', 'contusion/haematoma, hip region', 'subtype_contusion_haematoma_hip_region_ffc578cee0', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma', 'accepted_deterministic'),
  ('696', 'e2119242858ccf50381edc55a2a79cd8bba724cd253466083deca49ea6434a48', 'Subacromial impingement', 'subtype_subacromial_impingement_79b7477c84', 'dx_shoulder_impingement_c2f2a634b4', 'Shoulder impingement', 'accepted_deterministic'),
  ('697', '3e6bb8b43d7ed0f2daa39256a313e0fc18666a1a8e3baf2d949148618da50744', 'Medial gastroc strain', 'subtype_medial_gastroc_strain_c97059f639', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'accepted_deterministic'),
  ('698', '1d6c47667771798d0c72d6e0d1bb6c659332be0d2d98fcccb07b5cd87b18d5bc', 'Patellar tendinopathy', 'subtype_patellar_tendinopathy_3ea4d4d1bf', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'accepted_deterministic'),
  ('699', 'b781344e263e3e81b3539b1192ed509f879be5623f430524ba7f3730cdea61a5', 'Concussion in a player with a concerning history', 'subtype_concussion_in_a_player_with_a_concerning_history_1cae645d5b', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('700', '426e9a86af966122066cfa63227c1d3525a7a8c5f7ce71e120b9c74cce042938', 'Head impact (not concussion) with Criteria 2 video signs', 'subtype_head_impact_not_concussion_with_criteria_2_video_signs_b8358c89ea', 'dx_head_impact_non_concussion_3feadb53e8', 'Head impact, non-concussion', 'accepted_deterministic'),
  ('706', 'ea36b3c97911c49ccc6df29b0122ee8247798fb256becf26172b8a9d112f3198', 'Patellofemoral osteoarthritis', 'subtype_patellofemoral_osteoarthritis_9cf4d87446', 'dx_knee_osteoarthritis_088b6b8911', 'Knee osteoarthritis', 'accepted_deterministic'),
  ('707', '7ce3ea08543e2db2f5dab3f703d36707370782574fb413e2e09b20bcc1c4648c', 'Other bony/overuse injuries not elsewhere classified', 'subtype_other_bony_overuse_injuries_not_elsewhere_classified_37a6be6e20', 'dx_other_bony_or_overuse_injury_b469c96cb6', 'Other bony or overuse injury', 'accepted_deterministic'),
  ('708', 'd2a64dcbc5828a876c15f6c85ff68fc090ba1c9d3d5278bc6376881f1f7c5cd5', 'Ankle contusion/haematoma', 'subtype_ankle_contusion_haematoma_dda81acafa', 'dx_ankle_contusion_beb9f51162', 'Ankle contusion', 'accepted_deterministic'),
  ('715', '3e29d0e3ccf59238c4d127b72af8aed1f56e9105b1e1feff5016bbe71c59f311', 'Grade 1 A/C joint sprain', 'subtype_grade_1_a_c_joint_sprain_1ad80c156f', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('716', '6ee48e68929b4504d69a283be9a55c782373602ddcafd83377651c074c8b1e49', 'Fractured mid-fibula with associated syndesmosis injury ankle', 'subtype_fractured_mid_fibula_with_associated_syndesmosis_injury_ankle_4ed60a6a3f', 'dx_lower_leg_fracture_bfd7084788', 'Lower-leg fracture', 'accepted_deterministic'),
  ('717', '1d00b349a3f38e16cbef5d8b12d50e28b9c0fb9dea845cdcba3b221080468399', 'Concussion in a player with a concerning history', 'subtype_concussion_in_a_player_with_a_concerning_history_1cae645d5b', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('718', 'c9cf92c22c70305db65e38ab3458dfc84facf3d6ea869808ac8b500900e5bd8f', 'Shoulder dislocation with labral Bankart lesion', 'subtype_shoulder_dislocation_with_labral_bankart_lesion_962c9d821b', 'dx_shoulder_dislocation_2067688fdd', 'Shoulder dislocation', 'accepted_deterministic'),
  ('719', '6cfba53db0aa940db32c2bbb24b35eb11b3eba1ed0aa408387beb89534bb358b', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('721', 'cc87cdd74e1e2579ad3fdffed4ceb8d1b8bc72edd382e8aa6026ca04677e17ff', 'Fracture 3rd metacarpal', 'subtype_fracture_3rd_metacarpal_e6bbb1583a', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture', 'accepted_deterministic'),
  ('722', 'b3a66a46e71e94b321ddcf9605412ac1eef510cb2b0b16d74f24525a06b615f2', 'Other stress/Overuse Injuries to Thigh', 'subtype_other_stress_overuse_injuries_to_thigh_a3cb236c2f', 'dx_thigh_overuse_injury_3d503881d3', 'Thigh overuse injury', 'accepted_deterministic'),
  ('723', 'bf85076dac0bb4068c431c921e360c5a19c1334e300be27def7dc351aea6839d', 'Concussion with Criteria 2 video signs', 'subtype_concussion_with_criteria_2_video_signs_76f8c79a10', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('724', '910d07f45eee5a5376c20c7b831a9a75cc3d5edef33d4677b0dec474ffe0adfd', 'contusion/haematoma, hip region', 'subtype_contusion_haematoma_hip_region_ffc578cee0', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma', 'accepted_deterministic'),
  ('725', '19df31ce8881805caea4aa310eff36278238e84286d656b1cc634a43aa76061c', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('727', 'fc2c56decdc4494d827630591fb8e87c90566af87301c93e478ac16300d71eda', 'Concussion with Criteria 1 video signs', 'subtype_concussion_with_criteria_1_video_signs_624c97508a', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('728', 'cbfc2ab04114b4132de7b7131d3dd73131ea67e3ac7eaaf55540558ff82f1df2', 'Knee abrasion', 'subtype_knee_abrasion_72b0fd7a46', 'dx_knee_wound_7498252643', 'Knee wound', 'accepted_deterministic'),
  ('729', '683d235fdbf4f810fbe48a0cb989c469b3ea883470d49d1153b521207c260424', 'Bruised ribs/chest wall', 'subtype_bruised_ribs_chest_wall_0c223ac8bd', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('730', '91224588511b57fffe9e95787eca7270d8b936ec995565d623376a850e471443', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('731', 'b571be392093691236843f7454d3a1f17ad9e60365bd02487953cdb713693a8a', 'Grade 2 A/C joint sprain', 'subtype_grade_2_a_c_joint_sprain_ae2ea1925b', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('732', '170a19cd524a6316862611fd591e6c8a5db0123041366c8580503705ce196fde', 'Diagnosis not specified', 'subtype_diagnosis_not_specified_7787afa6db', 'dx_diagnosis_not_specified_7787afa6db', 'Diagnosis not specified', 'accepted_deterministic'),
  ('733', 'e9ee956176f82977382763e7be36e54f91186dad56957b8b68dd81e2e4e22bdf', 'Acute shoulder subluxation', 'subtype_acute_shoulder_subluxation_705b818f24', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('734', 'f288237463e4fd57762c5dd765736938679ee4393d605164b0c47bc98e15f30a', 'Cervical disc Injury', 'subtype_cervical_disc_injury_13c8608a7d', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury', 'accepted_deterministic'),
  ('735', 'c02e15bb4b94e5d291aa3f420fe88ea9ec3fd18506c71f37d075c9b128294a24', 'Pec Major tendon rupture', 'subtype_pec_major_tendon_rupture_c26bdc7ac3', 'dx_pectoralis_major_injury_ae7aff3738', 'Pectoralis major injury', 'accepted_deterministic'),
  ('736', '6f6ac8a783b85132275753640e71c63a8a4c05602bac131d0a2281319f10fe15', 'Head laceration location unspecified/or multiple requiring suturing', 'subtype_head_laceration_location_unspecified_or_multiple_requiring_suturing_f8a9faf624', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('737', '68a52e9aa91f612102f8f084d0b53142645c3e440c3e49225bc30326ae63e2a5', 'Patellar tendinopathy', 'subtype_patellar_tendinopathy_3ea4d4d1bf', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'accepted_deterministic'),
  ('738', '676b1d5cab9a5c947d266d791acb47258762d27a3b19a857ac03ec66fae653a7', 'Sprain lateral collateral ligament ankle', 'subtype_sprain_lateral_collateral_ligament_ankle_96d9293f86', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('744', '6d5a53a8ab1f359aaa6119e7b587023167638c5e02d26eac98b9e2a7f8a8038b', 'Diagnosis not specified', 'subtype_diagnosis_not_specified_7787afa6db', 'dx_diagnosis_not_specified_7787afa6db', 'Diagnosis not specified', 'accepted_deterministic'),
  ('748', '89aa00b5eaff4ea440c575474fe69e1d3859ca8359038ca5f16cd38341bad0b4', 'Thoracic disc prolapse', 'subtype_thoracic_disc_prolapse_7034b398b8', 'dx_thoracic_disc_disorder_9d9c895000', 'Thoracic disc disorder', 'accepted_deterministic'),
  ('749', 'cb2fb0130581ca7ab438898258b18a346f40a931a0070d1b282d1038e6ef7b95', 'Concussion in a player with a concerning history', 'subtype_concussion_in_a_player_with_a_concerning_history_1cae645d5b', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('750', '18a89abd16b6de25a0f851faab50d47b8614f9394598f14ee82d0549a0951973', 'Prepatellar bursitis', 'subtype_prepatellar_bursitis_d7a88bac59', 'dx_prepatellar_bursitis_d7a88bac59', 'Prepatellar bursitis', 'accepted_deterministic'),
  ('751', 'd2ab797a0e70943e3aaff0534f5f244fb504eaad1b72e094561be14eaad13ad1', 'Hip and Groin Muscle strain or tear', 'subtype_hip_and_groin_muscle_strain_or_tear_936dbed7ca', 'dx_hip_and_groin_muscle_injury_7ccd814142', 'Hip and groin muscle injury', 'accepted_deterministic'),
  ('752', 'a5e382b110686addf79ddd4a9c3adaf94375ce10632165478f5ddcc4572e860e', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('753', '299e269ea86f1080bf04240607ec31eb8dee07c3bcc09942b9ae1242cb2ef4fa', 'Eyebrow laceration requiring suturing', 'subtype_eyebrow_laceration_requiring_suturing_88ac45fb54', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('756', 'b982c732beb851ee649c7ef257f3fe875e4323187442bd6abe930186970cc366', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('757', 'f269a4853a834dce72acc882b65c8772479aaf3f50ce3d31541a42b0d30e085b', 'Lumbar pain with hamstring referral', 'subtype_lumbar_pain_with_hamstring_referral_c859c82cf8', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('758', '9dc92d930105b9c9ba996229669a7000a2efe1c41a3846100c70cb1eb946f261', 'Plantar heel pain (fasciitis/strain/calcaneal spur)', 'subtype_plantar_heel_pain_fasciitis_strain_calcaneal_spur_7ea3631a44', 'dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b', 'Plantar heel pain/fasciopathy', 'accepted_deterministic'),
  ('759', '7877fae4a8291fd735aa226a8762313bf6bc6053b2c87194a27dc57e37b19cdd', 'Inferior tibiofibular syndesmosis sprain', 'subtype_inferior_tibiofibular_syndesmosis_sprain_0545fce188', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'accepted_deterministic'),
  ('760', 'c15fc985e595588df25dcd991eef442d5ae724cfcf4340aa457b402c80beba65', 'Fracture 2nd Metatarsal', 'subtype_fracture_2nd_metatarsal_b47780754e', 'dx_metatarsal_fracture_40b473e6c8', 'Metatarsal fracture', 'accepted_deterministic'),
  ('761', '3a9202366a199b50a160b0330a9c9eacbfac7ad8cec65395541e990f96bf9f89', 'Lateral ligaments rupture (grade 3 injury)', 'subtype_lateral_ligaments_rupture_grade_3_injury_c5dc81b2fd', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('764', '04f5e865062165c0199e73db4273b7d9cc3e47f567838e1409cac84048c09b22', 'Brachial plexus traction injury/burner/stinger', 'subtype_brachial_plexus_traction_injury_burner_stinger_29eb517979', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury', 'accepted_deterministic'),
  ('780', '279c4db376f34d99474b1d2da5c7baf0857ab056deaec650df6577c4b63bd365', 'Concussion in a player with a concerning history', 'subtype_concussion_in_a_player_with_a_concerning_history_1cae645d5b', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('781', '6e77948c8231b3e6a7c8b71f23c2b75c525a98683557abff882af49f5921013f', 'Sternoclavicular joint instability', 'subtype_sternoclavicular_joint_instability_f6b329093c', 'dx_sternoclavicular_joint_instability_f6b329093c', 'Sternoclavicular joint instability', 'accepted_deterministic'),
  ('782', '9d8ecbd2698b211b65b0e6d842bf79b58e8e4a0b119e65faecde81e8eec7c4b4', 'Head/facial laceration', 'subtype_head_facial_laceration_850da462e6', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('783', '7c6c7d154a74e6b12d5efbc3fa03efdedc628e67fc9519916e4c986ed5358b3c', 'Posterior cruciate ligament (PCL) injury', 'subtype_posterior_cruciate_ligament_pcl_injury_fbe6c1cd7d', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury', 'accepted_deterministic'),
  ('784', '6e136879c241f4e28dd00ab4a72b6c8ec27d214605d119e2286124aff2eac999', 'Plantar heel pain (fasciitis/strain/calcaneal spur)', 'subtype_plantar_heel_pain_fasciitis_strain_calcaneal_spur_7ea3631a44', 'dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b', 'Plantar heel pain/fasciopathy', 'accepted_deterministic'),
  ('785', 'fe6fce79f8f4a6daaaa046f37264114a59360f17a4ddaf5ef2c7118d7f9914e6', 'Eyebrow laceration requiring suturing', 'subtype_eyebrow_laceration_requiring_suturing_88ac45fb54', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('786', '3dd06241e6f5eed4006d70db4aeb8602a8cb748276f9536e6753a464a204a344', 'Sartorius tendon strain', 'subtype_sartorius_tendon_strain_479dcdf678', 'dx_sartorius_injury_3dfafe7e54', 'Sartorius injury', 'accepted_deterministic'),
  ('787', '70e23fb8ad04bf448ef93c4a93252a596cdf8ba55295348418ab02c998838502', 'Diagnosis not specified', 'subtype_diagnosis_not_specified_7787afa6db', 'dx_diagnosis_not_specified_7787afa6db', 'Diagnosis not specified', 'accepted_deterministic'),
  ('788', '2319eba01bd7cd7a87df2c92690a2671b1fbc557b9e80d7394f0987d25259294', 'Diagnosis not specified', 'subtype_diagnosis_not_specified_7787afa6db', 'dx_diagnosis_not_specified_7787afa6db', 'Diagnosis not specified', 'accepted_deterministic'),
  ('830', 'b2a43d082b0de35b8a91b92f663c1231764e725fa9568fac89c7ff3f2bffa7e0', 'Rotator Cuff muscle injury', 'subtype_rotator_cuff_muscle_injury_79ec49deb3', 'dx_rotator_cuff_injury_0744f75c4c', 'Rotator cuff injury', 'accepted_deterministic'),
  ('831', '6945604eaaa557672f0c957f19f8065725c052cd34c63f1e681f52057f6b8902', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('832', '844a3118edb927159d8c990ee68342500d535c069957efb44cf657bbbe2177c8', 'Other finger pain not otherwise specified', 'subtype_other_finger_pain_not_otherwise_specified_32b8c20331', 'dx_finger_pain_0c38e0f81a', 'Finger pain', 'accepted_deterministic'),
  ('834', '6802b591749fc790144ae1278475c152b4e04651215a6c2253ada9346d668a43', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('840', '69492a4fcee3947f4c436f1d2b84c8d8af33bf9a9bac7503df517ce94357731f', 'Facet joint O/A lumbosacral spine', 'subtype_facet_joint_o_a_lumbosacral_spine_521852ba30', 'dx_lumbosacral_facet_joint_osteoarthritis_9a909e3df3', 'Lumbosacral facet joint osteoarthritis', 'accepted_deterministic'),
  ('849', '136b5e3b3e0deb9873d9d9c7dbbadec9f610e2aa05e7f06232d10b3e09e5c30e', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('850', '32d7420e78a320283a0fa512d586ea74d1292ded464f3dafaa81ea2e67679467', 'Neck muscle soreness/spasm/torticollis', 'subtype_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'dx_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'Neck muscle soreness/spasm/torticollis', 'identity_group'),
  ('853', 'befb874b1b3012f33397438819574a713cb0c7883401e15a9781b065bd56292f', 'Neck muscle soreness/spasm/torticollis', 'subtype_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'dx_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'Neck muscle soreness/spasm/torticollis', 'identity_group'),
  ('854', 'ad71e6b7fa4d90c9bcd66e2703e18098cda00785bb7bed130efad1b392572ecd', 'Abdominal oblique muscle strain', 'subtype_abdominal_oblique_muscle_strain_5b04cf0a3c', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury', 'accepted_deterministic'),
  ('856', '81c02562b1db255de1de20af390b566f118dea93ae069ca533d25a81a49f8b19', 'Facet Joint/Neck Ligament sprain', 'subtype_facet_joint_neck_ligament_sprain_369f0afd14', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder', 'accepted_deterministic'),
  ('858', 'b69b4fc0b355839712e50398f8d64803d7056714356563aa5887d88a6fa4b82f', 'Acute posterior internal impingement', 'subtype_acute_posterior_internal_impingement_bd3421d008', 'dx_shoulder_impingement_c2f2a634b4', 'Shoulder impingement', 'accepted_deterministic'),
  ('860', 'caa2ceeabe2f8f0360def3641a27ad5b65ba57d6a3ae3ab0640d318cb33bcadd', 'Fracture 3rd metatarsal', 'subtype_fracture_3rd_metatarsal_d36823ca6d', 'dx_metatarsal_fracture_40b473e6c8', 'Metatarsal fracture', 'accepted_deterministic'),
  ('861', '41e13f04138918ed8c91a04eb844354aebb9b4f57a60c0274cd8fd8ef30b3694', 'Foot contusion/haematoma', 'subtype_foot_contusion_haematoma_edd1025815', 'dx_foot_contusion_6c8a5bb721', 'Foot contusion', 'accepted_deterministic'),
  ('862', '77e48dfbadf251ec5d6c3e955f418ed70805d7694b295e7beadd62ca67aec536', 'Groin/hip bone contusion', 'subtype_groin_hip_bone_contusion_f785146788', 'dx_groin_and_hip_bone_contusion_e0da41307f', 'Groin and hip bone contusion', 'accepted_deterministic'),
  ('863', 'ba9dc58a06f1a5ddd473033c958abbe91bb86038a6ac5975202b2df7df8db135', 'Scalp laceration', 'subtype_scalp_laceration_50be43ed71', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('865', '2287a3546a562a03e4b89ee745ea1f1b3e6ee50063eaf8e9ad0ce9ffc4ac3435', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('866', '5be018c88f657c6e832436d511ed8b4f04ba1e756ac2423ff5a23a471779688c', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('867', 'aeaa1e15a6385d599437bf13400058dc492d042097516991adb4da3d80d7faa6', 'Quadriceps strain or tear', 'subtype_quadriceps_strain_or_tear_17ff226482', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('872', 'cf96930984a359f451ac29d670b59f2789cab55545709c66e344f444961f3612', 'Patellar tendinopathy', 'subtype_patellar_tendinopathy_3ea4d4d1bf', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'accepted_deterministic'),
  ('878', '1d1deb4202e5d50c45ffbe430a4f5332c3821e538bfe84cc5647029609a03d0e', 'Concussion with Criteria 2 video signs', 'subtype_concussion_with_criteria_2_video_signs_76f8c79a10', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('879', '1d3be584c8666bb07f093a7d577ae4265e4fa9a13fa2139db78a8211122842fd', 'Concussion with delayed symptom presentation', 'subtype_concussion_with_delayed_symptom_presentation_df9f41a9b0', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('880', '1ab957dfb00d4d62e0c34ee4810b7a1cfeae652bd4ef6f971509c99c6c84959c', 'Concussion in a player with a concerning history', 'subtype_concussion_in_a_player_with_a_concerning_history_1cae645d5b', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('882', '8beb2f5806a2d25589ee5e1e8ccad9e9a49fc1b9f5f3c8bfb6dd0bc36c5c2670', 'Knee abrasion', 'subtype_knee_abrasion_72b0fd7a46', 'dx_knee_wound_7498252643', 'Knee wound', 'accepted_deterministic'),
  ('883', '41184f8b237454559cd63b29f648b15e4913e1ab86b3a6d011cd3c58df3846c3', 'Knee abrasion', 'subtype_knee_abrasion_72b0fd7a46', 'dx_knee_wound_7498252643', 'Knee wound', 'accepted_deterministic'),
  ('884', '2ca0b85f314d84e769d785e117dd15aaaf85ff3175560567b9eeddb29f928d8e', 'Neck muscle soreness/spasm/torticollis', 'subtype_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'dx_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'Neck muscle soreness/spasm/torticollis', 'identity_group'),
  ('885', 'b94fa1cef34d9a2328bd08b6689787d095e71b5a3ad862ff04d6c08f94aff10a', 'Neck muscle soreness/spasm/torticollis', 'subtype_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'dx_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'Neck muscle soreness/spasm/torticollis', 'identity_group'),
  ('887', 'e8862390f3d7b120533848e39b0f1b3789fe18a05f42dd39f66ef9bffe2b1868', 'Fractured fibula with associated peroneal nerve injury', 'subtype_fractured_fibula_with_associated_peroneal_nerve_injury_e87361b96e', 'dx_lower_leg_fracture_bfd7084788', 'Lower-leg fracture', 'accepted_deterministic'),
  ('891', '03ce87f27054e319220c020ca9938173cc1a39227b3823b2569eef92f4a1b175', 'Hamstring cramping during exercise', 'subtype_hamstring_cramping_during_exercise_2eb7c1414b', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm', 'accepted_deterministic'),
  ('892', '24f809a59007a8ad3a1b96517f467592dfa1f8033c944ceee02af4fc5cc86065', 'Hamstring cramping during exercise', 'subtype_hamstring_cramping_during_exercise_2eb7c1414b', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm', 'accepted_deterministic'),
  ('894', 'fec911d02ba5cd8442f2f1c39026d94f4e14026c78a614d7cda942674b5b355c', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('898', '4c64ab1228ace456e135d0092ce94c9dfaa0770cdb9f3b843b966b92e11e565d', 'Chronic lumbar functional pain', 'subtype_chronic_lumbar_functional_pain_f5137cab5d', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('903', '34c71921c0671158219ed1be817a6c3a69769317f791de4cbf6aebe0ba177f0c', 'Knee contusion/haematoma (extraarticular)', 'subtype_knee_contusion_haematoma_extraarticular_19a33609a2', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('905', '2d645d4969718ae4c9ebda0a9fe97cb5e79eb1931004671637b5c73cae5f63e1', 'Hand bone contusion', 'subtype_hand_bone_contusion_fc017abdce', 'dx_hand_bone_contusion_fc017abdce', 'Hand bone contusion', 'accepted_deterministic'),
  ('906', '3b18b225c5bcd27591d03bbe363b83e2383ca5d26684fe2bc348275624676e7c', 'Leg Soft Tissue Bruising/Haematoma', 'subtype_leg_soft_tissue_bruising_haematoma_ee7067e86a', 'dx_leg_soft_tissue_contusion_or_haematoma_2264434fff', 'Leg soft tissue contusion or haematoma', 'accepted_deterministic'),
  ('907', '83d3f15d18a12aa9efc93e088ed7a9c56e150674228dd2ae71ceedc2b7932a49', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('908', '6e44ca9d32c9d9248028bceb24beb51e6c844b91ad9d757c0c202d2bff43ab63', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('910', '74fd94544065ec4464acd72a87c3a87a8b1b6a011855d2fa904d8df928d1133c', 'Sprain lateral collateral ligament ankle', 'subtype_sprain_lateral_collateral_ligament_ankle_96d9293f86', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('911', '96a0663750c41d93f4ffffcb01fcc7211921813fdf9dfca5bdfd0cdbbaea74cc', 'Sprain lateral collateral ligament ankle', 'subtype_sprain_lateral_collateral_ligament_ankle_96d9293f86', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('912', 'ae3165e58c667f1e69c1d24ef0cfb052bfe772b6d805f0c21933845f17bea4f9', 'Chest Wall Soft Tissue Bruising/Haematoma', 'subtype_chest_wall_soft_tissue_bruising_haematoma_bd1a62550f', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('913', 'b3c765513ddbd219dcdf08e4f72ff8d830198c2fa8e483eeceb04f4cc6535a05', 'Bruised ribs/chest wall', 'subtype_bruised_ribs_chest_wall_0c223ac8bd', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('914', '4b0ff48e38465cdde3bf955663ba536fec22be57050095e626eba85480b83e2a', 'Midfoot joint/ligament sprain (incl Lisfranc)', 'subtype_midfoot_joint_ligament_sprain_incl_lisfranc_282c947645', 'dx_midfoot_injury_3332895405', 'Midfoot injury', 'accepted_deterministic'),
  ('915', '9bcdf9c025ebddb9ee5c0bea3abba7b1f3a5b8cdc56294496b4376249543d351', 'Knee Impingement/Synovitis/Biomechanical Lesion not associated with other conditions', 'subtype_knee_impingement_synovitis_biomechanical_lesion_not_associated_with_other_conditions_ed9f75283a', 'dx_knee_synovitis_impingement_02e229b1cc', 'Knee synovitis/impingement', 'accepted_deterministic'),
  ('916', 'b1374f0f687159d8b4f356dce3e86322936bd416e1bfd81b2e9ee875b52908e3', 'Disc degeneration', 'subtype_disc_degeneration_5b20c16579', 'dx_spinal_disc_degeneration_850a87dc5e', 'Spinal disc degeneration', 'accepted_deterministic'),
  ('917', '4e2731e147cf8f921d16312ec8a49bdb3b7cddf693ce280e1fefddf083b07a0c', 'Neck muscle soreness/spasm/torticollis', 'subtype_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'dx_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'Neck muscle soreness/spasm/torticollis', 'identity_group'),
  ('918', '44c24ba623d33a0ab14858f039d8b30e7bfbf6e3b827c24e20f63033d995314e', 'Thumb bruising/haematoma', 'subtype_thumb_bruising_haematoma_97324f0de1', 'dx_thumb_contusion_or_haematoma_7a219de27a', 'Thumb contusion or haematoma', 'accepted_deterministic'),
  ('919', 'b7a22844a3ddcdef0aff0d620e239901f34e4a06bd522723c85969b95593faf0', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('925', 'df996d49bd409d9d505ffd693596720a33f2c59a5d17d8a594bbae371c1acbd5', 'Groin/hip bone contusion', 'subtype_groin_hip_bone_contusion_f785146788', 'dx_groin_and_hip_bone_contusion_e0da41307f', 'Groin and hip bone contusion', 'accepted_deterministic'),
  ('930', '7d557e7d3b93a6b31193b2ba72d9f2ad0fcd838242650d0e61f87f4b87d8d74b', 'Acute subacromial impingement', 'subtype_acute_subacromial_impingement_ab6b410714', 'dx_shoulder_impingement_c2f2a634b4', 'Shoulder impingement', 'accepted_deterministic'),
  ('940', '3aa482d52e777b45868c57247aa45be9852fcfb8c4278e3f7bca137a31b03955', 'Sprained/jarred elbow', 'subtype_sprained_jarred_elbow_a336ca7456', 'dx_elbow_injury_7100f71f81', 'Elbow injury', 'accepted_deterministic'),
  ('941', 'c4fdedea98a0d0c225e843f4f8eb99fcae45bfa53769e269d91a9c37807e273a', 'Foot bone bruise', 'subtype_foot_bone_bruise_128a1b35fa', 'dx_foot_bone_contusion_62bd9ea576', 'Foot bone contusion', 'accepted_deterministic'),
  ('942', '4adb33d499f8334ed5e932a652f2b3206e967e5eb7223a3557eeec0f46056631', 'contusion/haematoma, hip region', 'subtype_contusion_haematoma_hip_region_ffc578cee0', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma', 'accepted_deterministic'),
  ('943', '03f1f095a2491cfc42d043e3acefb04d05e0e2e8de4a4b76342d6df0a2365759', 'Scalp laceration', 'subtype_scalp_laceration_50be43ed71', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('944', '776471337a370bd08d04098630323136b303a6ec2e52faa950ee85abfeefff55', 'Scalp laceration', 'subtype_scalp_laceration_50be43ed71', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('945', '0700a84e1819f31989191c702655818a43b09225e47351f7fe7c512a4141f9bd', 'Head/facial contusion/haematoma', 'subtype_head_facial_contusion_haematoma_1131a060b5', 'dx_head_and_facial_contusion_74a20a767e', 'Head and facial contusion', 'accepted_deterministic'),
  ('947', '65c2101ecc54d906a695ef2dae1ca12d793184468ee223ee21413ced9143af81', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('948', '9ce15ab06397a16970e7e623c189cce3cc66ff13d6302288bc13ce7e8eb2b3a6', 'Calf muscle cramps/spasm', 'subtype_calf_muscle_cramps_spasm_7890832741', 'dx_calf_cramp_spasm_950b710fbb', 'Calf cramp/spasm', 'accepted_deterministic'),
  ('949', '5c6a8d5ac24b1cc293ddfd676b846533b07b94ea673fe3c7bad08a3347401fca', 'Quadriceps strain or tear', 'subtype_quadriceps_strain_or_tear_17ff226482', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('955', 'a6d8c925f9d5c00d48c02a5f16bbf77bf0f65f88929fa019f67bbebe4619390f', 'Sprain lateral collateral ligament ankle', 'subtype_sprain_lateral_collateral_ligament_ankle_96d9293f86', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('956', '7aae7b72bc2afccf6ad7ea415a36b28dc2d3f0f614479f167886f933a97e08e5', 'Elbow ulna/medial collateral ligament (UCL) strain or tear', 'subtype_elbow_ulna_medial_collateral_ligament_ucl_strain_or_tear_ab4c438f84', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury', 'accepted_deterministic'),
  ('958', 'b3e5750ca25884c04baf20b28a80e5721dea90aa8c9f2bab9663ecabcd16704f', 'Eyelid laceration not requiring suturing', 'subtype_eyelid_laceration_not_requiring_suturing_a40b5a029e', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('959', 'e6ce14ea768f27e17ca6aa44c64b3c958b3ccb1f102bbca6c41cea42b5709a99', 'Head impact (not concussion) with Criteria 2 video signs', 'subtype_head_impact_not_concussion_with_criteria_2_video_signs_b8358c89ea', 'dx_head_impact_non_concussion_3feadb53e8', 'Head impact, non-concussion', 'accepted_deterministic'),
  ('960', 'c36fccf2b5d08371658782b364051c6cc30296f3f1ff49c171a8f002c9b055d0', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('961', '9d0a03bfa3f98ec7afc9ce891b52889acf648279421902b1af22e9413d65e861', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('962', '64055372e84e86f29cc1ab08348694be3db0a2a615e608578c7391d0f79c0794', 'Thigh abrasion', 'subtype_thigh_abrasion_f7f1dfcab9', 'dx_thigh_laceration_or_abrasion_cec8e820c4', 'Thigh laceration or abrasion', 'accepted_deterministic'),
  ('969', '34619f24e7b2b98ed78789e4366a9d2409d9d84e9b5db2f554da0a6b3230dc47', 'Lateral hamstring insertion tendonitis', 'subtype_lateral_hamstring_insertion_tendonitis_0081afc8c6', 'dx_hamstring_tendon_injury_f86b1dad5b', 'Hamstring tendon injury', 'accepted_deterministic'),
  ('970', '8a37e5d95125228ce0fcd0cf1c3e07e2982e531f9d540e9bdd72089c0c87f021', 'Brachial plexus traction injury/burner/stinger', 'subtype_brachial_plexus_traction_injury_burner_stinger_29eb517979', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury', 'accepted_deterministic'),
  ('971', '7fa71e7e613512d1e2ad13289d8798179f4273b4959ebc9ae1c222c5f14b39da', 'Thumb sprain', 'subtype_thumb_sprain_730d144cbe', 'dx_thumb_sprain_730d144cbe', 'Thumb sprain', 'accepted_deterministic'),
  ('973', '70cf2b156714c28aa7b861f7627ab4c6b946d3bb1289fdcc4234f95a54038f41', 'Anterior talofibular ligament sprain', 'subtype_anterior_talofibular_ligament_sprain_f8c3b9037d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('975', 'b1fe9cc95141a18d84cb037f97a8659b69d25c296369d19e521a3ac547274de2', 'Biceps muscle strain', 'subtype_biceps_muscle_strain_9122d2b9c0', 'dx_biceps_muscle_injury_3a5679b9a5', 'Biceps muscle injury', 'accepted_deterministic'),
  ('977', '634121055319a731453ddc43dcb862d5e746559eaf4d53025c6f7262c1cd57a0', 'Adductor origin tendinopathy', 'subtype_adductor_origin_tendinopathy_75ee0d21d5', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'accepted_deterministic'),
  ('979', '8f04f39aa137d1485a58802dc112fa17269b1811d929ddcba08c59aadf00e6de', 'Mandible fracture', 'subtype_mandible_fracture_c2163574d2', 'dx_mandible_fracture_c2163574d2', 'Mandible fracture', 'accepted_deterministic'),
  ('980', 'ffe427ea8d8917dbbaf09873c91d0a0dcdcd0c5521b39c8fcea43e50d2188c10', 'Knee contusion/haematoma (extraarticular)', 'subtype_knee_contusion_haematoma_extraarticular_19a33609a2', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('981', '32bb681ac7bb89af252013ff67149206de72bdc25531b57d7092fbf9b961d2a5', 'Calf muscle cramps/spasm', 'subtype_calf_muscle_cramps_spasm_7890832741', 'dx_calf_cramp_spasm_950b710fbb', 'Calf cramp/spasm', 'accepted_deterministic'),
  ('982', 'ee18dc680d1dd556b447e17d29072d146f070a747fa5e1aaba283ca38326dd4b', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('983', '7ef9040d850c5633f117507f022011bc1ee80fbb1c27dd7a85140dc3871d8b45', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('988', 'd2107f3557a5cbd4f7281953f4badaa4bd1b1ac600cc05f1428512d14703a5ff', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('989', '72ad341413f4b38d11bf89fdb83dd89f027fc8d41f9d0a90ecdb066b5800ba7c', 'Quadriceps strain or tear', 'subtype_quadriceps_strain_or_tear_17ff226482', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('990', 'bb728e7205c306c9b59f0aec1bb89073c1d3c4cbf945b320f65602fc27045b2c', 'Lumbar soreness or muscle spasm', 'subtype_lumbar_soreness_or_muscle_spasm_d5cbfcf03b', 'dx_lumbar_soreness_or_muscle_spasm_d5cbfcf03b', 'Lumbar soreness or muscle spasm', 'identity_group'),
  ('999', '1962d052fde01c8a337c4765c14409c1f4892f679781a3758dbcebfaaf838c4b', 'Flexor Hallucis Longus tendinopathy', 'subtype_flexor_hallucis_longus_tendinopathy_e37ca6c8f7', 'dx_flexor_hallucis_longus_tendon_injury_3ae59d52af', 'Flexor hallucis longus tendon injury', 'accepted_deterministic'),
  ('1003', '2382b64aaa755d179479b416b94ad391edc4608a43fa7a23589f77a5bbbfee3a', 'Lumbar soreness or muscle spasm', 'subtype_lumbar_soreness_or_muscle_spasm_d5cbfcf03b', 'dx_lumbar_soreness_or_muscle_spasm_d5cbfcf03b', 'Lumbar soreness or muscle spasm', 'identity_group'),
  ('1021', '4d772a4129d70a8379dd64b59a474625dc6228a7b0421792477e68446295c343', 'contusion/haematoma, hip region', 'subtype_contusion_haematoma_hip_region_ffc578cee0', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma', 'accepted_deterministic'),
  ('1022', 'f37dcd59c69ef250e321439770795537829f410ef43b229209ad9eece0c33f14', 'Knee Sprains/Ligament Injuries', 'subtype_knee_sprains_ligament_injuries_bc9c2670dd', 'dx_knee_ligament_injury_unspecified_7ab630d44d', 'Knee ligament injury, unspecified', 'accepted_deterministic'),
  ('1024', 'f52077ecf552b452daeb8bca5b31adfb615ac097d70676dc1d5c12bda264371f', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1025', 'cba7f6d9686c4e2b489abcc00aae693c1aa5a45928419a70f5117507d2115aa6', 'Infrapatella fat pad contusion/haematoma +/- bursitis', 'subtype_infrapatella_fat_pad_contusion_haematoma_bursitis_3758a2ae3c', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury', 'accepted_deterministic'),
  ('1026', '273612101dc7c28deacb29b17cad0c17f96472a360f1a26f6567826ff97b9274', 'Popliteus muscle strain', 'subtype_popliteus_muscle_strain_da248dd71e', 'dx_popliteus_injury_0ac29f0573', 'Popliteus injury', 'accepted_deterministic'),
  ('1028', 'cf4712bdbde99005486c04f8bf7ab8a8f8658b0a453369206df2dbad4fb0ac6b', 'Facet Joint/Neck Ligament sprain', 'subtype_facet_joint_neck_ligament_sprain_369f0afd14', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder', 'accepted_deterministic'),
  ('1029', 'b624ec5cf80aff74b3e53377964252bad45a5ac460fbb4698e943626bf41a7d0', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('1030', '82c99855a7cca3c4a64b130492645356b99cf92c2fa7c04e57bd063691aaf3c4', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('1035', 'f86501df99d436c4103f3698899fe2068691560d67ef5c419e4067fb3ab6eef4', 'Fat pad contusion heel', 'subtype_fat_pad_contusion_heel_6a2375437b', 'dx_heel_contusion_4009d671bf', 'Heel contusion', 'accepted_deterministic'),
  ('1045', '02bf5292e64b6f9e91bf79c9f0784240181c3b441b700045e83bbd537b0d4e13', 'Bennett''s fracture/dislocation thumb', 'subtype_bennett_s_fracture_dislocation_thumb_3a25210b48', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture', 'accepted_deterministic'),
  ('1060', '4659e074aaf9007ba2f6766673c379384ccfecf7b2d1afe5187cbaa8f0720811', 'Piriformis syndrome (with sciatic nerve impingement)', 'subtype_piriformis_syndrome_with_sciatic_nerve_impingement_31b07271c8', 'dx_piriformis_syndrome_d562318818', 'Piriformis syndrome', 'accepted_deterministic'),
  ('1062', 'baa46afa7e597dc4dd9f2d0f89e7cfe6aea2ce60a9c1a12757610ceeab0a8167', 'Soleus Trigger points/Spasm', 'subtype_soleus_trigger_points_spasm_dfb83ed490', 'dx_soleus_trigger_points_spasm_56202bbe31', 'Soleus trigger points/spasm', 'accepted_deterministic'),
  ('1064', '6757feb4def5b5427ffca3cc06e40b1aca3940a6add5d4e9f739f9f89619b0a2', 'Diagnosis not specified', 'subtype_diagnosis_not_specified_7787afa6db', 'dx_diagnosis_not_specified_7787afa6db', 'Diagnosis not specified', 'accepted_deterministic'),
  ('1075', '1445f08e3e8d52e278db8d9cc50aa5c38c9c6b21f85eb37d23f1245e4543cf83', 'Anterior talofibular ligament sprain', 'subtype_anterior_talofibular_ligament_sprain_f8c3b9037d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('1077', '52b14dbddeb41497ac29430e78fb908221a31f28cbfebce5c12587ff45d84e06', 'Groin soreness or trigger points', 'subtype_groin_soreness_or_trigger_points_70c27347b8', 'dx_groin_soreness_or_trigger_points_70c27347b8', 'Groin soreness or trigger points', 'identity_group'),
  ('1079', '478bcd4de927856e092121578635235f7690aeeca0ee0b23978e4ab48aacc7db', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('1081', '21e05784e859d3e92441cf3952470d525f04fd8c084d4b4d492c4a4b7eee0aca', 'Adductor longus tendon strain', 'subtype_adductor_longus_tendon_strain_c1fa29e878', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'accepted_deterministic'),
  ('1082', 'cbb4e972a7002da6f50559e07bd86ef8862342588de84b5e4114ed3324013767', 'Adductor longus tendon strain', 'subtype_adductor_longus_tendon_strain_c1fa29e878', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'accepted_deterministic'),
  ('1083', 'b6b803d885af396fa96fec1a7115ea105d3807b50ae734eb6b71030a24fc21a7', 'Popliteus muscle strain', 'subtype_popliteus_muscle_strain_da248dd71e', 'dx_popliteus_injury_0ac29f0573', 'Popliteus injury', 'accepted_deterministic'),
  ('1085', 'ad5178594fb0bb73f6f82fcb40d727f4a8dee5b61a7fc5f0cbd7ff2ece2fc85d', 'Concussion with no concerning history or signs', 'subtype_concussion_with_no_concerning_history_or_signs_a256f29e16', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1086', '942d79a67543ab141a6c9e0b3463574f7adebd86f7bff25b409a467f1f57fc35', 'Wrist fibrocartilage tear', 'subtype_wrist_fibrocartilage_tear_aead44491e', 'dx_wrist_fibrocartilage_injury_fddc60c8f6', 'Wrist fibrocartilage injury', 'accepted_deterministic'),
  ('1087', 'c2da84de78c25f80ba0c7b28aff7c9680cbf7d66e1c79712dc148cce7c955185', 'Orbital fracture', 'subtype_orbital_fracture_a673b31938', 'dx_orbital_fracture_a673b31938', 'Orbital fracture', 'accepted_deterministic'),
  ('1088', '27f2a950b5a473a97d8fe0cf7dd6edc57fd0e39124d9f23ef19c51a99a40d75d', 'Neck muscle and/or tendon strain/spasm/trigger points', 'subtype_neck_muscle_and_or_tendon_strain_spasm_trigger_points_9c974fe830', 'dx_neck_muscle_and_or_tendon_strain_spasm_trigger_points_9c974fe830', 'Neck muscle and/or tendon strain/spasm/trigger points', 'identity_group'),
  ('1089', '5ae0412fd3b65665fd4493aaaebcc1142fa599b126aec693cd231197fcdd985a', 'Forehead laceration requiring suturing', 'subtype_forehead_laceration_requiring_suturing_047b8262be', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('1090', 'e7c092d88137b73b3edd8d64ea17dc11a03c7f592b04aff8c2c0ad59048e022c', 'Inferior tibiofibular syndesmosis sprain', 'subtype_inferior_tibiofibular_syndesmosis_sprain_0545fce188', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'accepted_deterministic'),
  ('1093', 'bc1f3dea20f85846d2b4b26e28c520ad6c66177932e867ddd15cf651226d41e8', 'Concussion in a player with a concerning history', 'subtype_concussion_in_a_player_with_a_concerning_history_1cae645d5b', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1094', '6133103b83687346be383d0153dd296299d7af0acb49f7e26edbad01e82c1a95', 'Concussion with delayed symptom presentation', 'subtype_concussion_with_delayed_symptom_presentation_df9f41a9b0', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1095', 'deca005ebbb5dcdac53945014d8e37779823c296c80c0af7b17bbd643f12846c', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('1096', '7d7fe393d195020426888c080a4a7586f3ad87cff7df75aa507b5b63752d9507', 'Inferior tibiofibular syndesmosis sprain', 'subtype_inferior_tibiofibular_syndesmosis_sprain_0545fce188', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'accepted_deterministic'),
  ('1097', 'd6e722f885820df520ee74f8ccb4888560996a0e17beda99cafe525d182b38da', 'Diagnosis not specified', 'subtype_diagnosis_not_specified_7787afa6db', 'dx_diagnosis_not_specified_7787afa6db', 'Diagnosis not specified', 'accepted_deterministic'),
  ('1098', 'b0d0b8af29bbbdf180e6bffe3e02d135d04e1a486e025d4625f118780753a0d5', 'PIP joint dislocation middle finger', 'subtype_pip_joint_dislocation_middle_finger_7a862b7a80', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'accepted_deterministic'),
  ('1099', '774c003846abe549a8c91a84d192912fa4b9cadfe1bd9c12b770f70b22dd6c5c', 'Diagnosis not specified', 'subtype_diagnosis_not_specified_7787afa6db', 'dx_diagnosis_not_specified_7787afa6db', 'Diagnosis not specified', 'accepted_deterministic'),
  ('1100', '81f2985ec1e35cef7c00fa79dd4c8bd720cbedcd145218125c4930432261d6c8', 'Facial laceration requiring suturing', 'subtype_facial_laceration_requiring_suturing_40a8df9bf4', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('1101', '594a671f868eef2dcd550c0eeba8bef41e5636e2b3fb3d73c7d96fcfe7681b62', 'Plantar heel pain (fasciitis/strain/calcaneal spur)', 'subtype_plantar_heel_pain_fasciitis_strain_calcaneal_spur_7ea3631a44', 'dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b', 'Plantar heel pain/fasciopathy', 'accepted_deterministic'),
  ('1102', 'efe71ac5fdb0ab1a9be94f55eda7d966913a65fc8273688f757ecdf2dd0decba', 'Scalp laceration', 'subtype_scalp_laceration_50be43ed71', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('1103', '14bc9994cfc023139437c015ce44a7633fd2b450aa23e033598ec6102ee2a5dc', 'Diagnosis not specified', 'subtype_diagnosis_not_specified_7787afa6db', 'dx_diagnosis_not_specified_7787afa6db', 'Diagnosis not specified', 'accepted_deterministic'),
  ('1104', 'a4320ae82551637db55338e42d351ab46e558f53df727023aa18a7aff720593f', 'Glenohumeral joint sprain with chondral/labral damage (incl SLAP tear)', 'subtype_glenohumeral_joint_sprain_with_chondral_labral_damage_incl_slap_tear_1eb5055b90', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('1105', '8c74fab48ce8cd5ad8253b418f1ed8b3dc53e97fdb7ef07b54b01f9703326b3a', 'Neck muscle soreness/spasm/torticollis', 'subtype_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'dx_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'Neck muscle soreness/spasm/torticollis', 'identity_group'),
  ('1109', '17a58ec1c4ab53126ce6ac3d8867dbe1111ce7c9e24a6be0703c0dedadf0ba42', 'Infrapatella fat pad contusion/haematoma +/- bursitis', 'subtype_infrapatella_fat_pad_contusion_haematoma_bursitis_3758a2ae3c', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury', 'accepted_deterministic'),
  ('1110', '02c7e2e592d54ba70cf8680cc9cbe34d5b02617da8e89f5ca68efad8ec2a654f', 'Chronic Ankle Instability', 'subtype_chronic_ankle_instability_171826703d', 'dx_chronic_ankle_instability_ec5aa4a147', 'Chronic ankle instability', 'accepted_deterministic'),
  ('1111', '6ae90b81ea793e3b4752f8959727088f9cc22ae1be0b86cc4b5d02431e5b53ef', 'Sprain lateral collateral ligament ankle', 'subtype_sprain_lateral_collateral_ligament_ankle_96d9293f86', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('1112', '683438318abb46ab9c4793f0ffa8ebbe20cf8c1ad8d72eb2ea3a9d18bfceb1e5', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('1113', '254adb43a683092d3b0d3e5b7c15c1670dce0fec2ddf29be6948741587b4e0ea', 'Popliteus muscle strain', 'subtype_popliteus_muscle_strain_da248dd71e', 'dx_popliteus_injury_0ac29f0573', 'Popliteus injury', 'accepted_deterministic'),
  ('1114', '28bd41e645034e8b5746371f40beebe4704f40419f44a36bf1d50b140dc8b1f9', 'Rectus femoris strain', 'subtype_rectus_femoris_strain_5670ca194b', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1115', '724b8f23ba6a2049479ef5cd11bacb8983d44175102853646895f0872712ca80', 'Grade 3 A/C joint dislocation', 'subtype_grade_3_a_c_joint_dislocation_89188eec71', 'dx_acromioclavicular_joint_dislocation_8954e719a9', 'Acromioclavicular joint dislocation', 'accepted_deterministic'),
  ('1116', 'dbbf5bf47fb7bf8c07bf343384d24dedb13547357435d478a7e828fbb37453b3', 'Supraspinatus tendon rupture full thickness', 'subtype_supraspinatus_tendon_rupture_full_thickness_fdf35346cd', 'dx_supraspinatus_tendon_injury_3840a1f333', 'Supraspinatus tendon injury', 'accepted_deterministic'),
  ('1117', 'eb475e3969caf0cabc5894687141b181c68027fccd78fce1868ae6c0b1d3c418', 'Neck muscle soreness/spasm/torticollis', 'subtype_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'dx_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'Neck muscle soreness/spasm/torticollis', 'identity_group'),
  ('1118', '640df3d7e7d4fc28011d1e8bae5cf2760f7e5a5b7bd4974f3059f03939a1fe5c', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1119', 'ff00b90201ea45656bc0335eaa87f80ef3d5be9aff2fbe6e17f1c271bffcf4a7', 'Neck muscle soreness/spasm/torticollis', 'subtype_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'dx_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'Neck muscle soreness/spasm/torticollis', 'identity_group'),
  ('1127', 'e1f6a5413176e02df6a405e1ab95bad5da61527c04d1b35f265391ebfbe8461f', 'Medial gastroc strain', 'subtype_medial_gastroc_strain_c97059f639', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'accepted_deterministic'),
  ('1128', '0862c71f0d67fa8538c5e434d898ab521e4813b61f7ca3f865fae42a534960ae', 'Medial hamstring insertion tendonitis/pes anserinus bursitis', 'subtype_medial_hamstring_insertion_tendonitis_pes_anserinus_bursitis_9e25705afb', 'dx_hamstring_tendon_injury_f86b1dad5b', 'Hamstring tendon injury', 'accepted_deterministic'),
  ('1129', 'edaf2d5f36a6fb34e430ff229d88ef9aa9abacaf16e6fd9ee5a7f7718c5a9c8e', 'Superior Labrum Anterior and Posterior (SLAP) lesion shoulder', 'subtype_superior_labrum_anterior_and_posterior_slap_lesion_shoulder_75eead2e0c', 'dx_shoulder_labral_injury_c99b83bba8', 'Shoulder labral injury', 'accepted_deterministic'),
  ('1132', '971c707cdc18b1099782b7470d61437f09d8a6a506dc88209ec6293aaf1c7f0e', 'Hip/Groin Pain Not otherwise specified', 'subtype_hip_groin_pain_not_otherwise_specified_742fb1cd99', 'dx_hip_and_groin_pain_27531edcc3', 'Hip and groin pain', 'accepted_deterministic'),
  ('1133', 'bc3167269563bde52f9b6f59e80f11d1fa5f9ad4066e4db5796706b551767559', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('1134', '828db79e0d0c0bdfb3073c8dbf5e04d28f443d291e62d25f4350a1ef8503acf1', 'Thoracic extensor muscle strain', 'subtype_thoracic_extensor_muscle_strain_1800bde28c', 'dx_thoracic_muscle_strain_or_spasm_8b7d429120', 'Thoracic muscle strain or spasm', 'accepted_deterministic'),
  ('1135', 'ce3ae80f50345a72b086d8468bf15d3959d16bdeb2ec4216851ab08442354d37', 'Ankle synovitis/Impingement/Bursitis', 'subtype_ankle_synovitis_impingement_bursitis_518a389deb', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis', 'accepted_deterministic'),
  ('1137', '7fd0a5b5e98d851cb5e02dcb76207aeb9a291879cf203a3e2518a6ce66bf347a', 'Superior Labrum Anterior and Posterior (SLAP) lesion shoulder', 'subtype_superior_labrum_anterior_and_posterior_slap_lesion_shoulder_75eead2e0c', 'dx_shoulder_labral_injury_c99b83bba8', 'Shoulder labral injury', 'accepted_deterministic'),
  ('1138', '511e116999a17058354bac3e2d227ae8dfa74d6eae0c63daffd2ce1d1ac470e1', 'Cervical functional pain', 'subtype_cervical_functional_pain_e11c275770', 'dx_cervical_functional_pain_e11c275770', 'Cervical functional pain', 'accepted_deterministic'),
  ('1139', '0a1c7a37102e327b3c30a3c23b6d5662c32a1e9ce9098586c11825666a0dc7d9', 'Grade 1 A/C joint sprain', 'subtype_grade_1_a_c_joint_sprain_1ad80c156f', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1140', '6ea435d47a61bb7e0dbb37e77b63fa660649a95441cf984ba754ff39628b83a6', 'Adductor longus strain', 'subtype_adductor_longus_strain_dd1eac51f6', 'dx_adductor_muscle_injury_97164c9b14', 'Adductor muscle injury', 'accepted_deterministic'),
  ('1143', '8026e40b349ee31a2fa7c52c986b10c5002caa2cfced5967b17c4669c4289190', 'Cervical nerve root compression/stretch', 'subtype_cervical_nerve_root_compression_stretch_6f650f0242', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('1144', '882aec180808d3c16f1ea41f3646ea440160280a20ff521f4d57f09fe6aea1a2', 'Lumbar pain with hamstring referral', 'subtype_lumbar_pain_with_hamstring_referral_c859c82cf8', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('1145', '7d2547fd68caa3ea1c2dd3fbea5763d186a31826b3d5e95bb7e7d8a708696218', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('1146', '61166bdf842677c993870a475b546039b491a2eeea0137791b5f2c6a213d2349', 'Costal cartilage/costochondral joint injury', 'subtype_costal_cartilage_costochondral_joint_injury_31f64ad2c4', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('1147', 'e3d433eab7809a7716c5549fe69657cbeceeaa9550439bb978e64b1c79c8a384', 'Head/neck impact not diagnosed as concussion', 'subtype_head_neck_impact_not_diagnosed_as_concussion_beb8ef679e', 'dx_head_impact_non_concussion_3feadb53e8', 'Head impact, non-concussion', 'accepted_deterministic'),
  ('1148', '4957da2d3169ca90a183b7706fce26665d56571d3ea8e8d91fa6c186dd9c5356', 'Facet Joint/Neck Ligament sprain', 'subtype_facet_joint_neck_ligament_sprain_369f0afd14', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder', 'accepted_deterministic'),
  ('1149', '64d3328f9118626203df3d532bce36549fb2d90fa3a2baf592c773c067a4b8c9', 'Lumbar Spine muscle and Tendon Strain/Spasm/Trigger Points', 'subtype_lumbar_spine_muscle_and_tendon_strain_spasm_trigger_points_0af31940e8', 'dx_lumbar_spine_muscle_and_tendon_strain_spasm_trigger_points_0af31940e8', 'Lumbar Spine muscle and Tendon Strain/Spasm/Trigger Points', 'identity_group'),
  ('1156', 'bdffce7019fa10ce45e8142fc883410baa2b260ce0f5268992d0b81b28d8737f', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1157', '130ca359c15ccf3709bee3f48b77ffa0a600e33ac029b7c3078cfdb31664b9e1', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1160', '417d4bd296b852d46dd76948db90eacc23a651a3f3849aef563a9d2c342bca55', 'Thoracic facet joint sprain', 'subtype_thoracic_facet_joint_sprain_205cac3c00', 'dx_thoracic_facet_joint_disorder_519c2ae5a8', 'Thoracic facet joint disorder', 'accepted_deterministic'),
  ('1166', '21429873b3149d52efd300fddca2e65f73ad4e8065588f457717876adf9e927b', 'Tibialis posterior tendinopathy', 'subtype_tibialis_posterior_tendinopathy_521e81b1a1', 'dx_tibialis_posterior_tendon_injury_8ddfcac54e', 'Tibialis posterior tendon injury', 'accepted_deterministic'),
  ('1167', '559af2bbdae20fe343b79468cb2fb1056c5fcbee55a458302210d0734511b3de', 'Gastrocnemius tendon injury', 'subtype_gastrocnemius_tendon_injury_eec309de3f', 'dx_gastrocnemius_tendon_injury_eec309de3f', 'Gastrocnemius tendon injury', 'accepted_deterministic'),
  ('1169', '09279f0f987ec75cdc30110a134593120265a59f18ae6b5c1541eb615756a42d', 'Scalp laceration', 'subtype_scalp_laceration_50be43ed71', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('1170', 'a8918663981045db8bc21f328a75552b6996fe72d05b63b22f49baab0a40d305', 'Concussion with no concerning history or signs', 'subtype_concussion_with_no_concerning_history_or_signs_a256f29e16', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1171', '835c7ed7916fb226c737c201ddcec207ed707e27db956fcd54a4a6516597fead', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1172', '6428368c4410cb3e7fc6bb7a262bb788af3d383c467a689c76f8a886a995d6f1', 'Chronic Ankle Instability', 'subtype_chronic_ankle_instability_171826703d', 'dx_chronic_ankle_instability_ec5aa4a147', 'Chronic ankle instability', 'accepted_deterministic'),
  ('1173', 'ce269305d630ad82c220d34a38aa2af8f092707f637ce525e443f2a922f3c9cf', 'Neck muscle soreness/spasm/torticollis', 'subtype_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'dx_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'Neck muscle soreness/spasm/torticollis', 'identity_group'),
  ('1174', 'fcb00d6c20a8ac24708de5bda45419b51d68258c12eb5b3d9e9d3b57f6c9047b', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('1175', '1db7edb2fdbfd44f460e8e8cf8f42d61605f431dc4c87aa6c0d51882f4979f48', 'Diagnosis not specified', 'subtype_diagnosis_not_specified_7787afa6db', 'dx_diagnosis_not_specified_7787afa6db', 'Diagnosis not specified', 'accepted_deterministic'),
  ('1176', '317a9f0cd8436cbcc858eec3cd0a40d3e4213085d476ef7f303f51e7e0a14c88', 'Acromioclavicular (A/C) joint sprain', 'subtype_acromioclavicular_a_c_joint_sprain_75f6a9a659', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1177', '9457c35ad03744ecb0abeafdaa02bd4cb2800f2bbec1b5891db2db6a8c5c7e78', 'Inferior tibiofibular syndesmosis sprain', 'subtype_inferior_tibiofibular_syndesmosis_sprain_0545fce188', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'accepted_deterministic'),
  ('1178', '3e649e4942a4f8ab393f542f58a56e4b0d43b1d1cb3de11dbc6d8f936b83a920', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('1179', 'fa0cda7313570e3e0ced5a718bdc478486e01c9e0a631a35f4f161ecc4712a8b', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('1180', '9b269f72989ce92e97e92df9a70c1042db23df596c8476b062797e55aaf8fa6f', 'contusion/haematoma, hip region', 'subtype_contusion_haematoma_hip_region_ffc578cee0', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma', 'accepted_deterministic'),
  ('1184', '966eee628522c494d58cf783a230daa62b24972bd008bbeb2915b7cd29623675', 'Thigh Laceration/Abrasion', 'subtype_thigh_laceration_abrasion_dff2e1be4d', 'dx_thigh_laceration_or_abrasion_cec8e820c4', 'Thigh laceration or abrasion', 'accepted_deterministic'),
  ('1185', 'a07364ea60a1e20d159c0272d76b9b3a276c2edb2db6fd737e08dddd28cccb9f', 'Combined ligament injuries knee', 'subtype_combined_ligament_injuries_knee_bf95dbc8d1', 'dx_knee_multiligament_injury_153dc1f5ba', 'Knee multiligament injury', 'accepted_deterministic'),
  ('1186', '211f448fd6cf4d2eee2254b7dd5f88dbc6e4c20747e22a7c7ba3bf08221bc679', 'Forearm Pain/Injury not otherwise specified', 'subtype_forearm_pain_injury_not_otherwise_specified_a829f429a2', 'dx_forearm_pain_5cdc1ed996', 'Forearm pain', 'accepted_deterministic'),
  ('1187', '3d36570bc90603d42543a508a300faaab799971febdc9b710e2606a4f4a3bdf6', 'Bruised ribs/chest wall', 'subtype_bruised_ribs_chest_wall_0c223ac8bd', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('1188', 'c45e85c53d27e4d29b49610ab3f7ad235ae9411511c14258d366d288c22e2375', 'Jaw sprain/temporomandibular joint (TMJ) symptoms', 'subtype_jaw_sprain_temporomandibular_joint_tmj_symptoms_6bea039af2', 'dx_temporomandibular_joint_disorder_d15bf1f47e', 'Temporomandibular joint disorder', 'accepted_deterministic'),
  ('1189', '83530d9833bf338207d01a57d53f78926f7843b743e8e1f20808f4fe0b7cc131', 'Brachial plexus traction injury/burner/stinger', 'subtype_brachial_plexus_traction_injury_burner_stinger_29eb517979', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury', 'accepted_deterministic'),
  ('1190', 'b5a3a8c669dd2aee1d678d1bbd0a2f6a1ac31241c8c5e2b0f5c637ef189b9945', 'Lumbar pain non-specific', 'subtype_lumbar_pain_non_specific_29a75fb1e1', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('1192', '77399cb6da621986157a6fa9399e74f5705409a3ad06235d4783f5b9d8ad212d', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1193', '7b73802529c991f28ab40e9925b169ea16eb9b2f1c562edde19dd2811adf0ff4', 'Elbow ulna/medial collateral ligament (UCL) strain or tear', 'subtype_elbow_ulna_medial_collateral_ligament_ucl_strain_or_tear_ab4c438f84', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury', 'accepted_deterministic'),
  ('1194', 'e35faf22ae7725bbe0bc7c2ebe27b7e0421b0ee40d28bf575c57be0b4c2f0c19', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('1195', '7aaf01dea618079964c91a708170299ea5ab13ca5190e8f256a8f00ca9a2e7f2', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('1196', 'd9ed5ae9d3451b27c4fc7f62f3d4c4ff000ace3402d358b405f0bd36d466fca2', 'Gastroc muscle trigger points/spasm', 'subtype_gastroc_muscle_trigger_points_spasm_c6c39392b5', 'dx_gastrocnemius_trigger_points_spasm_0e2bdaca3b', 'Gastrocnemius trigger points/spasm', 'accepted_deterministic'),
  ('1197', 'e8f30aa91b35c4dbcc04a4204e280ac82d679bd76a3e37ea193bdb6bcc908d6f', 'Sprained/jarred wrist joint', 'subtype_sprained_jarred_wrist_joint_7ec711f5b5', 'dx_wrist_injury_d94414e2c6', 'Wrist injury', 'accepted_deterministic'),
  ('1198', 'e18c56256507382ed20e5edee88f5e1d01d69940d6d74bda4a911308295dd420', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('1199', '09d284c059fedba0e55c65becf9c03b6bff558aca1e80dd841ebfd3dee373796', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('1200', 'd1e0910c7c7da82c31f7e934ec0f7c79871d2c21a7ba5f860198d88e829bc5e9', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('1201', 'e11ff9255cf86917f06e26f900c63b94468c31cad3338e8decff5e699e14d67e', 'Bruised ribs/chest wall', 'subtype_bruised_ribs_chest_wall_0c223ac8bd', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('1202', 'c4364efdfc8fc8640a8f6e46480282a6dd4f84c8703fb53eab0e2347e8193bbd', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1203', 'a679dc3e1d4a376285eb7bb03627cbfd9c0b6ea6fe6103ac4e00d7bead622896', 'Quadriceps strain or tear', 'subtype_quadriceps_strain_or_tear_17ff226482', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1204', 'c9faf09e345afd2f5ca8723650e234c3a8f18876e376a6f4f6a9fbaf0dd43fbf', 'Head/facial contusion/haematoma', 'subtype_head_facial_contusion_haematoma_1131a060b5', 'dx_head_and_facial_contusion_74a20a767e', 'Head and facial contusion', 'accepted_deterministic'),
  ('1216', '803781abf3411a3deb3a6709f47e2406f468a57a954fb0c9d226260f1ad2008c', 'Shoulder contusion/haematoma', 'subtype_shoulder_contusion_haematoma_1f687995cb', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion', 'accepted_deterministic'),
  ('1217', 'dafaeb2a94f8ac366db6abd06e95ff1886546bfed25428b0c7257ef95181c866', 'Bruised ribs/chest wall', 'subtype_bruised_ribs_chest_wall_0c223ac8bd', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('1218', 'e71f52521ef24d616ada5516a22a339f27e0a4cbfea55014d4d884b5bb46e167', 'Forearm contusion/haematoma', 'subtype_forearm_contusion_haematoma_3be5d37b72', 'dx_forearm_contusion_ea321e8e45', 'Forearm contusion', 'accepted_deterministic'),
  ('1219', 'f56471eab549dd7369a439cc5b8878982d6b216edacae83f6990ec7c38bcf6e3', 'contusion/haematoma, hip region', 'subtype_contusion_haematoma_hip_region_ffc578cee0', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma', 'accepted_deterministic'),
  ('1220', '0e6712f81f2c40c528ee3b8c89a53fc35c76d06d396ca3f5f9569ff6c23ae0ea', 'Neck Pain/Injury Not Otherwise Specified', 'subtype_neck_pain_injury_not_otherwise_specified_bb23fae555', 'dx_neck_pain_58ed6a0781', 'Neck pain', 'accepted_deterministic'),
  ('1221', 'd9e5fab2f0b506dfd93d79f4301c7b761a5fbce32866a4058b40abb7af87707f', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('1222', '3bb937f41546adfdcdfe086a6830bc3264d55180f45e718fe9bebdc62a820b35', 'Knee contusion/haematoma (extraarticular)', 'subtype_knee_contusion_haematoma_extraarticular_19a33609a2', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('1223', '3174e8163a73d877b0b45b4219a7e021f4ecc007ec10ff457468b3e3c604833a', 'Acromioclavicular (A/C) joint sprain', 'subtype_acromioclavicular_a_c_joint_sprain_75f6a9a659', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1224', '665711065f3465ef333d3f75e4420d639e4b011e219bd85a004ac67eaf1c1d2a', 'Finger laceration', 'subtype_finger_laceration_5c45833b82', 'dx_hand_wrist_laceration_or_abrasion_35c31d7555', 'Hand/wrist laceration or abrasion', 'accepted_deterministic'),
  ('1225', '05f9e23a80012ed801a724d3e0ca9d47666328e029e73712ca6a5e14c1eed64b', 'Sprain lateral collateral ligament ankle', 'subtype_sprain_lateral_collateral_ligament_ankle_96d9293f86', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('1251', '1ce8badc9b45e8c041969f523e5759dac03933703af86ca0ffa61621557c84f5', 'Back referred hamstring tightness', 'subtype_back_referred_hamstring_tightness_6fbd78d98a', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'accepted_deterministic'),
  ('1252', '372b5fb9691b2366f2559f41a7f826618eeffb0200819faa496bb3134adb9b30', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('1253', '0050357f1734aa3c9bc488d8043a9aeb9d324064fb0c596ac837a427455ba1cd', 'Spondylolisthesis any Level', 'subtype_spondylolisthesis_any_level_d276b4f399', 'dx_spondylolisthesis_4fff227886', 'Spondylolisthesis', 'accepted_deterministic'),
  ('1254', 'f9975f4261c400cbecccc7b1f82e9bddd535c9517b3a03b36575b3236fdd4484', 'Plantar fascia rupture', 'subtype_plantar_fascia_rupture_dbe62f4d0b', 'dx_plantar_fascia_rupture_dbe62f4d0b', 'Plantar fascia rupture', 'accepted_deterministic'),
  ('1255', '10e454bb35579b9ee0e8155a5269af71741e6e981f375dd636955096e695cc17', 'Lateral gastrocnemius trigger points or spasm', 'subtype_lateral_gastrocnemius_trigger_points_or_spasm_a1f39ca618', 'dx_gastrocnemius_trigger_points_spasm_0e2bdaca3b', 'Gastrocnemius trigger points/spasm', 'accepted_deterministic'),
  ('1256', 'ce2d37cd22352c5b2ca3aef7ff16cd1ce6c451e802e423887767c4e1245c239b', 'Neck contusion/haematoma', 'subtype_neck_contusion_haematoma_d4fc2fd301', 'dx_neck_contusion_7f04c7cc90', 'Neck contusion', 'accepted_deterministic'),
  ('1258', '33cf0f5648853dc01cfa04634ead250e13a99fb79467f86b4ab2597cc922814d', 'Cervical Spine Instability', 'subtype_cervical_spine_instability_87f1adf4cc', 'dx_cervical_spine_instability_658367d444', 'Cervical spine instability', 'accepted_deterministic'),
  ('1259', '575a80f1c49847dfac018fc46066537fe4a5224300f6b9f273d25feeb5ff1a32', 'Hamstring origin tendinopathy', 'subtype_hamstring_origin_tendinopathy_aa7298eaae', 'dx_hamstring_tendon_injury_f86b1dad5b', 'Hamstring tendon injury', 'accepted_deterministic'),
  ('1260', 'd66959bee95b41bda00c2e38ea02762736659cda1cb89a7de5437748ce5bb915', 'Scapholunate ligament sprain', 'subtype_scapholunate_ligament_sprain_4db8cb13f7', 'dx_wrist_ligament_injury_6b21f37d24', 'Wrist ligament injury', 'accepted_deterministic'),
  ('1261', '432e3e785e750354ecbcceb59d9b626b75f51431292c1f4377f67572be32704b', 'Acromioclavicular (A/C) joint sprain', 'subtype_acromioclavicular_a_c_joint_sprain_75f6a9a659', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1262', 'bcfad6cddecf9dc3ea622a01680c1cd8fc140329eb50f1bf8b03578847374124', 'Groin soreness or trigger points', 'subtype_groin_soreness_or_trigger_points_70c27347b8', 'dx_groin_soreness_or_trigger_points_70c27347b8', 'Groin soreness or trigger points', 'identity_group'),
  ('1263', '9318cd2c2b955565fd59caba779d81534e4235edc26ed973d722bdb432c78844', 'Hip flexor muscle strain', 'subtype_hip_flexor_muscle_strain_3e1d987aae', 'dx_hip_flexor_injury_cedda9fa03', 'Hip flexor injury', 'accepted_deterministic'),
  ('1266', '8097ddcc91246fbc6b0437b52b600640a0f42c65ecfbfc35562bd0de1572c551', 'Cervical nerve root compression/stretch', 'subtype_cervical_nerve_root_compression_stretch_6f650f0242', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('1268', '5eab959acfdd1bacf90596a9b560a6d49f937487234264e971cb4fe3a84e35f4', 'Adductor longus strain', 'subtype_adductor_longus_strain_dd1eac51f6', 'dx_adductor_muscle_injury_97164c9b14', 'Adductor muscle injury', 'accepted_deterministic'),
  ('1269', '1802fb58e69d407b0b93c9fd7d04bd2429781024b751af14231e863535aa28a0', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('1270', 'd5c771bb224268e8404f1866132d9b8e4ac499e5c22e38de47efdd4cee4606ae', 'Avulsed/fractured tooth', 'subtype_avulsed_fractured_tooth_d992bbc154', 'dx_dental_injury_b97b2afe75', 'Dental injury', 'accepted_deterministic'),
  ('1271', '85b1624f56c40fe267d05025d9373546c5369a69533ec29fc7517d31ff66d30a', 'Distal phalanx fracture middle finger', 'subtype_distal_phalanx_fracture_middle_finger_67705c5715', 'dx_middle_finger_distal_phalanx_fracture_05d6aac876', 'Middle finger distal phalanx fracture', 'accepted_deterministic'),
  ('1272', '8512590f9be2de5ceaf37d190855eb54dc753a68b7e084eb356ca77f5756f131', 'Soleus Trigger points/Spasm', 'subtype_soleus_trigger_points_spasm_dfb83ed490', 'dx_soleus_trigger_points_spasm_56202bbe31', 'Soleus trigger points/spasm', 'accepted_deterministic'),
  ('1273', '0524cdcf7bf8e89c9fa546527b90d02e13d0c3cee80ce68c66919a080aef79b7', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1274', 'd15240d009fcd492700bf6a6a929094bf208e7650c2e5bd716c78c3d1345d6c7', 'Ankle multiple ligaments sprain', 'subtype_ankle_multiple_ligaments_sprain_7b65bb0881', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('1275', 'a4b932fc5f5bf2a9c876e6314e9788453670c65225756ad0d055abd46afffe07', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1276', 'b1bda002dce5e40149ab5cf2fca34c1bc24df4e5f1def822c1274fb5ab6f7833', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1277', 'ad070221f132cb58e95c5dc90dec19e0c9b608e5eae5b5272fe0cd320a3b8f5c', 'Elbow olecranon bursitis', 'subtype_elbow_olecranon_bursitis_ce5591cc2d', 'dx_elbow_bursitis_24fdbc7698', 'Elbow bursitis', 'accepted_deterministic'),
  ('1279', 'edee76c7aa695dd8d21f2b0b07242bf2b74ed7acd5b131fb83f53b23f129390b', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('1280', '6b81c02d7959cffb9d0a3889a8e7378647522d37cd6885c95df0147d69f069c1', 'Cervical nerve root compression/stretch', 'subtype_cervical_nerve_root_compression_stretch_6f650f0242', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('1281', 'd3d181310d1e586d8a487d65300618e2378c0fb36b39b0f30a496d7f4ccf06af', 'Gluteus maximus strain', 'subtype_gluteus_maximus_strain_5f32db98a3', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury', 'accepted_deterministic'),
  ('1282', 'ebbaba03c662adebe559cca6007d9edd10ad58751f69e0199b26c4c2236e8e11', 'Shoulder contusion/haematoma', 'subtype_shoulder_contusion_haematoma_1f687995cb', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion', 'accepted_deterministic'),
  ('1283', 'c2eb46445ce1d4a604676ea517d8172afd0335eec2c05688cf0c960758fdb4f1', 'Bruised ribs/chest wall', 'subtype_bruised_ribs_chest_wall_0c223ac8bd', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('1284', 'c95019ae2d792b0eb5e0632eef97b2edb23592a47e8fa8331b585c25d5885cf3', 'Cervical nerve root compression/stretch', 'subtype_cervical_nerve_root_compression_stretch_6f650f0242', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('1285', 'c9f8c5fa757dd636f1750fd3582ed932f8852ed60794439ee6513931cafca8d9', 'Costal cartilage/costochondral joint injury', 'subtype_costal_cartilage_costochondral_joint_injury_31f64ad2c4', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('1286', '223831c65c02e2d6ee8f3851db595d29a7f622236cb2b2696ad610ddabfddf6f', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1287', '507db7b54f9a2b84457a8dfcd18601d2904ceb7343eaee52464f4f868a97db47', 'Groin soreness or trigger points', 'subtype_groin_soreness_or_trigger_points_70c27347b8', 'dx_groin_soreness_or_trigger_points_70c27347b8', 'Groin soreness or trigger points', 'identity_group'),
  ('1288', '55da64258cfc880e7559a48bb772e97f2f1b204d5118743822554a439fb54c20', 'Lateral hamstring trigger points', 'subtype_lateral_hamstring_trigger_points_ea90bfdf92', 'dx_lateral_hamstring_trigger_points_ea90bfdf92', 'Lateral hamstring trigger points', 'identity_group'),
  ('1289', 'ba3f1b965b5e26e52af55da13740a746148b6d5518a12aebc14c829946898e0c', 'Groin soreness or trigger points', 'subtype_groin_soreness_or_trigger_points_70c27347b8', 'dx_groin_soreness_or_trigger_points_70c27347b8', 'Groin soreness or trigger points', 'identity_group'),
  ('1291', 'a668d84bfff36081fa6aa2d769942729c424849b52fc85d4eb84710cf9c66e30', 'Ankle anterior impingement', 'subtype_ankle_anterior_impingement_3a5b67cd15', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis', 'accepted_deterministic'),
  ('1292', '2a79453811e26178b91ec3f0b765ea7813d08491d1128bb823d66051dac181aa', 'Glenohumeral joint sprains', 'subtype_glenohumeral_joint_sprains_0aefa97c55', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('1293', '03782a6786989d556429e645957e3c5ef3b82133a95216446f71b815a74eda22', 'Cervical nerve root compression/stretch', 'subtype_cervical_nerve_root_compression_stretch_6f650f0242', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('1294', 'c334ed6082414356a9f3b3546a9e7c764f3739d9f9efc41a6cc96ac820a483f0', 'Ankle anterior impingement', 'subtype_ankle_anterior_impingement_3a5b67cd15', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis', 'accepted_deterministic'),
  ('1295', '72507e179a6015d0b2092701bcc2205164222b9e26da878bcbf09665106af3fc', 'Inferior tibiofibular syndesmosis sprain', 'subtype_inferior_tibiofibular_syndesmosis_sprain_0545fce188', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'accepted_deterministic'),
  ('1296', 'd2da01841361ec5df4d376138121a64a9aa8a7bbfa2d8720f0bf48145b214777', 'Cervical Spine Instability', 'subtype_cervical_spine_instability_87f1adf4cc', 'dx_cervical_spine_instability_658367d444', 'Cervical spine instability', 'accepted_deterministic'),
  ('1297', '36f9aea544f6d97b11f220a83b77ad89a1f4b4a8f9aafc9c0c202eceedd3b3dd', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1298', '8932e5a115a5dbdc994786016ac94d6314ab3553539b708082c3b54b17826c67', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1301', '1d543171bbdfad48316486ed5cfefcc31e54cb65d1d3c784c6cbe0b6a5b3006a', 'Gluteus medius/minimus strain', 'subtype_gluteus_medius_minimus_strain_d87e368e47', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury', 'accepted_deterministic'),
  ('1302', 'e96ed0dbe50e4e794781820555c3b51adbb5a9e15d23532f8c4312e89af206b6', 'Back referred hamstring tightness', 'subtype_back_referred_hamstring_tightness_6fbd78d98a', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'accepted_deterministic'),
  ('1304', '0f882c0709dc1da56461196dc050b4d748fe2c97df8fa7cfd54e22a789fdc189', 'Anterior shin splints', 'subtype_anterior_shin_splints_0ed8947a1b', 'dx_shin_splints_88d33d2fb5', 'Shin splints', 'accepted_deterministic'),
  ('1305', 'f412339d261a78cf3361c9df3c8b787b89e4cfe164018acc87a0229ccabf7df7', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1306', '8332c1475c3100a489ba08c00150af3a6de816a051fbd3a11fb663bde7d46413', 'Knee medial collateral ligament (MCL) injury', 'subtype_knee_medial_collateral_ligament_mcl_injury_9cce43fa53', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('1307', '7cd01ef7b5508fbdaa2adcc720b2a5cf5b68890f8286a0a96e24298823875697', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('1308', '7084c57ca5a6a3c0ca82066397355e716b0992f92e833c4452a3a1ee84de7d38', 'Foot contusion/haematoma', 'subtype_foot_contusion_haematoma_edd1025815', 'dx_foot_contusion_6c8a5bb721', 'Foot contusion', 'accepted_deterministic'),
  ('1309', '554ec5489920e0f402dc7d890a0ddd02cdd1f8418ea954585c6e287e5e607696', 'Lumbar pain with hamstring referral', 'subtype_lumbar_pain_with_hamstring_referral_c859c82cf8', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('1310', 'e7378cf5b55e9865928bfbab36730e88b2463bd6832fda0d0d55df9db0ce1151', 'Cervicogenic headache', 'subtype_cervicogenic_headache_5202049312', 'dx_cervicogenic_headache_5202049312', 'Cervicogenic headache', 'accepted_deterministic'),
  ('1311', '500eb5f0a5d9243267c14487ec520966a642498120f3dcf75e2032bdc1b1ef41', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1312', 'b93c928da50c4d51890e6000ef420de5356f2681cf32e8a8a9a4f1c6c8b7e8a8', 'Knee Impingement/Synovitis/Biomechanical Lesion not associated with other conditions', 'subtype_knee_impingement_synovitis_biomechanical_lesion_not_associated_with_other_conditions_ed9f75283a', 'dx_knee_synovitis_impingement_02e229b1cc', 'Knee synovitis/impingement', 'accepted_deterministic'),
  ('1313', '8a4390e0989082165ed9949d0aaacc9ff118ff18400287a064c1fac68184de18', 'Hip joint chondral lesion', 'subtype_hip_joint_chondral_lesion_7e190b132e', 'dx_hip_cartilage_injury_59a16f2a24', 'Hip cartilage injury', 'accepted_deterministic'),
  ('1314', '7162e5ab5fc1e583c528fc39b7e0ceee68c0d9be17326602f5ca479e10af633c', 'Achilles tendon strain', 'subtype_achilles_tendon_strain_24d715a823', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('1315', '1cc7d6d2a0b966b85f04e00b694fef4a600bfd0cdadf0ed8964df70425ecb163', 'Sprain lateral collateral ligament ankle', 'subtype_sprain_lateral_collateral_ligament_ankle_96d9293f86', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('1316', '34c4a9cd10502352792ca1b79893dbcf69311799f13179015291b0feef6d7122', 'Knee contusion/haematoma (extraarticular)', 'subtype_knee_contusion_haematoma_extraarticular_19a33609a2', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('1317', '3947434e588baa73f228babf494365793d18f268f21057326b928b9d778aa833', 'Sprain lateral collateral ligament ankle', 'subtype_sprain_lateral_collateral_ligament_ankle_96d9293f86', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('1318', 'f7401a1f4b8407b3ad14f9ea6b0c9807342812dcc6f0f999ef7b5cd844576b9a', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1319', 'f637178510441dd2f6a99a261684c4d0d9a491904fc3bd3001dbea973686fd2c', 'Sprained toe/''turf toe''', 'subtype_sprained_toe_turf_toe_8130fe4d55', 'dx_great_toe_injury_71c02ad835', 'Great toe injury', 'accepted_deterministic'),
  ('1320', '04d99f9cc8b3a9c358d9f4829b38615ad26aff8e8ffe4c5572a137415e9d8fb8', 'Back referred hamstring tightness', 'subtype_back_referred_hamstring_tightness_6fbd78d98a', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'accepted_deterministic'),
  ('1321', '6ebaf803adf1f238da89f48e2059de89df3a3f2fa09bc0a1fb4ce492fcee8069', 'Peroneal Haematoma', 'subtype_peroneal_haematoma_3a4c507ede', 'dx_peroneal_injury_b0c8606ad2', 'Peroneal injury', 'accepted_deterministic'),
  ('1322', '611bccff421a0b6aa445931a7d3c817646236c9ab0941b85df9620d322a9a818', 'Knee Pain/Injury Not otherwise specified', 'subtype_knee_pain_injury_not_otherwise_specified_f2690253b3', 'dx_knee_pain_609ce718bc', 'Knee pain', 'accepted_deterministic'),
  ('1324', '729aa08a73b15c81059837dfc94c7ae7236b0a3aa935b9e93b4200b43cd3dc3e', 'Sprain lateral collateral ligament ankle', 'subtype_sprain_lateral_collateral_ligament_ankle_96d9293f86', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('1325', '860d56538fd7ffc17e850b75b7955c4dfaacc8b60888e5a4d4dec578f3a3be90', 'Lumbar pain with hamstring referral', 'subtype_lumbar_pain_with_hamstring_referral_c859c82cf8', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('1326', '65449d5a4b4f06876f45c9691c45f3bee4c802f103fbbdc6de12f1001063f059', 'Groin soreness or trigger points', 'subtype_groin_soreness_or_trigger_points_70c27347b8', 'dx_groin_soreness_or_trigger_points_70c27347b8', 'Groin soreness or trigger points', 'identity_group'),
  ('1327', '5c295fb44bdbe2b1fba73b4b831405fc39e9ede6c4541c8fc05abbb0893f2d55', 'Groin soreness or trigger points', 'subtype_groin_soreness_or_trigger_points_70c27347b8', 'dx_groin_soreness_or_trigger_points_70c27347b8', 'Groin soreness or trigger points', 'identity_group'),
  ('1328', '900a588ab6c10dc09e2cf97fd75a63ebfd441fdd2990144298c0116df6887643', 'Brachial plexus traction injury/burner/stinger', 'subtype_brachial_plexus_traction_injury_burner_stinger_29eb517979', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury', 'accepted_deterministic'),
  ('1329', '177728b1f6c3a1df023cf477bd8a42863bebe4444680f35c03bb62505ea403b5', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1330', '9995b42649f53ab61fd2915a8c33a2a56ceb04059daaabb57784cad2db37cec3', 'Ankle synovitis/Impingement/Bursitis', 'subtype_ankle_synovitis_impingement_bursitis_518a389deb', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis', 'accepted_deterministic'),
  ('1332', '209e45e3b020d278b7348ff0430e5d1b7d61380967cf89bd6dd60b60e7bd3a9c', 'Grade 3 hamstring strain', 'subtype_grade_3_hamstring_strain_6183bcd886', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1333', '6e419130466b28ba77c2b291c8769fa191ec884ca7842f3db5c6b42b744333c5', 'Chronic lumbar functional pain', 'subtype_chronic_lumbar_functional_pain_f5137cab5d', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('1334', 'c0bfa26a14b721422fd2c671a16d70b1a7a0dc16fef03c64d8f3a82fc22c646b', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('1335', '7b81bd226dc8246847e7d60edcbff39169580017cc6feb0bb8329c62c7e128f4', 'Sprain IP ligament(s) great toe', 'subtype_sprain_ip_ligament_s_great_toe_610119a6ab', 'dx_great_toe_ip_sprain_fa3b57c942', 'Great toe IP sprain', 'accepted_deterministic'),
  ('1336', '3b9334898195983b2155117362a706574cce653a31f448f9027ec44e163f4192', 'Pectoralis major muscle strain', 'subtype_pectoralis_major_muscle_strain_5887d37d12', 'dx_pectoral_muscle_injury_981511cfe1', 'Pectoral muscle injury', 'accepted_deterministic'),
  ('1339', '7db55a69d9b507d350aa27ed3182b65d9e12363105451ef87f4de38bfec8de59', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('1340', 'a0a0400c496562b96543b0284dead10d203401497e53601708ee9d314bd7b710', 'Patellofemoral pain with patellar tendinopathy', 'subtype_patellofemoral_pain_with_patellar_tendinopathy_d1c558c88e', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'accepted_deterministic'),
  ('1341', '159a743fb346a869f01778d336f7d1f51146d991f034f97b9e4619ede51a4aa8', 'Chronic thoracic functional pain', 'subtype_chronic_thoracic_functional_pain_3fccab80ba', 'dx_thoracic_spine_pain_9ec9a9f2e5', 'Thoracic spine pain', 'accepted_deterministic'),
  ('1342', '7ebb10c70a29a3f0077b70ae4e9ada0531f3dbf306fd1a8b5bf83ccee924dca5', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('1343', 'df95a900880a6f47dda9bd05eea7530d71ced28381e151d187c20823a215a8c6', 'Shin contusion', 'subtype_shin_contusion_5ea21c3f50', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('1344', '6214b708a8ff6e411be9d4197f6db47efd3f9c914a1fc50d19994312f2dc6619', 'Back referred muscle tightness', 'subtype_back_referred_muscle_tightness_16c7f83f63', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'accepted_deterministic'),
  ('1345', '89402964d5148b1d7e4a4333a6f8d2c3ce8ecb2386cfebe51e4766c5474cd3dd', 'Proximal adductor trigger points', 'subtype_proximal_adductor_trigger_points_e0737a9324', 'dx_proximal_adductor_trigger_points_e0737a9324', 'Proximal adductor trigger points', 'identity_group'),
  ('1348', 'af5eccd9efb4a458df44b64a1ab1fb26833905d3d13c4d314557cbc2f83c126e', 'Hamstring origin tendinopathy', 'subtype_hamstring_origin_tendinopathy_aa7298eaae', 'dx_hamstring_tendon_injury_f86b1dad5b', 'Hamstring tendon injury', 'accepted_deterministic'),
  ('1349', '51b2cd91d18efe9d9ed7d80954bb73c2215259ee0bc7b117aafdf73dd0f29ab6', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1350', 'ff5dde4cfa8cac6118b2566e475f7ba655f4294ac0b44e6c16ae230cd55215fb', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1351', 'baf3ee1f74cc3d79935b6c4c99b3c0cb266aef0af2202ab6b48c2ac0df313f96', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1352', 'a713fa61bc8f2397849b9cc482af4c681b2f57049a58a93f5e04376117bd8aa0', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1353', '9009cc7fe7ed104b8417c246aec492197ae88bbee8ab94ea80bd30906dc137dc', 'Calf muscle cramps/spasm', 'subtype_calf_muscle_cramps_spasm_7890832741', 'dx_calf_cramp_spasm_950b710fbb', 'Calf cramp/spasm', 'accepted_deterministic'),
  ('1354', '13369874632022b223e092896d085093ec6651ab68ab2733f4f68e7203413bfb', 'Hip and Groin Muscle strain or tear', 'subtype_hip_and_groin_muscle_strain_or_tear_936dbed7ca', 'dx_hip_and_groin_muscle_injury_7ccd814142', 'Hip and groin muscle injury', 'accepted_deterministic'),
  ('1355', '2022a7eabbd054d3d11e6d6d9db5050f7fc62e2d330d815216b8672c6ea6efe9', 'Infrapatella fat pad contusion/haematoma +/- bursitis', 'subtype_infrapatella_fat_pad_contusion_haematoma_bursitis_3758a2ae3c', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury', 'accepted_deterministic'),
  ('1356', '563b4458cf61d15890481412c50dd7621ca89e8bf552132fcfa5a2e86055a79c', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1357', 'edc9590d0c6622e7f9c9d0cc21e16ae482c0d34efffc1ade7780a64ed38062b2', 'Elbow ulna/medial collateral ligament (UCL) strain or tear', 'subtype_elbow_ulna_medial_collateral_ligament_ucl_strain_or_tear_ab4c438f84', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury', 'accepted_deterministic'),
  ('1358', '5dd6172da92cfd1df08fec68eeca24ce62fe0e3b622c5cb59fc4854adfdbc497', 'Hamstring cramping during exercise', 'subtype_hamstring_cramping_during_exercise_2eb7c1414b', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm', 'accepted_deterministic'),
  ('1359', '3a6b45e8ef51d830ef216980a70a96cee4f288fea6985bbf66e7ac131a7a92d6', 'Thoracic Pain/Injury not otherwise specified', 'subtype_thoracic_pain_injury_not_otherwise_specified_2fa9b78923', 'dx_thoracic_spine_pain_9ec9a9f2e5', 'Thoracic spine pain', 'accepted_deterministic'),
  ('1360', '91b3d22fd501af7fe797580be9b2fda7d44a2d86fad4efb3ebf2946f1747e5dd', 'Back referred hamstring tightness', 'subtype_back_referred_hamstring_tightness_6fbd78d98a', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'accepted_deterministic'),
  ('1361', '991b90d9e0ab689e698e060c1f90a648db5d8dbf544da80ce272a204b8c052e0', 'Rectus femoris strain', 'subtype_rectus_femoris_strain_5670ca194b', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1362', 'ba9602530e1054b03026279dcccd3266fa5d618ea83a246d4b220b54d326f2cf', 'Bruised ribs/chest wall', 'subtype_bruised_ribs_chest_wall_0c223ac8bd', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('1363', '95602e9a609923e715365773e3eff5344174b155e52aaaa9758c93b35732548b', 'Adductor longus tendon rupture', 'subtype_adductor_longus_tendon_rupture_b9c9dcf83a', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'accepted_deterministic'),
  ('1364', 'aff5fa3daf7451404e5cc3dfd852a526eed9515e1f2f5b5635613ea3196d724b', 'Cervical Spine Instability', 'subtype_cervical_spine_instability_87f1adf4cc', 'dx_cervical_spine_instability_658367d444', 'Cervical spine instability', 'accepted_deterministic'),
  ('1365', 'f3a7635e266616de2ebf881db752b4e1834b51f1a574ead457444b7d103e2870', 'Knee meniscal cartilage injury', 'subtype_knee_meniscal_cartilage_injury_eda330b0ed', 'dx_meniscal_injury_b166306f7d', 'Meniscal injury', 'accepted_deterministic'),
  ('1366', 'e4f3c5dacc73f750444785d354cbee468a91b7487e5366125e5bf435dbcf6d7e', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1368', 'a1f29c1364c1f1d90865bf125bc12538bf1e31ef1955a53a405e9c9c0701c0cb', 'Patellofemoral joint chondral pain', 'subtype_patellofemoral_joint_chondral_pain_63e8d81e49', 'dx_patellofemoral_injury_a6e2fe370a', 'Patellofemoral injury', 'accepted_deterministic'),
  ('1371', '80b9b9502360c367734862d9a2e699978aec1ad3c132e69223c8e2370575a7cb', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('1372', 'db425358df383a71e5b6ab0675faeccea490cadb451ae20bf198ee8dd0f93ad9', 'Medial gastrocnemius trigger points or spasm', 'subtype_medial_gastrocnemius_trigger_points_or_spasm_d58836dc7f', 'dx_gastrocnemius_trigger_points_spasm_0e2bdaca3b', 'Gastrocnemius trigger points/spasm', 'accepted_deterministic'),
  ('1373', '0ca183da77a129c36f20e4e9e0c0124fac61786d157fcb769cd6be7f8b848d38', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1374', 'a6ad0693cf80c96832a02fb0491c553a48eaa202f454b47abbd2a814fcf85430', 'Calcaneal bursitis (pump bump)', 'subtype_calcaneal_bursitis_pump_bump_ddfe297857', 'dx_heel_bursitis_d80d084f22', 'Heel bursitis', 'accepted_deterministic'),
  ('1375', '2fce31a987b48011a2777cff8efc27d4acf03781a9a941f17bee6cd073824714', 'Thoracic facet joint sprain', 'subtype_thoracic_facet_joint_sprain_205cac3c00', 'dx_thoracic_facet_joint_disorder_519c2ae5a8', 'Thoracic facet joint disorder', 'accepted_deterministic'),
  ('1376', '2795a6cd9b7ce07bd2bca9523a50ac1ded72a612e7102b80b0ae84ccd494c8f4', 'Thoracic facet joint sprain', 'subtype_thoracic_facet_joint_sprain_205cac3c00', 'dx_thoracic_facet_joint_disorder_519c2ae5a8', 'Thoracic facet joint disorder', 'accepted_deterministic'),
  ('1377', '3a948c457ffa7bbafa38f1b8f22eec191ecbfc1650fc3003a320b7ad0693f0c2', 'Costovertebral joint sprains', 'subtype_costovertebral_joint_sprains_7b33a39da8', 'dx_costovertebral_joint_sprain_f6582e1466', 'Costovertebral joint sprain', 'accepted_deterministic'),
  ('1378', '31bff4f656c06ef6caf0c99c10bc63625afe4c88142170f8ff4548c810b285bf', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('1379', '81a38d073371ac0d2c7af9bf96f28b36966b80b3d4e469ef384860f038cd94ad', 'Gluteal muscle trigger points', 'subtype_gluteal_muscle_trigger_points_0dc668ef54', 'dx_gluteal_muscle_trigger_points_0dc668ef54', 'Gluteal muscle trigger points', 'identity_group'),
  ('1380', '5e0e5eee64a00268b07ad3c27149a6fed54fab78504bca33321be2e57b885e78', 'Finger extensor tendon injury (incl mallet finger +/- avulsion fracture distal phalanx)', 'subtype_finger_extensor_tendon_injury_incl_mallet_finger_avulsion_fracture_distal_phalanx_62e86d0854', 'dx_finger_extensor_tendon_injury_mallet_finger_36d86ff004', 'Finger extensor tendon injury/mallet finger', 'accepted_deterministic'),
  ('1381', '4ca1851dc73ae3f87f4da1576af024378067847572b0c9792d980b9bf8c5b976', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1382', 'd4e9b97d7282a371c5bf14d394a6558a21605557810337731e20e3b6ed2e6274', 'Chronic lumbar functional pain', 'subtype_chronic_lumbar_functional_pain_f5137cab5d', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('1383', '6b1cd8fee3576f58e3a13cfcbcc646922e86c134745fd4efbb2cdf2928d39916', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1384', 'bc3964e160619c1c20f7dea5425c9171a7665c4d3e478659a709ca348767f114', 'Distal quadricep haematoma', 'subtype_distal_quadricep_haematoma_01c745cc46', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1385', '2ee4d78a3f33d75fe825154e337f51a38e84cf6613d5e515cfde7100e6d80663', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1386', '4845f3126d3d9a12e6f0e36c0bcfdc11347e7d27339237f915bd7ae0c83093ff', 'Thoracic Muscle Strain/Spasm/Trigger Points', 'subtype_thoracic_muscle_strain_spasm_trigger_points_c483ca1853', 'dx_thoracic_muscle_strain_spasm_trigger_points_c483ca1853', 'Thoracic Muscle Strain/Spasm/Trigger Points', 'identity_group'),
  ('1388', '64f0fc9fe3c7985041a8a14236e9be3a61dc3aff36df1f216de2d46293ecfb95', 'Hip Joint Chondral/Osteochondral Injury', 'subtype_hip_joint_chondral_osteochondral_injury_d9e18fdeff', 'dx_hip_cartilage_injury_59a16f2a24', 'Hip cartilage injury', 'accepted_deterministic'),
  ('1390', '6b8defe694f53375a855ea59c6ad40d2a80aaf0149b07d9bf7650a2672900272', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1391', '14bccef4551e9a4490811ee56df0eba19ccb315b5c4f4511bb38c7ba6d72808e', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1392', 'bbe017714111af04c328f91f2796a804f598e604a927203bb916f5a4da3a63b6', 'Calf muscle cramps/spasm', 'subtype_calf_muscle_cramps_spasm_7890832741', 'dx_calf_cramp_spasm_950b710fbb', 'Calf cramp/spasm', 'accepted_deterministic'),
  ('1393', '0e971513e63f3835a7455eb0a5cea417a7fd8e6d932d2b0bfd078960b773145e', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('1394', '5ad8ce9796a66eaebe287683e4fcddec3a05a0db176e93c4d928da04309774f5', 'Sprained toe/''turf toe''', 'subtype_sprained_toe_turf_toe_8130fe4d55', 'dx_great_toe_injury_71c02ad835', 'Great toe injury', 'accepted_deterministic'),
  ('1395', 'c000c7c60ad9228dd43e7da70de3d0895a31a55256fa0748383bd4b685a5e0cb', 'Knee Pain/Injury Not otherwise specified', 'subtype_knee_pain_injury_not_otherwise_specified_f2690253b3', 'dx_knee_pain_609ce718bc', 'Knee pain', 'accepted_deterministic'),
  ('1396', '7af2a5ee1d054068519251c07244e7d9a35b62b6fe640e59285d293a90a26249', 'Back referred hamstring tightness', 'subtype_back_referred_hamstring_tightness_6fbd78d98a', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'accepted_deterministic'),
  ('1397', '44e3fa824958a49f54ade79033fb03a08f65f559fc70c9701460ca773e0fcb3e', 'Groin soreness or trigger points', 'subtype_groin_soreness_or_trigger_points_70c27347b8', 'dx_groin_soreness_or_trigger_points_70c27347b8', 'Groin soreness or trigger points', 'identity_group'),
  ('1398', 'ebfcf5e79e0280b3d7c076ddc97c6b8081b399c07d499b85b0e7039f3b2b6a50', 'Acromioclavicular (A/C) joint sprain', 'subtype_acromioclavicular_a_c_joint_sprain_75f6a9a659', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1400', 'c15cfe81b8cca41012d107cd02e7dc7f33a72ff7e9cfb380ec9ad9c42e9d1aa7', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('1402', '64bb43ee8966d372f0203a4112ebf57b0fd56e53fe5ff38dbc9b74ec97aada75', 'Peroneal Haematoma', 'subtype_peroneal_haematoma_3a4c507ede', 'dx_peroneal_injury_b0c8606ad2', 'Peroneal injury', 'accepted_deterministic'),
  ('1403', '2b2e0c236d59213c1c25ae6fd3e8385223e580e26162a1b6787449c831b69f93', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1404', '7bfc307b80b20243c8bc9ebeb476c0f8219de49f1aa58b3b9484ef1930ce2d98', 'Bruised ribs/chest wall', 'subtype_bruised_ribs_chest_wall_0c223ac8bd', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('1406', 'b7d0464cf1ec4024426b5d63bb02b9d18ce4977febff8c6fddf8bad68150b25d', 'Plantar heel pain (fasciitis/strain/calcaneal spur)', 'subtype_plantar_heel_pain_fasciitis_strain_calcaneal_spur_7ea3631a44', 'dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b', 'Plantar heel pain/fasciopathy', 'accepted_deterministic'),
  ('1407', '7f36bc1838bffb4567803c6e4d3d2cf495b5669f17d43531d68bf67b189a4eb8', 'Midfoot joint/ligament sprain (incl Lisfranc)', 'subtype_midfoot_joint_ligament_sprain_incl_lisfranc_282c947645', 'dx_midfoot_injury_3332895405', 'Midfoot injury', 'accepted_deterministic'),
  ('1408', '491f23eae6b70cc13f040000566d9dc967787fffa2232ee7703a43f17121eaf0', 'Medial Tibial Stress Syndrome (''shin splints'')', 'subtype_medial_tibial_stress_syndrome_shin_splints_95e1a13bce', 'dx_medial_tibial_stress_syndrome_shin_splints_651f7c8df6', 'Medial tibial stress syndrome/shin splints', 'accepted_deterministic'),
  ('1409', '4d216c09321df132682fbc0e0bed379e008156e578b3b14c398a0077214be390', 'Knee pain undiagnosed', 'subtype_knee_pain_undiagnosed_cd27746a95', 'dx_knee_pain_609ce718bc', 'Knee pain', 'accepted_deterministic'),
  ('1410', '74353f2f5b5fa3f0c98c237a495bcb02b1b3293c35e2a1554b25785ab283c479', 'Adductor magnus strain', 'subtype_adductor_magnus_strain_46f3060b06', 'dx_adductor_muscle_injury_97164c9b14', 'Adductor muscle injury', 'accepted_deterministic'),
  ('1411', '79cd222dcd3ea586a44e8a2f0e3626137168509feed3b645f120cb0e0bdc2a99', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1413', '4bf133d3e2d0df219469c0105e47323ca3c534b26c2e92f54e1400ef4b6d6d1b', 'Proximal adductor trigger points', 'subtype_proximal_adductor_trigger_points_e0737a9324', 'dx_proximal_adductor_trigger_points_e0737a9324', 'Proximal adductor trigger points', 'identity_group'),
  ('1414', 'b16880394403cc2ea6317c9dffd55f3ddab8ff9d864a0e7e23d28400466d8210', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('1415', '11c83b41036ff4c51c3622b00f02490fefa94fb0ca539db82a1456d54dc32b4c', 'PIP joint dislocation little finger', 'subtype_pip_joint_dislocation_little_finger_e9c08ade1f', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'accepted_deterministic'),
  ('1416', '8ead388807397990c2bc5424f600b64452023771d4d1c594a2f784bada5a33e4', 'Acute Concussion with visual symptoms', 'subtype_acute_concussion_with_visual_symptoms_b0614b3e2b', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1417', '933a4d7535a1aa181f62eca1effd3073c12deeceaeabac9e0588480211294688', 'Chronic lumbar functional pain', 'subtype_chronic_lumbar_functional_pain_f5137cab5d', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('1418', 'b2765b15abc2abbf77964829c6da091086f3b6986344d1dfbc7ca852372825b6', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1419', '719e58be40a74d5ca0584c77291a5355d0c300bb2e01177127dbb5e79cbe0ce2', 'Grade 3 A/C joint dislocation', 'subtype_grade_3_a_c_joint_dislocation_89188eec71', 'dx_acromioclavicular_joint_dislocation_8954e719a9', 'Acromioclavicular joint dislocation', 'accepted_deterministic'),
  ('1420', '7aff7602dc23dde088c11ea2a7ce67fe26948f2360113d49c6915ce38a141552', 'Ankle multiple ligaments sprain', 'subtype_ankle_multiple_ligaments_sprain_7b65bb0881', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('1421', '26d90ddbb5d6db9ac59b4b366c6be08b3630d065c15758af2af4187d55116428', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1422', '8ea00d9cb91be863d6363306f693e7dedbb887375c24f67e495e414b94da2f18', 'Acromioclavicular (A/C) joint sprain', 'subtype_acromioclavicular_a_c_joint_sprain_75f6a9a659', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1423', 'a8ff194475403beedc6e4c5290812f9faf27a849c637e0523fd602fe34ef2af8', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('1424', 'ae4e8dec246b8f4f6cc3ad12d343993827f99b9c88449d6c0b9b72605d8c55b4', 'Back referred hamstring tightness', 'subtype_back_referred_hamstring_tightness_6fbd78d98a', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'accepted_deterministic'),
  ('1425', '660f87a18fdd0165cb527516167a524c924a847cbaabcbde44b6a69f24a79cfd', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('1429', '2c999c7a5dec3e598aaf2a8c8f9ab6bf458911d217f9c751886677313ef90857', 'Cervical nerve root compression/stretch', 'subtype_cervical_nerve_root_compression_stretch_6f650f0242', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('1430', '45ecc61f03a9bef692a9f4ef6a8314568d4f09cdb18cf31b779cb71d12365245', 'Sprained toe/''turf toe''', 'subtype_sprained_toe_turf_toe_8130fe4d55', 'dx_great_toe_injury_71c02ad835', 'Great toe injury', 'accepted_deterministic'),
  ('1432', '0efc774b693dd1b47ca61b693db24def62e05b35d8c9bf64a10afe9b9570b98d', 'Cervical functional pain', 'subtype_cervical_functional_pain_e11c275770', 'dx_cervical_functional_pain_e11c275770', 'Cervical functional pain', 'accepted_deterministic'),
  ('1433', 'd9bb924adbac9cf13850859137d2dd1314779d6f47e3a0b7402a2da8395f36cc', 'Proximal adductor trigger points', 'subtype_proximal_adductor_trigger_points_e0737a9324', 'dx_proximal_adductor_trigger_points_e0737a9324', 'Proximal adductor trigger points', 'identity_group'),
  ('1435', '2ee36390addb6612cbd37263ad1796a703208493c2e13f0aa6b9842cb3301d51', 'Cervical Spine Instability', 'subtype_cervical_spine_instability_87f1adf4cc', 'dx_cervical_spine_instability_658367d444', 'Cervical spine instability', 'accepted_deterministic'),
  ('1436', '0035c0c923155ab385225cadd466070b2fe98055ea12d65644cc65b4c2ccb4f9', 'Sprained toe/''turf toe''', 'subtype_sprained_toe_turf_toe_8130fe4d55', 'dx_great_toe_injury_71c02ad835', 'Great toe injury', 'accepted_deterministic'),
  ('1437', '85117d016c72ce5505783eb54e22ca9096896aff2de5522069b6c9d1325fec13', 'Hip Joint Inflammation/Synovitis/Other Biomechanical Lesion', 'subtype_hip_joint_inflammation_synovitis_other_biomechanical_lesion_b7683e426f', 'dx_hip_joint_injury_07aa18de20', 'Hip joint injury', 'accepted_deterministic'),
  ('1438', '2c684f938e0c0b1fcb38051d028fd2bb557b82b2f95e77c4feb0adc97e4def6c', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('1439', '5caed8715479104f5eecfcff52ca370e4942cf95ebb3d9c5cb59dcd08376c6ac', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1440', 'd647048b96b1448cd09a0e130e10664745f8f319ddd91897cf34bf34671b140e', 'Heel bruising/haematoma incl fat pad contusion', 'subtype_heel_bruising_haematoma_incl_fat_pad_contusion_c73ea914d5', 'dx_heel_contusion_4009d671bf', 'Heel contusion', 'accepted_deterministic'),
  ('1441', 'ff7742a6c645c06ef44640f40c4428bc49436f41d6d6daff443006874742208c', 'Sprained toe/''turf toe''', 'subtype_sprained_toe_turf_toe_8130fe4d55', 'dx_great_toe_injury_71c02ad835', 'Great toe injury', 'accepted_deterministic'),
  ('1442', '420149ea1be1399d499a8ce9af5c72c70a93df49d855f213ea72893b395fc477', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('1443', '9dc666a07f4790055005b5b00eb04a3eb441261871e59febc97418e11e34976e', 'Glenohumeral joint sprains', 'subtype_glenohumeral_joint_sprains_0aefa97c55', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('1444', '63c227c30ef5f3de8670a80ae7612314996a9d0a239299dd1f0925fee3a54bf4', 'Posterolateral corner and LCL ligament injuries knee', 'subtype_posterolateral_corner_and_lcl_ligament_injuries_knee_35a23d3afe', 'dx_knee_posterolateral_corner_injury_a4c4c64579', 'Knee posterolateral corner injury', 'accepted_deterministic'),
  ('1445', '999d9023044f0b488ee78f32f031993f18451fdfa9551c79b92bdae2b768f0f1', 'Inferior tibiofibular syndesmosis sprain', 'subtype_inferior_tibiofibular_syndesmosis_sprain_0545fce188', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'accepted_deterministic'),
  ('1446', 'd3fec14f71b3e7c29c60eddbecd1067123b01544de74b2a46f41b35f43254aae', 'Back referred hamstring tightness', 'subtype_back_referred_hamstring_tightness_6fbd78d98a', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'accepted_deterministic'),
  ('1447', 'c85a574d2c23c4948b05a34f5ff1ad684cbef710c92df1aa8ef1db7ee456af26', 'Adductor origin tendinopathy', 'subtype_adductor_origin_tendinopathy_75ee0d21d5', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'accepted_deterministic'),
  ('1450', 'ec0539ba490484dd2152266c3a206a77c09010acb647bde5b5ec4455c38dbdbb', 'Fractured ulna midshaft', 'subtype_fractured_ulna_midshaft_3e716cf076', 'dx_ulnar_shaft_fracture_8603134cce', 'Ulnar shaft fracture', 'accepted_deterministic'),
  ('1451', 'e1dd3ef0094506f0c8b234d1fa21caf51dadb7c4cf2b6bbf025dd81b10f02493', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1455', 'f1a48d1b89e4443b1d4cdc337cb4ac93e960eb865134120fff0f4730b0a20abe', 'Patellar tendinopathy', 'subtype_patellar_tendinopathy_3ea4d4d1bf', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'accepted_deterministic'),
  ('1456', 'b4b35047f549e33bfae900207b6451aed1e7ae1725db9ebcb635cedf6dbdfaea', 'Back referred hamstring tightness', 'subtype_back_referred_hamstring_tightness_6fbd78d98a', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'accepted_deterministic'),
  ('1457', '2575d175cc835d245132065c32eff39e0e0958d48066efad233169e5cf3be10d', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('1458', '8a8424d718a2459d5452503591a422b5405b77960c793ce9605e854b2dfd1cd8', 'Wrist fibrocartilage tear', 'subtype_wrist_fibrocartilage_tear_aead44491e', 'dx_wrist_fibrocartilage_injury_fddc60c8f6', 'Wrist fibrocartilage injury', 'accepted_deterministic'),
  ('1459', '64e8caf55809d716ab6d9260dbd92d34ed0b924bd942b6e0a6765b3338eb8768', 'Knee Pain/Injury Not otherwise specified', 'subtype_knee_pain_injury_not_otherwise_specified_f2690253b3', 'dx_knee_pain_609ce718bc', 'Knee pain', 'accepted_deterministic'),
  ('1460', '452820e84407b217c58fd04606e573dab75bebbdf9f527e7db4e3eabbec3a468', 'Fracture 3rd metacarpal', 'subtype_fracture_3rd_metacarpal_e6bbb1583a', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture', 'accepted_deterministic'),
  ('1461', '7354c700fc70e83f56137f29222d025e614cefd8240a94f6392d6b411c6573d1', 'Sesamoid stress injury', 'subtype_sesamoid_stress_injury_5eb1bfd18a', 'dx_foot_bone_stress_injury_unspecified_872bcaf23e', 'Foot bone stress injury, unspecified', 'accepted_deterministic'),
  ('1462', '8486e06ecfb9e31caa8ec1745e6f240c3e1948c4ce82006418419c27d85dc980', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('1464', '654c3279bf84c61260bde3568af7661ca1ea98e4939e78d9c85e87423f3522e2', 'Hamstring cramping during exercise', 'subtype_hamstring_cramping_during_exercise_2eb7c1414b', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm', 'accepted_deterministic'),
  ('1465', '761a9de16c5f5e20efd654399b04493895c66bde641ead5ca8f483dad0d6222b', 'Lumbar Spine Joint Injury', 'subtype_lumbar_spine_joint_injury_2217f317ac', 'dx_lumbar_spine_injury_27c07f4f95', 'Lumbar spine injury', 'accepted_deterministic'),
  ('1466', '76fa18092b26a6c01fab56a8f2011432c3dd795d382794319ea4bc0d51127eb6', 'Other Stress/Overuse Injury Hip and Groin', 'subtype_other_stress_overuse_injury_hip_and_groin_a42c390491', 'dx_hip_and_groin_overuse_injury_71c787dc38', 'Hip and groin overuse injury', 'accepted_deterministic'),
  ('1467', '4815793befc67933e39adf57630c7b765a82e80fa7ef02fe78456ecb487dae76', 'Shin contusion', 'subtype_shin_contusion_5ea21c3f50', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('1468', '8891928dc07a045a258e5ad2a1dd979fd33d96e0cac6dd480f1dc775f8f77cdd', 'Adductor longus strain', 'subtype_adductor_longus_strain_dd1eac51f6', 'dx_adductor_muscle_injury_97164c9b14', 'Adductor muscle injury', 'accepted_deterministic'),
  ('1469', '090462c4e6b5240c7ce412209acf7146bab50baf2c6e5cc830ae5ca9cec0dfe5', 'Posterior cruciate ligament (PCL) injury', 'subtype_posterior_cruciate_ligament_pcl_injury_fbe6c1cd7d', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury', 'accepted_deterministic'),
  ('1470', '98e70021bea26c6f1c70b5727054104fd2c3343d097ab8bbecfad74f456cfec0', 'Sprained toe/''turf toe''', 'subtype_sprained_toe_turf_toe_8130fe4d55', 'dx_great_toe_injury_71c02ad835', 'Great toe injury', 'accepted_deterministic'),
  ('1471', 'eaddf710740374f74d4705eb79e9a3a25f433ed65d6f4413b0578b19b4284289', 'Back referred hamstring tightness', 'subtype_back_referred_hamstring_tightness_6fbd78d98a', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'accepted_deterministic'),
  ('1472', '7d7a286db8f521927cf7760c6ebb9141ac8b6a8a78f9aadb7a00ff65ce7519ed', 'Heel bruising/haematoma incl fat pad contusion', 'subtype_heel_bruising_haematoma_incl_fat_pad_contusion_c73ea914d5', 'dx_heel_contusion_4009d671bf', 'Heel contusion', 'accepted_deterministic'),
  ('1474', '08a40f20bc071634d1d024395d67724a1a3a2aa69f9c30d4fa001a65cd2affb9', 'Elbow posterior impingement/synovitis', 'subtype_elbow_posterior_impingement_synovitis_dcda290ac8', 'dx_posterior_elbow_impingement_9844ae2f8c', 'Posterior elbow impingement', 'accepted_deterministic'),
  ('1475', '092a2cfec1aad557c01650e400ae1fdb31342b426d6d3439cb8c15cd89673af7', 'Sprained ulnar collateral ligament (Skier''s) thumb', 'subtype_sprained_ulnar_collateral_ligament_skier_s_thumb_9625d9031b', 'dx_thumb_ucl_injury_00b846b6dd', 'Thumb UCL injury', 'accepted_deterministic'),
  ('1476', 'e5fa4121d25e02caceacea443eb4c26ccf1aab9be9c656805d1559635bbc8801', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('1478', 'b068020c1a2a0ef313b507b60b7cf54d1deeaf64267d8cfc6f58d2c7eddca4e4', 'Thoracic facet joint sprain', 'subtype_thoracic_facet_joint_sprain_205cac3c00', 'dx_thoracic_facet_joint_disorder_519c2ae5a8', 'Thoracic facet joint disorder', 'accepted_deterministic'),
  ('1480', 'd0271e621e3cd6663124b0f8b732a052a198b19b00da1edc86ebb0783f0886c9', 'Cervical disc Injury', 'subtype_cervical_disc_injury_13c8608a7d', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury', 'accepted_deterministic'),
  ('1482', 'd4371a960689ec2ba65a70fa451c5ae0be8b592c6c24b1edf54a5c39430226ef', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('1483', '291b2d0f77ef0250db1e22c205d2231d7f56be043408797e98467d70bad37a0f', 'Cervical Spine Instability', 'subtype_cervical_spine_instability_87f1adf4cc', 'dx_cervical_spine_instability_658367d444', 'Cervical spine instability', 'accepted_deterministic'),
  ('1484', '4ba400937d6d5a23b39167fb1318be451099e4df26f0c1b47e6eb66e8b242fd2', 'Elbow ulna/medial collateral ligament (UCL) strain or tear', 'subtype_elbow_ulna_medial_collateral_ligament_ucl_strain_or_tear_ab4c438f84', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury', 'accepted_deterministic'),
  ('1485', '1fb7f8894d0dcd7a6286ae42cfe911e2379bf522e89f0d95122754de980176cb', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1486', '6d5484a5d7853373736d846ff60bb56c7ce7efc865cccac7f45b5eb8e67f6b0c', 'Scapholunate ligament sprain', 'subtype_scapholunate_ligament_sprain_4db8cb13f7', 'dx_wrist_ligament_injury_6b21f37d24', 'Wrist ligament injury', 'accepted_deterministic'),
  ('1487', 'd622f8ab810f005aa74d42471844a2ed960be0a6a5262874570d27c26931aec6', 'Acromioclavicular (A/C) joint sprain', 'subtype_acromioclavicular_a_c_joint_sprain_75f6a9a659', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1488', 'f75f79ea01e30991275e8baf4ea2a6f8e1f4a870770bcf71127b2e3e9c3b0b24', 'Chronic lumbar functional pain', 'subtype_chronic_lumbar_functional_pain_f5137cab5d', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('1490', 'e183e02986b72b9f4a6a547fb33d55c06444e35656a77ae06e7824de042f11dc', 'Lateral hamstring trigger points', 'subtype_lateral_hamstring_trigger_points_ea90bfdf92', 'dx_lateral_hamstring_trigger_points_ea90bfdf92', 'Lateral hamstring trigger points', 'identity_group'),
  ('1491', '614541aad8375c607b84b15dc062d7190e4ceedc829ca98ff89bfc9d3dcff604', 'Lateral hamstring trigger points', 'subtype_lateral_hamstring_trigger_points_ea90bfdf92', 'dx_lateral_hamstring_trigger_points_ea90bfdf92', 'Lateral hamstring trigger points', 'identity_group'),
  ('1492', 'bc8946bf89ec1f0ed87047f7af4c18e30a306d3f1a15c4e9bdf299da1a1facd6', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1493', 'db0f9f5d7a68387a3d5c79b1bf9f8b5d6a9ffaf86b823c62ba08afdc17776cf2', 'Quadriceps strain or tear', 'subtype_quadriceps_strain_or_tear_17ff226482', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1494', 'a9bf41a3f11010af4036665212a4bb0edc4bb58c03706ca7c1902192c9b9cd34', 'Gluteus maximus strain', 'subtype_gluteus_maximus_strain_5f32db98a3', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury', 'accepted_deterministic'),
  ('1495', '6f1e0f4bd63f09d28febb1b25636ab5ed5f253bc620d2fb0d0bdfecfb3bf52d0', 'Grade 2 A/C joint sprain', 'subtype_grade_2_a_c_joint_sprain_ae2ea1925b', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1496', 'f9ba7fc1fd170e855ff9e2e879f9f99af0867e477a174797139bcb913874170c', 'Bennett''s fracture/dislocation thumb', 'subtype_bennett_s_fracture_dislocation_thumb_3a25210b48', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture', 'accepted_deterministic'),
  ('1497', 'c1e1ceaf089430c9fe5f21c3d4121173cd95e6d798a372a6d1a22f06b30a1fa4', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('1513', '17e4af41a2dc931d04378a8ca768f02fd0f5f325bf4a12b8af77b85d671cde36', 'Distal adductor strain', 'subtype_distal_adductor_strain_9d4ad9b5e9', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'accepted_deterministic'),
  ('1517', 'a2a054bf56d627a81e09cfbe6a677c957cba2844aa8ffa0477b28ce4a3801a4f', 'Gastrocnemius muscle injury or strain', 'subtype_gastrocnemius_muscle_injury_or_strain_367914bc2d', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'accepted_deterministic'),
  ('1518', 'a73b5ad525476d09df11ff86c429f6fba78e6af7f8ad58236f63cb1cd0da57f5', 'Anterior talofibular and calcaneofibular ligament sprain', 'subtype_anterior_talofibular_and_calcaneofibular_ligament_sprain_b3a64a632d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('1519', 'f94a545e5abf287c612190d03d2d0d2ce38cbd38049bab8644b7043824165068', 'Posterior shoulder dislocation with posterior labral lesion', 'subtype_posterior_shoulder_dislocation_with_posterior_labral_lesion_1df5d6f867', 'dx_shoulder_dislocation_2067688fdd', 'Shoulder dislocation', 'accepted_deterministic'),
  ('1520', '8c6c70c0ba345ed6f34518faf9ae068ce14c7da00fc12259f301c223f777b713', 'Anterior talofibular and calcaneofibular ligament sprain', 'subtype_anterior_talofibular_and_calcaneofibular_ligament_sprain_b3a64a632d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('1521', 'c9e580eb9403dea221440e3b223379b5609e3916f369e90a0a38e84dba0a10c4', 'Sprained toe/''turf toe''', 'subtype_sprained_toe_turf_toe_8130fe4d55', 'dx_great_toe_injury_71c02ad835', 'Great toe injury', 'accepted_deterministic'),
  ('1522', '68ee7f5aff4206ba16b7b94d438c584f5a679b767adb2b7ff0137c3a74e739fa', 'Sprained toe/''turf toe''', 'subtype_sprained_toe_turf_toe_8130fe4d55', 'dx_great_toe_injury_71c02ad835', 'Great toe injury', 'accepted_deterministic'),
  ('1523', '6f9707bb7a4175963c217b87961d55acbd786fbab46da8d01e56e7fff98d7284', 'Gluteus medius/minimus strain', 'subtype_gluteus_medius_minimus_strain_d87e368e47', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury', 'accepted_deterministic'),
  ('1524', 'd69dc134b5a49103c2c982c02740476062c2ec7d523cd4f08f664f247fb1dff7', 'Gluteus medius/minimus strain', 'subtype_gluteus_medius_minimus_strain_d87e368e47', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury', 'accepted_deterministic'),
  ('1526', 'f1239ef44b73d56f9abd7d4ef01e498dd30dc710699c34aaa188122370fbbfa7', 'Indirect inguinal hernia', 'subtype_indirect_inguinal_hernia_103c299479', 'dx_inguinal_hernia_b37371f06e', 'Inguinal hernia', 'accepted_deterministic'),
  ('1527', '859b434e954f31d9ee2cd184b2d3ee968d069459bdd34082fe87dc661498a20f', 'Lumbar Spine Facet Joint Pain/ Stiffness', 'subtype_lumbar_spine_facet_joint_pain_stiffness_053a763145', 'dx_lumbar_facet_joint_disorder_4a13830647', 'Lumbar facet joint disorder', 'accepted_deterministic'),
  ('1528', '6ec0c861d0ac7d2b52ea853ec93d4f4edd60da8d16a47a1a4ae3f1a0a8e3d81e', 'Lumbar contusion/haematoma', 'subtype_lumbar_contusion_haematoma_ae89cb3e74', 'dx_lumbar_soft_tissue_contusion_125139d685', 'Lumbar soft tissue contusion', 'accepted_deterministic'),
  ('1529', '03bf044089e69e732ac7f1428b613ec6f9bd9350edd7f37a20b1c2a6c731406c', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1532', '8bb238972bab5d4cfae7c99e24a0e5160d802eb115a9a9c6bb631c333f274ca6', 'Sportsman''s hernia', 'subtype_sportsman_s_hernia_c9eeb6b61d', 'dx_sports_hernia_ad99f8552f', 'Sports hernia', 'accepted_deterministic'),
  ('1535', 'eab1c6d396ddc8192929caecc8fd59714907c24ec7a358b024d4b69747982893', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1536', '7fb0c2b98cce9c0cbb809aad779e902fecc078e65e347eaa276c495f0721fc9d', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1537', '85dbfbd49e5aa080cad3e3db2ebf338b7985ae4f2d59b1b6823d347982bcbbff', 'Sprained toe/''turf toe''', 'subtype_sprained_toe_turf_toe_8130fe4d55', 'dx_great_toe_injury_71c02ad835', 'Great toe injury', 'accepted_deterministic'),
  ('1538', '3abdeb65eec2a4c456a3e456d5ed778f8111b48cfe33eb990c5688b5c1ebb62c', 'Adductor magnus strain', 'subtype_adductor_magnus_strain_46f3060b06', 'dx_adductor_muscle_injury_97164c9b14', 'Adductor muscle injury', 'accepted_deterministic'),
  ('1539', 'a9d3187227a0a207177bff5e85c3d626fd61897789d4e72d982f7e63d76310ab', 'Supraspinatus tendon injury', 'subtype_supraspinatus_tendon_injury_3840a1f333', 'dx_supraspinatus_tendon_injury_3840a1f333', 'Supraspinatus tendon injury', 'accepted_deterministic'),
  ('1540', '89054ae1330f3feac56bcf8d715687d9700ec0610967cade3d67378805fb09d9', 'Dislocated metacarpophalangeal or interphalangeal joint', 'subtype_dislocated_metacarpophalangeal_or_interphalangeal_joint_7acd7fd43f', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'accepted_deterministic'),
  ('1541', 'dd7d3f9985ce0d346013028b7cdbab9c9612669e53172c354cd00ddc6379ae91', 'Facet Joint/Neck Ligament sprain', 'subtype_facet_joint_neck_ligament_sprain_369f0afd14', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder', 'accepted_deterministic'),
  ('1542', 'fd7427aad72795aa81f5f5bdd309aa245a553ace115f6f4d8d5df0554d4fed82', 'Lisfranc dislocation', 'subtype_lisfranc_dislocation_ebd876cf9e', 'dx_lisfranc_injury_a82b5577c5', 'Lisfranc injury', 'accepted_deterministic'),
  ('1544', '52badd40871aeb8480e1246adef82831a04f21ec048dda8b12a02e5448d2fa18', 'Knee osteoarthritis (O/A)', 'subtype_knee_osteoarthritis_o_a_139fc2f12b', 'dx_knee_osteoarthritis_088b6b8911', 'Knee osteoarthritis', 'accepted_deterministic'),
  ('1549', '2f679a69c66b1b702e6b2558f877dea7b2e2ad820521cb8695d043b49ce7a8ed', 'Gastrocnemius muscle injury or strain', 'subtype_gastrocnemius_muscle_injury_or_strain_367914bc2d', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'accepted_deterministic'),
  ('1552', '7e8136c31629792c356e622eff3496d3b08656c11550169ac403a41e1a8e5f01', 'Lumbar pain non-specific', 'subtype_lumbar_pain_non_specific_29a75fb1e1', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('1556', 'd01737132bac7a03b22f92eace4f840eb627504fffcac10e1ed3d17f2fd0701b', 'Anterior talofibular and calcaneofibular ligament sprain', 'subtype_anterior_talofibular_and_calcaneofibular_ligament_sprain_b3a64a632d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('1557', '1a8ecb9b03671378a8a1e884dfcc699ad75316cad4e0fab4f3f2e0f83c2b3352', 'Sportsman''s hernia', 'subtype_sportsman_s_hernia_c9eeb6b61d', 'dx_sports_hernia_ad99f8552f', 'Sports hernia', 'accepted_deterministic'),
  ('1558', 'cf9dbee7c6fb41ede7adef235121ed31c08ac274508d9e0e71982359367f780a', 'Sprained toe/''turf toe''', 'subtype_sprained_toe_turf_toe_8130fe4d55', 'dx_great_toe_injury_71c02ad835', 'Great toe injury', 'accepted_deterministic'),
  ('1559', '9bd5979311bf00bf7791f9df777695712758a51e0b8c5395371d63342cc70828', 'Conjunctival haematoma', 'subtype_conjunctival_haematoma_d0548fcc2a', 'dx_conjunctival_haematoma_d0548fcc2a', 'Conjunctival haematoma', 'accepted_deterministic'),
  ('1560', '67c43e6eb9fb2e5ed7c0a59a114a537e6eb077e1a481cb2e13f7cd01f34b7f62', 'ACL rupture', 'subtype_acl_rupture_f84927fab2', 'dx_acl_injury_4b8eb47e96', 'ACL injury', 'accepted_deterministic'),
  ('1562', 'e7e707ed32db03ff9b876edf245b49f6dd531e83185344fe3d2df53cdbc91ac0', 'Metacarpophalangeal joint sprain', 'subtype_metacarpophalangeal_joint_sprain_103ce7f526', 'dx_finger_mcp_injury_6c586feb13', 'Finger MCP injury', 'accepted_deterministic'),
  ('1564', '16a8a28b4482665041ea373466ce1c96c719147b1ad1f4529d596c7ee718fc91', 'Sprain medial collateral (deltoid) ligament ankle', 'subtype_sprain_medial_collateral_deltoid_ligament_ankle_ba23692ed8', 'dx_medial_ankle_ligament_injury_9add2aecee', 'Medial ankle ligament injury', 'accepted_deterministic'),
  ('1566', 'ea9cf5185a0f36d2a0464877c74e2d9c9f394cbaf1e4e055eeb848e7787edc03', 'Anterior talofibular and calcaneofibular ligament sprain', 'subtype_anterior_talofibular_and_calcaneofibular_ligament_sprain_b3a64a632d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('1567', 'f338aabba8df798b090973fa04705246656f73957098ca83b8f4677119026197', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1568', '67c15ab180bab074b48daa773c834a2442991a925f5d77e8af2609d7b5e177d6', 'Hip and Groin Muscle strain or tear', 'subtype_hip_and_groin_muscle_strain_or_tear_936dbed7ca', 'dx_hip_and_groin_muscle_injury_7ccd814142', 'Hip and groin muscle injury', 'accepted_deterministic'),
  ('1569', 'fbe11733612fa205ab2ba21bed3ef25f86ce4e376ce1f9bee94ffe5145001ab1', 'Disc degeneration', 'subtype_disc_degeneration_5b20c16579', 'dx_spinal_disc_degeneration_850a87dc5e', 'Spinal disc degeneration', 'accepted_deterministic'),
  ('1570', '236652a92e72d7cd5c1a5c58150af1fa8471f20c84ea71cd33901c3c0e2362e4', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1571', '33e49e3b3aeff4267525246c0b5ad09b0b42825ca42a3c561c958defc8fa9b36', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1572', 'e7d08997116fab4009839e8dcaa5d5357626ebbf43dd75d8be83f5b3f1c142e4', 'Lisfranc sprain', 'subtype_lisfranc_sprain_460169f63a', 'dx_lisfranc_injury_a82b5577c5', 'Lisfranc injury', 'accepted_deterministic'),
  ('1578', '4ce1188e48832630613e0a3d087c7282ab03bdcb3bc8be90db57dde8599abb10', 'Foot Joint Sprain', 'subtype_foot_joint_sprain_8ee641b736', 'dx_foot_joint_injury_28a178b0b5', 'Foot joint injury', 'accepted_deterministic'),
  ('1582', 'a364adc796458ca80494dcdb2a7a50e866385fa0a5d57b9ed5692bb8726dc813', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1585', '6c6f243e135f7ea186cd15f88bc769607135f20486e96ea203199f7c67af7fd8', 'Wrist or hand pain or injury, not otherwise specified', 'subtype_wrist_or_hand_pain_or_injury_not_otherwise_specified_9e1bbf83d9', 'dx_wrist_or_hand_pain_57c9958c78', 'Wrist or hand pain', 'accepted_deterministic'),
  ('1586', 'a368e123b1e94348bc56db0f6faea158ac7f47912aee38f28bfd59d4e5c61d3d', 'Distal quadricep haematoma', 'subtype_distal_quadricep_haematoma_01c745cc46', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1588', '9360482c8a7e304bfb0d982f340beef31fd3c5bd140e7d00517cbf5eb654c44e', 'Acute shoulder subluxation', 'subtype_acute_shoulder_subluxation_705b818f24', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('1599', '2e8b4eac014f87b22c0b62388c1d539b3223fda13d1e0558881178c88ad6906e', 'Cervical disc Injury', 'subtype_cervical_disc_injury_13c8608a7d', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury', 'accepted_deterministic'),
  ('1600', '7eb2238ec841aabc64b432162e4463e317977a5862ef3a7fc5a02c5601c9dadd', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1603', 'f14ea3ec120a9c0948009fff1d28d080f2bdc779b92b3daecf77be2a539431d8', 'Patellar tendinopathy', 'subtype_patellar_tendinopathy_3ea4d4d1bf', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'accepted_deterministic'),
  ('1604', '2cb30841834e8897b5288d056c6e30972e326fc135c20f644f6c0e28cfe29a02', 'Soleus Trigger points/Spasm', 'subtype_soleus_trigger_points_spasm_dfb83ed490', 'dx_soleus_trigger_points_spasm_56202bbe31', 'Soleus trigger points/spasm', 'accepted_deterministic'),
  ('1606', 'e015cfeb0338633463b9846f8d4ef6dceff6a3e078fec001250613f6ee22f742', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('1607', '009e32399b5d076d99281a4302e233bef194743110f823053e179302bcc08e94', 'Avulsed/fractured tooth', 'subtype_avulsed_fractured_tooth_d992bbc154', 'dx_dental_injury_b97b2afe75', 'Dental injury', 'accepted_deterministic'),
  ('1608', '2c18e921d919056cf81d3a9b2aa01d97eb1852573ef68b95b0945efa138d6fe2', 'A/C Joint instability/recurrent sprains', 'subtype_a_c_joint_instability_recurrent_sprains_ed3ae2521a', 'dx_acromioclavicular_joint_chronic_instability_299408db68', 'Acromioclavicular joint chronic instability', 'accepted_deterministic'),
  ('1609', 'e6b89df4b178f16a1c5df7b454a204089b36f949d05aa8d45d052df287237ee1', 'Bruised ribs/chest wall', 'subtype_bruised_ribs_chest_wall_0c223ac8bd', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('1610', 'cefafb5c3b7e87d5c4a0b3461a04bfe59d049301f835e69eeb209094068b8744', 'Elbow olecranon bursitis', 'subtype_elbow_olecranon_bursitis_ce5591cc2d', 'dx_elbow_bursitis_24fdbc7698', 'Elbow bursitis', 'accepted_deterministic'),
  ('1611', '9430e28386628ac6b4b6a78f3ba0ecf2e0b05f7ca95fc0828e800630de458435', 'Supraspinatus tendon tear partial thickness', 'subtype_supraspinatus_tendon_tear_partial_thickness_0843f7001c', 'dx_supraspinatus_tendon_injury_3840a1f333', 'Supraspinatus tendon injury', 'accepted_deterministic'),
  ('1612', 'e87d818377773e9a2f97c3f32f396addc43fa9d1247b403a1dcd1a13d5dd64c4', 'Rupture thumb extensor tendon (excl if complication of wrist fracture - see specific fracture)', 'subtype_rupture_thumb_extensor_tendon_excl_if_complication_of_wrist_fracture_see_specific_fracture_f114c9e214', 'dx_thumb_extensor_tendon_injury_e76a7cbccf', 'Thumb extensor tendon injury', 'accepted_deterministic'),
  ('1614', '009d7c1cca7d0a8b65cc48000dd94a905fd9ce0fe31de713e675bdb7cd9ff6da', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1615', '0078bb72f1f93bdc6ff2b1ccc6465871902e6b0a492ebd90e6b905d05973a809', 'Elbow UCL injury and common flexor origin tear', 'subtype_elbow_ucl_injury_and_common_flexor_origin_tear_447eb313bc', 'dx_elbow_ucl_injury_and_common_flexor_origin_tear_447eb313bc', 'Elbow UCL injury and common flexor origin tear', 'identity_group'),
  ('1616', '8db2a125c728b6bc451a19a70ee5efbf142786ebc1a9a3f9bafe6578d616316c', 'Distal radioulnar joint injury', 'subtype_distal_radioulnar_joint_injury_bd4d88a83d', 'dx_wrist_injury_d94414e2c6', 'Wrist injury', 'accepted_deterministic'),
  ('1617', 'd26c39574ac35b5ae0f3465c40ef522ef77d66e03e704bc13aa312b3b0de2759', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1619', '232d7cd3e7cb1532fd115d799d50c19c177f4458f203a45a12867e1e3940200e', 'Cervical disc Injury', 'subtype_cervical_disc_injury_13c8608a7d', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury', 'accepted_deterministic'),
  ('1620', '8fecde7c3ba9cb6b6b2e8b5e21d8cd5e207ca7952ef69e1c31019677f114b567', 'Forehead laceration requiring suturing', 'subtype_forehead_laceration_requiring_suturing_047b8262be', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('1621', 'bb1c4a1a9b864c7060e2e3f5801999f09ba8827284ad64587dd96650b1191afe', 'Cervical nerve root compression/stretch', 'subtype_cervical_nerve_root_compression_stretch_6f650f0242', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('1622', 'fdc86246b9d9877a2a023fa0d6180902f88e65259d0e65b557adfc0cafdb467a', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1623', 'e44cd8331939dad83b56fbc05ce45e3dbaafce3ccf275b44aa7128d2bc1e837b', 'Calf muscle cramps/spasm', 'subtype_calf_muscle_cramps_spasm_7890832741', 'dx_calf_cramp_spasm_950b710fbb', 'Calf cramp/spasm', 'accepted_deterministic'),
  ('1624', '7ee8ec70c6b47e4767d4b678d058134db00a6502a0a888ec89cd081f838b11e5', 'Adductor longus strain', 'subtype_adductor_longus_strain_dd1eac51f6', 'dx_adductor_muscle_injury_97164c9b14', 'Adductor muscle injury', 'accepted_deterministic'),
  ('1625', '1748d41f0a2ee94c8c9386f38a916229b9c371473a4cd6f545a8fcf5ca64f7b4', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1626', '53623aa3f547a73eae405bb70719508d91a07c270acef4d38c03cd8370b83469', 'Head Injuries', 'subtype_head_injuries_0959bc32c6', 'dx_head_injury_unspecified_611d184685', 'Head injury, unspecified', 'accepted_deterministic'),
  ('1627', '81a5b5aa73af4bbf047f2df1a33bb41e346a545bad25e45832b51f3995b8ea00', 'Cervical nerve root compression/stretch', 'subtype_cervical_nerve_root_compression_stretch_6f650f0242', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('1628', 'e664dc8256ac011bb8ba9af1976f6ab1bf056a8b2ed50b29080bff4e111ef726', 'Head Injuries', 'subtype_head_injuries_0959bc32c6', 'dx_head_injury_unspecified_611d184685', 'Head injury, unspecified', 'accepted_deterministic'),
  ('1629', 'b639c792ed576f37c2cc1e1556711ac3482dd8c87613a97d7ebec5b6da78399c', 'Thigh Muscle strain/Spasm/Trigger Points', 'subtype_thigh_muscle_strain_spasm_trigger_points_bba788e936', 'dx_thigh_muscle_strain_spasm_trigger_points_bba788e936', 'Thigh Muscle strain/Spasm/Trigger Points', 'identity_group'),
  ('1630', '5bb82dfff5a474b079622bc0c723078cc665404358e4c1e5f9c90cf8cf8924eb', 'Lateral meniscal tear', 'subtype_lateral_meniscal_tear_8f122c7931', 'dx_meniscal_injury_b166306f7d', 'Meniscal injury', 'accepted_deterministic'),
  ('1631', '627ff8d194a044c0d3246040fcfc948515349709bcabcfab7834a9f9e78f88b4', 'Sprain medial collateral (deltoid) ligament ankle', 'subtype_sprain_medial_collateral_deltoid_ligament_ankle_ba23692ed8', 'dx_medial_ankle_ligament_injury_9add2aecee', 'Medial ankle ligament injury', 'accepted_deterministic'),
  ('1632', 'ac26ccea3651236e07a8da082bcb50a35bd8d80674c60acfb38f19e1c5a1c066', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1633', '3a27f5cb3d2e70d31ee934db8aa173c774a1756bb79bacadb67914565035a095', 'Labral tear, hip joint', 'subtype_labral_tear_hip_joint_f90e9ab29f', 'dx_hip_labral_injury_91413d20be', 'Hip labral injury', 'accepted_deterministic'),
  ('1634', '1a02b9c02aa64f8a305d080b45bfea360286dbace1d9acce373e0f3e47c7803e', 'Grade 2 MCL tear knee', 'subtype_grade_2_mcl_tear_knee_843dc46804', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('1635', '12b71c07936e83a652bfef175065025556404e129d750f97080d195a357541e4', 'Head Injuries', 'subtype_head_injuries_0959bc32c6', 'dx_head_injury_unspecified_611d184685', 'Head injury, unspecified', 'accepted_deterministic'),
  ('1638', '7f273000fbff2fbe7aa209962514175d9a8d31b1662a011a8c978e90d76fabe0', 'Distal quadricep haematoma', 'subtype_distal_quadricep_haematoma_01c745cc46', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1639', 'ea7832a94d6e33fc6b0ca667cb01dcf1d77fdc25c049725975a76bd975be78c7', 'Knee Pain/Injury Not otherwise specified', 'subtype_knee_pain_injury_not_otherwise_specified_f2690253b3', 'dx_knee_pain_609ce718bc', 'Knee pain', 'accepted_deterministic'),
  ('1641', 'da32e73d0d7a8c774002cd347cee9bdb8df7a0eacde23e24a2761658b44c9220', 'Proximal adductor trigger points', 'subtype_proximal_adductor_trigger_points_e0737a9324', 'dx_proximal_adductor_trigger_points_e0737a9324', 'Proximal adductor trigger points', 'identity_group'),
  ('1642', '29f8789a642f20d42095b35cfeb0c3db4208509ce9c5c585af82c238b6508907', 'Loose Body in Elbow', 'subtype_loose_body_in_elbow_7ea00fe2a3', 'dx_elbow_loose_body_85f452ea62', 'Elbow loose body', 'accepted_deterministic'),
  ('1644', '807b069545a59927f07d6eae1547a12baa7fc62d8b41273264b4bcec12f6521b', 'Neurological Neck Injury', 'subtype_neurological_neck_injury_25dc3f335f', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('1645', '2e32ac43b805545fe846e65c97b0034a38671b1b64eb5c71a34a413e44b3ac41', 'Bruised ribs/chest wall', 'subtype_bruised_ribs_chest_wall_0c223ac8bd', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('1647', '72e56787303a9a560f6901a4b15d7692e8e392ca9079b45bebf89bad541ec121', 'Ankle multiple ligaments sprain', 'subtype_ankle_multiple_ligaments_sprain_7b65bb0881', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('1648', 'e9efe7b67c769fbd726ba92b0444e33058046c9c35d58c15a27316aba38cf1d1', 'Rectus femoris origin tendon rupture', 'subtype_rectus_femoris_origin_tendon_rupture_2d5e723e36', 'dx_rectus_femoris_tendon_rupture_0e94ff146b', 'Rectus femoris tendon rupture', 'accepted_deterministic'),
  ('1649', '79a948769ba7261ea3f04a66f96ecaa710430d2417a364e4e87b13b34ba7a95a', 'Distal radioulnar joint injury', 'subtype_distal_radioulnar_joint_injury_bd4d88a83d', 'dx_wrist_injury_d94414e2c6', 'Wrist injury', 'accepted_deterministic'),
  ('1651', '897040139a2f2eca1c78b3b65451a5a1293495d255edaa897465266ad84dadf6', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1652', '97b3cc109b455620a287dcde6d990f7da3cb41d924eaeb99f9a4aeafa34501b6', 'Semimembranosis/tendinosis strain (grade 1 - 2)', 'subtype_semimembranosis_tendinosis_strain_grade_1_2_83548c8a09', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1653', 'd615e39027d157620cecdf4f68d55ead65a0e48a03379da161a1795735ae91d6', 'Grade 1 A/C joint sprain', 'subtype_grade_1_a_c_joint_sprain_1ad80c156f', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1654', 'e8f04a6b5e44fffc4c23e990fb4c65d2a6761e68445166db2c33689c7b51ba6b', 'Hamstring cramping during exercise', 'subtype_hamstring_cramping_during_exercise_2eb7c1414b', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm', 'accepted_deterministic'),
  ('1655', '9173b37f88171d3061c72f1ef114849e941cc2da396f4684217dc6dd3a057c3a', 'Synovitis of MTP joint(s)', 'subtype_synovitis_of_mtp_joint_s_52c849b5e4', 'dx_toe_joint_synovitis_df423d00d4', 'Toe joint synovitis', 'accepted_deterministic'),
  ('1656', '203274f0650402cf405bd715d2a15865945d9d36b52bb82de34bf0724f5b0d8b', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('1657', '58cb5e7cf0a088eba783649875ee00ceb7e2d885bbd36355f2dfc78b832b2f64', 'Iliotibial band syndrome', 'subtype_iliotibial_band_syndrome_126a373d4b', 'dx_iliotibial_band_syndrome_126a373d4b', 'Iliotibial band syndrome', 'accepted_deterministic'),
  ('1658', '4f754a61e64b5e16d0ceebbc3b39bb1eaf0b4d4491c9e2607660161730f42be2', 'Hip Joint Inflammation/Synovitis/Other Biomechanical Lesion', 'subtype_hip_joint_inflammation_synovitis_other_biomechanical_lesion_b7683e426f', 'dx_hip_joint_injury_07aa18de20', 'Hip joint injury', 'accepted_deterministic'),
  ('1659', '6b66725b65ba0641554a2c0c9056173423805573d24bc30fbb6ed68c32c4d601', 'A/C Joint instability/recurrent sprains', 'subtype_a_c_joint_instability_recurrent_sprains_ed3ae2521a', 'dx_acromioclavicular_joint_chronic_instability_299408db68', 'Acromioclavicular joint chronic instability', 'accepted_deterministic'),
  ('1660', '935f6b43c1ec57853d4c7c9315c615e5f6adec1b621899904f61c6bed65abf42', 'Adductor longus strain', 'subtype_adductor_longus_strain_dd1eac51f6', 'dx_adductor_muscle_injury_97164c9b14', 'Adductor muscle injury', 'accepted_deterministic'),
  ('1661', '2cf8930c581a73c5ce02265ace44d9a503a8a09d72d242e5c7f3c8d4d430c752', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1662', '99253e2e5c10f3157f6aa226f02ab3f0c415ab935981bd4115ed16e049668205', 'Distal radioulnar joint injury', 'subtype_distal_radioulnar_joint_injury_bd4d88a83d', 'dx_wrist_injury_d94414e2c6', 'Wrist injury', 'accepted_deterministic'),
  ('1663', 'c148ec960f3778414b002d990c58d0f8af662bf9b95f3665dcc47f7b8975ed2b', 'Glenohumeral joint sprain with chondral/labral damage (incl SLAP tear)', 'subtype_glenohumeral_joint_sprain_with_chondral_labral_damage_incl_slap_tear_1eb5055b90', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('1664', '76943a2471b6ace989faf5f19766dd0983f271a2a017922af5b8c82b64a16766', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1666', '76f395ade15596b11117379c109f484c38b749dbf231b4d71748211426b275ac', 'Grade 1 A/C joint sprain', 'subtype_grade_1_a_c_joint_sprain_1ad80c156f', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1667', 'ec0a12d2ea6c6023e3a7d3f8a77482adf2341d1f09321a6b105dc1f8353492af', 'Osteolysis of distal clavicle', 'subtype_osteolysis_of_distal_clavicle_77177bd36c', 'dx_distal_clavicle_osteolysis_0f9c9b6604', 'Distal clavicle osteolysis', 'accepted_deterministic'),
  ('1668', '2144c7de2856563a1834d8a5cbf7d12dcd11205653d62c8146984e2f6c116f59', 'Ankle anterior impingement', 'subtype_ankle_anterior_impingement_3a5b67cd15', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis', 'accepted_deterministic'),
  ('1669', '24d18fc37b3f786c470c051304de84582b4d3041191559f8e233fbd3e49c6857', 'Hip and Groin Muscle strain or tear', 'subtype_hip_and_groin_muscle_strain_or_tear_936dbed7ca', 'dx_hip_and_groin_muscle_injury_7ccd814142', 'Hip and groin muscle injury', 'accepted_deterministic'),
  ('1671', '29e4f3548aedda29fd9d92fa76ee633aa7ceb52dc43875ffbef0f742efb011aa', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1672', '4c78ce099d76681161ac6ebc6f8b4347b556751898d43e6daef5ad850fc4a1cd', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1673', '9f65e3183169ead7ab93cc2bba10865cdff83daf6cc631680365eeb1374e1dd9', 'Ankle pain undiagnosed', 'subtype_ankle_pain_undiagnosed_309d1922bc', 'dx_ankle_pain_de6b615afc', 'Ankle pain', 'accepted_deterministic'),
  ('1674', '3c7d10977940b34cce71d5b694e3552f862fb600df98e08d512ff17fa65cd4f8', 'Knee pain or injury, not otherwise specified', 'subtype_knee_pain_or_injury_not_otherwise_specified_50ca194d1d', 'dx_knee_pain_609ce718bc', 'Knee pain', 'accepted_deterministic'),
  ('1675', '0f1a6be732f5413604ee759f7c138dbb1b9319d1fccf452ecebad9841c64e6c8', 'Soleus Trigger points/Spasm', 'subtype_soleus_trigger_points_spasm_dfb83ed490', 'dx_soleus_trigger_points_spasm_56202bbe31', 'Soleus trigger points/spasm', 'accepted_deterministic'),
  ('1677', '70bf6264f92db42edc0645aeaaf3ce1f967b489c6db484d32f988a7edaad698b', 'Back referred hamstring tightness', 'subtype_back_referred_hamstring_tightness_6fbd78d98a', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'accepted_deterministic'),
  ('1678', 'b18da31d5c0f23c83e9055debff925d0f8bd220bfd6098dbe59f85798a5df575', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1679', '7553d46c2744fb6d9443d497f629cd9929368dae07e16ea5cc57d24663872a02', 'Acute shoulder subluxation', 'subtype_acute_shoulder_subluxation_705b818f24', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('1680', 'f22b237291cec1430d7b1a5a30720294adb8bf6c109d02b115c22e5968b6750e', 'Costal cartilage/costochondral joint injury', 'subtype_costal_cartilage_costochondral_joint_injury_31f64ad2c4', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('1681', 'a9455464f9563e10d6491532ade30a3339fbb764f0dc5d80c24f053e243010a8', 'Acromioclavicular (A/C) joint sprain', 'subtype_acromioclavicular_a_c_joint_sprain_75f6a9a659', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1684', 'f19df645f792aaf9220c6071df7b06e67074b7e73c3eaada5b42a17738cd1e5f', 'Quadriceps tendon injury', 'subtype_quadriceps_tendon_injury_08ea99efaf', 'dx_quadriceps_tendon_injury_08ea99efaf', 'Quadriceps tendon injury', 'accepted_deterministic'),
  ('1685', 'd5141832122ddc8d36d15b277637dd67757bc5d3e65a3c1c3300e46da01f3c1a', 'Hamstring tendon injury', 'subtype_hamstring_tendon_injury_f86b1dad5b', 'dx_hamstring_tendon_injury_f86b1dad5b', 'Hamstring tendon injury', 'accepted_deterministic'),
  ('1686', '94c6c81b401850a74dc665f9209e79a1acdbe4433dd8c20e87a6fd0aaa2be538', 'Nose fracture', 'subtype_nose_fracture_7b8a158870', 'dx_nasal_fracture_a291a11f04', 'Nasal fracture', 'accepted_deterministic'),
  ('1687', '4ad0913ae1390dd397927d5a6514e3c5b562eae52569b7e60487ddc6f8dc4673', 'Lateral meniscal tear', 'subtype_lateral_meniscal_tear_8f122c7931', 'dx_meniscal_injury_b166306f7d', 'Meniscal injury', 'accepted_deterministic'),
  ('1688', '332040e140a716710917b455d0b82137a1a3b1331e8e1cb20b15663d7d11c78c', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1689', 'e0d4d7c3dd2ef7a121ad5cf90045262361c0cfa7676efed20a9eb0fa2ff5c388', 'Nose laceration requiring suturing', 'subtype_nose_laceration_requiring_suturing_7ac079db51', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('1690', '2bbb7b78858e3b7abdf3661169cc7ec22620e336d4e90457caf8cddb2a8ef980', 'Fracture distal phalanx thumb', 'subtype_fracture_distal_phalanx_thumb_e21344c491', 'dx_thumb_distal_phalanx_fracture_148dd4f5fc', 'Thumb distal phalanx fracture', 'accepted_deterministic'),
  ('1691', '7b0f07f25de19ef9485845a99565f68dc21c54272cb1529fec63a5d6a61f3ac6', 'Calf muscle cramps/spasm', 'subtype_calf_muscle_cramps_spasm_7890832741', 'dx_calf_cramp_spasm_950b710fbb', 'Calf cramp/spasm', 'accepted_deterministic'),
  ('1692', '43f2eaea584ae18137b2736829d84ec8c16f9cac4f6643c6ff53b1f9a2fe68b9', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('1693', '5f83867b0641c9549e45186ae1670034c9228829c14dcd7a5472a1909f80f955', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('1694', 'ad232bae26092d6a4af7ca54da4de3d34be3fa80fa449c694444fbe3e064886a', 'Acute shoulder subluxation', 'subtype_acute_shoulder_subluxation_705b818f24', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('1695', '6bd5fd1f5000d7cad13c73563489454670f9653cbc3cbeb0e7822999a5540d0e', 'Thumb IP joint sprain', 'subtype_thumb_ip_joint_sprain_a5a6317c8f', 'dx_thumb_ip_sprain_8664a5f1e4', 'Thumb IP sprain', 'accepted_deterministic'),
  ('1696', '5573455b2a1f8ff2a6bcc4253abd6fa067b6a05f540e7e207296da01bef4346f', 'Instability 1st CMC joint', 'subtype_instability_1st_cmc_joint_77f00eb8fa', 'dx_first_cmc_joint_instability_63d125fc16', 'First CMC joint instability', 'accepted_deterministic'),
  ('1697', '9ae1f3e3608e5222f6d97d354822d2b8065283006d9be58ab874017e33cd631e', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1698', 'edd5fc480ffcb1dceec3bf3229ddc4c42b70efb46b50e98f514912c7b89692be', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1699', '5fd3a903065f3e7bcae0563cda6b912b57b8cceef03f3c4ae4c57a0075d51b70', 'Cervical functional pain', 'subtype_cervical_functional_pain_e11c275770', 'dx_cervical_functional_pain_e11c275770', 'Cervical functional pain', 'accepted_deterministic'),
  ('1700', 'b676485a213672e4a0f6f9da61d75728ed502a5a33b736d14716b4ad2c256afa', 'Thoracic disc prolapse', 'subtype_thoracic_disc_prolapse_7034b398b8', 'dx_thoracic_disc_disorder_9d9c895000', 'Thoracic disc disorder', 'accepted_deterministic'),
  ('1701', '30cd5b49d601b97ae20a24bf8a00a9d8173e69412d7bec85700194dcb63cfbda', 'Lateral compartment osteoarthritis knee', 'subtype_lateral_compartment_osteoarthritis_knee_a5a8fabaab', 'dx_knee_osteoarthritis_088b6b8911', 'Knee osteoarthritis', 'accepted_deterministic'),
  ('1702', 'ed6d100a9969789610f6e0b9f9cd1dc351810dd856b94125c76dba9253aa5f59', 'Knee Pain/Injury Not otherwise specified', 'subtype_knee_pain_injury_not_otherwise_specified_f2690253b3', 'dx_knee_pain_609ce718bc', 'Knee pain', 'accepted_deterministic'),
  ('1703', '82b00db9dfb8bc9944f217eadf8fce98e2475dfc4aeb78fb8e612c5a38c8e8fb', 'Glenohumeral ligament tear', 'subtype_glenohumeral_ligament_tear_c7ff258e45', 'dx_glenohumeral_ligament_injury_0fa65242e3', 'Glenohumeral ligament injury', 'accepted_deterministic'),
  ('1705', 'd00945f3fefe91664f44eda3bbe6a84bc00850000b22bc6181aeb56b75f5ff7f', 'Acute shoulder subluxation', 'subtype_acute_shoulder_subluxation_705b818f24', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('1706', '75d575e8bfe27d8756e58738265fb4ba0439d601bd15fa45d58c5e59b83568dc', 'Sprained/jarred elbow', 'subtype_sprained_jarred_elbow_a336ca7456', 'dx_elbow_injury_7100f71f81', 'Elbow injury', 'accepted_deterministic'),
  ('1707', 'bdc7776ceee2c458dc535eb6f07f1f98095cc8718298c5e62a30c41266718ce5', 'Fracture Middle rib (5 - 9)', 'subtype_fracture_middle_rib_5_9_a58fe86e0f', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('1708', '8dc1449bb8caf174f5708a2df671e3e23c51402c803678c2d4c1ce3733ad3459', 'Thumb ulnar collateral ligament (UCL) rupture at MCP joint (skier''s thumb)', 'subtype_thumb_ulnar_collateral_ligament_ucl_rupture_at_mcp_joint_skier_s_thumb_1db84f53fe', 'dx_thumb_ucl_injury_00b846b6dd', 'Thumb UCL injury', 'accepted_deterministic'),
  ('1709', '48ed58fd4a9fc1c5aed895162fc28b7afda695ea53f960bde72eee5b994ee5b7', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1710', 'efc531178527a80d8e55ff75bd10fe0d1b646d0af124b816c9cf6ea35bfde644', 'Knee medial collateral ligament (MCL) injury', 'subtype_knee_medial_collateral_ligament_mcl_injury_9cce43fa53', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('1713', '27782cb9328ddb73ff9e5a90b93657b812d15f9522461f2cf10629b2e737188c', 'Post shoulder surgery', 'subtype_post_shoulder_surgery_b20274a235', 'dx_postoperative_shoulder_condition_ee7c38fb4d', 'Postoperative shoulder condition', 'accepted_deterministic'),
  ('1714', 'c6e0f200a6d072e04bdbdfa7d056675c076f879294cb8a229aabb48683ce3774', 'Hand laceration', 'subtype_hand_laceration_1ca99c2b1b', 'dx_hand_wrist_laceration_or_abrasion_35c31d7555', 'Hand/wrist laceration or abrasion', 'accepted_deterministic'),
  ('1753', '955ac60b846476c4b92f6407f12fad846587966e93c26dced2fe5c8664c623df', 'Shoulder Pain/Injury not otherwise specified', 'subtype_shoulder_pain_injury_not_otherwise_specified_18170edcc8', 'dx_shoulder_pain_738e4b93f7', 'Shoulder pain', 'accepted_deterministic'),
  ('1754', '982bbf182e7664d50d044fb081efed24a9d506f8b01f6d2edd094fab0f85836d', 'Sartorius tendon injury', 'subtype_sartorius_tendon_injury_1da1e5ccf0', 'dx_sartorius_tendon_injury_1da1e5ccf0', 'Sartorius tendon injury', 'accepted_deterministic'),
  ('1758', '8002ed0352be791bcaaec0057f8a36c29ebe9a0e2ef7d66e0ba4a923e001e372', 'Lumbar contusion/haematoma', 'subtype_lumbar_contusion_haematoma_ae89cb3e74', 'dx_lumbar_soft_tissue_contusion_125139d685', 'Lumbar soft tissue contusion', 'accepted_deterministic'),
  ('1761', '851d97946b742747963b36a716eae190e72314d83047d116ba17c69e61715fa2', 'Knee posterolateral complex (PLC) strain or tear', 'subtype_knee_posterolateral_complex_plc_strain_or_tear_036571cdc7', 'dx_knee_posterolateral_corner_injury_a4c4c64579', 'Knee posterolateral corner injury', 'accepted_deterministic'),
  ('1762', '65443f42b00737443a222056142b3f1b1263f74fbf2ce6cf52ca008e383ba615', 'Fracture 2nd metacarpal', 'subtype_fracture_2nd_metacarpal_47cf07eded', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture', 'accepted_deterministic'),
  ('1763', '5dac6d765e3e086e181f719d899858bf307898d98b3dc53b8be66403648e1c03', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('1764', '557a43c1a2b56cbef53e303cd493b6942042649f600469b11890099ce421a02b', 'Shoulder dislocation with labral Bankart lesion', 'subtype_shoulder_dislocation_with_labral_bankart_lesion_962c9d821b', 'dx_shoulder_dislocation_2067688fdd', 'Shoulder dislocation', 'accepted_deterministic'),
  ('1765', '5227c847c4e3c91760f2f405b370072d9ed7fadb50421e7cac9578108dc8588e', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1766', '1ac8b77317207f162139a5a975289cf15f04b095a90031a34b250a67882c15c2', 'Proximal biceps tendon injury', 'subtype_proximal_biceps_tendon_injury_121c1b2433', 'dx_biceps_tendon_injury_cbd11d2125', 'Biceps tendon injury', 'accepted_deterministic'),
  ('1767', '1895c378953541867de140cbd4e9093ac2b1808d3c3045f490b3cab610dfab7f', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('1768', 'e69fafa7115257920f927dbd18f4b7ea7a19439280b9efb417b5ba72c44382b6', 'Ankle multiple ligaments sprain', 'subtype_ankle_multiple_ligaments_sprain_7b65bb0881', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('1771', '3bc86054d690bd18a5df51727a58e2d0993246eaa666ed68db8102bfe9d8c96b', 'Shoulder region contusion', 'subtype_shoulder_region_contusion_cb32ad2030', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion', 'accepted_deterministic'),
  ('1772', 'a62382f72196ff91b25ac1255fb24fd5850925c1df7c5a90def7efb4f5705642', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1774', '9a5384f55121627877987dbb2e0d27aa75b5bad3634083e04f6b81ecce6bf2e9', 'Knee articular cartilage damage', 'subtype_knee_articular_cartilage_damage_015fa9455b', 'dx_knee_cartilage_injury_761df482b3', 'Knee cartilage injury', 'accepted_deterministic'),
  ('1775', 'cbffcf46873077e9bb3a007caca20e79a40de2b6190759e2918f251e083d8d47', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1777', '39ab884e82929616e64cc29f9bd5899795155cb355ff32f9814106b34d3e78f3', 'Hip/Groin Pain Not otherwise specified', 'subtype_hip_groin_pain_not_otherwise_specified_742fb1cd99', 'dx_hip_and_groin_pain_27531edcc3', 'Hip and groin pain', 'accepted_deterministic'),
  ('1779', 'b9fe4801b4a741d5cf098763327d6f8042614ca24021d493b457cc2787571de0', 'Grade 1 MCL tear knee', 'subtype_grade_1_mcl_tear_knee_6a8ace9800', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('1780', '2dd4ad8e9f3b38159176a67882a8a835dd38448d22ed00f9c7138b7625b4decf', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1781', '22e32982cfc77f5912e6a02131c8e958ca278ccf811d6bcb93467346afdc0d8a', 'Other soft tissue bruising/haematoma knee', 'subtype_other_soft_tissue_bruising_haematoma_knee_3ffba13606', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('1783', 'efc995e0eb37a0640771a6d287f460dfb50372724ae5e0d2b01d34d27a73403a', 'Thigh muscle haematoma', 'subtype_thigh_muscle_haematoma_814a5219d6', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('1784', 'f0a3fc640164555cc3dc1a699c60109a82544bb90b7bbf4a1b7db7727a1cdc3a', 'Inferior tibiofibular syndesmosis sprain', 'subtype_inferior_tibiofibular_syndesmosis_sprain_0545fce188', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'accepted_deterministic'),
  ('1785', 'ac24f014dde962ee704b32c2c7e6a18fa5952da862b6e215f058c4e57dad7aee', 'Thigh muscle haematoma', 'subtype_thigh_muscle_haematoma_814a5219d6', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('1786', 'fb355cb50c2e9ecc34cf4725bde11080e90c14a2ff46d39ee9f58ccf32ed44d9', 'Hand laceration', 'subtype_hand_laceration_1ca99c2b1b', 'dx_hand_wrist_laceration_or_abrasion_35c31d7555', 'Hand/wrist laceration or abrasion', 'accepted_deterministic'),
  ('1791', 'd0baad8ca845911b19831f6a5c4a1e21008f92d2873c3f6b5cb54bb3a40e9198', 'Semimembranosis/tendinosis strain (grade 1 - 2)', 'subtype_semimembranosis_tendinosis_strain_grade_1_2_83548c8a09', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1792', '36f37d2dd9c8891a8336c28d1d233e40a3a86a58e099dc2f364caec507c009ed', 'Rectus femoris strain', 'subtype_rectus_femoris_strain_5670ca194b', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1795', '1347206600121bc4b5bf3a6f33fb71889315c86a30d4a115ae57148b4807133c', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1797', '7ae141c68ddef88a24e86cc659ec419dadd22eba6a70adda3c0054b8ba59149e', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('1808', '81008dc139725bad77eeda56ffac0f3089ba45921933e231c4a4abf045ec7ae6', 'Distal biceps tendon rupture', 'subtype_distal_biceps_tendon_rupture_a28ef09d0b', 'dx_biceps_tendon_injury_cbd11d2125', 'Biceps tendon injury', 'accepted_deterministic'),
  ('1810', '9e5b3f8b5c4430bbb4a0ac2f0147c90ee177122b2f3966047e5c6a1066208ded', 'Patellofemoral osteochondral injury', 'subtype_patellofemoral_osteochondral_injury_95dab31c6f', 'dx_patellofemoral_injury_a6e2fe370a', 'Patellofemoral injury', 'accepted_deterministic'),
  ('1811', '0410978d64ecb25c63bfc7099d87bc7e3c99bb9d77357b1797b6e30696b59e14', 'Anterior talofibular ligament sprain', 'subtype_anterior_talofibular_ligament_sprain_f8c3b9037d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('1825', '5acd2659e1f532728a5f80080422397243b27ed15d436e903fb9b6a655813fbd', 'Hamstring cramping during exercise', 'subtype_hamstring_cramping_during_exercise_2eb7c1414b', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm', 'accepted_deterministic'),
  ('1827', 'f9fdaffcd87f1076a25c307ea524551f2e4277db8f4c0b9bf649d2cbcad17042', 'Posterior cruciate ligament (PCL) injury', 'subtype_posterior_cruciate_ligament_pcl_injury_fbe6c1cd7d', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury', 'accepted_deterministic'),
  ('1828', '85ef404e75d7515bb83f14aef81b6bfdc1413bfa197dcaa2baf628d08ab6f19b', 'Inferior tibiofibular syndesmosis sprain', 'subtype_inferior_tibiofibular_syndesmosis_sprain_0545fce188', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'accepted_deterministic'),
  ('1829', 'cfe08d685a5ff70726513af3e2aa494b2dde9ca3a2b884456d5d56d06447abc2', 'Posterior cruciate ligament (PCL) injury', 'subtype_posterior_cruciate_ligament_pcl_injury_fbe6c1cd7d', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury', 'accepted_deterministic'),
  ('1830', 'fcfab4b2521a831d4b15e5a5a26bf0ac7c38e1ac150cf5e43605b34e0e7ee248', 'Chin laceration', 'subtype_chin_laceration_e38a663885', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('1832', 'ad00b0855d8adc12599b6f057f2bc568d9caeed2a91126bdb4ed854b8216851f', 'Calf muscle cramps/spasm', 'subtype_calf_muscle_cramps_spasm_7890832741', 'dx_calf_cramp_spasm_950b710fbb', 'Calf cramp/spasm', 'accepted_deterministic'),
  ('1833', '80b0f630857f7307edebd8d5b84d6d82615e291524638db4909c9add123ed24f', 'Glenohumeral joint sprains', 'subtype_glenohumeral_joint_sprains_0aefa97c55', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('1834', 'a38477eedb8803e27a58a7e006517e0654d30ca37037481d3fd7c96edcf178bb', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1835', '2181b1d930c57a050d7f74d9de0c1b862719c75e8d1cd87f51cc4a5afa93536a', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1836', 'f2286a71364a12ca4cc6a02e7c5fe9afd458891d6688e8a52d1f02ac807a027a', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1837', 'e13964fb828a65401bf85842b1023c793ecd3fab8d0a1f13f5e4bc4ddf1525cb', 'Thigh Laceration/Abrasion', 'subtype_thigh_laceration_abrasion_dff2e1be4d', 'dx_thigh_laceration_or_abrasion_cec8e820c4', 'Thigh laceration or abrasion', 'accepted_deterministic'),
  ('1838', '51c20d2d81eaae95639182eae0a440d6028f96f9b3c25bb3a75e7a648616b9ef', 'Gastrocnemius muscle injury or strain', 'subtype_gastrocnemius_muscle_injury_or_strain_367914bc2d', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'accepted_deterministic'),
  ('1839', '2a797a141e23c9fc561cbdfcac549705d6c95c1df8e4d840587624cda9bce996', 'Diagnosis not specified', 'subtype_diagnosis_not_specified_7787afa6db', 'dx_diagnosis_not_specified_7787afa6db', 'Diagnosis not specified', 'accepted_deterministic'),
  ('1840', '0cba0d768f0dff0b4dece48c3f72dba16183f9405357abb45e8391b687f0c80c', 'Foot Joint Sprain', 'subtype_foot_joint_sprain_8ee641b736', 'dx_foot_joint_injury_28a178b0b5', 'Foot joint injury', 'accepted_deterministic'),
  ('1841', '263a5b32a67f3eb872cc186fa19fef2a0e55e57318b414cf92ffe82c3fd527c2', 'Elbow hyperextension +/- strain anterior elbow structures', 'subtype_elbow_hyperextension_strain_anterior_elbow_structures_2510e40065', 'dx_elbow_injury_7100f71f81', 'Elbow injury', 'accepted_deterministic'),
  ('1842', '46060844d15c5d087e77515b625c95687724e784d35857e1f6f32461958dbf75', 'Lumbar nerve root impingement due to foraminal stenosis bony and disc', 'subtype_lumbar_nerve_root_impingement_due_to_foraminal_stenosis_bony_and_disc_2467044408', 'dx_lumbar_nerve_root_disorder_906788391c', 'Lumbar nerve root disorder', 'accepted_deterministic'),
  ('1844', '88776d9938d1b249f551d716a9160c8f53a46cc61b24f527edb3bc5d1708343f', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1846', 'f558201765f04ce601d7289331cb377a51938d6e332dc0c010ea71187676fdac', 'Knee pain undiagnosed', 'subtype_knee_pain_undiagnosed_cd27746a95', 'dx_knee_pain_609ce718bc', 'Knee pain', 'accepted_deterministic'),
  ('1847', '0cb0259947373dbecf9be89a6891fe7f493ffb106f4c82fda898ff60f60e50b7', 'Foot Joint Sprain', 'subtype_foot_joint_sprain_8ee641b736', 'dx_foot_joint_injury_28a178b0b5', 'Foot joint injury', 'accepted_deterministic'),
  ('1849', '313f0bc40c5700fb4e135435da273aeb02ef32e3090d7e950f1bd6665c1845dd', 'Cervical nerve root compression/stretch', 'subtype_cervical_nerve_root_compression_stretch_6f650f0242', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('1850', 'ad6e1c70934b0af514daa36450eacda0952160cb1d2d727b6b042d422e1348bc', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1851', '892431a7fc3bea7e7b0d070c8bd8448c64a326cf98aec3beffc2e2702c70d1c4', 'contusion/haematoma, hip region', 'subtype_contusion_haematoma_hip_region_ffc578cee0', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma', 'accepted_deterministic'),
  ('1852', 'ce3b4c00b0b1fd6b2766b51ca961572bd141082a885e806a9267e1bf8e656322', 'Lumbar soreness or muscle spasm', 'subtype_lumbar_soreness_or_muscle_spasm_d5cbfcf03b', 'dx_lumbar_soreness_or_muscle_spasm_d5cbfcf03b', 'Lumbar soreness or muscle spasm', 'identity_group'),
  ('1853', 'bd3b4c19fc6666190cb4bd4caedb2bc2c954e4ce377e04df153c302844b07c86', 'Knee posterolateral complex (PLC) strain or tear', 'subtype_knee_posterolateral_complex_plc_strain_or_tear_036571cdc7', 'dx_knee_posterolateral_corner_injury_a4c4c64579', 'Knee posterolateral corner injury', 'accepted_deterministic'),
  ('1854', 'dc073bd191de8448810a46075f6974d685787f290808676aae9650a46331cee1', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1855', '0cf9c85c10c79494c67b274ecf731740b3f1417d59a9ff8d64158dc4c71939f6', 'Anterior shoulder instability', 'subtype_anterior_shoulder_instability_03b722a3bd', 'dx_shoulder_instability_2b9f54f442', 'Shoulder instability', 'accepted_deterministic'),
  ('1856', '5d4e51f0f0b9ab6872f03abaa0832894cbc9436aa45ec12cf6b327907ae13ee8', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1859', '825f2088284abc4821d882b0837445db0840357f9eebe211c73780baa2b9f60b', 'Gastroc muscle trigger points/spasm', 'subtype_gastroc_muscle_trigger_points_spasm_c6c39392b5', 'dx_gastrocnemius_trigger_points_spasm_0e2bdaca3b', 'Gastrocnemius trigger points/spasm', 'accepted_deterministic'),
  ('1860', 'bc143f1a7d9f90c3198bd7f674a326d3f766957d3efdd28bc33317369c30743c', 'Anterior talofibular ligament sprain', 'subtype_anterior_talofibular_ligament_sprain_f8c3b9037d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('1867', '56e50680a5f600e1e9a1079e85fc182fd9ab483874b173121b3f186ae975c6cc', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1868', '8e4b799f10e5c6d96ec0ec7c82cbeb94bbb9d3c608d5123087d8e5436ff62cb7', 'Buttock Muscle Strain/Spasm/Trigger Points', 'subtype_buttock_muscle_strain_spasm_trigger_points_bed2057d40', 'dx_buttock_muscle_strain_spasm_trigger_points_bed2057d40', 'Buttock Muscle Strain/Spasm/Trigger Points', 'identity_group'),
  ('1869', '112c798ca361b2ee64ddcf9fcc6486a21a62d5c0af641ca70afa41bd0ce44517', 'Thoracic facet joint sprain', 'subtype_thoracic_facet_joint_sprain_205cac3c00', 'dx_thoracic_facet_joint_disorder_519c2ae5a8', 'Thoracic facet joint disorder', 'accepted_deterministic'),
  ('1875', '8a22d45d5710f214a189e8ba002aba5c9fa0fbed1a2959c2ef2e3c22b4e7df88', 'Lateral meniscal tear', 'subtype_lateral_meniscal_tear_8f122c7931', 'dx_meniscal_injury_b166306f7d', 'Meniscal injury', 'accepted_deterministic'),
  ('1876', '26c713efd915a79004a632066f78f1f0547a716a68cfee950ea8215cdbbbcbc4', 'Inferior tibiofibular syndesmosis sprain', 'subtype_inferior_tibiofibular_syndesmosis_sprain_0545fce188', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'accepted_deterministic'),
  ('1909', 'b6781b05bced304702d05f04d61fec12d29e48349957420a170f2f80bcaac6d2', 'Hamstring cramping during exercise', 'subtype_hamstring_cramping_during_exercise_2eb7c1414b', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm', 'accepted_deterministic'),
  ('1910', '06264b3863197e3d67d9fbdacd2fe1a5228f29205848afd2be6aeb4581d26ab1', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1915', 'f60dc76836cd8632c0dfc4634540d7e391fa40352f83d28c408cbcb165142f23', 'Lumbar soreness or muscle spasm', 'subtype_lumbar_soreness_or_muscle_spasm_d5cbfcf03b', 'dx_lumbar_soreness_or_muscle_spasm_d5cbfcf03b', 'Lumbar soreness or muscle spasm', 'identity_group'),
  ('1923', '6b30a7dc544df24b2fad8bd23b3635ab94e61a916f220986cfa1733512073797', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('1924', '209d796b116680a2fd3e87e3e56a5c97323f35fd07ee671a1f0c143cedce73bf', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('1925', 'a0a89fdaa0bdebee7933b4fd929ebc345300415aae16576920da75f468b54f00', 'MCL rupture knee', 'subtype_mcl_rupture_knee_54556835d2', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('1926', 'c55578615259aa5156d2d26896d165b654b273f8c06eb02bda1798f16ae86785', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1927', 'debd56c58dd010e11beebc1dec219816ade3bdbfc30793446e2a320182e28a6d', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('1928', '554a7413e44f1ca14060e09de91a885a1e0389cc4abfae88f634cfb34672c842', 'Abdominal muscle soreness or spasm', 'subtype_abdominal_muscle_soreness_or_spasm_1c26cffcaa', 'dx_abdominal_muscle_soreness_or_spasm_1c26cffcaa', 'Abdominal muscle soreness or spasm', 'identity_group'),
  ('1929', '614c3fa6daad5bb2392d51d7216582a2e553a1aab694caa784dd0f3e036d7be0', 'Acromioclavicular (A/C) joint sprain', 'subtype_acromioclavicular_a_c_joint_sprain_75f6a9a659', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1930', 'b5aaaa9a1b2738bbcc0f3a1079786cb165fe4504d34f665a0f43c964dde28593', 'Soleus Trigger points/Spasm', 'subtype_soleus_trigger_points_spasm_dfb83ed490', 'dx_soleus_trigger_points_spasm_56202bbe31', 'Soleus trigger points/spasm', 'accepted_deterministic'),
  ('1931', '155e2ad1210e37de4741299ba8c4a0d2d11c252a557a5ecde74dd486808e9271', 'Inferior tibiofibular syndesmosis sprain', 'subtype_inferior_tibiofibular_syndesmosis_sprain_0545fce188', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'accepted_deterministic'),
  ('1932', '5649cd7bb940e68e89ebadc2c0f2696cc473feed543720562b3b19d15552ffc0', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1937', '8ab1784e8ce2626e9f4b9f42c1ba5309a11d526a306af5f20d6ac251f34d53bf', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('1938', 'b0e19226b4883b1c00f832c5cd8dc23995909533016907d4e22dbfee564b72cb', 'Facet Joint/Neck Ligament sprain', 'subtype_facet_joint_neck_ligament_sprain_369f0afd14', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder', 'accepted_deterministic'),
  ('1940', '6e0b5d9de83573c27a9d4c4b563ee6d470056526dc964d19d7ef06c067cbe447', 'Posterior impingement ankle', 'subtype_posterior_impingement_ankle_61a8fec620', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis', 'accepted_deterministic'),
  ('1941', '0abedc5e70593392701fcc16f9c254a35fb14f6a0b193e2aeb73c1f94704f39d', 'Gastroc muscle trigger points/spasm', 'subtype_gastroc_muscle_trigger_points_spasm_c6c39392b5', 'dx_gastrocnemius_trigger_points_spasm_0e2bdaca3b', 'Gastrocnemius trigger points/spasm', 'accepted_deterministic'),
  ('1942', '53fdc3c2f594335fe08d4f39fc8f913ebff400d1d3184837bd1e287aa3d4b9be', 'Gastroc muscle trigger points/spasm', 'subtype_gastroc_muscle_trigger_points_spasm_c6c39392b5', 'dx_gastrocnemius_trigger_points_spasm_0e2bdaca3b', 'Gastrocnemius trigger points/spasm', 'accepted_deterministic'),
  ('1943', 'a6d98df3d0c59b4d5468a893bf2267a17d74a717c4773a6ddbb847237ac51c7b', 'Anterior talofibular ligament sprain', 'subtype_anterior_talofibular_ligament_sprain_f8c3b9037d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('1944', '0ffd087a6d3a8b28cbc759a2652f8cfdc0e6c2fd73e79c16f965e84a71ff03cd', 'Medial gastroc strain', 'subtype_medial_gastroc_strain_c97059f639', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'accepted_deterministic'),
  ('1947', 'c7c09f8613a61fb6eee1f6608364aa1b1e2a42f6249770cefb00978ce72c4fd8', 'Flexor tendon rupture finger(s)', 'subtype_flexor_tendon_rupture_finger_s_7133c47639', 'dx_finger_flexor_tendon_injury_93dca2c764', 'Finger flexor tendon injury', 'accepted_deterministic'),
  ('1948', '897d6843e6ebf967f0a81db3ea00ae211945fde4dda7445d14fbcf0966f67ea0', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('1949', 'c5e9f0398271440cb16bf63d9b649c3cbb1d3bc37fd2d373ec5fcb32c275ceb3', 'Dislocation of interphalangeal (IP) joint thumb', 'subtype_dislocation_of_interphalangeal_ip_joint_thumb_46c2243538', 'dx_thumb_ip_dislocation_a325ccd91d', 'Thumb IP dislocation', 'accepted_deterministic'),
  ('1950', '5155cf7d07e6811c34fcd8d1698d65617733928507f328f9f7fe183651dcf51e', 'Cervical nerve root compression/stretch', 'subtype_cervical_nerve_root_compression_stretch_6f650f0242', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('1951', 'af6d277faf0b8d82dee3f536f54b710e7401066c98c27992cc03f7af7d8c1666', 'Tib anterior haematoma', 'subtype_tib_anterior_haematoma_b7227bb3ea', 'dx_tibialis_anterior_muscle_haematoma_b2d920156c', 'Tibialis anterior muscle haematoma', 'accepted_deterministic'),
  ('1952', '10f9e2042e79ac6e635a8dcf2ae90b794b699d520513a2c275e319befafa887c', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1953', '8ca17aa91bbfaac5dedd29ac811a7fb599f1d67a30b398fda8d82be3effa9833', 'Midfoot joint/ligament sprain (incl Lisfranc)', 'subtype_midfoot_joint_ligament_sprain_incl_lisfranc_282c947645', 'dx_midfoot_injury_3332895405', 'Midfoot injury', 'accepted_deterministic'),
  ('1956', '58547cc776ebfdf20483ebfbb9accf55075cb9e36ba5ff2eeba7fd863b8b7ffb', 'Lumbar spine/buttock bone contusion', 'subtype_lumbar_spine_buttock_bone_contusion_419083e232', 'dx_lumbar_or_buttock_bone_contusion_933e74a361', 'Lumbar or buttock bone contusion', 'accepted_deterministic'),
  ('1957', '7899f7f58301e082d2e16ed7192eb40eb2ab841b568d5445a94c277f3ef493ec', 'Facial laceration requiring suturing', 'subtype_facial_laceration_requiring_suturing_40a8df9bf4', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('1958', 'fbb7693725a084706296ae5257d5e6e3f17528c035cdcdad732922f9c86a290b', 'Sprained/jarred wrist joint', 'subtype_sprained_jarred_wrist_joint_7ec711f5b5', 'dx_wrist_injury_d94414e2c6', 'Wrist injury', 'accepted_deterministic'),
  ('1964', '1c9274fbed0be442d8f47a83e3de647b47a8ae1d5b589c65ddc7eb9fb5397419', 'Abdominal oblique muscle strain', 'subtype_abdominal_oblique_muscle_strain_5b04cf0a3c', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury', 'accepted_deterministic'),
  ('1965', '298297bed819fb3ca90d1cc9bc0f4200f30c4d7fa160c650376f25b9401f441d', 'Elbow UCL injury and common flexor origin tear', 'subtype_elbow_ucl_injury_and_common_flexor_origin_tear_447eb313bc', 'dx_elbow_ucl_injury_and_common_flexor_origin_tear_447eb313bc', 'Elbow UCL injury and common flexor origin tear', 'identity_group'),
  ('1966', '90376b1f3055dd2e04a05f0b2c217a5ce7844bb2343e832f671547ce9b6650f4', 'Gastroc muscle trigger points/spasm', 'subtype_gastroc_muscle_trigger_points_spasm_c6c39392b5', 'dx_gastrocnemius_trigger_points_spasm_0e2bdaca3b', 'Gastrocnemius trigger points/spasm', 'accepted_deterministic'),
  ('1973', 'cfd1681afb2d33fd73e4054ff448fd9de4dbf8ee296998beca73d2f56c93fb06', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('1974', '41997d515230879013fe8db727cf97db8f38cf2df22b191fb857e77b3e343b90', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('1975', 'a73fd1052c0e4fb0afc4055d4b67464515d519573272981205e3ffb6e00375a4', 'Gluteus medius/minimus strain', 'subtype_gluteus_medius_minimus_strain_d87e368e47', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury', 'accepted_deterministic'),
  ('1980', 'b3d920451a8c05ccdbfe828a71db469e4f30a6dbbaf4ccc85f2b80365f6be615', 'Hamstring cramping during exercise', 'subtype_hamstring_cramping_during_exercise_2eb7c1414b', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm', 'accepted_deterministic'),
  ('1989', 'b14a84b7c6a9e9b49a822c862ae69f7544348a60ccbd0aa06a43985db18ee4a3', 'Groin pain undiagnosed', 'subtype_groin_pain_undiagnosed_f045a6b426', 'dx_hip_and_groin_pain_27531edcc3', 'Hip and groin pain', 'accepted_deterministic'),
  ('1990', '0b1f7d211abb29a7b2dcc592d4b312d921f6c816e3597cba4b4734476da2b80e', 'Groin soreness or trigger points', 'subtype_groin_soreness_or_trigger_points_70c27347b8', 'dx_groin_soreness_or_trigger_points_70c27347b8', 'Groin soreness or trigger points', 'identity_group'),
  ('1991', '444e40dfd2c937a1c3e1fe4b0debc8363748ad8ddfcad69d3a02f695459e1abc', 'Semimembranosis/tendinosis strain (grade 1 - 2)', 'subtype_semimembranosis_tendinosis_strain_grade_1_2_83548c8a09', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('1992', '023982fe060a212e0d2c84f4f898ff1b662068d177266b78acbe30089540d543', 'Gluteus medius/minimus strain', 'subtype_gluteus_medius_minimus_strain_d87e368e47', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury', 'accepted_deterministic'),
  ('1993', '583679aeb455cdc4c629db857d1ccbc632dc89bf44b3c3f6b993e268082f8027', 'Knee contusion/haematoma (extraarticular)', 'subtype_knee_contusion_haematoma_extraarticular_19a33609a2', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('1994', '8f42a7ef198931173af637d969f8a9b44efe8a2ab2ded2173d9fe6b7015fa3a9', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('1996', 'cf75d141670f521c8b4a23f8fb648270f3cf79b09e21c17549cc02866d4a69b6', 'Adductor longus tendon strain', 'subtype_adductor_longus_tendon_strain_c1fa29e878', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'accepted_deterministic'),
  ('2003', 'b61af4e0ef58c8e6178162690bb755134292dbee18cc094a3ea6e57326d9cff7', 'Synovitis of MTP joint(s)', 'subtype_synovitis_of_mtp_joint_s_52c849b5e4', 'dx_toe_joint_synovitis_df423d00d4', 'Toe joint synovitis', 'accepted_deterministic'),
  ('2004', 'dfcd27818667671a3feb509b976817e8a27839fd05df238de5923f640749d6cf', 'Proximal adductor trigger points', 'subtype_proximal_adductor_trigger_points_e0737a9324', 'dx_proximal_adductor_trigger_points_e0737a9324', 'Proximal adductor trigger points', 'identity_group'),
  ('2014', 'e4d982974079cec3a6d5097eb8e9ccd6fd414970d782d81b66a5b82f97b4f52c', 'Lumbar pain with hamstring referral', 'subtype_lumbar_pain_with_hamstring_referral_c859c82cf8', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('2016', 'ce1dbbe0b04b05ab12fc2bf5beb6468ed22b26e074c6bcb8271f646581034d25', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2018', '0bd707421fd32480094db05f405d7b649a727e9e62833bfbfaa73caea5b89bf9', 'Lumbar facet joint sprain', 'subtype_lumbar_facet_joint_sprain_82bf226720', 'dx_lumbar_facet_joint_disorder_4a13830647', 'Lumbar facet joint disorder', 'accepted_deterministic'),
  ('2020', '4fc0cb7db017ed0e8d8f7bfa7eb7102acd33de04b48d2d87183a3cbc9fea831a', 'Glenohumeral joint sprains', 'subtype_glenohumeral_joint_sprains_0aefa97c55', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('2021', 'cfa9dad23b62aebb49a4a4b0aee19ec8993394254c5065c96b2aeffebffc2904', 'Acute posterior internal impingement', 'subtype_acute_posterior_internal_impingement_bd3421d008', 'dx_shoulder_impingement_c2f2a634b4', 'Shoulder impingement', 'accepted_deterministic'),
  ('2024', 'f37d412f097699c4c054680bc9664439f165ac79c7286c573f346a4fa72e09b2', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('2031', '4d18a4f11007d4472d674aa5bab57dfc2e2a5b8414b35baabbcf261c12d24777', 'Skin infection toenail - incl infected ingrown toenail', 'subtype_skin_infection_toenail_incl_infected_ingrown_toenail_29a82c7edc', 'dx_nail_skin_infection_e50f92314e', 'Nail/skin infection', 'accepted_deterministic'),
  ('2032', '928e5d7cc0e11b38869b9f8fe6cd81d554c5efc19bf8eeefda706f5ea7cff217', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2033', '220219b80db7d2f5ecd32a7be99c0b7b1fab660fe8d8de28005ecb00c01e1901', 'Shoulder dislocation (anterior)', 'subtype_shoulder_dislocation_anterior_543b318a46', 'dx_shoulder_dislocation_2067688fdd', 'Shoulder dislocation', 'accepted_deterministic'),
  ('2034', 'adff1c73bc5db1436bc8c3058c3e4aa267a1db15a0883315f2e7f47abec590df', 'Knee pain undiagnosed', 'subtype_knee_pain_undiagnosed_cd27746a95', 'dx_knee_pain_609ce718bc', 'Knee pain', 'accepted_deterministic'),
  ('2035', '5a8a367d38c09f463c01c11f187177a48237ec63200552c9dc9353ce9c7a27b8', 'Elbow ulna/medial collateral ligament (UCL) strain or tear', 'subtype_elbow_ulna_medial_collateral_ligament_ucl_strain_or_tear_ab4c438f84', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury', 'accepted_deterministic'),
  ('2038', 'e262611ac2c4b9299c093d94cf2c2eae697e97615a4ad1ed462110ff288c6a20', 'Other Stress/Overuse Injury Hip and Groin', 'subtype_other_stress_overuse_injury_hip_and_groin_a42c390491', 'dx_hip_and_groin_overuse_injury_71c787dc38', 'Hip and groin overuse injury', 'accepted_deterministic'),
  ('2041', 'c70ba95f3e5ba4e5c1298f7c7f994a84e17d1eb4228762fb8bba93aec230afbb', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('2043', '436d16961f68a7222f826856036f3035824289d51cc54d5a499c0517eae9e1a1', 'Facet Joint/Neck Ligament sprain', 'subtype_facet_joint_neck_ligament_sprain_369f0afd14', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder', 'accepted_deterministic'),
  ('2044', 'e8f59e399ae6216dcdb53a27e6e4dd3ba1724c8be53ac66849079027178b9ff7', 'Medial gastroc strain', 'subtype_medial_gastroc_strain_c97059f639', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'accepted_deterministic'),
  ('2045', '64e5dfd621c0cd19b77b9a81270a8a33da3033ce7793f8912033fca319c37b2e', 'Sprain of great toe', 'subtype_sprain_of_great_toe_0f26ba4390', 'dx_great_toe_injury_71c02ad835', 'Great toe injury', 'accepted_deterministic'),
  ('2052', '6882040f09a87597cebc64b4f72cb9de5ff0fe134d858b00da289f650a828a52', 'Knee contusion/haematoma (extraarticular)', 'subtype_knee_contusion_haematoma_extraarticular_19a33609a2', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('2055', 'f7ef55066cc04ea8bd67fc48694066e4aaca1f5a152043be70e8c69fa77c2f6e', 'Grade 3 hamstring strain', 'subtype_grade_3_hamstring_strain_6183bcd886', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2056', 'e1e7e189fc1011cc422abb914ebf025b610124e3761c84735351f3814a046410', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2057', 'b309f349e7c1c248a44fd2d8e35b314dded2efdbb89c8aa0674c9afcaaea8f08', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2058', '8cb1617fe1170285df6980857f6616ada75023d6461de164c6585e6d4c25d6a6', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('2059', '87cd33a1a7f33e4b4829ff2a4be408a072e993060ff283720f91ef0f6f15ea37', 'Cervical disc Injury', 'subtype_cervical_disc_injury_13c8608a7d', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury', 'accepted_deterministic'),
  ('2063', 'ee0a13b356fff0f12d33bba2e82f95b57e5bb8f3089206e87737305342968fe8', 'Knee Joint synovitis', 'subtype_knee_joint_synovitis_141778ac5a', 'dx_knee_synovitis_impingement_02e229b1cc', 'Knee synovitis/impingement', 'accepted_deterministic'),
  ('2065', 'd1d702b3c4820cd5c29dda6c2dc2cfecd5e370efe200e488b92a7d810a548f26', 'Costal cartilage/costochondral joint injury', 'subtype_costal_cartilage_costochondral_joint_injury_31f64ad2c4', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2066', 'eb3c0d107191a5e1ccb7c466ddd70460a85355d6c770cc3b2f8b1f6903a39aba', 'Glenohumeral joint sprains', 'subtype_glenohumeral_joint_sprains_0aefa97c55', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('2067', '246e129ff56e6483f91e7afaf2e95e4e73f0e8b08075353b7779f60c0f0cf5d5', 'Anterior talofibular ligament sprain', 'subtype_anterior_talofibular_ligament_sprain_f8c3b9037d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('2068', '8001f3556b82d856539cf3c405922ce08beccbefa6ccc70a992efad69794bddb', 'Thigh Muscle strain/Spasm/Trigger Points', 'subtype_thigh_muscle_strain_spasm_trigger_points_bba788e936', 'dx_thigh_muscle_strain_spasm_trigger_points_bba788e936', 'Thigh Muscle strain/Spasm/Trigger Points', 'identity_group'),
  ('2070', '21844587b100c9b7cc1336afd656416b6764d43421b0aeba04464060337ef1cd', 'Cervical nerve root compression/stretch', 'subtype_cervical_nerve_root_compression_stretch_6f650f0242', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('2071', 'ecdf58d21d775cc5ee4ac06984052f27e032eefea539aa15387431b1bd7dedfa', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2072', '223b5b91b37266e2b9e319262cf20dec92c3ff769f54987fe45071c850b0b39d', 'Sprain of great toe', 'subtype_sprain_of_great_toe_0f26ba4390', 'dx_great_toe_injury_71c02ad835', 'Great toe injury', 'accepted_deterministic'),
  ('2073', '579182734a5c5c4bd929b09cd96458cf554e2ed3198140933454009740cae81d', 'Hamstring cramping during exercise', 'subtype_hamstring_cramping_during_exercise_2eb7c1414b', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm', 'accepted_deterministic'),
  ('2074', 'd8bba3f64679509d8754028454ad61a9b9a446042bd2524325b42c79309121fc', 'Lumbar soreness or muscle spasm', 'subtype_lumbar_soreness_or_muscle_spasm_d5cbfcf03b', 'dx_lumbar_soreness_or_muscle_spasm_d5cbfcf03b', 'Lumbar soreness or muscle spasm', 'identity_group'),
  ('2075', 'ff4bccf75cc84f0138a3489d012353ae4a805d6e57febcae81f2c2bbb2b80066', 'Rectus femoris strain', 'subtype_rectus_femoris_strain_5670ca194b', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2076', 'c968e4f0f1c2924eed42378a83b2d320a6ab056da5d801e09f44dc10228196d4', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2132', '7279685578588d770159736aa7110fc6a4ebdd03bd86ebacac9a50f1da9f071f', 'Sportsman''s hernia', 'subtype_sportsman_s_hernia_c9eeb6b61d', 'dx_sports_hernia_ad99f8552f', 'Sports hernia', 'accepted_deterministic'),
  ('2160', '8ea9729b99bc2ac527853127681edd32a7f1546781d1e1e101e9ecee715e248d', 'Bruised sternum', 'subtype_bruised_sternum_ee6ea74286', 'dx_sternal_contusion_160fe1df77', 'Sternal contusion', 'accepted_deterministic'),
  ('2161', '463ab85f12dfea9df6e281d4d11e523bc145f0985e780252c49242f130866fa4', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2174', 'f27e244f97372b7419b6e7ed70686e6ce7eb4d32ebdee4801e3926dcb9664e9f', 'Corneal Abrasion', 'subtype_corneal_abrasion_9941832ebb', 'dx_eye_trauma_0bcdc22eb2', 'Eye trauma', 'accepted_deterministic'),
  ('2175', '2af053b055e1ec74de0e19ffc196bd5aa1b1e3570cd7e40bfcd2e9ff1dfc6ae9', 'Eyelid laceration requiring suturing', 'subtype_eyelid_laceration_requiring_suturing_8f76e0ddf1', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2176', '4c81867c8e90521c3ccbc5bfa7ac7ee81c305e45c04e329a711314d14ed0ab73', 'Popliteus tendinopathy/strain', 'subtype_popliteus_tendinopathy_strain_27deaa0d59', 'dx_popliteus_injury_0ac29f0573', 'Popliteus injury', 'accepted_deterministic'),
  ('2177', '4b7b261f17ddb2b8658f37cf70ada48b6f48448aca06c4fe362b7a7219c0010c', 'Cervical Disc sprain', 'subtype_cervical_disc_sprain_98da6e06ba', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury', 'accepted_deterministic'),
  ('2178', '033687527033fc485cb4fbf2fc9470a64037dfeadd74dea80f98b52465542d5c', 'Metacarpophalangeal joint sprain', 'subtype_metacarpophalangeal_joint_sprain_103ce7f526', 'dx_finger_mcp_injury_6c586feb13', 'Finger MCP injury', 'accepted_deterministic'),
  ('2179', '2c99c06174468e4b65ccdd0ed7795fd1519609cb5d6941270f27e44e88de4dbf', 'Bruising/haematoma iliac crest/gluteus medius', 'subtype_bruising_haematoma_iliac_crest_gluteus_medius_0d84299fc3', 'dx_buttock_contusion_46ae636fd7', 'Buttock contusion', 'accepted_deterministic'),
  ('2181', 'cef833873641866a50afb0658dd803d69cceb33f8b0e2e0dd977cb07c0e33a87', 'Intersection syndrome', 'subtype_intersection_syndrome_59b79f8251', 'dx_intersection_syndrome_59b79f8251', 'Intersection syndrome', 'accepted_deterministic'),
  ('2182', 'ea1e79e0cec1c9b2d6c150b89a1dadb33ec2e984771be8f089617067e9b90cba', 'Triceps muscle strain', 'subtype_triceps_muscle_strain_0048495411', 'dx_triceps_muscle_strain_0048495411', 'Triceps muscle strain', 'accepted_deterministic'),
  ('2184', '87297aebc1ea9e4c5f9c663a233a40c99d34dcfc8277045a3ce6145d6ee88512', 'Middle trapezius muscle strain', 'subtype_middle_trapezius_muscle_strain_60c4af025e', 'dx_middle_trapezius_muscle_strain_60c4af025e', 'Middle trapezius muscle strain', 'accepted_deterministic'),
  ('2185', 'e9921e79f2103fdd1914588dc2ac7cd1db23c91dd428012e21fd1561a1f9ba55', 'Hip flexor muscle strain', 'subtype_hip_flexor_muscle_strain_3e1d987aae', 'dx_hip_flexor_injury_cedda9fa03', 'Hip flexor injury', 'accepted_deterministic'),
  ('2186', '4ae55ce3805bfd921826eec98b9189af327cfb1fb6fca0a159594971e0202916', 'Hip/Groin Pain Not otherwise specified', 'subtype_hip_groin_pain_not_otherwise_specified_742fb1cd99', 'dx_hip_and_groin_pain_27531edcc3', 'Hip and groin pain', 'accepted_deterministic'),
  ('2188', 'abe714ef42a4552abac2ea9a1d7cbecea5f813bc676075ca56371d11f03e614b', 'Facial laceration not requiring suturing', 'subtype_facial_laceration_not_requiring_suturing_8bb4c346d9', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2189', '2e1acb1d1dc4824dd5eeb63abc1dcffa0fc0084f14bb711ae4a0f7dd985b75e9', 'Distal quadricep haematoma', 'subtype_distal_quadricep_haematoma_01c745cc46', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2190', '6414260c5f661883b814abb9172d653e7adcd208d30d52165af663e0b925f825', 'Hoffa''s fat pad impingement', 'subtype_hoffa_s_fat_pad_impingement_1c7deb1624', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury', 'accepted_deterministic'),
  ('2191', 'fd05527bd0e4190c80185cd0e49c8f446244984ce457547e7e5e9db4f289d0d4', 'Distal quadricep haematoma', 'subtype_distal_quadricep_haematoma_01c745cc46', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2192', 'd6c8782c3d843c21d857715695a1921f60ae4190cfcd9ef25e9b9e96ded60281', 'Knee contusion/haematoma (extraarticular)', 'subtype_knee_contusion_haematoma_extraarticular_19a33609a2', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('2193', '9c9af2e07d4569b6efc41f446285fdbf288fc33307563095596981fe48db652b', 'Distal quadricep haematoma', 'subtype_distal_quadricep_haematoma_01c745cc46', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2194', '476dfd5c4b6355f803da25047fd558b8c79d7d0818593da9fda0ad9267f7ab85', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('2195', '97a790e60fd8e730a0dcdcee2e56d54bdecda4f72f1c5de397e4a94ba9961fa4', 'Elbow ulna/medial collateral ligament (UCL) strain or tear', 'subtype_elbow_ulna_medial_collateral_ligament_ucl_strain_or_tear_ab4c438f84', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury', 'accepted_deterministic'),
  ('2196', 'c27b6b36362752763bd918fa12b68ae49a59f526320966f7eba6fe975ad4715e', 'Ear bruising/haematoma', 'subtype_ear_bruising_haematoma_5b5e34f5d4', 'dx_ear_injury_190079a2d0', 'Ear injury', 'accepted_deterministic'),
  ('2197', 'bfb7ad608e4e37ba1da45dda57014a3cb40e84202bd4293613bd92f1839df440', 'Thumb ulnar collateral ligament (UCL) rupture at MCP joint (skier''s thumb)', 'subtype_thumb_ulnar_collateral_ligament_ucl_rupture_at_mcp_joint_skier_s_thumb_1db84f53fe', 'dx_thumb_ucl_injury_00b846b6dd', 'Thumb UCL injury', 'accepted_deterministic'),
  ('2198', 'cf4a4823d9c2cf627e7bbf354af0d493d0cfc6f61e424e886f682f266fb36d21', 'Ear bruising/haematoma', 'subtype_ear_bruising_haematoma_5b5e34f5d4', 'dx_ear_injury_190079a2d0', 'Ear injury', 'accepted_deterministic'),
  ('2199', '672cc6e815c0fc3da402bff1b19962a3c001618375f9539cf434b98426c0c5c1', 'Shoulder contusion/haematoma', 'subtype_shoulder_contusion_haematoma_1f687995cb', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion', 'accepted_deterministic'),
  ('2206', 'cafcd1720045624436f0da366822943c5915e4f165af32008a21f4bf3e70bd75', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2207', '7a607566423fd5e192a4eef72f8e3e120ae547fde00a264b41c169a8d9f20be5', 'Corneal Abrasion', 'subtype_corneal_abrasion_9941832ebb', 'dx_eye_trauma_0bcdc22eb2', 'Eye trauma', 'accepted_deterministic'),
  ('2208', '66f61af217ea11202e064fb3b670bcbb86b0d4fec4f44b03ec4dc1d40524b4f3', 'Midfoot joint/ligament sprain (incl Lisfranc)', 'subtype_midfoot_joint_ligament_sprain_incl_lisfranc_282c947645', 'dx_midfoot_injury_3332895405', 'Midfoot injury', 'accepted_deterministic'),
  ('2209', '367c15821de495510cd95f27b8772d983c5356b044d6dd8d37792a9f117eda98', 'Shoulder contusion/haematoma', 'subtype_shoulder_contusion_haematoma_1f687995cb', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion', 'accepted_deterministic'),
  ('2210', '12a790a20c6e59f08cc7a7faf421c052c5b89f0d7fa0c4abf9043fb7d7fe3854', 'Complication of laceration incl. infection', 'subtype_complication_of_laceration_incl_infection_594ae25665', 'dx_wound_infection_complication_5415c9f38d', 'Wound infection/complication', 'accepted_deterministic'),
  ('2211', '3800b24bb8b836da8d6339231888cae96c162562bc78c070693e5c7971f56683', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2212', '466ac8a53bc8e46a53d7c0938b1753e527beebb103fcacc451f6bb70c0c3ecde', 'Acute shoulder subluxation', 'subtype_acute_shoulder_subluxation_705b818f24', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('2213', '5034ccbc76245db8ed97cca7c0084a439c79c811c50015c492a0508c5d996adb', 'Scalp laceration', 'subtype_scalp_laceration_50be43ed71', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2214', 'a82898f4e77b14fc79feede7434d24d049828fd37b6130ae4e4d2060b4cc2165', 'Other quadricep strain', 'subtype_other_quadricep_strain_d8561f4b63', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2217', '3b4400e678e54085c3f4bf4268300171898b332f6cddc68b2492526c4346060d', 'Neck soft tissue dysfunction', 'subtype_neck_soft_tissue_dysfunction_8f80031021', 'dx_neck_soft_tissue_dysfunction_8f80031021', 'Neck soft tissue dysfunction', 'accepted_deterministic'),
  ('2218', '2aea1d9c4140e64cfd36483ac7d113b5b5eeef86ed2d39997a648f5aa84a4d37', 'Costochondral joint sprain', 'subtype_costochondral_joint_sprain_d8cfc332b2', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2219', '1b903012efd396cf9ba0e94bdbc61464c2070c2491c5da5aa544e9c6476bbb3f', 'Shoulder contusion/haematoma', 'subtype_shoulder_contusion_haematoma_1f687995cb', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion', 'accepted_deterministic'),
  ('2220', 'd4136035ebf71d8b02189d0e5446de9e32a2d2e1f21746766d610604e3144ea5', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('2225', '17e5c2c0901a77f24553988778090402d6b837ab119147ab60592f43ccd0a736', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('2229', '4ccf47f47dcb89b1815d8434b812f94c76a546acf45f92095dcb8be1d48bf79e', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2230', '642599589440397890bc4240df5f30c93138da3e707cc6161841f565569c3ff0', 'Brachial plexus traction injury/burner/stinger', 'subtype_brachial_plexus_traction_injury_burner_stinger_29eb517979', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury', 'accepted_deterministic'),
  ('2231', '8340db0a666a1d8e57cecfcff9fef04e3c66f7a61ea3cba6de53049f97f1b9d6', 'Acute cauliflower ear', 'subtype_acute_cauliflower_ear_dbdd29e091', 'dx_cauliflower_ear_d6361b8000', 'Cauliflower ear', 'accepted_deterministic'),
  ('2232', 'a7d2f672fb7b6be7b3d8df0edf7d57f833f1d181d612bcb2740f5c7eafb5ba13', 'Instability 1st MCP joint', 'subtype_instability_1st_mcp_joint_12bde005a4', 'dx_thumb_mcp_injury_2b5c0aa20c', 'Thumb MCP injury', 'accepted_deterministic'),
  ('2234', '008e4394ad7efbb0c190331c96cdeed5350fc62be5e4a8a0bf9887749e0787b3', 'Foot soft tissue dysfunction', 'subtype_foot_soft_tissue_dysfunction_b977517935', 'dx_foot_soft_tissue_dysfunction_b977517935', 'Foot soft tissue dysfunction', 'accepted_deterministic'),
  ('2235', '1669871fd0f45fdd7eb458a41ece491053f7d6635a59245bfb7b65c8a2be0240', 'Lumbar pain or injury, not otherwise specified', 'subtype_lumbar_pain_or_injury_not_otherwise_specified_d98060910b', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('2237', 'afbf2b548581629f31203e842526b99284870735e57529aa3eefa150b040bae8', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2238', '33eb2b3547db36ad32c08a90a2737dcd1c331f6ba80849226e28b8f37b5338d7', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('2239', 'ac0d8551dbae8a5fa2798a29af9c23507bb3ab45d9ba5c5deda10925434aafbf', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2240', 'b310ab9d5489b3f641676b83f1ab9464a6faaa67ca08e51aff6561f50fef2828', 'Quadriceps strain or tear', 'subtype_quadriceps_strain_or_tear_17ff226482', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2243', '0e422e0718b1940dfe2d6c685b3554b5463751d86da490e30beee234648cff54', 'Achilles tendon rupture', 'subtype_achilles_tendon_rupture_6b59cc3783', 'dx_achilles_tendon_rupture_6b59cc3783', 'Achilles tendon rupture', 'accepted_deterministic'),
  ('2247', '869482cf73c00fd437a328c5a66248c9d5451c092b4da8b3122c0bb39ff57b94', 'Stress fracture anterior cortex tibia', 'subtype_stress_fracture_anterior_cortex_tibia_4dfa56a525', 'dx_tibial_bone_stress_fracture_2dd746f1b0', 'Tibial bone stress fracture', 'accepted_deterministic'),
  ('2248', 'c01c5b532d1eeea3ac782f994a116aa86d9e7842ed5754a3fe30a1cf2372f1b9', 'Lumbar pain or injury, not otherwise specified', 'subtype_lumbar_pain_or_injury_not_otherwise_specified_d98060910b', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('2249', '3d2b366d5b9ad5503fea4bb83c7204d20fd29eed0bf1c75eb33fb0816019e922', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2250', '50e0148a8748f35aa42dac8d0cd600acaf38265c5974fe9f4b688105cfd677ef', 'Lateral collateral ligament (LCL) strain/rupture', 'subtype_lateral_collateral_ligament_lcl_strain_rupture_0ba99e81ef', 'dx_lateral_collateral_ligament_injury_e3bbb5e542', 'Lateral collateral ligament injury', 'accepted_deterministic'),
  ('2254', '33dd9c2d3fce4ac71b428b0f375ee8fa73608d7209d02a7db7e15041541415de', 'Knee Sprains/Ligament Injuries', 'subtype_knee_sprains_ligament_injuries_bc9c2670dd', 'dx_knee_ligament_injury_unspecified_7ab630d44d', 'Knee ligament injury, unspecified', 'accepted_deterministic'),
  ('2258', 'fcc3cc097d8f592ffbafdb2d8cb36def486814f56c29730dcdaba5a04f35cae2', 'Fracture radius midshaft', 'subtype_fracture_radius_midshaft_981b784b8d', 'dx_radial_shaft_fracture_5e497038ca', 'Radial shaft fracture', 'accepted_deterministic'),
  ('2259', '8d7b8e460ec2b4ca3df083ca397c61bb315dea2ff313cd0e9840642f6a5d860d', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('2260', '8c8dd971311c9dc171183d7d3a758df51b2369614f216449405d2e09760b112f', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('2261', '4c53d4aacf9424ec1ec266e8a4b0f549005c2271b70ff8237a86960edb920107', 'Costochondral joint sprain', 'subtype_costochondral_joint_sprain_d8cfc332b2', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2262', '31ab67972542dc1d39fb53b667874da7fa42d31d2d62c629774cb03327c053a4', 'Lisfranc sprain with associated fracture', 'subtype_lisfranc_sprain_with_associated_fracture_1e974a4a3d', 'dx_lisfranc_injury_a82b5577c5', 'Lisfranc injury', 'accepted_deterministic'),
  ('2263', '14303c1f0baaab880a915758085c7e7b8a8db961be0ee70e595920b0bfe4c095', 'Buttock bruising or haematoma', 'subtype_buttock_bruising_or_haematoma_1ac8459681', 'dx_buttock_contusion_46ae636fd7', 'Buttock contusion', 'accepted_deterministic'),
  ('2264', '1d7142eb77644c8e4a724250c41d37c07b2625d5bee8d89608fa92b82e8be6e7', 'Tibial bone bruise', 'subtype_tibial_bone_bruise_7f5f7b3e9c', 'dx_tibial_bone_contusion_d98bda7b76', 'Tibial bone contusion', 'accepted_deterministic'),
  ('2265', '2bdd673030a8ee44b648f351f8ac7abc5af37736ec0ef724384cfc24a92917f8', 'Neck muscle strain', 'subtype_neck_muscle_strain_0413223767', 'dx_neck_muscle_injury_500aa507c9', 'Neck muscle injury', 'accepted_deterministic'),
  ('2266', '935ea59cf6f9f947786cb9351ec45f14c927b7245156d90f07c2cd88ec967746', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2267', 'af4385a2c1622918ef742b2d19899a3f37d3cd9d53c81a7757eb9ce032a5fe9d', 'Popliteus tendinopathy/strain', 'subtype_popliteus_tendinopathy_strain_27deaa0d59', 'dx_popliteus_injury_0ac29f0573', 'Popliteus injury', 'accepted_deterministic'),
  ('2268', '3c8509524d97012aafd615e26bca389000c003813d21cf0f0a640d8842a957da', 'Knee MCL contusion', 'subtype_knee_mcl_contusion_e9be973f04', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('2269', '7538c525a4070b7282c200726f9888f694fd76d64f72a2c0126b9b664a81be6f', 'Brachial plexus traction injury/burner/stinger', 'subtype_brachial_plexus_traction_injury_burner_stinger_29eb517979', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury', 'accepted_deterministic'),
  ('2271', '4c9b5569e7d27b6bade23f1efb375afab51c69d6e143e75d52ec859991969013', 'Synovitis of midfoot joints', 'subtype_synovitis_of_midfoot_joints_2c4d6d99e5', 'dx_midfoot_synovitis_f3756228a1', 'Midfoot synovitis', 'accepted_deterministic'),
  ('2272', '8f0dcee4b28ebfb0dbdccaf1ddc65aa39e5e6885d3c7f5557f97f5a857a442d1', 'Elbow laceration', 'subtype_elbow_laceration_66e6e36448', 'dx_elbow_laceration_66e6e36448', 'Elbow laceration', 'accepted_deterministic'),
  ('2273', 'fe36f49227d4ba1049581f616bf61882e184765a5a55de4ad4383133a6e14c76', 'Buttock bruising or haematoma', 'subtype_buttock_bruising_or_haematoma_1ac8459681', 'dx_buttock_contusion_46ae636fd7', 'Buttock contusion', 'accepted_deterministic'),
  ('2274', 'a1d9528ef038a8098617a999a6ba8bfaf587a73730c52326dcc6477c9ad3894f', 'Quadriceps tendon strain', 'subtype_quadriceps_tendon_strain_8fa7cff475', 'dx_quadriceps_tendon_injury_08ea99efaf', 'Quadriceps tendon injury', 'accepted_deterministic'),
  ('2275', '13f217c8ef35100fbc5c748e5d1360b1c3f65c90adcb1d058b9922ca279debda', 'Chronic Shoulder instability', 'subtype_chronic_shoulder_instability_4d091b8deb', 'dx_shoulder_instability_2b9f54f442', 'Shoulder instability', 'accepted_deterministic'),
  ('2276', 'd588f384456ff3a26eeff8b6417db603e04c6ea86e980708db16c61f8eb65fc8', 'Distal quadricep haematoma', 'subtype_distal_quadricep_haematoma_01c745cc46', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2277', '76c82617bd0f035d29f5d68fdd7dac46688c1c0383089c7788303b951215683a', 'Lumbar pain or injury, not otherwise specified', 'subtype_lumbar_pain_or_injury_not_otherwise_specified_d98060910b', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('2278', '138f47ac2177ad231f21bf6d918fed502bd3d0db7b4382b3168fcca50c4db535', 'Supraspinatus tendon injury of the shoulder', 'subtype_supraspinatus_tendon_injury_of_the_shoulder_3b7793bcd3', 'dx_supraspinatus_tendon_injury_3840a1f333', 'Supraspinatus tendon injury', 'accepted_deterministic'),
  ('2286', '8582fba133c5fccd1bf87928d63a4c650c9b940e57c5f648d41a31f99d5ed0be', 'Conjunctival foreign body of the eye', 'subtype_conjunctival_foreign_body_of_the_eye_f9b1910993', 'dx_eye_trauma_0bcdc22eb2', 'Eye trauma', 'accepted_deterministic'),
  ('2289', '8159d1eaa098d716621e8394d5e4b39aab724255d973d7f2fd30d75ea43a8337', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('2291', 'b187159c73083681dddf72add5fb2311eeb04f8c9a35233dffabf71ce751e2cd', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('2293', 'eb302a20bf6963ae50888c2559676c921de73cba197a62f2a0a172684d611305', 'Knee Sprains/Ligament Injuries', 'subtype_knee_sprains_ligament_injuries_bc9c2670dd', 'dx_knee_ligament_injury_unspecified_7ab630d44d', 'Knee ligament injury, unspecified', 'accepted_deterministic'),
  ('2294', '55bf837f4aa4fbd789ffd1b442dbd976dd1154ab0d88764aedd97faf94ff6cfc', 'Stress reaction of the inferior pubic ramus', 'subtype_stress_reaction_of_the_inferior_pubic_ramus_da2528735a', 'dx_pubic_bone_stress_reaction_ee1dc63e02', 'Pubic bone stress reaction', 'accepted_deterministic'),
  ('2296', '3fc25d71c9da0d10cd153a757df84d4caf0d78b46134f14df08a6d722cbfa7af', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2297', '1dcb7fbd616b237fa014bf3764f10a979d065ec4cf02460024f5d48dbf0ba760', 'Brachial plexus traction injury/burner/stinger', 'subtype_brachial_plexus_traction_injury_burner_stinger_29eb517979', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury', 'accepted_deterministic'),
  ('2298', 'd1ab6ef87031334ec428a4381a5f112b74d5c205607afdc0144f397d0f9400f9', 'Other quadricep strain', 'subtype_other_quadricep_strain_d8561f4b63', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2299', '7cedd1bca40c5f6aafce4539c35a549de532c90cc7cafeb6db5bf1cb433de28d', 'Brachial plexus traction injury/burner/stinger', 'subtype_brachial_plexus_traction_injury_burner_stinger_29eb517979', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury', 'accepted_deterministic'),
  ('2300', 'f6d013658aea03315e8ae3d39504171d3e2d2bec36feab691bcd9ba28579234f', 'Ear trauma', 'subtype_ear_trauma_7f4620effe', 'dx_ear_injury_190079a2d0', 'Ear injury', 'accepted_deterministic'),
  ('2301', '57ec1863f4f24be4f04c86aa2d24051cecef332ec964ace08b7ba9f3f16be169', 'Adductor longus strain', 'subtype_adductor_longus_strain_dd1eac51f6', 'dx_adductor_muscle_injury_97164c9b14', 'Adductor muscle injury', 'accepted_deterministic'),
  ('2302', '701870c681f9ff7167a75599f0182ede5687e1ad4f65274d642729352394d0ed', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('2303', 'b91dacd95a3449735f2a3d7ddcbab3a139ba74fcd0d5066704d7e5940d82c295', 'Acute shoulder subluxation', 'subtype_acute_shoulder_subluxation_705b818f24', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('2304', '05f060b89f5e4d1607b7082a80ca5520e3f20ba752ff07f05beb27ec8e554ed5', 'Lumbar pain or injury, not otherwise specified', 'subtype_lumbar_pain_or_injury_not_otherwise_specified_d98060910b', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('2307', '6289dca6452bb21f58a29de260de665848acaa4c7966c419ee8387c66503b9b6', 'MCL rupture knee', 'subtype_mcl_rupture_knee_54556835d2', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('2308', '1ade50f7e219ed3cb97f60365e76edf3d8fe89fb1e5c640bcfe0a5de04cb1dde', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('2309', 'a6605817c8e8a611ede2cc055c17ce3eb9437134ff24117aeeeacc725b155043', 'Partial PCL tear', 'subtype_partial_pcl_tear_ba3692c716', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury', 'accepted_deterministic'),
  ('2310', 'ac2e4c956e18dc1c511230cc5fa991cfa31d8cf097e95e42b053ddcda287cf6b', 'Foot contusion/haematoma', 'subtype_foot_contusion_haematoma_edd1025815', 'dx_foot_contusion_6c8a5bb721', 'Foot contusion', 'accepted_deterministic'),
  ('2311', 'c0f1ef8caaee29f28e03e2a65f6fefdb71c61436b76ca0b26a32b7e90bb0672f', 'MCL strain/rupture with chondral/meniscal damage knee', 'subtype_mcl_strain_rupture_with_chondral_meniscal_damage_knee_defdd9b212', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('2312', '319f5aff1c97b7f7dd6199d8ca4e2b7a5ff5ccdaf39e5f871a29f15a25252317', 'Sprained/jarred wrist joint', 'subtype_sprained_jarred_wrist_joint_7ec711f5b5', 'dx_wrist_injury_d94414e2c6', 'Wrist injury', 'accepted_deterministic'),
  ('2328', '8600c79ae5d8f25fbaa3aa2e8cfcaddf729c1cfb3216b8fc74c5cbd116d58594', 'Wrist and hand pain or injury, not otherwise specified', 'subtype_wrist_and_hand_pain_or_injury_not_otherwise_specified_0b130e1f85', 'dx_wrist_or_hand_pain_57c9958c78', 'Wrist or hand pain', 'accepted_deterministic'),
  ('2329', 'f2607bb3ed321e16be1d60723d46ee80fb06674f007bc16c4a095084c1a99b7e', 'Thumb sprain', 'subtype_thumb_sprain_730d144cbe', 'dx_thumb_sprain_730d144cbe', 'Thumb sprain', 'accepted_deterministic'),
  ('2330', '60ce4a9bf2c447cae32eaeab2eae5497bf9341fe2c79fbaae9937a2fca5d0167', 'Ankle contusion/haematoma', 'subtype_ankle_contusion_haematoma_dda81acafa', 'dx_ankle_contusion_beb9f51162', 'Ankle contusion', 'accepted_deterministic'),
  ('2331', '60aace9e115118065f1cd41b407f81fe33760c6788584893a2666f8596b0eb14', 'Shoulder contusion/haematoma', 'subtype_shoulder_contusion_haematoma_1f687995cb', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion', 'accepted_deterministic'),
  ('2332', 'c235721450393aa02723cba9d4e88772a646838b43a8cbf4af571942c5af02c2', 'Lumbar pain or injury, not otherwise specified', 'subtype_lumbar_pain_or_injury_not_otherwise_specified_d98060910b', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('2343', 'aecfd3b1712322d2f5bfa5c1dbcdce350d009bfdfa1598df1a3b61220414c02b', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('2344', '0779f15f91dc1141f1f4657e1d58785d3416ab7072fc3487b5e60b5adaf817e8', 'Gastrocnemius muscle injury or strain', 'subtype_gastrocnemius_muscle_injury_or_strain_367914bc2d', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'accepted_deterministic'),
  ('2345', 'fda91740e5cf5451064a14f74963822768c1f6f025553f8cf30e503262411eb9', 'Pectoralis major muscle strain', 'subtype_pectoralis_major_muscle_strain_5887d37d12', 'dx_pectoral_muscle_injury_981511cfe1', 'Pectoral muscle injury', 'accepted_deterministic'),
  ('2346', 'b63eb89bb91c66a9d813648230a1fb91702bc933f393d4a1b823ecec7541fe00', 'Knee contusion/haematoma (extraarticular)', 'subtype_knee_contusion_haematoma_extraarticular_19a33609a2', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('2347', '93504dab94cc2e654d63cebbbb18b8691bff76d1ec13b4e85e9ed9c556a5529b', 'Sprained/jarred elbow', 'subtype_sprained_jarred_elbow_a336ca7456', 'dx_elbow_injury_7100f71f81', 'Elbow injury', 'accepted_deterministic'),
  ('2348', '30646fbc32061af68215d413806ae853008a61e87308deced458f7b469d8bd55', 'Shoulder contusion/haematoma', 'subtype_shoulder_contusion_haematoma_1f687995cb', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion', 'accepted_deterministic'),
  ('2349', '339b5bd541fb65ef469d767a5b14f604127b3dc867c3e094e2a12e5a1cf51ac9', 'Dislocation of great toe MTP joint', 'subtype_dislocation_of_great_toe_mtp_joint_6023b11b48', 'dx_great_toe_mtp_dislocation_19361d8e58', 'Great toe MTP dislocation', 'accepted_deterministic'),
  ('2350', '83acd9afc693f97a3a9717b70c0aef8ce656e75b0f0aeb3dbd5fa87f9831ebce', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2352', 'a2121f8cc03ddfe020a3f1f95041d5e6f32d9adcdd0451b017f88a128e1d91c0', 'Rotator Cuff muscle injury', 'subtype_rotator_cuff_muscle_injury_79ec49deb3', 'dx_rotator_cuff_injury_0744f75c4c', 'Rotator cuff injury', 'accepted_deterministic'),
  ('2354', '214177e05b8e43fc8fbc6d6b3dfec528f48de64793f0c15a08ae66c8fd1e628c', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2357', '85a9ed8254b0824dc8ed99c0410705e3308b71c7187c04503f5fa23fd715ec3d', 'Lip laceration requiring suturing', 'subtype_lip_laceration_requiring_suturing_ac314964e5', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2358', 'd81846e5f48fcf042f6bc0e58aea519704ac04d5ac8345f225f5a3a2a82f3e64', 'Nose fracture', 'subtype_nose_fracture_7b8a158870', 'dx_nasal_fracture_a291a11f04', 'Nasal fracture', 'accepted_deterministic'),
  ('2360', '68cbd8b02ec513a60cfc535c363d5a92b9381fce4432f5fd44372b7717958a57', 'Gluteal muscle strain', 'subtype_gluteal_muscle_strain_9513fdc6a7', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury', 'accepted_deterministic'),
  ('2361', '8c8f3601ca055201b3679242bcae2219d332b23105b94fa56713d292af1ab96c', 'Calcaneal bursitis (pump bump)', 'subtype_calcaneal_bursitis_pump_bump_ddfe297857', 'dx_heel_bursitis_d80d084f22', 'Heel bursitis', 'accepted_deterministic'),
  ('2362', '38fd1535e0514c52794e0f66498f32b4db05d79ed3e1b20375db1d3736b3578b', 'Anteroinferior shoulder dislocation', 'subtype_anteroinferior_shoulder_dislocation_0e1ba032fe', 'dx_shoulder_dislocation_2067688fdd', 'Shoulder dislocation', 'accepted_deterministic'),
  ('2363', 'fc418f0f6d8e0c8735a5f77308860696d508ba358c6a5509d58a381b7280b54a', 'Distal quadricep haematoma', 'subtype_distal_quadricep_haematoma_01c745cc46', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2364', '167ca6c82177cc6b11a61ddc7a4c0f4db712eba413dee0742384d5133d5c306b', 'Facial laceration requiring suturing', 'subtype_facial_laceration_requiring_suturing_40a8df9bf4', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2365', '78f71f78854dfe1d86fe63ab98c6875aeed7c6378449edc6b03de40e3b1fb040', 'Distal quadricep haematoma', 'subtype_distal_quadricep_haematoma_01c745cc46', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2366', '4b18c9107aa47b3068d268aef0b97ff4dbac2230eb6702696963ce940801fc75', 'Facial laceration requiring suturing', 'subtype_facial_laceration_requiring_suturing_40a8df9bf4', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2367', '298d202e6f7dd70a5654180b233a6d4e0f579b93f69df87ec09573f2f74e09dc', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2368', '6b64578537db8a67c77f5a669a2f23f9d2ff4b42af65c32434708d5d980cf7d3', 'Elbow ulna/medial collateral ligament (UCL) strain or tear', 'subtype_elbow_ulna_medial_collateral_ligament_ucl_strain_or_tear_ab4c438f84', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury', 'accepted_deterministic'),
  ('2369', 'd974edd871b3653f4c980cdbd638587fb0aa8a1768299a409126fc32ac0b2d94', 'Achilles tendon rupture', 'subtype_achilles_tendon_rupture_6b59cc3783', 'dx_achilles_tendon_rupture_6b59cc3783', 'Achilles tendon rupture', 'accepted_deterministic'),
  ('2370', '30196469e7ae876f9531a65c6c9cdd51cf9be2c9a5d4ec5e385665f3ed21fc56', 'Scalp laceration', 'subtype_scalp_laceration_50be43ed71', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2371', 'e719b37cb7f9bc3ffe1ea54ded2615d676c2f85a660de2f8a963213b28a79c53', 'Forearm contusion/haematoma', 'subtype_forearm_contusion_haematoma_3be5d37b72', 'dx_forearm_contusion_ea321e8e45', 'Forearm contusion', 'accepted_deterministic'),
  ('2375', '760fa4a5e26edd4cd418dc331a3e3f8bae410e18558c5c19e0a7067470455738', 'ACL rupture', 'subtype_acl_rupture_f84927fab2', 'dx_acl_injury_4b8eb47e96', 'ACL injury', 'accepted_deterministic'),
  ('2376', '23ab0af865a904d8f5b0394b4a97dfe0d4f1fcee0773955623304e7867c19f16', 'Knee contusion/haematoma (extraarticular)', 'subtype_knee_contusion_haematoma_extraarticular_19a33609a2', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('2380', '5799aa4a47ea0fd16faa6281bad4cb3c8494afb2c2f1b69d6b09d2221d142895', 'Scalp laceration', 'subtype_scalp_laceration_50be43ed71', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2382', 'd9b486e4814a5b36e96d941b624eb671852396490bd3cbf0609f8cc8c450721f', 'Neck soft-tissue dysfunction', 'subtype_neck_soft_tissue_dysfunction_419ddfbf3d', 'dx_neck_soft_tissue_dysfunction_8f80031021', 'Neck soft tissue dysfunction', 'accepted_deterministic'),
  ('2383', 'cd048e02aa8acefe9f292b1a8042c0b5c5f69629eb5fa75f770ef1a8a67f294e', 'Whiplash/neck sprain', 'subtype_whiplash_neck_sprain_3597569aa7', 'dx_neck_sprain_or_whiplash_404e63fe9e', 'Neck sprain or whiplash', 'accepted_deterministic'),
  ('2384', 'b2e6f4598b9e0d688d0d961fad1a9e9504c0894bdc08bfa3272940249d3e4db5', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2385', '22b5c746bd93116fd5f6e9aeba4cf3c328aad5d6074aa9cbedbd5d2976a04e27', 'Ear trauma', 'subtype_ear_trauma_7f4620effe', 'dx_ear_injury_190079a2d0', 'Ear injury', 'accepted_deterministic'),
  ('2386', 'c53fe1845a8218cc01fde690da704a3d983c79f5ae78fabd47224f379ecd37d8', 'Scalp bruising/haematoma', 'subtype_scalp_bruising_haematoma_5ff45a6916', 'dx_scalp_contusion_or_haematoma_3665ef31fa', 'Scalp contusion or haematoma', 'accepted_deterministic'),
  ('2387', '089d1a1a29e149ccc4c88a7effeccb260bffc660108aae7115997dfd52850b41', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2388', '473abb4ce4636cf2411d603353a8a6ab41063048a0ef9fd9d2070432ad9d8665', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2391', '6d9b2ce5e3aa6d05adff556c20c80c2d4a0d89d277299d0dd0cc3586925a4413', 'Dislocated patella', 'subtype_dislocated_patella_26b8cc45c3', 'dx_patellar_dislocation_0c3c5e687e', 'Patellar dislocation', 'accepted_deterministic'),
  ('2392', '503d099a08af9adfb7e8cb8cabaa0ec99c1f08611fc4a691b566c1786650212d', 'Grade 1 MCL tear knee', 'subtype_grade_1_mcl_tear_knee_6a8ace9800', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('2394', '68aa8b7d1968dcf874a0933e75ec72195ec8eda79c6feafdf9c893952f5a9643', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('2395', '0086b710e99db746c6038dae65f2ab850dff62b0537e203f517201cae34f130e', 'Lip laceration requiring suturing', 'subtype_lip_laceration_requiring_suturing_ac314964e5', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2396', '173989e965189e8330fdc770cc03c42e8b2be8eb7375c1e54d0bf9c18e1ef8b9', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('2397', '18bcaad97c1784ed17e59e0b8df2512ef967c8ad2f7f555b0fbb93de8ec241eb', 'Costochondral joint sprain', 'subtype_costochondral_joint_sprain_d8cfc332b2', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2399', 'f961e9c0b7d0ebacac038ace784503c9df2990ed350b7ef71efd83fbabf39d7f', 'Eye injury/trauma', 'subtype_eye_injury_trauma_c57dff0d52', 'dx_eye_trauma_0bcdc22eb2', 'Eye trauma', 'accepted_deterministic'),
  ('2400', '1e6e63c90482aaabf261e34f11da208dcf2665dcb4d32b794dcf2f78692520a9', 'Scalp laceration', 'subtype_scalp_laceration_50be43ed71', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2402', 'f1d408355992a1705e1561503a6eae08f0e4bbe85453b9243ecf1698d80208bf', 'Blisters heel', 'subtype_blisters_heel_352c6952ef', 'dx_heel_blister_95bb983137', 'Heel blister', 'accepted_deterministic'),
  ('2403', '72d236ceb846987b09da1bd2fc27c3c4b570b4f14cd539a608f7923ebc9f7240', 'Quadriceps strain or tear', 'subtype_quadriceps_strain_or_tear_17ff226482', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2407', '83cac072a5dcbb3a0a1c1262af56e6bd8b843dd6ae62ee3b202c4be7eb2e69bc', 'Shoulder contusion/haematoma', 'subtype_shoulder_contusion_haematoma_1f687995cb', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion', 'accepted_deterministic'),
  ('2408', '54438c869b9737e8adb25e5488e01a08e2607b23a570846fc4196acbc524e8eb', 'Sprained toe/''turf toe''', 'subtype_sprained_toe_turf_toe_8130fe4d55', 'dx_great_toe_injury_71c02ad835', 'Great toe injury', 'accepted_deterministic'),
  ('2409', '88a7f14796de586a10f4fdd8161c17396005b66b66ad461a5494735ae7945099', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2410', 'ffe9588f4f2cf1553c93577444b5f24b90cfefcbf98ccc0968f8c409d96e0e2d', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('2411', 'e98a03f6736792055dfcf066d78bc36e2c146b0e6d281a275a3e70e5b184991b', 'Other Upper arm soft tissue bruising/haematoma', 'subtype_other_upper_arm_soft_tissue_bruising_haematoma_587fa7251d', 'dx_upper_arm_soft_tissue_contusion_or_haematoma_9e41a8da30', 'Upper arm soft tissue contusion or haematoma', 'accepted_deterministic'),
  ('2412', '27ab046f7147c288abb311d012076308fb1914996313a6ab410dfc5d7aa2c617', 'Pes anserine bursitis of the knee', 'subtype_pes_anserine_bursitis_of_the_knee_4a77d20615', 'dx_pes_anserine_bursitis_3af1f08842', 'Pes anserine bursitis', 'accepted_deterministic'),
  ('2413', '51a3e2024961f33f2c8b7ad14107b6b4600c45bb3e9c09531440a39dc2d792d4', 'Brachial plexus traction injury/burner/stinger', 'subtype_brachial_plexus_traction_injury_burner_stinger_29eb517979', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury', 'accepted_deterministic'),
  ('2414', '5794a50692d80dd16a367c72720055032bba74b410ad012da1b8026d76b9e9b8', 'Chest Wall Soft Tissue Bruising/Haematoma', 'subtype_chest_wall_soft_tissue_bruising_haematoma_bd1a62550f', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2415', 'ae1d9530df78587eb971b1cffb5335877a5f355836e129e35ecb8b920add9da4', 'Neck contusion/haematoma', 'subtype_neck_contusion_haematoma_d4fc2fd301', 'dx_neck_contusion_7f04c7cc90', 'Neck contusion', 'accepted_deterministic'),
  ('2416', 'c46d274acd64cf83568357e11f724a4466e0ad0771364f934b36ceb78d497dbf', 'Eyelid laceration requiring suturing', 'subtype_eyelid_laceration_requiring_suturing_8f76e0ddf1', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2419', 'c55bfcac85af7574a26422b3cdd7b5a2b11bd9231233a0ab288915e5b9df385a', 'Complication of knee laceration or abrasion', 'subtype_complication_of_knee_laceration_or_abrasion_6e5f740895', 'dx_wound_infection_complication_5415c9f38d', 'Wound infection/complication', 'accepted_deterministic'),
  ('2420', '2962d90087e5d13fb3448283fe451bc8bce6824a6d374a4e776ea56c254ba4be', 'Trochanteric bursitis', 'subtype_trochanteric_bursitis_32cf79258b', 'dx_trochanteric_bursitis_32cf79258b', 'Trochanteric bursitis', 'accepted_deterministic'),
  ('2421', '04e014e2fe9e619b1966021aa8a83696bdda6680a4a66e9f16de7fe61454ef95', 'Complication of knee laceration or abrasion', 'subtype_complication_of_knee_laceration_or_abrasion_6e5f740895', 'dx_wound_infection_complication_5415c9f38d', 'Wound infection/complication', 'accepted_deterministic'),
  ('2422', 'a1562aec909f4a09e072c25afff3a171af860d5b9e9be0b73e0053590a08a359', 'Patellar tendinopathy', 'subtype_patellar_tendinopathy_3ea4d4d1bf', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'accepted_deterministic'),
  ('2424', '62c16bb29397bc12be41e5383e41b4ff35dbc8d74055d41d87d64911e33c9152', 'Knee contusion/haematoma (extraarticular)', 'subtype_knee_contusion_haematoma_extraarticular_19a33609a2', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('2425', '0d0a71f2c9dd48711f0890c8a5e8f78b72b8f3050bcd1f1656738bbbb576edf6', 'Neck soft-tissue dysfunction', 'subtype_neck_soft_tissue_dysfunction_419ddfbf3d', 'dx_neck_soft_tissue_dysfunction_8f80031021', 'Neck soft tissue dysfunction', 'accepted_deterministic'),
  ('2426', '2a2133e85a7670805f6e15dc5e4731dcf145d5a02ca94ab7ead1f03801dc4473', 'Proximal biceps tendon injury', 'subtype_proximal_biceps_tendon_injury_121c1b2433', 'dx_biceps_tendon_injury_cbd11d2125', 'Biceps tendon injury', 'accepted_deterministic'),
  ('2427', 'aa4de56a0f6aeaf09f60e7523c8ff955abb590d1b6368e272e1419b273568c9d', 'Trochanteric bursitis', 'subtype_trochanteric_bursitis_32cf79258b', 'dx_trochanteric_bursitis_32cf79258b', 'Trochanteric bursitis', 'accepted_deterministic'),
  ('2428', '2dda95c3c39a0cc93977757ef464fc730d63966f0cb0d846977cfb7fbed6c2d3', 'Grade 1 MCL tear knee', 'subtype_grade_1_mcl_tear_knee_6a8ace9800', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('2429', 'bfbcfe84f083ed6f7e6a0b7f1f66ab2793f4b7ff3c4899dba6a5bec7dffdbe36', 'Buttock Soft Tissue Bruising/Haematoma', 'subtype_buttock_soft_tissue_bruising_haematoma_21fdd2d181', 'dx_buttock_contusion_46ae636fd7', 'Buttock contusion', 'accepted_deterministic'),
  ('2430', '4166c3dffd5e4c3c932d6a87c1dc3f4ed72533a48ac957afab60e65b93023435', 'Neck soft-tissue dysfunction', 'subtype_neck_soft_tissue_dysfunction_419ddfbf3d', 'dx_neck_soft_tissue_dysfunction_8f80031021', 'Neck soft tissue dysfunction', 'accepted_deterministic'),
  ('2431', 'c2927e682781d3411c7032567195e181b408124cef7e7f1533bee593cb63b235', 'Bruised ribs/chest wall', 'subtype_bruised_ribs_chest_wall_0c223ac8bd', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2432', 'f482cee99b5fdec368690b0238376db9e9b5c779bb6868b922c168d1dea6335f', 'Brachial plexus traction injury/burner/stinger', 'subtype_brachial_plexus_traction_injury_burner_stinger_29eb517979', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury', 'accepted_deterministic'),
  ('2437', '2749b07c11b053fe7f4ff428438f016d78106e4dbf3eb5bcd31f4cba21c83946', 'Lumbar pain or injury, not otherwise specified', 'subtype_lumbar_pain_or_injury_not_otherwise_specified_d98060910b', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('2438', '3b5b751cfffeb763490e2bf43e29035c0d2b68dd175181633c813d0244cc2e26', 'Foot Muscle Strain/Spasm/trigger Points', 'subtype_foot_muscle_strain_spasm_trigger_points_32f0948947', 'dx_foot_muscle_strain_spasm_trigger_points_32f0948947', 'Foot Muscle Strain/Spasm/trigger Points', 'identity_group'),
  ('2454', '8e119eecd1cbf1e52575e253775251bd75dee04bd255762600a5d3220664b455', 'Lumbar pain or injury, not otherwise specified', 'subtype_lumbar_pain_or_injury_not_otherwise_specified_d98060910b', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('2455', '66863d5681819894a4429242ca684f78d8ff16fe2cab977c57822df90fdbe651', 'Supraspinatus tendon tear partial thickness', 'subtype_supraspinatus_tendon_tear_partial_thickness_0843f7001c', 'dx_supraspinatus_tendon_injury_3840a1f333', 'Supraspinatus tendon injury', 'accepted_deterministic'),
  ('2456', 'ac5e9bdfb5befd3506335f45e3e2e3117ecc82c4cf087af95be1bc184e3f757a', 'Neck muscle soreness/spasm/torticollis', 'subtype_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'dx_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'Neck muscle soreness/spasm/torticollis', 'identity_group'),
  ('2458', 'cb374f0ff15c005436bbde3044886e3c02df574a5152aa4a3cb3014aef96c3ed', 'Disc prolapse/disruption', 'subtype_disc_prolapse_disruption_100f0c1c3f', 'dx_spinal_disc_injury_e3b980b6b8', 'Spinal disc injury', 'accepted_deterministic'),
  ('2459', '6b71851e5934125e6cebc778ba99de35bf971344f2c86016d9a77b0ada2cbb83', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2464', 'f12b30f431f38c78d958ed072a944aa28cfe030fb11c4d7b34490fa23471913e', 'Knee joint effusion, cause undiagnosed', 'subtype_knee_joint_effusion_cause_undiagnosed_dd4a697270', 'dx_knee_joint_effusion_65cd9bd317', 'Knee joint effusion', 'accepted_deterministic'),
  ('2465', 'b7e8d65327152edfda08a0a09131dd7181cf6005f573d4f617c6026740ec500b', 'Facial laceration requiring suturing', 'subtype_facial_laceration_requiring_suturing_40a8df9bf4', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2466', '48f2f697269ece54132271f357d26b8c2b1a9abc8e9ae9d4f255e7f8c970484a', 'Tibialis posterior strain', 'subtype_tibialis_posterior_strain_5b1038e8f3', 'dx_tibialis_posterior_tendon_injury_8ddfcac54e', 'Tibialis posterior tendon injury', 'accepted_deterministic'),
  ('2467', 'bec472518b15784f2b9146131ebb784fc2ad1d03d0a0fe83b74a881d0d65c76f', 'Disc prolapse/disruption', 'subtype_disc_prolapse_disruption_100f0c1c3f', 'dx_spinal_disc_injury_e3b980b6b8', 'Spinal disc injury', 'accepted_deterministic'),
  ('2468', '7c030df8b3a8a56fbdfb5ea32a4946f4a489bb07cfd65d904fd60f3e54f19171', 'Biceps muscle strain', 'subtype_biceps_muscle_strain_9122d2b9c0', 'dx_biceps_muscle_injury_3a5679b9a5', 'Biceps muscle injury', 'accepted_deterministic'),
  ('2469', 'e7816e0e872b2a337b5a52898147f761169a10a650305f963f4e7b3c33fb56f2', 'Facial laceration requiring suturing', 'subtype_facial_laceration_requiring_suturing_40a8df9bf4', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2470', '8a8711cb75d879450c6dbb60aa0f5e6ffaaeb73b8c398036d2b3999cdd30b6e0', 'Acromioclavicular (A/C) joint sprain', 'subtype_acromioclavicular_a_c_joint_sprain_75f6a9a659', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('2471', '03bbd1b35b2f9044d197c6d1918abda1bb67dc655401dbd17d92679112546fdb', 'Plantar heel pain (fasciitis/strain/calcaneal spur)', 'subtype_plantar_heel_pain_fasciitis_strain_calcaneal_spur_7ea3631a44', 'dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b', 'Plantar heel pain/fasciopathy', 'accepted_deterministic'),
  ('2472', '1532f4da600715c721dbb1410a303cf5706441e255514e436b21b844b597567f', 'Facet Joint/Neck Ligament sprain', 'subtype_facet_joint_neck_ligament_sprain_369f0afd14', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder', 'accepted_deterministic'),
  ('2477', '93d1fd84902c3ee79071ccacaad0d7480fb8c4cede347ffa96d18608dcd09a9e', 'Pes anserine bursitis of the knee', 'subtype_pes_anserine_bursitis_of_the_knee_4a77d20615', 'dx_pes_anserine_bursitis_3af1f08842', 'Pes anserine bursitis', 'accepted_deterministic'),
  ('2482', '11c46c8de1ba00d51d74261f07853589b7c38f5aa40c351e8ed2bb2bf0eecd4a', 'Calf laceration/abrasion', 'subtype_calf_laceration_abrasion_72a78a404f', 'dx_lower_leg_laceration_5e3fbc19d5', 'Lower leg laceration', 'accepted_deterministic'),
  ('2483', '63a437278f8d4da705b5c871e23e89ff793a6af1456a7af24eb5f5d57f8f9176', 'Supraspinatus tendon tear partial thickness', 'subtype_supraspinatus_tendon_tear_partial_thickness_0843f7001c', 'dx_supraspinatus_tendon_injury_3840a1f333', 'Supraspinatus tendon injury', 'accepted_deterministic'),
  ('2484', 'e956387af8d1b8d840cd961483082c26e7fbcb8d8654074911612851bf9d72d9', 'Calf laceration/abrasion', 'subtype_calf_laceration_abrasion_72a78a404f', 'dx_lower_leg_laceration_5e3fbc19d5', 'Lower leg laceration', 'accepted_deterministic'),
  ('2485', '009a8e157d68c0bd93af97064f63591cb3d884bc7451194db034b8c91224b7ce', 'Calf laceration/abrasion', 'subtype_calf_laceration_abrasion_72a78a404f', 'dx_lower_leg_laceration_5e3fbc19d5', 'Lower leg laceration', 'accepted_deterministic'),
  ('2486', '34e94a8cc5d216abfe0ba652ef1b73c6ce45e4754537db9088b35907c2d003e0', 'Rectus femoris strain', 'subtype_rectus_femoris_strain_5670ca194b', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2487', 'b0e3dea505c7651ea2d3a824e5ef636987b414f968935d0e6e8359c7bb1e8eb1', 'Biceps muscle strain', 'subtype_biceps_muscle_strain_9122d2b9c0', 'dx_biceps_muscle_injury_3a5679b9a5', 'Biceps muscle injury', 'accepted_deterministic'),
  ('2488', 'ebe65c7d0817b7a5ab4f246a830af91ea1105c8abd2b373473da1997fbc07c9e', 'Distal quadricep haematoma', 'subtype_distal_quadricep_haematoma_01c745cc46', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2489', '04b13dad1ebbd32a25527f0d10f36c2a0c22b18de646f32e97f0879e51c038cd', 'Thumb ulnar collateral ligament (UCL) rupture at MCP joint (skier''s thumb)', 'subtype_thumb_ulnar_collateral_ligament_ucl_rupture_at_mcp_joint_skier_s_thumb_1db84f53fe', 'dx_thumb_ucl_injury_00b846b6dd', 'Thumb UCL injury', 'accepted_deterministic'),
  ('2490', 'c334ef83f87b1ac845e9a4cdd1dd0a33b16a5544b5a7dc849052e3bd11b0e918', 'Thumb bruising/haematoma', 'subtype_thumb_bruising_haematoma_97324f0de1', 'dx_thumb_contusion_or_haematoma_7a219de27a', 'Thumb contusion or haematoma', 'accepted_deterministic'),
  ('2491', '7a0a1d0f86311878c8e3d586e038d3222b145e006f6d799f16cb37fda7a7b4f0', 'Calf laceration/abrasion', 'subtype_calf_laceration_abrasion_72a78a404f', 'dx_lower_leg_laceration_5e3fbc19d5', 'Lower leg laceration', 'accepted_deterministic'),
  ('2493', '350cd657d36c85640a96edabe93b025af5a5453f43b374080d45273d1f54153d', 'Lumbar pain or injury, not otherwise specified', 'subtype_lumbar_pain_or_injury_not_otherwise_specified_d98060910b', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('2497', '5b83a234169958620b82e0f0d819c45b08dee5b75b60725c09ec8a3096c91892', 'Tibial bone bruise', 'subtype_tibial_bone_bruise_7f5f7b3e9c', 'dx_tibial_bone_contusion_d98bda7b76', 'Tibial bone contusion', 'accepted_deterministic'),
  ('2498', '1215d54b8da1034837a38000e24cd1903a7640eaec968d86d1f8e1dbc478f053', 'Knee Sprains/Ligament Injuries', 'subtype_knee_sprains_ligament_injuries_bc9c2670dd', 'dx_knee_ligament_injury_unspecified_7ab630d44d', 'Knee ligament injury, unspecified', 'accepted_deterministic'),
  ('2499', 'c08cf58b4626d2825496d495dbb4ab5016d2c119c8bf6840c6dd497ac1059268', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2500', '90172616bcd39b679f7339593053a728d6b5aa5ffce6209fab87c97a9c33975b', 'Scalp laceration', 'subtype_scalp_laceration_50be43ed71', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2501', 'df9ee76c44f02fca9fcc3800bb43a09e84f3e5f562d13b40812d18c6fff95f86', 'Cervical nerve root compression/stretch', 'subtype_cervical_nerve_root_compression_stretch_6f650f0242', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('2503', '4272a41c0880e0a40ebbc16a3d02589c6542e8b46e63c5d4aa97c3cae6290fc6', 'Pectoralis major muscle strain', 'subtype_pectoralis_major_muscle_strain_5887d37d12', 'dx_pectoral_muscle_injury_981511cfe1', 'Pectoral muscle injury', 'accepted_deterministic'),
  ('2504', '2532905e067e22f96c0d29331d74e21c80d57e22c76b970087d4fde91169472a', 'Patellofemoral joint chondral pain', 'subtype_patellofemoral_joint_chondral_pain_63e8d81e49', 'dx_patellofemoral_injury_a6e2fe370a', 'Patellofemoral injury', 'accepted_deterministic'),
  ('2510', '320960668d62499f8f244a449ef1203b372cae4da24402a30d9706d26a3a815f', 'Superior Labrum Anterior and Posterior (SLAP) lesion shoulder', 'subtype_superior_labrum_anterior_and_posterior_slap_lesion_shoulder_75eead2e0c', 'dx_shoulder_labral_injury_c99b83bba8', 'Shoulder labral injury', 'accepted_deterministic'),
  ('2511', '6030f68a024b192d5183ac75f5aa25541d1b0584d48f7dc3964996743c62be29', 'Anterior sternoclavicular (S/C) joint sprain', 'subtype_anterior_sternoclavicular_s_c_joint_sprain_16f2b0b445', 'dx_sternoclavicular_joint_sprain_6316623d10', 'Sternoclavicular joint sprain', 'accepted_deterministic'),
  ('2512', '50824510649333bf51086563f87ffd69e5e5397c52dfbbc228bcc2db7887dd44', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2513', '72c0797ed407df27a95bb15892f018d063d7d7b852643c0111cb12d9c7290066', 'Costochondral joint sprain', 'subtype_costochondral_joint_sprain_d8cfc332b2', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2514', '3713a580ce0513abd34203471db7ecfb890796e63884f6650c3ce94b1bf00c54', 'Thoracic Muscle Strain/Spasm/Trigger Points', 'subtype_thoracic_muscle_strain_spasm_trigger_points_c483ca1853', 'dx_thoracic_muscle_strain_spasm_trigger_points_c483ca1853', 'Thoracic Muscle Strain/Spasm/Trigger Points', 'identity_group'),
  ('2515', '992f09cd3c35831cce90c566619ea6f411737851e12630fb1f48160c8f802176', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('2519', 'a2425333b299c96caf5f7e6866977fefa4dc01e2e7e2c126cbb6c8993a2e4d68', 'Facet Joint/Neck Ligament sprain', 'subtype_facet_joint_neck_ligament_sprain_369f0afd14', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder', 'accepted_deterministic'),
  ('2520', '5e124cde3ca08039319e34af3ad5675553aabc638820d4e1cc6a2c0f9547234a', 'Lumbar pain or injury, not otherwise specified', 'subtype_lumbar_pain_or_injury_not_otherwise_specified_d98060910b', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('2524', '909f36d9ae873663f8754b5fa2ff91a47b2c82f60d6810a477e2dd8e5c50f6e8', 'Scalp laceration', 'subtype_scalp_laceration_50be43ed71', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2525', '4b5301841ef602e40d1fd2b7d9c418b876f58b1fd0f493f434fb4c94d2416190', 'Cauliflower Ear (chronic)', 'subtype_cauliflower_ear_chronic_3c9b5064b0', 'dx_cauliflower_ear_d6361b8000', 'Cauliflower ear', 'accepted_deterministic'),
  ('2528', '1c5dd2106e65d96365cd0455165d9d3f09e72183b06f00236f6586c89700f1c3', 'Lumbar pain or injury, not otherwise specified', 'subtype_lumbar_pain_or_injury_not_otherwise_specified_d98060910b', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('2529', 'a23f1b8e5778a9abb2e3972c952b4474dd235e2a207628a4b9cae6d43c8a1c4b', 'Instability associated subacromial impingement', 'subtype_instability_associated_subacromial_impingement_0976185074', 'dx_shoulder_instability_2b9f54f442', 'Shoulder instability', 'accepted_deterministic'),
  ('2535', 'fc13bd02fd4915fb9cb8245141998afd1e22b72fec15f90b371270b92dd0e01e', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('2536', 'af08d84cf37ae9d94effb5e8ef4220df242e3c32e027247fe47dfd0fa26f81d6', 'contusion/haematoma, hip region', 'subtype_contusion_haematoma_hip_region_ffc578cee0', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma', 'accepted_deterministic'),
  ('2537', '13b21a8e175e70f00b3910e5fb91de1a05de0d62cd5672e7e2a7640d86fe621e', 'Pectoralis major muscle strain', 'subtype_pectoralis_major_muscle_strain_5887d37d12', 'dx_pectoral_muscle_injury_981511cfe1', 'Pectoral muscle injury', 'accepted_deterministic'),
  ('2538', '3b061806297b8693094de1f7fc51d6c11ad267ab5394e83d81200d9675586f8c', 'Chest Wall Soft Tissue Bruising/Haematoma', 'subtype_chest_wall_soft_tissue_bruising_haematoma_bd1a62550f', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2539', '28044865d5b52e21c3d00e748c5c20efc7996f4b5cbf2c7f432a08b83954d679', 'Eyelid laceration requiring suturing', 'subtype_eyelid_laceration_requiring_suturing_8f76e0ddf1', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2541', 'ac98ff7d5ccb35c663296cbceae31ddc4985cfcb0c9e7885505b3a2d112162cc', 'Lumbar pain or injury, not otherwise specified', 'subtype_lumbar_pain_or_injury_not_otherwise_specified_d98060910b', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('2542', '0bfaf3b13d6a1350b1c71e0f3de184eff07a9e1f387887159852ecde51d212f0', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2545', '11d8b60ae87a4178a56dd1609377d725801b04345b37bcd04542959f6daa491e', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2546', '64c95b9e2370ad0fa2f5080d3bfab815a8b70d013704acc700c94a8d161667d4', 'Acute shoulder subluxation', 'subtype_acute_shoulder_subluxation_705b818f24', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('2550', 'ff66872bc8b839138cad1a16e9426157f86553654a8d3da59e0c870da41a632d', 'Cervical Disc sprain', 'subtype_cervical_disc_sprain_98da6e06ba', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury', 'accepted_deterministic'),
  ('2551', 'd477741fbfb4ab5cc71010c8e6c38940674b4171b9a90f7aa960e1023477b4a7', 'Distal quadricep haematoma', 'subtype_distal_quadricep_haematoma_01c745cc46', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2552', 'fcf667e4a425ff8325729a1f19840ebf120a307d02668f54c16ead056220120c', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('2553', '0ba36023d85141bcaf52a8d9f543fdb04b7e8616e30d2a0f146841ba765e542a', 'Grade 1 MCL tear knee', 'subtype_grade_1_mcl_tear_knee_6a8ace9800', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('2554', '1b2a503a187a58cdb7f3ff212f7247316e5525402addfe2752e423821ec5df8e', 'Corneal Abrasion', 'subtype_corneal_abrasion_9941832ebb', 'dx_eye_trauma_0bcdc22eb2', 'Eye trauma', 'accepted_deterministic'),
  ('2555', '19ef4d9279d875a822539bfed27fae1a9deb4faa5a5fe4a6c31b3d616823277d', 'Grade 1 MCL tear knee', 'subtype_grade_1_mcl_tear_knee_6a8ace9800', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('2556', '02e6f90e267f156b77f3f4e014741ce80a5de671c12d420f4e2e08e0d124c6ff', 'Distal quadricep haematoma', 'subtype_distal_quadricep_haematoma_01c745cc46', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2574', '78c96605db5052642491b9fe11cd6f8f3f0fde9c85d3d8503c7c9c65f8446533', 'Eyebrow laceration requiring suturing', 'subtype_eyebrow_laceration_requiring_suturing_88ac45fb54', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2575', 'b847b9fb485d40ed0b2219c8f24e0270d3de4a67093a932af2b7f8826ee5abd1', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2576', 'd5004e0811e9fa15bb2c53d8adb6f2421150e4c41378eb285e0e1d8a79d71428', 'Quadriceps strain or tear', 'subtype_quadriceps_strain_or_tear_17ff226482', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2577', '829c67a479ea469aea98700f51d0b93c1c17bec11a3c43411e5af37eae7ae2ec', 'Foot contusion/haematoma', 'subtype_foot_contusion_haematoma_edd1025815', 'dx_foot_contusion_6c8a5bb721', 'Foot contusion', 'accepted_deterministic'),
  ('2581', '6d1e0b0a4c7c3adb910f211815a7fcf3674cba969300ebc0a55cd5ea455a110e', 'Nose fracture', 'subtype_nose_fracture_7b8a158870', 'dx_nasal_fracture_a291a11f04', 'Nasal fracture', 'accepted_deterministic'),
  ('2582', '2ec16112c4f813a6e94eaba32c5baed7702d65fc045885b62482a4e34e985e31', 'Knee medial collateral ligament (MCL) injury', 'subtype_knee_medial_collateral_ligament_mcl_injury_9cce43fa53', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('2583', '3672efa581314853fa2a2c9214ead5600462fd91f52cb16976f15607d9ecc9a9', 'Foot contusion/haematoma', 'subtype_foot_contusion_haematoma_edd1025815', 'dx_foot_contusion_6c8a5bb721', 'Foot contusion', 'accepted_deterministic'),
  ('2584', '73f73157e09287433f1c812e9cb3682323d9d2e16d3da02a6e9bcec2d21c86b0', 'Eye injury/trauma', 'subtype_eye_injury_trauma_c57dff0d52', 'dx_eye_trauma_0bcdc22eb2', 'Eye trauma', 'accepted_deterministic'),
  ('2585', 'c9508d4d04a5cc10fe6fbe283a9c7b9b0cd17bb615e7501e99ece78571c85c55', 'Quadriceps strain or tear', 'subtype_quadriceps_strain_or_tear_17ff226482', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2586', 'e0f3677b76c5c8b47680fe2035a414f12bebac1f00fb6559f77803ca93336878', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2588', '335fda0f3ac4e104d107e9dccf6edec2b33030f3da26013ad316270e554e9cdb', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2589', '512d05d89c4154d4faafb8c3f5cd0f5085986f1c67c6497a425dbbe998d718ab', 'Dislocation of MCP joint finger(s)', 'subtype_dislocation_of_mcp_joint_finger_s_44e87a594b', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'accepted_deterministic'),
  ('2590', '62b41e576b407d4f1be906a4c74a200de5c9e6cf94fdf8838a26e2de6766034f', 'Thumbnail haematoma', 'subtype_thumbnail_haematoma_7aaed10e68', 'dx_thumb_nail_haematoma_b3559f250c', 'Thumb nail haematoma', 'accepted_deterministic'),
  ('2591', '45ac2a6c64afb320c36bee3be14fd8ac1a1b31ced97180e1d5c58925ccb6877f', 'Eyebrow laceration requiring suturing', 'subtype_eyebrow_laceration_requiring_suturing_88ac45fb54', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2592', '43f01b76160e4636b87caff6bcafbcec43bc3cda6950c10fd40e99b8cd831c9d', 'Elbow contusion/haematoma', 'subtype_elbow_contusion_haematoma_b5b25cbc38', 'dx_elbow_contusion_ac2f8ee65d', 'Elbow contusion', 'accepted_deterministic'),
  ('2593', '48b35a4115c37b86e357d2a7d5770bc9b48e306c64109c3975d18da626d80701', 'Glenohumeral joint sprains', 'subtype_glenohumeral_joint_sprains_0aefa97c55', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('2594', '2711244e179a7a94c25fb584f4a02dd365013ac968031bea30b9dc629313aa7a', 'Abdominal oblique muscle strain', 'subtype_abdominal_oblique_muscle_strain_5b04cf0a3c', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury', 'accepted_deterministic'),
  ('2595', 'fae037330d1b93e40c5e03fbda6201da84a2d8620aedc5063363c8a0200358e9', 'Head/facial laceration', 'subtype_head_facial_laceration_850da462e6', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2596', '9679d21ce6308c503f4d242e48512ce8ac6c5382180669e397e6bcb319cf9fb2', 'Inferior tibiofibular syndesmosis sprain', 'subtype_inferior_tibiofibular_syndesmosis_sprain_0545fce188', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'accepted_deterministic'),
  ('2597', '249967ce2c2c5e4f79f01bca0990bf189acea14e628aeb15a1c60385f88e2d35', 'Chest Wall Soft Tissue Bruising/Haematoma', 'subtype_chest_wall_soft_tissue_bruising_haematoma_bd1a62550f', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2598', 'fa1bb7e5e99e50f6b5b34889c6ac530e19f7fd58f9445cc4808ebe04da780fbd', 'Anterior talofibular and calcaneofibular ligament sprain', 'subtype_anterior_talofibular_and_calcaneofibular_ligament_sprain_b3a64a632d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('2599', '37c21aaa9d508f8f9f261b7a135d558526b98a11fe81b0cfa864aed38a7779bc', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('2601', '9df33df15178093ac37b83aa3663561f8c73dfc48897ec604ce07c088e38b145', 'Grade 2 MCL tear knee', 'subtype_grade_2_mcl_tear_knee_843dc46804', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('2602', '1ea5da16d30d02af71c2ef647aa43136e0204d14334a3538d004cfc60e066f2e', 'Fracture lower rib (10 - 12', 'subtype_fracture_lower_rib_10_12_54689f5754', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2603', 'e8fd96ec36291c91ff9b6d8219fcc65167698755979df6de44e77ee639f02e61', 'Inferior tibiofibular syndesmosis sprain', 'subtype_inferior_tibiofibular_syndesmosis_sprain_0545fce188', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'accepted_deterministic'),
  ('2604', '06b7b21e37453068eef6d4c990b4f20c0f0c3d8c289ea197cf25cb24bd82ae01', 'Abdominal oblique muscle strain', 'subtype_abdominal_oblique_muscle_strain_5b04cf0a3c', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury', 'accepted_deterministic'),
  ('2605', '6a065606bec6491c438e5e3016fb175baae501896dec6031d5c809c568751d8d', 'Hip and Groin Tendon Injuries', 'subtype_hip_and_groin_tendon_injuries_37ce042157', 'dx_hip_or_groin_tendon_injury_99544a4bce', 'Hip or groin tendon injury', 'accepted_deterministic'),
  ('2606', 'd3235837aaf5c6ba4b9feb77d2f358171c87e536b1d66a3a933fc0ab0c452561', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2607', 'a9460e51a11fec9f3e84ee300e8c0448c0711706edc2ca640cab098d6d7785f1', 'Chronic Ankle Instability', 'subtype_chronic_ankle_instability_171826703d', 'dx_chronic_ankle_instability_ec5aa4a147', 'Chronic ankle instability', 'accepted_deterministic'),
  ('2608', 'dd76475928abe6ffc85fb5cd98c07aa8b956837e47f9b11fe94b6f39603eeddf', 'Partial-thickness pectoralis major tendon strain', 'subtype_partial_thickness_pectoralis_major_tendon_strain_fa603ebf4a', 'dx_pectoralis_major_injury_ae7aff3738', 'Pectoralis major injury', 'accepted_deterministic'),
  ('2609', '0242e6504517b27a5c192b4c0c3fbfc7c10f263075ff2a8eb749af15fab72571', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2611', '85114b27f10660aaab96da778bbb5320c0aeba8f4913f94e0a45b74d00175445', 'Cervical facet joint pain, chronic inflammation or stiffness', 'subtype_cervical_facet_joint_pain_chronic_inflammation_or_stiffness_6aa64dd327', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder', 'accepted_deterministic'),
  ('2612', '4e1c6606be00a091b773272eb508ea292cfbce17581fad236a74d66bb0e76919', 'Grade 2 MCL tear knee', 'subtype_grade_2_mcl_tear_knee_843dc46804', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('2613', 'dcb72ae1bd6ea6fcfb8a3022273c78bc265d9256c764c6bca933b02eb8c2c654', 'A/C Joint instability/recurrent sprains', 'subtype_a_c_joint_instability_recurrent_sprains_ed3ae2521a', 'dx_acromioclavicular_joint_chronic_instability_299408db68', 'Acromioclavicular joint chronic instability', 'accepted_deterministic'),
  ('2614', '5f3a58d9ec5a24a7b2179e916575bb1f4bc1d48e8e6dbf114986faebca3bcc95', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2615', 'a8dfba0da81a445534a171498ccbbd74317b28e3a5a9667057478caeb6f2db8a', 'Knee medial collateral ligament (MCL) injury', 'subtype_knee_medial_collateral_ligament_mcl_injury_9cce43fa53', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('2616', '8fb05819d722bb217082cd2b016c2438dc603f4e6489305f0d3b8a4fda8aad84', 'Hamstring tendon injury', 'subtype_hamstring_tendon_injury_f86b1dad5b', 'dx_hamstring_tendon_injury_f86b1dad5b', 'Hamstring tendon injury', 'accepted_deterministic'),
  ('2617', '035651b3d487699be83d5838d47c7367d34514ea0cefa94a34ea8722bbd8e424', 'Cervical Facet joint pain/ chronic inflammation/ stiffness', 'subtype_cervical_facet_joint_pain_chronic_inflammation_stiffness_8911953b82', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder', 'accepted_deterministic'),
  ('2618', '9f7249f0da4172b211b6ac71ff5be8d05dc5514770a8a1a44f272c18b1f4679f', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('2619', '9ed4d7a708053b433e4b222019d57b9cd7d7ac8931b44a411ee00924b92b15d6', 'Cervical facet joint pain, chronic inflammation or stiffness', 'subtype_cervical_facet_joint_pain_chronic_inflammation_or_stiffness_6aa64dd327', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder', 'accepted_deterministic'),
  ('2620', '339d3dfd044d094ab8a65a5725f63c0e0ce0edce6aa4fc2ef0831b8c0bfabd6a', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('2622', 'abd34cb88d28e3a8667e84db0248e0e7e1911bc5e3fe72df24054fc1ff90a3e7', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2623', '3da9f47435123ae976b8106778f09980f449b833f71e15febecab65a423ef25d', 'Lumbar facet joint sprain', 'subtype_lumbar_facet_joint_sprain_82bf226720', 'dx_lumbar_facet_joint_disorder_4a13830647', 'Lumbar facet joint disorder', 'accepted_deterministic'),
  ('2624', 'f6e26c744730312887c9917b27e18013b7149bf085ebc90699ba738bb3122ca8', 'Lumbar contusion/haematoma', 'subtype_lumbar_contusion_haematoma_ae89cb3e74', 'dx_lumbar_soft_tissue_contusion_125139d685', 'Lumbar soft tissue contusion', 'accepted_deterministic'),
  ('2625', '35480620895f363fd275530ce25d2daf397a9bf8947caf8f4b05180f1bb7e455', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2626', 'a9f5f1a6b6beea00637d22c42924945e664a56d319a2b70ebbfe415dc391cc9f', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2627', '1ec958b3e18ce1631f0a58f253dfa7f052a1fff9daa7b69872309d7c8e237e04', 'Abdominopelvic Soft Tissue Bruising/Haematoma', 'subtype_abdominopelvic_soft_tissue_bruising_haematoma_a62368817b', 'dx_abdominopelvic_soft_tissue_contusion_6fc95fc1db', 'Abdominopelvic soft tissue contusion', 'accepted_deterministic'),
  ('2628', 'ceaf86180b9ab4ea5be0c0b8d418ce25e8fc2e1c1d344363be0d828271742aa9', 'Bruised ribs/chest wall', 'subtype_bruised_ribs_chest_wall_0c223ac8bd', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2629', '93c6cb966c4b9772b6897e2509ddf6922b5ad164e736e171fb90fd81e7d4debb', 'Bruised ribs/chest wall', 'subtype_bruised_ribs_chest_wall_0c223ac8bd', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2630', '286ccb1b87747d9bd05581dedd4ecab04d1e3e18606e9c776ae804d8cafe88ce', 'Fracture Middle rib (5 - 9)', 'subtype_fracture_middle_rib_5_9_a58fe86e0f', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2631', '040b42508525903a4e99096a327164f178990bea977049bec22a0ce0c1ad9c14', 'Knee contusion/haematoma (extraarticular)', 'subtype_knee_contusion_haematoma_extraarticular_19a33609a2', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('2632', '52c0ecad4d70b116ee89a2625df28253e614086c3fce989afaafa5d3e41190c2', 'Sprained/jarred wrist joint', 'subtype_sprained_jarred_wrist_joint_7ec711f5b5', 'dx_wrist_injury_d94414e2c6', 'Wrist injury', 'accepted_deterministic'),
  ('2633', '49e7acd1304d5a3d421c94022ffa552433593ee95da86b471d906ce29a60cbf1', 'Elbow ulna/medial collateral ligament (UCL) strain or tear', 'subtype_elbow_ulna_medial_collateral_ligament_ucl_strain_or_tear_ab4c438f84', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury', 'accepted_deterministic'),
  ('2634', '9106568fb4174df726b88e900699d77da77ba84ac10295bc2f1d0f867b611f12', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2636', '59e634e2099551dc59eaaf61059cc7f3d1add8ac2b2d2d60cf120982895d0b40', 'Finger extensor tendon injury (incl mallet finger +/- avulsion fracture distal phalanx)', 'subtype_finger_extensor_tendon_injury_incl_mallet_finger_avulsion_fracture_distal_phalanx_62e86d0854', 'dx_finger_extensor_tendon_injury_mallet_finger_36d86ff004', 'Finger extensor tendon injury/mallet finger', 'accepted_deterministic'),
  ('2637', 'f727ddb15d742bfdc7c9ec04ada49cb62a300db0841d84c65883fd8ec43b1bbe', 'Scalp laceration', 'subtype_scalp_laceration_50be43ed71', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2638', '23ec7388faa7d2967421986625a18851ad371efd2d90a5b5f58afcc218a42f32', 'Sternocostal joint dislocation', 'subtype_sternocostal_joint_dislocation_3658d02019', 'dx_sternocostal_joint_dislocation_3658d02019', 'Sternocostal joint dislocation', 'accepted_deterministic'),
  ('2639', 'fbb829bcc4d179d41f2d408fec4f74661a990821e1c9714c4acdd18e6e4ef073', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2640', '6351c2efa86f7839a8f85dc1475dab76f468a5769d5cf80211882d2b21ff9b8e', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2641', '9c5ca10f9789392e037d8ce34bf99db74ee90d3d13f5f6fbcd24243c8949b555', 'Ear trauma', 'subtype_ear_trauma_7f4620effe', 'dx_ear_injury_190079a2d0', 'Ear injury', 'accepted_deterministic'),
  ('2642', '3adf5e2bd1206892941681001e28c306f5252cfd35187838e21542a8f99c3232', 'Medial gastroc strain', 'subtype_medial_gastroc_strain_c97059f639', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'accepted_deterministic'),
  ('2646', 'd731d98f9ca33b24811aab4e1258cd7bf35bef7f1a02c0f20bf78e5755623c0e', 'Inferior tibiofibular syndesmosis sprain', 'subtype_inferior_tibiofibular_syndesmosis_sprain_0545fce188', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'accepted_deterministic'),
  ('2652', 'e67024806fc165886df2ee4d7d9c86e0821fa030804f4a7b8e58ac5d5f06940f', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2653', 'cb52746235f3a69cc17006cbc662ec29fd1fbd2cd52b09763fd9a865642dc04f', 'Chronic synovitis of PIP joint(s)', 'subtype_chronic_synovitis_of_pip_joint_s_e7b48cd67a', 'dx_pip_joint_synovitis_b027f84ad3', 'PIP joint synovitis', 'accepted_deterministic'),
  ('2654', '45bf3d74833f424908fd8ea41645bd6aeb5929cab61ac1c0174ec07dcbf3ac15', 'Posterior cruciate ligament (PCL) injury', 'subtype_posterior_cruciate_ligament_pcl_injury_fbe6c1cd7d', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury', 'accepted_deterministic'),
  ('2655', '7ff62cd7d2ea9afb893ba1eb9a6799908fa7f0e3baf230d32e367938247a5ec1', 'Fractured glenoid /bony Bankart lesion', 'subtype_fractured_glenoid_bony_bankart_lesion_28aa2e9eb2', 'dx_glenoid_fracture_4db9569087', 'Glenoid fracture', 'accepted_deterministic'),
  ('2656', 'c9293383050a2de42fdc2ba9f6f4be15bf1021313ceb8ae92e181931b3e9f7b5', 'Scapula fracture', 'subtype_scapula_fracture_eb45c41e7a', 'dx_scapula_fracture_eb45c41e7a', 'Scapula fracture', 'accepted_deterministic'),
  ('2657', '6bba6182254deef3c3cd1fe378bb7fbd873ddaa4e5cbe6d2eb7f14ed82b518b3', 'Sportsman''s hernia', 'subtype_sportsman_s_hernia_c9eeb6b61d', 'dx_sports_hernia_ad99f8552f', 'Sports hernia', 'accepted_deterministic'),
  ('2661', '38b0bdd9f3dbbc171e0df6c6eaf6a8fb45492c93aedae004084602e3010f9f48', 'Hoffa''s fat pad impingement', 'subtype_hoffa_s_fat_pad_impingement_1c7deb1624', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury', 'accepted_deterministic'),
  ('2664', 'bb3687cc3ab6ed7028e908e909c4e6da70079f5d6dbcf94150f7de0a62a020e5', 'Anterior talofibular and calcaneofibular ligament sprain', 'subtype_anterior_talofibular_and_calcaneofibular_ligament_sprain_b3a64a632d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('2665', '1dc07ee5632df5e0746e1d2ffbd79f098cab9b865f925b8f017bc7f2322dcc14', 'Bruised ribs/chest wall', 'subtype_bruised_ribs_chest_wall_0c223ac8bd', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2666', 'c084e07249b8139e70ae90be6d356433fe82004e1e576b89942fc3d37ca5ef25', 'Distal quadricep haematoma', 'subtype_distal_quadricep_haematoma_01c745cc46', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2667', '71eed73e66b9087555bf18dd3a53b272f4a733d79b98718d00ef0c52a873c06d', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('2668', 'fa475fa1ebe1a727459652100f98ceec6f3d423c74ada29b42ad0b746ed789d7', 'Infrapatellar fat pad haematoma/ bursitis', 'subtype_infrapatellar_fat_pad_haematoma_bursitis_650edc0a53', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury', 'accepted_deterministic'),
  ('2669', '41929c5ad5730858dd9b8e799525ece30255e9525fe7fc28d575e64b98afc2fe', 'Glenohumeral joint sprain with chondral/labral damage (incl SLAP tear)', 'subtype_glenohumeral_joint_sprain_with_chondral_labral_damage_incl_slap_tear_1eb5055b90', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'accepted_deterministic'),
  ('2670', '22e2047d1d5cf2720f17e2f55307ca772263e35aa89e84ec59e87f4176b72c04', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('2672', 'deba3382520ece7521b665727e8356fee314198447d13ac6999e5dc30cda43aa', 'Gluteal muscle trigger points', 'subtype_gluteal_muscle_trigger_points_0dc668ef54', 'dx_gluteal_muscle_trigger_points_0dc668ef54', 'Gluteal muscle trigger points', 'identity_group'),
  ('2673', '16fca487f8921f305314837b24d9262dd6db0cea2e7f324398845039407782cd', 'Quadriceps strain or tear', 'subtype_quadriceps_strain_or_tear_17ff226482', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2674', 'ad85c0cbeab075ed72428042e95c030a6883bb1222476327ac327866c2ed3dfc', 'Knee posterolateral complex (PLC) strain or tear', 'subtype_knee_posterolateral_complex_plc_strain_or_tear_036571cdc7', 'dx_knee_posterolateral_corner_injury_a4c4c64579', 'Knee posterolateral corner injury', 'accepted_deterministic'),
  ('2675', '386191523492b08c0ac8e9cd3a50faa86d42bdf475fbc16fe8191c01e53dea9a', 'Biceps muscle strain', 'subtype_biceps_muscle_strain_9122d2b9c0', 'dx_biceps_muscle_injury_3a5679b9a5', 'Biceps muscle injury', 'accepted_deterministic'),
  ('2676', '6fad8cb7420ed60e1f2641176b92a9f11445f7eb422444520d949c9cd26b523a', 'Anterior talofibular and calcaneofibular ligament sprain', 'subtype_anterior_talofibular_and_calcaneofibular_ligament_sprain_b3a64a632d', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('2677', 'b12de51a5629934e188edeadfd6a3252cff3e2dfc950af1a750eeeae2c8f0a42', 'Scapholunate ligament sprain/tear', 'subtype_scapholunate_ligament_sprain_tear_4ea1ee7dcf', 'dx_scapholunate_ligament_injury_0d2ca4c746', 'Scapholunate ligament injury', 'accepted_deterministic'),
  ('2678', '43dcf403c2ccb4c5a6643a544f9cf20377db752bcac9656f3f475f2d8b6bcfe1', 'Forearm flexor muscle strain', 'subtype_forearm_flexor_muscle_strain_d73bfca6be', 'dx_forearm_flexor_muscle_strain_d73bfca6be', 'Forearm flexor muscle strain', 'accepted_deterministic'),
  ('2679', 'e0b09a842c3280872e00fc5602ee517c9ea208cd36140448e666bf93c756e855', 'Knee medial collateral ligament (MCL) injury', 'subtype_knee_medial_collateral_ligament_mcl_injury_9cce43fa53', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('2680', '373f581f17e5cf0b0c283eb546385b7aee3b2d19b5b1d8e86a8f73ce91afc458', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2681', '0893a8496002cf51a48ccec9412b34221d3280d08e70719c52e71c592aa76707', 'Posterior labral lesion of the shoulder', 'subtype_posterior_labral_lesion_of_the_shoulder_4803d8d0d8', 'dx_shoulder_labral_injury_c99b83bba8', 'Shoulder labral injury', 'accepted_deterministic'),
  ('2682', 'b5ce3050dd3697e35a3b98486f04124b72d9daab7670b6d0bde0bf4c22b22583', 'Eyebrow laceration requiring suturing', 'subtype_eyebrow_laceration_requiring_suturing_88ac45fb54', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2683', 'fecc999469c2703d27ad9fa181b4c06b39f6469d3f2ea033c0b438d371bd3541', 'Head Injuries', 'subtype_head_injuries_0959bc32c6', 'dx_head_injury_unspecified_611d184685', 'Head injury, unspecified', 'accepted_deterministic'),
  ('2684', 'a56c290c727641cb3a53842eeff3ec1eed7eef15832e4c3e88383a2c687bfba2', 'Adductor longus strain', 'subtype_adductor_longus_strain_dd1eac51f6', 'dx_adductor_muscle_injury_97164c9b14', 'Adductor muscle injury', 'accepted_deterministic'),
  ('2685', '70a3d7ee5f496961c1efcb1069065e8a47b2a75443049b047eb4f0f51a1c53f9', 'Pes anserine bursitis of the knee', 'subtype_pes_anserine_bursitis_of_the_knee_4a77d20615', 'dx_pes_anserine_bursitis_3af1f08842', 'Pes anserine bursitis', 'accepted_deterministic'),
  ('2688', '6b7c3a6ba9572b276bc6f166167f0389155ccc42c395e2665b42f9f64531616b', 'Eyebrow laceration requiring suturing', 'subtype_eyebrow_laceration_requiring_suturing_88ac45fb54', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2689', '98883a761982036238f66a5c8ce8b06216ee5dda7181d380e3e8d558986aca5a', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2690', 'cf6854b992c2b017ee2cb1d5a6ac00c46f2a1fb12cdb128ba2b0c73b6d864ac0', 'Quadriceps strain or tear', 'subtype_quadriceps_strain_or_tear_17ff226482', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2691', 'c863c2d1b82bf0266292043f69ec4ea813ab4f7c980a21883e1f738ffd9566aa', 'Plantar heel pain (fasciitis/strain/calcaneal spur)', 'subtype_plantar_heel_pain_fasciitis_strain_calcaneal_spur_7ea3631a44', 'dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b', 'Plantar heel pain/fasciopathy', 'accepted_deterministic'),
  ('2692', '73d4225321f51211e0849c4210086838d54a2b7a7633a2dce4649aaf077ea9b7', 'Biceps haematoma', 'subtype_biceps_haematoma_9e45c72a18', 'dx_biceps_muscle_injury_3a5679b9a5', 'Biceps muscle injury', 'accepted_deterministic'),
  ('2693', 'f9bee2de60eafe93435e6893d5e1a9c2a42586e3ae4ce44fdc220e6c81cf27ef', 'Quadriceps strain or tear', 'subtype_quadriceps_strain_or_tear_17ff226482', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2698', 'fbdc4867ab0ae22af3b2593fe8c392d768b924b77669fe2c10ab79409a86b9e8', 'Hamstring tendinopathy with ischial bursitis', 'subtype_hamstring_tendinopathy_with_ischial_bursitis_aac6575ce0', 'dx_hamstring_tendon_injury_f86b1dad5b', 'Hamstring tendon injury', 'accepted_deterministic'),
  ('2704', '4d105c2f4d24df0ef64bae62b61308845f56112aeec1a43e3304a76aa1fe9249', 'Gastrocnemius muscle injury or strain', 'subtype_gastrocnemius_muscle_injury_or_strain_367914bc2d', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'accepted_deterministic'),
  ('2705', 'f39be72b520bf41b164d6b9ab900edcfeb28dedf87ccddb3d58710b2b3029cc1', 'Quadriceps strain or tear', 'subtype_quadriceps_strain_or_tear_17ff226482', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2707', 'be4b799f57a45dc573e9051d6fa8de04f3ad16409fbabc7bfc942e6ed0663fa5', 'Ankle fracture', 'subtype_ankle_fracture_97af59eea6', 'dx_ankle_fracture_97af59eea6', 'Ankle fracture', 'accepted_deterministic'),
  ('2708', '6f45f3d4d9312e51ef6632d28a7d9c2e7c38ef2f73bdb722df64a39f33b1b502', 'Elbow contusion/haematoma', 'subtype_elbow_contusion_haematoma_b5b25cbc38', 'dx_elbow_contusion_ac2f8ee65d', 'Elbow contusion', 'accepted_deterministic'),
  ('2709', 'e34ec336254df04ab6cdc82ac6ff704be49666c2daf32a1a2d0bcfffacc1a203', 'Foot Pain/Injury Not otherwise specified', 'subtype_foot_pain_injury_not_otherwise_specified_949eb48abd', 'dx_foot_pain_116521a908', 'Foot pain', 'accepted_deterministic'),
  ('2710', '971c29cbacc0b17326c73159608b94f08210dd4d53b61c82f7d37f16207e933f', 'Headache/pain undiagnosed', 'subtype_headache_pain_undiagnosed_8cbf73ff3d', 'dx_headache_45575633c6', 'Headache', 'accepted_deterministic'),
  ('2714', '00463aa1df32e8f4cdf515510cd2ab4dcb9e3f092845e25962e4d5780193eea2', 'MCL rupture knee', 'subtype_mcl_rupture_knee_54556835d2', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('2715', 'adadc857f22256c30c72087e932cff9eb97fd05ae119ee5a54f38e32e619a024', 'Facet Joint/Neck Ligament sprain', 'subtype_facet_joint_neck_ligament_sprain_369f0afd14', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder', 'accepted_deterministic'),
  ('2716', '3ebad352b3339cfb4a3996bf5ba3bfd96cda1ed8ab725669b7701bb63dad796d', 'Inferior tibiofibular syndesmosis sprain', 'subtype_inferior_tibiofibular_syndesmosis_sprain_0545fce188', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'accepted_deterministic'),
  ('2717', '328b0ea09ba3648c19181d3716b85a77aa8587a6a6ef1d024ac0aa093794a6d8', 'Thoracic facet joint pain/ chronic inflammation/ stiffness', 'subtype_thoracic_facet_joint_pain_chronic_inflammation_stiffness_f219d19252', 'dx_thoracic_facet_joint_disorder_519c2ae5a8', 'Thoracic facet joint disorder', 'accepted_deterministic'),
  ('2718', '5161935792f7b856c1d03237fa426913a6489533cbee7507b24c09d5be3c75f1', 'Distal quadricep haematoma', 'subtype_distal_quadricep_haematoma_01c745cc46', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2719', '18129811438b9614832283431bf21fceb3584462c9011a739c6535d90b1cafd4', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('2721', 'ae8533a8a893efbdfe67cd7e076d52b9ad6f86cdb50c1a4e8b89c60f2c1b1129', 'Bruised ribs/chest wall', 'subtype_bruised_ribs_chest_wall_0c223ac8bd', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2722', 'aa230ee0fa459b051ee88ddef7c74e1354d4378102ec7ea2b00f05cf3476c0ba', 'Eyebrow laceration requiring suturing', 'subtype_eyebrow_laceration_requiring_suturing_88ac45fb54', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2723', '236a5cec4b16555040eaae1cefca65676f72fb99352db2fe53eb8f76429630d4', 'Lumbar soft-tissue dysfunction', 'subtype_lumbar_soft_tissue_dysfunction_e594190cd3', 'dx_lumbar_soft_tissue_dysfunction_d3330bd580', 'Lumbar soft tissue dysfunction', 'accepted_deterministic'),
  ('2724', '7e89368d98ca35151481a1cc2096cae9fc74bcc08588a34b2bcd1b617a95ae1c', 'Femoroacetabular impingement of the hip', 'subtype_femoroacetabular_impingement_of_the_hip_82d1b984fd', 'dx_femoroacetabular_impingement_76f8c7b5bc', 'Femoroacetabular impingement', 'accepted_deterministic'),
  ('2725', '7a68f9a83d6cae39b5b8489f152a74b0e27768cca7a9bc129343c0b750f437d5', 'Gastrocnemius muscle injury or strain', 'subtype_gastrocnemius_muscle_injury_or_strain_367914bc2d', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'accepted_deterministic'),
  ('2727', '3ee23963d80e9b2e5ef9b06ff8162c9c3c11ac46225c4a61baae485177fd4536', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2756', '919f94776a3f1c5fef66a01fbf388929debf53ec32c8b8d676de736fecc3e834', 'Lumbar Spine Joint Injury', 'subtype_lumbar_spine_joint_injury_2217f317ac', 'dx_lumbar_spine_injury_27c07f4f95', 'Lumbar spine injury', 'accepted_deterministic'),
  ('2757', '0d15dbe2d3bc0d265b4aceabaa5863d23ee460a5f13dee4820ad9677485247a0', 'Biceps femoris strain grade 1 - 2', 'subtype_biceps_femoris_strain_grade_1_2_bf0033afde', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2759', 'eea7faea73d3be2a8fa2c48ece9eaf352fa9a92199ad9f82c82354c02255cfae', 'Lateral hamstring trigger points', 'subtype_lateral_hamstring_trigger_points_ea90bfdf92', 'dx_lateral_hamstring_trigger_points_ea90bfdf92', 'Lateral hamstring trigger points', 'identity_group'),
  ('2761', '7be93fa92579b5755368f7cf6434a0be8092d97e68c687505db7bba84ad06555', 'Cervical nerve root compression/stretch', 'subtype_cervical_nerve_root_compression_stretch_6f650f0242', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('2762', '213097135c21c2a7a5410cb752b259826bda4aa8148a7e397cd3b16d0b7484cf', 'Other complication of wrist sprain', 'subtype_other_complication_of_wrist_sprain_6492247285', 'dx_wrist_sprain_complication_ae8ef1df9e', 'Wrist sprain complication', 'accepted_deterministic'),
  ('2763', '967f0f20954a8a9dc5ef61a152306ebf3f19d85d7749e4803864ca574078a799', 'Lumbar pain non-specific', 'subtype_lumbar_pain_non_specific_29a75fb1e1', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('2764', 'ab37e5e339ac8a85f4cb563b165e4c1fbc7d0927cfb4c1fca2a08a96a6d2d6a9', 'Lumbar Spine muscle and Tendon Strain/Spasm/Trigger Points', 'subtype_lumbar_spine_muscle_and_tendon_strain_spasm_trigger_points_0af31940e8', 'dx_lumbar_spine_muscle_and_tendon_strain_spasm_trigger_points_0af31940e8', 'Lumbar Spine muscle and Tendon Strain/Spasm/Trigger Points', 'identity_group'),
  ('2765', '28320d8a3ac6bafc6982c3c0220fcc30e338378ef108c56c0630221483e23bbc', 'Neck pain undiagnosed', 'subtype_neck_pain_undiagnosed_3e98145efc', 'dx_neck_pain_58ed6a0781', 'Neck pain', 'accepted_deterministic'),
  ('2766', 'fa9272238ae62fa60f3114dfed54578ae91b1b336f0b4b007dace5829b3dd37d', 'Lateral hamstring trigger points', 'subtype_lateral_hamstring_trigger_points_ea90bfdf92', 'dx_lateral_hamstring_trigger_points_ea90bfdf92', 'Lateral hamstring trigger points', 'identity_group'),
  ('2767', '1d2062429ef39c43108aa95556df94d30e333518e23dc2972ac8947ba21cfcd4', 'Ankle Pain/Injury undiagnosed', 'subtype_ankle_pain_injury_undiagnosed_00a809c59b', 'dx_ankle_pain_de6b615afc', 'Ankle pain', 'accepted_deterministic'),
  ('2768', '9b19a998a4498144c18165879c2071dffb54211099f0c6135fac96bd676c18b7', 'Knee pain undiagnosed', 'subtype_knee_pain_undiagnosed_cd27746a95', 'dx_knee_pain_609ce718bc', 'Knee pain', 'accepted_deterministic'),
  ('2769', 'ca305cc08ed6fe66a6ff77bb976a77c14ec4330ab84f914edb7d6f58be65cde4', 'Sinus tarsi syndrome (subtalar joint synovitis)', 'subtype_sinus_tarsi_syndrome_subtalar_joint_synovitis_b4663f208a', 'dx_sinus_tarsi_syndrome_ab59e85509', 'Sinus tarsi syndrome', 'accepted_deterministic'),
  ('2770', '9e6c461517f263e566d26152b666eec56c02719dc5882880ad95e6b3be0e87c2', 'Sprained/jarred wrist joint', 'subtype_sprained_jarred_wrist_joint_7ec711f5b5', 'dx_wrist_injury_d94414e2c6', 'Wrist injury', 'accepted_deterministic'),
  ('2771', 'e6a0411d37ce0bf9c23151a137b95e09947e98537fe7ad44872d0e48b949416c', 'Shoulder pain undiagnosed', 'subtype_shoulder_pain_undiagnosed_17d9bbee64', 'dx_shoulder_pain_738e4b93f7', 'Shoulder pain', 'accepted_deterministic'),
  ('2772', '47f07d9e40d3551b008e96e0490365b77de15ca185f67170756d9fa6156e590b', 'Instability 1st MCP joint', 'subtype_instability_1st_mcp_joint_12bde005a4', 'dx_thumb_mcp_injury_2b5c0aa20c', 'Thumb MCP injury', 'accepted_deterministic'),
  ('2774', 'dde72a917268d160bbb1c243c56804ce63b9d9b155ed8dba12cc6c495ffa9f91', 'Buttock Muscle Strain/Spasm/Trigger Points', 'subtype_buttock_muscle_strain_spasm_trigger_points_bed2057d40', 'dx_buttock_muscle_strain_spasm_trigger_points_bed2057d40', 'Buttock Muscle Strain/Spasm/Trigger Points', 'identity_group'),
  ('2775', 'c404706f9d1a457b407c9aae3546f5a54fead5308e4354a4fb7d4706e359eadd', 'Finger extensor tendon injury (incl mallet finger +/- avulsion fracture distal phalanx)', 'subtype_finger_extensor_tendon_injury_incl_mallet_finger_avulsion_fracture_distal_phalanx_62e86d0854', 'dx_finger_extensor_tendon_injury_mallet_finger_36d86ff004', 'Finger extensor tendon injury/mallet finger', 'accepted_deterministic'),
  ('2776', 'bb8c85953784f154b703121884b42d27eb214458714bb70930821099f7035ecb', 'Elbow pain undiagnosed', 'subtype_elbow_pain_undiagnosed_dc61928844', 'dx_elbow_pain_ce93745d98', 'Elbow pain', 'accepted_deterministic'),
  ('2777', 'd8a6c15c87f2e004c83b8ad67dfb38a18ba197e727fc1912ccecf77e1cd43a55', 'Neck pain undiagnosed', 'subtype_neck_pain_undiagnosed_3e98145efc', 'dx_neck_pain_58ed6a0781', 'Neck pain', 'accepted_deterministic'),
  ('2779', '4244c41a69bd765090e093f79167e155add505c9007d8493b0eaaa923ea505a9', 'Shoulder pain undiagnosed', 'subtype_shoulder_pain_undiagnosed_17d9bbee64', 'dx_shoulder_pain_738e4b93f7', 'Shoulder pain', 'accepted_deterministic'),
  ('2780', '588bf00652cd6ae182bbb3a6a98212dfc1eddc97ba9de48bd64e3f81253863f9', 'Adductor origin tendinopathy', 'subtype_adductor_origin_tendinopathy_75ee0d21d5', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'accepted_deterministic'),
  ('2781', '88256c60d1d908abed12a2aa5b005b951d964173589e660c1020b6b9dc4f5173', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2782', '207cc59bd14ad42f44cfaca741343dff92e3f9850ed220cc2a696efa9dc96126', 'Ankle anterior impingement', 'subtype_ankle_anterior_impingement_3a5b67cd15', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis', 'accepted_deterministic'),
  ('2783', '9882ec1d4ad6a4786d83ec75dc65324563e6722ebb7dfa3bd7a522919dbd64ec', 'Costal cartilage/costochondral joint injury', 'subtype_costal_cartilage_costochondral_joint_injury_31f64ad2c4', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2784', '13a7b9c06da1b69acef60d3be3a17f0b4bad48ffe358acecbbef3792e0497896', 'Shoulder pain undiagnosed', 'subtype_shoulder_pain_undiagnosed_17d9bbee64', 'dx_shoulder_pain_738e4b93f7', 'Shoulder pain', 'accepted_deterministic'),
  ('2785', '566d7f4d8aa572c5156e09aa275c190c9900433f227f1e7c4754d3abff27e90d', 'Achilles paratenonopathy', 'subtype_achilles_paratenonopathy_567b7c4104', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('2786', 'a874817d68e09c65291b2e0ccc9072238407f877a8ba93c772bb7786e2225d39', 'Abdominal oblique muscle strain', 'subtype_abdominal_oblique_muscle_strain_5b04cf0a3c', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury', 'accepted_deterministic'),
  ('2787', '7c21cb0304cf961ccf898c772aa25d1575ad1a682c6b4fef331e071c9593cae2', 'Hand muscle bruising/haematoma', 'subtype_hand_muscle_bruising_haematoma_dc72b631fa', 'dx_hand_muscle_contusion_or_haematoma_1d004bb885', 'Hand muscle contusion or haematoma', 'accepted_deterministic'),
  ('2788', '505a053cb89da10a78d08c55fcf97a890fc0fda0de54ad8e9dab435e4a969833', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2791', 'b57c04581330eef77a7cc8086395a18617a61b4a0a1e198f6da8fed1e7fbb3e4', 'Head Injuries', 'subtype_head_injuries_0959bc32c6', 'dx_head_injury_unspecified_611d184685', 'Head injury, unspecified', 'accepted_deterministic'),
  ('2792', 'fc9e167476fc55e7d902e78cff9bb575e4c8f457dd6b9fdecc86f6a3ce328ef9', 'Cervical Spine Instability', 'subtype_cervical_spine_instability_87f1adf4cc', 'dx_cervical_spine_instability_658367d444', 'Cervical spine instability', 'accepted_deterministic'),
  ('2793', '55f8ae9f5dd2da856a9ee11404ced990869a21e7f744fefa2902e5f531e5daa0', 'Infection as complication of lower leg laceration/abrasion', 'subtype_infection_as_complication_of_lower_leg_laceration_abrasion_fbe0f0818a', 'dx_wound_infection_complication_5415c9f38d', 'Wound infection/complication', 'accepted_deterministic'),
  ('2795', '8f19e5330e9c39bdbf0a0ce212ebbb555be4752e4ad3a56e6e85c479d3175715', 'Knee pain undiagnosed', 'subtype_knee_pain_undiagnosed_cd27746a95', 'dx_knee_pain_609ce718bc', 'Knee pain', 'accepted_deterministic'),
  ('2796', '04b88ab1808bfee7755dfeaf1752b40819f67fafbcbc4177f546d75a6f83e2e6', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('2797', '6dd7f8a966d75efb78b8a0a9e393529365f71b23d9c49f0a69c0bcd6c3ac1d25', 'Bruised ribs/chest wall', 'subtype_bruised_ribs_chest_wall_0c223ac8bd', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2798', '03dbb09fbfa40d284ced343695949fc250661bc9157c81a99a7e248bd91b2e99', 'Chest pain undiagnosed', 'subtype_chest_pain_undiagnosed_e8ab5537ef', 'dx_chest_pain_883378ac08', 'Chest pain', 'accepted_deterministic'),
  ('2799', 'eaaded74e50eb33deeec8e981cb630b7d1755a25302d562ffeb849d962f0d4b2', 'Lateral hamstring trigger points', 'subtype_lateral_hamstring_trigger_points_ea90bfdf92', 'dx_lateral_hamstring_trigger_points_ea90bfdf92', 'Lateral hamstring trigger points', 'identity_group'),
  ('2800', 'c980ea1321e5ea989aa27ed09e9bcf3bcc034b21883dc5b769130b4717ad03a8', 'Sprain lateral collateral ligament ankle', 'subtype_sprain_lateral_collateral_ligament_ankle_96d9293f86', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('2801', '2eacc4f9b3976a67cc80530e452ee1cddced6763423f008582ac7a78aa606057', 'Ear trauma', 'subtype_ear_trauma_7f4620effe', 'dx_ear_injury_190079a2d0', 'Ear injury', 'accepted_deterministic'),
  ('2802', '6ca2101b88e0b3bd9856f3a5f95623146aaad2856a400beadc35b0af6544198d', 'Knee posterolateral complex (PLC) strain or tear', 'subtype_knee_posterolateral_complex_plc_strain_or_tear_036571cdc7', 'dx_knee_posterolateral_corner_injury_a4c4c64579', 'Knee posterolateral corner injury', 'accepted_deterministic'),
  ('2803', '3204e2388a83ec0cdd4730f6e6d7e3d639dba4b32be27fff46b60c174fde6aa2', 'Adductor longus strain', 'subtype_adductor_longus_strain_dd1eac51f6', 'dx_adductor_muscle_injury_97164c9b14', 'Adductor muscle injury', 'accepted_deterministic'),
  ('2806', 'fc8ca934f02092129bc38556e44e01d8dbe719af34e7c5ee825f59a2119dc776', 'Distal quadricep haematoma', 'subtype_distal_quadricep_haematoma_01c745cc46', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2807', '8db6cb6e59c58f4fcfc10cec9106c54e32430eb724f8e1197b5483ed98a82375', 'Gastrocnemius tendon injury', 'subtype_gastrocnemius_tendon_injury_eec309de3f', 'dx_gastrocnemius_tendon_injury_eec309de3f', 'Gastrocnemius tendon injury', 'accepted_deterministic'),
  ('2808', 'e606854943356af4e1cceb018da758c322a8eca458f05073c9403420928120a7', 'Hamstring cramping during exercise', 'subtype_hamstring_cramping_during_exercise_2eb7c1414b', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm', 'accepted_deterministic'),
  ('2809', '1877744086b2b95d5e7c14d719b8a4180b24456c7d0bf1679f68d569d5d44d81', 'Hip flexor muscle strain', 'subtype_hip_flexor_muscle_strain_3e1d987aae', 'dx_hip_flexor_injury_cedda9fa03', 'Hip flexor injury', 'accepted_deterministic'),
  ('2810', '9f0e34a5fc4e18d1e5e3993781141c8d1d7de17c39c7f063857a57416c7940e9', 'Patellar Tendon Injury', 'subtype_patellar_tendon_injury_c88ba5aba6', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'accepted_deterministic'),
  ('2812', 'a23aa13816ca3943660610fb5f47521df04c4a39439a62a87999a9efc26babbe', 'Head/facial contusion/haematoma', 'subtype_head_facial_contusion_haematoma_1131a060b5', 'dx_head_and_facial_contusion_74a20a767e', 'Head and facial contusion', 'accepted_deterministic'),
  ('2814', 'f33336bed05ca0af529d27dd2a1778305ecf2e74c274a819813772dd2f6b7207', 'Cervical Spine Instability', 'subtype_cervical_spine_instability_87f1adf4cc', 'dx_cervical_spine_instability_658367d444', 'Cervical spine instability', 'accepted_deterministic'),
  ('2815', '1eeac576ce0fc0f4b4d0c16b8b2ff93e4a78295320b201c763533d022f6d05cb', 'Other soft tissue bruising/haematoma knee', 'subtype_other_soft_tissue_bruising_haematoma_knee_3ffba13606', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('2816', 'e749c72e491b761b85f0fc6b4c61e24c604cfe1365f394ed6c91c9cbfce2a570', 'Hamstring cramping during exercise', 'subtype_hamstring_cramping_during_exercise_2eb7c1414b', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm', 'accepted_deterministic'),
  ('2817', '213ae3cfba95c3245ede699328c478f3b461b0dfec046265172825fe886be88c', 'Patellar tendinopathy', 'subtype_patellar_tendinopathy_3ea4d4d1bf', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'accepted_deterministic'),
  ('2818', '93a87765eab1620ee4f34e90d6238196178e99239cd425e0730a36e94018e0b1', 'Quadriceps muscle haematoma', 'subtype_quadriceps_muscle_haematoma_9b59bd886c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2819', '515e90bfe55fd4414910f3a4b44f92a91836c2e0bde9c920281d18a23a8e92a6', 'ACL rupture', 'subtype_acl_rupture_f84927fab2', 'dx_acl_injury_4b8eb47e96', 'ACL injury', 'accepted_deterministic'),
  ('2820', '0fb63fa5dff752fa982074026253c0aba4aac42ba9cc09dc0d326b1ec1c850fd', 'Ankle osteochondral Injuries', 'subtype_ankle_osteochondral_injuries_51605a67c0', 'dx_ankle_osteochondral_injury_7842c657f7', 'Ankle osteochondral injury', 'accepted_deterministic'),
  ('2821', 'b0efe7f96d236d0d238d7c18ef2ffdbc87e9cdc0932414ed324fe0a21c2fb084', 'Calf cramping during exercise', 'subtype_calf_cramping_during_exercise_a1fb0ba554', 'dx_calf_cramp_spasm_950b710fbb', 'Calf cramp/spasm', 'accepted_deterministic'),
  ('2823', 'fb4fae9dfc1a67dfe0b465db65ee3c44001872f25f3ab6eb3667754306097aee', 'Calf contusion/haematoma', 'subtype_calf_contusion_haematoma_1ed62efd4d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'accepted_deterministic'),
  ('2824', 'e4c5f589f91ba86ae148279a14e596e6293f6a3037ca2df9746d825cca48b312', 'Costal cartilage/costochondral joint injury', 'subtype_costal_cartilage_costochondral_joint_injury_31f64ad2c4', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2825', '01932941d8c477137633388db01eb3b296ff894a55f1e42c7d859799e41ae39b', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('2826', '9899bce2c402003b975a51482def072564c893ff75439e4453e1b06430017ffe', 'Lacerated knee', 'subtype_lacerated_knee_9e6fcc291a', 'dx_knee_wound_7498252643', 'Knee wound', 'accepted_deterministic'),
  ('2827', 'd75227a36a998437edd2e1c90cb4e224de11cae954d8ee2cb57e9947a708bc47', 'Medial hamstring tendon strain at knee', 'subtype_medial_hamstring_tendon_strain_at_knee_7fa521f204', 'dx_hamstring_tendon_injury_f86b1dad5b', 'Hamstring tendon injury', 'accepted_deterministic'),
  ('2828', '15f74461ef7ca6854e09303804527d2b28f9adf3f1397eb08c7a5202ab55c25d', 'Shoulder osteochondral injury', 'subtype_shoulder_osteochondral_injury_06178c6960', 'dx_shoulder_osteochondral_injury_06178c6960', 'Shoulder osteochondral injury', 'accepted_deterministic'),
  ('2829', 'c255e4716b14d90fa4fdc1bf9e93515b48881aa2461179b55ea4a69bce600a17', 'Other foot soft tissue bruising/haematoma not elsewhere specified', 'subtype_other_foot_soft_tissue_bruising_haematoma_not_elsewhere_specified_1175637973', 'dx_foot_contusion_6c8a5bb721', 'Foot contusion', 'accepted_deterministic'),
  ('2830', 'f4b63f91658ca99ad68bfa1441a48a5f824ac27fc8e5a7acbec844c76ce7145d', 'Foot joint sprain', 'subtype_foot_joint_sprain_cd46c09b48', 'dx_foot_joint_injury_28a178b0b5', 'Foot joint injury', 'accepted_deterministic'),
  ('2831', '922f66992ec94060d14326448b5f87fa426380d40a40d6d5eaab44cd28c184d8', 'Proximal adductor trigger points', 'subtype_proximal_adductor_trigger_points_e0737a9324', 'dx_proximal_adductor_trigger_points_e0737a9324', 'Proximal adductor trigger points', 'identity_group'),
  ('2832', 'e7226ab8b7706697b54e1a4339e9a37b235127c8a73eea7f024000dcf7ecd9e8', 'Other quadricep strain', 'subtype_other_quadricep_strain_d8561f4b63', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2833', '0fb112db3cb09c5b78aa5723b3a4ce3f09c42f8472bb10350e4ffea7b4f00984', 'Thoracic spine pain undiagnosed', 'subtype_thoracic_spine_pain_undiagnosed_743d0f3258', 'dx_thoracic_spine_pain_9ec9a9f2e5', 'Thoracic spine pain', 'accepted_deterministic'),
  ('2834', '2e7f25feeb5168345e22537179cbeef931fff5c94c78bd49d8c5bf052858a474', 'Head Injuries', 'subtype_head_injuries_0959bc32c6', 'dx_head_injury_unspecified_611d184685', 'Head injury, unspecified', 'accepted_deterministic'),
  ('2835', 'f5a2441be6f0eae77739d796ac2f200605f7c9be3bfed1c171f473a48f06ebb7', 'Grade 3 hamstring strain', 'subtype_grade_3_hamstring_strain_6183bcd886', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2836', '078919921270c97eea4d47191ba812a7b587276a5e45224ce919d85b17f7528b', 'Ankle Pain/Injury undiagnosed', 'subtype_ankle_pain_injury_undiagnosed_00a809c59b', 'dx_ankle_pain_de6b615afc', 'Ankle pain', 'accepted_deterministic'),
  ('2837', '459322b7fdf95edb0c823d19a10b60b089b675ea2137ef0c6dd525ff21787657', 'Ankle multiple ligaments sprain', 'subtype_ankle_multiple_ligaments_sprain_7b65bb0881', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('2838', '6136774f69d9d4a19737bf174631fbc85a5587e937b576521ad3dd45091e9220', 'Patellar Tendon Injury', 'subtype_patellar_tendon_injury_c88ba5aba6', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'accepted_deterministic'),
  ('2839', 'fb8de19dca5820b200982cd944476223d7a2e2af6318e34575f5b23dda527bf6', 'Sprain medial collateral (deltoid) ligament ankle', 'subtype_sprain_medial_collateral_deltoid_ligament_ankle_ba23692ed8', 'dx_medial_ankle_ligament_injury_9add2aecee', 'Medial ankle ligament injury', 'accepted_deterministic'),
  ('2841', '29dc94da67f1b7d1beee2c851fb1b56ef461689e300cf8bd8fcdea1408c4b6d6', 'Hip/Groin Pain Not otherwise specified', 'subtype_hip_groin_pain_not_otherwise_specified_742fb1cd99', 'dx_hip_and_groin_pain_27531edcc3', 'Hip and groin pain', 'accepted_deterministic'),
  ('2842', 'de463418a09f6b7f29f77e06fb14c674ff02cd8691b89252fde0e8f4e5173eb2', 'Knee pain undiagnosed', 'subtype_knee_pain_undiagnosed_cd27746a95', 'dx_knee_pain_609ce718bc', 'Knee pain', 'accepted_deterministic'),
  ('2843', 'c9e6046d7bd80ba3eb67080496f4a19fbb9b601236c6c869dc008e7539f77ecd', 'Knee Impingement/Synovitis/Biomechanical Lesion not associated with other conditions', 'subtype_knee_impingement_synovitis_biomechanical_lesion_not_associated_with_other_conditions_ed9f75283a', 'dx_knee_synovitis_impingement_02e229b1cc', 'Knee synovitis/impingement', 'accepted_deterministic'),
  ('2845', 'efc27bc2babead10f637efd87a0f039003697fc640384dadc04719fb998f5c10', 'Sprain lateral collateral ligament ankle', 'subtype_sprain_lateral_collateral_ligament_ankle_96d9293f86', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('2847', 'f2838fabd305150b0756b0b2baa42472594921ea05f37b9a6d609bf296095270', 'Lumbar Spine muscle and Tendon Strain/Spasm/Trigger Points', 'subtype_lumbar_spine_muscle_and_tendon_strain_spasm_trigger_points_0af31940e8', 'dx_lumbar_spine_muscle_and_tendon_strain_spasm_trigger_points_0af31940e8', 'Lumbar Spine muscle and Tendon Strain/Spasm/Trigger Points', 'identity_group'),
  ('2848', '9b1c388733e4746f2e3e59c5ad3a1d77de0da51055c2ea9958a7f3540ab48179', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2849', '542eb3cc3f17ddbb4064e185bb4cc88a8925b7da9dd38f25a2a4a42a265899c2', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('2850', '86687c896b75c476d4049bac7489f676e700f9517a289ffd1590b96948f206e2', 'Infrapatella fat pad contusion/haematoma +/- bursitis', 'subtype_infrapatella_fat_pad_contusion_haematoma_bursitis_3758a2ae3c', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury', 'accepted_deterministic'),
  ('2851', 'f5e6b688ff0e19a3ce8dfa0b6255b983bf60b35059ac3e382be5ae70b3110280', 'Infrapatella fat pad contusion/haematoma +/- bursitis', 'subtype_infrapatella_fat_pad_contusion_haematoma_bursitis_3758a2ae3c', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury', 'accepted_deterministic'),
  ('2853', '0de2ed6483ecf4340ef70c7409cf71f715db2f4073a4479e599f04baa3f9b353', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2854', '5bb5d3beef43d2cd2e9667c6ca861cf02a46f09ff599a8236bfa5f050707250a', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2855', '68a8161852a07ef9e8e796a8ec493c35f2cf8b37e12a6a3745de946907860b17', 'Ankle Pain/Injury undiagnosed', 'subtype_ankle_pain_injury_undiagnosed_00a809c59b', 'dx_ankle_pain_de6b615afc', 'Ankle pain', 'accepted_deterministic'),
  ('2856', '96716837e7537cbe6b826a181c2dea366ca9d6b41ba103918d93324d227741b8', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('2857', '198aaf05dca5d31936b96d835aec9e8828da9875dc16a50b80418dd8619f814c', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2858', '22c7df8be698f15a5f38c0fc8ff98b972346e50535042b75fcca076cf5b8cc13', 'Elbow contusion/haematoma', 'subtype_elbow_contusion_haematoma_b5b25cbc38', 'dx_elbow_contusion_ac2f8ee65d', 'Elbow contusion', 'accepted_deterministic'),
  ('2859', 'e83d1761dad8d556d0c6ac2ee04896a896dc3dedaa5415bf8c8511c3e23a3c5d', 'Avulsed/fractured tooth', 'subtype_avulsed_fractured_tooth_d992bbc154', 'dx_dental_injury_b97b2afe75', 'Dental injury', 'accepted_deterministic'),
  ('2860', 'c4044f020aefc671c5768d9c208f665d1bc6d782e17f1b7b71071ad9d31cab76', 'Lateral gastroc strain', 'subtype_lateral_gastroc_strain_64cca89166', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'accepted_deterministic'),
  ('2861', '686832ef016d3e071640d9ac4438d6d56b7388e83dd6112cf7c42f67d6715c7b', 'Calf cramping during exercise', 'subtype_calf_cramping_during_exercise_a1fb0ba554', 'dx_calf_cramp_spasm_950b710fbb', 'Calf cramp/spasm', 'accepted_deterministic'),
  ('2862', '05ac5c33f8512b81a9412861ab8dc34df61a1867d87a93b5194cd61867c1d02b', 'Cervical functional pain', 'subtype_cervical_functional_pain_e11c275770', 'dx_cervical_functional_pain_e11c275770', 'Cervical functional pain', 'accepted_deterministic'),
  ('2863', '4abcbd2ca47d4c4a1c68b6fb24321e519e0f2c1c4142e5097804d211c1b67413', 'Knee Pain/Injury Not otherwise specified', 'subtype_knee_pain_injury_not_otherwise_specified_f2690253b3', 'dx_knee_pain_609ce718bc', 'Knee pain', 'accepted_deterministic'),
  ('2864', 'b95192341da843f494d293baae810c130d8188232637a5d3ef36a30ea6710709', 'Neurological Neck Injury', 'subtype_neurological_neck_injury_25dc3f335f', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('2865', '3ceb476b0d0982250f8667b1ea4daf33bc44275d58209856bf0e7460c232a288', 'Plantar heel pain (fasciitis/strain/calcaneal spur)', 'subtype_plantar_heel_pain_fasciitis_strain_calcaneal_spur_7ea3631a44', 'dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b', 'Plantar heel pain/fasciopathy', 'accepted_deterministic'),
  ('2866', '3b178b7b850e88bd83c3ce637b459bbdffcace9c687f2a47fdeddde90227dc7b', 'Ulnar neuropathy, elbow', 'subtype_ulnar_neuropathy_elbow_447d7e77ce', 'dx_ulnar_neuropathy_d6dcc82595', 'Ulnar neuropathy', 'accepted_deterministic'),
  ('2867', '57a25b2934abd029b2f21ee4401da459593163880334468f5042e6d335bc4f40', 'Back referred hamstring tightness', 'subtype_back_referred_hamstring_tightness_6fbd78d98a', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'accepted_deterministic'),
  ('2869', 'd11b3781b695042853c83da8838545a5b5e4dc8b3b420d0762f936d746cb954f', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2870', '52a88aa6ef91a2693f23c4221485580a715ba3242005e3607d3b5721b7b79d2c', 'Lumbar disc injury with L4 nerve root injury', 'subtype_lumbar_disc_injury_with_l4_nerve_root_injury_cb277bdfe6', 'dx_lumbar_disc_injury_a2189aa3a0', 'Lumbar disc injury', 'accepted_deterministic'),
  ('2871', '19db2ca5f344f4ec13f2a33b8fa7769e878b3b908177fc64e3d858ecdf2497b8', 'Lumbar Spine muscle and Tendon Strain/Spasm/Trigger Points', 'subtype_lumbar_spine_muscle_and_tendon_strain_spasm_trigger_points_0af31940e8', 'dx_lumbar_spine_muscle_and_tendon_strain_spasm_trigger_points_0af31940e8', 'Lumbar Spine muscle and Tendon Strain/Spasm/Trigger Points', 'identity_group'),
  ('2872', '3c9950839ac8dbac12d566ea96c0ea9411e36d9c2476b2396a6006865823eac1', 'Lumbar pain or injury, not otherwise specified', 'subtype_lumbar_pain_or_injury_not_otherwise_specified_d98060910b', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('2873', '352a009f72cb2ef287529165f3eaeb814228668f39b1629ec9ea86fe99cb2d68', 'Sinus tarsi syndrome (subtalar joint synovitis)', 'subtype_sinus_tarsi_syndrome_subtalar_joint_synovitis_b4663f208a', 'dx_sinus_tarsi_syndrome_ab59e85509', 'Sinus tarsi syndrome', 'accepted_deterministic'),
  ('2874', '6853c3da4804de16e54b38a05ea21ddaf11a9d47f01ce0fd2fe27d685c30fa63', 'Thoracic Pain/Injury not otherwise specified', 'subtype_thoracic_pain_injury_not_otherwise_specified_2fa9b78923', 'dx_thoracic_spine_pain_9ec9a9f2e5', 'Thoracic spine pain', 'accepted_deterministic'),
  ('2875', '11775883d09d1f491204a4959042eb5bdb86ac4c87c0288907b0d56e73eb735a', 'Patellar Tendon Injury', 'subtype_patellar_tendon_injury_c88ba5aba6', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'accepted_deterministic'),
  ('2877', '02fe3b6cddf3bcf5406c035d1c9dc2bfb95559805623a253be40d2169519198b', 'Posterior cruciate ligament (PCL) injury', 'subtype_posterior_cruciate_ligament_pcl_injury_fbe6c1cd7d', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury', 'accepted_deterministic'),
  ('2878', 'e5a7fb675a2f59cad481f395b2df4c4a6084426fcacbf0f5dab9b05539ba21c3', 'Lumbar Spine Neurological Injury', 'subtype_lumbar_spine_neurological_injury_03cdf78500', 'dx_lumbar_neurological_injury_bb35f1e8ee', 'Lumbar neurological injury', 'accepted_deterministic'),
  ('2879', 'cfafeea7fa58bd233e28b5dbc309d019d0678a86d871f6c0d0f2779111879129', 'Other shoulder muscle injury not elsewhere specified', 'subtype_other_shoulder_muscle_injury_not_elsewhere_specified_e29c677862', 'dx_shoulder_muscle_injury_f1ad3d954e', 'Shoulder muscle injury', 'accepted_deterministic'),
  ('2882', '651424e91d33d1444f9df7dacedad17250e2b9c153a7a08fde5982fd167d2393', 'Proximal adductor trigger points', 'subtype_proximal_adductor_trigger_points_e0737a9324', 'dx_proximal_adductor_trigger_points_e0737a9324', 'Proximal adductor trigger points', 'identity_group'),
  ('2883', '38f1d24b7f271ce2b0c086f6dbb60e38a6e96971b57c50f7443d2936d838bca5', 'Fat pad contusion heel', 'subtype_fat_pad_contusion_heel_6a2375437b', 'dx_heel_contusion_4009d671bf', 'Heel contusion', 'accepted_deterministic'),
  ('2884', 'd3e470021cd06b7c3dcf535fa858958779abe02e5e749bdee0a161c9464deedf', 'Hip flexor muscle strain', 'subtype_hip_flexor_muscle_strain_3e1d987aae', 'dx_hip_flexor_injury_cedda9fa03', 'Hip flexor injury', 'accepted_deterministic'),
  ('2885', 'a2ffbcc954e9001539d784cc5d7790eb32e613ff7e3a37bd6e57e59138e2d595', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2886', '49e466ccaff5d0c6ce6eea1daf859e3cd0c55255fe9abe51a37ad51743ea3241', 'Fracture thoracic vertebral body', 'subtype_fracture_thoracic_vertebral_body_2c6f238b37', 'dx_thoracic_vertebral_fracture_dae2957a37', 'Thoracic vertebral fracture', 'accepted_deterministic'),
  ('2889', '431ea099a0b438f8f0e913859d16ea0ab27795d9a3abd5cad71b12acb04242fa', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('2890', '76f2e54914b962d1b9484d425f12379a6935cacdfd33faff695e76d09306e075', 'Thoracic Pain/Injury not otherwise specified', 'subtype_thoracic_pain_injury_not_otherwise_specified_2fa9b78923', 'dx_thoracic_spine_pain_9ec9a9f2e5', 'Thoracic spine pain', 'accepted_deterministic'),
  ('2891', '536b57595e56dd88050d3b99c730312abb2ec3bea0a2d79dcb75530d0a4f2c3d', 'Eyebrow laceration requiring suturing', 'subtype_eyebrow_laceration_requiring_suturing_88ac45fb54', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2892', '77599d25917aa19b34f6b37be6edeb0ae8bc22581c0926b4748f08ce28430a83', 'Cervical functional pain', 'subtype_cervical_functional_pain_e11c275770', 'dx_cervical_functional_pain_e11c275770', 'Cervical functional pain', 'accepted_deterministic'),
  ('2893', 'ff3863976aca28c390afc252e8c254aec79c48e1f257dbaf80beab58637205d7', 'Hip flexor muscle strain', 'subtype_hip_flexor_muscle_strain_3e1d987aae', 'dx_hip_flexor_injury_cedda9fa03', 'Hip flexor injury', 'accepted_deterministic'),
  ('2894', '7aadf0f544405a63d53e59657c26f9c4142481e2c8b64ba9191ea50b08e16489', 'Dislocated metacarpophalangeal or interphalangeal joint', 'subtype_dislocated_metacarpophalangeal_or_interphalangeal_joint_7acd7fd43f', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'accepted_deterministic'),
  ('2895', '96746505d220ed04c404a9544d58e5938513c8900921c4dbfb5a6478127ba8cd', 'Lateral hamstring trigger points', 'subtype_lateral_hamstring_trigger_points_ea90bfdf92', 'dx_lateral_hamstring_trigger_points_ea90bfdf92', 'Lateral hamstring trigger points', 'identity_group'),
  ('2897', 'e68bb7a5cca4e39b80630fc3672598a7fadba23f906db66b685c5679369bb947', 'Groin soreness or trigger points', 'subtype_groin_soreness_or_trigger_points_70c27347b8', 'dx_groin_soreness_or_trigger_points_70c27347b8', 'Groin soreness or trigger points', 'identity_group'),
  ('2898', 'd809bb90810b274d72e5be4b8a53166aed3423a9a45a7e67c1c1d061e6d314a4', 'Adductor origin tendinopathy', 'subtype_adductor_origin_tendinopathy_75ee0d21d5', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'accepted_deterministic'),
  ('2899', 'e02eec7c4408b595fa570b828eac0339f5517864a6a2fb48bf654ae91f84b125', 'Inferior tibiofibular syndesmosis sprain', 'subtype_inferior_tibiofibular_syndesmosis_sprain_0545fce188', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'accepted_deterministic'),
  ('2900', 'ca4ddfbf989e5edb8ce5ff389ba368dd41ed5da9f9b1240e8ef794cd92eb1ab9', 'Calf muscle cramps/spasm', 'subtype_calf_muscle_cramps_spasm_7890832741', 'dx_calf_cramp_spasm_950b710fbb', 'Calf cramp/spasm', 'accepted_deterministic'),
  ('2901', 'c2ae817b8f9f472a6533074433918daa7c36bdba1cecb6c71d5ef93c6739d8f3', 'Thoracic Pain/Injury not otherwise specified', 'subtype_thoracic_pain_injury_not_otherwise_specified_2fa9b78923', 'dx_thoracic_spine_pain_9ec9a9f2e5', 'Thoracic spine pain', 'accepted_deterministic'),
  ('2902', '124cccf32e43ce3ebc04be14f899a5388354a739836c5810cdcc072d4c371f6c', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2903', '86f15eb02f1b8f27cf757b196e62a3603008c7c69595ce44a0c0b2f5874f3812', 'A/C Joint contusion', 'subtype_a_c_joint_contusion_787ed8ed6a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'accepted_deterministic'),
  ('2904', '84eaf0f174e20f9dcf6b200c6842fd90e02ffa0125a8d10567865129f50e0bb7', 'Concussion with imaging abnormality', 'subtype_concussion_with_imaging_abnormality_6d73b078a8', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2905', '7a9ca4d47a91142f627fb65fba6001f917bf7aef2d34e46cc617a883e5364bb5', 'Cervical functional pain', 'subtype_cervical_functional_pain_e11c275770', 'dx_cervical_functional_pain_e11c275770', 'Cervical functional pain', 'accepted_deterministic'),
  ('2906', '07165adffdaa746459f59596c52d4cc1184c9359093a4a611391aa12c0f5a543', 'Knee Sprains/Ligament Injuries', 'subtype_knee_sprains_ligament_injuries_bc9c2670dd', 'dx_knee_ligament_injury_unspecified_7ab630d44d', 'Knee ligament injury, unspecified', 'accepted_deterministic'),
  ('2907', '753bd78df0353b65d574dd6e9ca0be611b902753fc2499b662c1f236d63b2392', 'Osgood-Schlatter syndrome', 'subtype_osgood_schlatter_syndrome_34f2e1629e', 'dx_osgood_schlatter_syndrome_34f2e1629e', 'Osgood-Schlatter syndrome', 'accepted_deterministic'),
  ('2908', '5535c01523f08a046299673030f954f524291c96d57ab11d8bde1a4f99a6d449', 'PIP joint dislocation ring finger', 'subtype_pip_joint_dislocation_ring_finger_0551271774', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'accepted_deterministic'),
  ('2909', '940cd047e63e586c47d3bdc2b3888b549d3f76aeb2e7509a0b542ab0bb1dd04b', 'Other posterior ankle impingement', 'subtype_other_posterior_ankle_impingement_2d906f2579', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis', 'accepted_deterministic'),
  ('2910', '00ed0289a4ecec151c31e6fabf6ae3a5b199aab71e6c6f67b2f29949e2395773', 'DIP joint dislocation little finger', 'subtype_dip_joint_dislocation_little_finger_1d6c9aa203', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'accepted_deterministic'),
  ('2911', '0ba020739f61180e34148bb4dc4d53dd93d3a0cd14e5d44c686e79fb2d3088db', 'Sprained/jarred elbow', 'subtype_sprained_jarred_elbow_a336ca7456', 'dx_elbow_injury_7100f71f81', 'Elbow injury', 'accepted_deterministic'),
  ('2912', 'b81daa7f253ba65012f1698635b958c53ff93d78b6a94388b11af90de7a250d0', 'Other wrist pain not otherwise specified', 'subtype_other_wrist_pain_not_otherwise_specified_545d2e6b25', 'dx_wrist_or_hand_pain_57c9958c78', 'Wrist or hand pain', 'accepted_deterministic'),
  ('2913', 'e73b3128376bdc92157c2f8ba70c0ed9f923fd1d7d1abf087d7fcbfd45f15d07', 'Ankle osteochondral Injuries', 'subtype_ankle_osteochondral_injuries_51605a67c0', 'dx_ankle_osteochondral_injury_7842c657f7', 'Ankle osteochondral injury', 'accepted_deterministic'),
  ('2914', 'cac288b189adebef12e2250a9eccc42ce2572e5d6fe1c324e00b6a2cb8a880f6', 'Distal quadricep haematoma', 'subtype_distal_quadricep_haematoma_01c745cc46', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2915', '495a64328518b21101fbca5ea889f46fab8677b84553fcb46f1531584c03f566', 'Achilles tendinopathy', 'subtype_achilles_tendinopathy_f38a9f037b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'accepted_deterministic'),
  ('2916', '46094e6660aaf1dbf420788cfa639fecc9b7d3502ea3c62afb4b8c82a69cd602', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2917', '55e1146924ffdc2ba1c277cd6420c011c3209489ac271a6a54b39cb70c3af710', 'Hamstring tendon injury', 'subtype_hamstring_tendon_injury_f86b1dad5b', 'dx_hamstring_tendon_injury_f86b1dad5b', 'Hamstring tendon injury', 'accepted_deterministic'),
  ('2919', 'e9194a192ff3edd051e24c4f64d15aa7edc327b41d470108cb4dedfc7b9aa61b', 'Facial laceration requiring suturing', 'subtype_facial_laceration_requiring_suturing_40a8df9bf4', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'accepted_deterministic'),
  ('2922', '45e83f1523bddb234a3dfe9441803eee8deb37243885dedcf47de07f6bf4157f', 'Rectus femoris strain', 'subtype_rectus_femoris_strain_5670ca194b', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2923', 'd298bc8a8ce1900b4d4eb45e253cde1112999bb1f7658ff25c154e9455645c05', 'ACL rupture', 'subtype_acl_rupture_f84927fab2', 'dx_acl_injury_4b8eb47e96', 'ACL injury', 'accepted_deterministic'),
  ('2925', '58ef7cfd49014c84c434aa2baf14a9d3f10d25d39e8ddf5d56b2f60c279b3e07', 'Traumatic knee bursitis', 'subtype_traumatic_knee_bursitis_3ab0742840', 'dx_knee_bursitis_42542bca17', 'Knee bursitis', 'accepted_deterministic'),
  ('2926', 'c84255f2aa11e79632e0760b4a3f7d26d880a30c38593741892746ab6921131c', 'Lateral hamstring trigger points', 'subtype_lateral_hamstring_trigger_points_ea90bfdf92', 'dx_lateral_hamstring_trigger_points_ea90bfdf92', 'Lateral hamstring trigger points', 'identity_group'),
  ('2927', '8b686c022b8e6dd134044380630402f666db52e4292bf15db734046da2eca232', 'Lateral hamstring trigger points', 'subtype_lateral_hamstring_trigger_points_ea90bfdf92', 'dx_lateral_hamstring_trigger_points_ea90bfdf92', 'Lateral hamstring trigger points', 'identity_group'),
  ('2959', '2e63e45bc5103910dc2b10c59a3a53096720f0f3582455e6d4f1c11d4371289e', 'Lumbar pain/injury not otherwise specified', 'subtype_lumbar_pain_injury_not_otherwise_specified_483de50da8', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('2963', '0de94aa6fa9d22cc8522a9f91076d8a3fe0c3f17c52fb43ce310bebc4a29514e', 'Ankle osteochondral Injuries', 'subtype_ankle_osteochondral_injuries_51605a67c0', 'dx_ankle_osteochondral_injury_7842c657f7', 'Ankle osteochondral injury', 'accepted_deterministic'),
  ('2964', 'ed6db6d83a0b8bef2ef25b984b1df9dd5744c46b94283edafc8d78aecf15f342', 'Foot pain undiagnosed', 'subtype_foot_pain_undiagnosed_9427f60898', 'dx_foot_pain_116521a908', 'Foot pain', 'accepted_deterministic'),
  ('2967', '1c6f46ca7b9d1670c71218ff10b647370de368737039edeb9acbe44f46c7bfc9', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('2970', 'd8ac0c7791021f8d932fa32826fcee3b3c75630a23308b0d7b689d3315672a34', 'Lumbar pain non-specific', 'subtype_lumbar_pain_non_specific_29a75fb1e1', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('2971', '0aafca78b242b88bf56f6a2da6977dd451627fe9e98e95fc53ab7e3b44624afe', 'Rectus femoris strain', 'subtype_rectus_femoris_strain_5670ca194b', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'accepted_deterministic'),
  ('2972', '46b012a6b06741e391a35c54fe94adba99fd363c68a19856dc8f1fa14d768f1e', 'Disc prolapse/disruption', 'subtype_disc_prolapse_disruption_100f0c1c3f', 'dx_spinal_disc_injury_e3b980b6b8', 'Spinal disc injury', 'accepted_deterministic'),
  ('2973', '973c47ba7aa12ed53e0a17e3ad0c244b2bd86187c977d7782825d8ae8a3006e7', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2974', '562c3328294520c538ce45946ea15c68be1927218dd68dba4daa5678cf8a4d9f', 'Concussion/Brain Injury', 'subtype_concussion_brain_injury_be840ebdbc', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2977', '9e2d9d30141ee52462d968645bae0ae48d8193d7bf00f070984cfc4465a9c1c3', 'Ankle osteochondral Injuries', 'subtype_ankle_osteochondral_injuries_51605a67c0', 'dx_ankle_osteochondral_injury_7842c657f7', 'Ankle osteochondral injury', 'accepted_deterministic'),
  ('2978', '82186346504103c5b41f8b085608fb6f53fa1841dd58a7055790355ebea031dd', 'Mid/distal plantar fasciitis', 'subtype_mid_distal_plantar_fasciitis_0161a8fbf8', 'dx_plantar_fascia_injury_ec4d3703e9', 'Plantar fascia injury', 'accepted_deterministic'),
  ('2980', 'c806993198a2e9fc52e6a31bf22248b19aea3f0c41ceadcffb08b9b557529a35', 'Patellofemoral osteochondral injury', 'subtype_patellofemoral_osteochondral_injury_95dab31c6f', 'dx_patellofemoral_injury_a6e2fe370a', 'Patellofemoral injury', 'accepted_deterministic'),
  ('2981', '660ef136e1233c031c6f3d143dd176c96241accf7dac0d32b03c07b6f34e7cdf', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2982', '5bbba330a617e9d0424bcb8e3ee9023500aed43039c05df3608400ed1f9fa490', 'Concussion with delayed symptom presentation', 'subtype_concussion_with_delayed_symptom_presentation_df9f41a9b0', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2983', 'd65b4d725aa86d35626ad53f6559bd2aa86cbe2943151a174bb2066555a38e12', 'Fracture Middle rib (5 - 9)', 'subtype_fracture_middle_rib_5_9_a58fe86e0f', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2984', '1d6d4b4a3e7d426bebcb675a8d761cc579e5bfea79fda554e8cacec3ba55557b', 'Lateral meniscal tear', 'subtype_lateral_meniscal_tear_8f122c7931', 'dx_meniscal_injury_b166306f7d', 'Meniscal injury', 'accepted_deterministic'),
  ('2985', 'a572f5ef4ea341d36fc3e1b7c446690b7dfef8caba4d5b67461cb4821047fc22', 'Lateral ligaments rupture (grade 3 injury)', 'subtype_lateral_ligaments_rupture_grade_3_injury_c5dc81b2fd', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'accepted_deterministic'),
  ('2986', 'f37b23e565ff1156181ace5bf57a1daaa36a8227f2844aa4381464ce5a2f01f6', 'Foot pain undiagnosed', 'subtype_foot_pain_undiagnosed_9427f60898', 'dx_foot_pain_116521a908', 'Foot pain', 'accepted_deterministic'),
  ('2987', '00d0293b67b97d8a789be4c5d1702647e54221362604bd06fcf49fae84387f58', 'Cervical disc Injury', 'subtype_cervical_disc_injury_13c8608a7d', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury', 'accepted_deterministic'),
  ('2989', '8c3dfd19ce7abaff9d9b8384610ecb8561caae07bb1bacf33bef4df0224c5945', 'Fracture lower rib (10 - 12', 'subtype_fracture_lower_rib_10_12_54689f5754', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'accepted_deterministic'),
  ('2992', 'f2a77162cc61a35c297be73d31393b8ab4535e16b87d1e0bd27d88517c9e91f0', 'Concussion', 'subtype_concussion_a91e1107d7', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('2993', '2d9d3e51a948ca6699801ab5eeb95dc90a292007525b0f2ce46868d4a943c271', 'Lumbar disc prolapse', 'subtype_lumbar_disc_prolapse_b31dfa288e', 'dx_lumbar_disc_disorder_771d5d6a37', 'Lumbar disc disorder', 'accepted_deterministic'),
  ('2994', '3e3b28146ef6cebc60eae22ad730d3355b140f905cec617facbd4239461a34e9', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('2997', '509c8c4a984eb797918ed865a5630529b2a79bd91c7269b3b1a462bdc1527d10', 'Knee contusion/haematoma (extraarticular)', 'subtype_knee_contusion_haematoma_extraarticular_19a33609a2', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'accepted_deterministic'),
  ('2998', '98816574ccd46569af0e1ea317bb92453ac1f47227f028e95f900c597cbc521f', 'Neck contusion/haematoma', 'subtype_neck_contusion_haematoma_d4fc2fd301', 'dx_neck_contusion_7f04c7cc90', 'Neck contusion', 'accepted_deterministic'),
  ('3000', 'c5fdf97f6efc47ab0d0af7b4bf4c881ffdacfc91947f1d78c80dde6cbe67e7a1', 'Grade 3 hamstring strain', 'subtype_grade_3_hamstring_strain_6183bcd886', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('3008', 'ee27e46b35609ad239641dea5be395df7ab0ffecb67a1b97aba72ab5e9e0f985', 'Abdominal oblique muscle strain', 'subtype_abdominal_oblique_muscle_strain_5b04cf0a3c', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury', 'accepted_deterministic'),
  ('3009', 'a8334f57aff3d3d2ae280daf58ad8627cc112668dea5b2e083851cf110c31bcf', 'Popliteus muscle strain', 'subtype_popliteus_muscle_strain_da248dd71e', 'dx_popliteus_injury_0ac29f0573', 'Popliteus injury', 'accepted_deterministic'),
  ('3010', 'bbb246e69f3173256475e5ee14a0ba8f370b8f0d6e8270201d421a22c4a49241', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('3011', '45735eb60058a024a1ad801c3c246c3afe482f4ed32c8770fdb208e8705e7651', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('3012', '40a52b15951dbeb6214af70c7164bd72777aad134ec456565b479f13c537680b', 'Cervical nerve root compression/stretch', 'subtype_cervical_nerve_root_compression_stretch_6f650f0242', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'accepted_deterministic'),
  ('3014', 'efc9abb2b261968043d7924ba91cb4df9ca6790b6731154bcc3dfb15924bde5a', 'Partial PCL tear', 'subtype_partial_pcl_tear_ba3692c716', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury', 'accepted_deterministic'),
  ('3015', 'b029ca450c08eb83a45b55bdebe3167d4b39bf69022571969ffd9901cfd48253', 'Grade 2 MCL tear knee', 'subtype_grade_2_mcl_tear_knee_843dc46804', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'accepted_deterministic'),
  ('3016', '2ebc96c813af56b53211ba17b9bf19ec89ed0c2c78bf281cab1e4417db906f1a', 'Sternoclavicular joint sprains', 'subtype_sternoclavicular_joint_sprains_a347384997', 'dx_sternoclavicular_joint_sprain_6316623d10', 'Sternoclavicular joint sprain', 'accepted_deterministic'),
  ('3017', 'c5a40e915eb86d718f044f16cdec3313ee3cf0431adc67048792348d7b3c9b64', 'Common flexor origin tear', 'subtype_common_flexor_origin_tear_b246edb8bb', 'dx_common_flexor_origin_injury_b40614ca9b', 'Common flexor origin injury', 'accepted_deterministic'),
  ('3018', '56f2e35f2b8f85cb44e6de71d4ed1ef480c9999e3cacf6eedc9b57dfc0f87df0', 'Medial meniscal tear', 'subtype_medial_meniscal_tear_003d3c548f', 'dx_meniscal_injury_b166306f7d', 'Meniscal injury', 'accepted_deterministic'),
  ('3019', 'e55d5222abab330f65e73ab7e4adffaf94bce5aab49dfc2fb85ab357889287e6', 'Fracture 4th metacarpal', 'subtype_fracture_4th_metacarpal_692e2ae9f0', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture', 'accepted_deterministic'),
  ('3020', 'de12bbdbeed183cd9e6f8c1f70aabc6170fe5a3e7bbf9be66db83fc17f2cca63', 'Knee pain undiagnosed', 'subtype_knee_pain_undiagnosed_cd27746a95', 'dx_knee_pain_609ce718bc', 'Knee pain', 'accepted_deterministic'),
  ('3021', '6e2406daa878c3bc5174e78143e0b96c6e681026abc5def35830c2985d9db07c', 'Calcaneal bursitis (pump bump)', 'subtype_calcaneal_bursitis_pump_bump_ddfe297857', 'dx_heel_bursitis_d80d084f22', 'Heel bursitis', 'accepted_deterministic'),
  ('3022', '1de9067cacdbc223ffc02c65bb7d4e2949d7a8ea0f61cb13d74a7c2b34133d41', 'Hamstring strain or tear', 'subtype_hamstring_strain_or_tear_15b7ea6af6', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('3023', 'dd0ad858ddbfdf97c834d36535cc20631fd69ea9b6b77ef806194487dad2a07c', 'Fractured scaphoid', 'subtype_fractured_scaphoid_101f1c04f5', 'dx_scaphoid_fracture_906035d07c', 'Scaphoid fracture', 'accepted_deterministic'),
  ('3031', 'c55dae31080edac317b78c08f81d5133439426677542d5f93089034c7b243240', 'Sportsman''s hernia', 'subtype_sportsman_s_hernia_c9eeb6b61d', 'dx_sports_hernia_ad99f8552f', 'Sports hernia', 'accepted_deterministic'),
  ('3036', '0b1f353a4ce221bf5374a49b56e59dcf8e27abfd824febca57476d8c773aea4a', 'Posterior shoulder instability', 'subtype_posterior_shoulder_instability_7701a06964', 'dx_shoulder_instability_2b9f54f442', 'Shoulder instability', 'accepted_deterministic'),
  ('3038', '6bd9c4bcbb769d6863053b937774e47dc8f6d258054ce4d1af420b36cdc28002', 'Lumbar pain non-specific', 'subtype_lumbar_pain_non_specific_29a75fb1e1', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('3039', '53ebbb7cf2ed86dce09bc357039365b9746066c2128f61b9d0aa54fd684a44ee', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('3040', '1d4ff9c154ad48e9c2420292236ecfc9641ef19fcd0e882a2f6e2d9f34407678', 'Contusion/haematoma of thigh', 'subtype_contusion_haematoma_of_thigh_3fb31f3797', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'accepted_deterministic'),
  ('3041', 'fe73e325066f8558b2bb9b3192b070b48ad6a8558f47b0358e11e08e15e868c7', 'Knee joint cartilage injury (unspecified)', 'subtype_knee_joint_cartilage_injury_unspecified_6457ac12a3', 'dx_knee_cartilage_injury_761df482b3', 'Knee cartilage injury', 'accepted_deterministic'),
  ('3044', '9cae5ea1e5335909ff9f819fd76d05715a5554bba0ebc90377e408bc3ce468ec', 'Lumbar pain non-specific', 'subtype_lumbar_pain_non_specific_29a75fb1e1', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('3045', '36632a11fd2e5dbb1aad2656a093636d9dc483caef3d0735f1c6987c9c17f5c9', 'Lumbar pain non-specific', 'subtype_lumbar_pain_non_specific_29a75fb1e1', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('3046', 'e57d890284b5fe1125aace957cac9cd1399b7b76042816c6908f2be4433adf85', 'Hip/Groin Pain Not otherwise specified', 'subtype_hip_groin_pain_not_otherwise_specified_742fb1cd99', 'dx_hip_and_groin_pain_27531edcc3', 'Hip and groin pain', 'accepted_deterministic'),
  ('3048', 'd57cebbd730148dc5bd547c1762ea2fdcc4d131de1bd1b3fe3219cd4b84157ef', 'Concussion/Brain Injury', 'subtype_concussion_brain_injury_be840ebdbc', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('3049', '197070a9fad05acdcb46c2bb6ee62a98f930297142ae35975cded13fb869f1d0', 'Elbow UCL injury and common flexor origin tear', 'subtype_elbow_ucl_injury_and_common_flexor_origin_tear_447eb313bc', 'dx_elbow_ucl_injury_and_common_flexor_origin_tear_447eb313bc', 'Elbow UCL injury and common flexor origin tear', 'identity_group'),
  ('3050', '3b7c6ec248bd1b47cc8279adec6a1535694113919ec1111325a8e9f5c4dab124', 'Wrist fibrocartilage tear', 'subtype_wrist_fibrocartilage_tear_aead44491e', 'dx_wrist_fibrocartilage_injury_fddc60c8f6', 'Wrist fibrocartilage injury', 'accepted_deterministic'),
  ('3051', 'd5c814cc6cd3d90912fde513067f1fdffcde75f97f15271b077d52a72ac14de4', 'Achilles tendon rupture', 'subtype_achilles_tendon_rupture_6b59cc3783', 'dx_achilles_tendon_rupture_6b59cc3783', 'Achilles tendon rupture', 'accepted_deterministic'),
  ('3054', '1577bd77dfb996f0f761ebb8967c179ada6747e0f960f5d17680459f80f2da3c', 'Grade 3 hamstring strain', 'subtype_grade_3_hamstring_strain_6183bcd886', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'accepted_deterministic'),
  ('3055', '0af5fa0b72c1b784672e3d55d233e5cec934174a73467633d25286dcab5d4201', 'Concussion/Brain Injury', 'subtype_concussion_brain_injury_be840ebdbc', 'dx_concussion_a91e1107d7', 'Concussion', 'accepted_deterministic'),
  ('3057', '40b0ea05a949c95fc58d67562fc9d385af35578f632c8a7820eaaaec7b81dcc4', 'Lumbar pain non-specific', 'subtype_lumbar_pain_non_specific_29a75fb1e1', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'accepted_deterministic'),
  ('3058', '7d88735862d1d6eb9108fde3edafadcf97a771a22813dedb954365cdaad034bd', 'Soleus muscle strain', 'subtype_soleus_muscle_strain_c78da38c9c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'accepted_deterministic'),
  ('3059', '54df9d04bb9397c036e3c7714e0664c9543632b6099e70eb5c8de6740939f97e', 'Ankle sprains', 'subtype_ankle_sprains_cb1ab3d70a', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'accepted_deterministic'),
  ('3060', 'ce4e65ed183f1fa546f1a5e8c7102170debe8394deb3cdfe04f1950a6b3c2d7b', 'Other Ankle Pain/Injury not otherwise specified', 'subtype_other_ankle_pain_injury_not_otherwise_specified_3d735e2c86', 'dx_ankle_pain_de6b615afc', 'Ankle pain', 'accepted_deterministic'),
  ('3061', '692e0171b61918b1b50af13370ef16621433ba747f55dcaf1744b9681befab01', 'Fractured phalanx (foot)', 'subtype_fractured_phalanx_foot_a65da95620', 'dx_foot_phalanx_fracture_674038ca61', 'Foot phalanx fracture', 'accepted_deterministic');

create table audit.urc_2024_25_illness_profile_source_rows_v1 (
  adjudication_version text not null references
    audit.urc_diagnosis_family_adjudication_evidence_v1(adjudication_version)
    default 'urc_diagnosis_family_adjudication_v1',
  source_row integer not null check (source_row > 1),
  source_row_sha256 text not null check (source_row_sha256 ~ '^[0-9a-f]{64}$'),
  source_label text not null,
  illness_code text not null,
  illness_label text not null,
  primary key (adjudication_version, source_row),
  unique (adjudication_version, source_row_sha256)
);

insert into audit.urc_2024_25_illness_profile_source_rows_v1 (
  source_row, source_row_sha256, source_label, illness_code, illness_label
)
values
  ('404', '19f633f1f0efa4a3166222406fe1d33542f8dc0b74234a20ab0fd0b4fdffbf77', 'Gastrointestinal illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('406', '37d592bcb35679e542397f0cf3b03857ebb650423d0d54820884b9c85c581fea', 'Gastrointestinal illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('407', '76d2ad4b46c64b341f49fd9f6e5223c17ef0f8680a05b18b03423394360b432a', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('410', '6fa94cc010e6092639a0800b9966da0670cdf6d6c7ff445d7123057a90f43c05', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('417', '8531681f89779bab98270a8a5adab2dd09288db342eedc00ba92da976a6d2ca9', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('418', 'd902a7ad8ce98d13004aa936159d5084c7e5bbdfc42642335e352589ddca7587', 'Gastrointestinal illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('420', '6811b688b712779a4902bef1ff3c44089623e55f8e502ed154a3dafb871dade4', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('421', '2c444c6e0622716773da0f4ff8fb3f7a833c6504840467657108cec8c2f599f3', 'Gastrointestinal illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('425', '49bfa9aaae9d32e891484a3d076e7238019719a990fad808ee9b8df004592cc4', 'Gastrointestinal illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('429', 'bd8b077c1050341f411408a69a9a63f825d1ec22355101c3027b24bb5dc1f9c8', 'Gastrointestinal illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('430', '5333415381c4d8a17293d2ba3e0de8e4a2612f70409bafd23ade3080c70bb347', 'Gastrointestinal illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('434', 'f9fd6012ff0a765b4a574c1bba74f5d3c4a102a97ec4e80c32b973c70cba2aab', 'Influenza', 'dx_influenza_27addce986', 'Influenza'),
  ('435', 'd6bdd04b43362d42213cc6f41a787877d99bfbfc43f8061e45601e25e87cacd9', 'Influenza', 'dx_influenza_27addce986', 'Influenza'),
  ('440', 'e2a42e9851c304f5ffa3d3dc072b3e690b29d7d0568bbead615a705763874749', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('441', 'ba929067cb205353a043ade78e83b169ae01dddbb07ce29b0847d9fc20bed776', 'Gastrointestinal illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('442', '841d1a0bdc2586bba068267a3af96a8b2cdcf5b79746f8840c97edd6d3644b88', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('451', 'e3ed5fe287c6bf979653c85904094b76d2fe02661064481ebc0c356b8823db16', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('453', '3702977a336511fa172e5c093da995ebf4cb73b39d24d98fe569ab7ba1ac90a7', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('455', 'f51627ac04b236e6f96aabbfb48977ad8a1437a004f6a88a8ca5f5ef088d2cbb', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('459', '81c28706c5ba233d410e1e0642b64d5202a17fbf41c527261f87209b0fa88f14', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('460', 'f324ac574bb41172381e13fdaa7e2f0d34f2451b946e5c09f374956a8313905e', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('461', '5bea43d14b5cbfc66ea7f7c0e93bfdf5848c2d7d4e50ad2093b5a298c0bef2f9', 'Bacterial gastroenteritis, including food poisoning', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('479', 'ca1b8954c86659f8497ebc47d24a071254672ce5c561b299307d8b034a623667', 'Diarrhoea', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('480', 'e4febdcf5f7b9b053dee2e48635c114ff365a69e88ee28c1ac987f875976619b', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('481', '5a74cf4f0ea9d2d06595ed620eeb0e77ec1be71ca0d42a6e60e4f84f279362b8', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('483', '9aa361fce8d6aa93dd2735f71c36636965b81321388d8906d3210b3c19780690', 'Diarrhoea', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('493', '5b99a85371c8613eb5cb87b0bb5693cbb447ebb7769cb0f2438d34dd3564a336', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('494', 'ddd345839aea283cf7d8cd8e6603e005f4346444c30599f4527eeff2a5f004aa', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('501', 'a19605e127042c7ad2fea817465667f1f05cc55ca3b96e59e87669c503b624d6', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('506', '7e5a38a78d48ea5f496fd769fe7123358d6a513a9418c32c3bb44a58b6dcfcf3', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('507', 'f7f0a898c552cc4ffaf57a11ff8d8aa71597ee1fc61a41bbb6b97052a78efc85', 'Gastrointestinal illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('508', '82805b6bd429e9f1444148831c0be78097fe791af94cfcde36d7a1736a80ac16', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('513', 'da015d47c26feb448dedb6f69c9733ab0ef695cc5003fc90c26a3e58e8fc01fb', 'Gastrointestinal illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('519', '3a90bde06c513734687aa91f1b9a7e7ba9be8aa3ee61e03904c6b3a50e8467e0', 'Gastrointestinal illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('522', 'f088ce354cfeb0a74dca860f1082bad919c35e08683747806c9c8ff0f59c7be7', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('527', '799aa00f9d432487767ab813af286c3499da326f03ce717aa5b0ea3cb1bb140d', 'Gastrointestinal illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('532', '02df4b4c09558715e9ca7a6f01794e8e478550f5f69e7699f428edf60244960d', 'Influenza virus infection', 'dx_influenza_27addce986', 'Influenza'),
  ('575', '42888b14e3107a2bbc75fc0e319d889bc22477ada15757617c086e6100f3ea97', 'Anxiety/panic/compulsive disorder', 'dx_anxiety_or_related_disorder_fa6bf088b3', 'Anxiety or related disorder'),
  ('589', '141369972e37e078a0a71641f33303569dd6d814cadeac11ad7f76b6f301a816', 'Ear +/- sinuses/throat infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('590', '83c31227f6ddfb6241b1b16975286a17f0db873cbabe2ece4a94eeaa0997c97f', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('609', 'b6162458f5635cd9343186a9ff6794d4f5288d9458deac000b60ba965a8aa315', 'Skin Infection/Cellulitis/abscess', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('627', '30740874ecab5913d5019de084d20349ba2d73e860cddb1d2d711f50ee961a0e', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('650', '653558f1ce016f30edae4926a005dd4042e3f335f9b611c8b2b9bcae3caec07e', 'Medical Illness Undiagnosed/Other', 'dx_medical_illness_33b4f89cb8', 'Medical illness'),
  ('653', '0fdc1869e93f26f40eb37e33066140e0d64601e34ee86dfd6bd32629cc414d69', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('658', 'fcb6cd385b1526813a4ecc70f3e16e376daf68edade3e1d5523170b012800943', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('659', '6a34856644b3c0ebbc760ec85b12df1ccc29f14ee6c6ed5ea6ab151dd6ddd317', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('660', 'e2cac5a107aa10974527e1f2742078260fb8cdfea245c2fd485fd6e6b3c381af', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('675', 'a50e884aaaada47489305477a53e5aca8b88e6599470dda717ba01e452c1fdf3', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('680', '83b7ec1039ef6c7cb5003a408a20a1caae6ef7fe3ee9a86f81254c00deb5acb2', 'Ear +/- sinuses/throat infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('681', '26f271aa8e6765db004ed158a7958b861cabb306d20d1262b932bbfefd1a01b3', 'Ear +/- sinuses/throat infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('687', 'cd4f63e4e46e2357a5e143ff9bf4b2deb655faa70466e32b8e8afbed219304f5', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('688', '9fe4b617ae33e7830194b5c9d857f55807f26d0778937b1888a0073f8e487b28', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('689', 'd9abf742d33c49b7cdf9faeddcc46b52d8fbf80da2f762e44372d882b615460e', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('692', 'e50fa6806660a52f31700ebd22cd7a62cad2ccfd28edeb2d87197349b292d4e2', 'Complication of forearm laceration including infection', 'dx_forearm_laceration_complication_d9523be6e0', 'Forearm laceration complication'),
  ('701', '9c0e99ed3783153f9652c2e32fb03c6d6339f5a1cfa4b88296bea314df4bcd61', 'Ear +/- sinuses/throat infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('703', 'ca9e2ed1ecd6efa8fbb6d6973c2ad89065d7256d41a1f47887db3d8cb7edf2f9', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('704', '88433240eeaf268562c5d541cb3fbb1ffd028aa9439a9e6ed768f9e8a4c22972', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('714', '180fde5f199946aff918f483a0bebc5d405baf9d3b49224071addc6b14280adc', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('720', 'ee8292aa20be8b2c685ca91163431b71639c9e62380f0868624a84223748ee34', 'Tonsillitis', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('739', 'ea1e373d55b6f6e22484f4b7e8ca15794f395679e3c9b2f1e06585b9dfd5e37a', 'Skin Infection/Cellulitis/abscess', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('746', 'bf497645e5afffa345dd95c7018208cacca3494d2e78ea415f04b1649211ab40', 'Mumps', 'dx_mumps_822dad4efb', 'Mumps'),
  ('747', 'c341ad43370265357224ec96483e31c481e4c04de50613f9d90c31f12e20e1ea', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('754', '464ca59466cbe5f8ee18ab73047ebda0e463c508420581a532711ed318967917', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('755', 'e38aaebad46ddd2338016bfc69efdef0c64d25149a34dfc40165dac8744ffea5', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('775', '33e1f5c344610691a7c58371216db48658fab031333784fa2ff4ff3af54e9397', 'Skin infection head/face/neck', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('833', '9c31fcf45931570248a1dcda4f75cf39ec83c7a1670f8aaba1bad3baa0057cb2', 'Ear infection', 'dx_ear_infection_da58e903bf', 'Ear infection'),
  ('842', '776e17c5d8dc488d79bab4e48a8b168f98a036f7fe8177a8ca577fd4384b045b', 'Skin Infection/Cellulitis/abscess', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('843', '46e91ca0753fec0ba267cd47c1eeb0069508162e8450d40d4df314bd7852e424', 'Migraine', 'dx_migraine_d6c8001cb9', 'Migraine'),
  ('848', 'fd835546f2f9d057108b99bf1684cf89e5a3ecf16b64635424a2d590970f77c7', 'Medical Illness Undiagnosed/Other', 'dx_medical_illness_33b4f89cb8', 'Medical illness'),
  ('851', '05d7cf2fddabee36a16c430ea95005eba5ffa71abbc1acc38637052f39afa6ef', 'Pneumonia/bronchitis/lower respiratory tract infection', 'dx_lower_respiratory_infection_8a34a48ae8', 'Lower respiratory infection'),
  ('855', 'a74c05670d1b50d6c31cc34ffb9a53de5553a22f76640f37d57ece6aa9e5b998', 'Herpes simplex', 'dx_herpes_infection_a87b003a4b', 'Herpes infection'),
  ('864', '8a6efa43199642e2eb12d2cf862c029c13306fe49eddb09a495444bc350e96a9', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('895', '74da8f1f6df2ee8cdc68e10721dfaadd9e068b2006eb16f555ec49b8eac588c4', 'Other lower respiratory tract infection', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('896', 'cdf55d9e86547cb04220fc9236091dbb08905a9288247bf2e75b3a4561aa034c', 'Asthma/allergy/hay fever/respiratory', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('897', '1a322d952a15d586b7538bd3fd38a20224ab5526559242586acf6ad9b69fcb3c', 'Nose /throat illness /condition', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('899', 'bf4dffb3242725220fc01d882f74deccb74dda8a95881226c013bbc6aa88f37a', 'Viral gastroenteritis', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('900', '0f3e687bbe7c030b19be3a98b7a55dc44b427452605a3c2e37f65e0af82d7990', 'Nose /throat illness /condition', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('901', 'be5796cd1345fe4233f14d7079eceda4340a861b848a0293459a09e5c1efe909', 'Viral gastroenteritis', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('904', '34b3b5a714be649889a805a8a413ebbe52a30ccfa3cb8646537e1775e1aa7114', 'Sinusitis', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('927', '062db2dc775c3f00ded5793a3945c537f25b2b22b0514e42aa03fd94f400e73b', 'Diarrhoea', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('928', 'd0f444137ef082d2f6612d4122b6fcad254f9f8b8cc1ad22d1ac5c42e6d9a52f', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('929', 'c31fcd82e315e7d50493fc15ce94a5f5167c033d324c7b840cc86aa6882a99cc', 'Nose /throat illness /condition', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('931', '26575b4f9cf371c69166abc134ec93bd67bd3704ff53535aa82317e61950e058', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('932', '61cf406e55f2241345c3ab1abd624a5c505c3db1a503df6912ff0d966589dc11', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('933', 'ae8992fca734b46b627cac23b0745ab32b4c58ac18cf76746d94000549e14ef1', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('937', 'f673fe72754a2031798b4eaeb8273d89e0ab8a9dac8c3497b5097b4ab488a77b', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('946', 'fd3283c00231a558e073e69f8b7d517a4fec7c615dbea753a7b29810d1841bd1', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('950', '584d99bac7bcb63c578292d8ccb9819a5c94aa13d659d1abe568e730fa350819', 'Rash /other dermatological condition', 'dx_dermatological_condition_cf62967c16', 'Dermatological condition'),
  ('951', 'ca6047003c2ad30e7811a2f4e1c6dae55e9f3f3306e8b970f8138b46851c5a5a', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('952', 'a3622cfa25f80a2a79c471cda2e6095e547d636ea6a0903f13784558c406acae', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('963', 'd2995860e94ebc645536033bda4a8fe7c59f8eab0fc6cee89b48a9b8d726b90a', 'Other lower respiratory tract infection', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('972', 'becc9ef8758b0e0deb1a8ad716e240f30421c03a7154590017448bf0a1b09f90', 'Complication of laceration incl. infection', 'dx_wound_infection_complication_5415c9f38d', 'Wound infection/complication'),
  ('985', '56bc07b92dd6315b452293e81dde951f106703103a4e34f075d7de2b0162926b', 'Skin Infection/Cellulitis/abscess', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('987', '1da3f1b1fa3391cb1d82c138d8ee966d219179c27a5f32ad5906488bf125f87c', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('998', '3e1fccf4faf093e451b65b41ed1328bca2161a655be02167854bd9f95eafd551', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1000', '22d135941fe85d263753819a5c13521fc16a7fc8c94e4268c5873279c12a8c8d', 'Skin Infection/Cellulitis/abscess', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('1001', 'dde12bd1e783c9b8a43d88a9c29d20aebcad2de6c609d9ef707fdfe8566e0028', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1002', 'cd1c08a71067a5050cc438160eb3e38f7d6d216e79426286bd7a148fce828d7e', 'Sinusitis', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1027', 'd7587cd0a7d6d32958d5f56f96b78bd8540e3bc0a8b1f755d4902b880ba92049', 'Herpes simplex', 'dx_herpes_infection_a87b003a4b', 'Herpes infection'),
  ('1031', '333ff277eae03fae0d25d7b2b1121883fadd87092624811dd02e41bf30c8b746', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1033', '687a300a006e31968d9389d961b3bf5deb804ed1c2848bf9c8cd8d624be4cc85', 'Other gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('1037', 'e3943aab5d75676b6ac60082bdb726d2b265bca504108d477154c6deddec8e90', 'NSAID associated gastritis/peptic ulceration', 'dx_gastritis_or_peptic_ulcer_disease_2685b6a7c1', 'Gastritis or peptic ulcer disease'),
  ('1043', 'dfaaf7e2b243321bba8d600cd0d93854eefb60a1e880f29063e27d58f263ff4b', 'Asthma/allergy/hay fever/respiratory', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('1049', 'bc492f21f60b3c4a5c7ddc82c3618560d14a47d749bd519eef185dda89a3c365', 'Concussion in a player with a concerning history', 'dx_concussion_a91e1107d7', 'Concussion'),
  ('1051', 'b00a9e78517073e85302ed9e873382a4b54327c50b3b074a1d50892d9329361d', 'Sunburn', 'dx_sunburn_43a7926700', 'Sunburn'),
  ('1057', 'f9c61134485f24de122d395b8653be982a9eebd3800235f68fd14c642c9fe5b7', 'Skin Infection - fungal', 'dx_fungal_skin_infection_3158ef505c', 'Fungal skin infection'),
  ('1058', '8aa354c228032cb88f6c7a13dc9dfeb6ae581e4eb9dce3ffbe40cb6f4b342b04', 'Skin Infection/Cellulitis/abscess', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('1059', 'e3a1c537ae2ba34fe4aa654cf4110b41c0c676a1b7c5db78e43aeef56bf1e76a', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('1063', '7951e3495fd37d48fac1862a3631cfd14809cf1e2916d5404d8904c365d86fbd', 'Herpes simplex', 'dx_herpes_infection_a87b003a4b', 'Herpes infection'),
  ('1065', '01492652f6a769f5ff9ba70185f2020bdcadfd6b64140ff6938a09e07146faf7', 'Other gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('1078', 'ba9047442ff2d6906959f1e799ac320bdcaea99b63a72071ad141c211583dc51', 'Costochondritis', 'dx_costochondritis_3202be581d', 'Costochondritis'),
  ('1084', '35c1e91f9ef12040b17e635be70b6dc21e6e051fa23607a5ff9edabdba144210', 'Skin Infection - fungal', 'dx_fungal_skin_infection_3158ef505c', 'Fungal skin infection'),
  ('1091', 'ac4eb92a49788657ae2bf5607c90bfc3868de20a3cb39da83d47cd5ef0a4b8fa', 'Skin Infection/Cellulitis/abscess', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('1092', '1a6ce1d4eeec208878dd8076e13e4e091c600f1c8169155f57f522533b87229e', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('1107', '3ead43b691d20bb0db355d08555a447fbd8687324de56a0f403bfd79c1d7e8f8', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1108', '0fcf2d1b857e8be4292a81755b760fb5919033bf877da8f29aac9be21d9243b9', 'Skin Infection/Cellulitis/abscess', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('1130', 'a63303ad84e9f784ffd27ff59a5c61f6f6e672a9f292f0e2a79c6ef107631946', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1131', '3b3716b62d4c61a513f9080beb7b1e7f1dee1ab500be8ebc5e069c3b0063703f', 'Skin Infection/Cellulitis/abscess', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('1168', '7f4e0c0e5b0155fe072e85785c62d533b457835256bca9070c094bd9eb77b614', 'Tonsillitis', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1181', '889789232e0ff294d646ebe93c0878edca8ee811eb865abbcffd204465220564', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('1525', 'f5a4bbd74de8c9f1fb26fad1f43724b83ec664c7eb5b62394594458dadafb9cd', 'Gastritis', 'dx_gastritis_or_peptic_ulcer_disease_2685b6a7c1', 'Gastritis or peptic ulcer disease'),
  ('1531', 'e4c1073a2223d73447ca145062e4b6121dd5c85ebedb6b0f96457f3187a02ef3', 'Bronchitis', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('1534', 'd3e7fa983f4a421a93b70def9e43d2e50a9812ed84f35f6807e4ec33cca3776c', 'Bacterial gastroenteritis (incl food poisoning)', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('1543', '9205cf62231a3c85c1f1b0a7507714326a5c8ad717dc3efb868f868fbfd2a428', 'Bacterial gastroenteritis (incl food poisoning)', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('1545', '59c6e7781e3ff8d8e20cfdf77908c408257e2ecb8ab6a316413674df26fdb762', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1546', '07ed729a5cf35f3f16b34f5f2824198ac39e824aa08b335c9d80d0a9d146dfca', 'Migraine', 'dx_migraine_d6c8001cb9', 'Migraine'),
  ('1547', 'c7a4c4a06d69fb54119cce8a7664ab90aec13e81d4dd1a826ee750011e471321', 'Influenza A or B', 'dx_influenza_27addce986', 'Influenza'),
  ('1548', '1a67e7a07eb26192a0f5496f17560fa260b3c39711ed1c0d96b860fc8fccd15c', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1550', '600f23f90aa327fa025aeb3ab9009cc6786a88bfaeaa909a7db276582c41dfd8', 'Tonsillitis', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1555', 'd258ac52614e177c24d0474aa17b38ce1b865a452aec98ea11a9274507a7e510', 'Viral gastroenteritis', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('1561', 'be11fe7700663c58a8a8a108bb492e59d6a9a8c46edb004d6338d3db9b0ce82c', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('1563', 'd57d0739c5da81037b2807f58708dd93ef90ce6a4b0e084f7f0ba597c9e4d24c', 'Bronchitis', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('1565', 'a607aa4247ed2f4ebeacc2fbd48842a184f4bc9b03a2092029523b6ea9791b5e', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1573', '646062ee4d942b8a36f66e864bcce70f743562adba7cfa230c479b13a0d496a1', 'Viral gastroenteritis', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('1574', 'db68babde70cade80d0e491f62609ddae3256fa192b5e8e573650b461358bae2', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1575', '3036d21ad0e1b8f82c574af94222682a74a2690545173d1cdcc60cd963e2bdd0', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1583', 'f67dfe2cb4e99bf8333d5bc91df8b264f5826c89b71df9d061617a27e63ade35', 'Bronchitis', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('1584', '752de5c3f03737c2f4e58cec4e2a132b96f23d60032bb9c670c628c6e35c9ef8', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('1587', '329f0489d7efdda511fbba91368f9e2408ed6ea73b014c43cec454b202e05aeb', 'Bronchitis', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('1755', '3c8b9248f4d5bff614cc42edb630bcc87cb0fb4fa0f005662b3638661fd792bd', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1756', 'bad51eae561207153bfbdc464e49bd9410c30ab1b23b111f6481d4f59fe03fe9', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('1757', 'f895fea40a3ce92bdfc81c01f41285a90d6edce2f3708c6719c9de2919edd198', 'Dental condition', 'dx_dental_condition_e9d2167e5f', 'Dental condition'),
  ('1759', '7e190e734530a17f659687956effe4133b7ca7429396febb7b584d971f460d21', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1769', 'be4abdd4085db58289cf3fb97e2dfcdd126fa4e0ab674d8ee4182244fc0ab5e2', 'Other medical illness', 'dx_medical_illness_33b4f89cb8', 'Medical illness'),
  ('1773', '4fda2a1abaecf15c8a01423b85fa74054c75ab0e2e62a99414af8689b4407dc5', 'Dental condition', 'dx_dental_condition_e9d2167e5f', 'Dental condition'),
  ('1776', '33f2d2a51d41add869b1fab5dc51454b7710fd41e94a0c1257658674837e4635', 'Diarrhoea', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('1782', 'bc248cc83436e7154d39ba55943d2ba26288a7705c5bd09790591f482d238a59', 'Influenza virus', 'dx_influenza_27addce986', 'Influenza'),
  ('1789', '8d00c316a032ceb4b6bd67f16ee03851c92af249ef9222e68a3502e490bfbb22', 'Dental condition', 'dx_dental_condition_e9d2167e5f', 'Dental condition'),
  ('1790', '3c6656073a64b7ac79badbafe253c0633997dd5901f6d62e1be0a4ee7f03b3d5', 'Influenza virus', 'dx_influenza_27addce986', 'Influenza'),
  ('1793', 'd45065ead941c1982d110b3da8c03a729670797afdfb85796ac06ef94cabbb2e', 'Influenza virus', 'dx_influenza_27addce986', 'Influenza'),
  ('1794', 'ae8d6c8b37dcd980c8b6254feb0e345d41e0a4484ddf820a185b3efc7e1b3297', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('1831', '0cc1a08e7a3f6a481bf507193f97ebd7d316ad11f4be2bce37311003b46f0a7d', 'Other respiratory illness not otherwise specified', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('1843', '7b238e3cb4591b0769eea6c93c47b9795d7c7243f6b3e2397f2bfa5ec173b30f', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1845', '47aaffff7721e741652373bc296598510011848362b93eb5efb8dc1a972c33f9', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('1848', 'b544d3e86f7963b6176de1421c3926ce12aadca8be1b8e3e11242e0ecc6b80a8', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('1871', '4367e760443d4e4ed517afc4abcce8cd7dfccda812b1016ff05df8e8d1e1a061', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('1873', '399e61e7f23b0ceea5a538c3ac276d880a58dd3e842483d1ed5559a05eae2166', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1874', '4c583673b4f7ede48efb802bd0ccb8dde1f9ef64b62db677618145726c9b0323', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('1914', '1c1758d34016e4cd7432ef2caf71f61e46a74557088889923121f148c1c7073c', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('1920', 'b5d4e5dc465b848400de1777fb9d5496e25fa464d208d25118f70dc7bb10ccd9', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('1921', 'd2555a63e0c1ec41745dffc4280fe370b0213a0ed45ac60cd03df8c8c0e123e8', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('1934', '86d7b5e9cfd1eac0b1b8b3a30a5f90f818ef1bf134fff170d28675652c1c510f', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1935', '666b4bc58e7ffc75fb8c889f6bb347896b0077ff9c1073ce6140953b38aab193', 'Other respiratory illness not otherwise specified', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('1936', '9066555d8b72281582f6031b108e5d968eec91e6f38a98baa687e9295a64b677', 'Other respiratory illness not otherwise specified', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('1939', 'a38fb6e3b88d889eb67e9fd35d6177a34a7ec4c98d6fbc70ad3be7481e0debf0', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('1945', '3a17f559568c0956cac0d8c14fc5590240ef8689f6fbc028b93bf2566dbb292e', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1946', 'bb96233df8f42bf718a428e5188306004a789b299975ccbf9f2cc81f578f4f3c', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('1962', '91f4fefc15662a3d546ac60fe4a4a6fa3f61888383fc9bf28cec71c76d205ec4', 'Other respiratory illness not otherwise specified', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('1970', 'acc37854aa132de4780d463e51e3a88117d66ccc6ccbab8bcce82d81d3d03eea', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('1972', 'af2b3cda344ca6bad51fb04a5e0d954c27f5b2389699a307721e7048334c18cd', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1976', '19dce344183fb827e079b9ea72c54d284d888d112129143077fd1e1e842c2d67', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1977', '2cfe133863dd1bcf3563e5010cb1655d93f8819c60329922bf703a770eddd49e', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1978', '4d2805efcebb43c79535844ad4c8413b8d69638588d3655e1a2cfe5841ed8212', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1979', 'c12768afb40260881dc161778ef0ce5152fa2e12c254d4bdf85a5844a7110008', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1981', 'ec01805c6645898c6142d8e48243ce8b1e046e69ae47bb16cd290bf2cf893a24', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1982', '28460ad88e5f7bc037b207b776e1f8d2e19a30e881068fa0d2d5a2a36bc2bd42', 'Other skin infection not specifically mentioned', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('1997', '9d2c244c9880ff001d3df6aa45cd9477fbede22940b2a51424758c34cadd3faa', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('1998', '316b6eae5aef5fc53b8fdd388d1a08d129a70bf5ec520d8fd16a30c682d5a0d0', 'Diarrhoea', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('1999', '149011cfcc7f5de5c336ad663101bf48ceb7413b35cedd34fdee56f49111e571', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2001', '525f302941ff340113953d071bd303ad55d509e94e63013993810ceb219e200e', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2002', '52b14ad6560dfebc09067bac715b8c9cc11cd204f03e103a7e6beaee36f84dcd', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2015', 'bebd7b20e03162effedcd41dd75b67769ee0e442b3e0502a60c1ce663c69e042', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2017', '976d804ed09774649480121b8b7e2e672265c7e16218dec4cd6242be271a3941', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2022', '1f70810ecf2999285a6e03d6908936904c305a47642cd6fd7699328185fc6ad0', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2023', '4235ca3024ba8d35a20a5fa9b1403ba11cad71885de08df4eac0b8e508fda554', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2025', '27975ad82a2c5cd86a2ff862f94fc88041395e944c79762e79d2915e50fd7e93', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2026', '05a8e81cd6cae08e8c032d0473f496a7aad3b0f827e5745b4baf1f8a1f2af3c3', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2027', 'd1269e50160ec19caa3c9e7ac1925198b7fc2c88b746872cbd23c8be7f7da736', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2028', 'efc6975e9066e59c5e04c46916630ede071c4e75a86066b9b3e0f23bd9d7a9ec', 'Glandular Fever', 'dx_glandular_fever_2dde147b25', 'Glandular fever'),
  ('2029', 'd6122c338126b3948bbed5d0b1d8fb4de03920b4acbda06156f2a4a00dde5b7d', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2030', '09b10adc598c7203cfcc2c18aa9c1b41946db5067ec44bc6a299d17f363f0140', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2036', '4c813309bd29a02ced693240e3ce46d0ab903aa7a75b8324d35e11e45c503360', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2042', '1ccef92c5d87065659504b2c38db0c9d0390e1a1c43f5e9989d0441f84b4a628', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2053', '63957b06d0a08ffd77ed35fefcf25648938cb84c581cc16bf37e11771da7a24b', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2054', '268f5573aa02161b0f1e2045ee864da5da56aea75a29f53e4bb3b66240570284', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2060', '91a50ba15cf20d7db0509b5ef38c8858764c0952fad63992e0ba5216b91abf90', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2062', '54d90aba4ec941f07104982f31d911a2d5bef625773b6be9b7162ff290b4e46f', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2069', '035ba84787c0a280a74d6b3e2b70919e8f92fc25212f6c93dece4a44200a0d2a', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2131', '73f9ff18ad00570d406b31808e86b18730f680f7c59c2f3e18b47bc41e45550c', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2133', '9c6aec0a383a2f54cc78b99ed1b6883f3b833dd4d9191ca9bf2063ee56979251', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2134', 'e16fc5ece48d3c9d3ff0a9e991e5a48a97aff65e754edcddf05586cba96dfacf', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2135', '7717513f9680de5f67b7a9c4c93407e49cbfe8c99b7399b27d9e9208eab725a9', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2136', 'ea98b8eb950b9ec94128421d5d8112fad6654ce119aac23d8ac98b0dba8f3b66', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2137', '7c1f74adc6cb221c49b98fb1f7704863e2d17312476ea9f616b9cbaf19fa2967', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2138', '66cdc6fb04d724dba3e4868d5cf648e6d7330ce0e7da0eb28fc4c89a60c77101', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2139', '9f4b52f4b11fb561eacc162787e5fe535b9894277631a41e2d0a083493b3e647', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2140', 'e61ba22129c328e97b3892d143561611f55710c6011e7937c6492ccf4b47eef1', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2141', 'de6bf83cf556a80172f7fd478f62626689719e41a0df74b112d51135658747fa', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2147', '039a8dc798c24a237b39df2b015799256806e7d89fea6cc46f08ee58cf725c6b', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2148', 'aab410c78f141e9345092bc14ab0d811e477614b85ba9d7425f4955a37da04b0', 'Other rash not otherwise mentioned or undiagnosed', 'dx_rash_8b717bdc92', 'Rash'),
  ('2149', '5bda705d34dfd0ae8a283bb2ed395513e10fb294e7e1c94c5e9f56d8832a60b6', 'Skin Infection/Cellulitis/abscess', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('2150', 'edabadd1eb6a7c2995b4fa5668d64305ecf79999ff0211cb849c0fe81c97a708', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2151', '966ac0b769f668558c1221c4b0b0177f289e11adafcec4c33ba7f9bbf8d829a1', 'Viral gastroenteritis', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2159', 'aa1461453aff5d19c659b12433b44c4cb1e731ff8abc9317ade0c4169f4f7ad7', 'Depression/mood disorder', 'dx_depression_or_mood_disorder_be85ab8119', 'Depression or mood disorder'),
  ('2162', '5d4d10c1350f430eac2d285c178a1f4afb2c76443204f384ae0422b42bfc6b27', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2163', 'f2fa2c278df2c6ad32a63d60331bfd0a16dc8ab6977e54b29485dd10393f43a0', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2169', '31ae0bdaebb6480b332bab79b03e9b2403c4b36ecb1db8f5e7aee89c36be9421', 'Herpes simplex', 'dx_herpes_infection_a87b003a4b', 'Herpes infection'),
  ('2170', 'de51ea3a8878a77e8e65b0de427ad0f274433a71b93d1211e6beaa0b2cde786a', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2171', '8fa3862c535be36d2443150bc86eb0cdfc28b4306172e53c23cb5b032ef41197', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2172', 'db54a048ea74a88707e52aeae605ecefeb1197747a354be68a15fcbd1e65e2ae', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2173', '98960a03a0ffc6126c7e41714f8f9d64da876fff0da44b0e1a39c768e99fdb1c', 'Skin Infection/Cellulitis/abscess', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('2180', 'ff21d35f2d7e91da32e8fa4015019027a48d6d04466cf7791d439a08c80e704e', 'Foot cellulitis/infected ulcer', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('2183', '99a6c0ccb83dae5ead11b159e7527f1784d293674898219816be27fa0b56aba7', 'Other skin infection not specifically mentioned', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('2187', '2cb30ca8c8d4b5f8802e0654a5455b18b67d2641458a414c8ebead14e35b509e', 'Other skin infection not specifically mentioned', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('2200', '12f0896f133e5c8dfbc5f807d8b256480a573fa42345a1018a4ae8e22067cb47', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2201', 'dbe931fb768144af6ee5b556d5a85a7d3112427e8761c4e74922edcfcc48dcb5', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2202', 'aa5c44b3d600a09db338b97934be8ecc73ea2593380bd8b751c45dc515937e5d', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2203', 'ba0f69b2766fd10202d12e01ceef0137eaa8edb6a9c37d72013013379d1951a7', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2204', 'e8eee089dab623505f8293068e033f399b09e55921f0106a6e901157e5b2470a', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2205', '9171972e5fc56ad74002f1124e51f3e910c50eadefc89f553a5ffff01b635120', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2215', 'e092d642f8ae506279a3c4b4624bd9db69c0b121309fc21c5f2e769e3fec6e4e', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2216', '59b6262a414c554ca1b62a4ac2e8dfd2368216ee4e4061032e0e7f8440896e61', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2221', '8803ed667d41b067a3b38bc30392b0c4400b244ed8f57f49f98de844be9c1ef3', 'Nausea, undiagnosed', 'dx_nausea_d6bea94b06', 'Nausea'),
  ('2222', '078f7bd305cc57e5ba0bd51a85f762290b3c2e7a5daf1eee4c8532ea493bafd5', 'Allergic reaction, unspecified', 'dx_allergic_reaction_710675864a', 'Allergic reaction'),
  ('2223', '658ea864ffca7b5476ff57ef5b91421a889b734ddbf8b91c389a5cab38ac9fa1', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2224', '3a0e5cd74bf991a485fb419c43b3caf48635950b7d0cd5fdbb77a5e6dc3c6214', 'Primary insomnia', 'dx_insomnia_9dcefd14ed', 'Insomnia'),
  ('2226', '7664223d0743a741aa9a8ab6799d7ed5ac172c30ec0a3a5d17fedc5c2d83d3e4', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2227', 'fde9898e86c3c3b9473818c75d84009625475fdd605efd44bf381ff1c78fa2d0', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2228', '2ed7ad11a46b971a862b79c5f31eabb05cfda973464480e475f4c7af978b5b55', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2233', 'ca9ec5950f2b2a7a6ed3c7e6678de9cd6d6f771c5dc5af1c97d4e506de9efc3d', 'Sinusitis', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2241', '88c99bde8ab0b344349ddd95cced00fd13dff10c0069e55da61b4ed3944fa215', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2242', 'ada7883100ed8eb5f0f9d0f0cec7aefece8cd36bfa6ed1fd108299a6f56063a2', 'Gastritis', 'dx_gastritis_or_peptic_ulcer_disease_2685b6a7c1', 'Gastritis or peptic ulcer disease'),
  ('2244', '3dd23526d7f0766fb4f91ef324a188e61bce1689ab5e37826c946dfa3ee96509', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2245', '89483a6d6023815d9c7e24c977163dbcd4451e896c81b9fabe78d4eaaca531b0', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2246', '5a3795a7665bd99eb761b5ada765cc6ccf1d59e43f8c4a73eedc1674ee2b96b2', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2252', 'c6e616d2da356e1880aa3d4d8b26a121adb3def3de9d8cdd9d73e862c5410495', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2253', '6752a493ac76c560b928ebcfe324f52813067989155b601ef650d0c4393f4186', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2255', 'a3eb606166cc96e8e703d1040c77db020f5b048c730ff1d8d55253e132ed1f5a', 'Tinea corporis', 'dx_fungal_skin_infection_3158ef505c', 'Fungal skin infection'),
  ('2256', 'de50a707560aebbae9ada4d66aba8379a52fe662e860b85c2533e2dece35d7d2', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2257', 'c6b24ceb5fdda37b4d882907dd80486308e19b6aac9d5148290e10f39a0acf3d', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2270', '3ab258bc0d52a0d9fcb56a3f5ed18df851feb4dfb8315fe465115927c60b7589', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2285', 'ef63ae155b8cafeb82263a060fc0f9f454d26ae253d3bc97978d87b669de3965', 'Tinea pedis/athlete''s foot', 'dx_fungal_skin_infection_3158ef505c', 'Fungal skin infection'),
  ('2287', '87c8145b6f83eb18b47700a146907445267b650bd4abdd028d0604414782bf4b', 'Gastritis/peptic ulceration - non exercise/NSAID related', 'dx_gastritis_or_peptic_ulcer_disease_2685b6a7c1', 'Gastritis or peptic ulcer disease'),
  ('2290', '3b75d3dbeb3409b2986fbfbf4a3e33af99386e830ac0abc1e90cde57e185ea70', 'Viral gastroenteritis', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2292', '59523e5fc49440d0f21e34b305e2282ee8223e91185e8f5c4170ded66e162344', 'Viral gastroenteritis', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2295', '315346800afabe4e96f74057eed0ba84713cd9957ba556f5ca2ff0bd065e0c99', 'Viral gastroenteritis', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2305', '32ccb4eb6db749995704b8b8f0a396f846e2e8c968f1ccd4b90a8ab8946a3e3b', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2306', 'b294c1d960b26cc30b93c59c1ce0d1dd2b642c32fe97b73c16e15c9de2d48a11', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2313', 'f1df4dec28cdf40c67f4f1fdc5c6a2fb579b1d888d358616d2475bd046464926', 'Other gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2314', 'a47cff431a0d2790c3c44d9f25ba26ad0d0c07b70dbe68c644d4eb0f680d1767', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2315', '00eeef1104ccc6cd5390b00132a7f82c537cb6aecd3fa8634d906f5046054733', 'Other gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2316', 'e372b8abd766d567c8572baeec7c58e9313ab8a2d652e29619ccd53022b01e4b', 'Herpes simplex', 'dx_herpes_infection_a87b003a4b', 'Herpes infection'),
  ('2317', 'cb690c9bd8fafb31ca43d2592138816b3d3bc929584a96e055181ffed536fe28', 'Other gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2318', 'cf8d3499bcaf1e30af2b17c3e7da13bb7630cd4cc4ff6b03ca9442b56094d3bf', 'Other gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2319', 'b1f94572632f0a3889dfb7adc09d5721cc73a5b57a5d92c8fb6e22b24891f835', 'Tinea versicolor', 'dx_fungal_skin_infection_3158ef505c', 'Fungal skin infection'),
  ('2333', '8494eff1fbb5e65778d0715053fb8d216749cd6ec6498f124df4ed76679451e7', 'Viral or bacterial conjunctivitis', 'dx_conjunctivitis_26dfbd55b4', 'Conjunctivitis'),
  ('2334', '0cfb3a9272a2446bdc508da007240fb55d8bce98009184f488ea38ffad7c9b19', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2351', 'd9ec0383e60f8b1fa82c99f9ff3c36fc239cb60c94e9c4eb064818514283538b', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2353', 'ee6cf62aabc1cea22c5fc37bb3e5351827a5eed7b2b11975f1444181fa8981ae', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2355', '49d6f07babf69e94f03a3cde3f4eb4356a081a61744ce1f4ad5f21f17d66bf75', 'Herpes gladiatorum', 'dx_herpes_infection_a87b003a4b', 'Herpes infection'),
  ('2356', '90e078ce5551996a7a5750e6914991d6c0d45cb9aa95a6af437606cd988274ac', 'Foot cellulitis/infected ulcer', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('2359', 'b0a8980b741e0c8656b588c4bc80f5e9d8cf60329fcb7bfa70af1d91557fef4e', 'Herpes simplex', 'dx_herpes_infection_a87b003a4b', 'Herpes infection'),
  ('2372', '364189ae574e8041c074935f391bea4a2ec4ed6383370d369fe1966178091d5c', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2373', '9565bd078bb4c4760af2e526c5de57cccd39b0fba9e30bb9f2b525e91f5d0354', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2374', '6fa278b195bc9a4accba344d0c7697d21dc81807bea6d7658776fb639efd358f', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2377', 'c879383b3ed2e3796fca470d0dfda095db43683fa1084f1057b4000386481b6a', 'Herpes simplex', 'dx_herpes_infection_a87b003a4b', 'Herpes infection'),
  ('2378', 'ea5c9547194edcd2f3d6199306ce158a418c77d41f88fb7735e1674e127dc367', 'Staphylococcal infection of the wrist/hand, excluding the joint', 'dx_wrist_or_hand_skin_infection_c6d12c80e7', 'Wrist or hand skin infection'),
  ('2379', '2096d09e0e701a91224b3e735164ecfdf804ae6a67187354e2bb7ff4db2f28f2', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2381', 'faa0743bad0b1a757b99073443c384ce6497a70b92ee79a53f7009e4dc4eb3ce', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2389', '6733c1608c6c2447aa9e334869397a2d34455b001bd7a0b15a6b8e5287db5963', 'Tinea pedis/athlete''s foot', 'dx_fungal_skin_infection_3158ef505c', 'Fungal skin infection'),
  ('2390', 'fc0e14b0069d03a9738c1aeed6aabeadf92243975832035a7917b8432cfa2cd3', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2393', '61a7b7357432d0c43d9cf10873834d314ee1822682019e86caa35956846e0154', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2398', '3cfed0807994f5219daa4536fbdde5cd50581c4a9a3f91b3fd230f0d591f2c6f', 'Other gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2401', 'c3a0f7854284f8479eb4a45cca73c42783aa09a0b220b86bbbf0d071b94d8fdf', 'Infected wrist, hand, finger, thumb joint', 'dx_hand_or_wrist_joint_infection_59d60a70fc', 'Hand or wrist joint infection'),
  ('2404', '7160df62f21f047dd02dd3ba8a8f201147406a853687ab204522eaee68b78124', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2405', '1c5303b8d35847d81abaf836c0dae5d6b62c747de11b7bb7aba0d61b1ac0fd4b', 'Herpes simplex', 'dx_herpes_infection_a87b003a4b', 'Herpes infection'),
  ('2406', '0e32885c9e61c0cbab324ee4bdeba2fcd0e6f0259ab162dfe789ebff0630987b', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2417', 'bc4dd66ba7daeb0dd8de6b6e1dab17cc62b270109e75d980f26090bfb8873d72', 'Dizziness, undiagnosed', 'dx_dizziness_6db71bef23', 'Dizziness'),
  ('2418', '9321254554a98d3146926b2e9fc6ea5bc53eb49f08ab5e0cf0f281f0a79cfb24', 'Nose /throat illness /condition', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2423', '511cc83c7d8a56bf2b7a0bb0dcf35599c8ccc19561c4eed66fe6ab82e0a9e13d', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2433', 'a91f8d087da341134848e7ccd2a78f6c12a92654f41788d694f75f0046158c29', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2434', 'd1975fa5a156787a8d395f7450a2a9bf5390c6cb2b3da5b217d71e7b90369d6f', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2435', 'fd1991d223e4cc40f8603d77c160dd2e1c3de5251dc83b8393859e0dfab43b69', 'Nose /throat illness /condition', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2436', '016ef1591ebcb7802607fd75d720db61e33fed75c5db9ab8bfa7601ec2c7ff08', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2450', '87e718e8bb572e556703e79565eb528fc574263fb8052df95bf596b78dd6a282', 'Skin Infection/Cellulitis/abscess', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('2451', '2fa8d0df5163574d6bc778bfe73d07dadda3b96005d0ab44e74e803562441415', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2452', 'cc92ce295feb64a4e6435de18e234f8d258029f15a78db3eaa815deeacd0fbf7', 'Rash /other dermatological condition', 'dx_dermatological_condition_cf62967c16', 'Dermatological condition'),
  ('2453', 'e44839e357f0734cf51079c9c5fb4fb5aaf4f95e057f335c9b61304670e1334d', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2457', '36a466e44975c3660e679cfd924aabce469647448a19dce9345b062ad129c757', 'Benign skin lesion', 'dx_benign_skin_lesion_b6ced4831e', 'Benign skin lesion'),
  ('2460', '740dd8dc906107574fbb71d64f8cee0f80b5f4d2b017dc10a54e3e23ebc8d6f6', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2461', '4e58f60faefd82862a64f9dab984208338bfaae20b0ca86a4e997c714f599e08', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2462', 'b6ee1946d7b44ea8fd1549febdab111db4bb5cce6654f050171cda874b864ed4', 'Headache not otherwise specified', 'dx_headache_45575633c6', 'Headache'),
  ('2463', 'e7e00ef5293cde33e77449cfc129d6036865f23a99598b8f5f3ebdd6bcf4e2f5', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2473', 'c71a9cc2799ec96fd1c93d70fe12720ce17d61331fc6600641cc543e6380d81f', 'Nose /throat illness /condition', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2474', 'ef1f37103b2aeb4bf265de85967c57e90223784e2425ec208b44f0041d5a8942', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2475', 'f3ca01ad19f34fdfcbc145a5e51e9d5dc2df8ea8493967fdc3505520c06dd60b', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2476', '5738165753aa6fef580c405c0af70df844356ed205aec1af31f08ec683ffda2b', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2478', '968ff7f9742b5fe5f195da46339f1d6489de2b2fca0bb5f8f13d472320cd6f3e', 'Herpes gladiatorum', 'dx_herpes_infection_a87b003a4b', 'Herpes infection'),
  ('2479', 'd9fab4bf8d9d4dc5f1528717bea7262d158692f8d10d52db1abc3d33a0c1f45a', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2480', 'be09be46deb806f851ea92aac984b9040f73db33cf79a155c42368c063114819', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2481', '8a5cf3bd2b285cb0285d48ccf614a063498fe485cf7fa1bea153f2c6356d6585', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2492', '7c9d7058563bd4a86cfa8c872cd4ab55db0dec9ab9263463bf9e7d0423b03bb4', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2494', 'd0b84ae6ae631ca8c9a6c7fa38a93a731b63ddcc85747a264f680fe54dd4a1d7', 'Allergic reaction, unspecified', 'dx_allergic_reaction_710675864a', 'Allergic reaction'),
  ('2495', '72b48bbd03c52c7b4fc72ca7930a6cc69fa4c74606623c49655c124bf54eea07', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2496', 'bc10d6d4a39256770e3092212a4b93bcf5fa76a8b786ffcca2263b7ce295e997', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2502', 'f288744a55b937811558d3681947d188b72cea73ee5c9fb1d67a3ca579af0e01', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2505', 'fda210e99a47ca05f4536e703aa6b4d97048cfc44ca2ae34f9982049c4f8d53b', 'Skin Infection - fungal', 'dx_fungal_skin_infection_3158ef505c', 'Fungal skin infection'),
  ('2506', '7d1b1bb23854d8c083507216f0e7ea0caefec6133692be7bc9e604fdf377bccb', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2507', '090fac422fce375436401155e44ce8a4475228d7adf34566cd505e1c7c037458', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2508', '4dc7f8c52683caa026d6b4b36fb5c13dd013582d668e0f22899f236d9d3569c7', 'Tinea versicolor', 'dx_fungal_skin_infection_3158ef505c', 'Fungal skin infection'),
  ('2509', '6cf411c94880a4d1d35cfa3db38d331a4f7f6315cc9f3f98d35518ee314eed6f', 'Other skin infection not specifically mentioned', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('2516', 'b7a023b99ec622e51577290d3dc5ea07f90c8b2e50ca1e5a5be98830cc5ceb1b', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2517', '62152a5eedc1eb727e42687330541ce49eea35e23d0ca0edc2e15561b70c0523', 'Tinea pedis/athlete''s foot', 'dx_fungal_skin_infection_3158ef505c', 'Fungal skin infection'),
  ('2518', 'a1052376f6bce4c6a88b645b0b7f5f40a06b1394caa1f0526c465140b321a0fc', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2522', '3c2772386f50cdd286547425dd30568342f15cc5f22badaae38940991769c931', 'Other skin infection not specifically mentioned', 'dx_skin_infection_0815acb73e', 'Skin infection'),
  ('2526', '9ef79989400d51c2bb77a43ef87a8b0ff1c7133c6b2b4ad9eb8c50166460ef74', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2527', 'ca497ac3445e436197a471c7ceff5c7fb8204ae3552d52870d5fe3f0ac9bfe8a', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2530', 'fa55f5ef997a7c4a8051d0d322a4b51aab50e03fc495fd7cc893fe084b8f7994', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2531', 'fe5bc6fc7dc68ab166721893eb1d1373f845cd5060e8a4423e4920e21317303f', 'Clinical fatigue, undiagnosed', 'dx_clinical_fatigue_424a3570e2', 'Clinical fatigue'),
  ('2532', 'a8a4a072357128d9c4eef75e6ddddc6b3b01dc0640e1a5ad9c9ea4126e1ae1d0', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2533', '049574136a1c8bfbeedf6872c19ac6a058ee5f9aa4d9b1a2d9e525aa1df865a1', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2534', '02b2ed976c5b4a2ab996b6d345dff0a4e478fd52d301394bb704adb98a62eb1d', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2540', 'b285baa1c3de9a60a3b46dd9020cd13abda82c13c6a0f2ac1577e45f3f97b292', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2543', '88991c43b8ff905551ff3c910f356f660252ded89c3340676698cdfa5b8210c4', 'Ear infection', 'dx_ear_infection_da58e903bf', 'Ear infection'),
  ('2544', '2e444c26d7d7c0dc8fddd473e4313291d8e07f933d88a81c5a709ba0a43ee826', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2547', '2f9affee2b13ce90abcac023159870f3b25f32dafcb88da57eaa9917c6f841a8', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2548', 'b801b0d26454f25c7dc6e86a6a548b330327857e0f995bbfd51002eadb89260b', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2549', '353eb6197395bb36a2fe19a479d7d91492a3b594291affe50bcacf4aa47d6862', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2572', '850a5d44ada8f082fcfc1ef0628ef59288670e5518a2e39261e05d06d46e5bec', 'Viral gastroenteritis', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2573', '2df7971b282e02bd9682538a2a87db875b54ea6d8948bbc4806356d3c7968ea4', 'Viral gastroenteritis', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2587', '37d4dfc1c67d6e589e0bbe456aad65181691868bcfe3815069d94e80588b10d6', 'Influenza A or B', 'dx_influenza_27addce986', 'Influenza'),
  ('2600', 'bf3146eaaa7ff73e73a3f40f7edac724e917c3eda754c1f33cbfc6106d32cf40', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2610', 'd40438327d9de146e839db6f58ca9051cac79ee87161981073a521a90f3a5cd8', 'Ear +/- sinuses/throat infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2621', '05a5063fab27c1690518e2bd0f770c1d24b45ef63095601c321281448a338749', 'Viral gastroenteritis', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2635', '3d5cacb2b4f58f1e68d7910739ebf4df36f67ac3af336ddf09e59ec22ee21a8d', 'Ear +/- sinuses/throat infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2650', '3a2a1c0e9f8f15e8f64dfba9dd2aa0a4ab119d8163447edd29d2cdee9c6bedb2', 'Bronchitis', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('2651', 'f1448f484c7922ffef549cdb18340a8cd3bc0adffebfef8e44b2a5d259ef4802', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2658', 'b09616a72e3dadfd2cc09f0f8dd5ba07ebc8dad12ebf97b3dcd414e70b3408ad', 'Viral or bacterial conjunctivitis', 'dx_conjunctivitis_26dfbd55b4', 'Conjunctivitis'),
  ('2659', '2a2506b297393734d646f2bd84fe9c784b881654a3c099a8e01bd675e413e250', 'Eye infection', 'dx_eye_infection_be5c00f469', 'Eye infection'),
  ('2660', '52c1cd12b1a66f87ac2ace27965384d0c432ed451ffd426354db039c0d80adc2', 'Other ear disorder, not otherwise specified', 'dx_ear_disorder_unspecified_ea02189bd2', 'Ear disorder, unspecified'),
  ('2671', '3786e3a8e24f30cc55d9fec1f2a0aec997ebeace5857790eadcceae5c0a9900b', 'Ear +/- sinuses/throat infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2687', '90e738be748abce52bbce8ecc60a566194450d8aaea0c41072ef886f0d201030', 'Tinea corporis', 'dx_fungal_skin_infection_3158ef505c', 'Fungal skin infection'),
  ('2696', 'fec0b761447fd1f4984a3550ab5bb88635e3fe89ddb5f6c996e5ac393493a2cd', 'Viral gastroenteritis', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2697', 'aeb85236b2da3049d8bdd77015652e3d775c8338e002df330d5cf19f7f42cb84', 'Viral gastroenteritis', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('2699', 'ca3b9c12b56091b7ec52c9f17129f9f3fe1b4bc3b0df7decc71b8c77720a5e21', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2700', '0b92290b606acb0806939bec4408c637e9e612b0a02a84a7ecbc7be4c0839293', 'Ear +/- sinuses/throat infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2701', '9428e3b818a1c9f98d69f004ec96747ea0cae3d266e117d8f5e7e4ee7741bcd0', 'Ear +/- sinuses/throat infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2702', 'f7ab4e24a7d3ccb70d9ed2c7f66a02ecbbf39ffbce3a836de216fbf9f50f4523', 'Ear +/- sinuses/throat infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2703', '1c0d06ed44cce7e15e0d84f7f5e696aee3406ff8e5b67edd44f376e5ddfc053b', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2706', '44a5902b21d9ee25d8460886757dcf29238a92e046062cbb1c93e2c5d21b8413', 'Ear +/- sinuses/throat infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2711', '2168b39f2e4123b1aec04a749234fbfa2c1a0d41995716cce9372b8dae0575fe', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2712', '252c3bea705b4ff437e0d5bb1abbfb984f9eb43f0b4cfd48a28f843907a23770', 'Abscess of the head, face or neck', 'dx_head_face_or_neck_abscess_7fe7c8cf27', 'Head, face or neck abscess'),
  ('2713', 'ee5583d0fa1e3415735e303ff4bbc5a1f4d8eb4281f8aaa6dcdef4204dea8340', 'Other cardiovascular disease', 'dx_other_cardiovascular_disease_ddc1f5b58b', 'Other cardiovascular disease'),
  ('2720', 'b03a73f5ce7885e452db2431ab3c539dc4896541afbd86180079c650775ef4dd', 'Ear +/- sinuses/throat infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2726', 'e92ae00e02cac5b9c87cf68e666f0ea7de149275765f67650d8e5cd3922b103b', 'Ear +/- sinuses/throat infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2729', '2d46081ad6b82745564db2ad322860fec4d9d1f0e7da0650bb74d398a8862abf', 'Ear +/- sinuses/throat infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2958', '37fbc963eba500def12aceb8907ad49eba8e8f8dcdfac46ecdc27bd4778472f1', 'Other respiratory illness not otherwise specified', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('2960', '4adf178c7e9485293143449d82fb3644a504d0e8f5d5278dafe07da3465866aa', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2961', '6cd99e9aba0421e6eb35b59dba3fe062e8bedb5587d514cda2e1916fd2c0d612', 'Respiratory Disease', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('2968', 'e891799a2a59340aa33bd97b890c9be21cbd9ca95974cef652b41b209709e785', 'Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2969', 'a7831193af630d63e2e89da7e8d0515ba5f4bc9c779b5b5538fe2570051c3657', 'Other medical illness', 'dx_medical_illness_33b4f89cb8', 'Medical illness'),
  ('2975', '920e0d7857f6f88ae6ace25afe4df831d664d27800928bc9c66ef384e4f58ad9', 'Other medical illness', 'dx_medical_illness_33b4f89cb8', 'Medical illness'),
  ('2976', '44af637fd4fda08769563c4ff6dc935b8de117f4064feb1f166dcc2980c160c6', 'Nose /throat illness /condition', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('2979', '7f1f1b9528e03057832500902f97cb8f799b5f0aadf01b97757fa1500b97378e', 'Other medical illness', 'dx_medical_illness_33b4f89cb8', 'Medical illness'),
  ('2988', '9f0eb336f731fde2bd2f4c9e41b44b7fe34564021a5449886d78564eb4621dc9', 'Other medical illness', 'dx_medical_illness_33b4f89cb8', 'Medical illness'),
  ('2990', 'e6b9ab2c7c4fb64bbdd1de963f799fe7d9ae64c86e8d5ef0580f63df0251d1f2', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2991', '3c87014ac44c7b2dc5bd9587b2c2707d7b254bd93152fdecaf74d8b2afabb994', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2996', '855fa56ce7e550dd7c3580c3aaff648d81bbb89633eed1041092b7dcae218e06', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('2999', '3ec97925a6b8042f65b6b1128b86a7c5c9bb793dd92f0971aa2e3385202b8e98', 'Respiratory Disease', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('3005', '524299c1c8e2171c376787dd9ba68fec0d9a072687ba01a29c0df9f992319160', 'Pharyngitis', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection'),
  ('3006', 'fa20e6b02dc87e73f6667f820725cf78ccba3eee00af7787e8993d595db71e59', 'Other respiratory illness not otherwise specified', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('3013', 'af416765efa44db18192356978fb9f26f13e2bb25f0a8002682e120e56f1d078', 'Wisdom tooth', 'dx_dental_condition_e9d2167e5f', 'Dental condition'),
  ('3024', '4e6ae8ac3764fa1a0d83dc3daaad7745a0313cd25d9019a8ffba3938e3ad459a', 'Other respiratory illness not otherwise specified', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('3027', '99de8bd92fce2f3f57a356da000d0ead7bca8bb18486e4ddec260a0c46893581', 'Other respiratory illness not otherwise specified', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('3028', '7f43a7fe7c67cb37ce71e2314cfb535bd311c8db2430189096f14e6e97be10ba', 'Other respiratory illness not otherwise specified', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('3029', '5973da57aeb67cd92e414aed1c83e0a879fe83070d343ab3b2602d93b7dc9b3c', 'Other respiratory illness not otherwise specified', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('3030', 'efc9c384b04165ec3055cb1f4c460e9d0ec2875737b80b336144411f521698e7', 'Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified'),
  ('3032', '217f71178b454349b7f057d2c26cca9576de7a5560baab96041934d2240137fa', 'Other respiratory illness not otherwise specified', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness'),
  ('3033', '58de9e8dd13f12e066a229b39cc1f899a5c27678cf4cbe2f88e177d45782f5ce', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('3034', '313b8b11efab20e422446eafad6df63e66fb1040d0aa4beac5bca9c59eb1b679', 'Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection'),
  ('3052', 'daf0af9417f8acce951720888f376a04c191ffa957e75a2a31e56f9f5078cea2', 'Wisdom tooth', 'dx_dental_condition_e9d2167e5f', 'Dental condition'),
  ('3056', '9629e0813d36b3f277b2110654be8fd3f358ca04843d46faa237eb8528e99ecd', 'Wisdom tooth', 'dx_dental_condition_e9d2167e5f', 'Dental condition');

create table audit.urc_2025_26_diagnosis_family_exact_labels_v1 (
  adjudication_version text not null references
    audit.urc_diagnosis_family_adjudication_evidence_v1(adjudication_version)
    default 'urc_diagnosis_family_adjudication_v1',
  source_label text not null,
  subtype_code text not null,
  family_code text,
  family_label text,
  problem_type_scope text not null,
  review_status text not null,
  row_filter_required boolean not null,
  primary key (adjudication_version, source_label),
  check ((family_code is null) = (family_label is null))
);

insert into audit.urc_2025_26_diagnosis_family_exact_labels_v1 (
  source_label, subtype_code, family_code, family_label,
  problem_type_scope, review_status, row_filter_required
)
values
  ('A/C Joint contusion', 'a_c_joint_contusion', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('A/C Joint instability/recurrent sprains', 'a_c_joint_instability_recurrent_sprains', 'dx_acromioclavicular_joint_chronic_instability_299408db68', 'Acromioclavicular joint chronic instability', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('A/C joint stress/overuse injury', 'a_c_joint_stress_overuse_injury', 'dx_a_c_joint_stress_overuse_injury_2b361001ea', 'A/C joint stress/overuse injury', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Abdominal oblique muscle strain', 'abdominal_oblique_muscle_strain', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Abdominal Soft Tissue Dysfunction', 'abdominal_soft_tissue_dysfunction', 'dx_abdominal_soft_tissue_dysfunction_5b3072bafe', 'Abdominal Soft Tissue Dysfunction', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Abdominal tendon insertion strain', 'abdominal_tendon_insertion_strain', 'dx_abdominal_tendon_insertion_strain_9b7dda21e3', 'Abdominal tendon insertion strain', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Abdominopelvic Soft Tissue Bruising/Haematoma', 'abdominopelvic_soft_tissue_bruising_haematoma', 'dx_abdominopelvic_soft_tissue_contusion_6fc95fc1db', 'Abdominopelvic soft tissue contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Achilles enthesopathy', 'achilles_enthesopathy', 'dx_achilles_enthesopathy_a32a2cbe67', 'Achilles enthesopathy', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Achilles enthesopathy with retrocalcaneal bursitis', 'achilles_enthesopathy_with_retrocalcaneal_bursitis', 'dx_achilles_enthesopathy_with_retrocalcaneal_bursitis_2901a57f2e', 'Achilles enthesopathy with retrocalcaneal bursitis', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Achilles tendinopathy', 'achilles_tendinopathy', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Achilles tendon rupture', 'achilles_tendon_rupture', 'dx_achilles_tendon_rupture_6b59cc3783', 'Achilles tendon rupture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('ACL or PCL sprain of the knee', 'acl_or_pcl_sprain_of_the_knee', 'dx_acl_or_pcl_sprain_of_the_knee_251aa299df', 'ACL or PCL sprain of the knee', 'injury_or_unresolved', 'identity_group', 'false'),
  ('ACL rupture', 'acl_rupture', 'dx_acl_injury_4b8eb47e96', 'ACL injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('ACL strain/rupture with chondral/meniscal injury', 'acl_strain_rupture_with_chondral_meniscal_injury', 'dx_acl_injury_4b8eb47e96', 'ACL injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Acromioclavicular (A/C) joint sprain', 'acromioclavicular_a_c_joint_sprain', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Acute Concussion', 'acute_concussion', 'dx_concussion_a91e1107d7', 'Concussion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Acute Concussion with visual symptoms', 'acute_concussion_with_visual_symptoms', 'dx_concussion_a91e1107d7', 'Concussion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Acute shoulder subluxation', 'acute_shoulder_subluxation', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Adductor longus strain', 'adductor_longus_strain', 'dx_adductor_muscle_injury_97164c9b14', 'Adductor muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Adductor longus tendon injury', 'adductor_longus_tendon_injury', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Adductor longus tendon strain', 'adductor_longus_tendon_strain', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Adductor muscle cramping during exercise', 'adductor_muscle_cramping_during_exercise', 'dx_adductor_muscle_cramping_during_exercise_060f6639d9', 'Adductor muscle cramping during exercise', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Adductor muscle haematoma', 'adductor_muscle_haematoma', 'dx_adductor_muscle_injury_97164c9b14', 'Adductor muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Adductor origin tendinopathy', 'adductor_origin_tendinopathy', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Adductor Soft Tissue Dysfunction', 'adductor_soft_tissue_dysfunction', 'dx_adductor_soft_tissue_dysfunction_902285b985', 'Adductor Soft Tissue Dysfunction', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Ankle - Bone contusion', 'ankle_bone_contusion', 'dx_ankle_bone_contusion_368d1dec1c', 'Ankle - Bone contusion', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Ankle anterior impingement', 'ankle_anterior_impingement', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Ankle contusion/haematoma', 'ankle_contusion_haematoma', 'dx_ankle_contusion_beb9f51162', 'Ankle contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Ankle fracture with diastasis of syndesmosis', 'ankle_fracture_with_diastasis_of_syndesmosis', 'dx_ankle_fracture_97af59eea6', 'Ankle fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Ankle joint synovitis', 'ankle_joint_synovitis', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Ankle multiple ligaments sprain', 'ankle_multiple_ligaments_sprain', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Ankle Pain/Injury undiagnosed', 'ankle_pain_injury_undiagnosed', 'dx_ankle_pain_de6b615afc', 'Ankle pain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Ankle sprains', 'ankle_sprains', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Ankle synovitis/Impingement/Bursitis', 'ankle_synovitis_impingement_bursitis', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Ankle tendon injury', 'ankle_tendon_injury', 'dx_ankle_tendon_injury_af7fde2c3e', 'Ankle tendon injury', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Anterior cruciate ligament (ACL) injury', 'anterior_cruciate_ligament_acl_injury', 'dx_acl_injury_4b8eb47e96', 'ACL injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Anterior instability of shoulder', 'anterior_instability_of_shoulder', 'dx_shoulder_instability_2b9f54f442', 'Shoulder instability', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Anterior shoulder instability', 'anterior_shoulder_instability', 'dx_shoulder_instability_2b9f54f442', 'Shoulder instability', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Anterior sternoclavicular (S/C) joint sprain', 'anterior_sternoclavicular_s_c_joint_sprain', 'dx_sternoclavicular_joint_sprain_6316623d10', 'Sternoclavicular joint sprain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Anterior talofibular and calcaneofibular ligament sprain', 'anterior_talofibular_and_calcaneofibular_ligament_sprain', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Anterior talofibular ligament sprain', 'anterior_talofibular_ligament_sprain', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Anteroinferior instability of shoulder', 'anteroinferior_instability_of_shoulder', 'dx_shoulder_instability_2b9f54f442', 'Shoulder instability', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Anteroinferior shoulder dislocation', 'anteroinferior_shoulder_dislocation', 'dx_shoulder_dislocation_2067688fdd', 'Shoulder dislocation', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Asthma/allergy/hay fever/respiratory', 'asthma_allergy_hay_fever_respiratory', null, null, 'illness', 'out_of_scope', 'false'),
  ('Avulsion fracture elbow multiple locations or location unspecified', 'avulsion_fracture_elbow_multiple_locations_or_location_unspecified', 'dx_avulsion_fracture_elbow_multiple_locations_or_location_unspecified_098c8e40ed', 'Avulsion fracture elbow multiple locations or location unspecified', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Avulsion fracture phalanx', 'avulsion_fracture_phalanx', 'dx_avulsion_fracture_phalanx_11aab985f5', 'Avulsion fracture phalanx', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Back referred hamstring tightness', 'back_referred_hamstring_tightness', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Back referred muscle tightness', 'back_referred_muscle_tightness', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Bennett''s fracture/dislocation thumb', 'bennett_s_fracture_dislocation_thumb', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Biceps femoris strain grade 1 - 2', 'biceps_femoris_strain_grade_1_2', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Biceps haematoma', 'biceps_haematoma', 'dx_biceps_muscle_injury_3a5679b9a5', 'Biceps muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Biceps muscle strain', 'biceps_muscle_strain', 'dx_biceps_muscle_injury_3a5679b9a5', 'Biceps muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Brachial plexus traction injury/burner/stinger', 'brachial_plexus_traction_injury_burner_stinger', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Bruised ribs/chest wall', 'bruised_ribs_chest_wall', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Bruising buttock/ pelvis not otherwise specified', 'bruising_buttock_pelvis_not_otherwise_specified', 'dx_buttock_contusion_46ae636fd7', 'Buttock contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Bruising/haematoma iliac crest/gluteus medius', 'bruising_haematoma_iliac_crest_gluteus_medius', 'dx_buttock_contusion_46ae636fd7', 'Buttock contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Buttock bruising or haematoma', 'buttock_bruising_or_haematoma', 'dx_buttock_contusion_46ae636fd7', 'Buttock contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Buttock Muscle Strain/Spasm/Trigger Points', 'buttock_muscle_strain_spasm_trigger_points', 'dx_buttock_muscle_strain_spasm_trigger_points_bed2057d40', 'Buttock Muscle Strain/Spasm/Trigger Points', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Buttock Pain not otherwise specified', 'buttock_pain_not_otherwise_specified', 'dx_buttock_pain_not_otherwise_specified_ac42868f08', 'Buttock Pain not otherwise specified', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Buttock Soft Tissue Bruising/Haematoma', 'buttock_soft_tissue_bruising_haematoma', 'dx_buttock_contusion_46ae636fd7', 'Buttock contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Calcaneofibular ligament sprain', 'calcaneofibular_ligament_sprain', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Calf contusion/haematoma', 'calf_contusion_haematoma', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Calf cramping during exercise', 'calf_cramping_during_exercise', 'dx_calf_cramp_spasm_950b710fbb', 'Calf cramp/spasm', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Calf laceration/abrasion', 'calf_laceration_abrasion', 'dx_lower_leg_laceration_5e3fbc19d5', 'Lower leg laceration', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Calf muscle cramps/spasm', 'calf_muscle_cramps_spasm', 'dx_calf_cramp_spasm_950b710fbb', 'Calf cramp/spasm', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Carpometacarpal (CMC) joint O/A', 'carpometacarpal_cmc_joint_o_a', 'dx_carpometacarpal_cmc_joint_o_a_84ae71954a', 'Carpometacarpal (CMC) joint O/A', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Cervical disc degeneration', 'cervical_disc_degeneration', 'dx_cervical_disc_degeneration_0eaff195fc', 'Cervical disc degeneration', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Cervical disc Injury', 'cervical_disc_injury', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Cervical Disc Prolapse', 'cervical_disc_prolapse', 'dx_cervical_disc_prolapse_605eec93af', 'Cervical Disc Prolapse', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Cervical Disc sprain', 'cervical_disc_sprain', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Cervical functional pain', 'cervical_functional_pain', 'dx_cervical_functional_pain_e11c275770', 'Cervical functional pain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Cervical nerve root compression/stretch', 'cervical_nerve_root_compression_stretch', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Cervical rib', 'cervical_rib', 'dx_cervical_rib_4be6f8f7a7', 'Cervical rib', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Cervical Spine Instability', 'cervical_spine_instability', 'dx_cervical_spine_instability_658367d444', 'Cervical spine instability', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Cheek laceration not requiring suturing', 'cheek_laceration_not_requiring_suturing', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Chest muscle strain', 'chest_muscle_strain', 'dx_chest_muscle_injury_8a57562fd8', 'Chest muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Chest Wall Soft Tissue Bruising/Haematoma', 'chest_wall_soft_tissue_bruising_haematoma', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Chin laceration', 'chin_laceration', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Chronic lateral instability', 'chronic_lateral_instability', 'dx_chronic_lateral_instability_70afaf7c03', 'Chronic lateral instability', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Chronic lumbar functional pain', 'chronic_lumbar_functional_pain', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Chronic PCL insufficiency', 'chronic_pcl_insufficiency', 'dx_pcl_injury_4986df0532', 'PCL injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Chronic Shoulder instability', 'chronic_shoulder_instability', 'dx_shoulder_instability_2b9f54f442', 'Shoulder instability', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Compartment Syndrome of Thigh', 'compartment_syndrome_of_thigh', 'dx_compartment_syndrome_of_thigh_f17e27a47f', 'Compartment Syndrome of Thigh', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Complication of finger MCP joint sprain', 'complication_of_finger_mcp_joint_sprain', 'dx_complication_of_finger_mcp_joint_sprain_5a4dac318a', 'Complication of finger MCP joint sprain', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Complication of foot laceration incl infection', 'complication_of_foot_laceration_incl_infection', 'dx_complication_of_foot_laceration_incl_infection_165b97dfbf', 'Complication of foot laceration incl infection', 'mixed', 'identity_group', 'true'),
  ('Complication of laceration incl. infection', 'complication_of_laceration_incl_infection', 'dx_complication_of_laceration_incl_infection_594ae25665', 'Complication of laceration incl. infection', 'mixed', 'identity_group', 'true'),
  ('Concussion', 'concussion', 'dx_concussion_a91e1107d7', 'Concussion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Concussion in a player with a concerning history', 'concussion_in_a_player_with_a_concerning_history', 'dx_concussion_a91e1107d7', 'Concussion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Concussion with Criteria 1 video signs', 'concussion_with_criteria_1_video_signs', 'dx_concussion_a91e1107d7', 'Concussion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Concussion with imaging abnormality', 'concussion_with_imaging_abnormality', 'dx_concussion_a91e1107d7', 'Concussion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Concussion with no concerning history or signs', 'concussion_with_no_concerning_history_or_signs', 'dx_concussion_a91e1107d7', 'Concussion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Concussion/Brain Injury', 'concussion_brain_injury', 'dx_concussion_a91e1107d7', 'Concussion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Contusion/haematoma of thigh', 'contusion_haematoma_of_thigh', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('contusion/haematoma, hip region', 'contusion_haematoma_hip_region', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Corneal Abrasion', 'corneal_abrasion', 'dx_eye_trauma_0bcdc22eb2', 'Eye trauma', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Costal cartilage/costochondral joint injury', 'costal_cartilage_costochondral_joint_injury', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Costochondral joint dislocation', 'costochondral_joint_dislocation', 'dx_costochondral_joint_dislocation_e432cb66a1', 'Costochondral joint dislocation', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Costochondral joint instability', 'costochondral_joint_instability', 'dx_costochondral_joint_instability_5683c80b63', 'Costochondral joint instability', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Costochondral joint sprain', 'costochondral_joint_sprain', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Costovertebral joint sprains', 'costovertebral_joint_sprains', 'dx_costovertebral_joint_sprain_f6582e1466', 'Costovertebral joint sprain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Delayed onset muscle soreness', 'delayed_onset_muscle_soreness', 'dx_delayed_onset_muscle_soreness_a2914190a6', 'Delayed onset muscle soreness', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Deltoid haematoma', 'deltoid_haematoma', 'dx_deltoid_contusion_2c7874c7dc', 'Deltoid contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Diarrhoea', 'diarrhoea', null, null, 'illness', 'out_of_scope', 'false'),
  ('DIP joint dislocation little finger', 'dip_joint_dislocation_little_finger', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('DIP joint dislocation middle finger', 'dip_joint_dislocation_middle_finger', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('DIP joint dislocation ring finger', 'dip_joint_dislocation_ring_finger', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Disc prolapse/disruption', 'disc_prolapse_disruption', 'dx_spinal_disc_injury_e3b980b6b8', 'Spinal disc injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Discoid lateral meniscus', 'discoid_lateral_meniscus', 'dx_discoid_lateral_meniscus_bffa540332', 'Discoid lateral meniscus', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Dislocated metacarpophalangeal or interphalangeal joint', 'dislocated_metacarpophalangeal_or_interphalangeal_joint', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Dislocated shoulder', 'dislocated_shoulder', 'dx_shoulder_dislocation_2067688fdd', 'Shoulder dislocation', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Dislocation of interphalangeal (IP) joint thumb', 'dislocation_of_interphalangeal_ip_joint_thumb', 'dx_thumb_ip_dislocation_a325ccd91d', 'Thumb IP dislocation', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Dislocation of MCP joint thumb', 'dislocation_of_mcp_joint_thumb', 'dx_dislocation_of_mcp_joint_thumb_ca42ee2d60', 'Dislocation of MCP joint thumb', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Dislocation of midfoot through tarsometatarsal (TMT) joints/Lisfranc dislocation', 'dislocation_of_midfoot_through_tarsometatarsal_tmt_joints_lisfranc_dislocation', 'dx_lisfranc_injury_a82b5577c5', 'Lisfranc injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Distal adductor strain', 'distal_adductor_strain', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Distal biceps tendinopathy', 'distal_biceps_tendinopathy', 'dx_distal_biceps_tendinopathy_49d3aa6b31', 'Distal biceps tendinopathy', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Distal biceps tendon rupture', 'distal_biceps_tendon_rupture', 'dx_biceps_tendon_injury_cbd11d2125', 'Biceps tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Distal interphalangeal (DIP) joint dislocation index finger', 'distal_interphalangeal_dip_joint_dislocation_index_finger', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Distal quadricep haematoma', 'distal_quadricep_haematoma', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Distal radioulnar joint injury', 'distal_radioulnar_joint_injury', 'dx_wrist_injury_d94414e2c6', 'Wrist injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Dorsal hand laceration', 'dorsal_hand_laceration', 'dx_hand_wrist_laceration_or_abrasion_35c31d7555', 'Hand/wrist laceration or abrasion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Ear bruising/haematoma', 'ear_bruising_haematoma', 'dx_ear_injury_190079a2d0', 'Ear injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Ear laceration requiring suturing', 'ear_laceration_requiring_suturing', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Elbow abrasion superficial', 'elbow_abrasion_superficial', 'dx_elbow_abrasion_fca1398b6d', 'Elbow abrasion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Elbow contusion/haematoma', 'elbow_contusion_haematoma', 'dx_elbow_contusion_ac2f8ee65d', 'Elbow contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Elbow hyperextension +/- strain anterior elbow structures', 'elbow_hyperextension_strain_anterior_elbow_structures', 'dx_elbow_injury_7100f71f81', 'Elbow injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Elbow olecranon bursitis', 'elbow_olecranon_bursitis', 'dx_elbow_bursitis_24fdbc7698', 'Elbow bursitis', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Elbow posterior impingement/synovitis', 'elbow_posterior_impingement_synovitis', 'dx_posterior_elbow_impingement_9844ae2f8c', 'Posterior elbow impingement', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Elbow ulna/medial collateral ligament (UCL) strain or tear', 'elbow_ulna_medial_collateral_ligament_ucl_strain_or_tear', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Epistaxis', 'epistaxis', 'dx_epistaxis_671a1d1cf3', 'Epistaxis', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Eye bruising/haematoma', 'eye_bruising_haematoma', 'dx_eye_contusion_e7b7eba1e2', 'Eye contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Eye injury/trauma', 'eye_injury_trauma', 'dx_eye_trauma_0bcdc22eb2', 'Eye trauma', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Eyebrow laceration requiring suturing', 'eyebrow_laceration_requiring_suturing', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Eyelid laceration not requiring suturing', 'eyelid_laceration_not_requiring_suturing', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Eyelid laceration requiring suturing', 'eyelid_laceration_requiring_suturing', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Facet Joint/Neck Ligament sprain', 'facet_joint_neck_ligament_sprain', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Facial abrasion not otherwise specified', 'facial_abrasion_not_otherwise_specified', 'dx_facial_abrasion_not_otherwise_specified_3e4564695d', 'Facial abrasion not otherwise specified', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Facial laceration not requiring suturing', 'facial_laceration_not_requiring_suturing', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Facial laceration requiring suturing', 'facial_laceration_requiring_suturing', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Fat pad contusion heel', 'fat_pad_contusion_heel', 'dx_heel_contusion_4009d671bf', 'Heel contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Femoroacetabular impingement of the hip', 'femoroacetabular_impingement_of_the_hip', 'dx_femoroacetabular_impingement_76f8c7b5bc', 'Femoroacetabular impingement', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Fifth metacarpal fracture', 'fifth_metacarpal_fracture', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Finger bruising/haematoma', 'finger_bruising_haematoma', 'dx_finger_contusion_3c9fa0195a', 'Finger contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Finger extensor tendon injury (incl mallet finger +/- avulsion fracture distal phalanx)', 'finger_extensor_tendon_injury_incl_mallet_finger_avulsion_fracture_distal_phalanx_', 'dx_finger_extensor_tendon_injury_mallet_finger_36d86ff004', 'Finger extensor tendon injury/mallet finger', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Finger laceration', 'finger_laceration', 'dx_hand_wrist_laceration_or_abrasion_35c31d7555', 'Hand/wrist laceration or abrasion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Flexor Hallucis Longus tendinopathy', 'flexor_hallucis_longus_tendinopathy', 'dx_flexor_hallucis_longus_tendon_injury_3ae59d52af', 'Flexor hallucis longus tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Foot abrasion', 'foot_abrasion', 'dx_foot_abrasion_aff798febb', 'Foot abrasion', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Foot bone bruise', 'foot_bone_bruise', 'dx_foot_bone_contusion_62bd9ea576', 'Foot bone contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Foot contusion/haematoma', 'foot_contusion_haematoma', 'dx_foot_contusion_6c8a5bb721', 'Foot contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Foot Joint Sprain', 'foot_joint_sprain', 'dx_foot_joint_injury_28a178b0b5', 'Foot joint injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Foot Muscle Strain/Spasm/trigger Points', 'foot_muscle_strain_spasm_trigger_points', 'dx_foot_muscle_strain_spasm_trigger_points_32f0948947', 'Foot Muscle Strain/Spasm/trigger Points', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Foot Neurological Injury', 'foot_neurological_injury', 'dx_foot_neurological_injury_78239413fe', 'Foot Neurological Injury', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Foot Pain/Injury Not otherwise specified', 'foot_pain_injury_not_otherwise_specified', 'dx_foot_pain_116521a908', 'Foot pain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Forearm contusion/haematoma', 'forearm_contusion_haematoma', 'dx_forearm_contusion_ea321e8e45', 'Forearm contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Forearm extensor tenosynovitis', 'forearm_extensor_tenosynovitis', 'dx_forearm_extensor_tenosynovitis_761e446d53', 'Forearm extensor tenosynovitis', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Forehead laceration requiring suturing', 'forehead_laceration_requiring_suturing', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Fracture 2nd metacarpal', 'fracture_2nd_metacarpal', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Fracture 2nd Metatarsal', 'fracture_2nd_metatarsal', 'dx_metatarsal_fracture_40b473e6c8', 'Metatarsal fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Fracture 3rd metacarpal', 'fracture_3rd_metacarpal', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Fracture 4th metacarpal', 'fracture_4th_metacarpal', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Fracture 5th metatarsal shaft', 'fracture_5th_metatarsal_shaft', 'dx_metatarsal_fracture_40b473e6c8', 'Metatarsal fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Fracture distal phalanx thumb', 'fracture_distal_phalanx_thumb', 'dx_thumb_distal_phalanx_fracture_148dd4f5fc', 'Thumb distal phalanx fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Fracture distal pole scaphoid', 'fracture_distal_pole_scaphoid', 'dx_scaphoid_fracture_906035d07c', 'Scaphoid fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Fracture lower rib (10 - 12', 'fracture_lower_rib_10_12', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Fracture of costochondral margin', 'fracture_of_costochondral_margin', 'dx_fracture_of_costochondral_margin_8e9fd971fe', 'Fracture of costochondral margin', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Fracture other carpal bone', 'fracture_other_carpal_bone', 'dx_fracture_other_carpal_bone_c1b47b9be2', 'Fracture other carpal bone', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Fracture radius midshaft', 'fracture_radius_midshaft', 'dx_radial_shaft_fracture_5e497038ca', 'Radial shaft fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Fractured calcaneus', 'fractured_calcaneus', 'dx_foot_fracture_05db66a2b3', 'Foot fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Fractured distal radius', 'fractured_distal_radius', 'dx_fractured_distal_radius_505ac4b58c', 'Fractured distal radius', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Fractured mid-fibula with associated syndesmosis injury ankle', 'fractured_mid_fibula_with_associated_syndesmosis_injury_ankle', 'dx_lower_leg_fracture_bfd7084788', 'Lower-leg fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Fractured midshaft tibia and fibula', 'fractured_midshaft_tibia_and_fibula', 'dx_lower_leg_fracture_bfd7084788', 'Lower-leg fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Fractured olecranon', 'fractured_olecranon', 'dx_fractured_olecranon_0ec451aae1', 'Fractured olecranon', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Fractured phalanx', 'fractured_phalanx', 'dx_finger_fracture_c3e56e214c', 'Finger fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Fractured phalanx (foot)', 'fractured_phalanx_foot_', 'dx_foot_phalanx_fracture_674038ca61', 'Foot phalanx fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Fractured Tooth', 'fractured_tooth', 'dx_fractured_tooth_bf8c5034b9', 'Fractured Tooth', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Fractured ulna midshaft', 'fractured_ulna_midshaft', 'dx_ulnar_shaft_fracture_8603134cce', 'Ulnar shaft fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Functional head pain', 'functional_head_pain', 'dx_functional_head_pain_0afead0766', 'Functional head pain', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Gastroc muscle trigger points/spasm', 'gastroc_muscle_trigger_points_spasm', 'dx_gastrocnemius_trigger_points_spasm_0e2bdaca3b', 'Gastrocnemius trigger points/spasm', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Gastrocnemius muscle injury or strain', 'gastrocnemius_muscle_injury_or_strain', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Gastrocnemius muscle injury/strain', 'gastrocnemius_muscle_injury_strain', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Glenohumeral joint sprain with chondral/labral damage (incl SLAP tear)', 'glenohumeral_joint_sprain_with_chondral_labral_damage_incl_slap_tear_', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Glenohumeral joint sprains', 'glenohumeral_joint_sprains', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Glenohumeral ligament sprain', 'glenohumeral_ligament_sprain', 'dx_shoulder_ligament_injury_4d364e78e5', 'Shoulder ligament injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Gluteal muscle strain', 'gluteal_muscle_strain', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Gluteal tendinopathy/enthesopathy', 'gluteal_tendinopathy_enthesopathy', 'dx_gluteal_tendinopathy_enthesopathy_3fe266040c', 'Gluteal tendinopathy/enthesopathy', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Gluteus maximus strain', 'gluteus_maximus_strain', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Gluteus medius/minimus strain', 'gluteus_medius_minimus_strain', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Grade 1 A/C joint sprain', 'grade_1_a_c_joint_sprain', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Grade 1 MCL tear knee', 'grade_1_mcl_tear_knee', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Grade 2 A/C joint sprain', 'grade_2_a_c_joint_sprain', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Grade 2 MCL tear knee', 'grade_2_mcl_tear_knee', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Grade 3 A/C joint dislocation', 'grade_3_a_c_joint_dislocation', 'dx_acromioclavicular_joint_dislocation_8954e719a9', 'Acromioclavicular joint dislocation', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Grade 3 hamstring strain', 'grade_3_hamstring_strain', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Groin soreness or trigger points', 'groin_soreness_or_trigger_points', 'dx_groin_soreness_or_trigger_points_70c27347b8', 'Groin soreness or trigger points', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Groin/hip abrasion', 'groin_hip_abrasion', 'dx_groin_hip_abrasion_f59b6c2719', 'Groin/hip abrasion', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Groin/hip bone contusion', 'groin_hip_bone_contusion', 'dx_groin_and_hip_bone_contusion_e0da41307f', 'Groin and hip bone contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Haematoma lesser toes', 'haematoma_lesser_toes', 'dx_toe_contusion_04da23a430', 'Toe contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Hamstring cramping during exercise', 'hamstring_cramping_during_exercise', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Hamstring origin tendon rupture', 'hamstring_origin_tendon_rupture', 'dx_hamstring_origin_tendon_rupture_4f83a46939', 'Hamstring origin tendon rupture', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Hamstring Soft Tissue Dysfunction', 'hamstring_soft_tissue_dysfunction', 'dx_hamstring_soft_tissue_dysfunction_6246d70b45', 'Hamstring Soft Tissue Dysfunction', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Hamstring strain or tear', 'hamstring_strain_or_tear', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Hamstring strain/tear', 'hamstring_strain_tear', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Hamstring tendon injury', 'hamstring_tendon_injury', 'dx_hamstring_tendon_injury_f86b1dad5b', 'Hamstring tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Hand bone contusion', 'hand_bone_contusion', 'dx_hand_bone_contusion_fc017abdce', 'Hand bone contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Hand laceration', 'hand_laceration', 'dx_hand_wrist_laceration_or_abrasion_35c31d7555', 'Hand/wrist laceration or abrasion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Hand muscle bruising/haematoma', 'hand_muscle_bruising_haematoma', 'dx_hand_muscle_contusion_or_haematoma_1d004bb885', 'Hand muscle contusion or haematoma', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Head impact (not concussion) with Criteria 2 video signs', 'head_impact_not_concussion_with_criteria_2_video_signs', 'dx_head_impact_non_concussion_3feadb53e8', 'Head impact, non-concussion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Head Injuries', 'head_injuries', 'dx_head_injury_unspecified_611d184685', 'Head injury, unspecified', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Head/facial contusion/haematoma', 'head_facial_contusion_haematoma', 'dx_head_and_facial_contusion_74a20a767e', 'Head and facial contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Head/neck impact not diagnosed as concussion', 'head_neck_impact_not_diagnosed_as_concussion', 'dx_head_impact_non_concussion_3feadb53e8', 'Head impact, non-concussion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Heel bruising/haematoma incl fat pad contusion', 'heel_bruising_haematoma_incl_fat_pad_contusion', 'dx_heel_contusion_4009d671bf', 'Heel contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Hip and Groin Muscle strain or tear', 'hip_and_groin_muscle_strain_or_tear', 'dx_hip_and_groin_muscle_injury_7ccd814142', 'Hip and groin muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Hip and Groin Muscle Strain/Tear', 'hip_and_groin_muscle_strain_tear', 'dx_hip_and_groin_muscle_injury_7ccd814142', 'Hip and groin muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Hip flexor muscle strain', 'hip_flexor_muscle_strain', 'dx_hip_flexor_injury_cedda9fa03', 'Hip flexor injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Hip Joint Inflammation/Synovitis/Other Biomechanical Lesion', 'hip_joint_inflammation_synovitis_other_biomechanical_lesion', 'dx_hip_joint_injury_07aa18de20', 'Hip joint injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Hip joint osteoarthritis (O/A)', 'hip_joint_osteoarthritis_o_a_', 'dx_hip_joint_osteoarthritis_o_a_f8633d4994', 'Hip joint osteoarthritis (O/A)', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Hip joint sprain/jar', 'hip_joint_sprain_jar', 'dx_hip_joint_injury_07aa18de20', 'Hip joint injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Hip/Groin Pain Not otherwise specified', 'hip_groin_pain_not_otherwise_specified', 'dx_hip_and_groin_pain_27531edcc3', 'Hip and groin pain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Hoffa''s fat pad impingement', 'hoffa_s_fat_pad_impingement', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Inferior shoulder dislocation', 'inferior_shoulder_dislocation', 'dx_shoulder_dislocation_2067688fdd', 'Shoulder dislocation', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Inferior tibiofibular syndesmosis sprain', 'inferior_tibiofibular_syndesmosis_sprain', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Influenza virus', 'influenza_virus', null, null, 'illness', 'out_of_scope', 'false'),
  ('Infrapatella fat pad contusion/haematoma +/- bursitis', 'infrapatella_fat_pad_contusion_haematoma_bursitis', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Insertional Achilles tendon rupture', 'insertional_achilles_tendon_rupture', 'dx_insertional_achilles_tendon_rupture_bbd1909405', 'Insertional Achilles tendon rupture', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Instability 1st MCP joint', 'instability_1st_mcp_joint', 'dx_thumb_mcp_injury_2b5c0aa20c', 'Thumb MCP injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Intercostal muscle strain', 'intercostal_muscle_strain', 'dx_intercostal_muscle_strain_f722258288', 'Intercostal muscle strain', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Jaw bruising/haematoma', 'jaw_bruising_haematoma', 'dx_jaw_bruising_haematoma_2d620564a0', 'Jaw bruising/haematoma', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Knee - Joint sprain', 'knee_joint_sprain', 'dx_knee_ligament_injury_unspecified_7ab630d44d', 'Knee ligament injury, unspecified', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Knee - Peripheral nerve injury', 'knee_peripheral_nerve_injury', 'dx_knee_peripheral_nerve_injury_d85bbaf1cb', 'Knee - Peripheral nerve injury', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Knee abrasion', 'knee_abrasion', 'dx_knee_wound_7498252643', 'Knee wound', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Knee articular cartilage damage', 'knee_articular_cartilage_damage', 'dx_knee_cartilage_injury_761df482b3', 'Knee cartilage injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Knee bone contusion', 'knee_bone_contusion', 'dx_knee_bone_contusion_ba129fc033', 'Knee bone contusion', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Knee contusion/haematoma (extraarticular)', 'knee_contusion_haematoma_extraarticular_', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Knee Fractures', 'knee_fractures', 'dx_knee_fractures_b896bc31ab', 'Knee Fractures', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Knee Impingement/Synovitis/Biomechanical Lesion not associated with other conditions', 'knee_impingement_synovitis_biomechanical_lesion_not_associated_with_other_conditions', 'dx_knee_synovitis_impingement_02e229b1cc', 'Knee synovitis/impingement', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Knee joint cartilage injury (unspecified)', 'knee_joint_cartilage_injury_unspecified_', 'dx_knee_cartilage_injury_761df482b3', 'Knee cartilage injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Knee joint effusion, cause undiagnosed', 'knee_joint_effusion_cause_undiagnosed', 'dx_knee_joint_effusion_65cd9bd317', 'Knee joint effusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Knee Joint synovitis', 'knee_joint_synovitis', 'dx_knee_synovitis_impingement_02e229b1cc', 'Knee synovitis/impingement', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Knee MCL contusion', 'knee_mcl_contusion', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Knee medial collateral ligament (MCL) injury', 'knee_medial_collateral_ligament_mcl_injury', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Knee meniscal cartilage injury', 'knee_meniscal_cartilage_injury', 'dx_meniscal_injury_b166306f7d', 'Meniscal injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Knee Meniscal cartilage injury', 'knee_meniscal_cartilage_injury', 'dx_meniscal_injury_b166306f7d', 'Meniscal injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Knee osteoarthritis (O/A)', 'knee_osteoarthritis_o_a_', 'dx_knee_osteoarthritis_088b6b8911', 'Knee osteoarthritis', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Knee Pain/Injury Not otherwise specified', 'knee_pain_injury_not_otherwise_specified', 'dx_knee_pain_609ce718bc', 'Knee pain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Knee Sprains/Ligament Injuries', 'knee_sprains_ligament_injuries', 'dx_knee_ligament_injury_unspecified_7ab630d44d', 'Knee ligament injury, unspecified', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Labral tear, hip joint', 'labral_tear_hip_joint', 'dx_hip_labral_injury_91413d20be', 'Hip labral injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Lacerated knee', 'lacerated_knee', 'dx_knee_wound_7498252643', 'Knee wound', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Laryngeal trauma', 'laryngeal_trauma', 'dx_laryngeal_trauma_0951672ed1', 'Laryngeal trauma', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Lateral hamstring insertion tendonitis', 'lateral_hamstring_insertion_tendonitis', 'dx_hamstring_tendon_injury_f86b1dad5b', 'Hamstring tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Lateral hamstring tendon rupture at knee', 'lateral_hamstring_tendon_rupture_at_knee', 'dx_lateral_hamstring_tendon_rupture_at_knee_14d1a3104c', 'Lateral hamstring tendon rupture at knee', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Lateral hamstring trigger points', 'lateral_hamstring_trigger_points', 'dx_lateral_hamstring_trigger_points_ea90bfdf92', 'Lateral hamstring trigger points', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Lateral ligaments rupture (grade 3 injury)', 'lateral_ligaments_rupture_grade_3_injury_', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Lateral meniscal tear', 'lateral_meniscal_tear', 'dx_meniscal_injury_b166306f7d', 'Meniscal injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Leg Soft Tissue Bruising/Haematoma', 'leg_soft_tissue_bruising_haematoma', 'dx_leg_soft_tissue_contusion_or_haematoma_2264434fff', 'Leg soft tissue contusion or haematoma', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Lisfranc Sprain', 'lisfranc_sprain', 'dx_lisfranc_injury_a82b5577c5', 'Lisfranc injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Loose Body in Elbow', 'loose_body_in_elbow', 'dx_elbow_loose_body_85f452ea62', 'Elbow loose body', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Lower Leg Laceration', 'lower_leg_laceration', 'dx_lower_leg_laceration_5e3fbc19d5', 'Lower leg laceration', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Lower leg muscle Injury', 'lower_leg_muscle_injury', 'dx_lower_leg_muscle_injury_95c9565f32', 'Lower leg muscle Injury', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Lumbar contusion/haematoma', 'lumbar_contusion_haematoma', 'dx_lumbar_soft_tissue_contusion_125139d685', 'Lumbar soft tissue contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Lumbar disc annular tear', 'lumbar_disc_annular_tear', 'dx_lumbar_disc_annular_tear_77982d4ca8', 'Lumbar disc annular tear', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Lumbar disc injury with associated L5 nerve root injury', 'lumbar_disc_injury_with_associated_l5_nerve_root_injury', 'dx_lumbar_disc_injury_a2189aa3a0', 'Lumbar disc injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Lumbar disc prolapse', 'lumbar_disc_prolapse', 'dx_lumbar_disc_disorder_771d5d6a37', 'Lumbar disc disorder', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Lumbar facet joint sprain', 'lumbar_facet_joint_sprain', 'dx_lumbar_facet_joint_disorder_4a13830647', 'Lumbar facet joint disorder', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Lumbar functional movement disorder', 'lumbar_functional_movement_disorder', 'dx_lumbar_functional_disorder_54b3525e5c', 'Lumbar functional disorder', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Lumbar pain non-specific', 'lumbar_pain_non_specific', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Lumbar pain or injury, not otherwise specified', 'lumbar_pain_or_injury_not_otherwise_specified', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Lumbar pain with hamstring referral', 'lumbar_pain_with_hamstring_referral', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Lumbar Pain/ Injury nor otherwise specified', 'lumbar_pain_injury_nor_otherwise_specified', 'dx_lumbar_pain_injury_nor_otherwise_specified_85b05c0bc8', 'Lumbar Pain/ Injury nor otherwise specified', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Lumbar pain/injury not otherwise specified', 'lumbar_pain_injury_not_otherwise_specified', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Lumbar soreness or muscle spasm', 'lumbar_soreness_or_muscle_spasm', 'dx_lumbar_soreness_or_muscle_spasm_d5cbfcf03b', 'Lumbar soreness or muscle spasm', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Lumbar spinal injury', 'lumbar_spinal_injury', 'dx_lumbar_spinal_injury_eec16e7f16', 'Lumbar spinal injury', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Lumbar Spine muscle and Tendon Strain/Spasm/Trigger Points', 'lumbar_spine_muscle_and_tendon_strain_spasm_trigger_points', 'dx_lumbar_spine_muscle_and_tendon_strain_spasm_trigger_points_0af31940e8', 'Lumbar Spine muscle and Tendon Strain/Spasm/Trigger Points', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Lumbar Spine Neurological Injury', 'lumbar_spine_neurological_injury', 'dx_lumbar_neurological_injury_bb35f1e8ee', 'Lumbar neurological injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Mandible fracture', 'mandible_fracture', 'dx_mandible_fracture_c2163574d2', 'Mandible fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('MCL rupture knee', 'mcl_rupture_knee', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Medial gastroc strain', 'medial_gastroc_strain', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Medial Wall orbit fracture', 'medial_wall_orbit_fracture', 'dx_medial_wall_orbit_fracture_02a2c03441', 'Medial Wall orbit fracture', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Metacarpophalangeal ulnar collateral ligament sprain', 'metacarpophalangeal_ulnar_collateral_ligament_sprain', 'dx_metacarpophalangeal_ulnar_collateral_ligament_sprain_a1ef5f9a21', 'Metacarpophalangeal ulnar collateral ligament sprain', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Metatarsal Stress Reaction', 'metatarsal_stress_reaction', 'dx_metatarsal_stress_reaction_b33d3fd741', 'Metatarsal Stress Reaction', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Middle finger flexor tendon rupture', 'middle_finger_flexor_tendon_rupture', 'dx_finger_flexor_tendon_injury_93dca2c764', 'Finger flexor tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Midfoot joint/ligament sprain (incl Lisfranc)', 'midfoot_joint_ligament_sprain_incl_lisfranc_', 'dx_midfoot_injury_3332895405', 'Midfoot injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Migraine', 'migraine', null, null, 'illness', 'out_of_scope', 'false'),
  ('Mixed osteochondral and meniscal injury of the knee', 'mixed_osteochondral_and_meniscal_injury_of_the_knee', 'dx_mixed_osteochondral_and_meniscal_injury_of_the_knee_445d6bf607', 'Mixed osteochondral and meniscal injury of the knee', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Neck contusion/haematoma', 'neck_contusion_haematoma', 'dx_neck_contusion_7f04c7cc90', 'Neck contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Neck Injuries', 'neck_injuries', 'dx_neck_injuries_ea5ff4a3ab', 'Neck Injuries', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Neck muscle and/or tendon strain/spasm/trigger points', 'neck_muscle_and_or_tendon_strain_spasm_trigger_points', 'dx_neck_muscle_and_or_tendon_strain_spasm_trigger_points_9c974fe830', 'Neck muscle and/or tendon strain/spasm/trigger points', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Neck muscle soreness/spasm/torticollis', 'neck_muscle_soreness_spasm_torticollis', 'dx_neck_muscle_soreness_spasm_torticollis_3926cb2a2f', 'Neck muscle soreness/spasm/torticollis', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Neck muscle strain', 'neck_muscle_strain', 'dx_neck_muscle_injury_500aa507c9', 'Neck muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Neck pain undiagnosed', 'neck_pain_undiagnosed', 'dx_neck_pain_58ed6a0781', 'Neck pain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Neck Soft Tissue Dysfunction', 'neck_soft_tissue_dysfunction', 'dx_neck_soft_tissue_dysfunction_520d571115', 'Neck Soft Tissue Dysfunction', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Neurological Neck Injury', 'neurological_neck_injury', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Nose contusion/haematoma', 'nose_contusion_haematoma', 'dx_nose_contusion_c6e2d71b0b', 'Nose contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Nose fracture', 'nose_fracture', 'dx_nasal_fracture_a291a11f04', 'Nasal fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Orbital fracture', 'orbital_fracture', 'dx_orbital_fracture_a673b31938', 'Orbital fracture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Osteoarthritis location unspecified', 'osteoarthritis_location_unspecified', 'dx_osteoarthritis_location_unspecified_e5b8136c0c', 'Osteoarthritis location unspecified', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Other Ankle Pain/Injury not otherwise specified', 'other_ankle_pain_injury_not_otherwise_specified', 'dx_ankle_pain_de6b615afc', 'Ankle pain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Other chronic subacromial impingement', 'other_chronic_subacromial_impingement', 'dx_shoulder_impingement_c2f2a634b4', 'Shoulder impingement', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Other finger pain not otherwise specified', 'other_finger_pain_not_otherwise_specified', 'dx_finger_pain_0c38e0f81a', 'Finger pain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Other foot soft tissue bruising/haematoma not elsewhere specified', 'other_foot_soft_tissue_bruising_haematoma_not_elsewhere_specified', 'dx_foot_contusion_6c8a5bb721', 'Foot contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Other gluteal muslce trigger points', 'other_gluteal_muslce_trigger_points', 'dx_other_gluteal_muslce_trigger_points_449b63ecd4', 'Other gluteal muslce trigger points', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Other hand or finger ligament tear', 'other_hand_or_finger_ligament_tear', 'dx_other_hand_or_finger_ligament_tear_b218208d22', 'Other hand or finger ligament tear', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Other quadricep strain', 'other_quadricep_strain', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Other shin soft tissue bruising/haematoma not otherwise specified', 'other_shin_soft_tissue_bruising_haematoma_not_otherwise_specified', 'dx_lower_leg_contusion_fb9e4ab231', 'Lower leg contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Other skin infection not specifically mentioned', 'other_skin_infection_not_specifically_mentioned', null, null, 'illness', 'out_of_scope', 'false'),
  ('Other soft tissue bruising/haematoma knee', 'other_soft_tissue_bruising_haematoma_knee', 'dx_knee_contusion_94058fe1a4', 'Knee contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Other Stress/Overuse Injury Hip and Groin', 'other_stress_overuse_injury_hip_and_groin', 'dx_hip_and_groin_overuse_injury_71c787dc38', 'Hip and groin overuse injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Other Upper arm soft tissue bruising/haematoma', 'other_upper_arm_soft_tissue_bruising_haematoma', 'dx_upper_arm_soft_tissue_contusion_or_haematoma_9e41a8da30', 'Upper arm soft tissue contusion or haematoma', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Other upper respiratory tract infection', 'other_upper_respiratory_tract_infection', null, null, 'illness', 'out_of_scope', 'false'),
  ('Other Wrist Injury not otherwise specified', 'other_wrist_injury_not_otherwise_specified', 'dx_other_wrist_injury_not_otherwise_specified_9b197015b7', 'Other Wrist Injury not otherwise specified', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Other wrist pain not otherwise specified', 'other_wrist_pain_not_otherwise_specified', 'dx_wrist_or_hand_pain_57c9958c78', 'Wrist or hand pain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Partial ACL tear', 'partial_acl_tear', 'dx_acl_injury_4b8eb47e96', 'ACL injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Partial PCL tear', 'partial_pcl_tear', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Patellar contusion', 'patellar_contusion', 'dx_patellar_contusion_b8aa88789c', 'Patellar contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Patellar tendinopathy', 'patellar_tendinopathy', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Patellar Tendon Injury', 'patellar_tendon_injury', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Patellofemoral joint chondral pain', 'patellofemoral_joint_chondral_pain', 'dx_patellofemoral_injury_a6e2fe370a', 'Patellofemoral injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Patellofemoral pain with patellar tendinopathy', 'patellofemoral_pain_with_patellar_tendinopathy', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Pectoralis major muscle strain', 'pectoralis_major_muscle_strain', 'dx_pectoral_muscle_injury_981511cfe1', 'Pectoral muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Pectoralis major tendon injury', 'pectoralis_major_tendon_injury', 'dx_pectoralis_major_tendon_injury_a8d80cd7ea', 'Pectoralis major tendon injury', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Pes anserine bursitis of the knee', 'pes_anserine_bursitis_of_the_knee', 'dx_pes_anserine_bursitis_3af1f08842', 'Pes anserine bursitis', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('PIP joint dislocation little finger', 'pip_joint_dislocation_little_finger', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('PIP joint dislocation middle finger', 'pip_joint_dislocation_middle_finger', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('PIP joint dislocation ring finger', 'pip_joint_dislocation_ring_finger', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Piriformis syndrome (with sciatic nerve impingement)', 'piriformis_syndrome_with_sciatic_nerve_impingement_', 'dx_piriformis_syndrome_d562318818', 'Piriformis syndrome', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Plantar fascia rupture', 'plantar_fascia_rupture', 'dx_plantar_fascia_rupture_dbe62f4d0b', 'Plantar fascia rupture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Plantar heel pain (fasciitis/strain/calcaneal spur)', 'plantar_heel_pain_fasciitis_strain_calcaneal_spur_', 'dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b', 'Plantar heel pain/fasciopathy', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Plantar plate disruption MTP joint', 'plantar_plate_disruption_mtp_joint', 'dx_plantar_plate_disruption_mtp_joint_89172e7e78', 'Plantar plate disruption MTP joint', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Popliteus tendinopathy/strain', 'popliteus_tendinopathy_strain', 'dx_popliteus_injury_0ac29f0573', 'Popliteus injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Post open shoulder stabilisation', 'post_open_shoulder_stabilisation', 'dx_post_open_shoulder_stabilisation_41692eabe8', 'Post open shoulder stabilisation', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Post shoulder surgery', 'post_shoulder_surgery', 'dx_postoperative_shoulder_condition_ee7c38fb4d', 'Postoperative shoulder condition', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Posterior cruciate ligament (PCL) injury', 'posterior_cruciate_ligament_pcl_injury', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Posterior impingement ankle', 'posterior_impingement_ankle', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Posterior labral lesion of the shoulder', 'posterior_labral_lesion_of_the_shoulder', 'dx_shoulder_labral_injury_c99b83bba8', 'Shoulder labral injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Posterior shoulder instability', 'posterior_shoulder_instability', 'dx_shoulder_instability_2b9f54f442', 'Shoulder instability', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Posterolateral corner and LCL ligament injuries knee', 'posterolateral_corner_and_lcl_ligament_injuries_knee', 'dx_knee_posterolateral_corner_injury_a4c4c64579', 'Knee posterolateral corner injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Prepatellar bursitis', 'prepatellar_bursitis', 'dx_prepatellar_bursitis_d7a88bac59', 'Prepatellar bursitis', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Proximal adductor trigger points', 'proximal_adductor_trigger_points', 'dx_proximal_adductor_trigger_points_e0737a9324', 'Proximal adductor trigger points', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Proximal biceps tendon injury', 'proximal_biceps_tendon_injury', 'dx_biceps_tendon_injury_cbd11d2125', 'Biceps tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Proximal phalanx fracture index finger', 'proximal_phalanx_fracture_index_finger', 'dx_proximal_phalanx_fracture_index_finger_b771113e11', 'Proximal phalanx fracture index finger', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Proximal phalanx fracture ring finger', 'proximal_phalanx_fracture_ring_finger', 'dx_proximal_phalanx_fracture_ring_finger_ce93c277e9', 'Proximal phalanx fracture ring finger', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Quadriceps muscle haematoma', 'quadriceps_muscle_haematoma', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Quadriceps strain or tear', 'quadriceps_strain_or_tear', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Quadriceps tendinopathy +/- suprapatellar bursitis', 'quadriceps_tendinopathy_suprapatellar_bursitis', 'dx_quadriceps_tendon_injury_08ea99efaf', 'Quadriceps tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Rectus abdominus strain', 'rectus_abdominus_strain', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Rectus femoris origin tendon rupture', 'rectus_femoris_origin_tendon_rupture', 'dx_rectus_femoris_tendon_rupture_0e94ff146b', 'Rectus femoris tendon rupture', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Rectus femoris strain', 'rectus_femoris_strain', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Retinal detachment', 'retinal_detachment', 'dx_retinal_detachment_b855388d45', 'Retinal detachment', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Ring finger flexor tendon rupture', 'ring_finger_flexor_tendon_rupture', 'dx_finger_flexor_tendon_injury_93dca2c764', 'Finger flexor tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Rotator Cuff muscle injury', 'rotator_cuff_muscle_injury', 'dx_rotator_cuff_injury_0744f75c4c', 'Rotator cuff injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Rupture of long head of biceps tendon', 'rupture_of_long_head_of_biceps_tendon', 'dx_rupture_of_long_head_of_biceps_tendon_3390bb5c65', 'Rupture of long head of biceps tendon', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Ruptured Baker''s Cyst', 'ruptured_baker_s_cyst', 'dx_ruptured_baker_s_cyst_dd9ae083a6', 'Ruptured Baker''s Cyst', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Scalp laceration', 'scalp_laceration', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Scapholunate ligament sprain', 'scapholunate_ligament_sprain', 'dx_wrist_ligament_injury_6b21f37d24', 'Wrist ligament injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Scapholunate ligament sprain/tear', 'scapholunate_ligament_sprain_tear', 'dx_scapholunate_ligament_injury_0d2ca4c746', 'Scapholunate ligament injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Semimembranosis/tendinosis strain (grade 1 - 2)', 'semimembranosis_tendinosis_strain_grade_1_2_', 'dx_hamstring_muscle_injury_f003473b56', 'Hamstring muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Sesamoid stress injury', 'sesamoid_stress_injury', 'dx_foot_bone_stress_injury_unspecified_872bcaf23e', 'Foot bone stress injury, unspecified', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Sesamoiditis/stress fracture', 'sesamoiditis_stress_fracture', 'dx_sesamoiditis_stress_fracture_3f3eb10d2d', 'Sesamoiditis/stress fracture', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Shin abrasion', 'shin_abrasion', 'dx_shin_abrasion_c327f2dfa3', 'Shin abrasion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Shin contusion', 'shin_contusion', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Shoulder contusion/haematoma', 'shoulder_contusion_haematoma', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Shoulder impingement/Synovitis', 'shoulder_impingement_synovitis', 'dx_shoulder_impingement_c2f2a634b4', 'Shoulder impingement', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Shoulder muscle haematoma', 'shoulder_muscle_haematoma', 'dx_shoulder_muscle_contusion_7c8bce0320', 'Shoulder muscle contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Shoulder Neurological injury', 'shoulder_neurological_injury', 'dx_shoulder_neurological_injury_bb131de542', 'Shoulder Neurological injury', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Shoulder Osteoarthritis', 'shoulder_osteoarthritis', 'dx_shoulder_osteoarthritis_d4977e3889', 'Shoulder Osteoarthritis', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Shoulder pain undiagnosed', 'shoulder_pain_undiagnosed', 'dx_shoulder_pain_738e4b93f7', 'Shoulder pain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Shoulder region contusion', 'shoulder_region_contusion', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Shoulder Soft Tissue Dysfunction', 'shoulder_soft_tissue_dysfunction', 'dx_shoulder_soft_tissue_dysfunction_d518e56d10', 'Shoulder Soft Tissue Dysfunction', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Soleus muscle strain', 'soleus_muscle_strain', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Soleus Trigger points/Spasm', 'soleus_trigger_points_spasm', 'dx_soleus_trigger_points_spasm_56202bbe31', 'Soleus trigger points/spasm', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Spinal joint sprain', 'spinal_joint_sprain', 'dx_spinal_joint_sprain_5136523f74', 'Spinal joint sprain', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Sportsman''s hernia', 'sportsman_s_hernia', 'dx_sports_hernia_ad99f8552f', 'Sports hernia', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Sprain 1st MTP joint with volar plate rupture', 'sprain_1st_mtp_joint_with_volar_plate_rupture', 'dx_first_mtp_joint_sprain_3d3547b2db', 'First MTP joint sprain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Sprain lateral collateral ligament ankle', 'sprain_lateral_collateral_ligament_ankle', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Sprain medial collateral (deltoid) ligament ankle', 'sprain_medial_collateral_deltoid_ligament_ankle', 'dx_medial_ankle_ligament_injury_9add2aecee', 'Medial ankle ligament injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Sprain of great toe', 'sprain_of_great_toe', 'dx_great_toe_injury_71c02ad835', 'Great toe injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Sprained superior tibiofibular joint', 'sprained_superior_tibiofibular_joint', 'dx_superior_tibiofibular_joint_sprain_b52d941096', 'Superior tibiofibular joint sprain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Sprained toe/''turf toe''', 'sprained_toe_turf_toe_', 'dx_great_toe_injury_71c02ad835', 'Great toe injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Sprained ulnar collateral ligament (Skier''s) thumb', 'sprained_ulnar_collateral_ligament_skier_s_thumb', 'dx_thumb_ucl_injury_00b846b6dd', 'Thumb UCL injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Sprained/jarred elbow', 'sprained_jarred_elbow', 'dx_elbow_injury_7100f71f81', 'Elbow injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Sprained/jarred wrist joint', 'sprained_jarred_wrist_joint', 'dx_wrist_injury_d94414e2c6', 'Wrist injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Sternal fracture', 'sternal_fracture', 'dx_sternal_fracture_502ba5d67f', 'Sternal fracture', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Sternoclavicular joint sprains', 'sternoclavicular_joint_sprains', 'dx_sternoclavicular_joint_sprain_6316623d10', 'Sternoclavicular joint sprain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Subscapularis Tendon Injury', 'subscapularis_tendon_injury', 'dx_subscapularis_tendon_injury_fb2a0a8f78', 'Subscapularis Tendon Injury', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Superior Labrum Anterior and Posterior (SLAP) lesion shoulder', 'superior_labrum_anterior_and_posterior_slap_lesion_shoulder', 'dx_shoulder_labral_injury_c99b83bba8', 'Shoulder labral injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Supraspinatus tendinopathy', 'supraspinatus_tendinopathy', 'dx_supraspinatus_tendinopathy_0badf3caf7', 'Supraspinatus tendinopathy', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Supraspinatus tendon tear partial thickness', 'supraspinatus_tendon_tear_partial_thickness', 'dx_supraspinatus_tendon_injury_3840a1f333', 'Supraspinatus tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Tendinopathy crossing anatomical boundaries', 'tendinopathy_crossing_anatomical_boundaries', 'dx_tendinopathy_crossing_anatomical_boundaries_05a9131487', 'Tendinopathy crossing anatomical boundaries', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Thigh contusion or haematoma', 'thigh_contusion_or_haematoma', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Thigh Laceration/Abrasion', 'thigh_laceration_abrasion', 'dx_thigh_laceration_or_abrasion_cec8e820c4', 'Thigh laceration or abrasion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Thigh muscle cramping during exercise', 'thigh_muscle_cramping_during_exercise', 'dx_thigh_muscle_cramping_during_exercise_1421f33fc9', 'Thigh muscle cramping during exercise', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Thigh muscle haematoma', 'thigh_muscle_haematoma', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Thigh Muscle strain/Spasm/Trigger Points', 'thigh_muscle_strain_spasm_trigger_points', 'dx_thigh_muscle_strain_spasm_trigger_points_bba788e936', 'Thigh Muscle strain/Spasm/Trigger Points', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Thigh pain/Injury Not otherwise specified', 'thigh_pain_injury_not_otherwise_specified', 'dx_thigh_pain_injury_not_otherwise_specified_aa85f89649', 'Thigh pain/Injury Not otherwise specified', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Thigh Tendon Injuries', 'thigh_tendon_injuries', 'dx_thigh_tendon_injuries_a3b0c35c5e', 'Thigh Tendon Injuries', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Thoracic disc prolapse', 'thoracic_disc_prolapse', 'dx_thoracic_disc_disorder_9d9c895000', 'Thoracic disc disorder', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Thoracic facet joint sprain', 'thoracic_facet_joint_sprain', 'dx_thoracic_facet_joint_disorder_519c2ae5a8', 'Thoracic facet joint disorder', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Thoracic Muscle Strain/Spasm/Trigger Points', 'thoracic_muscle_strain_spasm_trigger_points', 'dx_thoracic_muscle_strain_spasm_trigger_points_c483ca1853', 'Thoracic Muscle Strain/Spasm/Trigger Points', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Thoracic Pain/Injury not otherwise specified', 'thoracic_pain_injury_not_otherwise_specified', 'dx_thoracic_spine_pain_9ec9a9f2e5', 'Thoracic spine pain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Thumb bruising/haematoma', 'thumb_bruising_haematoma', 'dx_thumb_contusion_or_haematoma_7a219de27a', 'Thumb contusion or haematoma', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Thumb CMC joint sprain', 'thumb_cmc_joint_sprain', 'dx_thumb_cmc_joint_sprain_01a9a8af0e', 'Thumb CMC joint sprain', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Thumb sprain', 'thumb_sprain', 'dx_thumb_sprain_730d144cbe', 'Thumb sprain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Thumb ulnar collateral ligament (UCL) rupture at MCP joint (skier''s thumb)', 'thumb_ulnar_collateral_ligament_ucl_rupture_at_mcp_joint_skier_s_thumb_', 'dx_thumb_ucl_injury_00b846b6dd', 'Thumb UCL injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Tibial bone bruise', 'tibial_bone_bruise', 'dx_tibial_bone_contusion_d98bda7b76', 'Tibial bone contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Tibialis posterior insertional tendinopathy', 'tibialis_posterior_insertional_tendinopathy', 'dx_tibialis_posterior_insertional_tendinopathy_14f8b52c06', 'Tibialis posterior insertional tendinopathy', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Tibialis posterior tendinopathy', 'tibialis_posterior_tendinopathy', 'dx_tibialis_posterior_tendon_injury_8ddfcac54e', 'Tibialis posterior tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Toenail problem/contusion/haematoma', 'toenail_problem_contusion_haematoma', 'dx_toenail_problem_contusion_haematoma_57b819c481', 'Toenail problem/contusion/haematoma', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Transversus abdominis muscle strain', 'transversus_abdominis_muscle_strain', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Traumatic knee bursitis', 'traumatic_knee_bursitis', 'dx_knee_bursitis_42542bca17', 'Knee bursitis', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Triceps muscle strain', 'triceps_muscle_strain', 'dx_triceps_muscle_strain_0048495411', 'Triceps muscle strain', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Unknown', 'unknown', 'unknown', 'Unknown diagnosis', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Unknown diagnosis', 'unknown_diagnosis', 'unknown', 'Unknown diagnosis', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Unspecified or multiple adductor tendon injury', 'unspecified_or_multiple_adductor_tendon_injury', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Upper arm muscle bruising/haematoma', 'upper_arm_muscle_bruising_haematoma', 'dx_upper_arm_soft_tissue_contusion_or_haematoma_9e41a8da30', 'Upper arm soft tissue contusion or haematoma', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Upper limb neurological injury', 'upper_limb_neurological_injury', 'dx_upper_limb_neurological_injury_ddd5b8bace', 'Upper limb neurological injury', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Whiplash/neck sprain', 'whiplash_neck_sprain', 'dx_neck_sprain_or_whiplash_404e63fe9e', 'Neck sprain or whiplash', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Wrist fibrocartilage tear', 'wrist_fibrocartilage_tear', 'dx_wrist_fibrocartilage_injury_fddc60c8f6', 'Wrist fibrocartilage injury', 'injury_or_unresolved', 'accepted_deterministic', 'false'),
  ('Wrist ganglion', 'wrist_ganglion', 'dx_wrist_ganglion_67b6f058d5', 'Wrist ganglion', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Wrist Neurological Injury', 'wrist_neurological_injury', 'dx_wrist_neurological_injury_dcb82fa46d', 'Wrist Neurological Injury', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Wrist or hand pain undiagnosed', 'wrist_or_hand_pain_undiagnosed', 'dx_wrist_or_hand_pain_undiagnosed_7237db0cdf', 'Wrist or hand pain undiagnosed', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Wrist Osteoarthritis (O/A)', 'wrist_osteoarthritis_o_a_', 'dx_wrist_osteoarthritis_o_a_3bf013a9d8', 'Wrist Osteoarthritis (O/A)', 'injury_or_unresolved', 'identity_group', 'false'),
  ('Wrist Soft Tissue Bruising/Haematoma', 'wrist_soft_tissue_bruising_haematoma', 'dx_wrist_contusion_e9973933b6', 'Wrist contusion', 'injury_or_unresolved', 'accepted_deterministic', 'false');

create table audit.urc_2025_26_illness_exact_labels_v1 (
  adjudication_version text not null references
    audit.urc_diagnosis_family_adjudication_evidence_v1(adjudication_version)
    default 'urc_diagnosis_family_adjudication_v1',
  source_label text not null,
  illness_code text not null,
  illness_label text not null,
  review_status text not null,
  primary key (adjudication_version, source_label)
);

insert into audit.urc_2025_26_illness_exact_labels_v1 (
  source_label, illness_code, illness_label, review_status
)
values
  ('Abcess Finger(s) (excl. Joint)', 'dx_skin_infection_0815acb73e', 'Skin infection', 'accepted_deterministic'),
  ('Abcess Lower Leg', 'dx_skin_infection_0815acb73e', 'Skin infection', 'accepted_deterministic'),
  ('Allergic Reaction [N/A]', 'dx_allergic_reaction_710675864a', 'Allergic reaction', 'accepted_deterministic'),
  ('Allergy - rhinitis/ sinusitis/ hayfever (for urticaria see MDUX) [N/A]', 'dx_allergic_rhinitis_hay_fever_d80a333e92', 'Allergic rhinitis/hay fever', 'accepted_deterministic'),
  ('Allergy - rhinitis/sinusitis/hayfever', 'dx_allergic_rhinitis_hay_fever_d80a333e92', 'Allergic rhinitis/hay fever', 'accepted_deterministic'),
  ('Anxiety/ panic disorder [N/A]', 'dx_anxiety_or_related_disorder_fa6bf088b3', 'Anxiety or related disorder', 'accepted_deterministic'),
  ('Anxiety/panic/compulsive disorder', 'dx_anxiety_or_related_disorder_fa6bf088b3', 'Anxiety or related disorder', 'accepted_deterministic'),
  ('Asthma and/or allergy [N/A]', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness', 'accepted_deterministic'),
  ('Atopic dermatitis / eczema', 'dx_dermatitis_eczema_bd9da247ec', 'Dermatitis/eczema', 'accepted_deterministic'),
  ('Bacterial gastroenteritis (incl food poisoning)', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection', 'accepted_deterministic'),
  ('Benign skin lesion', 'dx_benign_skin_lesion_b6ced4831e', 'Benign skin lesion', 'accepted_deterministic'),
  ('Benign Skin lesion [Right]', 'dx_benign_skin_lesion_b6ced4831e', 'Benign skin lesion', 'accepted_deterministic'),
  ('Bronchitis', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness', 'accepted_deterministic'),
  ('Cellulitis/ Abcess Finger(s) (excl. Joint)', 'dx_skin_infection_0815acb73e', 'Skin infection', 'accepted_deterministic'),
  ('Cellulitis/ Abcess Head/ Face/ Neck', 'dx_skin_infection_0815acb73e', 'Skin infection', 'accepted_deterministic'),
  ('Cellulitis/Abcess Knee (excl. Joint)', 'dx_skin_infection_0815acb73e', 'Skin infection', 'accepted_deterministic'),
  ('Confirmed COVID-19 infection (Symptomatic)', 'dx_covid_19_infection_320f43ae05', 'COVID-19 infection', 'accepted_deterministic'),
  ('Conjunctivitis', 'dx_conjunctivitis_26dfbd55b4', 'Conjunctivitis', 'accepted_deterministic'),
  ('Conjunctivitis (Viral/ Bacterial) [Right]', 'dx_conjunctivitis_26dfbd55b4', 'Conjunctivitis', 'accepted_deterministic'),
  ('Depression/mood disorder', 'dx_depression_or_mood_disorder_be85ab8119', 'Depression or mood disorder', 'accepted_deterministic'),
  ('Dermatitis [Bilateral]', 'dx_dermatitis_eczema_bd9da247ec', 'Dermatitis/eczema', 'accepted_deterministic'),
  ('Dermatitis [N/A]', 'dx_dermatitis_eczema_bd9da247ec', 'Dermatitis/eczema', 'accepted_deterministic'),
  ('Diarrhoea', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified', 'accepted_deterministic'),
  ('Dizziness (Undiagnosed) [Right]', 'dx_dizziness_6db71bef23', 'Dizziness', 'accepted_deterministic'),
  ('Ear +/- sinuses/throat infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection', 'accepted_deterministic'),
  ('Ear infection', 'dx_ear_infection_da58e903bf', 'Ear infection', 'accepted_deterministic'),
  ('ENT Illness including dental (excl sinusitis - see MPAL) [Right]', 'dx_ent_illness_including_dental_excl_sinusitis_see_mpal_right_dfad7b9848', 'ENT Illness including dental (excl sinusitis - see MPAL) [Right]', 'identity_group'),
  ('Exercise associated gastritis/reflux', 'dx_gastritis_or_peptic_ulcer_disease_2685b6a7c1', 'Gastritis or peptic ulcer disease', 'accepted_deterministic'),
  ('Eye Infection [Right]', 'dx_eye_infection_be5c00f469', 'Eye infection', 'accepted_deterministic'),
  ('Folliculitis', 'dx_folliculitis_f099cd0651', 'Folliculitis', 'identity_group'),
  ('Foot pain undiagnosed', 'dx_foot_pain_undiagnosed_9427f60898', 'Foot pain undiagnosed', 'identity_group'),
  ('Gastritis', 'dx_gastritis_or_peptic_ulcer_disease_2685b6a7c1', 'Gastritis or peptic ulcer disease', 'accepted_deterministic'),
  ('Gastritis/peptic ulceration - non exercise/NSAID related', 'dx_gastritis_or_peptic_ulcer_disease_2685b6a7c1', 'Gastritis or peptic ulcer disease', 'accepted_deterministic'),
  ('Gastrointestinal Illness', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified', 'accepted_deterministic'),
  ('Gastrointestinal Illness [N/A]', 'dx_gastrointestinal_illness_unspecified_68c6798d27', 'Gastrointestinal illness, unspecified', 'accepted_deterministic'),
  ('Gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection', 'accepted_deterministic'),
  ('Gout in ankle/foot (incl big toe)', 'dx_gout_9b87634ff8', 'Gout', 'accepted_deterministic'),
  ('Haematemesis/melaena/GI bleeding', 'dx_haematemesis_melaena_gi_bleeding_99e31e3310', 'Haematemesis/melaena/GI bleeding', 'identity_group'),
  ('Headache not otherwise specified', 'dx_headache_45575633c6', 'Headache', 'accepted_deterministic'),
  ('Headache not otherwise specified [Right]', 'dx_headache_45575633c6', 'Headache', 'accepted_deterministic'),
  ('Headaches', 'dx_headache_45575633c6', 'Headache', 'accepted_deterministic'),
  ('Herpes gladiatorum', 'dx_herpes_infection_a87b003a4b', 'Herpes infection', 'accepted_deterministic'),
  ('Herpes simplex', 'dx_herpes_infection_a87b003a4b', 'Herpes infection', 'accepted_deterministic'),
  ('Herpes simplex (incl scrum pox) [N/A]', 'dx_herpes_infection_a87b003a4b', 'Herpes infection', 'accepted_deterministic'),
  ('Herpes simplex (incl scrum pox) [Right]', 'dx_herpes_infection_a87b003a4b', 'Herpes infection', 'accepted_deterministic'),
  ('Infected knee joint', 'dx_infected_knee_joint_d9ac8a3997', 'Infected knee joint', 'identity_group'),
  ('Infection', 'dx_infection_647573c314', 'Infection', 'identity_group'),
  ('Infective conjunctivitis', 'dx_conjunctivitis_26dfbd55b4', 'Conjunctivitis', 'accepted_deterministic'),
  ('Influenza (A/B) [Center]', 'dx_influenza_27addce986', 'Influenza', 'accepted_deterministic'),
  ('Influenza (A/B) [N/A]', 'dx_influenza_27addce986', 'Influenza', 'accepted_deterministic'),
  ('Influenza virus', 'dx_influenza_27addce986', 'Influenza', 'accepted_deterministic'),
  ('Influenza virus infection', 'dx_influenza_27addce986', 'Influenza', 'accepted_deterministic'),
  ('Lymphadenopathy secondary to skin infection', 'dx_lymphadenopathy_secondary_to_skin_infection_4586fa81bd', 'Lymphadenopathy secondary to skin infection', 'identity_group'),
  ('Medical Illness [N/A]', 'dx_medical_illness_33b4f89cb8', 'Medical illness', 'accepted_deterministic'),
  ('Medical Illness Undiagnosed/ Other [Bilateral]', 'dx_medical_illness_33b4f89cb8', 'Medical illness', 'accepted_deterministic'),
  ('Medical Illness Undiagnosed/ Other [N/A]', 'dx_medical_illness_33b4f89cb8', 'Medical illness', 'accepted_deterministic'),
  ('Medical Illness Undiagnosed/Other', 'dx_medical_illness_33b4f89cb8', 'Medical illness', 'accepted_deterministic'),
  ('Middle ear infection', 'dx_middle_ear_infection_884af7c2ae', 'Middle ear infection', 'accepted_deterministic'),
  ('Molluscum Contagiosum [Left]', 'dx_molluscum_contagiosum_left_da75c67472', 'Molluscum Contagiosum [Left]', 'identity_group'),
  ('Nausea, undiagnosed', 'dx_nausea_d6bea94b06', 'Nausea', 'accepted_deterministic'),
  ('Nose /throat illness /condition', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection', 'accepted_deterministic'),
  ('Otalgia', 'dx_otalgia_907b35c969', 'Otalgia', 'identity_group'),
  ('Otalgia [Right]', 'dx_otalgia_907b35c969', 'Otalgia', 'identity_group'),
  ('Other cardiovascular disease', 'dx_other_cardiovascular_disease_ddc1f5b58b', 'Other cardiovascular disease', 'accepted_deterministic'),
  ('Other gastrointestinal infection', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection', 'accepted_deterministic'),
  ('Other lower respiratory tract infection', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness', 'accepted_deterministic'),
  ('Other lower respiratory tract infection [N/A]', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness', 'accepted_deterministic'),
  ('Other medical illness', 'dx_medical_illness_33b4f89cb8', 'Medical illness', 'accepted_deterministic'),
  ('Other medical illness [N/A]', 'dx_medical_illness_33b4f89cb8', 'Medical illness', 'accepted_deterministic'),
  ('Other rash not otherwise mentioned or undiagnosed', 'dx_rash_8b717bdc92', 'Rash', 'accepted_deterministic'),
  ('Other rash not otherwise mentioned or undiagnosed [Bilateral]', 'dx_rash_8b717bdc92', 'Rash', 'accepted_deterministic'),
  ('Other rash not otherwise mentioned or undiagnosed [N/A]', 'dx_rash_8b717bdc92', 'Rash', 'accepted_deterministic'),
  ('Other respiratory illness not otherwise specified', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness', 'accepted_deterministic'),
  ('Other respiratory illness not otherwise specified [N/A]', 'dx_respiratory_illness_416ea1def7', 'Respiratory illness', 'accepted_deterministic'),
  ('Other skin infection not specifically mentioned [N/A]', 'dx_skin_infection_0815acb73e', 'Skin infection', 'accepted_deterministic'),
  ('Other upper resp tract infection [N/A]', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection', 'accepted_deterministic'),
  ('Other upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection', 'accepted_deterministic'),
  ('Otitis externa', 'dx_otitis_externa_2a11386697', 'Otitis externa', 'identity_group'),
  ('Otitis externa [Right]', 'dx_otitis_externa_2a11386697', 'Otitis externa', 'identity_group'),
  ('Prepatellar bursitis', 'dx_prepatellar_bursitis_d7a88bac59', 'Prepatellar bursitis', 'identity_group'),
  ('Rash /other dermatological condition', 'dx_dermatological_condition_cf62967c16', 'Dermatological condition', 'accepted_deterministic'),
  ('Respiratory system infection', 'dx_respiratory_infection_unspecified_5a61537870', 'Respiratory infection unspecified', 'accepted_deterministic'),
  ('Respiratory tract infection (bacterial or viral) [N/A]', 'dx_respiratory_infection_unspecified_5a61537870', 'Respiratory infection unspecified', 'accepted_deterministic'),
  ('Secondary Insomnia (incl other assoc. diagnosis)', 'dx_insomnia_9dcefd14ed', 'Insomnia', 'accepted_deterministic'),
  ('Shingles (Zoster Virus) [Left]', 'dx_shingles_zoster_virus_left_4995f0207b', 'Shingles (Zoster Virus) [Left]', 'identity_group'),
  ('Sinus headache [Left]', 'dx_headache_45575633c6', 'Headache', 'accepted_deterministic'),
  ('Sinusitis', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection', 'accepted_deterministic'),
  ('Sinusitis [N/A]', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection', 'accepted_deterministic'),
  ('Skin Infection - fungal', 'dx_fungal_skin_infection_3158ef505c', 'Fungal skin infection', 'accepted_deterministic'),
  ('Skin Infection - fungal [Bilateral]', 'dx_fungal_skin_infection_3158ef505c', 'Fungal skin infection', 'accepted_deterministic'),
  ('Skin Infection - fungal [N/A]', 'dx_fungal_skin_infection_3158ef505c', 'Fungal skin infection', 'accepted_deterministic'),
  ('Skin infection elbow', 'dx_skin_infection_0815acb73e', 'Skin infection', 'accepted_deterministic'),
  ('Skin infection head/face/neck', 'dx_skin_infection_0815acb73e', 'Skin infection', 'accepted_deterministic'),
  ('Skin infection toenail - incl infected ingrown toenail [Right]', 'dx_skin_infection_0815acb73e', 'Skin infection', 'accepted_deterministic'),
  ('Skin Infection/ Cellulitis/ Abscess/ Infected Bursa - bacterial (excl infection complicating laceration - see ? KXQ) [Left]', 'dx_skin_infection_0815acb73e', 'Skin infection', 'accepted_deterministic'),
  ('Skin Infection/Cellulitis/abscess', 'dx_skin_infection_0815acb73e', 'Skin infection', 'accepted_deterministic'),
  ('Sleep Disorder(s) [N/A]', 'dx_sleep_disorder_s_n_a_320a409727', 'Sleep Disorder(s) [N/A]', 'identity_group'),
  ('Systemic Viral Infection (excl viruses localised to one area) [N/A]', 'dx_systemic_viral_infection_fbc3d5171c', 'Systemic viral infection', 'accepted_deterministic'),
  ('Tinea Corporis [Left]', 'dx_fungal_skin_infection_3158ef505c', 'Fungal skin infection', 'accepted_deterministic'),
  ('Tinea pedis/athlete''s foot', 'dx_fungal_skin_infection_3158ef505c', 'Fungal skin infection', 'accepted_deterministic'),
  ('Tinea versicolor', 'dx_fungal_skin_infection_3158ef505c', 'Fungal skin infection', 'accepted_deterministic'),
  ('Tired athlete undiagnosed', 'dx_tired_athlete_undiagnosed_5039279545', 'Tired athlete undiagnosed', 'identity_group'),
  ('Tonsillitis', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection', 'accepted_deterministic'),
  ('Tonsillitis [N/A]', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection', 'accepted_deterministic'),
  ('Unknown', 'dx_unknown_illness_f92f729b89', 'Unknown illness', 'identity_group'),
  ('Unknown diagnosis', 'dx_unknown_illness_f92f729b89', 'Unknown illness', 'identity_group'),
  ('Upper respiratory tract infection', 'dx_upper_respiratory_infection_d9d6ca2eb7', 'Upper respiratory infection', 'accepted_deterministic'),
  ('Urinary problem [N/A]', 'dx_urinary_problem_n_a_9777b590df', 'Urinary problem [N/A]', 'identity_group'),
  ('Urinary Tract Infection', 'dx_urinary_tract_infection_53ee3e3cdd', 'Urinary tract infection', 'accepted_deterministic'),
  ('Vasovagal Syncope [N/A]', 'dx_vasovagal_syncope_n_a_748722364b', 'Vasovagal Syncope [N/A]', 'identity_group'),
  ('Viral gastroenteritis', 'dx_gastrointestinal_infection_441bf77fd9', 'Gastrointestinal infection', 'accepted_deterministic'),
  ('Viral or bacterial conjunctivitis', 'dx_conjunctivitis_26dfbd55b4', 'Conjunctivitis', 'accepted_deterministic'),
  ('Wisdom tooth', 'dx_dental_condition_e9d2167e5f', 'Dental condition', 'accepted_deterministic');

create function audit.reject_urc_diagnosis_family_adjudication_mutation_v1()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  raise exception 'Diagnosis-family adjudication evidence is immutable';
end;
$$;

create trigger urc_diagnosis_family_evidence_immutable
before update or delete on audit.urc_diagnosis_family_adjudication_evidence_v1
for each row execute function audit.reject_urc_diagnosis_family_adjudication_mutation_v1();
create trigger urc_2024_25_diagnosis_family_rows_immutable
before update or delete on audit.urc_2024_25_diagnosis_family_source_rows_v1
for each row execute function audit.reject_urc_diagnosis_family_adjudication_mutation_v1();
create trigger urc_2024_25_illness_profile_rows_immutable
before update or delete on audit.urc_2024_25_illness_profile_source_rows_v1
for each row execute function audit.reject_urc_diagnosis_family_adjudication_mutation_v1();
create trigger urc_2025_26_diagnosis_family_labels_immutable
before update or delete on audit.urc_2025_26_diagnosis_family_exact_labels_v1
for each row execute function audit.reject_urc_diagnosis_family_adjudication_mutation_v1();
create trigger urc_2025_26_illness_labels_immutable
before update or delete on audit.urc_2025_26_illness_exact_labels_v1
for each row execute function audit.reject_urc_diagnosis_family_adjudication_mutation_v1();

alter table audit.urc_diagnosis_family_adjudication_evidence_v1 enable row level security;
alter table audit.urc_2024_25_diagnosis_family_source_rows_v1 enable row level security;
alter table audit.urc_2024_25_illness_profile_source_rows_v1 enable row level security;
alter table audit.urc_2025_26_diagnosis_family_exact_labels_v1 enable row level security;
alter table audit.urc_2025_26_illness_exact_labels_v1 enable row level security;
revoke all on audit.urc_diagnosis_family_adjudication_evidence_v1,
  audit.urc_2024_25_diagnosis_family_source_rows_v1,
  audit.urc_2024_25_illness_profile_source_rows_v1,
  audit.urc_2025_26_diagnosis_family_exact_labels_v1,
  audit.urc_2025_26_illness_exact_labels_v1
from public, anon, authenticated, web_reader;
revoke execute on function
  audit.reject_urc_diagnosis_family_adjudication_mutation_v1()
from public, anon, authenticated, web_reader;

create table reporting.diagnosis_family_release_bindings_v1 (
  season text primary key check (season in ('2024-25', '2025-26')),
  release_id uuid not null unique references reporting.aggregate_releases(id),
  release_label text not null,
  league_payload_sha256 text not null check (league_payload_sha256 ~ '^[0-9a-f]{64}$'),
  team_count integer not null check (team_count = 16),
  adjudication_version text not null references
    audit.urc_diagnosis_family_adjudication_evidence_v1(adjudication_version)
);

insert into reporting.diagnosis_family_release_bindings_v1 (
  season, release_id, release_label, league_payload_sha256, team_count,
  adjudication_version
)
select latest.season, latest.release_id, release.release_label,
  payload.payload_sha256, 16,
  'urc_diagnosis_family_adjudication_v1'
from reporting.latest_approved_dashboard_bundle_v4 latest
join reporting.aggregate_releases release on release.id = latest.release_id
join reporting.dashboard_bundle_league_payloads_v1 payload
  on payload.release_id = latest.release_id
where latest.season = '2024-25'
union all
select latest.season, latest.release_id, release.release_label,
  payload.payload_sha256, 16,
  'urc_diagnosis_family_adjudication_v1'
from reporting.latest_approved_league_bundle_v6 latest
join reporting.aggregate_releases release on release.id = latest.release_id
join reporting.league_release_payloads_v6 payload on payload.release_id = latest.release_id
where latest.season = '2025-26';

alter table reporting.diagnosis_family_release_bindings_v1 enable row level security;
create trigger urc_diagnosis_family_release_bindings_immutable
before update or delete on reporting.diagnosis_family_release_bindings_v1
for each row execute function audit.reject_urc_diagnosis_family_adjudication_mutation_v1();
revoke all on reporting.diagnosis_family_release_bindings_v1
from public, anon, authenticated, web_reader;

create view reporting.diagnosis_family_base_team_payloads_v1
with (security_invoker = true) as
select binding.season, payload.team_key, payload.dashboard_payload as dashboard
from reporting.diagnosis_family_release_bindings_v1 binding
join reporting.dashboard_bundle_team_payloads_v1 payload
  on payload.bundle_release_id = binding.release_id
where binding.season = '2024-25'
union all
select binding.season, payload.team_key, payload.dashboard_payload
from reporting.diagnosis_family_release_bindings_v1 binding
join reporting.team_dashboard_payloads_v2 payload
  on payload.bundle_release_id = binding.release_id
where binding.season = '2025-26';

create view reporting.diagnosis_family_base_league_payloads_v1
with (security_invoker = true) as
select binding.season, payload.dashboard_payload as dashboard
from reporting.diagnosis_family_release_bindings_v1 binding
join reporting.dashboard_bundle_league_payloads_v1 payload
  on payload.release_id = binding.release_id
where binding.season = '2024-25'
union all
select binding.season, payload.dashboard_payload
from reporting.diagnosis_family_release_bindings_v1 binding
join reporting.league_release_payloads_v6 payload
  on payload.release_id = binding.release_id
where binding.season = '2025-26';

revoke all on reporting.diagnosis_family_base_team_payloads_v1,
  reporting.diagnosis_family_base_league_payloads_v1
from public, anon, authenticated, web_reader;

create view analysis.urc_2025_26_canonical_injury_rows_v1
with (security_invoker = true) as
select injury.team_key, injury.source_row, injury.injury_date,
  injury.is_time_loss, injury.days_lost, injury.setting_code,
  injury.contact_context,
  injury.reporting_body_location_code as body_location_code,
  injury.reporting_body_location_label as body_location_label,
  injury.reporting_injury_type_code as injury_type_code,
  injury.reporting_injury_type_label as injury_type_label,
  injury.reporting_diagnosis_code as diagnosis_code,
  injury.diagnosis_label, injury.severity_code
from analysis.urc_2025_26_reporting_key_rows_v3 injury
join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence on true
join lineage.injury_master_rows_v3 master
  on master.version_id = evidence.successor_version_id
 and master.source_row = injury.source_row
where lower(btrim(master.row_values ->> 'Problem type')) = 'injury';

create view analysis.urc_canonical_injury_rows_v1
with (security_invoker = true) as
select injury.season, injury.team_key, injury.source_row, injury.date_injured
  as injury_date, injury.final_classification = 'Time Loss' as is_time_loss,
  case when injury.duration_usable then injury.days_lost end as days_lost,
  injury.setting_code, injury.contact_context, injury.body_location_code,
  injury.body_location_label, injury.injury_type_code, injury.injury_type_label,
  injury.diagnosis_code, injury.diagnosis_label,
  coalesce(injury.severity_code, 'unknown_or_censored') as severity_code
from analysis.urc_2024_25_final_injury_classification_v1 injury
where injury.canonical_problem_type = 'injury'
union all
select '2025-26', injury.team_key, injury.source_row, injury.injury_date,
  injury.is_time_loss, injury.days_lost, injury.setting_code,
  injury.contact_context, injury.body_location_code, injury.body_location_label,
  injury.injury_type_code, injury.injury_type_label, injury.diagnosis_code,
  injury.diagnosis_label, injury.severity_code
from analysis.urc_2025_26_canonical_injury_rows_v1 injury;

create materialized view analysis.urc_diagnosis_family_rows_v1 as
select injury.season, injury.team_key, injury.source_row,
  injury.setting_code, injury.final_classification = 'Time Loss' as is_time_loss,
  case when injury.duration_usable then injury.days_lost end as days_lost,
  family.family_code, family.family_label,
  family.subtype_code, family.source_label as subtype_label
from analysis.urc_2024_25_final_injury_classification_v1 injury
join audit.urc_2024_25_diagnosis_family_source_rows_v1 family
  on family.source_row = injury.source_row
join audit.urc_2024_25_specific_diagnosis_mappings_v1 source_evidence
  on source_evidence.season = injury.season
 and source_evidence.source_row = family.source_row
 and source_evidence.source_row_sha256 = family.source_row_sha256
where injury.canonical_problem_type = 'injury'
union all
select injury.season, injury.team_key, injury.source_row,
  injury.setting_code, injury.final_classification = 'Time Loss',
  case when injury.duration_usable then injury.days_lost end,
  'unknown', 'Unknown', 'subtype_unknown',
  coalesce(nullif(injury.diagnosis_label, ''), 'Unknown')
from analysis.urc_2024_25_final_injury_classification_v1 injury
left join audit.urc_2024_25_diagnosis_family_source_rows_v1 family
  on family.source_row = injury.source_row
where injury.canonical_problem_type = 'injury' and family.source_row is null
union all
select '2025-26', injury.team_key, injury.source_row, injury.setting_code,
  injury.is_time_loss, injury.days_lost,
  family.family_code, family.family_label,
  family.subtype_code, family.source_label
from analysis.urc_2025_26_canonical_injury_rows_v1 injury
join audit.urc_2025_26_diagnosis_family_exact_labels_v1 family
  on family.source_label = injury.diagnosis_label
 and family.family_code is not null
union all
select '2025-26', injury.team_key, injury.source_row, injury.setting_code,
  injury.is_time_loss, injury.days_lost,
  'unknown', 'Unknown diagnosis', 'subtype_unknown', injury.diagnosis_label
from analysis.urc_2025_26_canonical_injury_rows_v1 injury
left join audit.urc_2025_26_diagnosis_family_exact_labels_v1 family
  on family.source_label = injury.diagnosis_label
where family.family_code is null;

revoke all on analysis.urc_2025_26_canonical_injury_rows_v1,
  analysis.urc_canonical_injury_rows_v1,
  analysis.urc_diagnosis_family_rows_v1
from public, anon, authenticated, web_reader;

create view analysis.urc_diagnosis_family_team_exposure_v1
with (security_invoker = true) as
select payload.season, payload.team_key, setting.setting_code,
  case setting.setting_code
    when 'all' then (payload.dashboard #>> '{coverage,hours}')::numeric
    when 'match' then (payload.dashboard #>> '{coverage,match_hours}')::numeric
    when 'training' then (payload.dashboard #>> '{coverage,training_hours}')::numeric
  end as exposure_hours
from reporting.diagnosis_family_base_team_payloads_v1 payload
cross join (values ('all'::text), ('match'::text), ('training'::text), ('unknown'::text))
  setting(setting_code);

create view analysis.urc_diagnosis_family_team_subtypes_v1
with (security_invoker = true) as
with expanded as (
  select row.season, row.team_key, row.source_row, setting.setting_code,
    row.is_time_loss, row.days_lost, row.family_code, row.family_label,
    row.subtype_code, row.subtype_label
  from analysis.urc_diagnosis_family_rows_v1 row
  cross join lateral (
    select 'all'::text as setting_code
    union all select row.setting_code
  ) setting
)
select season, team_key, setting_code, family_code, family_label,
  subtype_code, subtype_label,
  count(*)::bigint as recorded_injuries,
  count(*) filter (where is_time_loss)::bigint as time_loss_injuries,
  count(*) filter (where is_time_loss and days_lost is not null)::bigint
    as known_duration_time_loss_injuries,
  coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days_lost
from expanded
group by season, team_key, setting_code, family_code, family_label,
  subtype_code, subtype_label;

create view analysis.urc_diagnosis_family_team_families_v1
with (security_invoker = true) as
with grouped as (
  select season, team_key, setting_code, family_code, family_label,
    sum(recorded_injuries)::bigint as recorded_injuries,
    sum(time_loss_injuries)::bigint as time_loss_injuries,
    sum(known_duration_time_loss_injuries)::bigint
      as known_duration_time_loss_injuries,
    sum(days_lost)::numeric as days_lost
  from analysis.urc_diagnosis_family_team_subtypes_v1
  group by season, team_key, setting_code, family_code, family_label
)
select grouped.*, exposure.exposure_hours,
  grouped.time_loss_injuries * 1000 / nullif(exposure.exposure_hours, 0)
    as incidence_per_1000h,
  grouped.days_lost * 1000 / nullif(exposure.exposure_hours, 0)
    as burden_per_1000h,
  grouped.days_lost / nullif(grouped.known_duration_time_loss_injuries, 0)
    as mean_severity_days
from grouped
join analysis.urc_diagnosis_family_team_exposure_v1 exposure
  using (season, team_key, setting_code);

create view analysis.urc_diagnosis_family_league_exposure_v1
with (security_invoker = true) as
select season, setting_code,
  case when count(exposure_hours) = 16 then sum(exposure_hours) end as exposure_hours
from analysis.urc_diagnosis_family_team_exposure_v1
group by season, setting_code;

create view analysis.urc_diagnosis_family_league_subtypes_v1
with (security_invoker = true) as
select season, setting_code, family_code, family_label,
  subtype_code, subtype_label,
  sum(recorded_injuries)::bigint as recorded_injuries,
  sum(time_loss_injuries)::bigint as time_loss_injuries,
  sum(known_duration_time_loss_injuries)::bigint
    as known_duration_time_loss_injuries,
  sum(days_lost)::numeric as days_lost
from analysis.urc_diagnosis_family_team_subtypes_v1
group by season, setting_code, family_code, family_label,
  subtype_code, subtype_label;

create view analysis.urc_diagnosis_family_league_families_v1
with (security_invoker = true) as
with grouped as (
  select season, setting_code, family_code, family_label,
    sum(recorded_injuries)::bigint as recorded_injuries,
    sum(time_loss_injuries)::bigint as time_loss_injuries,
    sum(known_duration_time_loss_injuries)::bigint
      as known_duration_time_loss_injuries,
    sum(days_lost)::numeric as days_lost
  from analysis.urc_diagnosis_family_league_subtypes_v1
  group by season, setting_code, family_code, family_label
)
select grouped.*, exposure.exposure_hours,
  grouped.time_loss_injuries * 1000 / nullif(exposure.exposure_hours, 0)
    as incidence_per_1000h,
  grouped.days_lost * 1000 / nullif(exposure.exposure_hours, 0)
    as burden_per_1000h,
  grouped.days_lost / nullif(grouped.known_duration_time_loss_injuries, 0)
    as mean_severity_days
from grouped
join analysis.urc_diagnosis_family_league_exposure_v1 exposure
  using (season, setting_code);

create materialized view analysis.urc_illness_profile_rows_v1 as
select illness.season, illness.team_key, illness.source_row,
  illness.illness_code, illness.illness_label,
  illness.days_lost is not null as duration_known, illness.days_lost
from (
  select '2024-25'::text as season, bridge.team_key, profile.source_row,
    profile.illness_code, profile.illness_label,
    case when btrim(subject.final_values ->> 'Days Injured')
      ~ '^[0-9]+(\.[0-9]+)?$'
      then btrim(subject.final_values ->> 'Days Injured')::numeric end as days_lost
  from audit.urc_2024_25_illness_profile_source_rows_v1 profile
  join lineage.master_source_bridge bridge
    on bridge.season = '2024-25' and bridge.source_row = profile.source_row
  cross join lateral analysis.row_correction_subject_v3(
    '2024-25', bridge.source_row_id
  ) subject
  where lower(btrim(subject.final_values ->> 'Problem type')) = 'illness'
) illness
union all
select '2025-26', inclusion.team_key, inclusion.source_row,
  profile.illness_code, profile.illness_label,
  master.time_loss_days is not null,
  master.time_loss_days
from lineage.injury_inclusion_rows_v3 inclusion
join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
  on inclusion.version_id = evidence.successor_version_id
join lineage.injury_master_rows_v3 master
  on master.version_id = inclusion.version_id
 and master.source_row = inclusion.source_row
join audit.urc_2025_26_illness_exact_labels_v1 profile
  on profile.source_label = coalesce(
    nullif(btrim(master.row_values ->> 'Specific Diagnosis'), ''), 'Unknown'
  )
where inclusion.dashboard_eligibility_reason = 'illness_record_not_in_injury_cohort'
  and lower(btrim(master.row_values ->> 'Problem type')) = 'illness';

create view analysis.urc_illness_team_profiles_v1
with (security_invoker = true) as
with grouped as (
  select season, team_key, illness_code, illness_label,
    count(*)::bigint as recorded_illnesses,
    count(*) filter (where duration_known)::bigint as known_duration_illnesses,
    coalesce(sum(days_lost) filter (where duration_known), 0)::numeric as days_lost
  from analysis.urc_illness_profile_rows_v1
  group by season, team_key, illness_code, illness_label
)
select grouped.*, 'all'::text as setting, exposure.exposure_hours,
  grouped.recorded_illnesses * 1000 / nullif(exposure.exposure_hours, 0)
    as incidence_per_1000h,
  grouped.days_lost * 1000 / nullif(exposure.exposure_hours, 0)
    as burden_per_1000h,
  grouped.days_lost / nullif(grouped.known_duration_illnesses, 0)
    as mean_severity_days
from grouped
join analysis.urc_diagnosis_family_team_exposure_v1 exposure
  on exposure.season = grouped.season
 and exposure.team_key = grouped.team_key
 and exposure.setting_code = 'all';

create view analysis.urc_illness_league_profiles_v1
with (security_invoker = true) as
with grouped as (
  select season, illness_code, illness_label,
    sum(recorded_illnesses)::bigint as recorded_illnesses,
    sum(known_duration_illnesses)::bigint as known_duration_illnesses,
    sum(days_lost)::numeric as days_lost
  from analysis.urc_illness_team_profiles_v1
  group by season, illness_code, illness_label
)
select grouped.*, 'all'::text as setting, exposure.exposure_hours,
  grouped.recorded_illnesses * 1000 / nullif(exposure.exposure_hours, 0)
    as incidence_per_1000h,
  grouped.days_lost * 1000 / nullif(exposure.exposure_hours, 0)
    as burden_per_1000h,
  grouped.days_lost / nullif(grouped.known_duration_illnesses, 0)
    as mean_severity_days
from grouped
join analysis.urc_diagnosis_family_league_exposure_v1 exposure
  on exposure.season = grouped.season and exposure.setting_code = 'all';

revoke all on analysis.urc_diagnosis_family_team_exposure_v1,
  analysis.urc_diagnosis_family_team_subtypes_v1,
  analysis.urc_diagnosis_family_team_families_v1,
  analysis.urc_diagnosis_family_league_exposure_v1,
  analysis.urc_diagnosis_family_league_subtypes_v1,
  analysis.urc_diagnosis_family_league_families_v1,
  analysis.urc_illness_profile_rows_v1,
  analysis.urc_illness_team_profiles_v1,
  analysis.urc_illness_league_profiles_v1
from public, anon, authenticated, web_reader;

create function reporting.diagnosis_family_rows_json_v1(
  target_season text,
  target_team text default null
)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, analysis as $$
declare result jsonb;
begin
  if target_team is null then
    with subtypes as materialized (
      select * from analysis.urc_diagnosis_family_league_subtypes_v1
      where season = target_season
    ), subtype_json as (
      select season, setting_code, family_code,
        jsonb_agg(jsonb_build_object(
          'code', subtype_code, 'label', subtype_label,
          'recorded_injuries', recorded_injuries,
          'time_loss_injuries', time_loss_injuries,
          'known_duration_time_loss_injuries',
            known_duration_time_loss_injuries,
          'days_lost', days_lost
        ) order by recorded_injuries desc, subtype_label, subtype_code) as rows
      from subtypes
      group by season, setting_code, family_code
    ), family_counts as (
      select season, setting_code, family_code, family_label,
        sum(recorded_injuries)::bigint as recorded_injuries,
        sum(time_loss_injuries)::bigint as time_loss_injuries,
        sum(known_duration_time_loss_injuries)::bigint
          as known_duration_time_loss_injuries,
        sum(days_lost)::numeric as days_lost
      from subtypes
      group by season, setting_code, family_code, family_label
    ), families as materialized (
      select family_counts.*, exposure.exposure_hours,
        family_counts.time_loss_injuries * 1000 /
          nullif(exposure.exposure_hours, 0) as incidence_per_1000h,
        family_counts.days_lost * 1000 /
          nullif(exposure.exposure_hours, 0) as burden_per_1000h,
        family_counts.days_lost /
          nullif(family_counts.known_duration_time_loss_injuries, 0)
          as mean_severity_days
      from family_counts
      join analysis.urc_diagnosis_family_league_exposure_v1 exposure
        using (season, setting_code)
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'code', families.family_code, 'label', families.family_label,
      'setting', families.setting_code,
      'recorded_injuries', families.recorded_injuries,
      'time_loss_injuries', families.time_loss_injuries,
      'known_duration_time_loss_injuries',
        families.known_duration_time_loss_injuries,
      'days_lost', families.days_lost,
      'exposure_hours', families.exposure_hours,
      'incidence_per_1000h', families.incidence_per_1000h,
      'burden_per_1000h', families.burden_per_1000h,
      'mean_severity_days', families.mean_severity_days,
      'subtypes', subtype_json.rows
    ) order by array_position(array['all','match','training','unknown'],
      families.setting_code), families.recorded_injuries desc,
      families.family_label, families.family_code), '[]'::jsonb)
    into result
    from families
    join subtype_json using (season, setting_code, family_code);
  else
    with subtypes as materialized (
      select * from analysis.urc_diagnosis_family_team_subtypes_v1
      where season = target_season and team_key = target_team
    ), subtype_json as (
      select season, team_key, setting_code, family_code,
        jsonb_agg(jsonb_build_object(
          'code', subtype_code, 'label', subtype_label,
          'recorded_injuries', recorded_injuries,
          'time_loss_injuries', time_loss_injuries,
          'known_duration_time_loss_injuries',
            known_duration_time_loss_injuries,
          'days_lost', days_lost
        ) order by recorded_injuries desc, subtype_label, subtype_code) as rows
      from subtypes
      group by season, team_key, setting_code, family_code
    ), family_counts as (
      select season, team_key, setting_code, family_code, family_label,
        sum(recorded_injuries)::bigint as recorded_injuries,
        sum(time_loss_injuries)::bigint as time_loss_injuries,
        sum(known_duration_time_loss_injuries)::bigint
          as known_duration_time_loss_injuries,
        sum(days_lost)::numeric as days_lost
      from subtypes
      group by season, team_key, setting_code, family_code, family_label
    ), families as materialized (
      select family_counts.*, exposure.exposure_hours,
        family_counts.time_loss_injuries * 1000 /
          nullif(exposure.exposure_hours, 0) as incidence_per_1000h,
        family_counts.days_lost * 1000 /
          nullif(exposure.exposure_hours, 0) as burden_per_1000h,
        family_counts.days_lost /
          nullif(family_counts.known_duration_time_loss_injuries, 0)
          as mean_severity_days
      from family_counts
      join analysis.urc_diagnosis_family_team_exposure_v1 exposure
        using (season, team_key, setting_code)
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'code', families.family_code, 'label', families.family_label,
      'setting', families.setting_code,
      'recorded_injuries', families.recorded_injuries,
      'time_loss_injuries', families.time_loss_injuries,
      'known_duration_time_loss_injuries',
        families.known_duration_time_loss_injuries,
      'days_lost', families.days_lost,
      'exposure_hours', families.exposure_hours,
      'incidence_per_1000h', families.incidence_per_1000h,
      'burden_per_1000h', families.burden_per_1000h,
      'mean_severity_days', families.mean_severity_days,
      'subtypes', subtype_json.rows
    ) order by array_position(array['all','match','training','unknown'],
      families.setting_code), families.recorded_injuries desc,
      families.family_label, families.family_code), '[]'::jsonb)
    into result
    from families
    join subtype_json using (season, team_key, setting_code, family_code);
  end if;
  return result;
end;
$$;

create function reporting.illness_profile_rows_json_v1(
  target_season text,
  target_team text default null
)
returns jsonb language sql stable security definer
set search_path = pg_catalog, analysis, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', illness_code, 'label', illness_label, 'setting', setting,
    'recorded_illnesses', recorded_illnesses,
    'known_duration_illnesses', known_duration_illnesses,
    'days_lost', days_lost, 'exposure_hours', exposure_hours,
    'incidence_per_1000h', incidence_per_1000h,
    'burden_per_1000h', burden_per_1000h,
    'mean_severity_days', mean_severity_days
  ) order by recorded_illnesses desc, illness_label, illness_code), '[]'::jsonb)
  from (
    select illness_code, illness_label, setting, recorded_illnesses,
      known_duration_illnesses, days_lost, exposure_hours,
      incidence_per_1000h, burden_per_1000h, mean_severity_days
    from analysis.urc_illness_league_profiles_v1
    where target_team is null and season = target_season
    union all
    select illness_code, illness_label, setting, recorded_illnesses,
      known_duration_illnesses, days_lost, exposure_hours,
      incidence_per_1000h, burden_per_1000h, mean_severity_days
    from analysis.urc_illness_team_profiles_v1
    where target_team is not null and season = target_season
      and team_key = target_team
  ) rows;
$$;

create function reporting.illness_summary_json_v1(
  target_season text,
  target_team text default null
)
returns jsonb language sql stable security definer
set search_path = pg_catalog, analysis, pg_temp as $$
  with exposure as (
    select exposure_hours
    from analysis.urc_diagnosis_family_league_exposure_v1
    where target_team is null and season = target_season and setting_code = 'all'
    union all
    select exposure_hours
    from analysis.urc_diagnosis_family_team_exposure_v1
    where target_team is not null and season = target_season
      and team_key = target_team and setting_code = 'all'
  ), totals as (
    select coalesce(sum(recorded_illnesses), 0)::bigint as recorded_illnesses,
      coalesce(sum(known_duration_illnesses), 0)::bigint
        as known_duration_illnesses,
      coalesce(sum(days_lost), 0)::numeric as days_lost
    from (
      select recorded_illnesses, known_duration_illnesses, days_lost
      from analysis.urc_illness_league_profiles_v1
      where target_team is null and season = target_season
      union all
      select recorded_illnesses, known_duration_illnesses, days_lost
      from analysis.urc_illness_team_profiles_v1
      where target_team is not null and season = target_season
        and team_key = target_team
    ) rows
  )
  select jsonb_build_object(
    'setting', 'all', 'recorded_illnesses', totals.recorded_illnesses,
    'known_duration_illnesses', totals.known_duration_illnesses,
    'days_lost', totals.days_lost, 'exposure_hours', exposure.exposure_hours,
    'incidence_per_1000h', totals.recorded_illnesses * 1000 /
      nullif(exposure.exposure_hours, 0),
    'burden_per_1000h', totals.days_lost * 1000 /
      nullif(exposure.exposure_hours, 0),
    'mean_severity_days', totals.days_lost /
      nullif(totals.known_duration_illnesses, 0),
    'qualification', 'Overall illness metrics use approved included illness rows and released total player-hours. Illness is not attributed to Match or Training.'
  )
  from totals cross join exposure;
$$;

create function reporting.diagnosis_family_profiles_json_v1(families jsonb)
returns jsonb language sql immutable strict
set search_path = pg_catalog, pg_temp as $$
  select coalesce(jsonb_agg((family - 'subtypes') || jsonb_build_object(
    'dimension', 'diagnosis'
  ) order by array_position(array['all','match','training','unknown'], family ->> 'setting'),
    (family ->> 'recorded_injuries')::numeric desc,
    family ->> 'label', family ->> 'code'), '[]'::jsonb)
  from jsonb_array_elements(families) family;
$$;

create function reporting.replace_diagnosis_profiles_v1(
  profiles jsonb,
  families jsonb
)
returns jsonb language sql immutable strict
set search_path = pg_catalog, reporting, pg_temp as $$
  select coalesce(jsonb_agg(item order by source_order, item_order), '[]'::jsonb)
  from (
    select item, 1 as source_order, ordinality as item_order
    from jsonb_array_elements(profiles) with ordinality source(item, ordinality)
    where item ->> 'dimension' <> 'diagnosis'
    union all
    select item, 2, ordinality
    from jsonb_array_elements(
      reporting.diagnosis_family_profiles_json_v1(families)
    ) with ordinality source(item, ordinality)
  ) rows;
$$;

create view analysis.urc_2025_26_setting_severity_v1
with (security_invoker = true) as
with expanded as (
  select injury.team_key, setting.setting_code, injury.severity_code,
    injury.is_time_loss, injury.days_lost
  from analysis.urc_2025_26_canonical_injury_rows_v1 injury
  cross join lateral (
    select 'all'::text as setting_code
    union all select injury.setting_code
      where injury.setting_code in ('match', 'training')
  ) setting
)
select team_key, setting_code, severity_code,
  case severity_code
    when 'zero_days_medical_attention_only' then 'Medical attention'
    when 'one_day' then '1 day'
    when 'two_to_three_days' then '2-3 days'
    when 'four_to_seven_days' then '4-7 days'
    when 'eight_to_twenty_eight_days' then '8-28 days'
    when 'greater_than_twenty_eight_days' then '>28 days'
    else 'Unknown or censored'
  end as severity_label,
  count(*)::bigint as recorded_injuries,
  count(*) filter (where is_time_loss)::bigint as time_loss_injuries,
  coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days_lost
from expanded
group by team_key, setting_code, severity_code;

create function reporting.urc_2025_26_setting_severity_json_v1(target_team text default null)
returns jsonb language sql stable security definer
set search_path = pg_catalog, analysis, pg_temp as $$
  with rows as (
    select setting_code, severity_code, severity_label,
      sum(recorded_injuries)::bigint as recorded_injuries,
      sum(time_loss_injuries)::bigint as time_loss_injuries,
      sum(days_lost)::numeric as days_lost
    from analysis.urc_2025_26_setting_severity_v1
    where target_team is null or team_key = target_team
    group by setting_code, severity_code, severity_label
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', severity_code, 'label', severity_label, 'setting', setting_code,
    'recorded_injuries', recorded_injuries,
    'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost
  ) order by array_position(array['all','match','training','unknown'], setting_code),
    array_position(array['zero_days_medical_attention_only','one_day',
      'two_to_three_days','four_to_seven_days','eight_to_twenty_eight_days',
      'greater_than_twenty_eight_days','unknown_or_censored'], severity_code)), '[]'::jsonb)
  from rows;
$$;

create function reporting.urc_canonical_injury_sections_json_v1(
  target_season text,
  target_team text default null
)
returns jsonb language sql stable security definer
set search_path = pg_catalog, analysis, reporting, pg_temp as $$
  with payload as (
    select dashboard
    from reporting.diagnosis_family_base_league_payloads_v1
    where target_team is null and season = target_season
    union all
    select dashboard
    from reporting.diagnosis_family_base_team_payloads_v1
    where target_team is not null and season = target_season
      and team_key = target_team
  ), rows as materialized (
    select * from analysis.urc_canonical_injury_rows_v1 injury
    where injury.season = target_season
      and (target_team is null or injury.team_key = target_team)
  ), coverage as (
    select (dashboard #>> '{coverage,hours}')::numeric as all_hours,
      (dashboard #>> '{coverage,match_hours}')::numeric as match_hours,
      (dashboard #>> '{coverage,training_hours}')::numeric as training_hours
    from payload
  ), summary as (
    select count(*)::bigint as recorded_injuries,
      count(*) filter (where is_time_loss)::bigint as time_loss_injuries,
      count(*) filter (where is_time_loss and days_lost is not null)::bigint
        as known_duration_time_loss_injuries,
      coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days_lost,
      percentile_cont(0.5) within group (order by days_lost)
        filter (where is_time_loss and days_lost is not null) as median_severity_days
    from rows
  ), monthly_source as (
    select month, to_date(month ->> 'month', 'Mon YYYY') as month_start
    from payload cross join lateral jsonb_array_elements(dashboard -> 'monthly') month
  ), monthly_injuries as (
    select date_trunc('month', injury_date)::date as month_start,
      count(*)::bigint as recorded_injuries,
      count(*) filter (where is_time_loss)::bigint as time_loss_injuries,
      coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days_lost
    from rows where injury_date is not null
    group by date_trunc('month', injury_date)
  ), settings as (
    select domain.setting_code,
      count(rows.*) filter (
        where domain.setting_code = 'all' or rows.setting_code = domain.setting_code
      )::bigint as recorded_injuries,
      count(rows.*) filter (where rows.is_time_loss and (
        domain.setting_code = 'all' or rows.setting_code = domain.setting_code
      ))::bigint as time_loss_injuries,
      count(rows.*) filter (where rows.is_time_loss and rows.days_lost is not null
        and (domain.setting_code = 'all' or rows.setting_code = domain.setting_code)
      )::bigint as known_duration_time_loss_injuries,
      coalesce(sum(rows.days_lost) filter (where rows.is_time_loss and (
        domain.setting_code = 'all' or rows.setting_code = domain.setting_code
      )), 0)::numeric as days_lost
    from (values ('all'::text), ('match'::text), ('training'::text),
      ('unknown'::text)) domain(setting_code)
    left join rows on true
    group by domain.setting_code
  ), profiles as (
    select setting.setting_code, dimension.dimension, dimension.code,
      dimension.label, count(*)::bigint as recorded_injuries,
      count(*) filter (where injury.is_time_loss)::bigint as time_loss_injuries,
      count(*) filter (where injury.is_time_loss and injury.days_lost is not null)::bigint
        as known_duration_time_loss_injuries,
      coalesce(sum(injury.days_lost) filter (where injury.is_time_loss), 0)::numeric
        as days_lost
    from rows injury
    cross join lateral (
      select 'all'::text as setting_code union all select injury.setting_code
    ) setting
    cross join lateral (values
      ('body_location'::text, injury.body_location_code, injury.body_location_label),
      ('injury_type'::text, injury.injury_type_code, injury.injury_type_label)
    ) dimension(dimension, code, label)
    group by setting.setting_code, dimension.dimension, dimension.code,
      dimension.label
  ), severity as (
    select setting.setting_code, band.severity_code,
      count(rows.*) filter (where rows.severity_code = band.severity_code)::bigint
        as recorded_injuries,
      count(rows.*) filter (where rows.severity_code = band.severity_code
        and rows.is_time_loss)::bigint as time_loss_injuries,
      coalesce(sum(rows.days_lost) filter (where rows.severity_code = band.severity_code
        and rows.is_time_loss), 0)::numeric as days_lost
    from (values ('all'::text), ('match'::text), ('training'::text))
      setting(setting_code)
    cross join (values ('zero_days_medical_attention_only'::text),
      ('one_day'::text), ('two_to_three_days'::text),
      ('four_to_seven_days'::text), ('eight_to_twenty_eight_days'::text),
      ('greater_than_twenty_eight_days'::text), ('unknown_or_censored'::text))
      band(severity_code)
    left join rows on (setting.setting_code = 'all'
      or rows.setting_code = setting.setting_code)
    group by setting.setting_code, band.severity_code
  ), contact as (
    select setting.setting_code, context.contact_context, context.contact_label,
      count(rows.*) filter (where rows.contact_context = context.contact_context)::bigint
        as recorded_injuries,
      count(rows.*) filter (where rows.contact_context = context.contact_context
        and rows.is_time_loss)::bigint as time_loss_injuries
    from (values ('all'::text), ('match'::text), ('training'::text),
      ('unknown'::text)) setting(setting_code)
    cross join (values ('contact'::text, 'Contact'::text),
      ('non_contact'::text, 'Non-contact'::text),
      ('unknown'::text, 'Unknown'::text))
      context(contact_context, contact_label)
    left join rows on (setting.setting_code = 'all'
      or rows.setting_code = setting.setting_code)
    group by setting.setting_code, context.contact_context, context.contact_label
  ), profile_json as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'dimension', dimension, 'code', code, 'label', label,
      'setting', setting_code, 'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
      'exposure_hours', case setting_code when 'all' then coverage.all_hours
        when 'match' then coverage.match_hours
        when 'training' then coverage.training_hours end,
      'incidence_per_1000h', time_loss_injuries * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'burden_per_1000h', days_lost * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'mean_severity_days', days_lost /
        nullif(known_duration_time_loss_injuries, 0)
    ) order by dimension, setting_code, code), '[]'::jsonb) as rows
    from profiles cross join coverage
  )
  select jsonb_build_object(
    'method', jsonb_build_array(
      'Recorded injuries use approved canonically injury-coded lineage rows.',
      'Time-loss status uses final classification. Days lost use known duration only.'
    ),
    'headline', jsonb_build_array(
      jsonb_build_object('key', 'recorded_injuries', 'label', 'Recorded injuries',
        'value', summary.recorded_injuries, 'unit', 'injuries',
        'formula', 'count(canonical Problem type = Injury rows, including undated)'),
      jsonb_build_object('key', 'time_loss_injuries', 'label', 'Time-loss injuries',
        'value', summary.time_loss_injuries, 'unit', 'injuries',
        'formula', 'count(canonical injury final classification = Time Loss)'),
      jsonb_build_object('key', 'overall_incidence_per_1000h',
        'label', 'Overall incidence',
        'value', summary.recorded_injuries * 1000 / nullif(coverage.all_hours, 0),
        'unit', 'per 1,000 player-hours', 'numerator', summary.recorded_injuries,
        'denominator', coverage.all_hours,
        'formula', 'canonical recorded injuries / released exposure hours * 1000'),
      jsonb_build_object('key', 'incidence_per_1000h', 'label', 'Incidence',
        'value', summary.time_loss_injuries * 1000 / nullif(coverage.all_hours, 0),
        'unit', 'per 1,000 player-hours', 'numerator', summary.time_loss_injuries,
        'denominator', coverage.all_hours,
        'formula', 'canonical Time Loss injuries / released exposure hours * 1000'),
      jsonb_build_object('key', 'severity_mean_days', 'label', 'Mean severity',
        'value', summary.days_lost /
          nullif(summary.known_duration_time_loss_injuries, 0),
        'unit', 'days lost per injury', 'numerator', summary.days_lost,
        'denominator', summary.known_duration_time_loss_injuries,
        'formula', 'known-duration Time Loss days / known-duration Time Loss injuries'),
      jsonb_build_object('key', 'severity_median_days', 'label', 'Median severity',
        'value', summary.median_severity_days, 'unit', 'days lost per injury',
        'denominator', summary.known_duration_time_loss_injuries,
        'formula', 'median known-duration Time Loss days'),
      jsonb_build_object('key', 'burden_per_1000h', 'label', 'Burden',
        'value', summary.days_lost * 1000 / nullif(coverage.all_hours, 0),
        'unit', 'days lost per 1,000 player-hours', 'numerator', summary.days_lost,
        'denominator', coverage.all_hours,
        'formula', 'known-duration Time Loss days / released exposure hours * 1000')
    ),
    'monthly', (select coalesce(jsonb_agg((monthly_source.month -
      array['recorded_injuries','time_loss_injuries','days_lost',
        'overall_incidence_per_1000h','incidence_per_1000h','burden_per_1000h'])
      || jsonb_build_object(
        'recorded_injuries', coalesce(monthly_injuries.recorded_injuries, 0),
        'time_loss_injuries', coalesce(monthly_injuries.time_loss_injuries, 0),
        'days_lost', coalesce(monthly_injuries.days_lost, 0),
        'overall_incidence_per_1000h',
          coalesce(monthly_injuries.recorded_injuries, 0) * 1000 /
            nullif((monthly_source.month ->> 'exposure_hours')::numeric, 0),
        'incidence_per_1000h',
          coalesce(monthly_injuries.time_loss_injuries, 0) * 1000 /
            nullif((monthly_source.month ->> 'exposure_hours')::numeric, 0),
        'burden_per_1000h', coalesce(monthly_injuries.days_lost, 0) * 1000 /
          nullif((monthly_source.month ->> 'exposure_hours')::numeric, 0)
      ) order by monthly_source.month_start), '[]'::jsonb)
      from monthly_source left join monthly_injuries using (month_start)),
    'body_locations', (select coalesce(jsonb_agg(jsonb_build_object(
      'key', code, 'label', label, 'time_loss_injuries', time_loss_injuries,
      'days_lost', days_lost, 'exposure_hours', coverage.all_hours,
      'incidence_per_1000h', time_loss_injuries * 1000 /
        nullif(coverage.all_hours, 0),
      'burden_per_1000h', days_lost * 1000 / nullif(coverage.all_hours, 0),
      'mean_severity_days', days_lost /
        nullif(known_duration_time_loss_injuries, 0)
    ) order by code), '[]'::jsonb) from profiles
      where dimension = 'body_location' and setting_code = 'all'),
    'injury_types', (select coalesce(jsonb_agg(jsonb_build_object(
      'key', code, 'label', label, 'time_loss_injuries', time_loss_injuries,
      'days_lost', days_lost, 'exposure_hours', coverage.all_hours,
      'incidence_per_1000h', time_loss_injuries * 1000 /
        nullif(coverage.all_hours, 0),
      'burden_per_1000h', days_lost * 1000 / nullif(coverage.all_hours, 0),
      'mean_severity_days', days_lost /
        nullif(known_duration_time_loss_injuries, 0)
    ) order by time_loss_injuries desc, code), '[]'::jsonb) from profiles
      where dimension = 'injury_type' and setting_code = 'all'),
    'injury_profiles', profile_json.rows,
    'injury_type_families', analysis.injury_type_families_from_payload_v3(
      profile_json.rows
    ),
    'severity_distribution', (select coalesce(jsonb_agg(jsonb_build_object(
      'setting', setting_code, 'key', severity_code,
      'label', case severity_code
        when 'zero_days_medical_attention_only' then 'Medical attention'
        when 'one_day' then '1 day' when 'two_to_three_days' then '2-3 days'
        when 'four_to_seven_days' then '4-7 days'
        when 'eight_to_twenty_eight_days' then '8-28 days'
        when 'greater_than_twenty_eight_days' then '>28 days'
        else 'Unknown or censored' end,
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost
    ) order by array_position(array['all','match','training'], setting_code),
      array_position(array['zero_days_medical_attention_only','one_day',
        'two_to_three_days','four_to_seven_days','eight_to_twenty_eight_days',
        'greater_than_twenty_eight_days','unknown_or_censored'], severity_code)
    ), '[]'::jsonb) from severity),
    'setting_split', (select coalesce(jsonb_agg(jsonb_build_object(
      'key', setting_code, 'label', initcap(setting_code),
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
      'exposure_hours', case setting_code when 'all' then coverage.all_hours
        when 'match' then coverage.match_hours
        when 'training' then coverage.training_hours end,
      'overall_incidence_per_1000h', recorded_injuries * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'incidence_per_1000h', time_loss_injuries * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'burden_per_1000h', days_lost * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'mean_severity_days', days_lost /
        nullif(known_duration_time_loss_injuries, 0)
    ) order by array_position(array['all','match','training','unknown'], setting_code)),
      '[]'::jsonb) from settings),
    'setting_metrics', (select coalesce(jsonb_agg(jsonb_build_object(
      'setting', setting_code, 'label', initcap(setting_code),
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
      'exposure_hours', case setting_code when 'all' then coverage.all_hours
        when 'match' then coverage.match_hours
        when 'training' then coverage.training_hours end,
      'overall_incidence_per_1000h', recorded_injuries * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'incidence_per_1000h', time_loss_injuries * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'burden_per_1000h', days_lost * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'mean_severity_days', days_lost /
        nullif(known_duration_time_loss_injuries, 0)
    ) order by array_position(array['all','match','training','unknown'], setting_code)),
      '[]'::jsonb) from settings),
    'contact_distribution', (select coalesce(jsonb_agg(jsonb_build_object(
      'key', contact_context, 'label', contact_label, 'setting', setting_code,
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries
    ) order by array_position(array['all','match','training','unknown'], setting_code),
      array_position(array['contact','non_contact','unknown'], contact_context)),
      '[]'::jsonb) from contact)
  )
  from summary cross join coverage cross join profile_json;
$$;

create view analysis.urc_2025_26_preliminary_monthly_rates_v1
with (security_invoker = true) as
with months as (
  select payload.team_key, to_date(month ->> 'month', 'Mon YYYY') as month_start,
    (month ->> 'exposure_hours')::numeric as exposure_hours
  from reporting.diagnosis_family_base_team_payloads_v1 payload
  cross join lateral jsonb_array_elements(payload.dashboard -> 'monthly') month
  where payload.season = '2025-26'
    and (month ->> 'exposure_hours')::numeric > 0
), injuries as (
  select date_trunc('month', injury_date)::date as month_start,
    count(*) filter (where is_time_loss)::bigint as time_loss_injuries,
    coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days_lost
  from analysis.urc_2025_26_canonical_injury_rows_v1
  where injury_date is not null
  group by date_trunc('month', injury_date)
), domain as (
  select value::date as month_start
  from generate_series(date '2025-09-01', date '2026-06-01', interval '1 month') value
), grouped as (
  select domain.month_start, count(months.team_key)::integer as contributor_count,
    sum(months.exposure_hours)::numeric as exposure_hours
  from domain left join months using (month_start)
  group by domain.month_start
)
select grouped.*, coalesce(injuries.time_loss_injuries, 0)::bigint
    as time_loss_injuries,
  coalesce(injuries.days_lost, 0)::numeric as days_lost,
  coalesce(injuries.time_loss_injuries, 0) * 1000 /
    nullif(grouped.exposure_hours, 0)
    as incidence_per_1000h,
  coalesce(injuries.days_lost, 0) * 1000 / nullif(grouped.exposure_hours, 0)
    as burden_per_1000h,
  'Preliminary contributor-aligned rate. Includes only teams with positive source-backed exposure in this month; not the official 16-team rate.'::text
    as qualification
from grouped left join injuries using (month_start);

create function reporting.urc_2025_26_preliminary_monthly_rates_json_v1()
returns jsonb language sql stable security definer
set search_path = pg_catalog, analysis, pg_temp as $$
  select jsonb_agg(jsonb_build_object(
    'month', to_char(month_start, 'YYYY-MM'),
    'contributor_count', contributor_count, 'exposure_hours', exposure_hours,
    'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
    'incidence_per_1000h', incidence_per_1000h,
    'burden_per_1000h', burden_per_1000h, 'qualification', qualification
  ) order by month_start)
  from analysis.urc_2025_26_preliminary_monthly_rates_v1;
$$;

revoke all on analysis.urc_2025_26_setting_severity_v1,
  analysis.urc_2025_26_preliminary_monthly_rates_v1
from public, anon, authenticated, web_reader;

create view reporting.diagnosis_family_team_dashboards_v1
with (security_invoker = true) as
select base.team_key, base.season,
  base.dashboard || jsonb_build_object(
    'injury_profiles', reporting.replace_diagnosis_profiles_v1(
      base.dashboard -> 'injury_profiles', family.rows
    ),
    'diagnosis_families', family.rows,
    'illness_profiles', reporting.illness_profile_rows_json_v1(
      base.season, base.team_key
    ),
    'illness_summary', reporting.illness_summary_json_v1(
      base.season, base.team_key
    ),
    'severity_distribution', case when base.season = '2025-26'
      then reporting.urc_2025_26_setting_severity_json_v1(base.team_key)
      else base.dashboard -> 'severity_distribution' end,
    'preliminary_monthly_rates', null
  ) as dashboard
from reporting.diagnosis_family_base_team_payloads_v1 base
cross join lateral (
  select reporting.diagnosis_family_rows_json_v1(base.season, base.team_key) as rows
) family;

create view reporting.diagnosis_family_league_dashboards_v1
with (security_invoker = true) as
select base.season,
  base.dashboard || jsonb_build_object(
    'injury_profiles', reporting.replace_diagnosis_profiles_v1(
      base.dashboard -> 'injury_profiles', family.rows
    ),
    'diagnosis_families', family.rows,
    'illness_profiles', reporting.illness_profile_rows_json_v1(base.season, null),
    'illness_summary', reporting.illness_summary_json_v1(base.season, null),
    'severity_distribution', case when base.season = '2025-26'
      then reporting.urc_2025_26_setting_severity_json_v1()
      else base.dashboard -> 'severity_distribution' end,
    'preliminary_monthly_rates', case when base.season = '2025-26'
      then reporting.urc_2025_26_preliminary_monthly_rates_json_v1()
      else null end
  ) as dashboard
from reporting.diagnosis_family_base_league_payloads_v1 base
cross join lateral (
  select reporting.diagnosis_family_rows_json_v1(base.season, null) as rows
) family;

revoke all on reporting.diagnosis_family_team_dashboards_v1,
  reporting.diagnosis_family_league_dashboards_v1
from public, anon, authenticated, web_reader;

create view reporting.latest_team_dashboard_v7
with (security_invoker = false, security_barrier = true) as
select team_key, dashboard ->> 'team' as team, season,
  (dashboard ->> 'generated_at')::timestamptz as generated_at,
  dashboard -> 'analysis_window' as analysis_window,
  dashboard -> 'method' as method, dashboard -> 'coverage' as coverage,
  dashboard -> 'headline' as headline,
  dashboard -> 'setting_split' as setting_split,
  dashboard -> 'setting_metrics' as setting_metrics,
  dashboard -> 'monthly' as monthly,
  dashboard -> 'body_locations' as body_locations,
  dashboard -> 'injury_types' as injury_types,
  dashboard -> 'injury_profiles' as injury_profiles,
  dashboard -> 'diagnosis_families' as diagnosis_families,
  dashboard -> 'illness_profiles' as illness_profiles,
  dashboard -> 'illness_summary' as illness_summary,
  dashboard -> 'injury_type_families' as injury_type_families,
  dashboard -> 'severity_distribution' as severity_distribution,
  dashboard -> 'contact_distribution' as contact_distribution,
  dashboard -> 'prior_season' as prior_season,
  dashboard -> 'limitations' as limitations,
  dashboard -> 'preliminary_monthly_rates' as preliminary_monthly_rates
from reporting.diagnosis_family_team_dashboards_v1;

create view reporting.latest_league_dashboard_v7
with (security_invoker = false, security_barrier = true) as
select dashboard ->> 'team' as team, season,
  (dashboard ->> 'generated_at')::timestamptz as generated_at,
  dashboard -> 'analysis_window' as analysis_window,
  dashboard -> 'method' as method, dashboard -> 'coverage' as coverage,
  dashboard -> 'headline' as headline,
  dashboard -> 'setting_split' as setting_split,
  dashboard -> 'setting_metrics' as setting_metrics,
  dashboard -> 'monthly' as monthly,
  dashboard -> 'body_locations' as body_locations,
  dashboard -> 'injury_types' as injury_types,
  dashboard -> 'injury_profiles' as injury_profiles,
  dashboard -> 'diagnosis_families' as diagnosis_families,
  dashboard -> 'illness_profiles' as illness_profiles,
  dashboard -> 'illness_summary' as illness_summary,
  dashboard -> 'injury_type_families' as injury_type_families,
  dashboard -> 'severity_distribution' as severity_distribution,
  dashboard -> 'contact_distribution' as contact_distribution,
  dashboard -> 'prior_season' as prior_season,
  dashboard -> 'limitations' as limitations,
  dashboard -> 'preliminary_monthly_rates' as preliminary_monthly_rates
from reporting.diagnosis_family_league_dashboards_v1;

create function reporting.season_comparison_top_diagnoses_v5(
  dashboard jsonb,
  setting_name text
)
returns jsonb language sql immutable strict
set search_path = pg_catalog, pg_temp as $$
  with ranked as (
    select row_number() over (
      order by (family ->> 'time_loss_injuries')::numeric desc,
        (family ->> 'burden_per_1000h')::numeric desc nulls last,
        family ->> 'label', family ->> 'code'
    ) as rank, family
    from jsonb_array_elements(dashboard -> 'diagnosis_families') family
    where family ->> 'setting' = setting_name
      and (family ->> 'time_loss_injuries')::numeric > 0
      and lower(family ->> 'code') !~ '(^|__)unknown(_|__|$)'
      and lower(family ->> 'label') !~ '(^|[[:space:]·/])unknown($|[[:space:]/])'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'rank', rank, 'diagnosis', family ->> 'label',
    'time_loss_injuries', (family ->> 'time_loss_injuries')::numeric,
    'incidence_per_1000h', (family ->> 'incidence_per_1000h')::numeric,
    'burden_per_1000h', (family ->> 'burden_per_1000h')::numeric
  ) order by rank), '[]'::jsonb)
  from ranked where rank <= 3;
$$;

create function reporting.build_season_comparison_v5(
  previous_dashboard jsonb,
  current_dashboard jsonb,
  comparison_scope text
)
returns jsonb language plpgsql stable strict security definer
set search_path = pg_catalog, pg_temp as $$
declare comparison jsonb; diagnoses jsonb;
begin
  comparison := reporting.season_comparison_presentation_v2(
    reporting.build_season_comparison_v1(
      previous_dashboard, current_dashboard, comparison_scope
    )
  );
  with settings(ordinal, setting, label) as (values
    (1, 'all', 'Overall'), (2, 'match', 'Match'), (3, 'training', 'Training')
  )
  select jsonb_agg(jsonb_build_object(
    'setting', setting, 'label', label,
    'previous', reporting.season_comparison_top_diagnoses_v5(
      previous_dashboard, setting
    ),
    'current', reporting.season_comparison_top_diagnoses_v5(
      current_dashboard, setting
    )
  ) order by ordinal) into diagnoses from settings;
  return jsonb_set(jsonb_set(comparison, '{rule_version}',
    to_jsonb('season_comparison_reporting_2026_09_01_v5'::text), false),
    '{diagnoses}', diagnoses, false);
end;
$$;

create view reporting.latest_team_season_comparison_v5
with (security_invoker = false, security_barrier = true) as
select previous.team_key, reporting.build_season_comparison_v5(
  to_jsonb(previous) - 'team_key', to_jsonb(current) - 'team_key', 'team'
) as comparison
from reporting.latest_team_dashboard_v7 previous
join reporting.latest_team_dashboard_v7 current using (team_key)
where previous.season = '2024-25' and current.season = '2025-26'
  and jsonb_array_length(previous.diagnosis_families) > 0
  and jsonb_array_length(current.diagnosis_families) > 0;

create view reporting.latest_league_season_comparison_v5
with (security_invoker = false, security_barrier = true) as
select reporting.build_season_comparison_v5(
  to_jsonb(previous), to_jsonb(current), 'league'
) as comparison
from reporting.latest_league_dashboard_v7 previous
cross join reporting.latest_league_dashboard_v7 current
where previous.season = '2024-25' and current.season = '2025-26'
  and jsonb_array_length(previous.diagnosis_families) > 0
  and jsonb_array_length(current.diagnosis_families) > 0;

create view reporting.approved_dashboard_reader_target_v7
with (security_invoker = false, security_barrier = true) as
select target_attested
  and to_regclass('reporting.latest_team_dashboard_v7') is not null
  and to_regclass('reporting.latest_league_dashboard_v7') is not null
  and to_regclass('reporting.latest_team_season_comparison_v5') is not null
  and to_regclass('reporting.latest_league_season_comparison_v5') is not null
  and (select count(*) from reporting.diagnosis_family_release_bindings_v1) = 2
  as target_attested
from reporting.approved_dashboard_reader_target_v6;

create function analysis.assert_urc_diagnosis_family_reporting_v1()
returns void language plpgsql
set search_path = pg_catalog, analysis, reporting, audit as $$
begin
  if (select count(*) from audit.urc_2024_25_diagnosis_family_source_rows_v1) <> 1660
    or (select count(*) from audit.urc_2024_25_illness_profile_source_rows_v1) <> 392
    or (select count(*) from audit.urc_2025_26_diagnosis_family_exact_labels_v1) <> 420
    or (select count(*) from audit.urc_2025_26_illness_exact_labels_v1) <> 113
    or (select count(distinct (illness_code, illness_label))
        from audit.urc_2025_26_illness_exact_labels_v1) <> 50
    or (select count(*) from reporting.diagnosis_family_base_team_payloads_v1) <> 32
    or (select count(*) from reporting.diagnosis_family_base_league_payloads_v1) <> 2
    or (select count(*) from reporting.latest_team_dashboard_v7) <> 32
    or (select count(*) from reporting.latest_league_dashboard_v7) <> 2
    or (select count(*) from reporting.latest_team_season_comparison_v5) <> 16
    or (select count(*) from reporting.latest_league_season_comparison_v5) <> 1
  then raise exception 'Diagnosis-family reporting cardinality failed'; end if;

  if (select count(*) from analysis.urc_diagnosis_family_rows_v1
      where season = '2024-25') <> 1662
    or (select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1) <> 1545
    or (select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1
        where is_time_loss) <> 938
    or (select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1
        where is_time_loss and days_lost is not null) <> 782
    or (select coalesce(sum(days_lost), 0)
        from analysis.urc_2025_26_canonical_injury_rows_v1
        where is_time_loss) <> 20665
    or (select count(*) from analysis.urc_diagnosis_family_rows_v1
        where season = '2025-26') <> 1545
    or (select count(*) from analysis.urc_illness_profile_rows_v1
        where season = '2024-25') <> 392
    or (select count(*) from analysis.urc_illness_profile_rows_v1
        where season = '2025-26') <> 439
    or (select count(*) from analysis.urc_illness_profile_rows_v1
        where season = '2025-26' and duration_known) <> 202
    or (select coalesce(sum(days_lost), 0)
        from analysis.urc_illness_profile_rows_v1
        where season = '2025-26' and duration_known) <> 927
    or (select count(distinct (illness_code, illness_label))
        from analysis.urc_illness_profile_rows_v1
        where season = '2025-26') <> 50
    or (select count(*)
        from audit.urc_2024_25_diagnosis_family_source_rows_v1 family
        join audit.urc_2024_25_specific_diagnosis_mappings_v1 source_evidence
          on source_evidence.season = '2024-25'
         and source_evidence.source_row = family.source_row
         and source_evidence.source_row_sha256 = family.source_row_sha256) <> 1660
    or (select count(*)
        from analysis.urc_2024_25_final_injury_classification_v1 injury
        join audit.urc_2024_25_diagnosis_family_source_rows_v1 family
          on family.source_row = injury.source_row
        where injury.canonical_problem_type = 'injury') <> 1658
    or (select count(*)
        from analysis.urc_2024_25_final_injury_classification_v1 injury
        left join audit.urc_2024_25_diagnosis_family_source_rows_v1 family
          on family.source_row = injury.source_row
        where injury.canonical_problem_type = 'injury'
          and family.source_row is null) <> 4
    or (select count(*)
        from audit.urc_2024_25_diagnosis_family_source_rows_v1 family
        left join analysis.urc_2024_25_final_injury_classification_v1 injury
          on injury.source_row = family.source_row
         and injury.canonical_problem_type = 'injury'
        where injury.source_row is null) <> 2
    or (select count(*) from analysis.urc_diagnosis_family_rows_v1
        where season = '2024-25' and family_code = 'unknown') <> 4
    or exists (
      select season, family_code
      from analysis.urc_diagnosis_family_rows_v1
      group by season, family_code
      having count(distinct family_label) <> 1
    )
    or (select count(*) from analysis.urc_diagnosis_family_rows_v1
        where season = '2025-26' and family_code <> 'unknown') <> 1464
    or (select count(*) from analysis.urc_diagnosis_family_rows_v1
        where season = '2025-26' and family_code = 'unknown') <> 81
    or (select count(*) from analysis.urc_diagnosis_family_rows_v1
        where season = '2025-26' and family_code = 'unknown'
          and is_time_loss) <> 73
    or (select coalesce(sum(days_lost), 0)
        from analysis.urc_diagnosis_family_rows_v1
        where season = '2025-26' and family_code = 'unknown'
          and is_time_loss) <> 1042
    or (select count(*)
        from analysis.urc_2025_26_canonical_injury_rows_v1 injury
        left join audit.urc_2025_26_diagnosis_family_exact_labels_v1 family
          on family.source_label = injury.diagnosis_label
        where family.family_code is null) <> 19
    or (select count(*)
        from analysis.urc_2025_26_canonical_injury_rows_v1 injury
        left join audit.urc_2025_26_diagnosis_family_exact_labels_v1 family
          on family.source_label = injury.diagnosis_label
        where family.family_code is null and injury.is_time_loss) <> 18
    or (select coalesce(sum(injury.days_lost), 0)
        from analysis.urc_2025_26_canonical_injury_rows_v1 injury
        left join audit.urc_2025_26_diagnosis_family_exact_labels_v1 family
          on family.source_label = injury.diagnosis_label
        where family.family_code is null and injury.is_time_loss) <> 73
    or exists (
      select 1
      from analysis.urc_diagnosis_family_rows_v1 rows
      cross join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
      join lineage.injury_master_rows_v3 master
        on master.version_id = evidence.successor_version_id
       and master.source_row = rows.source_row
      where rows.season = '2025-26'
        and lower(btrim(master.row_values ->> 'Problem type')) <> 'injury'
    )
  then raise exception 'Diagnosis-family row mapping or illness boundary failed'; end if;

  if exists (
    select 1 from reporting.latest_team_dashboard_v7 dashboard
    left join lateral (
      select count(*)::bigint as recorded,
        count(*) filter (where injury_date is not null)::bigint as dated,
        count(*) filter (where is_time_loss)::bigint as time_loss,
        coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days
      from analysis.urc_2025_26_canonical_injury_rows_v1 injury
      where injury.team_key = dashboard.team_key
    ) source on true
    where dashboard.season = '2025-26' and (
      (select (item ->> 'value')::bigint from jsonb_array_elements(dashboard.headline) item
        where item ->> 'key' = 'recorded_injuries') <> source.recorded
      or (select (item ->> 'value')::bigint from jsonb_array_elements(dashboard.headline) item
        where item ->> 'key' = 'time_loss_injuries') <> source.time_loss
      or (select (item ->> 'numerator')::numeric from jsonb_array_elements(dashboard.headline) item
        where item ->> 'key' = 'burden_per_1000h') <> source.days
      or (select (item ->> 'recorded_injuries')::bigint
          from jsonb_array_elements(dashboard.setting_metrics) item
          where item ->> 'setting' = 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.setting_metrics) item
          where item ->> 'setting' <> 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.monthly) item) <> source.dated
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.severity_distribution) item
          where item ->> 'setting' = 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.contact_distribution) item
          where item ->> 'setting' = 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.diagnosis_families) item
          where item ->> 'setting' = 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.diagnosis_families) item
          where item ->> 'setting' <> 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.injury_profiles) item
          where item ->> 'setting' = 'all'
            and item ->> 'dimension' = 'body_location') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.injury_profiles) item
          where item ->> 'setting' = 'all'
            and item ->> 'dimension' = 'injury_type') <> source.recorded
    )
  ) then raise exception '2025-26 team injury sections do not reconcile'; end if;

  if exists (
    select 1 from reporting.latest_team_dashboard_v7 dashboard
    left join lateral (
      select count(*)::bigint as recorded,
        count(*) filter (where date_injured is not null)::bigint as dated,
        count(*) filter (where final_classification = 'Time Loss')::bigint
          as time_loss,
        coalesce(sum(days_lost) filter (where final_classification = 'Time Loss'
          and duration_usable), 0)::numeric as days
      from analysis.urc_2024_25_final_injury_classification_v1 injury
      where injury.team_key = dashboard.team_key
        and injury.canonical_problem_type = 'injury'
    ) source on true
    left join lateral (
      select count(*)::bigint as mapped
      from analysis.urc_diagnosis_family_rows_v1 family
      where family.season = '2024-25' and family.team_key = dashboard.team_key
    ) diagnosis on true
    where dashboard.season = '2024-25' and (
      (select (item ->> 'value')::bigint from jsonb_array_elements(dashboard.headline) item
        where item ->> 'key' = 'recorded_injuries') <> source.recorded
      or (select (item ->> 'value')::bigint from jsonb_array_elements(dashboard.headline) item
        where item ->> 'key' = 'time_loss_injuries') <> source.time_loss
      or (select (item ->> 'numerator')::numeric from jsonb_array_elements(dashboard.headline) item
        where item ->> 'key' = 'burden_per_1000h') <> source.days
      or (select (item ->> 'recorded_injuries')::bigint
          from jsonb_array_elements(dashboard.setting_metrics) item
          where item ->> 'setting' = 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.setting_metrics) item
          where item ->> 'setting' <> 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.monthly) item) <> source.dated
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.contact_distribution) item
          where item ->> 'setting' = 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.diagnosis_families) item
          where item ->> 'setting' = 'all') <> diagnosis.mapped
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.injury_profiles) item
          where item ->> 'setting' = 'all'
            and item ->> 'dimension' = 'body_location') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.injury_profiles) item
          where item ->> 'setting' = 'all'
            and item ->> 'dimension' = 'injury_type') <> source.recorded
    )
  ) then raise exception '2024-25 team injury sections do not reconcile'; end if;

  if not exists (
    select 1 from reporting.latest_league_dashboard_v7 dashboard
    where dashboard.season = '2025-26'
      and (select (item ->> 'value')::bigint
           from jsonb_array_elements(dashboard.headline) item
           where item ->> 'key' = 'recorded_injuries') = 1545
      and (select (item ->> 'recorded_injuries')::bigint
           from jsonb_array_elements(dashboard.setting_metrics) item
           where item ->> 'setting' = 'all') = 1545
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.setting_metrics) item
           where item ->> 'setting' <> 'all') = 1545
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.monthly) item) =
          (select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1
           where injury_date is not null)
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.severity_distribution) item
           where item ->> 'setting' = 'all') = 1545
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.contact_distribution) item
           where item ->> 'setting' = 'all') = 1545
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.diagnosis_families) item
           where item ->> 'setting' = 'all') = 1545
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.diagnosis_families) item
           where item ->> 'setting' <> 'all') = 1545
  ) then raise exception '2025-26 league injury sections do not reconcile to 1545'; end if;

  if not exists (
    select 1 from reporting.latest_league_dashboard_v7 dashboard
    where dashboard.season = '2024-25'
      and (select (item ->> 'value')::bigint
           from jsonb_array_elements(dashboard.headline) item
           where item ->> 'key' = 'recorded_injuries') =
          (select count(*) from analysis.urc_2024_25_final_injury_classification_v1
           where canonical_problem_type = 'injury')
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.severity_distribution) item
           where item ->> 'setting' = 'all') = 1518
      and (select sum((item ->> 'time_loss_injuries')::bigint)
           from jsonb_array_elements(dashboard.severity_distribution) item
           where item ->> 'setting' = 'all') = 787
      and (select sum((item ->> 'days_lost')::numeric)
           from jsonb_array_elements(dashboard.severity_distribution) item
           where item ->> 'setting' = 'all') = 17575
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.diagnosis_families) item
           where item ->> 'setting' = 'all') = 1662
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.monthly) item) =
          (select count(*) from analysis.urc_2024_25_final_injury_classification_v1
           where canonical_problem_type = 'injury' and date_injured is not null)
  ) then raise exception '2024-25 league injury sections do not reconcile'; end if;

  if (select sum(recorded_illnesses) from analysis.urc_illness_league_profiles_v1
      where season = '2024-25') <> 392
    or (select sum(recorded_illnesses) from analysis.urc_illness_league_profiles_v1
        where season = '2025-26') <> 439
    or exists (select 1 from analysis.urc_illness_league_profiles_v1
      where setting <> 'all' or exposure_hours is null
        or incidence_per_1000h is null or burden_per_1000h is null)
    or exists (select 1 from analysis.urc_illness_team_profiles_v1
      where known_duration_illnesses = 0 and mean_severity_days is not null)
  then raise exception 'Illness profile cohort or metric rule failed'; end if;

  if exists (
    select 1 from (
      select season, team_key, illness_profiles, illness_summary
      from reporting.latest_team_dashboard_v7
      union all
      select season, null::text, illness_profiles, illness_summary
      from reporting.latest_league_dashboard_v7
    ) dashboard
    cross join lateral (
      select coalesce(sum((item ->> 'recorded_illnesses')::bigint), 0)::bigint
          as recorded,
        coalesce(sum((item ->> 'known_duration_illnesses')::bigint), 0)::bigint
          as known_duration,
        coalesce(sum((item ->> 'days_lost')::numeric), 0)::numeric as days_lost
      from jsonb_array_elements(dashboard.illness_profiles) item
    ) profile
    where jsonb_typeof(dashboard.illness_profiles) is distinct from 'array'
      or jsonb_typeof(dashboard.illness_summary) is distinct from 'object'
      or dashboard.illness_summary ->> 'setting' <> 'all'
      or dashboard.illness_summary ->> 'qualification' <>
        'Overall illness metrics use approved included illness rows and released total player-hours. Illness is not attributed to Match or Training.'
      or (dashboard.illness_summary ->> 'recorded_illnesses')::bigint <>
        profile.recorded
      or (dashboard.illness_summary ->> 'known_duration_illnesses')::bigint <>
        profile.known_duration
      or (dashboard.illness_summary ->> 'days_lost')::numeric <> profile.days_lost
      or ((dashboard.illness_summary ->> 'mean_severity_days')::numeric
          is distinct from profile.days_lost / nullif(profile.known_duration, 0))
  ) then raise exception 'Illness summary does not reconcile to illness profiles'; end if;

  if exists (
    select 1 from analysis.urc_diagnosis_family_team_families_v1 family
    left join (
      select season, team_key, setting_code, family_code,
        sum(recorded_injuries)::bigint as recorded_injuries,
        sum(time_loss_injuries)::bigint as time_loss_injuries,
        sum(known_duration_time_loss_injuries)::bigint as known_duration,
        sum(days_lost)::numeric as days_lost
      from analysis.urc_diagnosis_family_team_subtypes_v1
      group by season, team_key, setting_code, family_code
    ) subtype using (season, team_key, setting_code, family_code)
    where (family.recorded_injuries, family.time_loss_injuries,
      family.known_duration_time_loss_injuries, family.days_lost)
      is distinct from (subtype.recorded_injuries, subtype.time_loss_injuries,
        subtype.known_duration, subtype.days_lost)
  ) then raise exception 'Diagnosis family does not equal subtype sums'; end if;

  if not exists (
    select 1 from analysis.urc_diagnosis_family_league_families_v1
    where season = '2025-26' and setting_code = 'all'
      and family_label = 'Concussion' and recorded_injuries = 126
      and time_loss_injuries = 124 and days_lost = 1747
  ) or not exists (
    select 1 from analysis.urc_diagnosis_family_league_families_v1
    where season = '2025-26' and setting_code = 'training'
      and family_label = 'Concussion' and recorded_injuries = 17
      and time_loss_injuries = 17 and days_lost = 217
  ) or not exists (
    select 1 from analysis.urc_diagnosis_family_league_families_v1
    where season = '2025-26' and setting_code = 'match'
      and family_label = 'Concussion' and recorded_injuries = 109
      and time_loss_injuries = 107 and days_lost = 1530
  ) or not exists (
    select 1 from analysis.urc_diagnosis_family_league_families_v1
    where season = '2025-26' and setting_code = 'all'
      and family_label = 'Hamstring muscle injury' and recorded_injuries = 82
      and time_loss_injuries = 78 and days_lost = 2323
  ) or not exists (
    select 1 from analysis.urc_diagnosis_family_league_families_v1
    where season = '2024-25' and setting_code = 'all'
      and family_label = 'Concussion' and recorded_injuries = 109
      and time_loss_injuries = 104 and days_lost = 1476
  ) then raise exception 'Pinned diagnosis-family reconciliation failed'; end if;

  if exists (
    select 1 from reporting.diagnosis_family_team_dashboards_v1 successor
    join reporting.diagnosis_family_base_team_payloads_v1 predecessor
      using (team_key, season)
    where successor.dashboard - array['injury_profiles','diagnosis_families',
      'illness_profiles','illness_summary','severity_distribution',
      'preliminary_monthly_rates']
      <> predecessor.dashboard - array['injury_profiles','diagnosis_families',
      'illness_profiles','illness_summary','severity_distribution',
      'preliminary_monthly_rates']
  ) or exists (
    select 1 from reporting.diagnosis_family_league_dashboards_v1 successor
    join reporting.diagnosis_family_base_league_payloads_v1 predecessor using (season)
    where successor.dashboard - array['injury_profiles','diagnosis_families',
      'illness_profiles','illness_summary','severity_distribution',
      'preliminary_monthly_rates']
      <> predecessor.dashboard - array['injury_profiles','diagnosis_families',
      'illness_profiles','illness_summary','severity_distribution',
      'preliminary_monthly_rates']
  ) then raise exception 'Diagnosis-family successor changed a non-presentation field'; end if;

  if exists (
    select 1
    from reporting.diagnosis_family_team_dashboards_v1 successor
    join reporting.diagnosis_family_base_team_payloads_v1 predecessor
      using (team_key, season)
    where (select coalesce(jsonb_agg(item order by ordinality), '[]'::jsonb)
      from jsonb_array_elements(successor.dashboard -> 'injury_profiles')
        with ordinality rows(item, ordinality)
      where item ->> 'dimension' <> 'diagnosis')
      <> (select coalesce(jsonb_agg(item order by ordinality), '[]'::jsonb)
      from jsonb_array_elements(predecessor.dashboard -> 'injury_profiles')
        with ordinality rows(item, ordinality)
      where item ->> 'dimension' <> 'diagnosis')
  ) or exists (
    select 1
    from reporting.diagnosis_family_league_dashboards_v1 successor
    join reporting.diagnosis_family_base_league_payloads_v1 predecessor using (season)
    where (select coalesce(jsonb_agg(item order by ordinality), '[]'::jsonb)
      from jsonb_array_elements(successor.dashboard -> 'injury_profiles')
        with ordinality rows(item, ordinality)
      where item ->> 'dimension' <> 'diagnosis')
      <> (select coalesce(jsonb_agg(item order by ordinality), '[]'::jsonb)
      from jsonb_array_elements(predecessor.dashboard -> 'injury_profiles')
        with ordinality rows(item, ordinality)
      where item ->> 'dimension' <> 'diagnosis')
  ) then raise exception 'Diagnosis replacement changed a non-diagnosis profile row'; end if;

  if exists (
    select 1 from analysis.urc_diagnosis_family_team_families_v1
    where setting_code = 'unknown' and (exposure_hours is not null
      or incidence_per_1000h is not null or burden_per_1000h is not null)
  ) or exists (
    select 1 from analysis.urc_diagnosis_family_team_families_v1
    where known_duration_time_loss_injuries = 0 and mean_severity_days is not null
  ) then raise exception 'Null rate or known-duration severity rule failed'; end if;

  if (select count(*) from analysis.urc_2025_26_preliminary_monthly_rates_v1) <> 10
    or exists (
      select 1 from analysis.urc_2025_26_preliminary_monthly_rates_v1
      where contributor_count < 1 or contributor_count > 16
        or exposure_hours <= 0 or incidence_per_1000h is null
        or burden_per_1000h is null
    )
    or (select count(*) from reporting.approved_dashboard_reader_target_v7
        where target_attested) <> 1
  then raise exception 'Preliminary rates or reader attestation failed'; end if;
end;
$$;

select analysis.assert_urc_diagnosis_family_reporting_v1();

revoke all on function reporting.diagnosis_family_rows_json_v1(text, text),
  reporting.illness_profile_rows_json_v1(text, text),
  reporting.illness_summary_json_v1(text, text),
  reporting.diagnosis_family_profiles_json_v1(jsonb),
  reporting.replace_diagnosis_profiles_v1(jsonb, jsonb),
  reporting.urc_2025_26_setting_severity_json_v1(text),
  reporting.urc_canonical_injury_sections_json_v1(text, text),
  reporting.urc_2025_26_preliminary_monthly_rates_json_v1(),
  reporting.season_comparison_top_diagnoses_v5(jsonb, text),
  reporting.build_season_comparison_v5(jsonb, jsonb, text),
  analysis.assert_urc_diagnosis_family_reporting_v1()
from public, anon, authenticated, web_reader;

revoke all on reporting.latest_team_dashboard_v7,
  reporting.latest_league_dashboard_v7,
  reporting.latest_team_season_comparison_v5,
  reporting.latest_league_season_comparison_v5,
  reporting.approved_dashboard_reader_target_v7
from public, anon, authenticated, web_reader;

grant select on reporting.latest_team_dashboard_v7,
  reporting.latest_league_dashboard_v7,
  reporting.latest_team_season_comparison_v5,
  reporting.latest_league_season_comparison_v5,
  reporting.approved_dashboard_reader_target_v7
to web_reader;
grant execute on function reporting.build_season_comparison_v5(jsonb, jsonb, text)
to web_reader;

commit;
