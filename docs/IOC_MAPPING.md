# IOC Injury Taxonomy Mapping

This file documents the controlled injury body-location and tissue/pathology taxonomy used by the URC V2 pipeline. It is the methodology-facing companion to the executable mapping in `pipeline/__main__.py` and the review export labels in `pipeline/export_filled_standardised.mjs`.

## Source Standard

Primary source: International Olympic Committee 2020 consensus statement on recording and reporting injury and illness epidemiology data in sport.

Reference link: https://journals.sagepub.com/doi/10.1177/2325967120902908

The IOC statement recommends aggregate injury reporting by body area and tissue/pathology type. It uses OSIICS and SMDCS codes as sports-medicine diagnostic systems, with initial codes representing body area and later codes representing tissue/pathology.

## Body Location Categories

These are the global body-location categories used across teams.

| Pipeline key | Review label | IOC/OSIICS body code | Notes |
|---|---|---:|---|
| `head` | Head | H | Includes face, brain/concussion, eyes, ears, teeth. |
| `neck` | Neck | N | Includes cervical spine. |
| `shoulder` | Shoulder | S | Includes clavicle, scapula, rotator cuff, biceps tendon origin. |
| `upper_arm` | Upper arm | U | Upper arm segment. |
| `elbow` | Elbow | E | Includes elbow ligaments and insertional biceps/triceps tendon. |
| `forearm` | Forearm | R | Includes nonarticular radial and ulnar injuries. |
| `wrist` | Wrist | W | Carpus/wrist. |
| `hand` | Hand | P | Includes finger and thumb. |
| `chest` | Chest | C | Includes sternum, ribs, breast, chest organs. |
| `thoracic_spine` | Thoracic spine | D | Thoracic spine and costovertebral joints. |
| `lumbosacral` | Lumbosacral | L | Includes lumbar spine, sacroiliac joints, sacrum, coccyx, buttocks. |
| `abdomen` | Abdomen | O | Below diaphragm and above inguinal canal. |
| `hip_groin` | Hip/Groin | G | Hip and anterior groin structures. |
| `thigh` | Thigh | T | Includes femur, hamstring, quadriceps, middistal adductors. |
| `knee` | Knee | K | Includes patella and patellar tendon. |
| `lower_leg` | Lower leg | Q | Includes calf and Achilles tendon. |
| `ankle` | Ankle | A | Includes syndesmosis, talocrural and subtalar joints. |
| `foot` | Foot | F | Includes toes, calcaneus, plantar fascia. |
| `unspecified` | Unspecified | Z | Unspecified body area. |
| `multiple` | Multiple | X | Single injury crossing two or more regions. |

Pipeline rule:

1. If `Orchard Code` is present, use its first character as the IOC/OSIICS body-area code.
2. If no usable code is present, map the source `Body Part` to the nearest IOC body area.
3. Preserve the original source value and record the field origin.

Current Munster fallback mappings from source `Body Part`:

| Munster source value | Pipeline key | Rationale |
|---|---|---|
| `Ankle` | `ankle` | Direct IOC body area. |
| `Buttock/pelvis` | `lumbosacral` | IOC lumbosacral includes buttocks and pelvic/sacroiliac area. |
| `Chest` | `chest` | Direct IOC body area. |
| `Elbow` | `elbow` | Direct IOC body area. |
| `Foot` | `foot` | Direct IOC body area. |
| `Head` | `head` | Direct IOC body area. |
| `Hip/Groin` | `hip_groin` | Direct IOC combined body area. |
| `Knee` | `knee` | Direct IOC body area. |
| `Lower Leg` | `lower_leg` | Direct IOC body area. |
| `Lumbar Spine` | `lumbosacral` | IOC lumbosacral includes lumbar spine. |
| `Neck` | `neck` | Direct IOC body area. |
| `Shoulder` | `shoulder` | Direct IOC body area. |
| `Thigh` | `thigh` | Direct IOC body area. |
| `Thoracic Spine` | `thoracic_spine` | Direct IOC body area. |
| `Trunk/Abdominal` | `abdomen` | Closest IOC body area for abdominal/trunk records. |
| `Wrist/Hand` | `unspecified` | Code-first mapping should split wrist vs hand where Orchard code is present; source fallback is unspecified because the source category is not a single IOC body area. |

## Injury Tissue/Pathology Categories

These are the global tissue/pathology categories used across teams.

| Pipeline key | Review label | Notes |
|---|---|---|
| `muscle_injury` | Muscle injury | Includes strain, tear, rupture, intramuscular tendon. |
| `muscle_contusion` | Muscle contusion | IOC category retained for future teams; Munster currently maps bruising/haematoma to superficial contusion unless code evidence supports muscle contusion. |
| `muscle_compartment_syndrome` | Muscle compartment syndrome | Retained for future teams. |
| `tendinopathy` | Tendinopathy | Nonrupture tendon/paratenon/bursa/fascia-related category. |
| `tendon_rupture` | Tendon rupture | Complete/full-thickness tendon rupture. |
| `brain_spinal_cord_injury` | Brain/spinal cord injury | Includes concussion and brain/spinal cord injuries. |
| `peripheral_nerve_injury` | Peripheral nerve injury | Includes neuroma. |
| `fracture` | Fracture | Traumatic fracture, including avulsion fracture and teeth. |
| `bone_stress_injury` | Bone stress injury | Includes stress fracture/periostitis/bone marrow edema. |
| `bone_contusion` | Bone contusion | Acute bony traumatic injury without fracture. |
| `avascular_necrosis` | Avascular necrosis | Retained for future teams. |
| `physis_injury` | Physis injury | Includes apophysis. |
| `cartilage_injury` | Cartilage injury | Includes meniscal, labral, articular cartilage, osteochondral injuries. |
| `arthritis` | Arthritis | Posttraumatic osteoarthritis. |
| `synovitis_capsulitis` | Synovitis/capsulitis | Includes joint impingement. |
| `bursitis` | Bursitis | Separate IOC category; use only when bursitis is explicit. |
| `joint_sprain` | Joint sprain | Includes ligament tear, acute instability episode, capsule injury, dislocation/subluxation when not kept separately. |
| `chronic_instability` | Chronic instability | Chronic instability. |
| `contusion_superficial` | Contusion (superficial) | Contusion, bruise, vascular damage. |
| `laceration` | Laceration | Skin laceration. |
| `abrasion` | Abrasion | Skin abrasion. |
| `vascular_trauma` | Vessels (vascular trauma) | Retained for future teams. |
| `stump_injury` | Stump injury | Retained for future teams. |
| `internal_organ_trauma` | Internal organs (organ trauma) | Organ trauma excluding concussion. |
| `nonspecific` | Nonspecific | Injury without tissue/pathology specified. |

Current Munster mappings from `Injury Tissue Type/s`:

| Munster source value | Pipeline key | Review label |
|---|---|---|
| `Bruising/ Haematoma` | `contusion_superficial` | Contusion (superficial) |
| `Concussion/ Brain Injury` | `brain_spinal_cord_injury` | Brain/spinal cord injury |
| `Disc` | `nonspecific` | Nonspecific |
| `Dislocation` | `joint_sprain` | Joint sprain |
| `Fracture` | `fracture` | Fracture |
| `Instability` | `chronic_instability` | Chronic instability |
| `Laceration/ Abrasion` | `laceration` | Laceration |
| `Ligament` | `joint_sprain` | Joint sprain |
| `Muscle Strain/Spasm` | `muscle_injury` | Muscle injury |
| `Nerve` | `peripheral_nerve_injury` | Peripheral nerve injury |
| `Organ Damage` | `internal_organ_trauma` | Internal organs (organ trauma) |
| `Osteoarthritis` | `arthritis` | Arthritis |
| `Osteochondral` | `cartilage_injury` | Cartilage injury |
| `Other Pain/ Unspecified` | `nonspecific` | Nonspecific |
| `Post Surgery` | `nonspecific` | Nonspecific |
| `Synovitis/ Impingement/ Bursitis` | `synovitis_capsulitis` | Synovitis/capsulitis |
| `Tendon` | `tendinopathy` | Tendinopathy |
| `Unspecified/Crossing` | `nonspecific` | Nonspecific |

Known review point:

- `Synovitis/ Impingement/ Bursitis` combines two IOC categories: `synovitis_capsulitis` and `bursitis`. The current safe default is `synovitis_capsulitis` because the source value is not specific enough to split without extra evidence.
- `Disc` and `Post Surgery` do not have exact IOC Table 5 tissue/pathology categories from the available Munster source value alone, so they are mapped to `nonspecific` unless a diagnosis code or clinical review supports a more precise category.

## Severity Categories

The current severity bands follow the project decision from the reviewed legend:

| Pipeline key | Review label | Rule |
|---|---|---|
| `zero_days_medical_attention_only` | Medical Attention | `Days Injured = 0` |
| `one_day` | 1 day | `Days Injured = 1` |
| `two_to_three_days` | 2-3 days | `Days Injured` between 2 and 3 |
| `four_to_seven_days` | 4-7 days | `Days Injured` between 4 and 7 |
| `eight_to_twenty_eight_days` | 8-28 days | `Days Injured` between 8 and 28 |
| `greater_than_twenty_eight_days` | >28 days | `Days Injured > 28` |
| `unknown_or_censored` | Unknown | Missing days or unclosed/ongoing injury |

## Scope

This mapping is a controlled classification layer. It does not overwrite source values. For Year 1 Munster, the audit boundary starts at the supplied pseudonymised standardised intake file, with provisional locators back to the local original reference file. For Year 2 and later teams, this same taxonomy should be applied from the original local source through anonymisation, standardisation, ingestion, review, and analysis.
