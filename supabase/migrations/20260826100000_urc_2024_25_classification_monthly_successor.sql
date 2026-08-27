-- Additive 2024-25 classification and monthly reporting successor.
--
-- This migration is season-bound and correction-aware. It creates only new
-- evidence, fact, aggregate, candidate and assertion relations. Existing
-- V5
-- migrations and dashboard payloads remain frozen. Promotion and any live
-- database action are deliberately outside this file.
--
-- Successor tuple:
--   analysis_version: v5
--   classification_view_version:
--     reporting_classification_2024-25_2026-08-27_v1
--   cohort_view_version: analysis_window_2024-25_2026-07-25_v1

create table audit.urc_2024_25_classification_adjudications_v1 (
  season text not null default '2024-25' check (season = '2024-25'),
  source_row integer not null check (source_row > 1),
  source_locator jsonb not null check (jsonb_typeof(source_locator) = 'object'),
  source_locator_fingerprint text not null check (
    source_locator_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  source_row_sha256 text not null check (source_row_sha256 ~ '^[0-9a-f]{64}$'),
  source_value text not null check (source_value in ('', 'FALSE')),
  final_classification text not null check (
    final_classification in ('Time Loss', 'Medical Attention', 'unclassified')
  ),
  classification_origin text not null check (classification_origin = 'adjudicated'),
  reviewer text not null check (reviewer = 'Abdel Babiker'),
  reviewed_at date not null check (reviewed_at = date '2026-08-26'),
  rationale text not null,
  club_follow_up boolean not null,
  second_human_review text not null check (second_human_review = 'pending'),
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  source_identity text generated always as
    ('2024-25:' || source_row::text || ':' || source_row_sha256) stored,
  primary key (season, source_row),
  unique (season, source_locator_fingerprint),
  unique (season, source_identity)
);

alter table audit.urc_2024_25_classification_adjudications_v1 enable row level security;
revoke all on audit.urc_2024_25_classification_adjudications_v1
  from public, anon, authenticated, web_reader;

create function audit.prevent_urc_2024_25_classification_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception '2024-25 classification adjudications are append-only';
end;
$$;

revoke execute on function audit.prevent_urc_2024_25_classification_mutation()
  from public, anon, authenticated, web_reader;

create trigger urc_2024_25_classification_adjudications_immutable
before update or delete
on audit.urc_2024_25_classification_adjudications_v1
for each row execute function audit.prevent_urc_2024_25_classification_mutation();

create table audit.urc_2024_25_specific_diagnosis_mappings_v1 (
  season text not null default '2024-25' check (season = '2024-25'),
  source_row integer not null check (source_row > 1),
  source_row_sha256 text not null check (source_row_sha256 ~ '^[0-9a-f]{64}$'),
  diagnosis_group_code text not null check (length(diagnosis_group_code) > 0),
  diagnosis_group_label text not null check (length(diagnosis_group_label) > 0),
  source_identity text generated always as
    ('2024-25:' || source_row::text || ':' || source_row_sha256) stored,
  primary key (season, source_row),
  unique (season, source_identity)
);

alter table audit.urc_2024_25_specific_diagnosis_mappings_v1 enable row level security;
revoke all on audit.urc_2024_25_specific_diagnosis_mappings_v1
  from public, anon, authenticated, web_reader;

create function audit.prevent_urc_2024_25_specific_diagnosis_mapping_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception '2024-25 specific diagnosis mappings are append-only';
end;
$$;

revoke execute on function audit.prevent_urc_2024_25_specific_diagnosis_mapping_mutation()
  from public, anon, authenticated, web_reader;

create trigger urc_2024_25_specific_diagnosis_mappings_immutable
before update or delete
on audit.urc_2024_25_specific_diagnosis_mappings_v1
for each row execute function audit.prevent_urc_2024_25_specific_diagnosis_mapping_mutation();

insert into audit.urc_2024_25_specific_diagnosis_mappings_v1 (
  source_row, source_row_sha256, diagnosis_group_code, diagnosis_group_label
)
values
  (5, '32837f7fc5e2092cce58e9c4cc5e033df26d0b0c1fb0288f29a94cafeadf4613', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury'),
  (7, 'ba4caf4dc497523a4152e707157ba047fb60e8f8f83980f95e4e742695c36117', 'dx_plantar_fascia_rupture_dbe62f4d0b', 'Plantar fascia rupture'),
  (8, '3bd0717d8ef6a89df3b9186ea949127d0a1e29d694100fef9ea1ff270e0e43cb', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (9, '804810e0e8ad519c54658a499bae6b968409ecf2aa3517de5b37130fac17dcf6', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (10, '44d428f27c992e29b30320509d73502f31683820dfd31eba56a2b0baa34281dd', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (11, 'bb2a5aee74ff05041a61a13dd8b5c183a54fe9713423caae6520c17454a1f1ff', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (12, 'cc5f26bad533bcb5a1cb488ebc029a26eb732fc8ec7579fbf7ecb0057a22e87e', 'dx_neck_sprain_or_whiplash_404e63fe9e', 'Neck sprain or whiplash'),
  (13, '8f1396387829dba1bd16e645ee59860a49e31ed910167b4a80c074720fb1d69f', 'dx_abdominal_muscle_strain_or_spasm_8848453dde', 'Abdominal muscle strain or spasm'),
  (15, 'e22a07ab8d6a2b18819f25f09da5d680003e976b42adee1d6997e1a3b450f44a', 'dx_iliopsoas_muscle_injury_f4c389b8cc', 'Iliopsoas muscle injury'),
  (21, '1bee36323c4d45cfa8d21877a647ee86463a80b777dfb397f101a0263949a793', 'dx_achilles_tendon_rupture_6b59cc3783', 'Achilles tendon rupture'),
  (22, '006de652caf4763df41c360bf744405dc48a640e9046555c28f18d53c969dd90', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (23, '715ea15e1c2ba8cde588e24e90b4e6ce89606548fe1659c7664c6773b6806259', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (24, '2a0a68f2543b46b91a47026cf377f6e36bceb1bd7abc6676cae3339c606c169a', 'dx_biceps_injury_69e895b576', 'Biceps injury'),
  (25, '64677c81cf20ce00fcce834700f763444917decc50dcf6c38265e096b0827e8c', 'dx_biceps_injury_69e895b576', 'Biceps injury'),
  (26, 'd82c3876f44efae35596f4fc003d7e4ca4983de7fd0b16382ce7989c8dc972d0', 'dx_humeral_condyle_fracture_86595a3e03', 'Humeral condyle fracture'),
  (27, '527fcb3e584091073666ec3747bfb245b508999d6f1633a9f047e8d0b0323375', 'dx_plantar_fascia_injury_ec4d3703e9', 'Plantar fascia injury'),
  (29, 'ab3c8e723ea9bec089e952cc87c1afa813c541cf0173a2bb0ffde72717bcc350', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (30, '4e92f6d6743dd0e20aa8bbdb6669da93f52530cfde979868ed60dc60778d5ddd', 'dx_thigh_stump_trauma_1f598a2ab0', 'Thigh stump trauma'),
  (31, '0b213460f9c9638e14e52194b7e23a4e30251e0bb050bbcc471c26d2902e5bf6', 'dx_knee_posterolateral_corner_injury_a4c4c64579', 'Knee posterolateral corner injury'),
  (32, 'cf05e18cf640ef3015d6dc54404de7ca786c21e37610657dc5f952af48c589aa', 'dx_biceps_injury_69e895b576', 'Biceps injury'),
  (35, '8082544483a9563a4ddb2ec11c5ed682ed82b9b23455331b18611e77e8356422', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (36, 'a663a9fc6ea07f7982c1550d7b51d71106dadb91c194335eaef46aa87c99d71e', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (39, '7c3feab7f852f8b1d5345d26ad94989227129c7d578ced21070d276f54e2f57b', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (41, '0f985d50906a1ae5c2f3e4644d060f99f1c3e4d1c1d6118bf901fc0124ceacf4', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (43, '5711188fd930d37b0db3bf4bb4ce5b5acbb950b88d41745d8762f2059cd1d61c', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (44, 'e129d3fb7a3d5ba31f895807d1bf470f58a9cfd11c79b2e2815f9ae7722f168e', 'dx_lateral_malleolus_fracture_83cb1eb192', 'Lateral malleolus fracture'),
  (55, '5e029c8e0782b856fd11bde973b91779af0d01f335dcbe9ed8e273901dda3f8e', 'dx_medial_ankle_ligament_injury_9add2aecee', 'Medial ankle ligament injury'),
  (56, '4f3145c916047443ab2ad96bc613fe47125b02fb85e77415d66a714024358e87', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (57, 'e0b61c476cbc49d9d44e33bec6a1fc9a4cc4ae37eeb68c03787001101f8bca76', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (58, '79f578f203911f2e2125ab553c00c56f9e009fab5570e7e5598803af8dbc2477', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (59, 'ac87fff915744a336a86e9c043149a03e36ffd908bd7d17fa45caebf770a61a0', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (60, 'd45200a57ca3a497605b51bb872260432833505e64f7bd1b48624e63b95adc3f', 'dx_sartorius_injury_3dfafe7e54', 'Sartorius injury'),
  (64, '6c55f2b9517e6158072b6648bedcca88c4f79c15f47a6f10d81f1ab6b5d6427e', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (65, '0d6b2a5046d7ee83d9cc7dd462ce3a64a08ed2fcbce52c401c1dad4d9c43f34e', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (66, '03df3ad54c71e1a50661ceac8da25d73ead78fadec4d0ba3a1ec1ffa98aaf81f', 'dx_thumb_ucl_injury_00b846b6dd', 'Thumb UCL injury'),
  (67, 'e249c144c3145306397ed8707a6e99ef2f9271ceae0d83454cbe63192bc436ca', 'dx_cheek_abrasion_80d9386363', 'Cheek abrasion'),
  (68, 'f816db6c95a04d13af4e0feeacaac7162093a5f3cc39320731b6a25e20cfbe97', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (69, '13f89b00db03cff2fc86694997a2d98957e9f0036afd2bc2fd90b4807f85c72f', 'dx_buttock_contusion_46ae636fd7', 'Buttock contusion'),
  (70, 'eb993a40e4a2aa50a0ae5772036cc8927f7b979d7eed688ae31d696d830b51da', 'dx_knee_pain_609ce718bc', 'Knee pain'),
  (71, 'd364c055245c88e02edcbc46d1e6a7996b945652446f4e9b2ff53dcdd0992542', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (72, 'c65833445d3ae8ac9a60cb0e93b2b0504f85d29004c9afc46831f07497601c3a', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (73, '2d0f5bd09f19bb16e5215d55f55ceb11d02050a9bfa534d006dc560087712204', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (74, 'bba97e4ca8675ea881cfe445db949f0c56df2fe8250b459d7015986c5ee799f4', 'dx_thoracic_facet_joint_disorder_519c2ae5a8', 'Thoracic facet joint disorder'),
  (75, 'c4557eaadae798f56bf7096fa3c229a79f5adc21b3879986f5c39aacb9ef8032', 'dx_concussion_a91e1107d7', 'Concussion'),
  (76, '6050d63bd4e8342dafffbcec9741a65e66e4ed1fa8fedc3a5ea3f09b1051beeb', 'dx_concussion_a91e1107d7', 'Concussion'),
  (77, 'a6e85207408a4ec2753515b8633051046648cfcfe4a5c62a125646bc51d42e8e', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (78, '75e3e23434ac0d20f420eab01e27dab8d17325b30766581bc1ed403596cf8a6f', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury'),
  (79, '5a408cd8efa0dd46f53d3519a1d8ad483a282071e83ca8d8dda56bcd935bb44b', 'dx_knee_ligament_injury_unspecified_7ab630d44d', 'Knee ligament injury, unspecified'),
  (80, 'e0bfaf2072d552ae2d2806b8bd39df363163b67427e0e199f63895ef0ce74474', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (81, '1823d9ccded7d658f4625d1645754279d31b4281dff314f533347d50ff9fcf23', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (82, '24f0d2981356eb0e8b1934a079cde662840b09b9812cd108a79794c54ace565f', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (83, '17f7f0f09a1cecf1e1726296dcb59916c4d87b3fbfee28670a9c1b520ea5110f', 'dx_ankle_contusion_beb9f51162', 'Ankle contusion'),
  (84, 'b34a9d9811812fc138e07f21c5e644fcb52ba07e446d24cd996698d121751c0f', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (85, '29c340bb1a6de9af9edac14a1f7256d589304cc28ab37395764842d536da677a', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (86, '6139dfd763d84d270a58a6b2f320e9ec9a9c15322b3af1b601ab3a5802a6161d', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms'),
  (87, 'b31dc0ffb5c6a6fd612e39c840e83e89fb84a77a2fc18ab38beed3c3591e95a8', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (88, '96de1c0f83e34251e8b64ac85f787e9fc01fa2a06fcd1ee47e0349f8bb07ac1f', 'dx_knee_contusion_94058fe1a4', 'Knee contusion'),
  (89, 'dc7d74010331984de50a17cbda191bf9baebcf138bc82a28dd81c1c0d6bfeaf1', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (97, '55aae612bff3cdc9a092259fb39f5c0c52936acc634233a6463a2d2fa7bbd494', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (105, 'fc15096bb3dce1e471db2330addc6095941253458fcb12f3b9a179db9a5cf656', 'dx_wrist_injury_d94414e2c6', 'Wrist injury'),
  (106, '963bbb5f74cd8ae9ec556aeb626f52425fd849d080bd05cbbaad3e555c997b78', 'dx_nasal_fracture_a291a11f04', 'Nasal fracture'),
  (107, 'f2d3aea96381fa30c734da333e67972a443479e531eb85647447efe2732a6157', 'dx_knee_ligament_injury_unspecified_7ab630d44d', 'Knee ligament injury, unspecified'),
  (108, '376637cf1032d8350d1fa0581eac7a7fae91d2015be59a8eff1f73a71ceffed5', 'dx_knee_ligament_injury_unspecified_7ab630d44d', 'Knee ligament injury, unspecified'),
  (109, 'd85ce4dd274740173c6c2dc62fac4ff48812c79008182e7bd9489d5de78ad573', 'dx_pectoral_muscle_injury_981511cfe1', 'Pectoral muscle injury'),
  (110, '52ae15a6b7f92da5891f1f96cbe8847b93cc885ff5b624ea4e6cb76f8c5a24d6', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (111, '264a5eb57da2f0f1dc4a178e3968f76fbf6f3d68a9e891288fe442e56692d8c2', 'dx_concussion_a91e1107d7', 'Concussion'),
  (112, '651571a016fa08e338b1ecdc8a1006181c01cd761ce95b4d8b81c4958b008fcb', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (113, '223ef238143d338b9b1107c7b00cff004e251314c9aa79fab62c28fd779bf48f', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (114, '72b0d305da09ca7391128137dec62d85a9b40a5c44f854652348f6e9070fb787', 'dx_biceps_injury_69e895b576', 'Biceps injury'),
  (115, '7f72b5b99f06833362296329f7b5c45ce0a0bd0fb90fdd36cd36f380ea7c4aed', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (116, 'ee777cd114442a72ce9dff0f33e078404e12e701e36227bc3d94ebabf0a0e9a3', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (117, '9267789a62dddf69b1266251a0eb025f9d423d3a9c8ddd72acac27d0b9fefcb2', 'dx_shin_abrasion_c327f2dfa3', 'Shin abrasion'),
  (118, '6b2c03033ea9b46e34fcb539496202252798315d96fcdbfd59731c2fdac501ae', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (119, '16f8922a6ab43bc6ad5d9561221859768b5447c976835360e6a77d31105126e2', 'dx_pectoral_muscle_injury_981511cfe1', 'Pectoral muscle injury'),
  (120, '61cdbd6dd3a688899c24b8ce925da81cacb2cd24ff832e6569fc84d40ea04a34', 'dx_concussion_a91e1107d7', 'Concussion'),
  (121, '76dbef83bc935d118c0b991ac895ccbd3ae1529efda19272305bc2bb0cfcc26f', 'dx_costochondral_joint_instability_5683c80b63', 'Costochondral joint instability'),
  (122, 'e85d674fedbb8324c7e0c8315121c5ced63023bb3b0621a642cdf7f0bf85d31d', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (123, 'fa1b761f652cceb5fb01d0284b83168d4b5f08534caad0b9fafc1541f62791c7', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (124, 'ca84b8b1d60d5674d3021980b4f665d27561ac606c5ffedc511ffdb1043dae8c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (125, 'a1e10dc0cf9fd0a9d4def81f6bbe606122c3cc03fe1176aaf437b3f5660d4895', 'dx_acromioclavicular_joint_chronic_instability_299408db68', 'Acromioclavicular joint chronic instability'),
  (126, '11609a8447262dbc2bb8c70c4550f69e2fb58c9a862f610f393fa73848b3e500', 'dx_piriformis_syndrome_d562318818', 'Piriformis syndrome'),
  (127, 'c6a181ef2614e2091b6dc2abf0b2ff02e22fb41742649ef75f739942b04d1f82', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture'),
  (128, '6eb93b330cc7ffb8d201efd47c26f8c3f069aa9acc9144975df0b4c31fc7f33a', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (129, '9e8005ffc773aa1d6970c19db9d9aeede001c1d295278e87e80b58a150159df7', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (130, 'b988ad2586adf791d3422a37535fa92b3dc3b92425ec614b509d65f0bb647c70', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (131, '45423bad35744c6209584b0ae8aa3c2c4c373a4024266dae1272af7b6b29b477', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (132, 'ca50325fe041d5e33e554cd9e8d47b68ea8df1ef84c31b2859f273c99268fdaa', 'dx_knee_wound_7498252643', 'Knee wound'),
  (133, '0c261214e9b275dacc834aad98a62e5f797a93e8b479ecad2af039b8df6a7314', 'dx_hip_flexor_injury_cedda9fa03', 'Hip flexor injury'),
  (134, 'ee8bb442eedb1b0d2da8d8c86d0d71a664ea287db4887660acf2a363c3b6480b', 'dx_lumbar_functional_disorder_54b3525e5c', 'Lumbar functional disorder'),
  (135, '2ad20afc24b8f61ccff80d3c75ede9f5ca5b57c2b10f1d10860341715ea96231', 'dx_patellofemoral_injury_a6e2fe370a', 'Patellofemoral injury'),
  (136, 'd734597608927eaee9b6f83ee369b910305deb52dba4b1de50181c2bbc41e511', 'dx_medial_ankle_ligament_injury_9add2aecee', 'Medial ankle ligament injury'),
  (137, '67343820d1e7ae4fa830845926a3c8bd839cc0ccbe9ba5359904cf3f8b4f519d', 'dx_knee_cruciate_ligament_injury_unspecified_ce70a8f4a2', 'Knee cruciate ligament injury, unspecified'),
  (138, 'f4397fab335835466d09be07fc45530b04e6c7b059ab795e0941460a9c02ca49', 'dx_acl_injury_4b8eb47e96', 'ACL injury'),
  (139, '2a40ccbc7d7788e69eb4973b62366531b19e87d66eeec7f9f606d1189eb764ed', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (140, '0025a5797cc917b900431eadabda583e8c6db8f11446b7bd2d3e812a67eb9a31', 'dx_iliotibial_band_haematoma_8b35949b9e', 'Iliotibial band haematoma'),
  (141, '3b1b8b7aaa89033878c7b22ff181966a4e0031f56db811ba1ba6b6ab0ac895cf', 'dx_lumbar_functional_disorder_54b3525e5c', 'Lumbar functional disorder'),
  (142, '596fe392c1cf2e2ab0eeb5ce47c99ad577de9f5fd9ee6b77d29bcd4188623b3c', 'dx_lumbar_functional_disorder_54b3525e5c', 'Lumbar functional disorder'),
  (143, '1b85104c68da09c20a84e65f7ee53503889fb708b1ce2fe4f0221721a8cd89e4', 'dx_lumbar_functional_scoliosis_9c2f899865', 'Lumbar functional scoliosis'),
  (144, 'da8f53ec5cc4e3101df921032bdddab59177e3aaaafc2273a3b3a7c19d1e537e', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis'),
  (145, '8398d13c3636d88634bbf196b44b07a1ac8cf1a001b43c895585d41f8667addb', 'dx_lumbar_functional_disorder_54b3525e5c', 'Lumbar functional disorder'),
  (146, '99facaf70ce68483c7fd775b12866834ce5eecacdcf2a7e843582fb437de5436', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (147, '1bfc36c45afee702ee0ee581ebfa20af7f2f47230b6633412a78b0ac7687d0fb', 'dx_elbow_dislocation_6303e22e17', 'Elbow dislocation'),
  (148, '179a62f38fe0c4e1fb8cf4eb819a346de3803d4a315696acb6b859fcf0b040f9', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (149, 'e397b38426580b8e9519140f133d78b36064a03088117ab61a46242812424d81', 'dx_concussion_a91e1107d7', 'Concussion'),
  (175, '35ce82aa6a902059dec1233a811563735caf379f904dfcc8aa4e96d18ef53d50', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms'),
  (176, 'c496ab9eae4727b1314193231f23dc798ca54eb18b8bb46382115f35b8f970d0', 'dx_hip_and_groin_pain_27531edcc3', 'Hip and groin pain'),
  (177, 'ac91ac1fc7eec4763a21bb46a77779831c741f256a90f088920330307922b91e', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture'),
  (178, 'a3087b9b1ccf963161c74283defcf762f999aa7024efedc7f587b5253658c195', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (179, '49f28e6cf2ef8fb55d12fb6e31667f7ec55cdda7d3f948de0ed64c4fd616cc49', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (180, '3cdf523dd1458978c13e69bbbf0f4358985ab7a43f404b5a8e3c489ef37d8d27', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (181, '8190625dc8be32d8cfeb8bbfdcb5e2518910f63df317da99515b4e7821f497a6', 'dx_foot_traction_injury_7a520b8998', 'Foot traction injury'),
  (183, '0240050c1a30391f4d8bbaf0fa796a1b59c867063c16dfda8599fb6e769eea4a', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (185, '2f811361363d2fdbda79d589b85db4a0fd7ff53759d56e9178b8d2c311bc6da4', 'dx_acl_injury_4b8eb47e96', 'ACL injury'),
  (186, 'c6b0b33bfcc5c34478711422a3d499e46b0dfc8a8390cb69b7fce920c8b919d8', 'dx_elbow_dislocation_6303e22e17', 'Elbow dislocation'),
  (187, '7b8fab7711464895df76cae5bb9f96a1719f402f7bcb82db7650e5edaccc7552', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (188, 'b9e5648e1ed7e449add69451f9b1b569072635c211028dad7472f1314f5268ed', 'dx_concussion_a91e1107d7', 'Concussion'),
  (193, '948a8a97a8f44d7216e392f3da837c5ae19ac6e81b09299486252fe1c67fe904', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (197, '413f30c68659205fcb438aa8aa88e60c29f58f17a1305064c8941ac063946514', 'dx_concussion_a91e1107d7', 'Concussion'),
  (198, '9882389879d7de1c7d35bcbb0704b06851525271587d2d2ddb3be31ab25d7851', 'dx_ankle_pain_de6b615afc', 'Ankle pain'),
  (199, '6a3ef2b53b220f1912ee59bc08051b8c755ef752817949c76b8a84faf42bac3d', 'dx_patellar_dislocation_0c3c5e687e', 'Patellar dislocation'),
  (200, 'e401b61d2f4223558d86bc4393eb188960bdcc2742fade64f97692fda8a3aa3d', 'dx_concussion_a91e1107d7', 'Concussion'),
  (202, '8f19dddc5cd33ac0a9013e12f3b6c8bb32f8424cdead6dc08076ec5c63c70b94', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (203, 'c4d1e1aa5075eb82f3d752ae26b905b3239b4c49ad367840ba4f8f159db27c62', 'dx_foot_pain_116521a908', 'Foot pain'),
  (209, 'd33cf1730cfab8b0386ca5339261a66f84a86d08e8472c1e709763d78d71f45d', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (210, '2183bff1f55081fa41833156896650bdb455f451333c67d5c69cebb3243ca9b9', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (211, 'eb8bcc51371ab61eccea1078a9ad29ae44ff71b114c56f038cd73d92e139fbf3', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (221, '24970ad9e06ab8c8c087f8914720efe66b478b9497a4c19747cf8f5e6b8bcc6e', 'dx_lumbar_muscle_injury_a7fb20b2b8', 'Lumbar muscle injury'),
  (224, '3eb2a0fc27a1e8cefa4bee00ef4b9d82db9c7681c5ec6ef76ffe2c55b05368e0', 'dx_concussion_a91e1107d7', 'Concussion'),
  (225, '701db25df19b0df197ce6426a7d4d9be49864b4611d8e22e40a43b92db3f4484', 'dx_shoulder_pain_738e4b93f7', 'Shoulder pain'),
  (226, '4f239558d29b6ae2e19be6e7729111f626944180ad30c1bcda4dfc345dffee9a', 'dx_hip_and_groin_overuse_injury_71c787dc38', 'Hip and groin overuse injury'),
  (228, '3e7b49ec11a1a86a6b48323fa1d3586ef734368f4339d3d87eeb75959b85c842', 'dx_shoulder_impingement_c2f2a634b4', 'Shoulder impingement'),
  (229, '2d8866ff322921cd04743890bdba125d032df5d633e4eb1528f4a7353523fb31', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury'),
  (230, 'e46cc57c4c3b3895bad6222105bf02145742e2b9a1bce441aee41cd8e3e61f79', 'dx_wrist_injury_d94414e2c6', 'Wrist injury'),
  (232, '973d1edb65590fd2ac23f585ff7d3a66b3f7c5d4907ddf8301d9e5deb6b9cb76', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms'),
  (233, 'fe065240d22b1a9535eedd65a86b9c0fbf05ac533bd1439594fd1517fdefde66', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury'),
  (234, 'd3dde69f259e0a8747f3de27a14f6c55071162dee1da6612ebb4befeb0fa61b6', 'dx_finger_extensor_tendon_injury_mallet_finger_36d86ff004', 'Finger extensor tendon injury/mallet finger'),
  (235, 'b164bfe3601fab4b7d470ecbaa85bee0e07b011b4684e6088354d61ddc298d97', 'dx_rotator_cuff_injury_0744f75c4c', 'Rotator cuff injury'),
  (236, '04d667dab45da0a45fda3fd9602ede5e035cce199486bb55e6b6e5bf8f74a064', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury'),
  (237, '284b1c4dc008897fabff7c57dc6acc7280384d2f5af8b95c65cfd8e27f489e6c', 'dx_concussion_a91e1107d7', 'Concussion'),
  (238, '2aeea0610a557a58e86396e1110278daa0d50a1b46d1d3c26bef3361800c206a', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (240, 'bfc642cce9733a53e66ff5fad3414a4021f12dbdc116f028bfe6dbafa82134ef', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation'),
  (241, 'e9cc5cea501a25463bad6d11c69616b5b99665d4558b8fc9ddd4ff4213334a33', 'dx_concussion_a91e1107d7', 'Concussion'),
  (242, '4b25de2b44c278a6cece5e0e8953573cde43ffce427a617f9f9d3c2dd7db1076', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury'),
  (243, '3123266579ebc2ade9c291a5a2e1a020604c7a56d1463bdbaedac22e09ca8012', 'dx_buttock_contusion_46ae636fd7', 'Buttock contusion'),
  (244, '18e793ea51ac4dc326913736755d8e64dd37af9615eaeb17117748b0e9eb5f62', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury'),
  (245, '1cc716af8244dfe339b5c80426a733404a7beee5e898e3c67e4fef4de7b0dc6d', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (246, '58076baa37d3b0f2a826aef732ec39c79ccbe20ec14e76796147c199f706be4b', 'dx_shoulder_labral_chondral_injury_4ddc56b103', 'Shoulder labral/chondral injury'),
  (247, '413632cb89b17d518d22260c43eea086b0a3b0eff3756ebcae62a854aebced72', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (248, '7f337e407ee2a0fdfdde14aef38b5c54969715fdf48cc1e7ccb0cb7b2b985027', 'dx_midfoot_injury_3332895405', 'Midfoot injury'),
  (249, '25657fc970d7a18bbce7097d244942a85ef1410e4d811f2b8f9e0dc1c14f1436', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (250, 'f3d652308b570e7d1064f4fee587040e43c513aef33c0e0dbde58ff458370786', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms'),
  (252, '1001e06245ae8ccb3fab3f7fc9bffb304c1d10b7692d5cd27f1614955897426c', 'dx_superior_tibiofibular_joint_sprain_b52d941096', 'Superior tibiofibular joint sprain'),
  (253, 'fda6711719c92b4b0c6e8cd6f91eb787d284c88725f356db18afc307e6ce1362', 'dx_foot_contusion_6c8a5bb721', 'Foot contusion'),
  (254, '31b647798eb714935f593b277c936a0b2780a47ddb8e1945a027dc2a3b042efb', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (255, 'cd737c028d3f86a2c7b93a8cdca30632cc24189092dd7cb542b37244cfc02163', 'dx_posterior_malleolus_fracture_5a4d097409', 'Posterior malleolus fracture'),
  (256, '9d1d050711f41cd762c67dcd56361aadf083143fa8e894daa77a856a12666136', 'dx_shoulder_impingement_c2f2a634b4', 'Shoulder impingement'),
  (257, 'b69ac7db6487a5bb1bba5320d64894e16063f0132a2faefef2f94a80597b8f2f', 'dx_proximal_hamstring_tendinopathy_with_ischial_bursitis_9c962c1796', 'Proximal hamstring tendinopathy with ischial bursitis'),
  (258, '3c1a5bf09e804026c0ae2ffc359199ece543dd01b9264a80f693f2a7ce09a1fe', 'dx_concussion_a91e1107d7', 'Concussion'),
  (259, 'd057ffa0cd1fe0a785d552976e73b0a2ebf9ab39222fa925ac7d197b818bac8c', 'dx_lumbar_neurological_injury_bb35f1e8ee', 'Lumbar neurological injury'),
  (260, '2d4867f8e592651eae03423d2dd8313afafd6518f4bbfd11c302af3e65824c7f', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (261, '2780bda7b6260e5845b5193d26b2c3e9f7f91c50f6ece0b00c26fa49485346fa', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury'),
  (262, '65eb619661db658021a0a3c41c2a2fa6b80e335ce030b686564599bdbede06bf', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (264, 'f90b64d2b0fb65160f4956d3962cff72eba8ffa6ca016474ffb0848f7fc48eb8', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (265, '621a414852172782756c3e94d007eacacd3c6a1369a65a78d517e38e4da7c1a3', 'dx_knee_nerve_injury_3155d49308', 'Knee nerve injury'),
  (266, '4123ac156519c706d29d3a7d59f5329c8f7c9e1fee5c3716aecd7cf1985b1bd4', 'dx_thoracic_spine_pain_9ec9a9f2e5', 'Thoracic spine pain'),
  (267, 'a352eefa574c909f0c0d390aa040423f91b4f718b516fc0a4258a1b0b2692bd5', 'dx_spinal_disc_injury_e3b980b6b8', 'Spinal disc injury'),
  (268, '76e6fcd474ea988bda50d9234aca4016e963114e16ec7d99e87131b43df0607f', 'dx_midfoot_injury_3332895405', 'Midfoot injury'),
  (269, '31dbfc9a8aae636871a58c04de6e8e76bf4da68ebbd4959317f32f8549113522', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (270, '79950881593a9a65b387a661dc7f455337407a079fd9054dd1d3efd324deaeb0', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (272, '2b876e5108e7050b718b017fcd8fc760a08b0bb891bdda7e15d70da47361804b', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (273, 'b9762e458f73afda33db92509aad4ca6335b8b36a0ba4d1ddf56e05f0e2f767d', 'dx_concussion_a91e1107d7', 'Concussion'),
  (274, '78f37b223246f29d2561a4f69b781f2c7104b26978832d306374c171e944d8f5', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (276, 'a0eb949dd28d71f3785805ec172b84692c326ad859df78d9e4b6f494a9514519', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (277, '07e7f3c3a9f04a5cbee6b7d44716682bbf13ed0c433172c75d7fbca1476b2569', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (279, 'ae3a01dea391fb6b8461ba04b6894b7b5353067235b598856c667afe28de002d', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (280, '3af3503db27e6ff74c06cdbcd12deae193b310c4dc17ae285f2e9472d1ca126a', 'dx_foot_pain_116521a908', 'Foot pain'),
  (281, 'feff7be715cf709def4b986be7610b99d8dbe88e8215b31972963957720aa421', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (282, '7aae85cb1d2b4ae0dc77701e0b502841bb48c058e80d020f203644158476afb5', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury'),
  (283, '8f6a28ad317142dcb8c95b251247b58f70358f70b235d83b25b15df080faca11', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (284, 'cf9be6eb5afd174fffff615ad5933c506eade25beb62f51454f2ed2c6a36271d', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (285, '96fe4ed7847ed9c650fd24fe041dcd6b79f72998ba90419540719169ee4f0a5c', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (286, 'b3b65aee0b5aa88db94b408db9806939d3f3c557d5c356c4f78c4f50d5ee20e5', 'dx_lower_leg_muscle_haematoma_ee2865c913', 'Lower leg muscle haematoma'),
  (287, '92ad4b8b82a316f2308f7d8fdda90314f6858314c3be9f16205c5d54fb8a8465', 'dx_wound_infection_complication_5415c9f38d', 'Wound infection/complication'),
  (288, '97849bbc837cc651aac50ba8bc5c8b34e406e92e7a93d489ef052f08d9159162', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (289, '155ffaf3d40a4068d1c5fad5e2353e2f6c79d9af8301577fde59d8c9a67889fb', 'dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b', 'Plantar heel pain/fasciopathy'),
  (291, 'c3f8ba7e46838d4ebd1fa96a87d2edc4d9f9b33a6a1e101b4b2d7cbe6e02886a', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (292, '5eb0b78b6c43fd345e8661fe56319c1873b8782c37ba492ca66fbe6dc65b7bca', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (293, 'ee8a79990f1bf5d16cd4e0997176ed6d945d8dc1b1529a20bac532240b67fda2', 'dx_cervical_spine_instability_658367d444', 'Cervical spine instability'),
  (294, '1ec4a921999ef598177d1ac4f2c1e4706f604bb4a89f3a6004bcaf38ab0ba04a', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (295, 'c2f9765f5178c01c2302dd73faea42c9f8130a56511b5bca66a37c553eae8f79', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma'),
  (296, 'f07103cafe6c25b4c58f8e5d09a8d182358c8007dcb5844fb289fb85d3d4a51c', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (297, '667414a2ac6f065166588844c08029604bc1ee45eb981699f41dcbec580b9dd8', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (298, 'e312da631ddb31ebaa258a71c3c82dece0271fbbbcef5583d1625744aeb8322c', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury'),
  (300, '12a42b50f82bc18b378094161c57291d0f13cca7d65b181ca44a777cc3ed0cc0', 'dx_medial_tibial_stress_syndrome_shin_splints_651f7c8df6', 'Medial tibial stress syndrome/shin splints'),
  (301, 'c31aab9edbe4fa7c837603bede674e7a8cd36dc0e5c3d341bdf15262fe9b1aef', 'dx_little_finger_middle_phalanx_fracture_4f9d2f371a', 'Little finger middle phalanx fracture'),
  (302, '180eb690e49ede30d2d5006d0509318bf8cff597749147e9f67ed4854872394f', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (303, 'edbddb8e8eaa312c5c9f5f443986dec1f909798ef18fc4962609136f43b97482', 'dx_epistaxis_671a1d1cf3', 'Epistaxis'),
  (304, '10144b722204e6edb6966e824cc90632339389f9824c8443b8ece10cb18be010', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (306, 'c8844dce2020acae6599a25c19c7e5538cc23ab9a5320e23cfa660390a28640f', 'dx_thoracic_spine_pain_9ec9a9f2e5', 'Thoracic spine pain'),
  (307, 'e81ee91a5b1dfbbad1cef2980b8447e0fe44121818a0a684bfb2d58f32ebb384', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (308, 'bbf7fb543a7c1695de4243dc89fed29a6d1cfb2a0b3d3155d49c81162b70ea89', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (309, '1e9fda2b05c30ff49e2ac85c1aff9ce877940cc94e63f5bd3aa92d7468aeeb28', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (310, '281e456765844649a9a1e749e4b9be07000547bd940ec7c80649d3c8981c1df8', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (311, '871ad50ec4257a6b6a3932c02e0827500822a6dfb456d03e002ca8d65b75a1b3', 'dx_midfoot_arthritis_881bf0b51b', 'Midfoot arthritis'),
  (312, '6cd95553b86788f2e16d96ad55d1e6c2ebf071ec3ac42b692e8840e3f99eda5b', 'dx_hip_joint_injury_07aa18de20', 'Hip joint injury'),
  (313, '9b95ff2584354f38f0c4e2b076720872fcf5875de938f8f0c45c0683a1dc0036', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (314, 'f8fa9497047a3c975a1d1ce0d072823726c123edac281294ee605e08f85b64b4', 'dx_concussion_a91e1107d7', 'Concussion'),
  (315, 'b17f5e625e91d4db61b4fb3a36bc6817bb8ec7db0afdddc08a518e93f0e5092c', 'dx_concussion_a91e1107d7', 'Concussion'),
  (316, 'b7096680d68bc1bddc18012f4b9c57f50a94f1a4d590b90d93e10d668025a24f', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (317, '615f18a77b0ece70c3c91626602351777cea0f1aaee357ab3f0cf3b19c5f7993', 'dx_hip_joint_injury_07aa18de20', 'Hip joint injury'),
  (318, '3a3b3be9c51e0cf989ce91326d5414b407272b7f55b0d9a1fca4e0ff383fb971', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (319, '6d16ea4d181c46d518d270e310f037b4c3874d753cd96b9cbcc43a2dbb198bc9', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis'),
  (320, '31910169ac0da4d8047ecad763020d7d38870558dec3a880f8ceef4f980f59f1', 'dx_concussion_a91e1107d7', 'Concussion'),
  (321, '2d73fab4ffd9d621f2caf73ba0866502db6bec662e059bc7cb32ee19409d7c99', 'dx_shoulder_dislocation_2067688fdd', 'Shoulder dislocation'),
  (322, 'a935c45767f3bb86f3cd89e0e0454e49b8fc6040700d565761014e2bd0a81197', 'dx_wound_infection_complication_5415c9f38d', 'Wound infection/complication'),
  (323, '9ef07e13f860fd563bb1237e91370c6db43da5cf432b8a866677737824830cb4', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (324, 'a1d3c0a8ebc05d5ede364d2cea977f3cfd566f1fe44a7d501cfe6080489ee55d', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (326, '97612bcd84465e13216432e259148bd89f5635e62b6bc622c99eb85438e171d1', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (327, '4c15ae08051855896836ff1ef644e33738904c7b087d974a90ea804d17a53f51', 'dx_patellar_dislocation_0c3c5e687e', 'Patellar dislocation'),
  (328, '0edb1f1bba24a56ea066006a09db2b2e5b44a793b422512b0e33a28d3a3e27f1', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms'),
  (330, '573f6381e7826b758b6ff7a76b7ff4cfa333056f518bcb60a5d25ffe5b0a9f3e', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (331, 'cc959415c0102d08f0683ca39ec0dc65ccf2b2101128e51b27e82c65c7448b41', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury'),
  (332, 'd21efa9d18ff69a674e5de71d760ee0ac6c7b753d47e29a17ab55adcbe8be6c4', 'dx_concussion_a91e1107d7', 'Concussion'),
  (333, '0fa0429b7a3d716cdf6c78038e2f78be2242c2336e5cf128262e7dbe37215478', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (334, 'b0930142b46b0d2ef9676083fb6865b062005a90ab868bbfc895c5fc597a7459', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (335, '5181dc0525cdd6b97108a6f28082d1ca18026166b51b764afc4ea4bd3872fc64', 'dx_tibialis_posterior_tendon_injury_8ddfcac54e', 'Tibialis posterior tendon injury'),
  (388, 'ea11e429e3b9abe1e0784d9ad46fe83f9908b376381e88585f52c221f1f35ae8', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (393, '004292e8a3d96ebd32e9f7eac8d9f0468fbd2171f0aae1ea46be96659790e85d', 'dx_elbow_sprain_16dd0e91eb', 'Elbow sprain'),
  (396, '1bd34423845cda898c9733df721206777d67504166caf71681de5f69b8c987ae', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (397, '90b7c71d7c518692efedfe6912bfe5090f09da778872b7106be0f27ed8f719ae', 'dx_concussion_a91e1107d7', 'Concussion'),
  (398, 'b74230c6e9209b32c6ba36f7157762683a9c93930e83ad60b069a18e39102494', 'dx_wrist_fibrocartilage_injury_fddc60c8f6', 'Wrist fibrocartilage injury'),
  (400, '178af18707c162506f1db8098a6c765c9724ee0f7322859580f53368134a45d3', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (401, 'a069dcd43a6e7385e9c1155303ed85f5529bef97e1886364b74f1a1daac6ef17', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury'),
  (402, '0fbb5bd3d2ce95e509371db8ce663db3f0b2c34a67e0f474ecccba6583ce96f6', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (403, 'beeab91b0baa713df379693e70c95d161f0f543603ee605f04fc17650ff9288f', 'dx_lumbar_soft_tissue_contusion_125139d685', 'Lumbar soft tissue contusion'),
  (405, '25f6b4b0febcb6f69a2be13aea7e5f2b937592ab5f8ab59bc49823af023de125', 'dx_meniscal_injury_b166306f7d', 'Meniscal injury'),
  (408, '0a415204b08693dc6e9aa27e4514a7d42c981c23153e9534c342e5f77deadca2', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (409, '6eda97cec766d176ae34f8d3b91ccfc0592820f21e4522800e04705866d72691', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury'),
  (411, 'a4ee8303bdf7c6b745a28d663e0b8c7611347a80e068e7858c01fd664338aed4', 'dx_concussion_a91e1107d7', 'Concussion'),
  (412, 'd554edba20cf5515dd08372f1100a7a5f7a3fe869d4d06d2a215f18c50a52c7f', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (413, '0d3b71fd2f97475a710abe17a0e57a22c7f8107bcd6dd1cfc61abb9f0d249630', 'dx_cervical_spinal_canal_stenosis_15786dee1f', 'Cervical spinal canal stenosis'),
  (415, 'edf064d612d11cbcea1f1cdb80ef1125eb05edc5dc3ef7ce55e7d56901310f74', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma'),
  (419, '12d31fbc0788df45ebc1a8060ed9e271320dff7f2bacf7a5add8c0e79188d5b1', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury'),
  (422, 'eba3ddf0825494dce181e08416c7738b28a03e1869aebd0d1e12d472c61455eb', 'dx_sacroiliac_joint_disorder_69fe12ec92', 'Sacroiliac joint disorder'),
  (426, '3b8294777e5432e722aa94a2248a69eec4c345b37b674aa08220ffcdd43d8901', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury'),
  (428, 'c26e66e16803bf2007decac3ecae00aa9dee69dd04bad1320413d89002706b26', 'dx_concussion_a91e1107d7', 'Concussion'),
  (431, '03e6e31824293685740adb681c53a6322b2a90993b7991192af62c4c20145008', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (432, '9c4317246315000fff4c675d083274f44a283ab50c0b6a5ad1e56d98757af2c9', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation'),
  (433, 'bd2f64b704940ce5204000b11ff52325b3ec889b57149f91a8b20ca936e41280', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (443, '4a39b8a7f0b3604a3519db6fac2b6f6d0a0be6c9c24a700834fdea5d5e3681ed', 'dx_knee_bone_contusion_ba129fc033', 'Knee bone contusion'),
  (444, '95d62703c3413ab0966799badbce78d8cd0575f70dc9a222af074163607627ca', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (454, '58603e21290d822294304e9dfa1725a03d181735b936e82d0dbef92b561dff77', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (456, '8669e0823da04469a9233f37f0bd2ef38f4e35c54b5f4227ce595ee519ed44bb', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (457, '76fdc1e904d96cc0500b4234ecdb8cd9287abecbf7b537805ff4b4d0cd6b469f', 'dx_knee_posterolateral_corner_injury_a4c4c64579', 'Knee posterolateral corner injury'),
  (458, 'e2c7922524a5a9a0a0fd2a6ecc952c44a072535ec359efd036b2f3b75603abb9', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (468, '4d74001da43a9e6425217e61688c611bf69896eed3c2d85e05d3a7d7f6a7c044', 'dx_ankle_osteochondrosis_0b34b510e3', 'Ankle osteochondrosis'),
  (469, 'a0fa69f5d64c59bd429acb26ac52507a40f276d2d9ba1f5a7488a3e2916f4195', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (470, 'd24864148c40dd326b8dd0dff304247d0ee91496398096645b1625bd863b5dd3', 'dx_concussion_a91e1107d7', 'Concussion'),
  (471, '0becfbf23420e31ee73c5d4cd6d31614bca1116b29bb29dee74ace171ab191b7', 'dx_concussion_a91e1107d7', 'Concussion'),
  (472, '9c9f07fa55cb3b7f2b47385ad39ccaa7430c263bf60a05422b81e741c38581c5', 'dx_head_or_facial_fracture_3497d30cee', 'Head or facial fracture'),
  (473, '099da26bc8b7aeb44ea395c3a7363ee96fbe978b12a0003739dc5f4332b09bea', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (474, '73a10178a08cf2c5103604e66ccb99ce38ceb092daacde814c732d5fcdb501bb', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury'),
  (478, '3fa343e98b0489027f08a507fcba4b9ed2905d34654b35d444ddbbfec685ff34', 'dx_finger_flexor_tendon_injury_93dca2c764', 'Finger flexor tendon injury'),
  (482, '8f5e9a266c82d95ae3c31b39a9a1d2b97ac6c0079333de1ccf5d4e0210944320', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (484, '5ed46ccda322f4ce5206ecd21b97edb44a826382abb58d4087f1d30c37cd0305', 'dx_concussion_a91e1107d7', 'Concussion'),
  (485, 'd6474a38f6eed60d477a5f1a9d772961ea2f8d2db5ee999ef29fb87bb3818cc8', 'dx_abdominal_muscle_strain_or_spasm_8848453dde', 'Abdominal muscle strain or spasm'),
  (486, '4c41edd94f55f09808a20cc28a1dcd9c540fea0333f3aeb0257d1de3c11b62c5', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (487, 'd82dd65b8e55e6d68ef8f42aea9cc9e82f5e18ae6f7e5b1baf0f24e8ffb11f38', 'dx_concussion_a91e1107d7', 'Concussion'),
  (488, '289341186e95660283db982979bf2bed042f0a0824f160c8d09d10db7646c0d1', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (489, 'b8aa894672d83c2f067572d10b0094f145e90b8798ccafde821ec5f4b42ad645', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (490, 'c36222720060ecb5475fb7a578a5d0fdd0e970d187654be86583059b1359f6e5', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (491, '7cd00b5fb81d2d19acbde11cda762249b263921e0859ea8f3c73f23d3faae5ff', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (492, '9aee35a98d006908a738db2837a99adaa41a7dd5cae8fbbd3c55f518a554630e', 'dx_biceps_injury_69e895b576', 'Biceps injury'),
  (495, '97263bed643d3514d3ffb98921cdb2a400bcc9acfb38c366b0f30f94be161d94', 'dx_lower_leg_pain_64d4d83c4b', 'Lower leg pain'),
  (497, '07afc39ab0a47742b175b93911e30b1807353d825cbbc81c4e0ccde610e949ed', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (498, '5a8478cf221d426b2a3c759f16538436c0077b67920447359f352f15eebc6049', 'dx_knee_osteoarthritis_088b6b8911', 'Knee osteoarthritis'),
  (499, '0244d092e7160cab078ff27c3390d2992bf7dbc3ce2d14341b6539c5c9a3a38a', 'dx_concussion_a91e1107d7', 'Concussion'),
  (500, '9c55452f85e16f6ba02479bf5e405921864284d741b0000915bdc2ef6c6f9605', 'dx_concussion_a91e1107d7', 'Concussion'),
  (502, '4b7eb504fc58ed70f928fa677bfb1e4691cb7fcdb6f60bb9763dd812f7a11abe', 'dx_sports_hernia_ad99f8552f', 'Sports hernia'),
  (503, '3b780f0e8f960619e3b58b20c2216f2c116d8e35d5d2c165db8836f9be48ef3f', 'dx_sports_hernia_ad99f8552f', 'Sports hernia'),
  (505, '5bba4b49e7c66c4c13605e163685d3cdd17286bc56847f4565987cee30a7418c', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis'),
  (509, 'ba3b21fe9d806b643765bce4ea1ce5076cab10d32ebb408656855d42d25c3058', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury'),
  (510, '71a43b157b9eadfe205857914a9f6e7eebdb0f3fa3ea35e358d311db0c919b53', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (511, '8d6fdf50723fdd8eb913b5e283346afc5f4076e2a0435c8dccc40740901cdbe8', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (512, '02c5506f5ff668fd537127cb04b8227c23a298d30ed663787736408acb559c32', 'dx_sports_hernia_ad99f8552f', 'Sports hernia'),
  (514, '08be9dee5d7a985618ac8052149e9896c703f2834753f92e0cd6ab2c8529fc68', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (515, '52c0d4ba949f99b957c9549f2f268ff960a70e997a949154dad5227fa3c9506e', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (516, 'bcfadd072104c77ee24c1902e34c0735e6689e7e9b8ef74710c73e630b70848a', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (518, 'fc37670e5c2fff021361f005f13f8fb4906efc503f9971978230f72692f9d76a', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (520, '3a1c1274597911d28afb84d8f1d4343ebc56e8d27d215b0c7fc85f977b986530', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (521, 'ac221b7558eb97260da316b4f3b75d017b571d72a2bf0d0de158a518ba1e6e37', 'dx_concussion_a91e1107d7', 'Concussion'),
  (523, '1c1aec75ae4eb767a1c89000801c6e4406a0b5acfb48b1f72ce029bb3f2d992c', 'dx_thigh_nerve_entrapment_cf6619a0d0', 'Thigh nerve entrapment'),
  (524, 'dddb74c7ad6fd91132de97385e8ed3c13552e2810b1d34de8118a10ae8deb1e1', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (525, '2922df62e0e133a7fd17cc7334ffbcac8509969e71e9f20ce9fee03df3f99296', 'dx_concussion_a91e1107d7', 'Concussion'),
  (526, '386ba9339d5bb1c56b005b9bc6205e99cab713313ef8011944b3527832e18984', 'dx_hip_joint_sprain_6ee81972bd', 'Hip joint sprain'),
  (528, '77a079cee6879408387adf3640555dd9dbeb6047376f9d75ef54a9eff3386400', 'dx_sternoclavicular_joint_sprain_6316623d10', 'Sternoclavicular joint sprain'),
  (529, 'fc761f453a2cc7a64a39369250eef1aabcf39374068ed58cc5a2141ee8db7726', 'dx_concussion_a91e1107d7', 'Concussion'),
  (530, '6c606677cdf0270112f98cd5cfbbe74a3c355205670d61294bd23fc8b3fffddb', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (531, 'cf57e99c4af7495ee70842541ea96947839393336d0df060b43196c5b21ffd13', 'dx_pectoral_muscle_injury_981511cfe1', 'Pectoral muscle injury'),
  (535, '0600a3aabc3e8a87bd272ea48f53385f0a9fa520cc8d59814e97ff542f37e7f0', 'dx_concussion_a91e1107d7', 'Concussion'),
  (536, 'cfb320dec0b63d885bc6b9d5265e6f9f6270d9f60c84d30143a0e2b585ef3352', 'dx_ulnar_styloid_fracture_fe63bab748', 'Ulnar styloid fracture'),
  (539, 'ad8d807ca13ee5d54b3d7c7d1b2237955e61ee20b1d45495f5642c3b0209d781', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury'),
  (540, '886a66afade99c7e4461fc1f1c1ca4dc74d6c0da8f2d509260cbef10cfe48342', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury'),
  (576, '8e57cc86431fe3e3bb76dbb7be717bf3ecb4f7245e04f4b51496101c667b2dba', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (577, '6e53b38d72e8ed93966cd47e64e985d0c352fc38f42f7716101ed67d51413a58', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (578, '75353cdadafd21c973d409e3ab3c57f18d0ace02ea98dc57358ffa6bd8877f33', 'dx_concussion_a91e1107d7', 'Concussion'),
  (579, '8ceaa54e3b69fcca842806ca4eabe42c7d6434d1384a6f92dbc03eef7ea67771', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (580, '8cee4da8661a9cd7f5ee027ac4d1f386aae6a4ad0164a4293baf8ff4b2cf0f9d', 'dx_elbow_injury_7100f71f81', 'Elbow injury'),
  (585, '5be5be31becdc0ab28234f9c0599b2d2492ee5617b02df27d035c220536b2612', 'dx_biceps_injury_69e895b576', 'Biceps injury'),
  (586, '5bf98c52facaf2248db92676b62684b4010ef8f26f515495209a4240c9e119e3', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (587, '723fb8071c64d4064eb210728924553a6d686109d111ea8fcf2e02488778974a', 'dx_forearm_muscle_strain_or_soreness_652e41503b', 'Forearm muscle strain or soreness'),
  (588, '2ea53028dac437b813a3382d59d6a9bc08d5579ee2e8c6faef7ea528b78bb56c', 'dx_plantar_fascia_injury_ec4d3703e9', 'Plantar fascia injury'),
  (591, 'cb61fce2383ac5fe7160137c6a45c7f8c488281d188b7274cb0201b7198b3ebf', 'dx_knee_wound_7498252643', 'Knee wound'),
  (592, '7cc4f235d7c677656c9f630b47c2d1fa6561ea4a50e72f9f538b39035f591bed', 'dx_elbow_abrasion_fca1398b6d', 'Elbow abrasion'),
  (593, '966f46369adc500027213978e677e3f9d0644399d8651bad47f4a07649468ed1', 'dx_hand_wrist_laceration_or_abrasion_35c31d7555', 'Hand/wrist laceration or abrasion'),
  (594, '17814538fda17b304a51f986ed323d2995973abfa1fa1c04c32d0dea333c213a', 'dx_spinal_disc_injury_e3b980b6b8', 'Spinal disc injury'),
  (595, 'd50bb595e24afc5e932a5f1085b97b7554c39b09c4d4999c08191eef99e251d6', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation'),
  (597, '3e61479ba1e0229b599be635493fc931c54f455939110f4c471f1426673047f6', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (598, '3b3a698b51de4ebeaaa3feeb17a81055a34c38fe63fcff63c386d501fabc76c5', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma'),
  (599, '2ca495a8b76fb61b2102545a886d8ba58c78bca4301ccefe0058db5d8d7c6809', 'dx_thigh_overuse_injury_3d503881d3', 'Thigh overuse injury'),
  (600, '9e2ac4051d459c7298dc72cfe7efc21429304a588744934d7de210d1346fae09', 'dx_knee_wound_7498252643', 'Knee wound'),
  (604, 'cf1abb76a433a5a155c07db862c6554fa4ca7e71f7ad13d3e744e8b2bd4f299d', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (610, 'f5868e17631f6d22fec8fee8948e904c886915a88c4d0e3a027d6006fada8058', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury'),
  (611, '02f1dfcd7c382c33ce74b1d7307a01e04d7f5d547b541d1ca0ede69c636f3069', 'dx_ankle_pain_de6b615afc', 'Ankle pain'),
  (612, 'c1510f70464cfdf5e659a7272db18b4c1d25e3bf5deab8e1fca1f97ec8976648', 'dx_finger_mcp_injury_6c586feb13', 'Finger MCP injury'),
  (613, '409e80e0929b2d03a92964108d3e672b69715d7add9d6698e81cbedc9dccc915', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (614, '16fb06d3314f1c1277584a78fa50ebd4e1471af32e6b72b7910689cfd520310f', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (615, '71d3d530a906d22cbd7228a49b0c8a25987825452a178eb956a52ca8705db2e7', 'dx_lower_leg_laceration_5e3fbc19d5', 'Lower leg laceration'),
  (616, '10931c0f4a8633c42159196d80d0e1b1bc262077a35f86cd109aef33db07c99c', 'dx_elbow_abrasion_fca1398b6d', 'Elbow abrasion'),
  (617, 'e1e46218cb5c21d18aafcdd603723a78770d0f6c0af034790ef4e4d74e34a488', 'dx_knee_wound_7498252643', 'Knee wound'),
  (618, 'eda962e9bd42ca8ac0f6458d4d0e84149720eda5a9be822344ed1a617b0cae21', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation'),
  (619, 'b873578b5818c97208eed7393760adc59b9f56dae676f1861f0625596d338bb6', 'dx_rectus_femoris_muscle_rupture_8741b14c71', 'Rectus femoris muscle rupture'),
  (620, '2fd65618d1feeaa2d3ca1e62c3343fcd10d2f8c776ca270b3f9701bc2156b9cb', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (621, 'c071f429e661c460d92d76242a0a2c350c761a898c4de20c70083d676fbafcfe', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (622, '7d79411e2d4f6a4c4b7486c568856d1da5f5c22454b0511529d78673c41dc7e7', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (624, 'e2cad80f014612874c589cc2cb6dec8f3d649ab7a7acf5696937f7232d5c7501', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (625, '119a94e81869fbb4d02904a2edfa29d3391ec6b0c502219df4ed158559173fcc', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (626, 'c397bdb034bd1596124bdc151fda2241b2276723a0036d4b209b0bece36a7b1e', 'dx_concussion_a91e1107d7', 'Concussion'),
  (633, 'f16cea8ab559cd4de3ba00bf6d169b0b93eedd50cc1afed14c54b349f7eff035', 'dx_quadriceps_tendon_injury_08ea99efaf', 'Quadriceps tendon injury'),
  (634, '3f94b2c27ef4649ff312d07e1ce636d6da2a58d191dfdbf1ed9152216f72cde9', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (635, '1772b60dfea2ae249b1e67ee2af78d012119adffcf2a56f4e6b3e888c5202c7c', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation'),
  (636, 'e66e0ca2ec07adb672ae3d53c60e7156bc9cc9abe0b199df74b626cc750cc6c1', 'dx_knee_pain_609ce718bc', 'Knee pain'),
  (638, '8f7d944f66787ef171a066f8323fe31fdb283f9a477c11fbf09c2d0529300fb7', 'dx_neck_pain_58ed6a0781', 'Neck pain'),
  (639, '430b5452897d5aa5d884686ea62128d7e9cedac3ab2f7d2331f4ba3bf0171e4b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (644, 'e90549baeb9b2aeaadc1714d7565462e1f9a1ad02b7b0e05c61546db68ae20df', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (645, 'cdd1559478ea4fb6cbe307d65a5c14c9bfdfe3f7384f90f4295f28ea75e1f157', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation'),
  (646, 'ba6b5c41c639084a88ad433fc570c19a76343c0a62d31ad096d41cc84285e686', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (648, '4d181c0a1c2372aca50780b714fac78583d49485f71356323f5dc53b959812dc', 'dx_shin_abrasion_c327f2dfa3', 'Shin abrasion'),
  (649, 'd2a73414a40cf3d88603cec2d84a254e149fb0d400df958450cb16048ba8001c', 'dx_wound_infection_complication_5415c9f38d', 'Wound infection/complication'),
  (652, '83a6df19100b09dae56640e7511a47419c99b7907a33be432e50febd27d32651', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (654, '224bf78a2a3c1a133534ab7822e50056529b3f29c1b6dacff9fdcdf487cc25c0', 'dx_wrist_fibrocartilage_injury_fddc60c8f6', 'Wrist fibrocartilage injury'),
  (655, '28a375565d4f8ae5da7a1a0a15b7504dbb090dff548f61f10133ddc5cef941fd', 'dx_ankle_pain_de6b615afc', 'Ankle pain'),
  (656, '58e245e26cc8f09af48b5bfff578db4c5dae26b4d1ecd25a4392d7bee4cd78e4', 'dx_thigh_nerve_entrapment_cf6619a0d0', 'Thigh nerve entrapment'),
  (657, '6e25aa893838690ff2ce4a323442391d5c5f9774d965082bd077037a1b3a8b67', 'dx_metatarsal_fracture_40b473e6c8', 'Metatarsal fracture'),
  (662, '3f2d55c8ed736c3a3404acb32d6fcb1f87a7bf0ff3bb226a1dc9838b3b8e44ce', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (664, '7a497d3770481249ce8f08c30256a3f2b82e0f441403eec45e053c3c2f5f50b0', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (665, '92fab5e70d310ad522f6f25e1bab4d23c8764ddba56709cfafdf96015b2d7714', 'dx_knee_contusion_94058fe1a4', 'Knee contusion'),
  (666, '5f66ff66b1d34f09faca0fc7855adaecadc12bf7ccf93eaff399e3655a0b5aee', 'dx_shoulder_pain_738e4b93f7', 'Shoulder pain'),
  (667, 'cb513a5bb36f5e70045d612edef57f97d914df17172da580ed4914740997a90d', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis'),
  (668, 'ad59c3d9bcd9378dc275a7bdb0f2f246cb193f193c818b31934932c72b901e21', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (669, '1d4ff5d363e1699000719426de3e2cff9243000f779481df4472f65b775409a9', 'dx_elbow_abrasion_fca1398b6d', 'Elbow abrasion'),
  (670, '62625059ffe9d8d7e03e3f4c735ad929f3b7d2b48a18c990d3b73c65a4142cbb', 'dx_midfoot_injury_3332895405', 'Midfoot injury'),
  (671, 'cb5b4c75ed667405e261919072ed25d58fcbc4e905c821175108491059848d6a', 'dx_lower_leg_laceration_5e3fbc19d5', 'Lower leg laceration'),
  (674, 'c2c389d9fca1c1f072c149fde94c5c3d0c1f879edb4ef4cbd8981b3a53f11b02', 'dx_thigh_overuse_injury_3d503881d3', 'Thigh overuse injury'),
  (690, '80d1cc261d708b34647fed67108ee2a29c759573ac3ad398bc52d044a7aee649', 'dx_concussion_a91e1107d7', 'Concussion'),
  (691, 'b6cc2b9d75fbf36404ab6700c58e5378339afe2809e59d8b25ca1a47fac35d80', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture'),
  (693, '47f207d985b41da04c961824a70080b04fbf3e9ec4cfac925694c1ff3a0de08b', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (694, 'b408586787cf8d16f07cd8fc73c83461da0f2b37ef913fe19a536ce62d6911e9', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation'),
  (695, 'eaf21c02e53de7d1341c4a6d76dd47d5b0232f92630aaec954512d0b7a97ba10', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma'),
  (696, 'e2119242858ccf50381edc55a2a79cd8bba724cd253466083deca49ea6434a48', 'dx_shoulder_impingement_c2f2a634b4', 'Shoulder impingement'),
  (697, '3e6bb8b43d7ed0f2daa39256a313e0fc18666a1a8e3baf2d949148618da50744', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (698, '1d6c47667771798d0c72d6e0d1bb6c659332be0d2d98fcccb07b5cd87b18d5bc', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury'),
  (699, 'b781344e263e3e81b3539b1192ed509f879be5623f430524ba7f3730cdea61a5', 'dx_concussion_a91e1107d7', 'Concussion'),
  (700, '426e9a86af966122066cfa63227c1d3525a7a8c5f7ce71e120b9c74cce042938', 'dx_head_impact_non_concussion_3feadb53e8', 'Head impact, non-concussion'),
  (706, 'ea36b3c97911c49ccc6df29b0122ee8247798fb256becf26172b8a9d112f3198', 'dx_knee_osteoarthritis_088b6b8911', 'Knee osteoarthritis'),
  (707, '7ce3ea08543e2db2f5dab3f703d36707370782574fb413e2e09b20bcc1c4648c', 'dx_other_bony_or_overuse_injury_b469c96cb6', 'Other bony or overuse injury'),
  (708, 'd2a64dcbc5828a876c15f6c85ff68fc090ba1c9d3d5278bc6376881f1f7c5cd5', 'dx_ankle_contusion_beb9f51162', 'Ankle contusion'),
  (715, '3e29d0e3ccf59238c4d127b72af8aed1f56e9105b1e1feff5016bbe71c59f311', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (716, '6ee48e68929b4504d69a283be9a55c782373602ddcafd83377651c074c8b1e49', 'dx_lower_leg_fracture_bfd7084788', 'Lower-leg fracture'),
  (717, '1d00b349a3f38e16cbef5d8b12d50e28b9c0fb9dea845cdcba3b221080468399', 'dx_concussion_a91e1107d7', 'Concussion'),
  (718, 'c9cf92c22c70305db65e38ab3458dfc84facf3d6ea869808ac8b500900e5bd8f', 'dx_shoulder_dislocation_2067688fdd', 'Shoulder dislocation'),
  (719, '6cfba53db0aa940db32c2bbb24b35eb11b3eba1ed0aa408387beb89534bb358b', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (721, 'cc87cdd74e1e2579ad3fdffed4ceb8d1b8bc72edd382e8aa6026ca04677e17ff', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture'),
  (722, 'b3a66a46e71e94b321ddcf9605412ac1eef510cb2b0b16d74f24525a06b615f2', 'dx_thigh_overuse_injury_3d503881d3', 'Thigh overuse injury'),
  (723, 'bf85076dac0bb4068c431c921e360c5a19c1334e300be27def7dc351aea6839d', 'dx_concussion_a91e1107d7', 'Concussion'),
  (724, '910d07f45eee5a5376c20c7b831a9a75cc3d5edef33d4677b0dec474ffe0adfd', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma'),
  (725, '19df31ce8881805caea4aa310eff36278238e84286d656b1cc634a43aa76061c', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (727, 'fc2c56decdc4494d827630591fb8e87c90566af87301c93e478ac16300d71eda', 'dx_concussion_a91e1107d7', 'Concussion'),
  (728, 'cbfc2ab04114b4132de7b7131d3dd73131ea67e3ac7eaaf55540558ff82f1df2', 'dx_knee_wound_7498252643', 'Knee wound'),
  (729, '683d235fdbf4f810fbe48a0cb989c469b3ea883470d49d1153b521207c260424', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (730, '91224588511b57fffe9e95787eca7270d8b936ec995565d623376a850e471443', 'dx_concussion_a91e1107d7', 'Concussion'),
  (731, 'b571be392093691236843f7454d3a1f17ad9e60365bd02487953cdb713693a8a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (732, '170a19cd524a6316862611fd591e6c8a5db0123041366c8580503705ce196fde', 'unknown', 'Diagnosis not specified'),
  (733, 'e9ee956176f82977382763e7be36e54f91186dad56957b8b68dd81e2e4e22bdf', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (734, 'f288237463e4fd57762c5dd765736938679ee4393d605164b0c47bc98e15f30a', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury'),
  (735, 'c02e15bb4b94e5d291aa3f420fe88ea9ec3fd18506c71f37d075c9b128294a24', 'dx_pectoralis_major_injury_ae7aff3738', 'Pectoralis major injury'),
  (736, '6f6ac8a783b85132275753640e71c63a8a4c05602bac131d0a2281319f10fe15', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (737, '68a52e9aa91f612102f8f084d0b53142645c3e440c3e49225bc30326ae63e2a5', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury'),
  (738, '676b1d5cab9a5c947d266d791acb47258762d27a3b19a857ac03ec66fae653a7', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (744, '6d5a53a8ab1f359aaa6119e7b587023167638c5e02d26eac98b9e2a7f8a8038b', 'unknown', 'Diagnosis not specified'),
  (748, '89aa00b5eaff4ea440c575474fe69e1d3859ca8359038ca5f16cd38341bad0b4', 'dx_thoracic_disc_disorder_9d9c895000', 'Thoracic disc disorder'),
  (749, 'cb2fb0130581ca7ab438898258b18a346f40a931a0070d1b282d1038e6ef7b95', 'dx_concussion_a91e1107d7', 'Concussion'),
  (750, '18a89abd16b6de25a0f851faab50d47b8614f9394598f14ee82d0549a0951973', 'dx_prepatellar_bursitis_d7a88bac59', 'Prepatellar bursitis'),
  (751, 'd2ab797a0e70943e3aaff0534f5f244fb504eaad1b72e094561be14eaad13ad1', 'dx_hip_and_groin_muscle_injury_7ccd814142', 'Hip and groin muscle injury'),
  (752, 'a5e382b110686addf79ddd4a9c3adaf94375ce10632165478f5ddcc4572e860e', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (753, '299e269ea86f1080bf04240607ec31eb8dee07c3bcc09942b9ae1242cb2ef4fa', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (756, 'b982c732beb851ee649c7ef257f3fe875e4323187442bd6abe930186970cc366', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (757, 'f269a4853a834dce72acc882b65c8772479aaf3f50ce3d31541a42b0d30e085b', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (758, '9dc92d930105b9c9ba996229669a7000a2efe1c41a3846100c70cb1eb946f261', 'dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b', 'Plantar heel pain/fasciopathy'),
  (759, '7877fae4a8291fd735aa226a8762313bf6bc6053b2c87194a27dc57e37b19cdd', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury'),
  (760, 'c15fc985e595588df25dcd991eef442d5ae724cfcf4340aa457b402c80beba65', 'dx_metatarsal_fracture_40b473e6c8', 'Metatarsal fracture'),
  (761, '3a9202366a199b50a160b0330a9c9eacbfac7ad8cec65395541e990f96bf9f89', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (764, '04f5e865062165c0199e73db4273b7d9cc3e47f567838e1409cac84048c09b22', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury'),
  (780, '279c4db376f34d99474b1d2da5c7baf0857ab056deaec650df6577c4b63bd365', 'dx_concussion_a91e1107d7', 'Concussion'),
  (781, '6e77948c8231b3e6a7c8b71f23c2b75c525a98683557abff882af49f5921013f', 'dx_sternoclavicular_joint_instability_f6b329093c', 'Sternoclavicular joint instability'),
  (782, '9d8ecbd2698b211b65b0e6d842bf79b58e8e4a0b119e65faecde81e8eec7c4b4', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (783, '7c6c7d154a74e6b12d5efbc3fa03efdedc628e67fc9519916e4c986ed5358b3c', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury'),
  (784, '6e136879c241f4e28dd00ab4a72b6c8ec27d214605d119e2286124aff2eac999', 'dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b', 'Plantar heel pain/fasciopathy'),
  (785, 'fe6fce79f8f4a6daaaa046f37264114a59360f17a4ddaf5ef2c7118d7f9914e6', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (786, '3dd06241e6f5eed4006d70db4aeb8602a8cb748276f9536e6753a464a204a344', 'dx_sartorius_injury_3dfafe7e54', 'Sartorius injury'),
  (787, '70e23fb8ad04bf448ef93c4a93252a596cdf8ba55295348418ab02c998838502', 'unknown', 'Diagnosis not specified'),
  (788, '2319eba01bd7cd7a87df2c92690a2671b1fbc557b9e80d7394f0987d25259294', 'unknown', 'Diagnosis not specified'),
  (830, 'b2a43d082b0de35b8a91b92f663c1231764e725fa9568fac89c7ff3f2bffa7e0', 'dx_rotator_cuff_injury_0744f75c4c', 'Rotator cuff injury'),
  (831, '6945604eaaa557672f0c957f19f8065725c052cd34c63f1e681f52057f6b8902', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (832, '844a3118edb927159d8c990ee68342500d535c069957efb44cf657bbbe2177c8', 'dx_finger_pain_0c38e0f81a', 'Finger pain'),
  (834, '6802b591749fc790144ae1278475c152b4e04651215a6c2253ada9346d668a43', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (840, '69492a4fcee3947f4c436f1d2b84c8d8af33bf9a9bac7503df517ce94357731f', 'dx_lumbosacral_facet_joint_osteoarthritis_9a909e3df3', 'Lumbosacral facet joint osteoarthritis'),
  (849, '136b5e3b3e0deb9873d9d9c7dbbadec9f610e2aa05e7f06232d10b3e09e5c30e', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (850, '32d7420e78a320283a0fa512d586ea74d1292ded464f3dafaa81ea2e67679467', 'dx_neck_muscle_injury_500aa507c9', 'Neck muscle injury'),
  (853, 'befb874b1b3012f33397438819574a713cb0c7883401e15a9781b065bd56292f', 'dx_neck_muscle_injury_500aa507c9', 'Neck muscle injury'),
  (854, 'ad71e6b7fa4d90c9bcd66e2703e18098cda00785bb7bed130efad1b392572ecd', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury'),
  (856, '81c02562b1db255de1de20af390b566f118dea93ae069ca533d25a81a49f8b19', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder'),
  (858, 'b69b4fc0b355839712e50398f8d64803d7056714356563aa5887d88a6fa4b82f', 'dx_shoulder_impingement_c2f2a634b4', 'Shoulder impingement'),
  (860, 'caa2ceeabe2f8f0360def3641a27ad5b65ba57d6a3ae3ab0640d318cb33bcadd', 'dx_metatarsal_fracture_40b473e6c8', 'Metatarsal fracture'),
  (861, '41e13f04138918ed8c91a04eb844354aebb9b4f57a60c0274cd8fd8ef30b3694', 'dx_foot_contusion_6c8a5bb721', 'Foot contusion'),
  (862, '77e48dfbadf251ec5d6c3e955f418ed70805d7694b295e7beadd62ca67aec536', 'dx_groin_and_hip_bone_contusion_e0da41307f', 'Groin and hip bone contusion'),
  (863, 'ba9dc58a06f1a5ddd473033c958abbe91bb86038a6ac5975202b2df7df8db135', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (865, '2287a3546a562a03e4b89ee745ea1f1b3e6ee50063eaf8e9ad0ce9ffc4ac3435', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (866, '5be018c88f657c6e832436d511ed8b4f04ba1e756ac2423ff5a23a471779688c', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (867, 'aeaa1e15a6385d599437bf13400058dc492d042097516991adb4da3d80d7faa6', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (872, 'cf96930984a359f451ac29d670b59f2789cab55545709c66e344f444961f3612', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury'),
  (878, '1d1deb4202e5d50c45ffbe430a4f5332c3821e538bfe84cc5647029609a03d0e', 'dx_concussion_a91e1107d7', 'Concussion'),
  (879, '1d3be584c8666bb07f093a7d577ae4265e4fa9a13fa2139db78a8211122842fd', 'dx_concussion_a91e1107d7', 'Concussion'),
  (880, '1ab957dfb00d4d62e0c34ee4810b7a1cfeae652bd4ef6f971509c99c6c84959c', 'dx_concussion_a91e1107d7', 'Concussion'),
  (882, '8beb2f5806a2d25589ee5e1e8ccad9e9a49fc1b9f5f3c8bfb6dd0bc36c5c2670', 'dx_knee_wound_7498252643', 'Knee wound'),
  (883, '41184f8b237454559cd63b29f648b15e4913e1ab86b3a6d011cd3c58df3846c3', 'dx_knee_wound_7498252643', 'Knee wound'),
  (884, '2ca0b85f314d84e769d785e117dd15aaaf85ff3175560567b9eeddb29f928d8e', 'dx_neck_muscle_injury_500aa507c9', 'Neck muscle injury'),
  (885, 'b94fa1cef34d9a2328bd08b6689787d095e71b5a3ad862ff04d6c08f94aff10a', 'dx_neck_muscle_injury_500aa507c9', 'Neck muscle injury'),
  (887, 'e8862390f3d7b120533848e39b0f1b3789fe18a05f42dd39f66ef9bffe2b1868', 'dx_lower_leg_fracture_bfd7084788', 'Lower-leg fracture'),
  (891, '03ce87f27054e319220c020ca9938173cc1a39227b3823b2569eef92f4a1b175', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm'),
  (892, '24f809a59007a8ad3a1b96517f467592dfa1f8033c944ceee02af4fc5cc86065', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm'),
  (894, 'fec911d02ba5cd8442f2f1c39026d94f4e14026c78a614d7cda942674b5b355c', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (898, '4c64ab1228ace456e135d0092ce94c9dfaa0770cdb9f3b843b966b92e11e565d', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (903, '34c71921c0671158219ed1be817a6c3a69769317f791de4cbf6aebe0ba177f0c', 'dx_knee_contusion_94058fe1a4', 'Knee contusion'),
  (905, '2d645d4969718ae4c9ebda0a9fe97cb5e79eb1931004671637b5c73cae5f63e1', 'dx_hand_bone_contusion_fc017abdce', 'Hand bone contusion'),
  (906, '3b18b225c5bcd27591d03bbe363b83e2383ca5d26684fe2bc348275624676e7c', 'dx_leg_soft_tissue_contusion_or_haematoma_2264434fff', 'Leg soft tissue contusion or haematoma'),
  (907, '83d3f15d18a12aa9efc93e088ed7a9c56e150674228dd2ae71ceedc2b7932a49', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (908, '6e44ca9d32c9d9248028bceb24beb51e6c844b91ad9d757c0c202d2bff43ab63', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (910, '74fd94544065ec4464acd72a87c3a87a8b1b6a011855d2fa904d8df928d1133c', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (911, '96a0663750c41d93f4ffffcb01fcc7211921813fdf9dfca5bdfd0cdbbaea74cc', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (912, 'ae3165e58c667f1e69c1d24ef0cfb052bfe772b6d805f0c21933845f17bea4f9', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (913, 'b3c765513ddbd219dcdf08e4f72ff8d830198c2fa8e483eeceb04f4cc6535a05', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (914, '4b0ff48e38465cdde3bf955663ba536fec22be57050095e626eba85480b83e2a', 'dx_midfoot_injury_3332895405', 'Midfoot injury'),
  (915, '9bcdf9c025ebddb9ee5c0bea3abba7b1f3a5b8cdc56294496b4376249543d351', 'dx_knee_synovitis_impingement_02e229b1cc', 'Knee synovitis/impingement'),
  (916, 'b1374f0f687159d8b4f356dce3e86322936bd416e1bfd81b2e9ee875b52908e3', 'dx_spinal_disc_degeneration_850a87dc5e', 'Spinal disc degeneration'),
  (917, '4e2731e147cf8f921d16312ec8a49bdb3b7cddf693ce280e1fefddf083b07a0c', 'dx_neck_muscle_injury_500aa507c9', 'Neck muscle injury'),
  (918, '44c24ba623d33a0ab14858f039d8b30e7bfbf6e3b827c24e20f63033d995314e', 'dx_thumb_contusion_or_haematoma_7a219de27a', 'Thumb contusion or haematoma'),
  (919, 'b7a22844a3ddcdef0aff0d620e239901f34e4a06bd522723c85969b95593faf0', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (925, 'df996d49bd409d9d505ffd693596720a33f2c59a5d17d8a594bbae371c1acbd5', 'dx_groin_and_hip_bone_contusion_e0da41307f', 'Groin and hip bone contusion'),
  (930, '7d557e7d3b93a6b31193b2ba72d9f2ad0fcd838242650d0e61f87f4b87d8d74b', 'dx_shoulder_impingement_c2f2a634b4', 'Shoulder impingement'),
  (940, '3aa482d52e777b45868c57247aa45be9852fcfb8c4278e3f7bca137a31b03955', 'dx_elbow_injury_7100f71f81', 'Elbow injury'),
  (941, 'c4fdedea98a0d0c225e843f4f8eb99fcae45bfa53769e269d91a9c37807e273a', 'dx_foot_bone_contusion_62bd9ea576', 'Foot bone contusion'),
  (942, '4adb33d499f8334ed5e932a652f2b3206e967e5eb7223a3557eeec0f46056631', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma'),
  (943, '03f1f095a2491cfc42d043e3acefb04d05e0e2e8de4a4b76342d6df0a2365759', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (944, '776471337a370bd08d04098630323136b303a6ec2e52faa950ee85abfeefff55', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (945, '0700a84e1819f31989191c702655818a43b09225e47351f7fe7c512a4141f9bd', 'dx_head_and_facial_contusion_74a20a767e', 'Head and facial contusion'),
  (947, '65c2101ecc54d906a695ef2dae1ca12d793184468ee223ee21413ced9143af81', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (948, '9ce15ab06397a16970e7e623c189cce3cc66ff13d6302288bc13ce7e8eb2b3a6', 'dx_calf_muscle_injury_0b80e5492c', 'Calf muscle injury'),
  (949, '5c6a8d5ac24b1cc293ddfd676b846533b07b94ea673fe3c7bad08a3347401fca', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (955, 'a6d8c925f9d5c00d48c02a5f16bbf77bf0f65f88929fa019f67bbebe4619390f', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (956, '7aae7b72bc2afccf6ad7ea415a36b28dc2d3f0f614479f167886f933a97e08e5', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury'),
  (958, 'b3e5750ca25884c04baf20b28a80e5721dea90aa8c9f2bab9663ecabcd16704f', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (959, 'e6ce14ea768f27e17ca6aa44c64b3c958b3ccb1f102bbca6c41cea42b5709a99', 'dx_head_impact_non_concussion_3feadb53e8', 'Head impact, non-concussion'),
  (960, 'c36fccf2b5d08371658782b364051c6cc30296f3f1ff49c171a8f002c9b055d0', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (961, '9d0a03bfa3f98ec7afc9ce891b52889acf648279421902b1af22e9413d65e861', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (962, '64055372e84e86f29cc1ab08348694be3db0a2a615e608578c7391d0f79c0794', 'dx_thigh_laceration_or_abrasion_cec8e820c4', 'Thigh laceration or abrasion'),
  (969, '34619f24e7b2b98ed78789e4366a9d2409d9d84e9b5db2f554da0a6b3230dc47', 'dx_hamstring_tendon_injury_f86b1dad5b', 'Hamstring tendon injury'),
  (970, '8a37e5d95125228ce0fcd0cf1c3e07e2982e531f9d540e9bdd72089c0c87f021', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury'),
  (971, '7fa71e7e613512d1e2ad13289d8798179f4273b4959ebc9ae1c222c5f14b39da', 'dx_thumb_sprain_730d144cbe', 'Thumb sprain'),
  (973, '70cf2b156714c28aa7b861f7627ab4c6b946d3bb1289fdcc4234f95a54038f41', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (975, 'b1fe9cc95141a18d84cb037f97a8659b69d25c296369d19e521a3ac547274de2', 'dx_biceps_injury_69e895b576', 'Biceps injury'),
  (977, '634121055319a731453ddc43dcb862d5e746559eaf4d53025c6f7262c1cd57a0', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (979, '8f04f39aa137d1485a58802dc112fa17269b1811d929ddcba08c59aadf00e6de', 'dx_mandible_fracture_c2163574d2', 'Mandible fracture'),
  (980, 'ffe427ea8d8917dbbaf09873c91d0a0dcdcd0c5521b39c8fcea43e50d2188c10', 'dx_knee_contusion_94058fe1a4', 'Knee contusion'),
  (981, '32bb681ac7bb89af252013ff67149206de72bdc25531b57d7092fbf9b961d2a5', 'dx_calf_muscle_injury_0b80e5492c', 'Calf muscle injury'),
  (982, 'ee18dc680d1dd556b447e17d29072d146f070a747fa5e1aaba283ca38326dd4b', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (983, '7ef9040d850c5633f117507f022011bc1ee80fbb1c27dd7a85140dc3871d8b45', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (988, 'd2107f3557a5cbd4f7281953f4badaa4bd1b1ac600cc05f1428512d14703a5ff', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (989, '72ad341413f4b38d11bf89fdb83dd89f027fc8d41f9d0a90ecdb066b5800ba7c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (990, 'bb728e7205c306c9b59f0aec1bb89073c1d3c4cbf945b320f65602fc27045b2c', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (999, '1962d052fde01c8a337c4765c14409c1f4892f679781a3758dbcebfaaf838c4b', 'dx_flexor_hallucis_longus_tendon_injury_3ae59d52af', 'Flexor hallucis longus tendon injury'),
  (1003, '2382b64aaa755d179479b416b94ad391edc4608a43fa7a23589f77a5bbbfee3a', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (1021, '4d772a4129d70a8379dd64b59a474625dc6228a7b0421792477e68446295c343', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma'),
  (1022, 'f37dcd59c69ef250e321439770795537829f410ef43b229209ad9eece0c33f14', 'dx_knee_ligament_injury_unspecified_7ab630d44d', 'Knee ligament injury, unspecified'),
  (1024, 'f52077ecf552b452daeb8bca5b31adfb615ac097d70676dc1d5c12bda264371f', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1025, 'cba7f6d9686c4e2b489abcc00aae693c1aa5a45928419a70f5117507d2115aa6', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury'),
  (1026, '273612101dc7c28deacb29b17cad0c17f96472a360f1a26f6567826ff97b9274', 'dx_popliteus_injury_0ac29f0573', 'Popliteus injury'),
  (1028, 'cf4712bdbde99005486c04f8bf7ab8a8f8658b0a453369206df2dbad4fb0ac6b', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder'),
  (1029, 'b624ec5cf80aff74b3e53377964252bad45a5ac460fbb4698e943626bf41a7d0', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (1030, '82c99855a7cca3c4a64b130492645356b99cf92c2fa7c04e57bd063691aaf3c4', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (1035, 'f86501df99d436c4103f3698899fe2068691560d67ef5c419e4067fb3ab6eef4', 'dx_heel_contusion_4009d671bf', 'Heel contusion'),
  (1045, '02bf5292e64b6f9e91bf79c9f0784240181c3b441b700045e83bbd537b0d4e13', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture'),
  (1060, '4659e074aaf9007ba2f6766673c379384ccfecf7b2d1afe5187cbaa8f0720811', 'dx_piriformis_syndrome_d562318818', 'Piriformis syndrome'),
  (1062, 'baa46afa7e597dc4dd9f2d0f89e7cfe6aea2ce60a9c1a12757610ceeab0a8167', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (1064, '6757feb4def5b5427ffca3cc06e40b1aca3940a6add5d4e9f739f9f89619b0a2', 'unknown', 'Diagnosis not specified'),
  (1075, '1445f08e3e8d52e278db8d9cc50aa5c38c9c6b21f85eb37d23f1245e4543cf83', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (1077, '52b14dbddeb41497ac29430e78fb908221a31f28cbfebce5c12587ff45d84e06', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1079, '478bcd4de927856e092121578635235f7690aeeca0ee0b23978e4ab48aacc7db', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (1081, '21e05784e859d3e92441cf3952470d525f04fd8c084d4b4d492c4a4b7eee0aca', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1082, 'cbb4e972a7002da6f50559e07bd86ef8862342588de84b5e4114ed3324013767', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1083, 'b6b803d885af396fa96fec1a7115ea105d3807b50ae734eb6b71030a24fc21a7', 'dx_popliteus_injury_0ac29f0573', 'Popliteus injury'),
  (1085, 'ad5178594fb0bb73f6f82fcb40d727f4a8dee5b61a7fc5f0cbd7ff2ece2fc85d', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1086, '942d79a67543ab141a6c9e0b3463574f7adebd86f7bff25b409a467f1f57fc35', 'dx_wrist_fibrocartilage_injury_fddc60c8f6', 'Wrist fibrocartilage injury'),
  (1087, 'c2da84de78c25f80ba0c7b28aff7c9680cbf7d66e1c79712dc148cce7c955185', 'dx_orbital_fracture_a673b31938', 'Orbital fracture'),
  (1088, '27f2a950b5a473a97d8fe0cf7dd6edc57fd0e39124d9f23ef19c51a99a40d75d', 'dx_neck_muscle_injury_500aa507c9', 'Neck muscle injury'),
  (1089, '5ae0412fd3b65665fd4493aaaebcc1142fa599b126aec693cd231197fcdd985a', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (1090, 'e7c092d88137b73b3edd8d64ea17dc11a03c7f592b04aff8c2c0ad59048e022c', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury'),
  (1093, 'bc1f3dea20f85846d2b4b26e28c520ad6c66177932e867ddd15cf651226d41e8', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1094, '6133103b83687346be383d0153dd296299d7af0acb49f7e26edbad01e82c1a95', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1095, 'deca005ebbb5dcdac53945014d8e37779823c296c80c0af7b17bbd643f12846c', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (1096, '7d7fe393d195020426888c080a4a7586f3ad87cff7df75aa507b5b63752d9507', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury'),
  (1097, 'd6e722f885820df520ee74f8ccb4888560996a0e17beda99cafe525d182b38da', 'unknown', 'Diagnosis not specified'),
  (1098, 'b0d0b8af29bbbdf180e6bffe3e02d135d04e1a486e025d4625f118780753a0d5', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation'),
  (1099, '774c003846abe549a8c91a84d192912fa4b9cadfe1bd9c12b770f70b22dd6c5c', 'unknown', 'Diagnosis not specified'),
  (1100, '81f2985ec1e35cef7c00fa79dd4c8bd720cbedcd145218125c4930432261d6c8', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (1101, '594a671f868eef2dcd550c0eeba8bef41e5636e2b3fb3d73c7d96fcfe7681b62', 'dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b', 'Plantar heel pain/fasciopathy'),
  (1102, 'efe71ac5fdb0ab1a9be94f55eda7d966913a65fc8273688f757ecdf2dd0decba', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (1103, '14bc9994cfc023139437c015ce44a7633fd2b450aa23e033598ec6102ee2a5dc', 'unknown', 'Diagnosis not specified'),
  (1104, 'a4320ae82551637db55338e42d351ab46e558f53df727023aa18a7aff720593f', 'dx_shoulder_labral_chondral_injury_4ddc56b103', 'Shoulder labral/chondral injury'),
  (1105, '8c74fab48ce8cd5ad8253b418f1ed8b3dc53e97fdb7ef07b54b01f9703326b3a', 'dx_neck_muscle_injury_500aa507c9', 'Neck muscle injury'),
  (1109, '17a58ec1c4ab53126ce6ac3d8867dbe1111ce7c9e24a6be0703c0dedadf0ba42', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury'),
  (1110, '02c7e2e592d54ba70cf8680cc9cbe34d5b02617da8e89f5ca68efad8ec2a654f', 'dx_chronic_ankle_instability_ec5aa4a147', 'Chronic ankle instability'),
  (1111, '6ae90b81ea793e3b4752f8959727088f9cc22ae1be0b86cc4b5d02431e5b53ef', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (1112, '683438318abb46ab9c4793f0ffa8ebbe20cf8c1ad8d72eb2ea3a9d18bfceb1e5', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (1113, '254adb43a683092d3b0d3e5b7c15c1670dce0fec2ddf29be6948741587b4e0ea', 'dx_popliteus_injury_0ac29f0573', 'Popliteus injury'),
  (1114, '28bd41e645034e8b5746371f40beebe4704f40419f44a36bf1d50b140dc8b1f9', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1115, '724b8f23ba6a2049479ef5cd11bacb8983d44175102853646895f0872712ca80', 'dx_acromioclavicular_joint_dislocation_8954e719a9', 'Acromioclavicular joint dislocation'),
  (1116, 'dbbf5bf47fb7bf8c07bf343384d24dedb13547357435d478a7e828fbb37453b3', 'dx_supraspinatus_tendon_injury_3840a1f333', 'Supraspinatus tendon injury'),
  (1117, 'eb475e3969caf0cabc5894687141b181c68027fccd78fce1868ae6c0b1d3c418', 'dx_neck_muscle_injury_500aa507c9', 'Neck muscle injury'),
  (1118, '640df3d7e7d4fc28011d1e8bae5cf2760f7e5a5b7bd4974f3059f03939a1fe5c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1119, 'ff00b90201ea45656bc0335eaa87f80ef3d5be9aff2fbe6e17f1c271bffcf4a7', 'dx_neck_muscle_injury_500aa507c9', 'Neck muscle injury'),
  (1127, 'e1f6a5413176e02df6a405e1ab95bad5da61527c04d1b35f265391ebfbe8461f', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (1128, '0862c71f0d67fa8538c5e434d898ab521e4813b61f7ca3f865fae42a534960ae', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1129, 'edaf2d5f36a6fb34e430ff229d88ef9aa9abacaf16e6fd9ee5a7f7718c5a9c8e', 'dx_shoulder_labral_injury_c99b83bba8', 'Shoulder labral injury'),
  (1132, '971c707cdc18b1099782b7470d61437f09d8a6a506dc88209ec6293aaf1c7f0e', 'dx_hip_and_groin_pain_27531edcc3', 'Hip and groin pain'),
  (1133, 'bc3167269563bde52f9b6f59e80f11d1fa5f9ad4066e4db5796706b551767559', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (1134, '828db79e0d0c0bdfb3073c8dbf5e04d28f443d291e62d25f4350a1ef8503acf1', 'dx_thoracic_muscle_strain_or_spasm_8b7d429120', 'Thoracic muscle strain or spasm'),
  (1135, 'ce3ae80f50345a72b086d8468bf15d3959d16bdeb2ec4216851ab08442354d37', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis'),
  (1137, '7fd0a5b5e98d851cb5e02dcb76207aeb9a291879cf203a3e2518a6ce66bf347a', 'dx_shoulder_labral_injury_c99b83bba8', 'Shoulder labral injury'),
  (1138, '511e116999a17058354bac3e2d227ae8dfa74d6eae0c63daffd2ce1d1ac470e1', 'dx_cervical_functional_pain_e11c275770', 'Cervical functional pain'),
  (1139, '0a1c7a37102e327b3c30a3c23b6d5662c32a1e9ce9098586c11825666a0dc7d9', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1140, '6ea435d47a61bb7e0dbb37e77b63fa660649a95441cf984ba754ff39628b83a6', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1143, '8026e40b349ee31a2fa7c52c986b10c5002caa2cfced5967b17c4669c4289190', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (1144, '882aec180808d3c16f1ea41f3646ea440160280a20ff521f4d57f09fe6aea1a2', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (1145, '7d2547fd68caa3ea1c2dd3fbea5763d186a31826b3d5e95bb7e7d8a708696218', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (1146, '61166bdf842677c993870a475b546039b491a2eeea0137791b5f2c6a213d2349', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (1147, 'e3d433eab7809a7716c5549fe69657cbeceeaa9550439bb978e64b1c79c8a384', 'dx_head_impact_non_concussion_3feadb53e8', 'Head impact, non-concussion'),
  (1148, '4957da2d3169ca90a183b7706fce26665d56571d3ea8e8d91fa6c186dd9c5356', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder'),
  (1149, '64d3328f9118626203df3d532bce36549fb2d90fa3a2baf592c773c067a4b8c9', 'dx_lumbar_muscle_injury_a7fb20b2b8', 'Lumbar muscle injury'),
  (1156, 'bdffce7019fa10ce45e8142fc883410baa2b260ce0f5268992d0b81b28d8737f', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1157, '130ca359c15ccf3709bee3f48b77ffa0a600e33ac029b7c3078cfdb31664b9e1', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1160, '417d4bd296b852d46dd76948db90eacc23a651a3f3849aef563a9d2c342bca55', 'dx_thoracic_facet_joint_disorder_519c2ae5a8', 'Thoracic facet joint disorder'),
  (1166, '21429873b3149d52efd300fddca2e65f73ad4e8065588f457717876adf9e927b', 'dx_tibialis_posterior_tendon_injury_8ddfcac54e', 'Tibialis posterior tendon injury'),
  (1167, '559af2bbdae20fe343b79468cb2fb1056c5fcbee55a458302210d0734511b3de', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (1169, '09279f0f987ec75cdc30110a134593120265a59f18ae6b5c1541eb615756a42d', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (1170, 'a8918663981045db8bc21f328a75552b6996fe72d05b63b22f49baab0a40d305', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1171, '835c7ed7916fb226c737c201ddcec207ed707e27db956fcd54a4a6516597fead', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1172, '6428368c4410cb3e7fc6bb7a262bb788af3d383c467a689c76f8a886a995d6f1', 'dx_chronic_ankle_instability_ec5aa4a147', 'Chronic ankle instability'),
  (1173, 'ce269305d630ad82c220d34a38aa2af8f092707f637ce525e443f2a922f3c9cf', 'dx_neck_muscle_injury_500aa507c9', 'Neck muscle injury'),
  (1174, 'fcb00d6c20a8ac24708de5bda45419b51d68258c12eb5b3d9e9d3b57f6c9047b', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (1175, '1db7edb2fdbfd44f460e8e8cf8f42d61605f431dc4c87aa6c0d51882f4979f48', 'unknown', 'Diagnosis not specified'),
  (1176, '317a9f0cd8436cbcc858eec3cd0a40d3e4213085d476ef7f303f51e7e0a14c88', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1177, '9457c35ad03744ecb0abeafdaa02bd4cb2800f2bbec1b5891db2db6a8c5c7e78', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury'),
  (1178, '3e649e4942a4f8ab393f542f58a56e4b0d43b1d1cb3de11dbc6d8f936b83a920', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (1179, 'fa0cda7313570e3e0ced5a718bdc478486e01c9e0a631a35f4f161ecc4712a8b', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (1180, '9b269f72989ce92e97e92df9a70c1042db23df596c8476b062797e55aaf8fa6f', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma'),
  (1184, '966eee628522c494d58cf783a230daa62b24972bd008bbeb2915b7cd29623675', 'dx_thigh_laceration_or_abrasion_cec8e820c4', 'Thigh laceration or abrasion'),
  (1185, 'a07364ea60a1e20d159c0272d76b9b3a276c2edb2db6fd737e08dddd28cccb9f', 'dx_knee_multiligament_injury_153dc1f5ba', 'Knee multiligament injury'),
  (1186, '211f448fd6cf4d2eee2254b7dd5f88dbc6e4c20747e22a7c7ba3bf08221bc679', 'dx_forearm_pain_5cdc1ed996', 'Forearm pain'),
  (1187, '3d36570bc90603d42543a508a300faaab799971febdc9b710e2606a4f4a3bdf6', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (1188, 'c45e85c53d27e4d29b49610ab3f7ad235ae9411511c14258d366d288c22e2375', 'dx_temporomandibular_joint_disorder_d15bf1f47e', 'Temporomandibular joint disorder'),
  (1189, '83530d9833bf338207d01a57d53f78926f7843b743e8e1f20808f4fe0b7cc131', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury'),
  (1190, 'b5a3a8c669dd2aee1d678d1bbd0a2f6a1ac31241c8c5e2b0f5c637ef189b9945', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (1192, '77399cb6da621986157a6fa9399e74f5705409a3ad06235d4783f5b9d8ad212d', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1193, '7b73802529c991f28ab40e9925b169ea16eb9b2f1c562edde19dd2811adf0ff4', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury'),
  (1194, 'e35faf22ae7725bbe0bc7c2ebe27b7e0421b0ee40d28bf575c57be0b4c2f0c19', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (1195, '7aaf01dea618079964c91a708170299ea5ab13ca5190e8f256a8f00ca9a2e7f2', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (1196, 'd9ed5ae9d3451b27c4fc7f62f3d4c4ff000ace3402d358b405f0bd36d466fca2', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (1197, 'e8f30aa91b35c4dbcc04a4204e280ac82d679bd76a3e37ea193bdb6bcc908d6f', 'dx_wrist_injury_d94414e2c6', 'Wrist injury'),
  (1198, 'e18c56256507382ed20e5edee88f5e1d01d69940d6d74bda4a911308295dd420', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (1199, '09d284c059fedba0e55c65becf9c03b6bff558aca1e80dd841ebfd3dee373796', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (1200, 'd1e0910c7c7da82c31f7e934ec0f7c79871d2c21a7ba5f860198d88e829bc5e9', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (1201, 'e11ff9255cf86917f06e26f900c63b94468c31cad3338e8decff5e699e14d67e', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (1202, 'c4364efdfc8fc8640a8f6e46480282a6dd4f84c8703fb53eab0e2347e8193bbd', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1203, 'a679dc3e1d4a376285eb7bb03627cbfd9c0b6ea6fe6103ac4e00d7bead622896', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1204, 'c9faf09e345afd2f5ca8723650e234c3a8f18876e376a6f4f6a9fbaf0dd43fbf', 'dx_head_and_facial_contusion_74a20a767e', 'Head and facial contusion'),
  (1216, '803781abf3411a3deb3a6709f47e2406f468a57a954fb0c9d226260f1ad2008c', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion'),
  (1217, 'dafaeb2a94f8ac366db6abd06e95ff1886546bfed25428b0c7257ef95181c866', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (1218, 'e71f52521ef24d616ada5516a22a339f27e0a4cbfea55014d4d884b5bb46e167', 'dx_forearm_contusion_ea321e8e45', 'Forearm contusion'),
  (1219, 'f56471eab549dd7369a439cc5b8878982d6b216edacae83f6990ec7c38bcf6e3', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma'),
  (1220, '0e6712f81f2c40c528ee3b8c89a53fc35c76d06d396ca3f5f9569ff6c23ae0ea', 'dx_neck_pain_58ed6a0781', 'Neck pain'),
  (1221, 'd9e5fab2f0b506dfd93d79f4301c7b761a5fbce32866a4058b40abb7af87707f', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (1222, '3bb937f41546adfdcdfe086a6830bc3264d55180f45e718fe9bebdc62a820b35', 'dx_knee_contusion_94058fe1a4', 'Knee contusion'),
  (1223, '3174e8163a73d877b0b45b4219a7e021f4ecc007ec10ff457468b3e3c604833a', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1224, '665711065f3465ef333d3f75e4420d639e4b011e219bd85a004ac67eaf1c1d2a', 'dx_hand_wrist_laceration_or_abrasion_35c31d7555', 'Hand/wrist laceration or abrasion'),
  (1225, '05f9e23a80012ed801a724d3e0ca9d47666328e029e73712ca6a5e14c1eed64b', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (1251, '1ce8badc9b45e8c041969f523e5759dac03933703af86ca0ffa61621557c84f5', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms'),
  (1252, '372b5fb9691b2366f2559f41a7f826618eeffb0200819faa496bb3134adb9b30', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (1253, '0050357f1734aa3c9bc488d8043a9aeb9d324064fb0c596ac837a427455ba1cd', 'dx_spondylolisthesis_4fff227886', 'Spondylolisthesis'),
  (1254, 'f9975f4261c400cbecccc7b1f82e9bddd535c9517b3a03b36575b3236fdd4484', 'dx_plantar_fascia_rupture_dbe62f4d0b', 'Plantar fascia rupture'),
  (1255, '10e454bb35579b9ee0e8155a5269af71741e6e981f375dd636955096e695cc17', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (1256, 'ce2d37cd22352c5b2ca3aef7ff16cd1ce6c451e802e423887767c4e1245c239b', 'dx_neck_contusion_7f04c7cc90', 'Neck contusion'),
  (1258, '33cf0f5648853dc01cfa04634ead250e13a99fb79467f86b4ab2597cc922814d', 'dx_cervical_spine_instability_658367d444', 'Cervical spine instability'),
  (1259, '575a80f1c49847dfac018fc46066537fe4a5224300f6b9f273d25feeb5ff1a32', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1260, 'd66959bee95b41bda00c2e38ea02762736659cda1cb89a7de5437748ce5bb915', 'dx_wrist_ligament_injury_6b21f37d24', 'Wrist ligament injury'),
  (1261, '432e3e785e750354ecbcceb59d9b626b75f51431292c1f4377f67572be32704b', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1262, 'bcfad6cddecf9dc3ea622a01680c1cd8fc140329eb50f1bf8b03578847374124', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1263, '9318cd2c2b955565fd59caba779d81534e4235edc26ed973d722bdb432c78844', 'dx_hip_flexor_injury_cedda9fa03', 'Hip flexor injury'),
  (1266, '8097ddcc91246fbc6b0437b52b600640a0f42c65ecfbfc35562bd0de1572c551', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (1268, '5eab959acfdd1bacf90596a9b560a6d49f937487234264e971cb4fe3a84e35f4', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1269, '1802fb58e69d407b0b93c9fd7d04bd2429781024b751af14231e863535aa28a0', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (1270, 'd5c771bb224268e8404f1866132d9b8e4ac499e5c22e38de47efdd4cee4606ae', 'dx_dental_injury_b97b2afe75', 'Dental injury'),
  (1271, '85b1624f56c40fe267d05025d9373546c5369a69533ec29fc7517d31ff66d30a', 'dx_middle_finger_distal_phalanx_fracture_05d6aac876', 'Middle finger distal phalanx fracture'),
  (1272, '8512590f9be2de5ceaf37d190855eb54dc753a68b7e084eb356ca77f5756f131', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (1273, '0524cdcf7bf8e89c9fa546527b90d02e13d0c3cee80ce68c66919a080aef79b7', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1274, 'd15240d009fcd492700bf6a6a929094bf208e7650c2e5bd716c78c3d1345d6c7', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (1275, 'a4b932fc5f5bf2a9c876e6314e9788453670c65225756ad0d055abd46afffe07', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1276, 'b1bda002dce5e40149ab5cf2fca34c1bc24df4e5f1def822c1274fb5ab6f7833', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1277, 'ad070221f132cb58e95c5dc90dec19e0c9b608e5eae5b5272fe0cd320a3b8f5c', 'dx_elbow_bursitis_24fdbc7698', 'Elbow bursitis'),
  (1279, 'edee76c7aa695dd8d21f2b0b07242bf2b74ed7acd5b131fb83f53b23f129390b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (1280, '6b81c02d7959cffb9d0a3889a8e7378647522d37cd6885c95df0147d69f069c1', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (1281, 'd3d181310d1e586d8a487d65300618e2378c0fb36b39b0f30a496d7f4ccf06af', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury'),
  (1282, 'ebbaba03c662adebe559cca6007d9edd10ad58751f69e0199b26c4c2236e8e11', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion'),
  (1283, 'c2eb46445ce1d4a604676ea517d8172afd0335eec2c05688cf0c960758fdb4f1', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (1284, 'c95019ae2d792b0eb5e0632eef97b2edb23592a47e8fa8331b585c25d5885cf3', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (1285, 'c9f8c5fa757dd636f1750fd3582ed932f8852ed60794439ee6513931cafca8d9', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (1286, '223831c65c02e2d6ee8f3851db595d29a7f622236cb2b2696ad610ddabfddf6f', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1287, '507db7b54f9a2b84457a8dfcd18601d2904ceb7343eaee52464f4f868a97db47', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1288, '55da64258cfc880e7559a48bb772e97f2f1b204d5118743822554a439fb54c20', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1289, 'ba3f1b965b5e26e52af55da13740a746148b6d5518a12aebc14c829946898e0c', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1291, 'a668d84bfff36081fa6aa2d769942729c424849b52fc85d4eb84710cf9c66e30', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis'),
  (1292, '2a79453811e26178b91ec3f0b765ea7813d08491d1128bb823d66051dac181aa', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (1293, '03782a6786989d556429e645957e3c5ef3b82133a95216446f71b815a74eda22', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (1294, 'c334ed6082414356a9f3b3546a9e7c764f3739d9f9efc41a6cc96ac820a483f0', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis'),
  (1295, '72507e179a6015d0b2092701bcc2205164222b9e26da878bcbf09665106af3fc', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury'),
  (1296, 'd2da01841361ec5df4d376138121a64a9aa8a7bbfa2d8720f0bf48145b214777', 'dx_cervical_spine_instability_658367d444', 'Cervical spine instability'),
  (1297, '36f9aea544f6d97b11f220a83b77ad89a1f4b4a8f9aafc9c0c202eceedd3b3dd', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1298, '8932e5a115a5dbdc994786016ac94d6314ab3553539b708082c3b54b17826c67', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1301, '1d543171bbdfad48316486ed5cfefcc31e54cb65d1d3c784c6cbe0b6a5b3006a', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury'),
  (1302, 'e96ed0dbe50e4e794781820555c3b51adbb5a9e15d23532f8c4312e89af206b6', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms'),
  (1304, '0f882c0709dc1da56461196dc050b4d748fe2c97df8fa7cfd54e22a789fdc189', 'dx_shin_splints_88d33d2fb5', 'Shin splints'),
  (1305, 'f412339d261a78cf3361c9df3c8b787b89e4cfe164018acc87a0229ccabf7df7', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1306, '8332c1475c3100a489ba08c00150af3a6de816a051fbd3a11fb663bde7d46413', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (1307, '7cd01ef7b5508fbdaa2adcc720b2a5cf5b68890f8286a0a96e24298823875697', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (1308, '7084c57ca5a6a3c0ca82066397355e716b0992f92e833c4452a3a1ee84de7d38', 'dx_foot_contusion_6c8a5bb721', 'Foot contusion'),
  (1309, '554ec5489920e0f402dc7d890a0ddd02cdd1f8418ea954585c6e287e5e607696', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (1310, 'e7378cf5b55e9865928bfbab36730e88b2463bd6832fda0d0d55df9db0ce1151', 'dx_cervicogenic_headache_5202049312', 'Cervicogenic headache'),
  (1311, '500eb5f0a5d9243267c14487ec520966a642498120f3dcf75e2032bdc1b1ef41', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1312, 'b93c928da50c4d51890e6000ef420de5356f2681cf32e8a8a9a4f1c6c8b7e8a8', 'dx_knee_synovitis_impingement_02e229b1cc', 'Knee synovitis/impingement'),
  (1313, '8a4390e0989082165ed9949d0aaacc9ff118ff18400287a064c1fac68184de18', 'dx_hip_cartilage_injury_59a16f2a24', 'Hip cartilage injury'),
  (1314, '7162e5ab5fc1e583c528fc39b7e0ceee68c0d9be17326602f5ca479e10af633c', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (1315, '1cc7d6d2a0b966b85f04e00b694fef4a600bfd0cdadf0ed8964df70425ecb163', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (1316, '34c4a9cd10502352792ca1b79893dbcf69311799f13179015291b0feef6d7122', 'dx_knee_contusion_94058fe1a4', 'Knee contusion'),
  (1317, '3947434e588baa73f228babf494365793d18f268f21057326b928b9d778aa833', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (1318, 'f7401a1f4b8407b3ad14f9ea6b0c9807342812dcc6f0f999ef7b5cd844576b9a', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1319, 'f637178510441dd2f6a99a261684c4d0d9a491904fc3bd3001dbea973686fd2c', 'dx_great_toe_injury_71c02ad835', 'Great toe injury'),
  (1320, '04d99f9cc8b3a9c358d9f4829b38615ad26aff8e8ffe4c5572a137415e9d8fb8', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms'),
  (1321, '6ebaf803adf1f238da89f48e2059de89df3a3f2fa09bc0a1fb4ce492fcee8069', 'dx_peroneal_injury_b0c8606ad2', 'Peroneal injury'),
  (1322, '611bccff421a0b6aa445931a7d3c817646236c9ab0941b85df9620d322a9a818', 'dx_knee_pain_609ce718bc', 'Knee pain'),
  (1324, '729aa08a73b15c81059837dfc94c7ae7236b0a3aa935b9e93b4200b43cd3dc3e', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (1325, '860d56538fd7ffc17e850b75b7955c4dfaacc8b60888e5a4d4dec578f3a3be90', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (1326, '65449d5a4b4f06876f45c9691c45f3bee4c802f103fbbdc6de12f1001063f059', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1327, '5c295fb44bdbe2b1fba73b4b831405fc39e9ede6c4541c8fc05abbb0893f2d55', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1328, '900a588ab6c10dc09e2cf97fd75a63ebfd441fdd2990144298c0116df6887643', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury'),
  (1329, '177728b1f6c3a1df023cf477bd8a42863bebe4444680f35c03bb62505ea403b5', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1330, '9995b42649f53ab61fd2915a8c33a2a56ceb04059daaabb57784cad2db37cec3', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis'),
  (1332, '209e45e3b020d278b7348ff0430e5d1b7d61380967cf89bd6dd60b60e7bd3a9c', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1333, '6e419130466b28ba77c2b291c8769fa191ec884ca7842f3db5c6b42b744333c5', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (1334, 'c0bfa26a14b721422fd2c671a16d70b1a7a0dc16fef03c64d8f3a82fc22c646b', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (1335, '7b81bd226dc8246847e7d60edcbff39169580017cc6feb0bb8329c62c7e128f4', 'dx_great_toe_ip_sprain_fa3b57c942', 'Great toe IP sprain'),
  (1336, '3b9334898195983b2155117362a706574cce653a31f448f9027ec44e163f4192', 'dx_pectoral_muscle_injury_981511cfe1', 'Pectoral muscle injury'),
  (1339, '7db55a69d9b507d350aa27ed3182b65d9e12363105451ef87f4de38bfec8de59', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (1340, 'a0a0400c496562b96543b0284dead10d203401497e53601708ee9d314bd7b710', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury'),
  (1341, '159a743fb346a869f01778d336f7d1f51146d991f034f97b9e4619ede51a4aa8', 'dx_thoracic_spine_pain_9ec9a9f2e5', 'Thoracic spine pain'),
  (1342, '7ebb10c70a29a3f0077b70ae4e9ada0531f3dbf306fd1a8b5bf83ccee924dca5', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (1343, 'df95a900880a6f47dda9bd05eea7530d71ced28381e151d187c20823a215a8c6', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (1344, '6214b708a8ff6e411be9d4197f6db47efd3f9c914a1fc50d19994312f2dc6619', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms'),
  (1345, '89402964d5148b1d7e4a4333a6f8d2c3ce8ecb2386cfebe51e4766c5474cd3dd', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1348, 'af5eccd9efb4a458df44b64a1ab1fb26833905d3d13c4d314557cbc2f83c126e', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1349, '51b2cd91d18efe9d9ed7d80954bb73c2215259ee0bc7b117aafdf73dd0f29ab6', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1350, 'ff5dde4cfa8cac6118b2566e475f7ba655f4294ac0b44e6c16ae230cd55215fb', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1351, 'baf3ee1f74cc3d79935b6c4c99b3c0cb266aef0af2202ab6b48c2ac0df313f96', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1352, 'a713fa61bc8f2397849b9cc482af4c681b2f57049a58a93f5e04376117bd8aa0', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1353, '9009cc7fe7ed104b8417c246aec492197ae88bbee8ab94ea80bd30906dc137dc', 'dx_calf_muscle_injury_0b80e5492c', 'Calf muscle injury'),
  (1354, '13369874632022b223e092896d085093ec6651ab68ab2733f4f68e7203413bfb', 'dx_hip_and_groin_muscle_injury_7ccd814142', 'Hip and groin muscle injury'),
  (1355, '2022a7eabbd054d3d11e6d6d9db5050f7fc62e2d330d815216b8672c6ea6efe9', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury'),
  (1356, '563b4458cf61d15890481412c50dd7621ca89e8bf552132fcfa5a2e86055a79c', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1357, 'edc9590d0c6622e7f9c9d0cc21e16ae482c0d34efffc1ade7780a64ed38062b2', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury'),
  (1358, '5dd6172da92cfd1df08fec68eeca24ce62fe0e3b622c5cb59fc4854adfdbc497', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm'),
  (1359, '3a6b45e8ef51d830ef216980a70a96cee4f288fea6985bbf66e7ac131a7a92d6', 'dx_thoracic_spine_pain_9ec9a9f2e5', 'Thoracic spine pain'),
  (1360, '91b3d22fd501af7fe797580be9b2fda7d44a2d86fad4efb3ebf2946f1747e5dd', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms'),
  (1361, '991b90d9e0ab689e698e060c1f90a648db5d8dbf544da80ce272a204b8c052e0', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1362, 'ba9602530e1054b03026279dcccd3266fa5d618ea83a246d4b220b54d326f2cf', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (1363, '95602e9a609923e715365773e3eff5344174b155e52aaaa9758c93b35732548b', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury'),
  (1364, 'aff5fa3daf7451404e5cc3dfd852a526eed9515e1f2f5b5635613ea3196d724b', 'dx_cervical_spine_instability_658367d444', 'Cervical spine instability'),
  (1365, 'f3a7635e266616de2ebf881db752b4e1834b51f1a574ead457444b7d103e2870', 'dx_meniscal_injury_b166306f7d', 'Meniscal injury'),
  (1366, 'e4f3c5dacc73f750444785d354cbee468a91b7487e5366125e5bf435dbcf6d7e', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1368, 'a1f29c1364c1f1d90865bf125bc12538bf1e31ef1955a53a405e9c9c0701c0cb', 'dx_patellofemoral_injury_a6e2fe370a', 'Patellofemoral injury'),
  (1371, '80b9b9502360c367734862d9a2e699978aec1ad3c132e69223c8e2370575a7cb', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (1372, 'db425358df383a71e5b6ab0675faeccea490cadb451ae20bf198ee8dd0f93ad9', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (1373, '0ca183da77a129c36f20e4e9e0c0124fac61786d157fcb769cd6be7f8b848d38', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1374, 'a6ad0693cf80c96832a02fb0491c553a48eaa202f454b47abbd2a814fcf85430', 'dx_heel_bursitis_d80d084f22', 'Heel bursitis'),
  (1375, '2fce31a987b48011a2777cff8efc27d4acf03781a9a941f17bee6cd073824714', 'dx_thoracic_facet_joint_disorder_519c2ae5a8', 'Thoracic facet joint disorder'),
  (1376, '2795a6cd9b7ce07bd2bca9523a50ac1ded72a612e7102b80b0ae84ccd494c8f4', 'dx_thoracic_facet_joint_disorder_519c2ae5a8', 'Thoracic facet joint disorder'),
  (1377, '3a948c457ffa7bbafa38f1b8f22eec191ecbfc1650fc3003a320b7ad0693f0c2', 'dx_costovertebral_joint_sprain_f6582e1466', 'Costovertebral joint sprain'),
  (1378, '31bff4f656c06ef6caf0c99c10bc63625afe4c88142170f8ff4548c810b285bf', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (1379, '81a38d073371ac0d2c7af9bf96f28b36966b80b3d4e469ef384860f038cd94ad', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury'),
  (1380, '5e0e5eee64a00268b07ad3c27149a6fed54fab78504bca33321be2e57b885e78', 'dx_finger_extensor_tendon_injury_mallet_finger_36d86ff004', 'Finger extensor tendon injury/mallet finger'),
  (1381, '4ca1851dc73ae3f87f4da1576af024378067847572b0c9792d980b9bf8c5b976', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1382, 'd4e9b97d7282a371c5bf14d394a6558a21605557810337731e20e3b6ed2e6274', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (1383, '6b1cd8fee3576f58e3a13cfcbcc646922e86c134745fd4efbb2cdf2928d39916', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1384, 'bc3964e160619c1c20f7dea5425c9171a7665c4d3e478659a709ca348767f114', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1385, '2ee4d78a3f33d75fe825154e337f51a38e84cf6613d5e515cfde7100e6d80663', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1386, '4845f3126d3d9a12e6f0e36c0bcfdc11347e7d27339237f915bd7ae0c83093ff', 'dx_thoracic_muscle_strain_or_spasm_8b7d429120', 'Thoracic muscle strain or spasm'),
  (1388, '64f0fc9fe3c7985041a8a14236e9be3a61dc3aff36df1f216de2d46293ecfb95', 'dx_hip_cartilage_injury_59a16f2a24', 'Hip cartilage injury'),
  (1390, '6b8defe694f53375a855ea59c6ad40d2a80aaf0149b07d9bf7650a2672900272', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1391, '14bccef4551e9a4490811ee56df0eba19ccb315b5c4f4511bb38c7ba6d72808e', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1392, 'bbe017714111af04c328f91f2796a804f598e604a927203bb916f5a4da3a63b6', 'dx_calf_muscle_injury_0b80e5492c', 'Calf muscle injury'),
  (1393, '0e971513e63f3835a7455eb0a5cea417a7fd8e6d932d2b0bfd078960b773145e', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (1394, '5ad8ce9796a66eaebe287683e4fcddec3a05a0db176e93c4d928da04309774f5', 'dx_great_toe_injury_71c02ad835', 'Great toe injury'),
  (1395, 'c000c7c60ad9228dd43e7da70de3d0895a31a55256fa0748383bd4b685a5e0cb', 'dx_knee_pain_609ce718bc', 'Knee pain'),
  (1396, '7af2a5ee1d054068519251c07244e7d9a35b62b6fe640e59285d293a90a26249', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms'),
  (1397, '44e3fa824958a49f54ade79033fb03a08f65f559fc70c9701460ca773e0fcb3e', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1398, 'ebfcf5e79e0280b3d7c076ddc97c6b8081b399c07d499b85b0e7039f3b2b6a50', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1400, 'c15cfe81b8cca41012d107cd02e7dc7f33a72ff7e9cfb380ec9ad9c42e9d1aa7', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (1402, '64bb43ee8966d372f0203a4112ebf57b0fd56e53fe5ff38dbc9b74ec97aada75', 'dx_peroneal_injury_b0c8606ad2', 'Peroneal injury'),
  (1403, '2b2e0c236d59213c1c25ae6fd3e8385223e580e26162a1b6787449c831b69f93', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1404, '7bfc307b80b20243c8bc9ebeb476c0f8219de49f1aa58b3b9484ef1930ce2d98', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (1406, 'b7d0464cf1ec4024426b5d63bb02b9d18ce4977febff8c6fddf8bad68150b25d', 'dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b', 'Plantar heel pain/fasciopathy'),
  (1407, '7f36bc1838bffb4567803c6e4d3d2cf495b5669f17d43531d68bf67b189a4eb8', 'dx_midfoot_injury_3332895405', 'Midfoot injury'),
  (1408, '491f23eae6b70cc13f040000566d9dc967787fffa2232ee7703a43f17121eaf0', 'dx_medial_tibial_stress_syndrome_shin_splints_651f7c8df6', 'Medial tibial stress syndrome/shin splints'),
  (1409, '4d216c09321df132682fbc0e0bed379e008156e578b3b14c398a0077214be390', 'dx_knee_pain_609ce718bc', 'Knee pain'),
  (1410, '74353f2f5b5fa3f0c98c237a495bcb02b1b3293c35e2a1554b25785ab283c479', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1411, '79cd222dcd3ea586a44e8a2f0e3626137168509feed3b645f120cb0e0bdc2a99', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1413, '4bf133d3e2d0df219469c0105e47323ca3c534b26c2e92f54e1400ef4b6d6d1b', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1414, 'b16880394403cc2ea6317c9dffd55f3ddab8ff9d864a0e7e23d28400466d8210', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (1415, '11c83b41036ff4c51c3622b00f02490fefa94fb0ca539db82a1456d54dc32b4c', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation'),
  (1416, '8ead388807397990c2bc5424f600b64452023771d4d1c594a2f784bada5a33e4', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1417, '933a4d7535a1aa181f62eca1effd3073c12deeceaeabac9e0588480211294688', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (1418, 'b2765b15abc2abbf77964829c6da091086f3b6986344d1dfbc7ca852372825b6', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1419, '719e58be40a74d5ca0584c77291a5355d0c300bb2e01177127dbb5e79cbe0ce2', 'dx_acromioclavicular_joint_dislocation_8954e719a9', 'Acromioclavicular joint dislocation'),
  (1420, '7aff7602dc23dde088c11ea2a7ce67fe26948f2360113d49c6915ce38a141552', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (1421, '26d90ddbb5d6db9ac59b4b366c6be08b3630d065c15758af2af4187d55116428', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1422, '8ea00d9cb91be863d6363306f693e7dedbb887375c24f67e495e414b94da2f18', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1423, 'a8ff194475403beedc6e4c5290812f9faf27a849c637e0523fd602fe34ef2af8', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (1424, 'ae4e8dec246b8f4f6cc3ad12d343993827f99b9c88449d6c0b9b72605d8c55b4', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms'),
  (1425, '660f87a18fdd0165cb527516167a524c924a847cbaabcbde44b6a69f24a79cfd', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (1429, '2c999c7a5dec3e598aaf2a8c8f9ab6bf458911d217f9c751886677313ef90857', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (1430, '45ecc61f03a9bef692a9f4ef6a8314568d4f09cdb18cf31b779cb71d12365245', 'dx_great_toe_injury_71c02ad835', 'Great toe injury'),
  (1432, '0efc774b693dd1b47ca61b693db24def62e05b35d8c9bf64a10afe9b9570b98d', 'dx_cervical_functional_pain_e11c275770', 'Cervical functional pain'),
  (1433, 'd9bb924adbac9cf13850859137d2dd1314779d6f47e3a0b7402a2da8395f36cc', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1435, '2ee36390addb6612cbd37263ad1796a703208493c2e13f0aa6b9842cb3301d51', 'dx_cervical_spine_instability_658367d444', 'Cervical spine instability'),
  (1436, '0035c0c923155ab385225cadd466070b2fe98055ea12d65644cc65b4c2ccb4f9', 'dx_great_toe_injury_71c02ad835', 'Great toe injury'),
  (1437, '85117d016c72ce5505783eb54e22ca9096896aff2de5522069b6c9d1325fec13', 'dx_hip_joint_injury_07aa18de20', 'Hip joint injury'),
  (1438, '2c684f938e0c0b1fcb38051d028fd2bb557b82b2f95e77c4feb0adc97e4def6c', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (1439, '5caed8715479104f5eecfcff52ca370e4942cf95ebb3d9c5cb59dcd08376c6ac', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1440, 'd647048b96b1448cd09a0e130e10664745f8f319ddd91897cf34bf34671b140e', 'dx_heel_contusion_4009d671bf', 'Heel contusion'),
  (1441, 'ff7742a6c645c06ef44640f40c4428bc49436f41d6d6daff443006874742208c', 'dx_great_toe_injury_71c02ad835', 'Great toe injury'),
  (1442, '420149ea1be1399d499a8ce9af5c72c70a93df49d855f213ea72893b395fc477', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (1443, '9dc666a07f4790055005b5b00eb04a3eb441261871e59febc97418e11e34976e', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (1444, '63c227c30ef5f3de8670a80ae7612314996a9d0a239299dd1f0925fee3a54bf4', 'dx_knee_posterolateral_corner_injury_a4c4c64579', 'Knee posterolateral corner injury'),
  (1445, '999d9023044f0b488ee78f32f031993f18451fdfa9551c79b92bdae2b768f0f1', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury'),
  (1446, 'd3fec14f71b3e7c29c60eddbecd1067123b01544de74b2a46f41b35f43254aae', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms'),
  (1447, 'c85a574d2c23c4948b05a34f5ff1ad684cbef710c92df1aa8ef1db7ee456af26', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1450, 'ec0539ba490484dd2152266c3a206a77c09010acb647bde5b5ec4455c38dbdbb', 'dx_ulnar_shaft_fracture_8603134cce', 'Ulnar shaft fracture'),
  (1451, 'e1dd3ef0094506f0c8b234d1fa21caf51dadb7c4cf2b6bbf025dd81b10f02493', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1455, 'f1a48d1b89e4443b1d4cdc337cb4ac93e960eb865134120fff0f4730b0a20abe', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury'),
  (1456, 'b4b35047f549e33bfae900207b6451aed1e7ae1725db9ebcb635cedf6dbdfaea', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms'),
  (1457, '2575d175cc835d245132065c32eff39e0e0958d48066efad233169e5cf3be10d', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (1458, '8a8424d718a2459d5452503591a422b5405b77960c793ce9605e854b2dfd1cd8', 'dx_wrist_fibrocartilage_injury_fddc60c8f6', 'Wrist fibrocartilage injury'),
  (1459, '64e8caf55809d716ab6d9260dbd92d34ed0b924bd942b6e0a6765b3338eb8768', 'dx_knee_pain_609ce718bc', 'Knee pain'),
  (1460, '452820e84407b217c58fd04606e573dab75bebbdf9f527e7db4e3eabbec3a468', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture'),
  (1461, '7354c700fc70e83f56137f29222d025e614cefd8240a94f6392d6b411c6573d1', 'dx_foot_bone_stress_injury_unspecified_872bcaf23e', 'Foot bone stress injury, unspecified'),
  (1462, '8486e06ecfb9e31caa8ec1745e6f240c3e1948c4ce82006418419c27d85dc980', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (1464, '654c3279bf84c61260bde3568af7661ca1ea98e4939e78d9c85e87423f3522e2', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm'),
  (1465, '761a9de16c5f5e20efd654399b04493895c66bde641ead5ca8f483dad0d6222b', 'dx_lumbar_spine_injury_27c07f4f95', 'Lumbar spine injury'),
  (1466, '76fa18092b26a6c01fab56a8f2011432c3dd795d382794319ea4bc0d51127eb6', 'dx_hip_and_groin_overuse_injury_71c787dc38', 'Hip and groin overuse injury'),
  (1467, '4815793befc67933e39adf57630c7b765a82e80fa7ef02fe78456ecb487dae76', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (1468, '8891928dc07a045a258e5ad2a1dd979fd33d96e0cac6dd480f1dc775f8f77cdd', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1469, '090462c4e6b5240c7ce412209acf7146bab50baf2c6e5cc830ae5ca9cec0dfe5', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury'),
  (1470, '98e70021bea26c6f1c70b5727054104fd2c3343d097ab8bbecfad74f456cfec0', 'dx_great_toe_injury_71c02ad835', 'Great toe injury'),
  (1471, 'eaddf710740374f74d4705eb79e9a3a25f433ed65d6f4413b0578b19b4284289', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms'),
  (1472, '7d7a286db8f521927cf7760c6ebb9141ac8b6a8a78f9aadb7a00ff65ce7519ed', 'dx_heel_contusion_4009d671bf', 'Heel contusion'),
  (1474, '08a40f20bc071634d1d024395d67724a1a3a2aa69f9c30d4fa001a65cd2affb9', 'dx_posterior_elbow_impingement_9844ae2f8c', 'Posterior elbow impingement'),
  (1475, '092a2cfec1aad557c01650e400ae1fdb31342b426d6d3439cb8c15cd89673af7', 'dx_thumb_ucl_injury_00b846b6dd', 'Thumb UCL injury'),
  (1476, 'e5fa4121d25e02caceacea443eb4c26ccf1aab9be9c656805d1559635bbc8801', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (1478, 'b068020c1a2a0ef313b507b60b7cf54d1deeaf64267d8cfc6f58d2c7eddca4e4', 'dx_thoracic_facet_joint_disorder_519c2ae5a8', 'Thoracic facet joint disorder'),
  (1480, 'd0271e621e3cd6663124b0f8b732a052a198b19b00da1edc86ebb0783f0886c9', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury'),
  (1482, 'd4371a960689ec2ba65a70fa451c5ae0be8b592c6c24b1edf54a5c39430226ef', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (1483, '291b2d0f77ef0250db1e22c205d2231d7f56be043408797e98467d70bad37a0f', 'dx_cervical_spine_instability_658367d444', 'Cervical spine instability'),
  (1484, '4ba400937d6d5a23b39167fb1318be451099e4df26f0c1b47e6eb66e8b242fd2', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury'),
  (1485, '1fb7f8894d0dcd7a6286ae42cfe911e2379bf522e89f0d95122754de980176cb', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1486, '6d5484a5d7853373736d846ff60bb56c7ce7efc865cccac7f45b5eb8e67f6b0c', 'dx_wrist_ligament_injury_6b21f37d24', 'Wrist ligament injury'),
  (1487, 'd622f8ab810f005aa74d42471844a2ed960be0a6a5262874570d27c26931aec6', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1488, 'f75f79ea01e30991275e8baf4ea2a6f8e1f4a870770bcf71127b2e3e9c3b0b24', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (1490, 'e183e02986b72b9f4a6a547fb33d55c06444e35656a77ae06e7824de042f11dc', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1491, '614541aad8375c607b84b15dc062d7190e4ceedc829ca98ff89bfc9d3dcff604', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1492, 'bc8946bf89ec1f0ed87047f7af4c18e30a306d3f1a15c4e9bdf299da1a1facd6', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1493, 'db0f9f5d7a68387a3d5c79b1bf9f8b5d6a9ffaf86b823c62ba08afdc17776cf2', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1494, 'a9bf41a3f11010af4036665212a4bb0edc4bb58c03706ca7c1902192c9b9cd34', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury'),
  (1495, '6f1e0f4bd63f09d28febb1b25636ab5ed5f253bc620d2fb0d0bdfecfb3bf52d0', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1496, 'f9ba7fc1fd170e855ff9e2e879f9f99af0867e477a174797139bcb913874170c', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture'),
  (1497, 'c1e1ceaf089430c9fe5f21c3d4121173cd95e6d798a372a6d1a22f06b30a1fa4', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (1513, '17e4af41a2dc931d04378a8ca768f02fd0f5f325bf4a12b8af77b85d671cde36', 'dx_adductor_tendon_injury_ae39245d15', 'Adductor tendon injury'),
  (1517, 'a2a054bf56d627a81e09cfbe6a677c957cba2844aa8ffa0477b28ce4a3801a4f', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (1518, 'a73b5ad525476d09df11ff86c429f6fba78e6af7f8ad58236f63cb1cd0da57f5', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (1519, 'f94a545e5abf287c612190d03d2d0d2ce38cbd38049bab8644b7043824165068', 'dx_shoulder_dislocation_2067688fdd', 'Shoulder dislocation'),
  (1520, '8c6c70c0ba345ed6f34518faf9ae068ce14c7da00fc12259f301c223f777b713', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (1521, 'c9e580eb9403dea221440e3b223379b5609e3916f369e90a0a38e84dba0a10c4', 'dx_great_toe_injury_71c02ad835', 'Great toe injury'),
  (1522, '68ee7f5aff4206ba16b7b94d438c584f5a679b767adb2b7ff0137c3a74e739fa', 'dx_great_toe_injury_71c02ad835', 'Great toe injury'),
  (1523, '6f9707bb7a4175963c217b87961d55acbd786fbab46da8d01e56e7fff98d7284', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury'),
  (1524, 'd69dc134b5a49103c2c982c02740476062c2ec7d523cd4f08f664f247fb1dff7', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury'),
  (1526, 'f1239ef44b73d56f9abd7d4ef01e498dd30dc710699c34aaa188122370fbbfa7', 'dx_inguinal_hernia_b37371f06e', 'Inguinal hernia'),
  (1527, '859b434e954f31d9ee2cd184b2d3ee968d069459bdd34082fe87dc661498a20f', 'dx_lumbar_facet_joint_disorder_4a13830647', 'Lumbar facet joint disorder'),
  (1528, '6ec0c861d0ac7d2b52ea853ec93d4f4edd60da8d16a47a1a4ae3f1a0a8e3d81e', 'dx_lumbar_soft_tissue_contusion_125139d685', 'Lumbar soft tissue contusion'),
  (1529, '03bf044089e69e732ac7f1428b613ec6f9bd9350edd7f37a20b1c2a6c731406c', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1532, '8bb238972bab5d4cfae7c99e24a0e5160d802eb115a9a9c6bb631c333f274ca6', 'dx_sports_hernia_ad99f8552f', 'Sports hernia'),
  (1535, 'eab1c6d396ddc8192929caecc8fd59714907c24ec7a358b024d4b69747982893', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1536, '7fb0c2b98cce9c0cbb809aad779e902fecc078e65e347eaa276c495f0721fc9d', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1537, '85dbfbd49e5aa080cad3e3db2ebf338b7985ae4f2d59b1b6823d347982bcbbff', 'dx_great_toe_injury_71c02ad835', 'Great toe injury'),
  (1538, '3abdeb65eec2a4c456a3e456d5ed778f8111b48cfe33eb990c5688b5c1ebb62c', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1539, 'a9d3187227a0a207177bff5e85c3d626fd61897789d4e72d982f7e63d76310ab', 'dx_supraspinatus_tendon_injury_3840a1f333', 'Supraspinatus tendon injury'),
  (1540, '89054ae1330f3feac56bcf8d715687d9700ec0610967cade3d67378805fb09d9', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation'),
  (1541, 'dd7d3f9985ce0d346013028b7cdbab9c9612669e53172c354cd00ddc6379ae91', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder'),
  (1542, 'fd7427aad72795aa81f5f5bdd309aa245a553ace115f6f4d8d5df0554d4fed82', 'dx_lisfranc_injury_a82b5577c5', 'Lisfranc injury'),
  (1544, '52badd40871aeb8480e1246adef82831a04f21ec048dda8b12a02e5448d2fa18', 'dx_knee_osteoarthritis_088b6b8911', 'Knee osteoarthritis'),
  (1549, '2f679a69c66b1b702e6b2558f877dea7b2e2ad820521cb8695d043b49ce7a8ed', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (1552, '7e8136c31629792c356e622eff3496d3b08656c11550169ac403a41e1a8e5f01', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (1556, 'd01737132bac7a03b22f92eace4f840eb627504fffcac10e1ed3d17f2fd0701b', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (1557, '1a8ecb9b03671378a8a1e884dfcc699ad75316cad4e0fab4f3f2e0f83c2b3352', 'dx_sports_hernia_ad99f8552f', 'Sports hernia'),
  (1558, 'cf9dbee7c6fb41ede7adef235121ed31c08ac274508d9e0e71982359367f780a', 'dx_great_toe_injury_71c02ad835', 'Great toe injury'),
  (1559, '9bd5979311bf00bf7791f9df777695712758a51e0b8c5395371d63342cc70828', 'dx_conjunctival_haematoma_d0548fcc2a', 'Conjunctival haematoma'),
  (1560, '67c43e6eb9fb2e5ed7c0a59a114a537e6eb077e1a481cb2e13f7cd01f34b7f62', 'dx_acl_injury_4b8eb47e96', 'ACL injury'),
  (1562, 'e7e707ed32db03ff9b876edf245b49f6dd531e83185344fe3d2df53cdbc91ac0', 'dx_finger_mcp_injury_6c586feb13', 'Finger MCP injury'),
  (1564, '16a8a28b4482665041ea373466ce1c96c719147b1ad1f4529d596c7ee718fc91', 'dx_medial_ankle_ligament_injury_9add2aecee', 'Medial ankle ligament injury'),
  (1566, 'ea9cf5185a0f36d2a0464877c74e2d9c9f394cbaf1e4e055eeb848e7787edc03', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (1567, 'f338aabba8df798b090973fa04705246656f73957098ca83b8f4677119026197', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1568, '67c15ab180bab074b48daa773c834a2442991a925f5d77e8af2609d7b5e177d6', 'dx_hip_and_groin_muscle_injury_7ccd814142', 'Hip and groin muscle injury'),
  (1569, 'fbe11733612fa205ab2ba21bed3ef25f86ce4e376ce1f9bee94ffe5145001ab1', 'dx_spinal_disc_degeneration_850a87dc5e', 'Spinal disc degeneration'),
  (1570, '236652a92e72d7cd5c1a5c58150af1fa8471f20c84ea71cd33901c3c0e2362e4', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1571, '33e49e3b3aeff4267525246c0b5ad09b0b42825ca42a3c561c958defc8fa9b36', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1572, 'e7d08997116fab4009839e8dcaa5d5357626ebbf43dd75d8be83f5b3f1c142e4', 'dx_lisfranc_injury_a82b5577c5', 'Lisfranc injury'),
  (1578, '4ce1188e48832630613e0a3d087c7282ab03bdcb3bc8be90db57dde8599abb10', 'dx_foot_joint_injury_28a178b0b5', 'Foot joint injury'),
  (1582, 'a364adc796458ca80494dcdb2a7a50e866385fa0a5d57b9ed5692bb8726dc813', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1585, '6c6f243e135f7ea186cd15f88bc769607135f20486e96ea203199f7c67af7fd8', 'dx_wrist_or_hand_pain_57c9958c78', 'Wrist or hand pain'),
  (1586, 'a368e123b1e94348bc56db0f6faea158ac7f47912aee38f28bfd59d4e5c61d3d', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1588, '9360482c8a7e304bfb0d982f340beef31fd3c5bd140e7d00517cbf5eb654c44e', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (1599, '2e8b4eac014f87b22c0b62388c1d539b3223fda13d1e0558881178c88ad6906e', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury'),
  (1600, '7eb2238ec841aabc64b432162e4463e317977a5862ef3a7fc5a02c5601c9dadd', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1603, 'f14ea3ec120a9c0948009fff1d28d080f2bdc779b92b3daecf77be2a539431d8', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury'),
  (1604, '2cb30841834e8897b5288d056c6e30972e326fc135c20f644f6c0e28cfe29a02', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (1606, 'e015cfeb0338633463b9846f8d4ef6dceff6a3e078fec001250613f6ee22f742', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (1607, '009e32399b5d076d99281a4302e233bef194743110f823053e179302bcc08e94', 'dx_dental_injury_b97b2afe75', 'Dental injury'),
  (1608, '2c18e921d919056cf81d3a9b2aa01d97eb1852573ef68b95b0945efa138d6fe2', 'dx_acromioclavicular_joint_chronic_instability_299408db68', 'Acromioclavicular joint chronic instability'),
  (1609, 'e6b89df4b178f16a1c5df7b454a204089b36f949d05aa8d45d052df287237ee1', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (1610, 'cefafb5c3b7e87d5c4a0b3461a04bfe59d049301f835e69eeb209094068b8744', 'dx_elbow_bursitis_24fdbc7698', 'Elbow bursitis'),
  (1611, '9430e28386628ac6b4b6a78f3ba0ecf2e0b05f7ca95fc0828e800630de458435', 'dx_rotator_cuff_injury_0744f75c4c', 'Rotator cuff injury'),
  (1612, 'e87d818377773e9a2f97c3f32f396addc43fa9d1247b403a1dcd1a13d5dd64c4', 'dx_thumb_extensor_tendon_injury_e76a7cbccf', 'Thumb extensor tendon injury'),
  (1614, '009d7c1cca7d0a8b65cc48000dd94a905fd9ce0fe31de713e675bdb7cd9ff6da', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1615, '0078bb72f1f93bdc6ff2b1ccc6465871902e6b0a492ebd90e6b905d05973a809', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury'),
  (1616, '8db2a125c728b6bc451a19a70ee5efbf142786ebc1a9a3f9bafe6578d616316c', 'dx_wrist_injury_d94414e2c6', 'Wrist injury'),
  (1617, 'd26c39574ac35b5ae0f3465c40ef522ef77d66e03e704bc13aa312b3b0de2759', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1619, '232d7cd3e7cb1532fd115d799d50c19c177f4458f203a45a12867e1e3940200e', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury'),
  (1620, '8fecde7c3ba9cb6b6b2e8b5e21d8cd5e207ca7952ef69e1c31019677f114b567', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (1621, 'bb1c4a1a9b864c7060e2e3f5801999f09ba8827284ad64587dd96650b1191afe', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (1622, 'fdc86246b9d9877a2a023fa0d6180902f88e65259d0e65b557adfc0cafdb467a', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1623, 'e44cd8331939dad83b56fbc05ce45e3dbaafce3ccf275b44aa7128d2bc1e837b', 'dx_calf_muscle_injury_0b80e5492c', 'Calf muscle injury'),
  (1624, '7ee8ec70c6b47e4767d4b678d058134db00a6502a0a888ec89cd081f838b11e5', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1625, '1748d41f0a2ee94c8c9386f38a916229b9c371473a4cd6f545a8fcf5ca64f7b4', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1626, '53623aa3f547a73eae405bb70719508d91a07c270acef4d38c03cd8370b83469', 'dx_head_injury_unspecified_611d184685', 'Head injury, unspecified'),
  (1627, '81a5b5aa73af4bbf047f2df1a33bb41e346a545bad25e45832b51f3995b8ea00', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (1628, 'e664dc8256ac011bb8ba9af1976f6ab1bf056a8b2ed50b29080bff4e111ef726', 'dx_head_injury_unspecified_611d184685', 'Head injury, unspecified'),
  (1629, 'b639c792ed576f37c2cc1e1556711ac3482dd8c87613a97d7ebec5b6da78399c', 'dx_thigh_muscle_strain_or_spasm_73f7a9029c', 'Thigh muscle strain or spasm'),
  (1630, '5bb82dfff5a474b079622bc0c723078cc665404358e4c1e5f9c90cf8cf8924eb', 'dx_meniscal_injury_b166306f7d', 'Meniscal injury'),
  (1631, '627ff8d194a044c0d3246040fcfc948515349709bcabcfab7834a9f9e78f88b4', 'dx_medial_ankle_ligament_injury_9add2aecee', 'Medial ankle ligament injury'),
  (1632, 'ac26ccea3651236e07a8da082bcb50a35bd8d80674c60acfb38f19e1c5a1c066', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1633, '3a27f5cb3d2e70d31ee934db8aa173c774a1756bb79bacadb67914565035a095', 'dx_hip_labral_injury_91413d20be', 'Hip labral injury'),
  (1634, '1a02b9c02aa64f8a305d080b45bfea360286dbace1d9acce373e0f3e47c7803e', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (1635, '12b71c07936e83a652bfef175065025556404e129d750f97080d195a357541e4', 'dx_head_injury_unspecified_611d184685', 'Head injury, unspecified'),
  (1638, '7f273000fbff2fbe7aa209962514175d9a8d31b1662a011a8c978e90d76fabe0', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1639, 'ea7832a94d6e33fc6b0ca667cb01dcf1d77fdc25c049725975a76bd975be78c7', 'dx_knee_pain_609ce718bc', 'Knee pain'),
  (1641, 'da32e73d0d7a8c774002cd347cee9bdb8df7a0eacde23e24a2761658b44c9220', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1642, '29f8789a642f20d42095b35cfeb0c3db4208509ce9c5c585af82c238b6508907', 'dx_elbow_loose_body_85f452ea62', 'Elbow loose body'),
  (1644, '807b069545a59927f07d6eae1547a12baa7fc62d8b41273264b4bcec12f6521b', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (1645, '2e32ac43b805545fe846e65c97b0034a38671b1b64eb5c71a34a413e44b3ac41', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (1647, '72e56787303a9a560f6901a4b15d7692e8e392ca9079b45bebf89bad541ec121', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (1648, 'e9efe7b67c769fbd726ba92b0444e33058046c9c35d58c15a27316aba38cf1d1', 'dx_rectus_femoris_tendon_rupture_0e94ff146b', 'Rectus femoris tendon rupture'),
  (1649, '79a948769ba7261ea3f04a66f96ecaa710430d2417a364e4e87b13b34ba7a95a', 'dx_wrist_injury_d94414e2c6', 'Wrist injury'),
  (1651, '897040139a2f2eca1c78b3b65451a5a1293495d255edaa897465266ad84dadf6', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1652, '97b3cc109b455620a287dcde6d990f7da3cb41d924eaeb99f9a4aeafa34501b6', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1653, 'd615e39027d157620cecdf4f68d55ead65a0e48a03379da161a1795735ae91d6', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1654, 'e8f04a6b5e44fffc4c23e990fb4c65d2a6761e68445166db2c33689c7b51ba6b', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm'),
  (1655, '9173b37f88171d3061c72f1ef114849e941cc2da396f4684217dc6dd3a057c3a', 'dx_toe_joint_synovitis_df423d00d4', 'Toe joint synovitis'),
  (1656, '203274f0650402cf405bd715d2a15865945d9d36b52bb82de34bf0724f5b0d8b', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (1657, '58cb5e7cf0a088eba783649875ee00ceb7e2d885bbd36355f2dfc78b832b2f64', 'dx_iliotibial_band_syndrome_126a373d4b', 'Iliotibial band syndrome'),
  (1658, '4f754a61e64b5e16d0ceebbc3b39bb1eaf0b4d4491c9e2607660161730f42be2', 'dx_hip_joint_injury_07aa18de20', 'Hip joint injury'),
  (1659, '6b66725b65ba0641554a2c0c9056173423805573d24bc30fbb6ed68c32c4d601', 'dx_acromioclavicular_joint_chronic_instability_299408db68', 'Acromioclavicular joint chronic instability'),
  (1660, '935f6b43c1ec57853d4c7c9315c615e5f6adec1b621899904f61c6bed65abf42', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1661, '2cf8930c581a73c5ce02265ace44d9a503a8a09d72d242e5c7f3c8d4d430c752', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1662, '99253e2e5c10f3157f6aa226f02ab3f0c415ab935981bd4115ed16e049668205', 'dx_wrist_injury_d94414e2c6', 'Wrist injury'),
  (1663, 'c148ec960f3778414b002d990c58d0f8af662bf9b95f3665dcc47f7b8975ed2b', 'dx_shoulder_labral_chondral_injury_4ddc56b103', 'Shoulder labral/chondral injury'),
  (1664, '76943a2471b6ace989faf5f19766dd0983f271a2a017922af5b8c82b64a16766', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1666, '76f395ade15596b11117379c109f484c38b749dbf231b4d71748211426b275ac', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1667, 'ec0a12d2ea6c6023e3a7d3f8a77482adf2341d1f09321a6b105dc1f8353492af', 'dx_distal_clavicle_osteolysis_0f9c9b6604', 'Distal clavicle osteolysis'),
  (1668, '2144c7de2856563a1834d8a5cbf7d12dcd11205653d62c8146984e2f6c116f59', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis'),
  (1669, '24d18fc37b3f786c470c051304de84582b4d3041191559f8e233fbd3e49c6857', 'dx_hip_and_groin_muscle_injury_7ccd814142', 'Hip and groin muscle injury'),
  (1671, '29e4f3548aedda29fd9d92fa76ee633aa7ceb52dc43875ffbef0f742efb011aa', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1672, '4c78ce099d76681161ac6ebc6f8b4347b556751898d43e6daef5ad850fc4a1cd', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1673, '9f65e3183169ead7ab93cc2bba10865cdff83daf6cc631680365eeb1374e1dd9', 'dx_ankle_pain_de6b615afc', 'Ankle pain'),
  (1674, '3c7d10977940b34cce71d5b694e3552f862fb600df98e08d512ff17fa65cd4f8', 'dx_knee_pain_609ce718bc', 'Knee pain'),
  (1675, '0f1a6be732f5413604ee759f7c138dbb1b9319d1fccf452ecebad9841c64e6c8', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (1677, '70bf6264f92db42edc0645aeaaf3ce1f967b489c6db484d32f988a7edaad698b', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms'),
  (1678, 'b18da31d5c0f23c83e9055debff925d0f8bd220bfd6098dbe59f85798a5df575', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1679, '7553d46c2744fb6d9443d497f629cd9929368dae07e16ea5cc57d24663872a02', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (1680, 'f22b237291cec1430d7b1a5a30720294adb8bf6c109d02b115c22e5968b6750e', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (1681, 'a9455464f9563e10d6491532ade30a3339fbb764f0dc5d80c24f053e243010a8', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1684, 'f19df645f792aaf9220c6071df7b06e67074b7e73c3eaada5b42a17738cd1e5f', 'dx_quadriceps_tendon_injury_08ea99efaf', 'Quadriceps tendon injury'),
  (1685, 'd5141832122ddc8d36d15b277637dd67757bc5d3e65a3c1c3300e46da01f3c1a', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1686, '94c6c81b401850a74dc665f9209e79a1acdbe4433dd8c20e87a6fd0aaa2be538', 'dx_nasal_fracture_a291a11f04', 'Nasal fracture'),
  (1687, '4ad0913ae1390dd397927d5a6514e3c5b562eae52569b7e60487ddc6f8dc4673', 'dx_meniscal_injury_b166306f7d', 'Meniscal injury'),
  (1688, '332040e140a716710917b455d0b82137a1a3b1331e8e1cb20b15663d7d11c78c', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1689, 'e0d4d7c3dd2ef7a121ad5cf90045262361c0cfa7676efed20a9eb0fa2ff5c388', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (1690, '2bbb7b78858e3b7abdf3661169cc7ec22620e336d4e90457caf8cddb2a8ef980', 'dx_thumb_distal_phalanx_fracture_148dd4f5fc', 'Thumb distal phalanx fracture'),
  (1691, '7b0f07f25de19ef9485845a99565f68dc21c54272cb1529fec63a5d6a61f3ac6', 'dx_calf_muscle_injury_0b80e5492c', 'Calf muscle injury'),
  (1692, '43f2eaea584ae18137b2736829d84ec8c16f9cac4f6643c6ff53b1f9a2fe68b9', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (1693, '5f83867b0641c9549e45186ae1670034c9228829c14dcd7a5472a1909f80f955', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (1694, 'ad232bae26092d6a4af7ca54da4de3d34be3fa80fa449c694444fbe3e064886a', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (1695, '6bd5fd1f5000d7cad13c73563489454670f9653cbc3cbeb0e7822999a5540d0e', 'dx_thumb_ip_sprain_8664a5f1e4', 'Thumb IP sprain'),
  (1696, '5573455b2a1f8ff2a6bcc4253abd6fa067b6a05f540e7e207296da01bef4346f', 'dx_first_cmc_joint_instability_63d125fc16', 'First CMC joint instability'),
  (1697, '9ae1f3e3608e5222f6d97d354822d2b8065283006d9be58ab874017e33cd631e', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1698, 'edd5fc480ffcb1dceec3bf3229ddc4c42b70efb46b50e98f514912c7b89692be', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1699, '5fd3a903065f3e7bcae0563cda6b912b57b8cceef03f3c4ae4c57a0075d51b70', 'dx_cervical_functional_pain_e11c275770', 'Cervical functional pain'),
  (1700, 'b676485a213672e4a0f6f9da61d75728ed502a5a33b736d14716b4ad2c256afa', 'dx_thoracic_disc_disorder_9d9c895000', 'Thoracic disc disorder'),
  (1701, '30cd5b49d601b97ae20a24bf8a00a9d8173e69412d7bec85700194dcb63cfbda', 'dx_knee_osteoarthritis_088b6b8911', 'Knee osteoarthritis'),
  (1702, 'ed6d100a9969789610f6e0b9f9cd1dc351810dd856b94125c76dba9253aa5f59', 'dx_knee_pain_609ce718bc', 'Knee pain'),
  (1703, '82b00db9dfb8bc9944f217eadf8fce98e2475dfc4aeb78fb8e612c5a38c8e8fb', 'dx_glenohumeral_ligament_injury_0fa65242e3', 'Glenohumeral ligament injury'),
  (1705, 'd00945f3fefe91664f44eda3bbe6a84bc00850000b22bc6181aeb56b75f5ff7f', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (1706, '75d575e8bfe27d8756e58738265fb4ba0439d601bd15fa45d58c5e59b83568dc', 'dx_elbow_injury_7100f71f81', 'Elbow injury'),
  (1707, 'bdc7776ceee2c458dc535eb6f07f1f98095cc8718298c5e62a30c41266718ce5', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (1708, '8dc1449bb8caf174f5708a2df671e3e23c51402c803678c2d4c1ce3733ad3459', 'dx_thumb_ucl_injury_00b846b6dd', 'Thumb UCL injury'),
  (1709, '48ed58fd4a9fc1c5aed895162fc28b7afda695ea53f960bde72eee5b994ee5b7', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1710, 'efc531178527a80d8e55ff75bd10fe0d1b646d0af124b816c9cf6ea35bfde644', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (1713, '27782cb9328ddb73ff9e5a90b93657b812d15f9522461f2cf10629b2e737188c', 'dx_postoperative_shoulder_condition_ee7c38fb4d', 'Postoperative shoulder condition'),
  (1714, 'c6e0f200a6d072e04bdbdfa7d056675c076f879294cb8a229aabb48683ce3774', 'dx_hand_wrist_laceration_or_abrasion_35c31d7555', 'Hand/wrist laceration or abrasion'),
  (1753, '955ac60b846476c4b92f6407f12fad846587966e93c26dced2fe5c8664c623df', 'dx_shoulder_pain_738e4b93f7', 'Shoulder pain'),
  (1754, '982bbf182e7664d50d044fb081efed24a9d506f8b01f6d2edd094fab0f85836d', 'dx_sartorius_tendon_injury_1da1e5ccf0', 'Sartorius tendon injury'),
  (1758, '8002ed0352be791bcaaec0057f8a36c29ebe9a0e2ef7d66e0ba4a923e001e372', 'dx_lumbar_soft_tissue_contusion_125139d685', 'Lumbar soft tissue contusion'),
  (1761, '851d97946b742747963b36a716eae190e72314d83047d116ba17c69e61715fa2', 'dx_knee_posterolateral_corner_injury_a4c4c64579', 'Knee posterolateral corner injury'),
  (1762, '65443f42b00737443a222056142b3f1b1263f74fbf2ce6cf52ca008e383ba615', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture'),
  (1763, '5dac6d765e3e086e181f719d899858bf307898d98b3dc53b8be66403648e1c03', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (1764, '557a43c1a2b56cbef53e303cd493b6942042649f600469b11890099ce421a02b', 'dx_shoulder_dislocation_2067688fdd', 'Shoulder dislocation'),
  (1765, '5227c847c4e3c91760f2f405b370072d9ed7fadb50421e7cac9578108dc8588e', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1766, '1ac8b77317207f162139a5a975289cf15f04b095a90031a34b250a67882c15c2', 'dx_biceps_injury_69e895b576', 'Biceps injury'),
  (1767, '1895c378953541867de140cbd4e9093ac2b1808d3c3045f490b3cab610dfab7f', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (1768, 'e69fafa7115257920f927dbd18f4b7ea7a19439280b9efb417b5ba72c44382b6', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (1771, '3bc86054d690bd18a5df51727a58e2d0993246eaa666ed68db8102bfe9d8c96b', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion'),
  (1772, 'a62382f72196ff91b25ac1255fb24fd5850925c1df7c5a90def7efb4f5705642', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1774, '9a5384f55121627877987dbb2e0d27aa75b5bad3634083e04f6b81ecce6bf2e9', 'dx_knee_cartilage_injury_761df482b3', 'Knee cartilage injury'),
  (1775, 'cbffcf46873077e9bb3a007caca20e79a40de2b6190759e2918f251e083d8d47', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1777, '39ab884e82929616e64cc29f9bd5899795155cb355ff32f9814106b34d3e78f3', 'dx_hip_and_groin_pain_27531edcc3', 'Hip and groin pain'),
  (1779, 'b9fe4801b4a741d5cf098763327d6f8042614ca24021d493b457cc2787571de0', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (1780, '2dd4ad8e9f3b38159176a67882a8a835dd38448d22ed00f9c7138b7625b4decf', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1781, '22e32982cfc77f5912e6a02131c8e958ca278ccf811d6bcb93467346afdc0d8a', 'dx_knee_contusion_94058fe1a4', 'Knee contusion'),
  (1783, 'efc995e0eb37a0640771a6d287f460dfb50372724ae5e0d2b01d34d27a73403a', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (1784, 'f0a3fc640164555cc3dc1a699c60109a82544bb90b7bbf4a1b7db7727a1cdc3a', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury'),
  (1785, 'ac24f014dde962ee704b32c2c7e6a18fa5952da862b6e215f058c4e57dad7aee', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (1786, 'fb355cb50c2e9ecc34cf4725bde11080e90c14a2ff46d39ee9f58ccf32ed44d9', 'dx_hand_wrist_laceration_or_abrasion_35c31d7555', 'Hand/wrist laceration or abrasion'),
  (1791, 'd0baad8ca845911b19831f6a5c4a1e21008f92d2873c3f6b5cb54bb3a40e9198', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1792, '36f37d2dd9c8891a8336c28d1d233e40a3a86a58e099dc2f364caec507c009ed', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1795, '1347206600121bc4b5bf3a6f33fb71889315c86a30d4a115ae57148b4807133c', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1797, '7ae141c68ddef88a24e86cc659ec419dadd22eba6a70adda3c0054b8ba59149e', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (1808, '81008dc139725bad77eeda56ffac0f3089ba45921933e231c4a4abf045ec7ae6', 'dx_biceps_injury_69e895b576', 'Biceps injury'),
  (1810, '9e5b3f8b5c4430bbb4a0ac2f0147c90ee177122b2f3966047e5c6a1066208ded', 'dx_patellofemoral_injury_a6e2fe370a', 'Patellofemoral injury'),
  (1811, '0410978d64ecb25c63bfc7099d87bc7e3c99bb9d77357b1797b6e30696b59e14', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (1825, '5acd2659e1f532728a5f80080422397243b27ed15d436e903fb9b6a655813fbd', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm'),
  (1827, 'f9fdaffcd87f1076a25c307ea524551f2e4277db8f4c0b9bf649d2cbcad17042', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury'),
  (1828, '85ef404e75d7515bb83f14aef81b6bfdc1413bfa197dcaa2baf628d08ab6f19b', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury'),
  (1829, 'cfe08d685a5ff70726513af3e2aa494b2dde9ca3a2b884456d5d56d06447abc2', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury'),
  (1830, 'fcfab4b2521a831d4b15e5a5a26bf0ac7c38e1ac150cf5e43605b34e0e7ee248', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (1832, 'ad00b0855d8adc12599b6f057f2bc568d9caeed2a91126bdb4ed854b8216851f', 'dx_calf_muscle_injury_0b80e5492c', 'Calf muscle injury'),
  (1833, '80b0f630857f7307edebd8d5b84d6d82615e291524638db4909c9add123ed24f', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (1834, 'a38477eedb8803e27a58a7e006517e0654d30ca37037481d3fd7c96edcf178bb', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1835, '2181b1d930c57a050d7f74d9de0c1b862719c75e8d1cd87f51cc4a5afa93536a', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1836, 'f2286a71364a12ca4cc6a02e7c5fe9afd458891d6688e8a52d1f02ac807a027a', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1837, 'e13964fb828a65401bf85842b1023c793ecd3fab8d0a1f13f5e4bc4ddf1525cb', 'dx_thigh_laceration_or_abrasion_cec8e820c4', 'Thigh laceration or abrasion'),
  (1838, '51c20d2d81eaae95639182eae0a440d6028f96f9b3c25bb3a75e7a648616b9ef', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (1839, '2a797a141e23c9fc561cbdfcac549705d6c95c1df8e4d840587624cda9bce996', 'unknown', 'Diagnosis not specified'),
  (1840, '0cba0d768f0dff0b4dece48c3f72dba16183f9405357abb45e8391b687f0c80c', 'dx_foot_joint_injury_28a178b0b5', 'Foot joint injury'),
  (1841, '263a5b32a67f3eb872cc186fa19fef2a0e55e57318b414cf92ffe82c3fd527c2', 'dx_elbow_injury_7100f71f81', 'Elbow injury'),
  (1842, '46060844d15c5d087e77515b625c95687724e784d35857e1f6f32461958dbf75', 'dx_lumbar_nerve_root_disorder_906788391c', 'Lumbar nerve root disorder'),
  (1844, '88776d9938d1b249f551d716a9160c8f53a46cc61b24f527edb3bc5d1708343f', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1846, 'f558201765f04ce601d7289331cb377a51938d6e332dc0c010ea71187676fdac', 'dx_knee_pain_609ce718bc', 'Knee pain'),
  (1847, '0cb0259947373dbecf9be89a6891fe7f493ffb106f4c82fda898ff60f60e50b7', 'dx_foot_joint_injury_28a178b0b5', 'Foot joint injury'),
  (1849, '313f0bc40c5700fb4e135435da273aeb02ef32e3090d7e950f1bd6665c1845dd', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (1850, 'ad6e1c70934b0af514daa36450eacda0952160cb1d2d727b6b042d422e1348bc', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1851, '892431a7fc3bea7e7b0d070c8bd8448c64a326cf98aec3beffc2e2702c70d1c4', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma'),
  (1852, 'ce3b4c00b0b1fd6b2766b51ca961572bd141082a885e806a9267e1bf8e656322', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (1853, 'bd3b4c19fc6666190cb4bd4caedb2bc2c954e4ce377e04df153c302844b07c86', 'dx_knee_posterolateral_corner_injury_a4c4c64579', 'Knee posterolateral corner injury'),
  (1854, 'dc073bd191de8448810a46075f6974d685787f290808676aae9650a46331cee1', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1855, '0cf9c85c10c79494c67b274ecf731740b3f1417d59a9ff8d64158dc4c71939f6', 'dx_shoulder_instability_2b9f54f442', 'Shoulder instability'),
  (1856, '5d4e51f0f0b9ab6872f03abaa0832894cbc9436aa45ec12cf6b327907ae13ee8', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1859, '825f2088284abc4821d882b0837445db0840357f9eebe211c73780baa2b9f60b', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (1860, 'bc143f1a7d9f90c3198bd7f674a326d3f766957d3efdd28bc33317369c30743c', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (1867, '56e50680a5f600e1e9a1079e85fc182fd9ab483874b173121b3f186ae975c6cc', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1868, '8e4b799f10e5c6d96ec0ec7c82cbeb94bbb9d3c608d5123087d8e5436ff62cb7', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury'),
  (1869, '112c798ca361b2ee64ddcf9fcc6486a21a62d5c0af641ca70afa41bd0ce44517', 'dx_thoracic_facet_joint_disorder_519c2ae5a8', 'Thoracic facet joint disorder'),
  (1875, '8a22d45d5710f214a189e8ba002aba5c9fa0fbed1a2959c2ef2e3c22b4e7df88', 'dx_meniscal_injury_b166306f7d', 'Meniscal injury'),
  (1876, '26c713efd915a79004a632066f78f1f0547a716a68cfee950ea8215cdbbbcbc4', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury'),
  (1909, 'b6781b05bced304702d05f04d61fec12d29e48349957420a170f2f80bcaac6d2', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm'),
  (1910, '06264b3863197e3d67d9fbdacd2fe1a5228f29205848afd2be6aeb4581d26ab1', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1915, 'f60dc76836cd8632c0dfc4634540d7e391fa40352f83d28c408cbcb165142f23', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (1923, '6b30a7dc544df24b2fad8bd23b3635ab94e61a916f220986cfa1733512073797', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (1924, '209d796b116680a2fd3e87e3e56a5c97323f35fd07ee671a1f0c143cedce73bf', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (1925, 'a0a89fdaa0bdebee7933b4fd929ebc345300415aae16576920da75f468b54f00', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (1926, 'c55578615259aa5156d2d26896d165b654b273f8c06eb02bda1798f16ae86785', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1927, 'debd56c58dd010e11beebc1dec219816ade3bdbfc30793446e2a320182e28a6d', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (1928, '554a7413e44f1ca14060e09de91a885a1e0389cc4abfae88f634cfb34672c842', 'dx_abdominal_muscle_strain_or_spasm_8848453dde', 'Abdominal muscle strain or spasm'),
  (1929, '614c3fa6daad5bb2392d51d7216582a2e553a1aab694caa784dd0f3e036d7be0', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1930, 'b5aaaa9a1b2738bbcc0f3a1079786cb165fe4504d34f665a0f43c964dde28593', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (1931, '155e2ad1210e37de4741299ba8c4a0d2d11c252a557a5ecde74dd486808e9271', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury'),
  (1932, '5649cd7bb940e68e89ebadc2c0f2696cc473feed543720562b3b19d15552ffc0', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1937, '8ab1784e8ce2626e9f4b9f42c1ba5309a11d526a306af5f20d6ac251f34d53bf', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (1938, 'b0e19226b4883b1c00f832c5cd8dc23995909533016907d4e22dbfee564b72cb', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder'),
  (1940, '6e0b5d9de83573c27a9d4c4b563ee6d470056526dc964d19d7ef06c067cbe447', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis'),
  (1941, '0abedc5e70593392701fcc16f9c254a35fb14f6a0b193e2aeb73c1f94704f39d', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (1942, '53fdc3c2f594335fe08d4f39fc8f913ebff400d1d3184837bd1e287aa3d4b9be', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (1943, 'a6d98df3d0c59b4d5468a893bf2267a17d74a717c4773a6ddbb847237ac51c7b', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (1944, '0ffd087a6d3a8b28cbc759a2652f8cfdc0e6c2fd73e79c16f965e84a71ff03cd', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (1947, 'c7c09f8613a61fb6eee1f6608364aa1b1e2a42f6249770cefb00978ce72c4fd8', 'dx_finger_flexor_tendon_injury_93dca2c764', 'Finger flexor tendon injury'),
  (1948, '897d6843e6ebf967f0a81db3ea00ae211945fde4dda7445d14fbcf0966f67ea0', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (1949, 'c5e9f0398271440cb16bf63d9b649c3cbb1d3bc37fd2d373ec5fcb32c275ceb3', 'dx_thumb_ip_dislocation_a325ccd91d', 'Thumb IP dislocation'),
  (1950, '5155cf7d07e6811c34fcd8d1698d65617733928507f328f9f7fe183651dcf51e', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (1951, 'af6d277faf0b8d82dee3f536f54b710e7401066c98c27992cc03f7af7d8c1666', 'dx_tibialis_anterior_muscle_haematoma_b2d920156c', 'Tibialis anterior muscle haematoma'),
  (1952, '10f9e2042e79ac6e635a8dcf2ae90b794b699d520513a2c275e319befafa887c', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1953, '8ca17aa91bbfaac5dedd29ac811a7fb599f1d67a30b398fda8d82be3effa9833', 'dx_midfoot_injury_3332895405', 'Midfoot injury'),
  (1956, '58547cc776ebfdf20483ebfbb9accf55075cb9e36ba5ff2eeba7fd863b8b7ffb', 'dx_lumbar_or_buttock_bone_contusion_933e74a361', 'Lumbar or buttock bone contusion'),
  (1957, '7899f7f58301e082d2e16ed7192eb40eb2ab841b568d5445a94c277f3ef493ec', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (1958, 'fbb7693725a084706296ae5257d5e6e3f17528c035cdcdad732922f9c86a290b', 'dx_wrist_injury_d94414e2c6', 'Wrist injury'),
  (1964, '1c9274fbed0be442d8f47a83e3de647b47a8ae1d5b589c65ddc7eb9fb5397419', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury'),
  (1965, '298297bed819fb3ca90d1cc9bc0f4200f30c4d7fa160c650376f25b9401f441d', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury'),
  (1966, '90376b1f3055dd2e04a05f0b2c217a5ce7844bb2343e832f671547ce9b6650f4', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (1973, 'cfd1681afb2d33fd73e4054ff448fd9de4dbf8ee296998beca73d2f56c93fb06', 'dx_concussion_a91e1107d7', 'Concussion'),
  (1974, '41997d515230879013fe8db727cf97db8f38cf2df22b191fb857e77b3e343b90', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (1975, 'a73fd1052c0e4fb0afc4055d4b67464515d519573272981205e3ffb6e00375a4', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury'),
  (1980, 'b3d920451a8c05ccdbfe828a71db469e4f30a6dbbaf4ccc85f2b80365f6be615', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm'),
  (1989, 'b14a84b7c6a9e9b49a822c862ae69f7544348a60ccbd0aa06a43985db18ee4a3', 'dx_hip_and_groin_pain_27531edcc3', 'Hip and groin pain'),
  (1990, '0b1f7d211abb29a7b2dcc592d4b312d921f6c816e3597cba4b4734476da2b80e', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (1991, '444e40dfd2c937a1c3e1fe4b0debc8363748ad8ddfcad69d3a02f695459e1abc', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (1992, '023982fe060a212e0d2c84f4f898ff1b662068d177266b78acbe30089540d543', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury'),
  (1993, '583679aeb455cdc4c629db857d1ccbc632dc89bf44b3c3f6b993e268082f8027', 'dx_knee_contusion_94058fe1a4', 'Knee contusion'),
  (1994, '8f42a7ef198931173af637d969f8a9b44efe8a2ab2ded2173d9fe6b7015fa3a9', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (1996, 'cf75d141670f521c8b4a23f8fb648270f3cf79b09e21c17549cc02866d4a69b6', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (2003, 'b61af4e0ef58c8e6178162690bb755134292dbee18cc094a3ea6e57326d9cff7', 'dx_toe_joint_synovitis_df423d00d4', 'Toe joint synovitis'),
  (2004, 'dfcd27818667671a3feb509b976817e8a27839fd05df238de5923f640749d6cf', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (2014, 'e4d982974079cec3a6d5097eb8e9ccd6fd414970d782d81b66a5b82f97b4f52c', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (2016, 'ce1dbbe0b04b05ab12fc2bf5beb6468ed22b26e074c6bcb8271f646581034d25', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2018, '0bd707421fd32480094db05f405d7b649a727e9e62833bfbfaa73caea5b89bf9', 'dx_lumbar_facet_joint_disorder_4a13830647', 'Lumbar facet joint disorder'),
  (2020, '4fc0cb7db017ed0e8d8f7bfa7eb7102acd33de04b48d2d87183a3cbc9fea831a', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (2021, 'cfa9dad23b62aebb49a4a4b0aee19ec8993394254c5065c96b2aeffebffc2904', 'dx_shoulder_impingement_c2f2a634b4', 'Shoulder impingement'),
  (2024, 'f37d412f097699c4c054680bc9664439f165ac79c7286c573f346a4fa72e09b2', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (2031, '4d18a4f11007d4472d674aa5bab57dfc2e2a5b8414b35baabbcf261c12d24777', 'dx_nail_skin_infection_e50f92314e', 'Nail/skin infection'),
  (2032, '928e5d7cc0e11b38869b9f8fe6cd81d554c5efc19bf8eeefda706f5ea7cff217', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2033, '220219b80db7d2f5ecd32a7be99c0b7b1fab660fe8d8de28005ecb00c01e1901', 'dx_shoulder_dislocation_2067688fdd', 'Shoulder dislocation'),
  (2034, 'adff1c73bc5db1436bc8c3058c3e4aa267a1db15a0883315f2e7f47abec590df', 'dx_knee_pain_609ce718bc', 'Knee pain'),
  (2035, '5a8a367d38c09f463c01c11f187177a48237ec63200552c9dc9353ce9c7a27b8', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury'),
  (2038, 'e262611ac2c4b9299c093d94cf2c2eae697e97615a4ad1ed462110ff288c6a20', 'dx_hip_and_groin_overuse_injury_71c787dc38', 'Hip and groin overuse injury'),
  (2041, 'c70ba95f3e5ba4e5c1298f7c7f994a84e17d1eb4228762fb8bba93aec230afbb', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (2043, '436d16961f68a7222f826856036f3035824289d51cc54d5a499c0517eae9e1a1', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder'),
  (2044, 'e8f59e399ae6216dcdb53a27e6e4dd3ba1724c8be53ac66849079027178b9ff7', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (2045, '64e5dfd621c0cd19b77b9a81270a8a33da3033ce7793f8912033fca319c37b2e', 'dx_great_toe_injury_71c02ad835', 'Great toe injury'),
  (2052, '6882040f09a87597cebc64b4f72cb9de5ff0fe134d858b00da289f650a828a52', 'dx_knee_contusion_94058fe1a4', 'Knee contusion'),
  (2055, 'f7ef55066cc04ea8bd67fc48694066e4aaca1f5a152043be70e8c69fa77c2f6e', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2056, 'e1e7e189fc1011cc422abb914ebf025b610124e3761c84735351f3814a046410', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2057, 'b309f349e7c1c248a44fd2d8e35b314dded2efdbb89c8aa0674c9afcaaea8f08', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2058, '8cb1617fe1170285df6980857f6616ada75023d6461de164c6585e6d4c25d6a6', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (2059, '87cd33a1a7f33e4b4829ff2a4be408a072e993060ff283720f91ef0f6f15ea37', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury'),
  (2063, 'ee0a13b356fff0f12d33bba2e82f95b57e5bb8f3089206e87737305342968fe8', 'dx_knee_synovitis_impingement_02e229b1cc', 'Knee synovitis/impingement'),
  (2065, 'd1d702b3c4820cd5c29dda6c2dc2cfecd5e370efe200e488b92a7d810a548f26', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2066, 'eb3c0d107191a5e1ccb7c466ddd70460a85355d6c770cc3b2f8b1f6903a39aba', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (2067, '246e129ff56e6483f91e7afaf2e95e4e73f0e8b08075353b7779f60c0f0cf5d5', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (2068, '8001f3556b82d856539cf3c405922ce08beccbefa6ccc70a992efad69794bddb', 'dx_thigh_muscle_strain_or_spasm_73f7a9029c', 'Thigh muscle strain or spasm'),
  (2070, '21844587b100c9b7cc1336afd656416b6764d43421b0aeba04464060337ef1cd', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (2071, 'ecdf58d21d775cc5ee4ac06984052f27e032eefea539aa15387431b1bd7dedfa', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2072, '223b5b91b37266e2b9e319262cf20dec92c3ff769f54987fe45071c850b0b39d', 'dx_great_toe_injury_71c02ad835', 'Great toe injury'),
  (2073, '579182734a5c5c4bd929b09cd96458cf554e2ed3198140933454009740cae81d', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm'),
  (2074, 'd8bba3f64679509d8754028454ad61a9b9a446042bd2524325b42c79309121fc', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (2075, 'ff4bccf75cc84f0138a3489d012353ae4a805d6e57febcae81f2c2bbb2b80066', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2076, 'c968e4f0f1c2924eed42378a83b2d320a6ab056da5d801e09f44dc10228196d4', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2132, '7279685578588d770159736aa7110fc6a4ebdd03bd86ebacac9a50f1da9f071f', 'dx_sports_hernia_ad99f8552f', 'Sports hernia'),
  (2160, '8ea9729b99bc2ac527853127681edd32a7f1546781d1e1e101e9ecee715e248d', 'dx_sternal_contusion_160fe1df77', 'Sternal contusion'),
  (2161, '463ab85f12dfea9df6e281d4d11e523bc145f0985e780252c49242f130866fa4', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2174, 'f27e244f97372b7419b6e7ed70686e6ce7eb4d32ebdee4801e3926dcb9664e9f', 'dx_eye_trauma_0bcdc22eb2', 'Eye trauma'),
  (2175, '2af053b055e1ec74de0e19ffc196bd5aa1b1e3570cd7e40bfcd2e9ff1dfc6ae9', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2176, '4c81867c8e90521c3ccbc5bfa7ac7ee81c305e45c04e329a711314d14ed0ab73', 'dx_popliteus_injury_0ac29f0573', 'Popliteus injury'),
  (2177, '4b7b261f17ddb2b8658f37cf70ada48b6f48448aca06c4fe362b7a7219c0010c', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury'),
  (2178, '033687527033fc485cb4fbf2fc9470a64037dfeadd74dea80f98b52465542d5c', 'dx_finger_mcp_injury_6c586feb13', 'Finger MCP injury'),
  (2179, '2c99c06174468e4b65ccdd0ed7795fd1519609cb5d6941270f27e44e88de4dbf', 'dx_buttock_contusion_46ae636fd7', 'Buttock contusion'),
  (2181, 'cef833873641866a50afb0658dd803d69cceb33f8b0e2e0dd977cb07c0e33a87', 'dx_intersection_syndrome_59b79f8251', 'Intersection syndrome'),
  (2182, 'ea1e79e0cec1c9b2d6c150b89a1dadb33ec2e984771be8f089617067e9b90cba', 'dx_triceps_muscle_strain_0048495411', 'Triceps muscle strain'),
  (2184, '87297aebc1ea9e4c5f9c663a233a40c99d34dcfc8277045a3ce6145d6ee88512', 'dx_middle_trapezius_muscle_strain_60c4af025e', 'Middle trapezius muscle strain'),
  (2185, 'e9921e79f2103fdd1914588dc2ac7cd1db23c91dd428012e21fd1561a1f9ba55', 'dx_hip_flexor_injury_cedda9fa03', 'Hip flexor injury'),
  (2186, '4ae55ce3805bfd921826eec98b9189af327cfb1fb6fca0a159594971e0202916', 'dx_hip_and_groin_pain_27531edcc3', 'Hip and groin pain'),
  (2188, 'abe714ef42a4552abac2ea9a1d7cbecea5f813bc676075ca56371d11f03e614b', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2189, '2e1acb1d1dc4824dd5eeb63abc1dcffa0fc0084f14bb711ae4a0f7dd985b75e9', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2190, '6414260c5f661883b814abb9172d653e7adcd208d30d52165af663e0b925f825', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury'),
  (2191, 'fd05527bd0e4190c80185cd0e49c8f446244984ce457547e7e5e9db4f289d0d4', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2192, 'd6c8782c3d843c21d857715695a1921f60ae4190cfcd9ef25e9b9e96ded60281', 'dx_knee_contusion_94058fe1a4', 'Knee contusion'),
  (2193, '9c9af2e07d4569b6efc41f446285fdbf288fc33307563095596981fe48db652b', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2194, '476dfd5c4b6355f803da25047fd558b8c79d7d0818593da9fda0ad9267f7ab85', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (2195, '97a790e60fd8e730a0dcdcee2e56d54bdecda4f72f1c5de397e4a94ba9961fa4', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury'),
  (2196, 'c27b6b36362752763bd918fa12b68ae49a59f526320966f7eba6fe975ad4715e', 'dx_ear_injury_190079a2d0', 'Ear injury'),
  (2197, 'bfb7ad608e4e37ba1da45dda57014a3cb40e84202bd4293613bd92f1839df440', 'dx_thumb_ucl_injury_00b846b6dd', 'Thumb UCL injury'),
  (2198, 'cf4a4823d9c2cf627e7bbf354af0d493d0cfc6f61e424e886f682f266fb36d21', 'dx_ear_injury_190079a2d0', 'Ear injury'),
  (2199, '672cc6e815c0fc3da402bff1b19962a3c001618375f9539cf434b98426c0c5c1', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion'),
  (2206, 'cafcd1720045624436f0da366822943c5915e4f165af32008a21f4bf3e70bd75', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2207, '7a607566423fd5e192a4eef72f8e3e120ae547fde00a264b41c169a8d9f20be5', 'dx_eye_trauma_0bcdc22eb2', 'Eye trauma'),
  (2208, '66f61af217ea11202e064fb3b670bcbb86b0d4fec4f44b03ec4dc1d40524b4f3', 'dx_midfoot_injury_3332895405', 'Midfoot injury'),
  (2209, '367c15821de495510cd95f27b8772d983c5356b044d6dd8d37792a9f117eda98', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion'),
  (2210, '12a790a20c6e59f08cc7a7faf421c052c5b89f0d7fa0c4abf9043fb7d7fe3854', 'dx_wound_infection_complication_5415c9f38d', 'Wound infection/complication'),
  (2211, '3800b24bb8b836da8d6339231888cae96c162562bc78c070693e5c7971f56683', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2212, '466ac8a53bc8e46a53d7c0938b1753e527beebb103fcacc451f6bb70c0c3ecde', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (2213, '5034ccbc76245db8ed97cca7c0084a439c79c811c50015c492a0508c5d996adb', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2214, 'a82898f4e77b14fc79feede7434d24d049828fd37b6130ae4e4d2060b4cc2165', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2217, '3b4400e678e54085c3f4bf4268300171898b332f6cddc68b2492526c4346060d', 'dx_neck_soft_tissue_dysfunction_8f80031021', 'Neck soft tissue dysfunction'),
  (2218, '2aea1d9c4140e64cfd36483ac7d113b5b5eeef86ed2d39997a648f5aa84a4d37', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2219, '1b903012efd396cf9ba0e94bdbc61464c2070c2491c5da5aa544e9c6476bbb3f', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion'),
  (2220, 'd4136035ebf71d8b02189d0e5446de9e32a2d2e1f21746766d610604e3144ea5', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (2225, '17e5c2c0901a77f24553988778090402d6b837ab119147ab60592f43ccd0a736', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (2229, '4ccf47f47dcb89b1815d8434b812f94c76a546acf45f92095dcb8be1d48bf79e', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2230, '642599589440397890bc4240df5f30c93138da3e707cc6161841f565569c3ff0', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury'),
  (2231, '8340db0a666a1d8e57cecfcff9fef04e3c66f7a61ea3cba6de53049f97f1b9d6', 'dx_cauliflower_ear_d6361b8000', 'Cauliflower ear'),
  (2232, 'a7d2f672fb7b6be7b3d8df0edf7d57f833f1d181d612bcb2740f5c7eafb5ba13', 'dx_thumb_mcp_injury_2b5c0aa20c', 'Thumb MCP injury'),
  (2234, '008e4394ad7efbb0c190331c96cdeed5350fc62be5e4a8a0bf9887749e0787b3', 'dx_foot_soft_tissue_dysfunction_b977517935', 'Foot soft tissue dysfunction'),
  (2235, '1669871fd0f45fdd7eb458a41ece491053f7d6635a59245bfb7b65c8a2be0240', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (2237, 'afbf2b548581629f31203e842526b99284870735e57529aa3eefa150b040bae8', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2238, '33eb2b3547db36ad32c08a90a2737dcd1c331f6ba80849226e28b8f37b5338d7', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (2239, 'ac0d8551dbae8a5fa2798a29af9c23507bb3ab45d9ba5c5deda10925434aafbf', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2240, 'b310ab9d5489b3f641676b83f1ab9464a6faaa67ca08e51aff6561f50fef2828', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2243, '0e422e0718b1940dfe2d6c685b3554b5463751d86da490e30beee234648cff54', 'dx_achilles_tendon_rupture_6b59cc3783', 'Achilles tendon rupture'),
  (2247, '869482cf73c00fd437a328c5a66248c9d5451c092b4da8b3122c0bb39ff57b94', 'dx_tibial_bone_stress_fracture_2dd746f1b0', 'Tibial bone stress fracture'),
  (2248, 'c01c5b532d1eeea3ac782f994a116aa86d9e7842ed5754a3fe30a1cf2372f1b9', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (2249, '3d2b366d5b9ad5503fea4bb83c7204d20fd29eed0bf1c75eb33fb0816019e922', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2250, '50e0148a8748f35aa42dac8d0cd600acaf38265c5974fe9f4b688105cfd677ef', 'dx_lateral_collateral_ligament_injury_e3bbb5e542', 'Lateral collateral ligament injury'),
  (2254, '33dd9c2d3fce4ac71b428b0f375ee8fa73608d7209d02a7db7e15041541415de', 'dx_knee_ligament_injury_unspecified_7ab630d44d', 'Knee ligament injury, unspecified'),
  (2258, 'fcc3cc097d8f592ffbafdb2d8cb36def486814f56c29730dcdaba5a04f35cae2', 'dx_radial_shaft_fracture_5e497038ca', 'Radial shaft fracture'),
  (2259, '8d7b8e460ec2b4ca3df083ca397c61bb315dea2ff313cd0e9840642f6a5d860d', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (2260, '8c8dd971311c9dc171183d7d3a758df51b2369614f216449405d2e09760b112f', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (2261, '4c53d4aacf9424ec1ec266e8a4b0f549005c2271b70ff8237a86960edb920107', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2262, '31ab67972542dc1d39fb53b667874da7fa42d31d2d62c629774cb03327c053a4', 'dx_foot_fracture_05db66a2b3', 'Foot fracture'),
  (2263, '14303c1f0baaab880a915758085c7e7b8a8db961be0ee70e595920b0bfe4c095', 'dx_buttock_contusion_46ae636fd7', 'Buttock contusion'),
  (2264, '1d7142eb77644c8e4a724250c41d37c07b2625d5bee8d89608fa92b82e8be6e7', 'dx_tibial_bone_contusion_d98bda7b76', 'Tibial bone contusion'),
  (2265, '2bdd673030a8ee44b648f351f8ac7abc5af37736ec0ef724384cfc24a92917f8', 'dx_neck_muscle_injury_500aa507c9', 'Neck muscle injury'),
  (2266, '935ea59cf6f9f947786cb9351ec45f14c927b7245156d90f07c2cd88ec967746', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2267, 'af4385a2c1622918ef742b2d19899a3f37d3cd9d53c81a7757eb9ce032a5fe9d', 'dx_popliteus_injury_0ac29f0573', 'Popliteus injury'),
  (2268, '3c8509524d97012aafd615e26bca389000c003813d21cf0f0a640d8842a957da', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (2269, '7538c525a4070b7282c200726f9888f694fd76d64f72a2c0126b9b664a81be6f', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury'),
  (2271, '4c9b5569e7d27b6bade23f1efb375afab51c69d6e143e75d52ec859991969013', 'dx_midfoot_synovitis_f3756228a1', 'Midfoot synovitis'),
  (2272, '8f0dcee4b28ebfb0dbdccaf1ddc65aa39e5e6885d3c7f5557f97f5a857a442d1', 'dx_elbow_laceration_66e6e36448', 'Elbow laceration'),
  (2273, 'fe36f49227d4ba1049581f616bf61882e184765a5a55de4ad4383133a6e14c76', 'dx_buttock_contusion_46ae636fd7', 'Buttock contusion'),
  (2274, 'a1d9528ef038a8098617a999a6ba8bfaf587a73730c52326dcc6477c9ad3894f', 'dx_quadriceps_tendon_injury_08ea99efaf', 'Quadriceps tendon injury'),
  (2275, '13f217c8ef35100fbc5c748e5d1360b1c3f65c90adcb1d058b9922ca279debda', 'dx_shoulder_instability_2b9f54f442', 'Shoulder instability'),
  (2276, 'd588f384456ff3a26eeff8b6417db603e04c6ea86e980708db16c61f8eb65fc8', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2277, '76c82617bd0f035d29f5d68fdd7dac46688c1c0383089c7788303b951215683a', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (2278, '138f47ac2177ad231f21bf6d918fed502bd3d0db7b4382b3168fcca50c4db535', 'dx_supraspinatus_tendon_injury_3840a1f333', 'Supraspinatus tendon injury'),
  (2286, '8582fba133c5fccd1bf87928d63a4c650c9b940e57c5f648d41a31f99d5ed0be', 'dx_eye_trauma_0bcdc22eb2', 'Eye trauma'),
  (2289, '8159d1eaa098d716621e8394d5e4b39aab724255d973d7f2fd30d75ea43a8337', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (2291, 'b187159c73083681dddf72add5fb2311eeb04f8c9a35233dffabf71ce751e2cd', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (2293, 'eb302a20bf6963ae50888c2559676c921de73cba197a62f2a0a172684d611305', 'dx_knee_ligament_injury_unspecified_7ab630d44d', 'Knee ligament injury, unspecified'),
  (2294, '55bf837f4aa4fbd789ffd1b442dbd976dd1154ab0d88764aedd97faf94ff6cfc', 'dx_pubic_bone_stress_reaction_ee1dc63e02', 'Pubic bone stress reaction'),
  (2296, '3fc25d71c9da0d10cd153a757df84d4caf0d78b46134f14df08a6d722cbfa7af', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2297, '1dcb7fbd616b237fa014bf3764f10a979d065ec4cf02460024f5d48dbf0ba760', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury'),
  (2298, 'd1ab6ef87031334ec428a4381a5f112b74d5c205607afdc0144f397d0f9400f9', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2299, '7cedd1bca40c5f6aafce4539c35a549de532c90cc7cafeb6db5bf1cb433de28d', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury'),
  (2300, 'f6d013658aea03315e8ae3d39504171d3e2d2bec36feab691bcd9ba28579234f', 'dx_ear_injury_190079a2d0', 'Ear injury'),
  (2301, '57ec1863f4f24be4f04c86aa2d24051cecef332ec964ace08b7ba9f3f16be169', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (2302, '701870c681f9ff7167a75599f0182ede5687e1ad4f65274d642729352394d0ed', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (2303, 'b91dacd95a3449735f2a3d7ddcbab3a139ba74fcd0d5066704d7e5940d82c295', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (2304, '05f060b89f5e4d1607b7082a80ca5520e3f20ba752ff07f05beb27ec8e554ed5', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (2307, '6289dca6452bb21f58a29de260de665848acaa4c7966c419ee8387c66503b9b6', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (2308, '1ade50f7e219ed3cb97f60365e76edf3d8fe89fb1e5c640bcfe0a5de04cb1dde', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (2309, 'a6605817c8e8a611ede2cc055c17ce3eb9437134ff24117aeeeacc725b155043', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury'),
  (2310, 'ac2e4c956e18dc1c511230cc5fa991cfa31d8cf097e95e42b053ddcda287cf6b', 'dx_foot_contusion_6c8a5bb721', 'Foot contusion'),
  (2311, 'c0f1ef8caaee29f28e03e2a65f6fefdb71c61436b76ca0b26a32b7e90bb0672f', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (2312, '319f5aff1c97b7f7dd6199d8ca4e2b7a5ff5ccdaf39e5f871a29f15a25252317', 'dx_wrist_injury_d94414e2c6', 'Wrist injury'),
  (2328, '8600c79ae5d8f25fbaa3aa2e8cfcaddf729c1cfb3216b8fc74c5cbd116d58594', 'dx_wrist_or_hand_pain_57c9958c78', 'Wrist or hand pain'),
  (2329, 'f2607bb3ed321e16be1d60723d46ee80fb06674f007bc16c4a095084c1a99b7e', 'dx_thumb_sprain_730d144cbe', 'Thumb sprain'),
  (2330, '60ce4a9bf2c447cae32eaeab2eae5497bf9341fe2c79fbaae9937a2fca5d0167', 'dx_ankle_contusion_beb9f51162', 'Ankle contusion'),
  (2331, '60aace9e115118065f1cd41b407f81fe33760c6788584893a2666f8596b0eb14', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion'),
  (2332, 'c235721450393aa02723cba9d4e88772a646838b43a8cbf4af571942c5af02c2', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (2343, 'aecfd3b1712322d2f5bfa5c1dbcdce350d009bfdfa1598df1a3b61220414c02b', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (2344, '0779f15f91dc1141f1f4657e1d58785d3416ab7072fc3487b5e60b5adaf817e8', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (2345, 'fda91740e5cf5451064a14f74963822768c1f6f025553f8cf30e503262411eb9', 'dx_pectoral_muscle_injury_981511cfe1', 'Pectoral muscle injury'),
  (2346, 'b63eb89bb91c66a9d813648230a1fb91702bc933f393d4a1b823ecec7541fe00', 'dx_knee_contusion_94058fe1a4', 'Knee contusion'),
  (2347, '93504dab94cc2e654d63cebbbb18b8691bff76d1ec13b4e85e9ed9c556a5529b', 'dx_elbow_injury_7100f71f81', 'Elbow injury'),
  (2348, '30646fbc32061af68215d413806ae853008a61e87308deced458f7b469d8bd55', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion'),
  (2349, '339b5bd541fb65ef469d767a5b14f604127b3dc867c3e094e2a12e5a1cf51ac9', 'dx_great_toe_mtp_dislocation_19361d8e58', 'Great toe MTP dislocation'),
  (2350, '83acd9afc693f97a3a9717b70c0aef8ce656e75b0f0aeb3dbd5fa87f9831ebce', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2352, 'a2121f8cc03ddfe020a3f1f95041d5e6f32d9adcdd0451b017f88a128e1d91c0', 'dx_rotator_cuff_injury_0744f75c4c', 'Rotator cuff injury'),
  (2354, '214177e05b8e43fc8fbc6d6b3dfec528f48de64793f0c15a08ae66c8fd1e628c', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2357, '85a9ed8254b0824dc8ed99c0410705e3308b71c7187c04503f5fa23fd715ec3d', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2358, 'd81846e5f48fcf042f6bc0e58aea519704ac04d5ac8345f225f5a3a2a82f3e64', 'dx_nasal_fracture_a291a11f04', 'Nasal fracture'),
  (2360, '68cbd8b02ec513a60cfc535c363d5a92b9381fce4432f5fd44372b7717958a57', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury'),
  (2361, '8c8f3601ca055201b3679242bcae2219d332b23105b94fa56713d292af1ab96c', 'dx_heel_bursitis_d80d084f22', 'Heel bursitis'),
  (2362, '38fd1535e0514c52794e0f66498f32b4db05d79ed3e1b20375db1d3736b3578b', 'dx_shoulder_dislocation_2067688fdd', 'Shoulder dislocation'),
  (2363, 'fc418f0f6d8e0c8735a5f77308860696d508ba358c6a5509d58a381b7280b54a', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2364, '167ca6c82177cc6b11a61ddc7a4c0f4db712eba413dee0742384d5133d5c306b', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2365, '78f71f78854dfe1d86fe63ab98c6875aeed7c6378449edc6b03de40e3b1fb040', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2366, '4b18c9107aa47b3068d268aef0b97ff4dbac2230eb6702696963ce940801fc75', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2367, '298d202e6f7dd70a5654180b233a6d4e0f579b93f69df87ec09573f2f74e09dc', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2368, '6b64578537db8a67c77f5a669a2f23f9d2ff4b42af65c32434708d5d980cf7d3', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury'),
  (2369, 'd974edd871b3653f4c980cdbd638587fb0aa8a1768299a409126fc32ac0b2d94', 'dx_achilles_tendon_rupture_6b59cc3783', 'Achilles tendon rupture'),
  (2370, '30196469e7ae876f9531a65c6c9cdd51cf9be2c9a5d4ec5e385665f3ed21fc56', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2371, 'e719b37cb7f9bc3ffe1ea54ded2615d676c2f85a660de2f8a963213b28a79c53', 'dx_forearm_contusion_ea321e8e45', 'Forearm contusion'),
  (2375, '760fa4a5e26edd4cd418dc331a3e3f8bae410e18558c5c19e0a7067470455738', 'dx_acl_injury_4b8eb47e96', 'ACL injury'),
  (2376, '23ab0af865a904d8f5b0394b4a97dfe0d4f1fcee0773955623304e7867c19f16', 'dx_knee_contusion_94058fe1a4', 'Knee contusion'),
  (2380, '5799aa4a47ea0fd16faa6281bad4cb3c8494afb2c2f1b69d6b09d2221d142895', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2382, 'd9b486e4814a5b36e96d941b624eb671852396490bd3cbf0609f8cc8c450721f', 'dx_neck_pain_58ed6a0781', 'Neck pain'),
  (2383, 'cd048e02aa8acefe9f292b1a8042c0b5c5f69629eb5fa75f770ef1a8a67f294e', 'dx_neck_sprain_or_whiplash_404e63fe9e', 'Neck sprain or whiplash'),
  (2384, 'b2e6f4598b9e0d688d0d961fad1a9e9504c0894bdc08bfa3272940249d3e4db5', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2385, '22b5c746bd93116fd5f6e9aeba4cf3c328aad5d6074aa9cbedbd5d2976a04e27', 'dx_ear_injury_190079a2d0', 'Ear injury'),
  (2386, 'c53fe1845a8218cc01fde690da704a3d983c79f5ae78fabd47224f379ecd37d8', 'dx_scalp_contusion_or_haematoma_3665ef31fa', 'Scalp contusion or haematoma'),
  (2387, '089d1a1a29e149ccc4c88a7effeccb260bffc660108aae7115997dfd52850b41', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2388, '473abb4ce4636cf2411d603353a8a6ab41063048a0ef9fd9d2070432ad9d8665', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2391, '6d9b2ce5e3aa6d05adff556c20c80c2d4a0d89d277299d0dd0cc3586925a4413', 'dx_patellar_dislocation_0c3c5e687e', 'Patellar dislocation'),
  (2392, '503d099a08af9adfb7e8cb8cabaa0ec99c1f08611fc4a691b566c1786650212d', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (2394, '68aa8b7d1968dcf874a0933e75ec72195ec8eda79c6feafdf9c893952f5a9643', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (2395, '0086b710e99db746c6038dae65f2ab850dff62b0537e203f517201cae34f130e', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2396, '173989e965189e8330fdc770cc03c42e8b2be8eb7375c1e54d0bf9c18e1ef8b9', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (2397, '18bcaad97c1784ed17e59e0b8df2512ef967c8ad2f7f555b0fbb93de8ec241eb', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2399, 'f961e9c0b7d0ebacac038ace784503c9df2990ed350b7ef71efd83fbabf39d7f', 'dx_eye_trauma_0bcdc22eb2', 'Eye trauma'),
  (2400, '1e6e63c90482aaabf261e34f11da208dcf2665dcb4d32b794dcf2f78692520a9', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2402, 'f1d408355992a1705e1561503a6eae08f0e4bbe85453b9243ecf1698d80208bf', 'dx_heel_blister_95bb983137', 'Heel blister'),
  (2403, '72d236ceb846987b09da1bd2fc27c3c4b570b4f14cd539a608f7923ebc9f7240', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2407, '83cac072a5dcbb3a0a1c1262af56e6bd8b843dd6ae62ee3b202c4be7eb2e69bc', 'dx_shoulder_contusion_cf0de68001', 'Shoulder contusion'),
  (2408, '54438c869b9737e8adb25e5488e01a08e2607b23a570846fc4196acbc524e8eb', 'dx_great_toe_injury_71c02ad835', 'Great toe injury'),
  (2409, '88a7f14796de586a10f4fdd8161c17396005b66b66ad461a5494735ae7945099', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2410, 'ffe9588f4f2cf1553c93577444b5f24b90cfefcbf98ccc0968f8c409d96e0e2d', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (2411, 'e98a03f6736792055dfcf066d78bc36e2c146b0e6d281a275a3e70e5b184991b', 'dx_upper_arm_soft_tissue_contusion_or_haematoma_9e41a8da30', 'Upper arm soft tissue contusion or haematoma'),
  (2412, '27ab046f7147c288abb311d012076308fb1914996313a6ab410dfc5d7aa2c617', 'dx_pes_anserine_bursitis_3af1f08842', 'Pes anserine bursitis'),
  (2413, '51a3e2024961f33f2c8b7ad14107b6b4600c45bb3e9c09531440a39dc2d792d4', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury'),
  (2414, '5794a50692d80dd16a367c72720055032bba74b410ad012da1b8026d76b9e9b8', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2415, 'ae1d9530df78587eb971b1cffb5335877a5f355836e129e35ecb8b920add9da4', 'dx_neck_contusion_7f04c7cc90', 'Neck contusion'),
  (2416, 'c46d274acd64cf83568357e11f724a4466e0ad0771364f934b36ceb78d497dbf', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2419, 'c55bfcac85af7574a26422b3cdd7b5a2b11bd9231233a0ab288915e5b9df385a', 'dx_wound_infection_complication_5415c9f38d', 'Wound infection/complication'),
  (2420, '2962d90087e5d13fb3448283fe451bc8bce6824a6d374a4e776ea56c254ba4be', 'dx_trochanteric_bursitis_32cf79258b', 'Trochanteric bursitis'),
  (2421, '04e014e2fe9e619b1966021aa8a83696bdda6680a4a66e9f16de7fe61454ef95', 'dx_wound_infection_complication_5415c9f38d', 'Wound infection/complication'),
  (2422, 'a1562aec909f4a09e072c25afff3a171af860d5b9e9be0b73e0053590a08a359', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury'),
  (2424, '62c16bb29397bc12be41e5383e41b4ff35dbc8d74055d41d87d64911e33c9152', 'dx_knee_contusion_94058fe1a4', 'Knee contusion'),
  (2425, '0d0a71f2c9dd48711f0890c8a5e8f78b72b8f3050bcd1f1656738bbbb576edf6', 'dx_neck_pain_58ed6a0781', 'Neck pain'),
  (2426, '2a2133e85a7670805f6e15dc5e4731dcf145d5a02ca94ab7ead1f03801dc4473', 'dx_biceps_injury_69e895b576', 'Biceps injury'),
  (2427, 'aa4de56a0f6aeaf09f60e7523c8ff955abb590d1b6368e272e1419b273568c9d', 'dx_trochanteric_bursitis_32cf79258b', 'Trochanteric bursitis'),
  (2428, '2dda95c3c39a0cc93977757ef464fc730d63966f0cb0d846977cfb7fbed6c2d3', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (2429, 'bfbcfe84f083ed6f7e6a0b7f1f66ab2793f4b7ff3c4899dba6a5bec7dffdbe36', 'dx_buttock_contusion_46ae636fd7', 'Buttock contusion'),
  (2430, '4166c3dffd5e4c3c932d6a87c1dc3f4ed72533a48ac957afab60e65b93023435', 'dx_neck_pain_58ed6a0781', 'Neck pain'),
  (2431, 'c2927e682781d3411c7032567195e181b408124cef7e7f1533bee593cb63b235', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2432, 'f482cee99b5fdec368690b0238376db9e9b5c779bb6868b922c168d1dea6335f', 'dx_brachial_plexus_traction_injury_61f86c401c', 'Brachial plexus traction injury'),
  (2437, '2749b07c11b053fe7f4ff428438f016d78106e4dbf3eb5bcd31f4cba21c83946', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (2438, '3b5b751cfffeb763490e2bf43e29035c0d2b68dd175181633c813d0244cc2e26', 'dx_foot_muscle_strain_or_spasm_70d9a1ebc9', 'Foot muscle strain or spasm'),
  (2454, '8e119eecd1cbf1e52575e253775251bd75dee04bd255762600a5d3220664b455', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (2455, '66863d5681819894a4429242ca684f78d8ff16fe2cab977c57822df90fdbe651', 'dx_rotator_cuff_injury_0744f75c4c', 'Rotator cuff injury'),
  (2456, 'ac5e9bdfb5befd3506335f45e3e2e3117ecc82c4cf087af95be1bc184e3f757a', 'dx_neck_muscle_injury_500aa507c9', 'Neck muscle injury'),
  (2458, 'cb374f0ff15c005436bbde3044886e3c02df574a5152aa4a3cb3014aef96c3ed', 'dx_spinal_disc_injury_e3b980b6b8', 'Spinal disc injury'),
  (2459, '6b71851e5934125e6cebc778ba99de35bf971344f2c86016d9a77b0ada2cbb83', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2464, 'f12b30f431f38c78d958ed072a944aa28cfe030fb11c4d7b34490fa23471913e', 'dx_knee_joint_effusion_65cd9bd317', 'Knee joint effusion'),
  (2465, 'b7e8d65327152edfda08a0a09131dd7181cf6005f573d4f617c6026740ec500b', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2466, '48f2f697269ece54132271f357d26b8c2b1a9abc8e9ae9d4f255e7f8c970484a', 'dx_tibialis_posterior_tendon_injury_8ddfcac54e', 'Tibialis posterior tendon injury'),
  (2467, 'bec472518b15784f2b9146131ebb784fc2ad1d03d0a0fe83b74a881d0d65c76f', 'dx_spinal_disc_injury_e3b980b6b8', 'Spinal disc injury'),
  (2468, '7c030df8b3a8a56fbdfb5ea32a4946f4a489bb07cfd65d904fd60f3e54f19171', 'dx_biceps_injury_69e895b576', 'Biceps injury'),
  (2469, 'e7816e0e872b2a337b5a52898147f761169a10a650305f963f4e7b3c33fb56f2', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2470, '8a8711cb75d879450c6dbb60aa0f5e6ffaaeb73b8c398036d2b3999cdd30b6e0', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (2471, '03bbd1b35b2f9044d197c6d1918abda1bb67dc655401dbd17d92679112546fdb', 'dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b', 'Plantar heel pain/fasciopathy'),
  (2472, '1532f4da600715c721dbb1410a303cf5706441e255514e436b21b844b597567f', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder'),
  (2477, '93d1fd84902c3ee79071ccacaad0d7480fb8c4cede347ffa96d18608dcd09a9e', 'dx_pes_anserine_bursitis_3af1f08842', 'Pes anserine bursitis'),
  (2482, '11c46c8de1ba00d51d74261f07853589b7c38f5aa40c351e8ed2bb2bf0eecd4a', 'dx_lower_leg_laceration_5e3fbc19d5', 'Lower leg laceration'),
  (2483, '63a437278f8d4da705b5c871e23e89ff793a6af1456a7af24eb5f5d57f8f9176', 'dx_rotator_cuff_injury_0744f75c4c', 'Rotator cuff injury'),
  (2484, 'e956387af8d1b8d840cd961483082c26e7fbcb8d8654074911612851bf9d72d9', 'dx_lower_leg_laceration_5e3fbc19d5', 'Lower leg laceration'),
  (2485, '009a8e157d68c0bd93af97064f63591cb3d884bc7451194db034b8c91224b7ce', 'dx_lower_leg_laceration_5e3fbc19d5', 'Lower leg laceration'),
  (2486, '34e94a8cc5d216abfe0ba652ef1b73c6ce45e4754537db9088b35907c2d003e0', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2487, 'b0e3dea505c7651ea2d3a824e5ef636987b414f968935d0e6e8359c7bb1e8eb1', 'dx_biceps_injury_69e895b576', 'Biceps injury'),
  (2488, 'ebe65c7d0817b7a5ab4f246a830af91ea1105c8abd2b373473da1997fbc07c9e', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2489, '04b13dad1ebbd32a25527f0d10f36c2a0c22b18de646f32e97f0879e51c038cd', 'dx_thumb_ucl_injury_00b846b6dd', 'Thumb UCL injury'),
  (2490, 'c334ef83f87b1ac845e9a4cdd1dd0a33b16a5544b5a7dc849052e3bd11b0e918', 'dx_thumb_contusion_or_haematoma_7a219de27a', 'Thumb contusion or haematoma'),
  (2491, '7a0a1d0f86311878c8e3d586e038d3222b145e006f6d799f16cb37fda7a7b4f0', 'dx_lower_leg_laceration_5e3fbc19d5', 'Lower leg laceration'),
  (2493, '350cd657d36c85640a96edabe93b025af5a5453f43b374080d45273d1f54153d', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (2497, '5b83a234169958620b82e0f0d819c45b08dee5b75b60725c09ec8a3096c91892', 'dx_tibial_bone_contusion_d98bda7b76', 'Tibial bone contusion'),
  (2498, '1215d54b8da1034837a38000e24cd1903a7640eaec968d86d1f8e1dbc478f053', 'dx_knee_ligament_injury_unspecified_7ab630d44d', 'Knee ligament injury, unspecified'),
  (2499, 'c08cf58b4626d2825496d495dbb4ab5016d2c119c8bf6840c6dd497ac1059268', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2500, '90172616bcd39b679f7339593053a728d6b5aa5ffce6209fab87c97a9c33975b', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2501, 'df9ee76c44f02fca9fcc3800bb43a09e84f3e5f562d13b40812d18c6fff95f86', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (2503, '4272a41c0880e0a40ebbc16a3d02589c6542e8b46e63c5d4aa97c3cae6290fc6', 'dx_pectoral_muscle_injury_981511cfe1', 'Pectoral muscle injury'),
  (2504, '2532905e067e22f96c0d29331d74e21c80d57e22c76b970087d4fde91169472a', 'dx_patellofemoral_injury_a6e2fe370a', 'Patellofemoral injury'),
  (2510, '320960668d62499f8f244a449ef1203b372cae4da24402a30d9706d26a3a815f', 'dx_shoulder_labral_injury_c99b83bba8', 'Shoulder labral injury'),
  (2511, '6030f68a024b192d5183ac75f5aa25541d1b0584d48f7dc3964996743c62be29', 'dx_sternoclavicular_joint_sprain_6316623d10', 'Sternoclavicular joint sprain'),
  (2512, '50824510649333bf51086563f87ffd69e5e5397c52dfbbc228bcc2db7887dd44', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2513, '72c0797ed407df27a95bb15892f018d063d7d7b852643c0111cb12d9c7290066', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2514, '3713a580ce0513abd34203471db7ecfb890796e63884f6650c3ce94b1bf00c54', 'dx_thoracic_muscle_strain_or_spasm_8b7d429120', 'Thoracic muscle strain or spasm'),
  (2515, '992f09cd3c35831cce90c566619ea6f411737851e12630fb1f48160c8f802176', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (2519, 'a2425333b299c96caf5f7e6866977fefa4dc01e2e7e2c126cbb6c8993a2e4d68', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder'),
  (2520, '5e124cde3ca08039319e34af3ad5675553aabc638820d4e1cc6a2c0f9547234a', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (2524, '909f36d9ae873663f8754b5fa2ff91a47b2c82f60d6810a477e2dd8e5c50f6e8', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2525, '4b5301841ef602e40d1fd2b7d9c418b876f58b1fd0f493f434fb4c94d2416190', 'dx_cauliflower_ear_d6361b8000', 'Cauliflower ear'),
  (2528, '1c5dd2106e65d96365cd0455165d9d3f09e72183b06f00236f6586c89700f1c3', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (2529, 'a23f1b8e5778a9abb2e3972c952b4474dd235e2a207628a4b9cae6d43c8a1c4b', 'dx_shoulder_instability_2b9f54f442', 'Shoulder instability'),
  (2535, 'fc13bd02fd4915fb9cb8245141998afd1e22b72fec15f90b371270b92dd0e01e', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (2536, 'af08d84cf37ae9d94effb5e8ef4220df242e3c32e027247fe47dfd0fa26f81d6', 'dx_hip_or_groin_soft_tissue_contusion_or_haematoma_125dafb4d9', 'Hip or groin soft tissue contusion or haematoma'),
  (2537, '13b21a8e175e70f00b3910e5fb91de1a05de0d62cd5672e7e2a7640d86fe621e', 'dx_pectoral_muscle_injury_981511cfe1', 'Pectoral muscle injury'),
  (2538, '3b061806297b8693094de1f7fc51d6c11ad267ab5394e83d81200d9675586f8c', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2539, '28044865d5b52e21c3d00e748c5c20efc7996f4b5cbf2c7f432a08b83954d679', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2541, 'ac98ff7d5ccb35c663296cbceae31ddc4985cfcb0c9e7885505b3a2d112162cc', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (2542, '0bfaf3b13d6a1350b1c71e0f3de184eff07a9e1f387887159852ecde51d212f0', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2545, '11d8b60ae87a4178a56dd1609377d725801b04345b37bcd04542959f6daa491e', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2546, '64c95b9e2370ad0fa2f5080d3bfab815a8b70d013704acc700c94a8d161667d4', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (2550, 'ff66872bc8b839138cad1a16e9426157f86553654a8d3da59e0c870da41a632d', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury'),
  (2551, 'd477741fbfb4ab5cc71010c8e6c38940674b4171b9a90f7aa960e1023477b4a7', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2552, 'fcf667e4a425ff8325729a1f19840ebf120a307d02668f54c16ead056220120c', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (2553, '0ba36023d85141bcaf52a8d9f543fdb04b7e8616e30d2a0f146841ba765e542a', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (2554, '1b2a503a187a58cdb7f3ff212f7247316e5525402addfe2752e423821ec5df8e', 'dx_eye_trauma_0bcdc22eb2', 'Eye trauma'),
  (2555, '19ef4d9279d875a822539bfed27fae1a9deb4faa5a5fe4a6c31b3d616823277d', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (2556, '02e6f90e267f156b77f3f4e014741ce80a5de671c12d420f4e2e08e0d124c6ff', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2574, '78c96605db5052642491b9fe11cd6f8f3f0fde9c85d3d8503c7c9c65f8446533', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2575, 'b847b9fb485d40ed0b2219c8f24e0270d3de4a67093a932af2b7f8826ee5abd1', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2576, 'd5004e0811e9fa15bb2c53d8adb6f2421150e4c41378eb285e0e1d8a79d71428', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2577, '829c67a479ea469aea98700f51d0b93c1c17bec11a3c43411e5af37eae7ae2ec', 'dx_foot_contusion_6c8a5bb721', 'Foot contusion'),
  (2581, '6d1e0b0a4c7c3adb910f211815a7fcf3674cba969300ebc0a55cd5ea455a110e', 'dx_nasal_fracture_a291a11f04', 'Nasal fracture'),
  (2582, '2ec16112c4f813a6e94eaba32c5baed7702d65fc045885b62482a4e34e985e31', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (2583, '3672efa581314853fa2a2c9214ead5600462fd91f52cb16976f15607d9ecc9a9', 'dx_foot_contusion_6c8a5bb721', 'Foot contusion'),
  (2584, '73f73157e09287433f1c812e9cb3682323d9d2e16d3da02a6e9bcec2d21c86b0', 'dx_eye_trauma_0bcdc22eb2', 'Eye trauma'),
  (2585, 'c9508d4d04a5cc10fe6fbe283a9c7b9b0cd17bb615e7501e99ece78571c85c55', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2586, 'e0f3677b76c5c8b47680fe2035a414f12bebac1f00fb6559f77803ca93336878', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2588, '335fda0f3ac4e104d107e9dccf6edec2b33030f3da26013ad316270e554e9cdb', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2589, '512d05d89c4154d4faafb8c3f5cd0f5085986f1c67c6497a425dbbe998d718ab', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation'),
  (2590, '62b41e576b407d4f1be906a4c74a200de5c9e6cf94fdf8838a26e2de6766034f', 'dx_thumb_nail_haematoma_b3559f250c', 'Thumb nail haematoma'),
  (2591, '45ac2a6c64afb320c36bee3be14fd8ac1a1b31ced97180e1d5c58925ccb6877f', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2592, '43f01b76160e4636b87caff6bcafbcec43bc3cda6950c10fd40e99b8cd831c9d', 'dx_elbow_contusion_ac2f8ee65d', 'Elbow contusion'),
  (2593, '48b35a4115c37b86e357d2a7d5770bc9b48e306c64109c3975d18da626d80701', 'dx_shoulder_joint_injury_28bd49eadd', 'Shoulder joint injury'),
  (2594, '2711244e179a7a94c25fb584f4a02dd365013ac968031bea30b9dc629313aa7a', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury'),
  (2595, 'fae037330d1b93e40c5e03fbda6201da84a2d8620aedc5063363c8a0200358e9', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2596, '9679d21ce6308c503f4d242e48512ce8ac6c5382180669e397e6bcb319cf9fb2', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury'),
  (2597, '249967ce2c2c5e4f79f01bca0990bf189acea14e628aeb15a1c60385f88e2d35', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2598, 'fa1bb7e5e99e50f6b5b34889c6ac530e19f7fd58f9445cc4808ebe04da780fbd', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (2599, '37c21aaa9d508f8f9f261b7a135d558526b98a11fe81b0cfa864aed38a7779bc', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (2601, '9df33df15178093ac37b83aa3663561f8c73dfc48897ec604ce07c088e38b145', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (2602, '1ea5da16d30d02af71c2ef647aa43136e0204d14334a3538d004cfc60e066f2e', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2603, 'e8fd96ec36291c91ff9b6d8219fcc65167698755979df6de44e77ee639f02e61', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury'),
  (2604, '06b7b21e37453068eef6d4c990b4f20c0f0c3d8c289ea197cf25cb24bd82ae01', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury'),
  (2605, '6a065606bec6491c438e5e3016fb175baae501896dec6031d5c809c568751d8d', 'dx_hip_or_groin_tendon_injury_99544a4bce', 'Hip or groin tendon injury'),
  (2606, 'd3235837aaf5c6ba4b9feb77d2f358171c87e536b1d66a3a933fc0ab0c452561', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2607, 'a9460e51a11fec9f3e84ee300e8c0448c0711706edc2ca640cab098d6d7785f1', 'dx_chronic_ankle_instability_ec5aa4a147', 'Chronic ankle instability'),
  (2608, 'dd76475928abe6ffc85fb5cd98c07aa8b956837e47f9b11fe94b6f39603eeddf', 'dx_pectoralis_major_injury_ae7aff3738', 'Pectoralis major injury'),
  (2609, '0242e6504517b27a5c192b4c0c3fbfc7c10f263075ff2a8eb749af15fab72571', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2611, '85114b27f10660aaab96da778bbb5320c0aeba8f4913f94e0a45b74d00175445', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder'),
  (2612, '4e1c6606be00a091b773272eb508ea292cfbce17581fad236a74d66bb0e76919', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (2613, 'dcb72ae1bd6ea6fcfb8a3022273c78bc265d9256c764c6bca933b02eb8c2c654', 'dx_acromioclavicular_joint_chronic_instability_299408db68', 'Acromioclavicular joint chronic instability'),
  (2614, '5f3a58d9ec5a24a7b2179e916575bb1f4bc1d48e8e6dbf114986faebca3bcc95', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2615, 'a8dfba0da81a445534a171498ccbbd74317b28e3a5a9667057478caeb6f2db8a', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (2616, '8fb05819d722bb217082cd2b016c2438dc603f4e6489305f0d3b8a4fda8aad84', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2617, '035651b3d487699be83d5838d47c7367d34514ea0cefa94a34ea8722bbd8e424', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder'),
  (2618, '9f7249f0da4172b211b6ac71ff5be8d05dc5514770a8a1a44f272c18b1f4679f', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (2619, '9ed4d7a708053b433e4b222019d57b9cd7d7ac8931b44a411ee00924b92b15d6', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder'),
  (2620, '339d3dfd044d094ab8a65a5725f63c0e0ce0edce6aa4fc2ef0831b8c0bfabd6a', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (2622, 'abd34cb88d28e3a8667e84db0248e0e7e1911bc5e3fe72df24054fc1ff90a3e7', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2623, '3da9f47435123ae976b8106778f09980f449b833f71e15febecab65a423ef25d', 'dx_lumbar_facet_joint_disorder_4a13830647', 'Lumbar facet joint disorder'),
  (2624, 'f6e26c744730312887c9917b27e18013b7149bf085ebc90699ba738bb3122ca8', 'dx_lumbar_soft_tissue_contusion_125139d685', 'Lumbar soft tissue contusion'),
  (2625, '35480620895f363fd275530ce25d2daf397a9bf8947caf8f4b05180f1bb7e455', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2626, 'a9f5f1a6b6beea00637d22c42924945e664a56d319a2b70ebbfe415dc391cc9f', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2627, '1ec958b3e18ce1631f0a58f253dfa7f052a1fff9daa7b69872309d7c8e237e04', 'dx_abdominopelvic_soft_tissue_contusion_6fc95fc1db', 'Abdominopelvic soft tissue contusion'),
  (2628, 'ceaf86180b9ab4ea5be0c0b8d418ce25e8fc2e1c1d344363be0d828271742aa9', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2629, '93c6cb966c4b9772b6897e2509ddf6922b5ad164e736e171fb90fd81e7d4debb', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2630, '286ccb1b87747d9bd05581dedd4ecab04d1e3e18606e9c776ae804d8cafe88ce', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2631, '040b42508525903a4e99096a327164f178990bea977049bec22a0ce0c1ad9c14', 'dx_knee_contusion_94058fe1a4', 'Knee contusion'),
  (2632, '52c0ecad4d70b116ee89a2625df28253e614086c3fce989afaafa5d3e41190c2', 'dx_wrist_injury_d94414e2c6', 'Wrist injury'),
  (2633, '49e7acd1304d5a3d421c94022ffa552433593ee95da86b471d906ce29a60cbf1', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury'),
  (2634, '9106568fb4174df726b88e900699d77da77ba84ac10295bc2f1d0f867b611f12', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2636, '59e634e2099551dc59eaaf61059cc7f3d1add8ac2b2d2d60cf120982895d0b40', 'dx_finger_extensor_tendon_injury_mallet_finger_36d86ff004', 'Finger extensor tendon injury/mallet finger'),
  (2637, 'f727ddb15d742bfdc7c9ec04ada49cb62a300db0841d84c65883fd8ec43b1bbe', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2638, '23ec7388faa7d2967421986625a18851ad371efd2d90a5b5f58afcc218a42f32', 'dx_sternocostal_joint_dislocation_3658d02019', 'Sternocostal joint dislocation'),
  (2639, 'fbb829bcc4d179d41f2d408fec4f74661a990821e1c9714c4acdd18e6e4ef073', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2640, '6351c2efa86f7839a8f85dc1475dab76f468a5769d5cf80211882d2b21ff9b8e', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2641, '9c5ca10f9789392e037d8ce34bf99db74ee90d3d13f5f6fbcd24243c8949b555', 'dx_ear_injury_190079a2d0', 'Ear injury'),
  (2642, '3adf5e2bd1206892941681001e28c306f5252cfd35187838e21542a8f99c3232', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (2646, 'd731d98f9ca33b24811aab4e1258cd7bf35bef7f1a02c0f20bf78e5755623c0e', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury'),
  (2652, 'e67024806fc165886df2ee4d7d9c86e0821fa030804f4a7b8e58ac5d5f06940f', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2653, 'cb52746235f3a69cc17006cbc662ec29fd1fbd2cd52b09763fd9a865642dc04f', 'dx_pip_joint_synovitis_b027f84ad3', 'PIP joint synovitis'),
  (2654, '45bf3d74833f424908fd8ea41645bd6aeb5929cab61ac1c0174ec07dcbf3ac15', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury'),
  (2655, '7ff62cd7d2ea9afb893ba1eb9a6799908fa7f0e3baf230d32e367938247a5ec1', 'dx_glenoid_fracture_4db9569087', 'Glenoid fracture'),
  (2656, 'c9293383050a2de42fdc2ba9f6f4be15bf1021313ceb8ae92e181931b3e9f7b5', 'dx_scapula_fracture_eb45c41e7a', 'Scapula fracture'),
  (2657, '6bba6182254deef3c3cd1fe378bb7fbd873ddaa4e5cbe6d2eb7f14ed82b518b3', 'dx_sports_hernia_ad99f8552f', 'Sports hernia'),
  (2661, '38b0bdd9f3dbbc171e0df6c6eaf6a8fb45492c93aedae004084602e3010f9f48', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury'),
  (2664, 'bb3687cc3ab6ed7028e908e909c4e6da70079f5d6dbcf94150f7de0a62a020e5', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (2665, '1dc07ee5632df5e0746e1d2ffbd79f098cab9b865f925b8f017bc7f2322dcc14', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2666, 'c084e07249b8139e70ae90be6d356433fe82004e1e576b89942fc3d37ca5ef25', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2667, '71eed73e66b9087555bf18dd3a53b272f4a733d79b98718d00ef0c52a873c06d', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (2668, 'fa475fa1ebe1a727459652100f98ceec6f3d423c74ada29b42ad0b746ed789d7', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury'),
  (2669, '41929c5ad5730858dd9b8e799525ece30255e9525fe7fc28d575e64b98afc2fe', 'dx_shoulder_labral_chondral_injury_4ddc56b103', 'Shoulder labral/chondral injury'),
  (2670, '22e2047d1d5cf2720f17e2f55307ca772263e35aa89e84ec59e87f4176b72c04', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (2672, 'deba3382520ece7521b665727e8356fee314198447d13ac6999e5dc30cda43aa', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury'),
  (2673, '16fca487f8921f305314837b24d9262dd6db0cea2e7f324398845039407782cd', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2674, 'ad85c0cbeab075ed72428042e95c030a6883bb1222476327ac327866c2ed3dfc', 'dx_knee_posterolateral_corner_injury_a4c4c64579', 'Knee posterolateral corner injury'),
  (2675, '386191523492b08c0ac8e9cd3a50faa86d42bdf475fbc16fe8191c01e53dea9a', 'dx_biceps_injury_69e895b576', 'Biceps injury'),
  (2676, '6fad8cb7420ed60e1f2641176b92a9f11445f7eb422444520d949c9cd26b523a', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (2677, 'b12de51a5629934e188edeadfd6a3252cff3e2dfc950af1a750eeeae2c8f0a42', 'dx_scapholunate_ligament_injury_0d2ca4c746', 'Scapholunate ligament injury'),
  (2678, '43dcf403c2ccb4c5a6643a544f9cf20377db752bcac9656f3f475f2d8b6bcfe1', 'dx_forearm_flexor_muscle_strain_d73bfca6be', 'Forearm flexor muscle strain'),
  (2679, 'e0b09a842c3280872e00fc5602ee517c9ea208cd36140448e666bf93c756e855', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (2680, '373f581f17e5cf0b0c283eb546385b7aee3b2d19b5b1d8e86a8f73ce91afc458', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2681, '0893a8496002cf51a48ccec9412b34221d3280d08e70719c52e71c592aa76707', 'dx_shoulder_labral_injury_c99b83bba8', 'Shoulder labral injury'),
  (2682, 'b5ce3050dd3697e35a3b98486f04124b72d9daab7670b6d0bde0bf4c22b22583', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2683, 'fecc999469c2703d27ad9fa181b4c06b39f6469d3f2ea033c0b438d371bd3541', 'dx_head_injury_unspecified_611d184685', 'Head injury, unspecified'),
  (2684, 'a56c290c727641cb3a53842eeff3ec1eed7eef15832e4c3e88383a2c687bfba2', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (2685, '70a3d7ee5f496961c1efcb1069065e8a47b2a75443049b047eb4f0f51a1c53f9', 'dx_pes_anserine_bursitis_3af1f08842', 'Pes anserine bursitis'),
  (2688, '6b7c3a6ba9572b276bc6f166167f0389155ccc42c395e2665b42f9f64531616b', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2689, '98883a761982036238f66a5c8ce8b06216ee5dda7181d380e3e8d558986aca5a', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2690, 'cf6854b992c2b017ee2cb1d5a6ac00c46f2a1fb12cdb128ba2b0c73b6d864ac0', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2691, 'c863c2d1b82bf0266292043f69ec4ea813ab4f7c980a21883e1f738ffd9566aa', 'dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b', 'Plantar heel pain/fasciopathy'),
  (2692, '73d4225321f51211e0849c4210086838d54a2b7a7633a2dce4649aaf077ea9b7', 'dx_biceps_injury_69e895b576', 'Biceps injury'),
  (2693, 'f9bee2de60eafe93435e6893d5e1a9c2a42586e3ae4ce44fdc220e6c81cf27ef', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2698, 'fbdc4867ab0ae22af3b2593fe8c392d768b924b77669fe2c10ab79409a86b9e8', 'dx_proximal_hamstring_tendinopathy_with_ischial_bursitis_9c962c1796', 'Proximal hamstring tendinopathy with ischial bursitis'),
  (2704, '4d105c2f4d24df0ef64bae62b61308845f56112aeec1a43e3304a76aa1fe9249', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (2705, 'f39be72b520bf41b164d6b9ab900edcfeb28dedf87ccddb3d58710b2b3029cc1', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2707, 'be4b799f57a45dc573e9051d6fa8de04f3ad16409fbabc7bfc942e6ed0663fa5', 'dx_ankle_fracture_97af59eea6', 'Ankle fracture'),
  (2708, '6f45f3d4d9312e51ef6632d28a7d9c2e7c38ef2f73bdb722df64a39f33b1b502', 'dx_elbow_contusion_ac2f8ee65d', 'Elbow contusion'),
  (2709, 'e34ec336254df04ab6cdc82ac6ff704be49666c2daf32a1a2d0bcfffacc1a203', 'dx_foot_pain_116521a908', 'Foot pain'),
  (2710, '971c29cbacc0b17326c73159608b94f08210dd4d53b61c82f7d37f16207e933f', 'dx_headache_45575633c6', 'Headache'),
  (2714, '00463aa1df32e8f4cdf515510cd2ab4dcb9e3f092845e25962e4d5780193eea2', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (2715, 'adadc857f22256c30c72087e932cff9eb97fd05ae119ee5a54f38e32e619a024', 'dx_cervical_facet_joint_disorder_c3699c58d7', 'Cervical facet joint disorder'),
  (2716, '3ebad352b3339cfb4a3996bf5ba3bfd96cda1ed8ab725669b7701bb63dad796d', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury'),
  (2717, '328b0ea09ba3648c19181d3716b85a77aa8587a6a6ef1d024ac0aa093794a6d8', 'dx_thoracic_facet_joint_disorder_519c2ae5a8', 'Thoracic facet joint disorder'),
  (2718, '5161935792f7b856c1d03237fa426913a6489533cbee7507b24c09d5be3c75f1', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2719, '18129811438b9614832283431bf21fceb3584462c9011a739c6535d90b1cafd4', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (2721, 'ae8533a8a893efbdfe67cd7e076d52b9ad6f86cdb50c1a4e8b89c60f2c1b1129', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2722, 'aa230ee0fa459b051ee88ddef7c74e1354d4378102ec7ea2b00f05cf3476c0ba', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2723, '236a5cec4b16555040eaae1cefca65676f72fb99352db2fe53eb8f76429630d4', 'dx_lumbar_soft_tissue_dysfunction_d3330bd580', 'Lumbar soft tissue dysfunction'),
  (2724, '7e89368d98ca35151481a1cc2096cae9fc74bcc08588a34b2bcd1b617a95ae1c', 'dx_femoroacetabular_impingement_76f8c7b5bc', 'Femoroacetabular impingement'),
  (2725, '7a68f9a83d6cae39b5b8489f152a74b0e27768cca7a9bc129343c0b750f437d5', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (2727, '3ee23963d80e9b2e5ef9b06ff8162c9c3c11ac46225c4a61baae485177fd4536', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2756, '919f94776a3f1c5fef66a01fbf388929debf53ec32c8b8d676de736fecc3e834', 'dx_lumbar_spine_injury_27c07f4f95', 'Lumbar spine injury'),
  (2757, '0d15dbe2d3bc0d265b4aceabaa5863d23ee460a5f13dee4820ad9677485247a0', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2759, 'eea7faea73d3be2a8fa2c48ece9eaf352fa9a92199ad9f82c82354c02255cfae', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2761, '7be93fa92579b5755368f7cf6434a0be8092d97e68c687505db7bba84ad06555', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (2762, '213097135c21c2a7a5410cb752b259826bda4aa8148a7e397cd3b16d0b7484cf', 'dx_wrist_sprain_complication_ae8ef1df9e', 'Wrist sprain complication'),
  (2763, '967f0f20954a8a9dc5ef61a152306ebf3f19d85d7749e4803864ca574078a799', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (2764, 'ab37e5e339ac8a85f4cb563b165e4c1fbc7d0927cfb4c1fca2a08a96a6d2d6a9', 'dx_lumbar_muscle_injury_a7fb20b2b8', 'Lumbar muscle injury'),
  (2765, '28320d8a3ac6bafc6982c3c0220fcc30e338378ef108c56c0630221483e23bbc', 'dx_neck_pain_58ed6a0781', 'Neck pain'),
  (2766, 'fa9272238ae62fa60f3114dfed54578ae91b1b336f0b4b007dace5829b3dd37d', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2767, '1d2062429ef39c43108aa95556df94d30e333518e23dc2972ac8947ba21cfcd4', 'dx_ankle_pain_de6b615afc', 'Ankle pain'),
  (2768, '9b19a998a4498144c18165879c2071dffb54211099f0c6135fac96bd676c18b7', 'dx_knee_pain_609ce718bc', 'Knee pain'),
  (2769, 'ca305cc08ed6fe66a6ff77bb976a77c14ec4330ab84f914edb7d6f58be65cde4', 'dx_sinus_tarsi_syndrome_ab59e85509', 'Sinus tarsi syndrome'),
  (2770, '9e6c461517f263e566d26152b666eec56c02719dc5882880ad95e6b3be0e87c2', 'dx_wrist_injury_d94414e2c6', 'Wrist injury'),
  (2771, 'e6a0411d37ce0bf9c23151a137b95e09947e98537fe7ad44872d0e48b949416c', 'dx_shoulder_pain_738e4b93f7', 'Shoulder pain'),
  (2772, '47f07d9e40d3551b008e96e0490365b77de15ca185f67170756d9fa6156e590b', 'dx_thumb_mcp_injury_2b5c0aa20c', 'Thumb MCP injury'),
  (2774, 'dde72a917268d160bbb1c243c56804ce63b9d9b155ed8dba12cc6c495ffa9f91', 'dx_gluteal_muscle_injury_6ed1fcc3c2', 'Gluteal muscle injury'),
  (2775, 'c404706f9d1a457b407c9aae3546f5a54fead5308e4354a4fb7d4706e359eadd', 'dx_finger_extensor_tendon_injury_mallet_finger_36d86ff004', 'Finger extensor tendon injury/mallet finger'),
  (2776, 'bb8c85953784f154b703121884b42d27eb214458714bb70930821099f7035ecb', 'dx_elbow_pain_ce93745d98', 'Elbow pain'),
  (2777, 'd8a6c15c87f2e004c83b8ad67dfb38a18ba197e727fc1912ccecf77e1cd43a55', 'dx_neck_pain_58ed6a0781', 'Neck pain'),
  (2779, '4244c41a69bd765090e093f79167e155add505c9007d8493b0eaaa923ea505a9', 'dx_shoulder_pain_738e4b93f7', 'Shoulder pain'),
  (2780, '588bf00652cd6ae182bbb3a6a98212dfc1eddc97ba9de48bd64e3f81253863f9', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (2781, '88256c60d1d908abed12a2aa5b005b951d964173589e660c1020b6b9dc4f5173', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2782, '207cc59bd14ad42f44cfaca741343dff92e3f9850ed220cc2a696efa9dc96126', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis'),
  (2783, '9882ec1d4ad6a4786d83ec75dc65324563e6722ebb7dfa3bd7a522919dbd64ec', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2784, '13a7b9c06da1b69acef60d3be3a17f0b4bad48ffe358acecbbef3792e0497896', 'dx_shoulder_pain_738e4b93f7', 'Shoulder pain'),
  (2785, '566d7f4d8aa572c5156e09aa275c190c9900433f227f1e7c4754d3abff27e90d', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (2786, 'a874817d68e09c65291b2e0ccc9072238407f877a8ba93c772bb7786e2225d39', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury'),
  (2787, '7c21cb0304cf961ccf898c772aa25d1575ad1a682c6b4fef331e071c9593cae2', 'dx_hand_muscle_contusion_or_haematoma_1d004bb885', 'Hand muscle contusion or haematoma'),
  (2788, '505a053cb89da10a78d08c55fcf97a890fc0fda0de54ad8e9dab435e4a969833', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2791, 'b57c04581330eef77a7cc8086395a18617a61b4a0a1e198f6da8fed1e7fbb3e4', 'dx_head_injury_unspecified_611d184685', 'Head injury, unspecified'),
  (2792, 'fc9e167476fc55e7d902e78cff9bb575e4c8f457dd6b9fdecc86f6a3ce328ef9', 'dx_cervical_spine_instability_658367d444', 'Cervical spine instability'),
  (2793, '55f8ae9f5dd2da856a9ee11404ced990869a21e7f744fefa2902e5f531e5daa0', 'dx_wound_infection_complication_5415c9f38d', 'Wound infection/complication'),
  (2795, '8f19e5330e9c39bdbf0a0ce212ebbb555be4752e4ad3a56e6e85c479d3175715', 'dx_knee_pain_609ce718bc', 'Knee pain'),
  (2796, '04b88ab1808bfee7755dfeaf1752b40819f67fafbcbc4177f546d75a6f83e2e6', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (2797, '6dd7f8a966d75efb78b8a0a9e393529365f71b23d9c49f0a69c0bcd6c3ac1d25', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2798, '03dbb09fbfa40d284ced343695949fc250661bc9157c81a99a7e248bd91b2e99', 'dx_chest_pain_883378ac08', 'Chest pain'),
  (2799, 'eaaded74e50eb33deeec8e981cb630b7d1755a25302d562ffeb849d962f0d4b2', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2800, 'c980ea1321e5ea989aa27ed09e9bcf3bcc034b21883dc5b769130b4717ad03a8', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (2801, '2eacc4f9b3976a67cc80530e452ee1cddced6763423f008582ac7a78aa606057', 'dx_ear_injury_190079a2d0', 'Ear injury'),
  (2802, '6ca2101b88e0b3bd9856f3a5f95623146aaad2856a400beadc35b0af6544198d', 'dx_knee_posterolateral_corner_injury_a4c4c64579', 'Knee posterolateral corner injury'),
  (2803, '3204e2388a83ec0cdd4730f6e6d7e3d639dba4b32be27fff46b60c174fde6aa2', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (2806, 'fc8ca934f02092129bc38556e44e01d8dbe719af34e7c5ee825f59a2119dc776', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2807, '8db6cb6e59c58f4fcfc10cec9106c54e32430eb724f8e1197b5483ed98a82375', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (2808, 'e606854943356af4e1cceb018da758c322a8eca458f05073c9403420928120a7', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm'),
  (2809, '1877744086b2b95d5e7c14d719b8a4180b24456c7d0bf1679f68d569d5d44d81', 'dx_hip_flexor_injury_cedda9fa03', 'Hip flexor injury'),
  (2810, '9f0e34a5fc4e18d1e5e3993781141c8d1d7de17c39c7f063857a57416c7940e9', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury'),
  (2812, 'a23aa13816ca3943660610fb5f47521df04c4a39439a62a87999a9efc26babbe', 'dx_head_and_facial_contusion_74a20a767e', 'Head and facial contusion'),
  (2814, 'f33336bed05ca0af529d27dd2a1778305ecf2e74c274a819813772dd2f6b7207', 'dx_cervical_spine_instability_658367d444', 'Cervical spine instability'),
  (2815, '1eeac576ce0fc0f4b4d0c16b8b2ff93e4a78295320b201c763533d022f6d05cb', 'dx_knee_contusion_94058fe1a4', 'Knee contusion'),
  (2816, 'e749c72e491b761b85f0fc6b4c61e24c604cfe1365f394ed6c91c9cbfce2a570', 'dx_hamstring_cramp_spasm_ab47d7d2d7', 'Hamstring cramp/spasm'),
  (2817, '213ae3cfba95c3245ede699328c478f3b461b0dfec046265172825fe886be88c', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury'),
  (2818, '93a87765eab1620ee4f34e90d6238196178e99239cd425e0730a36e94018e0b1', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2819, '515e90bfe55fd4414910f3a4b44f92a91836c2e0bde9c920281d18a23a8e92a6', 'dx_acl_injury_4b8eb47e96', 'ACL injury'),
  (2820, '0fb63fa5dff752fa982074026253c0aba4aac42ba9cc09dc0d326b1ec1c850fd', 'dx_ankle_osteochondral_injury_7842c657f7', 'Ankle osteochondral injury'),
  (2821, 'b0efe7f96d236d0d238d7c18ef2ffdbc87e9cdc0932414ed324fe0a21c2fb084', 'dx_calf_muscle_injury_0b80e5492c', 'Calf muscle injury'),
  (2823, 'fb4fae9dfc1a67dfe0b465db65ee3c44001872f25f3ab6eb3667754306097aee', 'dx_calf_contusion_haematoma_1ed62efd4d', 'Calf contusion/haematoma'),
  (2824, 'e4c5f589f91ba86ae148279a14e596e6293f6a3037ca2df9746d825cca48b312', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2825, '01932941d8c477137633388db01eb3b296ff894a55f1e42c7d859799e41ae39b', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (2826, '9899bce2c402003b975a51482def072564c893ff75439e4453e1b06430017ffe', 'dx_knee_wound_7498252643', 'Knee wound'),
  (2827, 'd75227a36a998437edd2e1c90cb4e224de11cae954d8ee2cb57e9947a708bc47', 'dx_hamstring_tendon_injury_f86b1dad5b', 'Hamstring tendon injury'),
  (2828, '15f74461ef7ca6854e09303804527d2b28f9adf3f1397eb08c7a5202ab55c25d', 'dx_shoulder_osteochondral_injury_06178c6960', 'Shoulder osteochondral injury'),
  (2829, 'c255e4716b14d90fa4fdc1bf9e93515b48881aa2461179b55ea4a69bce600a17', 'dx_foot_contusion_6c8a5bb721', 'Foot contusion'),
  (2830, 'f4b63f91658ca99ad68bfa1441a48a5f824ac27fc8e5a7acbec844c76ce7145d', 'dx_foot_joint_injury_28a178b0b5', 'Foot joint injury'),
  (2831, '922f66992ec94060d14326448b5f87fa426380d40a40d6d5eaab44cd28c184d8', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (2832, 'e7226ab8b7706697b54e1a4339e9a37b235127c8a73eea7f024000dcf7ecd9e8', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2833, '0fb112db3cb09c5b78aa5723b3a4ce3f09c42f8472bb10350e4ffea7b4f00984', 'dx_thoracic_spine_pain_9ec9a9f2e5', 'Thoracic spine pain'),
  (2834, '2e7f25feeb5168345e22537179cbeef931fff5c94c78bd49d8c5bf052858a474', 'dx_head_injury_unspecified_611d184685', 'Head injury, unspecified'),
  (2835, 'f5a2441be6f0eae77739d796ac2f200605f7c9be3bfed1c171f473a48f06ebb7', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2836, '078919921270c97eea4d47191ba812a7b587276a5e45224ce919d85b17f7528b', 'dx_ankle_pain_de6b615afc', 'Ankle pain'),
  (2837, '459322b7fdf95edb0c823d19a10b60b089b675ea2137ef0c6dd525ff21787657', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (2838, '6136774f69d9d4a19737bf174631fbc85a5587e937b576521ad3dd45091e9220', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury'),
  (2839, 'fb8de19dca5820b200982cd944476223d7a2e2af6318e34575f5b23dda527bf6', 'dx_medial_ankle_ligament_injury_9add2aecee', 'Medial ankle ligament injury'),
  (2841, '29dc94da67f1b7d1beee2c851fb1b56ef461689e300cf8bd8fcdea1408c4b6d6', 'dx_hip_and_groin_pain_27531edcc3', 'Hip and groin pain'),
  (2842, 'de463418a09f6b7f29f77e06fb14c674ff02cd8691b89252fde0e8f4e5173eb2', 'dx_knee_pain_609ce718bc', 'Knee pain'),
  (2843, 'c9e6046d7bd80ba3eb67080496f4a19fbb9b601236c6c869dc008e7539f77ecd', 'dx_knee_synovitis_impingement_02e229b1cc', 'Knee synovitis/impingement'),
  (2845, 'efc27bc2babead10f637efd87a0f039003697fc640384dadc04719fb998f5c10', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (2847, 'f2838fabd305150b0756b0b2baa42472594921ea05f37b9a6d609bf296095270', 'dx_lumbar_muscle_injury_a7fb20b2b8', 'Lumbar muscle injury'),
  (2848, '9b1c388733e4746f2e3e59c5ad3a1d77de0da51055c2ea9958a7f3540ab48179', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2849, '542eb3cc3f17ddbb4064e185bb4cc88a8925b7da9dd38f25a2a4a42a265899c2', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (2850, '86687c896b75c476d4049bac7489f676e700f9517a289ffd1590b96948f206e2', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury'),
  (2851, 'f5e6b688ff0e19a3ce8dfa0b6255b983bf60b35059ac3e382be5ae70b3110280', 'dx_knee_fat_pad_injury_3748807c3d', 'Knee fat pad injury'),
  (2853, '0de2ed6483ecf4340ef70c7409cf71f715db2f4073a4479e599f04baa3f9b353', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2854, '5bb5d3beef43d2cd2e9667c6ca861cf02a46f09ff599a8236bfa5f050707250a', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2855, '68a8161852a07ef9e8e796a8ec493c35f2cf8b37e12a6a3745de946907860b17', 'dx_ankle_pain_de6b615afc', 'Ankle pain'),
  (2856, '96716837e7537cbe6b826a181c2dea366ca9d6b41ba103918d93324d227741b8', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (2857, '198aaf05dca5d31936b96d835aec9e8828da9875dc16a50b80418dd8619f814c', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2858, '22c7df8be698f15a5f38c0fc8ff98b972346e50535042b75fcca076cf5b8cc13', 'dx_elbow_contusion_ac2f8ee65d', 'Elbow contusion'),
  (2859, 'e83d1761dad8d556d0c6ac2ee04896a896dc3dedaa5415bf8c8511c3e23a3c5d', 'dx_dental_injury_b97b2afe75', 'Dental injury'),
  (2860, 'c4044f020aefc671c5768d9c208f665d1bc6d782e17f1b7b71071ad9d31cab76', 'dx_gastrocnemius_muscle_injury_f352ba5776', 'Gastrocnemius muscle injury'),
  (2861, '686832ef016d3e071640d9ac4438d6d56b7388e83dd6112cf7c42f67d6715c7b', 'dx_calf_muscle_injury_0b80e5492c', 'Calf muscle injury'),
  (2862, '05ac5c33f8512b81a9412861ab8dc34df61a1867d87a93b5194cd61867c1d02b', 'dx_cervical_functional_pain_e11c275770', 'Cervical functional pain'),
  (2863, '4abcbd2ca47d4c4a1c68b6fb24321e519e0f2c1c4142e5097804d211c1b67413', 'dx_knee_pain_609ce718bc', 'Knee pain'),
  (2864, 'b95192341da843f494d293baae810c130d8188232637a5d3ef36a30ea6710709', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (2865, '3ceb476b0d0982250f8667b1ea4daf33bc44275d58209856bf0e7460c232a288', 'dx_plantar_heel_pain_fasciopathy_a2f0d2cd4b', 'Plantar heel pain/fasciopathy'),
  (2866, '3b178b7b850e88bd83c3ce637b459bbdffcace9c687f2a47fdeddde90227dc7b', 'dx_ulnar_neuropathy_d6dcc82595', 'Ulnar neuropathy'),
  (2867, '57a25b2934abd029b2f21ee4401da459593163880334468f5042e6d335bc4f40', 'dx_lumbosacral_referred_symptoms_135afd8831', 'Lumbosacral referred symptoms'),
  (2869, 'd11b3781b695042853c83da8838545a5b5e4dc8b3b420d0762f936d746cb954f', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2870, '52a88aa6ef91a2693f23c4221485580a715ba3242005e3607d3b5721b7b79d2c', 'dx_lumbar_neurological_injury_bb35f1e8ee', 'Lumbar neurological injury'),
  (2871, '19db2ca5f344f4ec13f2a33b8fa7769e878b3b908177fc64e3d858ecdf2497b8', 'dx_lumbar_muscle_injury_a7fb20b2b8', 'Lumbar muscle injury'),
  (2872, '3c9950839ac8dbac12d566ea96c0ea9411e36d9c2476b2396a6006865823eac1', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (2873, '352a009f72cb2ef287529165f3eaeb814228668f39b1629ec9ea86fe99cb2d68', 'dx_sinus_tarsi_syndrome_ab59e85509', 'Sinus tarsi syndrome'),
  (2874, '6853c3da4804de16e54b38a05ea21ddaf11a9d47f01ce0fd2fe27d685c30fa63', 'dx_thoracic_spine_pain_9ec9a9f2e5', 'Thoracic spine pain'),
  (2875, '11775883d09d1f491204a4959042eb5bdb86ac4c87c0288907b0d56e73eb735a', 'dx_patellar_tendon_injury_91ccd5f25c', 'Patellar tendon injury'),
  (2877, '02fe3b6cddf3bcf5406c035d1c9dc2bfb95559805623a253be40d2169519198b', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury'),
  (2878, 'e5a7fb675a2f59cad481f395b2df4c4a6084426fcacbf0f5dab9b05539ba21c3', 'dx_lumbar_neurological_injury_bb35f1e8ee', 'Lumbar neurological injury'),
  (2879, 'cfafeea7fa58bd233e28b5dbc309d019d0678a86d871f6c0d0f2779111879129', 'dx_shoulder_muscle_injury_f1ad3d954e', 'Shoulder muscle injury'),
  (2882, '651424e91d33d1444f9df7dacedad17250e2b9c153a7a08fde5982fd167d2393', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (2883, '38f1d24b7f271ce2b0c086f6dbb60e38a6e96971b57c50f7443d2936d838bca5', 'dx_heel_contusion_4009d671bf', 'Heel contusion'),
  (2884, 'd3e470021cd06b7c3dcf535fa858958779abe02e5e749bdee0a161c9464deedf', 'dx_hip_flexor_injury_cedda9fa03', 'Hip flexor injury'),
  (2885, 'a2ffbcc954e9001539d784cc5d7790eb32e613ff7e3a37bd6e57e59138e2d595', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2886, '49e466ccaff5d0c6ce6eea1daf859e3cd0c55255fe9abe51a37ad51743ea3241', 'dx_thoracic_vertebral_fracture_dae2957a37', 'Thoracic vertebral fracture'),
  (2889, '431ea099a0b438f8f0e913859d16ea0ab27795d9a3abd5cad71b12acb04242fa', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (2890, '76f2e54914b962d1b9484d425f12379a6935cacdfd33faff695e76d09306e075', 'dx_thoracic_spine_pain_9ec9a9f2e5', 'Thoracic spine pain'),
  (2891, '536b57595e56dd88050d3b99c730312abb2ec3bea0a2d79dcb75530d0a4f2c3d', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2892, '77599d25917aa19b34f6b37be6edeb0ae8bc22581c0926b4748f08ce28430a83', 'dx_cervical_functional_pain_e11c275770', 'Cervical functional pain'),
  (2893, 'ff3863976aca28c390afc252e8c254aec79c48e1f257dbaf80beab58637205d7', 'dx_hip_flexor_injury_cedda9fa03', 'Hip flexor injury'),
  (2894, '7aadf0f544405a63d53e59657c26f9c4142481e2c8b64ba9191ea50b08e16489', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation'),
  (2895, '96746505d220ed04c404a9544d58e5938513c8900921c4dbfb5a6478127ba8cd', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2897, 'e68bb7a5cca4e39b80630fc3672598a7fadba23f906db66b685c5679369bb947', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (2898, 'd809bb90810b274d72e5be4b8a53166aed3423a9a45a7e67c1c1d061e6d314a4', 'dx_groin_and_adductor_injury_476e2d09eb', 'Groin and adductor injury'),
  (2899, 'e02eec7c4408b595fa570b828eac0339f5517864a6a2fb48bf654ae91f84b125', 'dx_ankle_syndesmosis_injury_757bf42431', 'Ankle syndesmosis injury'),
  (2900, 'ca4ddfbf989e5edb8ce5ff389ba368dd41ed5da9f9b1240e8ef794cd92eb1ab9', 'dx_calf_muscle_injury_0b80e5492c', 'Calf muscle injury'),
  (2901, 'c2ae817b8f9f472a6533074433918daa7c36bdba1cecb6c71d5ef93c6739d8f3', 'dx_thoracic_spine_pain_9ec9a9f2e5', 'Thoracic spine pain'),
  (2902, '124cccf32e43ce3ebc04be14f899a5388354a739836c5810cdcc072d4c371f6c', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2903, '86f15eb02f1b8f27cf757b196e62a3603008c7c69595ce44a0c0b2f5874f3812', 'dx_acromioclavicular_joint_injury_1a8d08823b', 'Acromioclavicular joint injury'),
  (2904, '84eaf0f174e20f9dcf6b200c6842fd90e02ffa0125a8d10567865129f50e0bb7', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2905, '7a9ca4d47a91142f627fb65fba6001f917bf7aef2d34e46cc617a883e5364bb5', 'dx_cervical_functional_pain_e11c275770', 'Cervical functional pain'),
  (2906, '07165adffdaa746459f59596c52d4cc1184c9359093a4a611391aa12c0f5a543', 'dx_knee_ligament_injury_unspecified_7ab630d44d', 'Knee ligament injury, unspecified'),
  (2907, '753bd78df0353b65d574dd6e9ca0be611b902753fc2499b662c1f236d63b2392', 'dx_osgood_schlatter_syndrome_34f2e1629e', 'Osgood-Schlatter syndrome'),
  (2908, '5535c01523f08a046299673030f954f524291c96d57ab11d8bde1a4f99a6d449', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation'),
  (2909, '940cd047e63e586c47d3bdc2b3888b549d3f76aeb2e7509a0b542ab0bb1dd04b', 'dx_ankle_impingement_or_synovitis_300d78f574', 'Ankle impingement or synovitis'),
  (2910, '00ed0289a4ecec151c31e6fabf6ae3a5b199aab71e6c6f67b2f29949e2395773', 'dx_finger_joint_dislocation_fa50126b94', 'Finger joint dislocation'),
  (2911, '0ba020739f61180e34148bb4dc4d53dd93d3a0cd14e5d44c686e79fb2d3088db', 'dx_elbow_injury_7100f71f81', 'Elbow injury'),
  (2912, 'b81daa7f253ba65012f1698635b958c53ff93d78b6a94388b11af90de7a250d0', 'dx_wrist_or_hand_pain_57c9958c78', 'Wrist or hand pain'),
  (2913, 'e73b3128376bdc92157c2f8ba70c0ed9f923fd1d7d1abf087d7fcbfd45f15d07', 'dx_ankle_osteochondral_injury_7842c657f7', 'Ankle osteochondral injury'),
  (2914, 'cac288b189adebef12e2250a9eccc42ce2572e5d6fe1c324e00b6a2cb8a880f6', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2915, '495a64328518b21101fbca5ea889f46fab8677b84553fcb46f1531584c03f566', 'dx_achilles_tendon_injury_6983aa352e', 'Achilles tendon injury'),
  (2916, '46094e6660aaf1dbf420788cfa639fecc9b7d3502ea3c62afb4b8c82a69cd602', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2917, '55e1146924ffdc2ba1c277cd6420c011c3209489ac271a6a54b39cb70c3af710', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2919, 'e9194a192ff3edd051e24c4f64d15aa7edc327b41d470108cb4dedfc7b9aa61b', 'dx_head_and_facial_laceration_18a8006cae', 'Head and facial laceration'),
  (2922, '45e83f1523bddb234a3dfe9441803eee8deb37243885dedcf47de07f6bf4157f', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2923, 'd298bc8a8ce1900b4d4eb45e253cde1112999bb1f7658ff25c154e9455645c05', 'dx_acl_injury_4b8eb47e96', 'ACL injury'),
  (2925, '58ef7cfd49014c84c434aa2baf14a9d3f10d25d39e8ddf5d56b2f60c279b3e07', 'dx_knee_bursitis_42542bca17', 'Knee bursitis'),
  (2926, 'c84255f2aa11e79632e0760b4a3f7d26d880a30c38593741892746ab6921131c', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2927, '8b686c022b8e6dd134044380630402f666db52e4292bf15db734046da2eca232', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2959, '2e63e45bc5103910dc2b10c59a3a53096720f0f3582455e6d4f1c11d4371289e', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (2963, '0de94aa6fa9d22cc8522a9f91076d8a3fe0c3f17c52fb43ce310bebc4a29514e', 'dx_ankle_osteochondral_injury_7842c657f7', 'Ankle osteochondral injury'),
  (2964, 'ed6db6d83a0b8bef2ef25b984b1df9dd5744c46b94283edafc8d78aecf15f342', 'dx_foot_pain_116521a908', 'Foot pain'),
  (2967, '1c6f46ca7b9d1670c71218ff10b647370de368737039edeb9acbe44f46c7bfc9', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (2970, 'd8ac0c7791021f8d932fa32826fcee3b3c75630a23308b0d7b689d3315672a34', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (2971, '0aafca78b242b88bf56f6a2da6977dd451627fe9e98e95fc53ab7e3b44624afe', 'dx_quadriceps_injury_82f2a4c482', 'Quadriceps injury'),
  (2972, '46b012a6b06741e391a35c54fe94adba99fd363c68a19856dc8f1fa14d768f1e', 'dx_spinal_disc_injury_e3b980b6b8', 'Spinal disc injury'),
  (2973, '973c47ba7aa12ed53e0a17e3ad0c244b2bd86187c977d7782825d8ae8a3006e7', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2974, '562c3328294520c538ce45946ea15c68be1927218dd68dba4daa5678cf8a4d9f', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2977, '9e2d9d30141ee52462d968645bae0ae48d8193d7bf00f070984cfc4465a9c1c3', 'dx_ankle_osteochondral_injury_7842c657f7', 'Ankle osteochondral injury'),
  (2978, '82186346504103c5b41f8b085608fb6f53fa1841dd58a7055790355ebea031dd', 'dx_plantar_fascia_injury_ec4d3703e9', 'Plantar fascia injury'),
  (2980, 'c806993198a2e9fc52e6a31bf22248b19aea3f0c41ceadcffb08b9b557529a35', 'dx_patellofemoral_injury_a6e2fe370a', 'Patellofemoral injury'),
  (2981, '660ef136e1233c031c6f3d143dd176c96241accf7dac0d32b03c07b6f34e7cdf', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2982, '5bbba330a617e9d0424bcb8e3ee9023500aed43039c05df3608400ed1f9fa490', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2983, 'd65b4d725aa86d35626ad53f6559bd2aa86cbe2943151a174bb2066555a38e12', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2984, '1d6d4b4a3e7d426bebcb675a8d761cc579e5bfea79fda554e8cacec3ba55557b', 'dx_meniscal_injury_b166306f7d', 'Meniscal injury'),
  (2985, 'a572f5ef4ea341d36fc3e1b7c446690b7dfef8caba4d5b67461cb4821047fc22', 'dx_lateral_ankle_ligament_injury_d9a611a9cb', 'Lateral ankle ligament injury'),
  (2986, 'f37b23e565ff1156181ace5bf57a1daaa36a8227f2844aa4381464ce5a2f01f6', 'dx_foot_pain_116521a908', 'Foot pain'),
  (2987, '00d0293b67b97d8a789be4c5d1702647e54221362604bd06fcf49fae84387f58', 'dx_cervical_disc_injury_43afeb7cdd', 'Cervical disc injury'),
  (2989, '8c3dfd19ce7abaff9d9b8384610ecb8561caae07bb1bacf33bef4df0224c5945', 'dx_rib_and_chest_wall_injury_bd04b4cfdc', 'Rib and chest wall injury'),
  (2992, 'f2a77162cc61a35c297be73d31393b8ab4535e16b87d1e0bd27d88517c9e91f0', 'dx_concussion_a91e1107d7', 'Concussion'),
  (2993, '2d9d3e51a948ca6699801ab5eeb95dc90a292007525b0f2ce46868d4a943c271', 'dx_lumbar_disc_disorder_771d5d6a37', 'Lumbar disc disorder'),
  (2994, '3e3b28146ef6cebc60eae22ad730d3355b140f905cec617facbd4239461a34e9', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (2997, '509c8c4a984eb797918ed865a5630529b2a79bd91c7269b3b1a462bdc1527d10', 'dx_knee_contusion_94058fe1a4', 'Knee contusion'),
  (2998, '98816574ccd46569af0e1ea317bb92453ac1f47227f028e95f900c597cbc521f', 'dx_neck_contusion_7f04c7cc90', 'Neck contusion'),
  (3000, 'c5fdf97f6efc47ab0d0af7b4bf4c881ffdacfc91947f1d78c80dde6cbe67e7a1', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (3008, 'ee27e46b35609ad239641dea5be395df7ab0ffecb67a1b97aba72ab5e9e0f985', 'dx_abdominal_muscle_injury_ed3000c7a4', 'Abdominal muscle injury'),
  (3009, 'a8334f57aff3d3d2ae280daf58ad8627cc112668dea5b2e083851cf110c31bcf', 'dx_popliteus_injury_0ac29f0573', 'Popliteus injury'),
  (3010, 'bbb246e69f3173256475e5ee14a0ba8f370b8f0d6e8270201d421a22c4a49241', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (3011, '45735eb60058a024a1ad801c3c246c3afe482f4ed32c8770fdb208e8705e7651', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (3012, '40a52b15951dbeb6214af70c7164bd72777aad134ec456565b479f13c537680b', 'dx_cervical_nerve_root_injury_fc81174c9d', 'Cervical nerve root injury'),
  (3014, 'efc9abb2b261968043d7924ba91cb4df9ca6790b6731154bcc3dfb15924bde5a', 'dx_posterior_cruciate_ligament_injury_e32cf54651', 'Posterior cruciate ligament injury'),
  (3015, 'b029ca450c08eb83a45b55bdebe3167d4b39bf69022571969ffd9901cfd48253', 'dx_mcl_injury_4a1ba1d5c9', 'MCL injury'),
  (3016, '2ebc96c813af56b53211ba17b9bf19ec89ed0c2c78bf281cab1e4417db906f1a', 'dx_sternoclavicular_joint_sprain_6316623d10', 'Sternoclavicular joint sprain'),
  (3017, 'c5a40e915eb86d718f044f16cdec3313ee3cf0431adc67048792348d7b3c9b64', 'dx_common_flexor_origin_injury_b40614ca9b', 'Common flexor origin injury'),
  (3018, '56f2e35f2b8f85cb44e6de71d4ed1ef480c9999e3cacf6eedc9b57dfc0f87df0', 'dx_meniscal_injury_b166306f7d', 'Meniscal injury'),
  (3019, 'e55d5222abab330f65e73ab7e4adffaf94bce5aab49dfc2fb85ab357889287e6', 'dx_metacarpal_fracture_1e117e3ddc', 'Metacarpal fracture'),
  (3020, 'de12bbdbeed183cd9e6f8c1f70aabc6170fe5a3e7bbf9be66db83fc17f2cca63', 'dx_knee_pain_609ce718bc', 'Knee pain'),
  (3021, '6e2406daa878c3bc5174e78143e0b96c6e681026abc5def35830c2985d9db07c', 'dx_heel_bursitis_d80d084f22', 'Heel bursitis'),
  (3022, '1de9067cacdbc223ffc02c65bb7d4e2949d7a8ea0f61cb13d74a7c2b34133d41', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (3023, 'dd0ad858ddbfdf97c834d36535cc20631fd69ea9b6b77ef806194487dad2a07c', 'dx_scaphoid_fracture_906035d07c', 'Scaphoid fracture'),
  (3031, 'c55dae31080edac317b78c08f81d5133439426677542d5f93089034c7b243240', 'dx_sports_hernia_ad99f8552f', 'Sports hernia'),
  (3036, '0b1f353a4ce221bf5374a49b56e59dcf8e27abfd824febca57476d8c773aea4a', 'dx_shoulder_instability_2b9f54f442', 'Shoulder instability'),
  (3038, '6bd9c4bcbb769d6863053b937774e47dc8f6d258054ce4d1af420b36cdc28002', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (3039, '53ebbb7cf2ed86dce09bc357039365b9746066c2128f61b9d0aa54fd684a44ee', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (3040, '1d4ff9c154ad48e9c2420292236ecfc9641ef19fcd0e882a2f6e2d9f34407678', 'dx_thigh_contusion_haematoma_6e95bc71b4', 'Thigh contusion/haematoma'),
  (3041, 'fe73e325066f8558b2bb9b3192b070b48ad6a8558f47b0358e11e08e15e868c7', 'dx_knee_cartilage_injury_761df482b3', 'Knee cartilage injury'),
  (3044, '9cae5ea1e5335909ff9f819fd76d05715a5554bba0ebc90377e408bc3ce468ec', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (3045, '36632a11fd2e5dbb1aad2656a093636d9dc483caef3d0735f1c6987c9c17f5c9', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (3046, 'e57d890284b5fe1125aace957cac9cd1399b7b76042816c6908f2be4433adf85', 'dx_hip_and_groin_pain_27531edcc3', 'Hip and groin pain'),
  (3048, 'd57cebbd730148dc5bd547c1762ea2fdcc4d131de1bd1b3fe3219cd4b84157ef', 'dx_concussion_a91e1107d7', 'Concussion'),
  (3049, '197070a9fad05acdcb46c2bb6ee62a98f930297142ae35975cded13fb869f1d0', 'dx_elbow_ulnar_collateral_ligament_injury_bc56107dc6', 'Elbow ulnar collateral ligament injury'),
  (3050, '3b7c6ec248bd1b47cc8279adec6a1535694113919ec1111325a8e9f5c4dab124', 'dx_wrist_fibrocartilage_injury_fddc60c8f6', 'Wrist fibrocartilage injury'),
  (3051, 'd5c814cc6cd3d90912fde513067f1fdffcde75f97f15271b077d52a72ac14de4', 'dx_achilles_tendon_rupture_6b59cc3783', 'Achilles tendon rupture'),
  (3054, '1577bd77dfb996f0f761ebb8967c179ada6747e0f960f5d17680459f80f2da3c', 'dx_hamstring_injury_f17cabd810', 'Hamstring injury'),
  (3055, '0af5fa0b72c1b784672e3d55d233e5cec934174a73467633d25286dcab5d4201', 'dx_concussion_a91e1107d7', 'Concussion'),
  (3057, '40b0ea05a949c95fc58d67562fc9d385af35578f632c8a7820eaaaec7b81dcc4', 'dx_lumbar_spine_pain_2022547a07', 'Lumbar spine pain'),
  (3058, '7d88735862d1d6eb9108fde3edafadcf97a771a22813dedb954365cdaad034bd', 'dx_soleus_injury_5b8a0d0266', 'Soleus injury'),
  (3059, '54df9d04bb9397c036e3c7714e0664c9543632b6099e70eb5c8de6740939f97e', 'dx_ankle_ligament_injury_286e8e6af7', 'Ankle ligament injury'),
  (3060, 'ce4e65ed183f1fa546f1a5e8c7102170debe8394deb3cdfe04f1950a6b3c2d7b', 'dx_ankle_pain_de6b615afc', 'Ankle pain'),
  (3061, '692e0171b61918b1b50af13370ef16621433ba747f55dcaf1744b9681befab01', 'dx_foot_phalanx_fracture_674038ca61', 'Foot phalanx fracture');

insert into audit.urc_2024_25_classification_adjudications_v1 (
  source_row, source_locator, source_locator_fingerprint,
  source_row_sha256, source_value, final_classification, classification_origin,
  reviewer, reviewed_at, rationale, club_follow_up, second_human_review,
  evidence_sha256
)
values
  (132, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":132}', 'b052957add6119407c20ec1c9745bff1973aefc4e0fe0c490aed7941a912fcb1', 'ca50325fe041d5e33e554cd9e8d47b68ea8df1ef84c31b2859f273c99268fdaa', '', 'Medical Attention', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Explicit human adjudication records a closed Medical Attention case on Date Injured.', false, 'pending', '91d26dcf2a9636cd444e093a874494683de6b590687af50a3c1cc81f2f8a9a25'),
  (144, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":144}', 'fd9c81c368f17078c7204f43d7bbb682e4f41598bf408e10eb8edbd5d49ee7f5', 'da8f53ec5cc4e3101df921032bdddab59177e3aaaafc2273a3b3a7c19d1e537e', '', 'unclassified', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human review found no governed basis to classify this eligible row as Time Loss or Medical Attention; retain it as recorded only. Club follow-up remains optional and does not block this release.', true, 'pending', '3d7450ecd884e0ff4dd94091ac77b4704ff553acac5053812af1e65e0ab1719a'),
  (193, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":193}', 'c16ebf5655254245e72c236e4f77ed50283e5f599dda4c076032b10dd4cc08e6', '948a8a97a8f44d7216e392f3da837c5ae19ac6e81b09299486252fe1c67fe904', '', 'unclassified', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human review found no governed basis to classify this eligible row as Time Loss or Medical Attention; retain it as recorded only. Club follow-up remains optional and does not block this release.', true, 'pending', 'cd1d844dd3925ee58fa1bb053fc681e8278dba9051ccd266c5a575ed9feba44d'),
  (203, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":203}', '8fca45556146e61498eb61f9b01ecd25dde9d66fe0ab28e47ec61b46331aa405', 'c4d1e1aa5075eb82f3d752ae26b905b3239b4c49ad367840ba4f8f159db27c62', '', 'unclassified', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human review found no governed basis to classify this eligible row as Time Loss or Medical Attention; retain it as recorded only. Club follow-up remains optional and does not block this release.', true, 'pending', '4014dec203a1d8623944a9986750c67793db08933ce37cdaf676388ea0493271'),
  (413, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":413}', 'f6742ae382283a550d33ecda50bf44f4276c3e8727bafb4878fb1c98895c99d5', '0d3b71fd2f97475a710abe17a0e57a22c7f8107bcd6dd1cfc61abb9f0d249630', '', 'unclassified', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human review found no governed basis to classify this eligible row as Time Loss or Medical Attention; retain it as recorded only. Club follow-up remains optional and does not block this release.', true, 'pending', '5d9492e67a22c688b438144a76b155ce57e06871b1bb62daddf14e006a4fee24'),
  (454, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":454}', 'c6a128fd4dd82bcce138546dd9a091b74af84a57d0e561cc0d5e23d9b6d3334f', '58603e21290d822294304e9dfa1725a03d181735b936e82d0dbef92b561dff77', '', 'Time Loss', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human adjudication overrides the default inference and records Time Loss without inventing duration or a return date.', false, 'pending', '9a5c4998efddf3ef4da825b573a2bffa18a189b8fa5c0e675528cc63c5d85c41'),
  (469, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":469}', '21327d7177bb8b07a31ed7cf57abe06c471965f7b81d384eae64c876b61ebf53', 'a0fa69f5d64c59bd429acb26ac52507a40f276d2d9ba1f5a7488a3e2916f4195', '', 'Time Loss', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human adjudication overrides the default inference and records Time Loss without inventing duration or a return date.', false, 'pending', '03af8eaeb6f4493c01c433e8d592d8176463cd1c610d9f61eb97e8f1bd8ef74d'),
  (484, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":484}', '5db4aa29f8b3b2300032a930703abdbcd63a7ac2b58ca872586bbed501811f32', '5ed46ccda322f4ce5206ecd21b97edb44a826382abb58d4087f1d30c37cd0305', '', 'Time Loss', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human adjudication overrides the default inference and records Time Loss without inventing duration or a return date.', false, 'pending', 'ad6966fa6f15b358c077efa044bc888f2e3bb064c95f70a5a7425ee5105f6af2'),
  (486, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":486}', '70377311fc4622c9ca07f8bd69e393e370ff2dd99bedaa875c9c5b34833c6da2', '4c41edd94f55f09808a20cc28a1dcd9c540fea0333f3aeb0257d1de3c11b62c5', '', 'Time Loss', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human adjudication overrides the default inference and records Time Loss without inventing duration or a return date.', false, 'pending', '905a75655f970c0bce72745427190b34da18aaeff4142cb7133b99dfbce1d46b'),
  (488, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":488}', '0c5cbc7a08b9986c705c1160223fadf04e810b419dd16e28180ceb9c1ace990f', '289341186e95660283db982979bf2bed042f0a0824f160c8d09d10db7646c0d1', '', 'Time Loss', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human adjudication overrides the default inference and records Time Loss without inventing duration or a return date.', false, 'pending', '7dad193f04e23968b04d3af7dcda6c5f05076e72f19015bd58a5f5ae25e77d69'),
  (490, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":490}', '2c966eab54f2e640a392a3038c237e08eae6e6b26a9ff76f3ff7be117414e61a', 'c36222720060ecb5475fb7a578a5d0fdd0e970d187654be86583059b1359f6e5', '', 'unclassified', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human review found no governed basis to classify this eligible row as Time Loss or Medical Attention; retain it as recorded only. Club follow-up remains optional and does not block this release.', true, 'pending', '5928bcb2fa2930bc6aab376980e0bcd858b04906c0eb5048a503c8f6479bbc76'),
  (491, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":491}', '05f2a7d9c3cadc3924d60478ec56f2e23396bf87b4f1059829105f59e67401ee', '7cd00b5fb81d2d19acbde11cda762249b263921e0859ea8f3c73f23d3faae5ff', '', 'unclassified', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human review found no governed basis to classify this eligible row as Time Loss or Medical Attention; retain it as recorded only. Club follow-up remains optional and does not block this release.', true, 'pending', '1c78dd7f9fa0d6fffaab3e6f90ce260c05cedd73ebda7df47c089f97ab2aac3d'),
  (495, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":495}', '65ad1b03f26b311768b51c9ffc0e56c7f8344b93cbf99e84c51c1f1cb4618227', '97263bed643d3514d3ffb98921cdb2a400bcc9acfb38c366b0f30f94be161d94', '', 'unclassified', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human review found no governed basis to classify this eligible row as Time Loss or Medical Attention; retain it as recorded only. Club follow-up remains optional and does not block this release.', true, 'pending', '68364d562c989bd0e69b710cf738517d2257b6bc7c93047d83b0f26ba3b4adb0'),
  (497, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":497}', '3cb074677295bc965a08dc2ff45fee849302bcee3480f8e4aaf9a207bf640442', '07afc39ab0a47742b175b93911e30b1807353d825cbbc81c4e0ccde610e949ed', '', 'Time Loss', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human adjudication overrides the default inference and records Time Loss without inventing duration or a return date.', false, 'pending', '0c70e39c45646f360b768def404f917ba2a48c068931a3aa9d82f0353a1fce6a'),
  (499, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":499}', '05fc4d0befbecb828b4972f516d59d9d0fed6f26348b4b73eff12bdb8619f33b', '0244d092e7160cab078ff27c3390d2992bf7dbc3ce2d14341b6539c5c9a3a38a', '', 'Time Loss', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human adjudication overrides the default inference and records Time Loss without inventing duration or a return date.', false, 'pending', 'daab20b382fb0f5726f4bd38c1d43da0c4684dfc39ee2054da362ad563758df0'),
  (500, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":500}', 'eb7300e0f39395628a8e587e7ecd9c736790e1dc06a40f1affa49a6c380d186b', '9c55452f85e16f6ba02479bf5e405921864284d741b0000915bdc2ef6c6f9605', '', 'Time Loss', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human adjudication overrides the default inference and records Time Loss without inventing duration or a return date.', false, 'pending', 'a823d9f4ee47b99262cd37925cb16520d8d3673aff31fa4ed2928ff8ec4f6d97'),
  (503, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":503}', '5f4cc4afad1d933abb113029bafe890c538fb34c3116215f5eb110339153641b', '3b780f0e8f960619e3b58b20c2216f2c116d8e35d5d2c165db8836f9be48ef3f', '', 'unclassified', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human review found no governed basis to classify this eligible row as Time Loss or Medical Attention; retain it as recorded only. Club follow-up remains optional and does not block this release.', true, 'pending', '0759101b5f0f1eae9a04db97bd5d9e429f35f865b6a648e1efe6311f7c4394fc'),
  (510, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":510}', '46d53bfac344d8daf08454129c91609679c47d8f7442f41da771c26cead8128b', '71a43b157b9eadfe205857914a9f6e7eebdb0f3fa3ea35e358d311db0c919b53', '', 'Time Loss', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human adjudication overrides the default inference and records Time Loss without inventing duration or a return date.', false, 'pending', '84c7ee3e4ae7667cce0d91e9d0228eceeb172fe4eb4b682e55b9c1be24533eb7'),
  (511, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":511}', '23f2867f4158455c45abe7ffbd4e015ce008f7c840937c21fe45793f20ba7ca7', '8d6fdf50723fdd8eb913b5e283346afc5f4076e2a0435c8dccc40740901cdbe8', '', 'unclassified', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human review found no governed basis to classify this eligible row as Time Loss or Medical Attention; retain it as recorded only. Club follow-up remains optional and does not block this release.', true, 'pending', 'aab4e7dc4674f7c8d7f453f22e55b186789058c7d1a8ebc9ad6456e1b68785b3'),
  (514, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":514}', 'b0ee6a28f3a4e993e508c61652921658710a765d5dad333e43f0b3ba047e9e54', '08be9dee5d7a985618ac8052149e9896c703f2834753f92e0cd6ab2c8529fc68', '', 'unclassified', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human review found no governed basis to classify this eligible row as Time Loss or Medical Attention; retain it as recorded only. Club follow-up remains optional and does not block this release.', true, 'pending', 'b9c4ee4bc5662eef08d0b13fe8736e042ef8f3c8f707404f324011c3cfcbf078'),
  (515, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":515}', '64f83f53cc3c19574e32f39eaf51b73f4a11a2d9db917919a679fe998972a9c9', '52c0d4ba949f99b957c9549f2f268ff960a70e997a949154dad5227fa3c9506e', '', 'Time Loss', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human adjudication overrides the default inference and records Time Loss without inventing duration or a return date.', false, 'pending', '01755c7025cadcc54104bd883878500f3d90ffb8c84a5ca7ac65d739dab141c3'),
  (526, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":526}', '42ae6d768eb101477e7709c501a788d28718580b4359c3337e0e323c54fd6c19', '386ba9339d5bb1c56b005b9bc6205e99cab713313ef8011944b3527832e18984', '', 'unclassified', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human review found no governed basis to classify this eligible row as Time Loss or Medical Attention; retain it as recorded only. Club follow-up remains optional and does not block this release.', true, 'pending', '6bd0ec715dc599ceb18541df905a0f579e0271b616e6d09a95cdd2ff8129803c'),
  (528, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":528}', '4821c8cab69d096de9c5982a0fca7b023545b5c42f6078265af543dde4d051dc', '77a079cee6879408387adf3640555dd9dbeb6047376f9d75ef54a9eff3386400', '', 'unclassified', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human review found no governed basis to classify this eligible row as Time Loss or Medical Attention; retain it as recorded only.', false, 'pending', 'f2528e19f393a8a30d3496c8a490683a1b9b57cc9e6480dcddd4118392441119'),
  (529, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":529}', '7c831f5ae53a7aa78c31093d17c0af8bcdedf2d116c830fcbbb74bb8834aa1d6', 'fc761f453a2cc7a64a39369250eef1aabcf39374068ed58cc5a2141ee8db7726', '', 'Time Loss', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human adjudication overrides the default inference and records Time Loss without inventing duration or a return date.', false, 'pending', '867123dc46f67d7603ff2af05426e486baf2f35a9afe896f264511df3b23b336'),
  (530, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":530}', 'f9903a2ae777b950b51711103d2974ff1a97df0a5e6448494c5030be2bc220fc', '6c606677cdf0270112f98cd5cfbbe74a3c355205670d61294bd23fc8b3fffddb', '', 'unclassified', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human review found no governed basis to classify this eligible row as Time Loss or Medical Attention; retain it as recorded only.', false, 'pending', 'dbc8356ea64becc923b7d5012e8bcd33cba360a214ada9e2cff79b9942ba929c'),
  (531, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":531}', '679dbc6e8c45ec6baa77520b00a503859fe60aef4050e1383c8fff44c0a6c554', 'cf57e99c4af7495ee70842541ea96947839393336d0df060b43196c5b21ffd13', '', 'unclassified', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human review found no governed basis to classify this eligible row as Time Loss or Medical Attention; retain it as recorded only.', false, 'pending', 'ce4297e1f47403204ed8fb64f74071e646113504e7179ec6fafe561a5c3d3b7a'),
  (535, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":535}', 'd650c98fec3050451af359d4adae6487206feb1cb2d0f5b446b45c925ea49470', '0600a3aabc3e8a87bd272ea48f53385f0a9fa520cc8d59814e97ff542f37e7f0', '', 'Time Loss', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human adjudication overrides the default inference and records Time Loss without inventing duration or a return date.', false, 'pending', '899f4acfa61abb255db9c8d64651614490d14c853494ad86d145133cfc42c6f7'),
  (1570, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":1570}', 'b8438a58d89fa99ffafb8e30ccc6bcd70affd0a06949a64785a246bf8ed23c88', '236652a92e72d7cd5c1a5c58150af1fa8471f20c84ea71cd33901c3c0e2362e4', 'FALSE', 'Time Loss', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human adjudication overrides the default inference and records Time Loss without inventing duration or a return date.', false, 'pending', '4b8117ed1784d63edc2f10c9afad906708ef8c77f092cc5c2230d42aa14d795e'),
  (1578, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":1578}', 'c83fce59600a5593d7360d0f16cb5338025cfde4a1ddb82c6263b1e6295de8dc', '4ce1188e48832630613e0a3d087c7282ab03bdcb3bc8be90db57dde8599abb10', 'FALSE', 'unclassified', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human review found no governed basis to classify this eligible row as Time Loss or Medical Attention; retain it as recorded only.', false, 'pending', 'edacfa5be47b609b7b6de25da34e7939a68aeee279ebc3256bf3af42efc577ef'),
  (1875, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":1875}', '21d59b88321d8312faa1a41ed73d76be3009e3747ca1dcd009cb6d17616428cf', '8a22d45d5710f214a189e8ba002aba5c9fa0fbed1a2959c2ef2e3c22b4e7df88', '', 'Time Loss', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human adjudication overrides the default inference and records Time Loss without inventing duration or a return date.', false, 'pending', '5abd39d99db554ab5bde2837fec8b6d5d5779adcb0ca79bc621f9c99b76577b9'),
  (1876, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":1876}', '568cf5828c10c49297e325cec7a7702d4f1c67ef3760a0fd968911684f3cfa2e', '26c713efd915a79004a632066f78f1f0547a716a68cfee950ea8215cdbbbcbc4', '', 'Time Loss', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human adjudication overrides the default inference and records Time Loss without inventing duration or a return date.', false, 'pending', 'eeeb105ada6fd1fc306d63728e32277cbdc3dbb32a2ff67688b06dd097cf8fa6'),
  (2275, '{"path":"data/2024-25/review/urc_injury_master_review_2024-25.xlsx","sheet":"Injury Master","excel_row":2275}', 'ab93374ae951e828dbccfde9514eda553f3df22b028516dd2c9a38d6f73c001f', '13f217c8ef35100fbc5c748e5d1360b1c3f65c90adcb1d058b9922ca279debda', 'FALSE', 'unclassified', 'adjudicated', 'Abdel Babiker', '2026-08-26', 'Human review found no governed basis to classify this eligible row as Time Loss or Medical Attention; retain it as recorded only.', false, 'pending', '724d317a17f101c35f47b26d9c4a7284165e2a268d2f8be9c8e4ad52852c881b');


create view analysis.urc_2024_25_classification_evidence_v1
with (security_invoker = true) as
with rows as (
  select a.*
  from audit.urc_2024_25_classification_adjudications_v1 a
  where a.season = '2024-25'
)
select
  '2024-25'::text as season,
  'urc_2024-25_classification_monthly_successor_2026-08-27_v1'::text
    as rule_version,
  count(*)::integer as adjudication_rows,
  count(*) filter (where final_classification = 'Time Loss')::integer
    as time_loss_rows,
  count(*) filter (where final_classification = 'Medical Attention')::integer
    as medical_attention_rows,
  count(*) filter (where final_classification = 'unclassified')::integer
    as unclassified_rows,
  count(*) filter (where source_value = '')::integer as blank_source_values,
  count(*) filter (where source_value = 'FALSE')::integer as false_source_values,
  -- Verified against these exact SQL rows by the local evidence contract test.
  'cd5bed8cd5a98a6b5290194371fb92f01020ed8020ff3ddb859251741f349835'::text
    as adjudication_manifest_sha256,
  '0f7707e9b905ce1c604beeb2261ac18df880af9942de5093e2a564589e08e833'::text
    as evidence_file_sha256,
  '87ebb569afc45ef28116df98dc83c2d8799139eaecd1c249372c209fa783f155'::text
    as adjudication_workbook_sha256,
  '4f1db130f9f5aff23c3473eb2ab64a467f739a0b6ac7e4f170ca0383d9072b73'::text
    as accepted_workbook_sha256,
  '15b9af0da05aa57698487f4c8ebacf9923cec4e66846ac00b76fa3c2b75f2f63'::text
    as source_master_sha256,
  'b83d9ab7cf68d8c1b2239ebcd49cb9de882d91b4db1174d80b3fbcdf7baea051'::text
    as active_correction_set_sha256,
  'a43ba36a7f67ecd208112d702bcc058de947b00d721399e9e0ad26d23f3ac167'::text
    as specific_diagnosis_evidence_sha256,
  '8c26ddfbabef220a5ddc8e957b6ef143f0eeb46342d4e9634edf720162e5b7c7'::text
    as specific_diagnosis_mapping_rows_sha256,
  1660::integer as specific_diagnosis_injury_rows,
  392::integer as specific_diagnosis_illness_rows_excluded,
  '9bd4ff3c60fb1aa33e3f4d1d1c5ff35f83bbd6cbd777aca90b6fbd3bc980de7c'::text
    as successor_disclosure_method_sha256,
  'd8b32c5dddb9f740d238b44e4c40d099ed671ccc58bcdc95a5310471c78b75f9'::text
    as successor_disclosure_limitations_sha256
from rows;

do $$
declare
  evidence analysis.urc_2024_25_classification_evidence_v1%rowtype;
begin
  select * into evidence from analysis.urc_2024_25_classification_evidence_v1;
  if evidence.adjudication_rows <> 32
     or evidence.time_loss_rows <> 15
     or evidence.medical_attention_rows <> 1
     or evidence.unclassified_rows <> 16
     or evidence.blank_source_values <> 29
     or evidence.false_source_values <> 3
     or evidence.evidence_file_sha256 <>
       '0f7707e9b905ce1c604beeb2261ac18df880af9942de5093e2a564589e08e833'
     or evidence.source_master_sha256 <>
       '15b9af0da05aa57698487f4c8ebacf9923cec4e66846ac00b76fa3c2b75f2f63'
     or evidence.adjudication_manifest_sha256 <>
       'cd5bed8cd5a98a6b5290194371fb92f01020ed8020ff3ddb859251741f349835'
     or evidence.active_correction_set_sha256 <>
       'b83d9ab7cf68d8c1b2239ebcd49cb9de882d91b4db1174d80b3fbcdf7baea051'
     or evidence.specific_diagnosis_evidence_sha256 <>
       'a43ba36a7f67ecd208112d702bcc058de947b00d721399e9e0ad26d23f3ac167'
     or evidence.specific_diagnosis_mapping_rows_sha256 <>
       '8c26ddfbabef220a5ddc8e957b6ef143f0eeb46342d4e9634edf720162e5b7c7'
     or evidence.specific_diagnosis_injury_rows <> 1660
     or evidence.specific_diagnosis_illness_rows_excluded <> 392
     or (select count(*) from audit.urc_2024_25_specific_diagnosis_mappings_v1) <> 1660
     or (select count(distinct diagnosis_group_code)
         from audit.urc_2024_25_specific_diagnosis_mappings_v1) <> 274
     or evidence.successor_disclosure_method_sha256 <>
       '9bd4ff3c60fb1aa33e3f4d1d1c5ff35f83bbd6cbd777aca90b6fbd3bc980de7c'
     or evidence.successor_disclosure_limitations_sha256 <>
       'd8b32c5dddb9f740d238b44e4c40d099ed671ccc58bcdc95a5310471c78b75f9'
  then
    raise exception '2024-25 adjudication evidence failed closed exact-count/hash gate';
  end if;
end;
$$;

create materialized view analysis.urc_2024_25_final_injury_classification_v1 as
with members as (
  select *
  from analysis.row_correction_member_releases_v1
  where season = '2024-25'
    and predecessor_bundle_id =
      '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid
), cohort as (
  select c.*, subject.final_values,
    subject.source_row_sha256 as ingestion_source_row_sha256,
    master.row_values ->> 'TimeLoss vs Medical Attention'
      as master_source_classification_value,
    injury.problem_type as canonical_problem_type,
    injury.contact_context,
    origin.diagnosis_code, origin.diagnosis_label
  from analysis.row_correction_effective_injury_cohort_v3 c
  join members m using (curated_build_id, team_key, season)
  cross join lateral analysis.row_correction_subject_v3(
    c.season, c.source_row_id
  ) subject
  join lineage.baselines baseline
    on baseline.season = c.season
   and baseline.master_json_sha256 =
     '15b9af0da05aa57698487f4c8ebacf9923cec4e66846ac00b76fa3c2b75f2f63'
  join lineage.master_rows master
    on master.season = c.season
   and master.source_row = c.source_row
  join lineage.master_source_bridge bridge
    on bridge.season = c.season
   and bridge.source_row = c.source_row
   and bridge.source_row_id = c.source_row_id
   and bridge.injury_id = c.injury_id
   and bridge.curated_build_id = c.curated_build_id
  join curated.injuries injury
    on injury.id = c.injury_id
   and injury.curated_build_id = c.curated_build_id
   and injury.team_key = c.team_key
   and injury.season = c.season
  left join analysis.row_correction_reporting_classification_origin_v3 origin
    on origin.injury_id = c.injury_id
   and origin.curated_build_id = c.curated_build_id
   and origin.team_key = c.team_key
   and origin.season = c.season
  where c.season = '2024-25'
), parsed as (
  select cohort.*,
    case
      when trim(cohort.final_values ->> 'Date Injured')
        ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
        then to_date(trim(cohort.final_values ->> 'Date Injured'), 'DD/MM/YYYY')
      else null::date
    end as parsed_date_injured,
    case
      when trim(cohort.final_values ->> 'Days Injured')
        ~ '^[0-9]+(\\.[0-9]+)?$'
        then trim(cohort.final_values ->> 'Days Injured')::numeric
      else null::numeric
    end as parsed_days_lost,
    lower(trim(coalesce(
      nullif(cohort.master_source_classification_value, ''),
      ''
    ))) as source_classification_value
  from cohort
), decided as (
  select parsed.*,
    adjudication.final_classification as adjudicated_classification,
    adjudication.classification_origin as adjudicated_origin,
    case
      when adjudication.final_classification is not null
        then adjudication.final_classification
      when parsed.is_time_loss then 'Time Loss'
      when parsed.source_classification_value in
        ('medical attention', 'medical_attention', 'medical-attention')
        then 'Medical Attention'
      when parsed.parsed_days_lost = 0
        then 'Medical Attention'
      when parsed.source_classification_value in
        ('time loss', 'time_loss', 'timeloss', 'true')
        then 'Time Loss'
      when parsed.parsed_days_lost > 0
        then 'Time Loss'
      else 'unclassified'
    end as final_classification
  from parsed
  left join audit.urc_2024_25_classification_adjudications_v1 adjudication
    on adjudication.season = parsed.season
   and adjudication.source_row = parsed.source_row
), classified as (
  select decided.*,
    case
      when adjudicated_classification is not null then adjudicated_origin
      when is_time_loss then 'predecessor_time_loss'
      when source_classification_value in
        ('medical attention', 'medical_attention', 'medical-attention',
         'time loss', 'time_loss', 'timeloss', 'true')
        then 'source_reported'
      when parsed_days_lost = 0 then 'inferred_zero_days'
      when parsed_days_lost > 0 then 'inferred_positive_days'
      else 'unclassified_default'
    end as classification_origin,
    parsed_days_lost is not null as duration_usable
  from decided
)
select
  season, source_row, source_row_id, injury_id, curated_build_id, team_key,
  parsed_date_injured as date_injured,
  parsed_days_lost as days_lost,
  ingestion_source_row_sha256,
  canonical_problem_type,
  source_classification_value,
  final_classification,
  classification_origin,
  duration_usable,
  final_classification = 'Time Loss' as is_time_loss,
  final_classification = 'Medical Attention' as is_medical_attention,
  final_classification = 'unclassified' as is_unclassified,
  case
    when final_classification = 'Time Loss' and parsed_days_lost is null
      then 'Open/Ongoing'
    when final_classification in ('Time Loss', 'Medical Attention')
      then 'Closed'
    else 'Not applicable'
  end as closure_status,
  case
    when final_classification = 'Medical Attention'
      then 'zero_days_medical_attention_only'
    when final_classification = 'Time Loss' and parsed_days_lost = 1
      then 'one_day'
    when final_classification = 'Time Loss' and parsed_days_lost between 2 and 3
      then 'two_to_three_days'
    when final_classification = 'Time Loss' and parsed_days_lost between 4 and 7
      then 'four_to_seven_days'
    when final_classification = 'Time Loss' and parsed_days_lost between 8 and 28
      then 'eight_to_twenty_eight_days'
    when final_classification = 'Time Loss' and parsed_days_lost > 28
      then 'greater_than_twenty_eight_days'
    else null
  end as severity_code,
  case
    when final_classification = 'Medical Attention' then 'Medical attention'
    when final_classification = 'Time Loss' and parsed_days_lost = 1
      then '1 day'
    when final_classification = 'Time Loss' and parsed_days_lost between 2 and 3
      then '2-3 days'
    when final_classification = 'Time Loss' and parsed_days_lost between 4 and 7
      then '4-7 days'
    when final_classification = 'Time Loss' and parsed_days_lost between 8 and 28
      then '8-28 days'
    when final_classification = 'Time Loss' and parsed_days_lost > 28
      then '>28 days'
    else null
  end as severity_label,
  parsed_date_injured is null as is_undated,
  setting_code,
  body_location_code,
  body_location_label,
  injury_type_code,
  injury_type_label,
  diagnosis_code,
  diagnosis_label,
  contact_context
from classified;

create view analysis.urc_2024_25_team_injury_metrics_v1
with (security_invoker = true) as
select
  f.curated_build_id, f.team_key, f.season,
  count(*)::bigint as recorded_injuries,
  count(*) filter (where f.final_classification = 'Time Loss')::bigint
    as time_loss_injuries,
  count(*) filter (where f.final_classification = 'Medical Attention')::bigint
    as medical_attention_injuries,
  count(*) filter (where f.final_classification = 'unclassified')::bigint
    as unclassified_injuries,
  count(*) filter (
    where f.final_classification = 'Time Loss' and f.duration_usable
  )::bigint as known_duration_time_loss_injuries,
  coalesce(sum(f.days_lost) filter (
    where f.final_classification = 'Time Loss' and f.duration_usable
  ), 0)::numeric as days_lost,
  avg(f.days_lost) filter (
    where f.final_classification = 'Time Loss' and f.duration_usable
  ) as mean_severity_days,
  percentile_cont(0.5) within group (order by f.days_lost) filter (
    where f.final_classification = 'Time Loss' and f.duration_usable
  ) as median_severity_days
from analysis.urc_2024_25_final_injury_classification_v1 f
group by f.curated_build_id, f.team_key, f.season;

create view analysis.urc_2024_25_team_setting_metrics_v1
with (security_invoker = true) as
with grouped as (
  select f.curated_build_id, f.team_key, f.season, f.setting_code,
    count(*)::bigint as recorded_injuries,
    count(*) filter (where f.final_classification = 'Time Loss')::bigint
      as time_loss_injuries,
    coalesce(sum(f.days_lost) filter (
      where f.final_classification = 'Time Loss' and f.duration_usable
    ), 0)::numeric as days_lost,
    count(*) filter (
      where f.final_classification = 'Time Loss' and f.duration_usable
    )::bigint as known_duration_time_loss_injuries
  from analysis.urc_2024_25_final_injury_classification_v1 f
  group by f.curated_build_id, f.team_key, f.season, f.setting_code
), exposure as (
  select p.team_key, p.dashboard_payload,
    p.curated_build_id
  from reporting.dashboard_bundle_team_payloads_v1 p
  where p.bundle_release_id =
    '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid
)
select g.*,
  case g.setting_code
    when 'match' then (e.dashboard_payload -> 'coverage' ->> 'match_hours')::numeric
    when 'training' then (e.dashboard_payload -> 'coverage' ->> 'training_hours')::numeric
    when 'all' then (e.dashboard_payload -> 'coverage' ->> 'hours')::numeric
    else null::numeric
  end as exposure_hours,
  case g.setting_code
    when 'match' then
      g.recorded_injuries::numeric * 1000 /
      nullif((e.dashboard_payload -> 'coverage' ->> 'match_hours')::numeric, 0)
    when 'training' then
      g.recorded_injuries::numeric * 1000 /
      nullif((e.dashboard_payload -> 'coverage' ->> 'training_hours')::numeric, 0)
    when 'all' then
      g.recorded_injuries::numeric * 1000 /
      nullif((e.dashboard_payload -> 'coverage' ->> 'hours')::numeric, 0)
    else null::numeric
  end as overall_incidence_per_1000h,
  case g.setting_code
    when 'match' then
      g.time_loss_injuries::numeric * 1000 /
      nullif((e.dashboard_payload -> 'coverage' ->> 'match_hours')::numeric, 0)
    when 'training' then
      g.time_loss_injuries::numeric * 1000 /
      nullif((e.dashboard_payload -> 'coverage' ->> 'training_hours')::numeric, 0)
    when 'all' then
      g.time_loss_injuries::numeric * 1000 /
      nullif((e.dashboard_payload -> 'coverage' ->> 'hours')::numeric, 0)
    else null::numeric
  end as incidence_per_1000h,
  case g.setting_code
    when 'match' then
      g.days_lost * 1000 /
      nullif((e.dashboard_payload -> 'coverage' ->> 'match_hours')::numeric, 0)
    when 'training' then
      g.days_lost * 1000 /
      nullif((e.dashboard_payload -> 'coverage' ->> 'training_hours')::numeric, 0)
    when 'all' then
      g.days_lost * 1000 /
      nullif((e.dashboard_payload -> 'coverage' ->> 'hours')::numeric, 0)
    else null::numeric
  end as burden_per_1000h,
  g.days_lost / nullif(g.known_duration_time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join exposure e using (team_key, curated_build_id);

create view analysis.urc_2024_25_team_profiles_v1
with (security_invoker = true) as
with dimensions as (
  select f.curated_build_id, f.team_key, f.season,
    d.dimension, d.code, d.label,
    count(*) filter (where f.final_classification = 'Time Loss')::bigint
      as time_loss_injuries,
    coalesce(sum(f.days_lost) filter (
      where f.final_classification = 'Time Loss' and f.duration_usable
    ), 0)::numeric as days_lost,
    count(*) filter (
      where f.final_classification = 'Time Loss' and f.duration_usable
    )::bigint as known_duration_time_loss_injuries
  from analysis.urc_2024_25_final_injury_classification_v1 f
  cross join lateral (values
    ('body_location'::text, f.body_location_code, f.body_location_label),
    ('injury_type'::text, f.injury_type_code, f.injury_type_label),
    ('injury_profile'::text,
      f.body_location_code || '__' || f.injury_type_code,
      f.body_location_label || ' · ' || f.injury_type_label)
  ) d(dimension, code, label)
  group by f.curated_build_id, f.team_key, f.season,
    d.dimension, d.code, d.label
  union all
  select f.curated_build_id, f.team_key, f.season,
    'diagnosis'::text as dimension,
    coalesce(m.diagnosis_group_code, 'unknown') as code,
    coalesce(m.diagnosis_group_label, 'Unknown') as label,
    count(*) filter (where f.final_classification = 'Time Loss')::bigint
      as time_loss_injuries,
    coalesce(sum(f.days_lost) filter (
      where f.final_classification = 'Time Loss' and f.duration_usable
    ), 0)::numeric as days_lost,
    count(*) filter (
      where f.final_classification = 'Time Loss' and f.duration_usable
    )::bigint as known_duration_time_loss_injuries
  from analysis.urc_2024_25_final_injury_classification_v1 f
  left join audit.urc_2024_25_specific_diagnosis_mappings_v1 m
    on m.season = f.season
   and m.source_row = f.source_row
  where f.canonical_problem_type = 'injury'
  group by f.curated_build_id, f.team_key, f.season,
    m.diagnosis_group_code, m.diagnosis_group_label
), exposure as (
  select p.team_key, p.curated_build_id, p.dashboard_payload
  from reporting.dashboard_bundle_team_payloads_v1 p
  where p.bundle_release_id =
    '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid
)
select d.*,
  (e.dashboard_payload -> 'coverage' ->> 'hours')::numeric as exposure_hours,
  d.time_loss_injuries::numeric * 1000 /
    nullif((e.dashboard_payload -> 'coverage' ->> 'hours')::numeric, 0)
    as incidence_per_1000h,
  d.days_lost * 1000 /
    nullif((e.dashboard_payload -> 'coverage' ->> 'hours')::numeric, 0)
    as burden_per_1000h,
  d.days_lost / nullif(d.known_duration_time_loss_injuries, 0)
    as mean_severity_days
from dimensions d join exposure e using (team_key, curated_build_id);

create view analysis.urc_2024_25_team_severity_distribution_v1
with (security_invoker = true) as
select f.curated_build_id, f.team_key, f.season, f.severity_code,
  f.severity_label,
  count(*)::bigint as recorded_injuries,
  count(*) filter (where f.final_classification = 'Time Loss')::bigint
    as time_loss_injuries,
  coalesce(sum(f.days_lost) filter (
    where f.final_classification = 'Time Loss' and f.duration_usable
  ), 0)::numeric as days_lost,
  case f.severity_code
    when 'zero_days_medical_attention_only' then 0
    when 'one_day' then 1
    when 'two_to_three_days' then 2
    when 'four_to_seven_days' then 3
    when 'eight_to_twenty_eight_days' then 4
    when 'greater_than_twenty_eight_days' then 5
    else 6
  end as band_order
from analysis.urc_2024_25_final_injury_classification_v1 f
where f.severity_code is not null
group by f.curated_build_id, f.team_key, f.season,
  f.severity_code, f.severity_label;

create view analysis.urc_2024_25_team_contact_distribution_v1
with (security_invoker = true) as
with observed as (
  select f.curated_build_id, f.team_key, f.season, f.setting_code,
    f.contact_context,
    count(*)::bigint as recorded_injuries,
    count(*) filter (where f.final_classification = 'Time Loss')::bigint
      as time_loss_injuries
  from analysis.urc_2024_25_final_injury_classification_v1 f
  group by f.curated_build_id, f.team_key, f.season,
    f.setting_code, f.contact_context
  union all
  select f.curated_build_id, f.team_key, f.season, 'all'::text,
    f.contact_context,
    count(*)::bigint,
    count(*) filter (where f.final_classification = 'Time Loss')::bigint
  from analysis.urc_2024_25_final_injury_classification_v1 f
  group by f.curated_build_id, f.team_key, f.season, f.contact_context
), domains as (
  select x.setting_code, y.contact_context, y.contact_label
  from (values ('all'), ('match'), ('training'), ('unknown')) x(setting_code)
  cross join (values
    ('contact', 'Contact'), ('non_contact', 'Non-contact'),
    ('unknown', 'Unknown')
  ) y(contact_context, contact_label)
)
select p.team_key, p.curated_build_id, '2024-25'::text as season,
  d.setting_code, d.contact_context, d.contact_label,
  coalesce(o.recorded_injuries, 0)::bigint as recorded_injuries,
  coalesce(o.time_loss_injuries, 0)::bigint as time_loss_injuries
from (
  select distinct team_key, curated_build_id, season
  from analysis.urc_2024_25_final_injury_classification_v1
) p
cross join domains d
left join observed o using (
  team_key, curated_build_id, season, setting_code, contact_context
);

create view analysis.urc_2024_25_team_monthly_v1
with (security_invoker = true) as
with predecessor_months as (
  select p.team_key, p.curated_build_id, item as source_item,
    to_date('01 ' || (item ->> 'month'), 'DD Mon YYYY') as month_start
  from reporting.dashboard_bundle_team_payloads_v1 p
  cross join lateral jsonb_array_elements(p.dashboard_payload -> 'monthly') item
  where p.bundle_release_id =
    '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid
), injuries as (
  select f.curated_build_id, f.team_key,
    date_trunc('month', f.date_injured)::date as month_start,
    count(*)::bigint as recorded_injuries,
    count(*) filter (where f.final_classification = 'Time Loss')::bigint
      as time_loss_injuries,
    coalesce(sum(f.days_lost) filter (
      where f.final_classification = 'Time Loss' and f.duration_usable
    ), 0)::numeric as days_lost
  from analysis.urc_2024_25_final_injury_classification_v1 f
  where f.date_injured is not null
  group by f.curated_build_id, f.team_key,
    date_trunc('month', f.date_injured)::date
)
select p.team_key, p.curated_build_id, p.source_item, p.month_start,
  coalesce(i.recorded_injuries, 0)::bigint as recorded_injuries,
  coalesce(i.time_loss_injuries, 0)::bigint as time_loss_injuries,
  coalesce(i.days_lost, 0)::numeric as days_lost,
  (p.source_item ->> 'exposure_hours')::numeric as exposure_hours,
  (p.source_item ->> 'distance_km')::numeric as distance_km,
  coalesce(i.recorded_injuries, 0)::numeric * 1000 /
    nullif((p.source_item ->> 'exposure_hours')::numeric, 0)
    as overall_incidence_per_1000h,
  coalesce(i.time_loss_injuries, 0)::numeric * 1000 /
    nullif((p.source_item ->> 'exposure_hours')::numeric, 0)
    as incidence_per_1000h,
  coalesce(i.days_lost, 0)::numeric * 1000 /
    nullif((p.source_item ->> 'exposure_hours')::numeric, 0)
    as burden_per_1000h
from predecessor_months p
left join injuries i using (team_key, curated_build_id, month_start);

create view analysis.urc_2024_25_league_metrics_v1
with (security_invoker = true) as
select
  '2024-25'::text as season,
  count(*)::bigint as recorded_injuries,
  count(*) filter (where final_classification = 'Time Loss')::bigint
    as time_loss_injuries,
  count(*) filter (where final_classification = 'Medical Attention')::bigint
    as medical_attention_injuries,
  count(*) filter (where final_classification = 'unclassified')::bigint
    as unclassified_injuries,
  count(*) filter (
    where final_classification = 'Time Loss' and duration_usable
  )::bigint as known_duration_time_loss_injuries,
  coalesce(sum(days_lost) filter (
    where final_classification = 'Time Loss' and duration_usable
  ), 0)::numeric as days_lost,
  avg(days_lost) filter (
    where final_classification = 'Time Loss' and duration_usable
  ) as mean_severity_days,
  percentile_cont(0.5) within group (order by days_lost) filter (
    where final_classification = 'Time Loss' and duration_usable
  ) as median_severity_days
from analysis.urc_2024_25_final_injury_classification_v1;

create view analysis.urc_2024_25_league_setting_metrics_v1
with (security_invoker = true) as
select setting_code,
  sum(recorded_injuries)::bigint as recorded_injuries,
  sum(time_loss_injuries)::bigint as time_loss_injuries,
  sum(days_lost)::numeric as days_lost,
  sum(known_duration_time_loss_injuries)::bigint
    as known_duration_time_loss_injuries,
  sum(exposure_hours)::numeric as exposure_hours,
  sum(recorded_injuries)::numeric * 1000 /
    nullif(sum(exposure_hours), 0) as overall_incidence_per_1000h,
  sum(time_loss_injuries)::numeric * 1000 /
    nullif(sum(exposure_hours), 0) as incidence_per_1000h,
  sum(days_lost)::numeric * 1000 / nullif(sum(exposure_hours), 0)
    as burden_per_1000h,
  sum(days_lost)::numeric /
    nullif(sum(known_duration_time_loss_injuries), 0) as mean_severity_days
from analysis.urc_2024_25_team_setting_metrics_v1
group by setting_code;

create view analysis.urc_2024_25_league_profiles_v1
with (security_invoker = true) as
select dimension, code, label,
  sum(time_loss_injuries)::bigint as time_loss_injuries,
  sum(days_lost)::numeric as days_lost,
  sum(known_duration_time_loss_injuries)::bigint
    as known_duration_time_loss_injuries,
  sum(exposure_hours)::numeric as exposure_hours,
  sum(time_loss_injuries)::numeric * 1000 /
    nullif(sum(exposure_hours), 0) as incidence_per_1000h,
  sum(days_lost)::numeric * 1000 / nullif(sum(exposure_hours), 0)
    as burden_per_1000h,
  sum(days_lost)::numeric /
    nullif(sum(known_duration_time_loss_injuries), 0) as mean_severity_days
from analysis.urc_2024_25_team_profiles_v1
group by dimension, code, label;

create view analysis.urc_2024_25_league_severity_distribution_v1
with (security_invoker = true) as
select severity_code, severity_label,
  sum(recorded_injuries)::bigint as recorded_injuries,
  sum(time_loss_injuries)::bigint as time_loss_injuries,
  sum(days_lost)::numeric as days_lost,
  min(band_order) as band_order
from analysis.urc_2024_25_team_severity_distribution_v1
group by severity_code, severity_label;

create view analysis.urc_2024_25_league_contact_distribution_v1
with (security_invoker = true) as
select setting_code, contact_context, contact_label,
  sum(recorded_injuries)::bigint as recorded_injuries,
  sum(time_loss_injuries)::bigint as time_loss_injuries
from analysis.urc_2024_25_team_contact_distribution_v1
group by setting_code, contact_context, contact_label;

create view analysis.urc_2024_25_league_monthly_v1
with (security_invoker = true) as
select month_start,
  sum(recorded_injuries)::bigint as recorded_injuries,
  sum(time_loss_injuries)::bigint as time_loss_injuries,
  sum(days_lost)::numeric as days_lost,
  sum(exposure_hours)::numeric as exposure_hours,
  sum(distance_km)::numeric as distance_km,
  sum(recorded_injuries)::numeric * 1000 /
    nullif(sum(exposure_hours), 0) as overall_incidence_per_1000h,
  sum(time_loss_injuries)::numeric * 1000 /
    nullif(sum(exposure_hours), 0) as incidence_per_1000h,
  sum(days_lost)::numeric * 1000 / nullif(sum(exposure_hours), 0)
    as burden_per_1000h
from analysis.urc_2024_25_team_monthly_v1
group by month_start;

create materialized view analysis.urc_2024_25_team_dashboard_candidate_v1 as
with predecessor as (
  select p.*
  from reporting.dashboard_bundle_team_payloads_v1 p
  where p.bundle_release_id =
    '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid
), metrics as (
  select m.*, p.team_release_id, p.dashboard_payload
  from analysis.urc_2024_25_team_injury_metrics_v1 m
  join predecessor p using (team_key, curated_build_id)
)
select m.team_key, m.season, m.team_release_id, m.curated_build_id,
  'v5'::text as analysis_version,
  'reporting_classification_2024-25_2026-08-27_v1'::text
    as classification_view_version,
  'analysis_window_2024-25_2026-07-25_v1'::text as cohort_view_version,
  cohort.cohort_evidence_sha256,
  '0f7707e9b905ce1c604beeb2261ac18df880af9942de5093e2a564589e08e833'::text
    as classification_evidence_sha256,
  m.dashboard_payload || jsonb_build_object(
      'method', jsonb_build_array(
        'Overall incidence includes all eligible injury records; TL incidence includes final Time Loss injuries, including open or ongoing cases with null duration. Both use pooled exposure hours x 1,000.',
        'Severity mean, severity median and burden use known-duration Time Loss injuries only; null-duration Time Loss contributes no days until duration is known.',
        'Explicit Medical Attention and zero-day cases are closed Medical Attention on Date Injured and are excluded from Time Loss, incidence and burden.',
        'Unclassified eligible injuries count as recorded injuries only and are excluded from Time Loss, Medical Attention, severity, burden and dashboard unknown categories.',
        'Monthly assignment uses Date Injured only; undated eligible injuries remain in season totals and are excluded from monthly series.',
        'Diagnosis metrics use reviewed specific-diagnosis groups for injuries only; illnesses are excluded.',
        'IOC-aligned body-location and tissue/pathology categories remain separate accepted mappings.',
        'Exposure and rate calculations retain full stored precision; display formatting may round hours.'
      ),
      'limitations', jsonb_build_array(
        'Open or ongoing Time Loss cases are counted for incidence but cannot contribute severity or burden until duration is known.',
        'Medical Attention and zero-day cases are recorded and closed on Date Injured, but never contribute to Time Loss, incidence or burden.',
        'Unclassified eligible cases are recorded only; no Time Loss, Medical Attention, severity, burden or front-facing unknown category is assigned.',
        'Only dated cases are plotted monthly from Date Injured; undated cases remain season totals only.',
        'The immutable reporting window defines numerator and denominator eligibility.',
        'Historical exposure state is retained; correction overlays do not mutate curated rows.',
        'Unknown-setting injuries are included in all-setting metrics but have no setting-specific rate.',
        'Specific diagnoses use reviewed groups; unresolved injury diagnoses remain internal unknown values and are not shown as named diagnoses.'
      ),
      'headline', jsonb_build_array(
        jsonb_build_object(
          'key', 'recorded_injuries', 'label', 'Recorded injuries',
          'value', m.recorded_injuries, 'unit', 'injuries',
          'formula', 'count(final classified eligible injury rows, including undated)'
        ),
        jsonb_build_object(
          'key', 'time_loss_injuries', 'label', 'Time-loss injuries',
          'value', m.time_loss_injuries, 'unit', 'injuries',
          'formula', 'count(final classification = Time Loss)'
        ),
        jsonb_build_object(
          'key', 'overall_incidence_per_1000h', 'label', 'Overall incidence',
          'value', m.recorded_injuries::numeric * 1000 /
            nullif((m.dashboard_payload -> 'coverage' ->> 'hours')::numeric, 0),
          'unit', 'per 1,000 player-hours',
          'numerator', m.recorded_injuries,
          'denominator', (m.dashboard_payload -> 'coverage' ->> 'hours')::numeric,
          'formula', 'pooled recorded injuries / pooled exposure hours * 1000'
        ),
        jsonb_build_object(
          'key', 'incidence_per_1000h', 'label', 'Incidence',
          'value', m.time_loss_injuries::numeric * 1000 /
            nullif((m.dashboard_payload -> 'coverage' ->> 'hours')::numeric, 0),
          'unit', 'per 1,000 player-hours',
          'numerator', m.time_loss_injuries,
          'denominator', (m.dashboard_payload -> 'coverage' ->> 'hours')::numeric,
          'formula', 'pooled final Time Loss injuries / pooled exposure hours * 1000'
        ),
        jsonb_build_object(
          'key', 'severity_mean_days', 'label', 'Mean severity',
          'value', m.mean_severity_days, 'unit', 'days lost per injury',
          'numerator', m.days_lost,
          'denominator', m.known_duration_time_loss_injuries,
          'formula', 'known-duration Time Loss days lost / known-duration Time Loss injuries'
        ),
        jsonb_build_object(
          'key', 'severity_median_days', 'label', 'Median severity',
          'value', m.median_severity_days, 'unit', 'days lost per injury',
          'denominator', m.known_duration_time_loss_injuries,
          'formula', 'median known-duration Time Loss days lost'
        ),
        jsonb_build_object(
          'key', 'burden_per_1000h', 'label', 'Burden',
          'value', m.days_lost::numeric * 1000 /
            nullif((m.dashboard_payload -> 'coverage' ->> 'hours')::numeric, 0),
          'unit', 'days lost per 1,000 player-hours',
          'numerator', m.days_lost,
          'denominator', (m.dashboard_payload -> 'coverage' ->> 'hours')::numeric,
          'formula', 'known-duration Time Loss days lost / pooled exposure hours * 1000'
        )
      ),
      'setting_split', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', x.setting_code, 'label', initcap(x.setting_code),
          'recorded_injuries', x.recorded_injuries,
          'time_loss_injuries', x.time_loss_injuries,
          'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
          'overall_incidence_per_1000h', x.overall_incidence_per_1000h,
          'incidence_per_1000h', x.incidence_per_1000h,
          'burden_per_1000h', x.burden_per_1000h,
          'mean_severity_days', x.mean_severity_days,
          'known_duration_time_loss_injuries',
            x.known_duration_time_loss_injuries
        ) order by x.setting_code)
        from analysis.urc_2024_25_team_setting_metrics_v1 x
        where x.team_key = m.team_key and x.curated_build_id = m.curated_build_id
      ), '[]'::jsonb),
      'setting_metrics', coalesce((
        select jsonb_agg(jsonb_build_object(
          'setting', x.setting_code, 'label', initcap(x.setting_code),
          'recorded_injuries', x.recorded_injuries,
          'time_loss_injuries', x.time_loss_injuries,
          'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
          'overall_incidence_per_1000h', x.overall_incidence_per_1000h,
          'incidence_per_1000h', x.incidence_per_1000h,
          'burden_per_1000h', x.burden_per_1000h,
          'mean_severity_days', x.mean_severity_days,
          'known_duration_time_loss_injuries',
            x.known_duration_time_loss_injuries
        ) order by x.setting_code)
        from analysis.urc_2024_25_team_setting_metrics_v1 x
        where x.team_key = m.team_key and x.curated_build_id = m.curated_build_id
      ), '[]'::jsonb),
      'monthly', coalesce((
        select jsonb_agg(
          x.source_item || jsonb_build_object(
            'recorded_injuries', x.recorded_injuries,
            'time_loss_injuries', x.time_loss_injuries,
            'days_lost', x.days_lost,
            'overall_incidence_per_1000h', x.overall_incidence_per_1000h,
            'incidence_per_1000h', x.incidence_per_1000h,
            'burden_per_1000h', x.burden_per_1000h
          ) order by x.month_start
        )
        from analysis.urc_2024_25_team_monthly_v1 x
        where x.team_key = m.team_key and x.curated_build_id = m.curated_build_id
      ), '[]'::jsonb),
      'body_locations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', x.code, 'label', x.label,
          'time_loss_injuries', x.time_loss_injuries,
          'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
          'incidence_per_1000h', x.incidence_per_1000h,
          'burden_per_1000h', x.burden_per_1000h,
          'mean_severity_days', x.mean_severity_days
        ) order by x.time_loss_injuries desc, x.days_lost desc, x.code)
        from analysis.urc_2024_25_team_profiles_v1 x
        where x.team_key = m.team_key and x.curated_build_id = m.curated_build_id
          and x.dimension = 'body_location'
      ), '[]'::jsonb),
      'injury_types', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', x.code, 'label', x.label,
          'time_loss_injuries', x.time_loss_injuries,
          'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
          'incidence_per_1000h', x.incidence_per_1000h,
          'burden_per_1000h', x.burden_per_1000h,
          'mean_severity_days', x.mean_severity_days
        ) order by x.time_loss_injuries desc, x.days_lost desc, x.code)
        from analysis.urc_2024_25_team_profiles_v1 x
        where x.team_key = m.team_key and x.curated_build_id = m.curated_build_id
          and x.dimension = 'injury_type'
      ), '[]'::jsonb),
      'injury_profiles', coalesce((
        select jsonb_agg(jsonb_build_object(
          'dimension', x.dimension, 'code', x.code, 'label', x.label,
          'setting', 'all', 'time_loss_injuries', x.time_loss_injuries,
          'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
          'incidence_per_1000h', x.incidence_per_1000h,
          'burden_per_1000h', x.burden_per_1000h,
          'mean_severity_days', x.mean_severity_days
        ) order by x.dimension, x.time_loss_injuries desc, x.days_lost desc, x.code)
        from analysis.urc_2024_25_team_profiles_v1 x
        where x.team_key = m.team_key and x.curated_build_id = m.curated_build_id
      ), '[]'::jsonb),
      'severity_distribution', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', x.severity_code, 'label', x.severity_label,
          'recorded_injuries', x.recorded_injuries,
          'time_loss_injuries', x.time_loss_injuries,
          'days_lost', x.days_lost
        ) order by x.band_order)
        from analysis.urc_2024_25_team_severity_distribution_v1 x
        where x.team_key = m.team_key and x.curated_build_id = m.curated_build_id
      ), '[]'::jsonb),
      'contact_distribution', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', x.contact_context, 'label', x.contact_label,
          'setting', x.setting_code,
          'recorded_injuries', x.recorded_injuries,
          'time_loss_injuries', x.time_loss_injuries
        ) order by x.setting_code, x.contact_context)
        from analysis.urc_2024_25_team_contact_distribution_v1 x
        where x.team_key = m.team_key and x.curated_build_id = m.curated_build_id
      ), '[]'::jsonb)
    ) as dashboard,
  '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid as predecessor_release_id,
  '93fdd34371aac097c4364d3c64c32135fba7e3f235747b9daeb285335b330a8f'::text
    as predecessor_canonical_bundle_sha256,
  '47853342b5f999810bdb151a3e4757a982bbaf3d6b49f002ee19f53e0378cc56'::text
    as predecessor_league_payload_sha256,
  '1563ac044888003751c0294df242b4b83fec811be0779d9a4c3d65ac6163234e'::text
    as predecessor_team_payload_set_sha256
from metrics m
join analysis.accepted_analysis_window_cohort_rules_v5 cohort
  on cohort.season = m.season
 and cohort.cohort_view_version = 'analysis_window_2024-25_2026-07-25_v1';

create materialized view analysis.urc_2024_25_league_dashboard_candidate_v1 as
with predecessor as (
  select p.*
  from reporting.dashboard_bundle_league_payloads_v1 p
  where p.release_id =
    '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid
), m as (
  select * from analysis.urc_2024_25_league_metrics_v1
)
select
  '2024-25'::text as season,
  'URC Overall'::text as team,
  'v5'::text as analysis_version,
  'reporting_classification_2024-25_2026-08-27_v1'::text
    as classification_view_version,
  'analysis_window_2024-25_2026-07-25_v1'::text as cohort_view_version,
  cohort.cohort_evidence_sha256,
  '0f7707e9b905ce1c604beeb2261ac18df880af9942de5093e2a564589e08e833'::text
    as classification_evidence_sha256,
  predecessor.dashboard_payload || jsonb_build_object(
      'method', jsonb_build_array(
        'Overall incidence includes all eligible injury records; TL incidence includes final Time Loss injuries, including open or ongoing cases with null duration. Both use pooled exposure hours x 1,000.',
        'Severity mean, severity median and burden use known-duration Time Loss injuries only; null-duration Time Loss contributes no days until duration is known.',
        'Explicit Medical Attention and zero-day cases are closed Medical Attention on Date Injured and are excluded from Time Loss, incidence and burden.',
        'Unclassified eligible injuries count as recorded injuries only and are excluded from Time Loss, Medical Attention, severity, burden and dashboard unknown categories.',
        'Monthly assignment uses Date Injured only; undated eligible injuries remain in season totals and are excluded from monthly series.',
        'Diagnosis metrics use reviewed specific-diagnosis groups for injuries only; illnesses are excluded.',
        'IOC-aligned body-location and tissue/pathology categories remain separate accepted mappings.',
        'Exposure and rate calculations retain full stored precision; display formatting may round hours.'
      ),
      'limitations', jsonb_build_array(
        'Open or ongoing Time Loss cases are counted for incidence but cannot contribute severity or burden until duration is known.',
        'Medical Attention and zero-day cases are recorded and closed on Date Injured, but never contribute to Time Loss, incidence or burden.',
        'Unclassified eligible cases are recorded only; no Time Loss, Medical Attention, severity, burden or front-facing unknown category is assigned.',
        'Only dated cases are plotted monthly from Date Injured; undated cases remain season totals only.',
        'The immutable reporting window defines numerator and denominator eligibility.',
        'Historical exposure state is retained; correction overlays do not mutate curated rows.',
        'Unknown-setting injuries are included in all-setting metrics but have no setting-specific rate.',
        'Specific diagnoses use reviewed groups; unresolved injury diagnoses remain internal unknown values and are not shown as named diagnoses.'
      ),
      'headline', jsonb_build_array(
        jsonb_build_object(
          'key', 'recorded_injuries', 'label', 'Recorded injuries',
          'value', m.recorded_injuries, 'unit', 'injuries',
          'formula', 'count(final classified eligible injury rows, including undated)'
        ),
        jsonb_build_object(
          'key', 'time_loss_injuries', 'label', 'Time-loss injuries',
          'value', m.time_loss_injuries, 'unit', 'injuries',
          'formula', 'count(final classification = Time Loss)'
        ),
        jsonb_build_object(
          'key', 'overall_incidence_per_1000h', 'label', 'Overall incidence',
          'value', m.recorded_injuries::numeric * 1000 /
            nullif((predecessor.dashboard_payload -> 'coverage' ->> 'hours')::numeric, 0),
          'unit', 'per 1,000 player-hours',
          'numerator', m.recorded_injuries,
          'denominator', (predecessor.dashboard_payload -> 'coverage' ->> 'hours')::numeric,
          'formula', 'pooled recorded injuries / pooled exposure hours * 1000'
        ),
        jsonb_build_object(
          'key', 'incidence_per_1000h', 'label', 'Incidence',
          'value', m.time_loss_injuries::numeric * 1000 /
            nullif((predecessor.dashboard_payload -> 'coverage' ->> 'hours')::numeric, 0),
          'unit', 'per 1,000 player-hours',
          'numerator', m.time_loss_injuries,
          'denominator', (predecessor.dashboard_payload -> 'coverage' ->> 'hours')::numeric,
          'formula', 'pooled final Time Loss injuries / pooled exposure hours * 1000'
        ),
        jsonb_build_object(
          'key', 'severity_mean_days', 'label', 'Mean severity',
          'value', m.mean_severity_days, 'unit', 'days lost per injury',
          'numerator', m.days_lost,
          'denominator', m.known_duration_time_loss_injuries,
          'formula', 'known-duration Time Loss days lost / known-duration Time Loss injuries'
        ),
        jsonb_build_object(
          'key', 'severity_median_days', 'label', 'Median severity',
          'value', m.median_severity_days, 'unit', 'days lost per injury',
          'denominator', m.known_duration_time_loss_injuries,
          'formula', 'median known-duration Time Loss days lost'
        ),
        jsonb_build_object(
          'key', 'burden_per_1000h', 'label', 'Burden',
          'value', m.days_lost::numeric * 1000 /
            nullif((predecessor.dashboard_payload -> 'coverage' ->> 'hours')::numeric, 0),
          'unit', 'days lost per 1,000 player-hours',
          'numerator', m.days_lost,
          'denominator', (predecessor.dashboard_payload -> 'coverage' ->> 'hours')::numeric,
          'formula', 'known-duration Time Loss days lost / pooled exposure hours * 1000'
        )
      ),
      'setting_split', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', x.setting_code, 'label', initcap(x.setting_code),
          'recorded_injuries', x.recorded_injuries,
          'time_loss_injuries', x.time_loss_injuries,
          'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
          'overall_incidence_per_1000h', x.overall_incidence_per_1000h,
          'incidence_per_1000h', x.incidence_per_1000h,
          'burden_per_1000h', x.burden_per_1000h,
          'mean_severity_days', x.mean_severity_days
        ) order by x.setting_code)
        from analysis.urc_2024_25_league_setting_metrics_v1 x
      ), '[]'::jsonb),
      'setting_metrics', coalesce((
        select jsonb_agg(jsonb_build_object(
          'setting', x.setting_code, 'label', initcap(x.setting_code),
          'recorded_injuries', x.recorded_injuries,
          'time_loss_injuries', x.time_loss_injuries,
          'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
          'overall_incidence_per_1000h', x.overall_incidence_per_1000h,
          'incidence_per_1000h', x.incidence_per_1000h,
          'burden_per_1000h', x.burden_per_1000h,
          'mean_severity_days', x.mean_severity_days
        ) order by x.setting_code)
        from analysis.urc_2024_25_league_setting_metrics_v1 x
      ), '[]'::jsonb),
      'monthly', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'month', to_char(x.month_start, 'Mon YYYY'),
            'recorded_injuries', x.recorded_injuries,
            'time_loss_injuries', x.time_loss_injuries,
            'days_lost', x.days_lost,
            'exposure_hours', x.exposure_hours,
            'distance_km', x.distance_km,
            'overall_incidence_per_1000h', x.overall_incidence_per_1000h,
            'incidence_per_1000h', x.incidence_per_1000h,
            'burden_per_1000h', x.burden_per_1000h
          ) order by x.month_start
        )
        from analysis.urc_2024_25_league_monthly_v1 x
      ), '[]'::jsonb),
      'body_locations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', x.code, 'label', x.label,
          'time_loss_injuries', x.time_loss_injuries,
          'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
          'incidence_per_1000h', x.incidence_per_1000h,
          'burden_per_1000h', x.burden_per_1000h,
          'mean_severity_days', x.mean_severity_days
        ) order by x.time_loss_injuries desc, x.days_lost desc, x.code)
        from analysis.urc_2024_25_league_profiles_v1 x
        where x.dimension = 'body_location'
      ), '[]'::jsonb),
      'injury_types', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', x.code, 'label', x.label,
          'time_loss_injuries', x.time_loss_injuries,
          'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
          'incidence_per_1000h', x.incidence_per_1000h,
          'burden_per_1000h', x.burden_per_1000h,
          'mean_severity_days', x.mean_severity_days
        ) order by x.time_loss_injuries desc, x.days_lost desc, x.code)
        from analysis.urc_2024_25_league_profiles_v1 x
        where x.dimension = 'injury_type'
      ), '[]'::jsonb),
      'injury_profiles', coalesce((
        select jsonb_agg(jsonb_build_object(
          'dimension', x.dimension, 'code', x.code, 'label', x.label,
          'setting', 'all', 'time_loss_injuries', x.time_loss_injuries,
          'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
          'incidence_per_1000h', x.incidence_per_1000h,
          'burden_per_1000h', x.burden_per_1000h,
          'mean_severity_days', x.mean_severity_days
        ) order by x.dimension, x.time_loss_injuries desc, x.days_lost desc, x.code)
        from analysis.urc_2024_25_league_profiles_v1 x
      ), '[]'::jsonb),
      'severity_distribution', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', x.severity_code, 'label', x.severity_label,
          'recorded_injuries', x.recorded_injuries,
          'time_loss_injuries', x.time_loss_injuries,
          'days_lost', x.days_lost
        ) order by x.band_order)
        from analysis.urc_2024_25_league_severity_distribution_v1 x
      ), '[]'::jsonb),
      'contact_distribution', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', x.contact_context, 'label', x.contact_label,
          'setting', x.setting_code,
          'recorded_injuries', x.recorded_injuries,
          'time_loss_injuries', x.time_loss_injuries
        ) order by x.setting_code, x.contact_context)
        from analysis.urc_2024_25_league_contact_distribution_v1 x
      ), '[]'::jsonb)
    ) as dashboard,
  '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid as predecessor_release_id,
  '93fdd34371aac097c4364d3c64c32135fba7e3f235747b9daeb285335b330a8f'::text
    as predecessor_canonical_bundle_sha256,
  '47853342b5f999810bdb151a3e4757a982bbaf3d6b49f002ee19f53e0378cc56'::text
    as predecessor_league_payload_sha256,
  '1563ac044888003751c0294df242b4b83fec811be0779d9a4c3d65ac6163234e'::text
    as predecessor_team_payload_set_sha256
from predecessor
cross join m
join analysis.accepted_analysis_window_cohort_rules_v5 cohort
  on cohort.season = m.season
 and cohort.cohort_view_version = 'analysis_window_2024-25_2026-07-25_v1';

create view analysis.urc_2024_25_classification_successor_candidates_v1
with (security_invoker = true) as
select 'team'::text as candidate_kind, team_key, season, team_release_id,
  curated_build_id, analysis_version, classification_view_version,
  cohort_view_version, classification_evidence_sha256, cohort_evidence_sha256,
  dashboard
from analysis.urc_2024_25_team_dashboard_candidate_v1
union all
select 'league', team, season, null::uuid, null::uuid, analysis_version,
  classification_view_version, cohort_view_version,
  classification_evidence_sha256, cohort_evidence_sha256, dashboard
from analysis.urc_2024_25_league_dashboard_candidate_v1;

create or replace view analysis.team_dashboard_release_candidates_analysis_window_v5
with (security_invoker = true) as
select team_key, season, team_release_id, curated_build_id, analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.urc_2024_25_team_dashboard_candidate_v1;

create or replace view analysis.league_dashboard_release_candidates_analysis_window_v5
with (security_invoker = true) as
select season, analysis_version, classification_view_version,
  classification_evidence_sha256, cohort_view_version,
  cohort_evidence_sha256, dashboard
from analysis.urc_2024_25_league_dashboard_candidate_v1;

create function analysis.assert_urc_2024_25_classification_successor_v1()
returns void
language plpgsql
set search_path = pg_catalog, analysis, audit, reporting
as $$
declare
  evidence analysis.urc_2024_25_classification_evidence_v1%rowtype;
  old_recorded bigint;
  old_time_loss bigint;
  old_days numeric;
  new_recorded bigint;
  new_time_loss bigint;
  new_days numeric;
  adjudicated_time_loss bigint;
  adjudicated_null_duration_time_loss bigint;
  adjudicated_medical_attention bigint;
  adjudicated_unclassified bigint;
  source_reported_null_time_loss bigint;
  dated_recorded bigint;
  dated_time_loss bigint;
  undated_recorded bigint;
  undated_time_loss bigint;
  monthly_recorded bigint;
  monthly_time_loss bigint;
  team_recorded bigint;
  team_time_loss bigint;
  team_days numeric;
begin
  select * into evidence from analysis.urc_2024_25_classification_evidence_v1;
  if evidence.adjudication_rows <> 32
     or evidence.time_loss_rows <> 15
     or evidence.medical_attention_rows <> 1
     or evidence.unclassified_rows <> 16
     or evidence.adjudication_manifest_sha256 <>
       'cd5bed8cd5a98a6b5290194371fb92f01020ed8020ff3ddb859251741f349835'
     or evidence.specific_diagnosis_evidence_sha256 <>
       'a43ba36a7f67ecd208112d702bcc058de947b00d721399e9e0ad26d23f3ac167'
     or evidence.specific_diagnosis_mapping_rows_sha256 <>
       '8c26ddfbabef220a5ddc8e957b6ef143f0eeb46342d4e9634edf720162e5b7c7'
     or evidence.specific_diagnosis_injury_rows <> 1660
     or evidence.specific_diagnosis_illness_rows_excluded <> 392
     or (select count(*) from audit.urc_2024_25_specific_diagnosis_mappings_v1) <> 1660
     or (select count(distinct diagnosis_group_code)
         from audit.urc_2024_25_specific_diagnosis_mappings_v1) <> 274
     or audit.row_correction_set_hash_v3('2024-25', null) <>
       'b83d9ab7cf68d8c1b2239ebcd49cb9de882d91b4db1174d80b3fbcdf7baea051'
  then
    raise exception 'classification evidence failed closed';
  end if;

  if (select count(*)
      from lineage.baselines baseline
      where baseline.season = '2024-25'
        and baseline.master_json_sha256 =
          '15b9af0da05aa57698487f4c8ebacf9923cec4e66846ac00b76fa3c2b75f2f63') <> 1
     or (select count(*)
         from audit.urc_2024_25_classification_adjudications_v1 adjudication
         join lineage.master_rows master
           on master.season = adjudication.season
          and master.source_row = adjudication.source_row
         where adjudication.season = '2024-25') <> 32
     or exists (
         select 1
         from audit.urc_2024_25_classification_adjudications_v1 adjudication
         join lineage.master_rows master
           on master.season = adjudication.season
          and master.source_row = adjudication.source_row
         where adjudication.season = '2024-25'
           and adjudication.source_value <>
             coalesce(master.row_values ->> 'TimeLoss vs Medical Attention', '')
       )
  then
    raise exception 'classification evidence is not bound to the immutable master baseline';
  end if;

  if (select count(*) from analysis.row_correction_member_releases_v1
      where season = '2024-25'
        and predecessor_bundle_id =
          '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid) <> 16
  then
    raise exception 'exact predecessor 16-team membership is absent';
  end if;

  if exists (
    select 1
    from analysis.urc_2024_25_final_injury_classification_v1 f
    join audit.urc_2024_25_specific_diagnosis_mappings_v1 m
      on m.season = f.season
     and m.source_row = f.source_row
    where f.canonical_problem_type <> 'injury'
  )
     or (select count(*)
         from analysis.urc_2024_25_final_injury_classification_v1 f
         left join audit.urc_2024_25_specific_diagnosis_mappings_v1 m
           on m.season = f.season
          and m.source_row = f.source_row
         where f.canonical_problem_type = 'injury'
           and m.source_row is null) <> 4
  then
    raise exception 'specific diagnosis mapping must be injury-only with four unknown fallbacks';
  end if;

  if (select count(*) from analysis.urc_2024_25_team_dashboard_candidate_v1) <> 16
     or (select count(*) from analysis.urc_2024_25_league_dashboard_candidate_v1) <> 1
  then
    raise exception 'successor candidate is not atomic 16-team plus league';
  end if;

  if exists (
    select 1
    from (
      select dashboard
      from analysis.urc_2024_25_team_dashboard_candidate_v1
      union all
      select dashboard
      from analysis.urc_2024_25_league_dashboard_candidate_v1
    ) candidates
    where candidates.dashboard -> 'method' is distinct from jsonb_build_array(
        'Overall incidence includes all eligible injury records; TL incidence includes final Time Loss injuries, including open or ongoing cases with null duration. Both use pooled exposure hours x 1,000.',
        'Severity mean, severity median and burden use known-duration Time Loss injuries only; null-duration Time Loss contributes no days until duration is known.',
        'Explicit Medical Attention and zero-day cases are closed Medical Attention on Date Injured and are excluded from Time Loss, incidence and burden.',
        'Unclassified eligible injuries count as recorded injuries only and are excluded from Time Loss, Medical Attention, severity, burden and dashboard unknown categories.',
        'Monthly assignment uses Date Injured only; undated eligible injuries remain in season totals and are excluded from monthly series.',
        'Diagnosis metrics use reviewed specific-diagnosis groups for injuries only; illnesses are excluded.',
        'IOC-aligned body-location and tissue/pathology categories remain separate accepted mappings.',
        'Exposure and rate calculations retain full stored precision; display formatting may round hours.'
      )
      or candidates.dashboard -> 'limitations' is distinct from jsonb_build_array(
        'Open or ongoing Time Loss cases are counted for incidence but cannot contribute severity or burden until duration is known.',
        'Medical Attention and zero-day cases are recorded and closed on Date Injured, but never contribute to Time Loss, incidence or burden.',
        'Unclassified eligible cases are recorded only; no Time Loss, Medical Attention, severity, burden or front-facing unknown category is assigned.',
        'Only dated cases are plotted monthly from Date Injured; undated cases remain season totals only.',
        'The immutable reporting window defines numerator and denominator eligibility.',
        'Historical exposure state is retained; correction overlays do not mutate curated rows.',
        'Unknown-setting injuries are included in all-setting metrics but have no setting-specific rate.',
        'Specific diagnoses use reviewed groups; unresolved injury diagnoses remain internal unknown values and are not shown as named diagnoses.'
      )
      or reporting.canonical_jsonb_sha256_v1(candidates.dashboard -> 'method') is distinct from
        '9bd4ff3c60fb1aa33e3f4d1d1c5ff35f83bbd6cbd777aca90b6fbd3bc980de7c'
      or reporting.canonical_jsonb_sha256_v1(candidates.dashboard -> 'limitations') is distinct from
        'd8b32c5dddb9f740d238b44e4c40d099ed671ccc58bcdc95a5310471c78b75f9'
  ) then
    raise exception 'successor method/limitations disclosure content or hash failed';
  end if;

  select
    count(*) filter (where a.final_classification = 'Time Loss'),
    count(*) filter (where a.final_classification = 'Medical Attention'),
    count(*) filter (where a.final_classification = 'unclassified')
  into adjudicated_time_loss, adjudicated_medical_attention,
    adjudicated_unclassified
  from audit.urc_2024_25_classification_adjudications_v1 a
  join analysis.urc_2024_25_final_injury_classification_v1 f
    on f.season = a.season
   and f.source_row = a.source_row
  where a.season = '2024-25';
  if adjudicated_time_loss <> 15
     or adjudicated_medical_attention <> 1
     or adjudicated_unclassified <> 16
  then
    raise exception 'classification rows failed exact 15/1/16 adjudication gate';
  end if;

  if (select count(*) from analysis.urc_2024_25_final_injury_classification_v1
      where final_classification = 'Time Loss') <> 913
     or (select count(*) from analysis.urc_2024_25_final_injury_classification_v1
         where final_classification = 'Medical Attention') <> 731
     or (select count(*) from analysis.urc_2024_25_final_injury_classification_v1
         where final_classification = 'unclassified') <> 18
  then
    raise exception 'final classification did not reconcile to 913 Time Loss, 731 Medical Attention and 18 unclassified';
  end if;

  select count(*)
  into source_reported_null_time_loss
  from analysis.urc_2024_25_final_injury_classification_v1 f
  where f.source_classification_value in
      ('time loss', 'time_loss', 'timeloss', 'true')
    and f.days_lost is null
    and not exists (
      select 1
      from audit.urc_2024_25_classification_adjudications_v1 a
      where a.season = f.season
      and a.source_row = f.source_row
    );

  select count(*)
  into adjudicated_null_duration_time_loss
  from audit.urc_2024_25_classification_adjudications_v1 a
  join analysis.urc_2024_25_final_injury_classification_v1 f
    on f.season = a.season
   and f.source_row = a.source_row
  where a.season = '2024-25'
    and a.final_classification = 'Time Loss'
    and f.days_lost is null;
  if adjudicated_null_duration_time_loss <> 15 then
    raise exception 'adjudicated null-duration Time Loss contribution is not exactly 15';
  end if;

  select
    (p.dashboard_payload -> 'headline' -> 0 ->> 'value')::bigint,
    (p.dashboard_payload -> 'headline' -> 1 ->> 'value')::bigint,
    (select (x.item ->> 'numerator')::numeric
       from jsonb_array_elements(p.dashboard_payload -> 'headline') x(item)
       where x.item ->> 'key' = 'severity_mean_days')
  into old_recorded, old_time_loss, old_days
  from reporting.dashboard_bundle_league_payloads_v1 p
  where p.release_id =
    '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid;

  select
    (dashboard -> 'headline' -> 0 ->> 'value')::bigint,
    (dashboard -> 'headline' -> 1 ->> 'value')::bigint,
    (select (x.item ->> 'numerator')::numeric
       from jsonb_array_elements(dashboard -> 'headline') x(item)
       where x.item ->> 'key' = 'severity_mean_days')
  into new_recorded, new_time_loss, new_days
  from analysis.urc_2024_25_league_dashboard_candidate_v1;

  if new_recorded <> old_recorded
     or new_days <> old_days
     or old_recorded <> 1662
     or old_time_loss <> 787
     or old_days <> 17575
     or new_recorded <> 1662
     or new_days <> 17575
     or source_reported_null_time_loss <> 111
     or new_time_loss <> 913
     or new_time_loss <> old_time_loss + source_reported_null_time_loss
       + adjudicated_null_duration_time_loss
  then
    raise exception 'successor did not reconcile 1662/787/17575 plus 111 source-reported and 15 adjudicated null-duration Time Loss cases to 1662/913/17575';
  end if;

  select coalesce(sum(recorded_injuries), 0),
    coalesce(sum(time_loss_injuries), 0),
    coalesce(sum(days_lost), 0)
  into team_recorded, team_time_loss, team_days
  from analysis.urc_2024_25_team_injury_metrics_v1;
  if team_recorded <> new_recorded
     or team_time_loss <> new_time_loss
     or team_days <> new_days
  then
    raise exception '16 team headline metrics do not reconcile to the league candidate';
  end if;

  if (select coalesce(sum(time_loss_injuries), 0)
      from analysis.urc_2024_25_league_profiles_v1
      where dimension = 'diagnosis') <>
     (select count(*)
      from analysis.urc_2024_25_final_injury_classification_v1
      where canonical_problem_type = 'injury'
        and final_classification = 'Time Loss')
  then
    raise exception 'specific diagnosis Time Loss total does not reconcile to injury facts';
  end if;

  if (select count(*)
      from audit.urc_2024_25_classification_adjudications_v1 a
      join analysis.urc_2024_25_final_injury_classification_v1 f
        on f.season = a.season
       and f.source_row = a.source_row
      where a.final_classification = 'Time Loss'
        and f.days_lost is null
        and f.closure_status = 'Open/Ongoing') <> 15
  then
    raise exception 'adjudicated null-duration Time Loss is not open/ongoing';
  end if;

  if exists (
    select 1 from analysis.urc_2024_25_final_injury_classification_v1 f
    where f.source_classification_value in
        ('time loss', 'time_loss', 'timeloss', 'true')
      and f.days_lost is null
      and (f.final_classification <> 'Time Loss'
        or not f.is_time_loss
        or f.is_medical_attention
        or f.closure_status <> 'Open/Ongoing')
  ) then
    raise exception 'source-reported null-duration Time Loss is not open/ongoing';
  end if;

  if exists (
    select 1 from analysis.urc_2024_25_final_injury_classification_v1
    where final_classification = 'Medical Attention'
      and (closure_status <> 'Closed' or date_injured is null)
  ) then
    raise exception 'Medical Attention rows must be closed on Date Injured';
  end if;

  if exists (
    select 1 from analysis.urc_2024_25_final_injury_classification_v1
    where final_classification = 'Medical Attention'
      and (not is_medical_attention or is_time_loss)
  ) then
    raise exception 'Medical Attention leaked into Time Loss';
  end if;

  if exists (
    select 1 from analysis.urc_2024_25_final_injury_classification_v1
    where final_classification = 'unclassified'
      and (is_time_loss or is_medical_attention)
  ) then
    raise exception 'unclassified rows leaked into classified metrics';
  end if;

  if (select count(*) from analysis.urc_2024_25_final_injury_classification_v1
      where final_classification = 'Time Loss'
        and duration_usable) <>
     (select known_duration_time_loss_injuries
      from analysis.urc_2024_25_league_metrics_v1)
     or (select known_duration_time_loss_injuries
         from analysis.urc_2024_25_league_metrics_v1) <> 787
  then
    raise exception 'severity denominator is not known-duration Time Loss only';
  end if;

  select count(*) filter (where date_injured is not null),
    count(*) filter (where date_injured is not null
      and final_classification = 'Time Loss'),
    count(*) filter (where date_injured is null),
    count(*) filter (where date_injured is null
      and final_classification = 'Time Loss')
  into dated_recorded, dated_time_loss, undated_recorded, undated_time_loss
  from analysis.urc_2024_25_final_injury_classification_v1;

  select sum(recorded_injuries), sum(time_loss_injuries)
  into monthly_recorded, monthly_time_loss
  from analysis.urc_2024_25_league_monthly_v1;

  if dated_recorded <> monthly_recorded
     or dated_time_loss <> monthly_time_loss
     or dated_recorded <> 1656
     or dated_time_loss <> 912
     or undated_recorded <> 6
     or undated_time_loss <> 1
  then
    raise exception 'monthly Date Injured reconciliation failed';
  end if;

  if exists (
    select 1
    from analysis.urc_2024_25_team_dashboard_candidate_v1 candidate
    join reporting.dashboard_bundle_team_payloads_v1 predecessor
      on predecessor.bundle_release_id =
        '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid
     and predecessor.team_key = candidate.team_key
     and predecessor.curated_build_id = candidate.curated_build_id
    where (candidate.dashboard - array[
      'headline','setting_split','setting_metrics','monthly',
      'body_locations','injury_types','injury_profiles',
      'severity_distribution','contact_distribution','method','limitations'
    ]) <>
      (predecessor.dashboard_payload - array[
      'headline','setting_split','setting_metrics','monthly',
      'body_locations','injury_types','injury_profiles',
      'severity_distribution','contact_distribution','method','limitations'
    ])
  ) then
    raise exception 'predecessor non-injury payload keys changed';
  end if;

  if exists (
    select 1
    from analysis.urc_2024_25_team_dashboard_candidate_v1 candidate
    join reporting.dashboard_bundle_team_payloads_v1 predecessor
      on predecessor.bundle_release_id =
        '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid
     and predecessor.team_key = candidate.team_key
     and predecessor.curated_build_id = candidate.curated_build_id
    cross join lateral jsonb_array_elements(candidate.dashboard -> 'monthly')
      with ordinality candidate_month(item, ordinal)
    cross join lateral jsonb_array_elements(predecessor.dashboard_payload -> 'monthly')
      with ordinality predecessor_month(item, ordinal)
    where jsonb_array_length(candidate.dashboard -> 'monthly') <>
        jsonb_array_length(predecessor.dashboard_payload -> 'monthly')
      or (candidate_month.ordinal = predecessor_month.ordinal
        and ((candidate_month.item -> 'exposure_hours') is distinct from
            (predecessor_month.item -> 'exposure_hours')
          or candidate_month.item -> 'distance_km' is distinct from
            predecessor_month.item -> 'distance_km'))
  ) then
    raise exception 'monthly exposure precision changed';
  end if;
end;
$$;

revoke execute on function analysis.assert_urc_2024_25_classification_successor_v1()
  from public, anon, authenticated, web_reader;

do $$
begin
  perform analysis.assert_urc_2024_25_classification_successor_v1();
end;
$$;
