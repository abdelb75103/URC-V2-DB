import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const INPUTS = {
  evidence2024: 'docs/evidence/urc_2024-25_specific_diagnosis_evidence.json',
  illnessInventory2025: 'docs/evidence/diagnosis-families/illness_label_inventory_2025-26.raw.json',
  report2024: 'content/reporting/urc_dashboard_2024-25.json',
  report2025: 'content/reporting/urc_dashboard_2025-26.json',
};
export const OUTPUT = 'docs/evidence/diagnosis-families/diagnosis_family_adjudication_v1.json';

const readJson = (relativePath) => JSON.parse(fs.readFileSync(path.join(ROOT, relativePath), 'utf8'));
const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');
const fileSha256 = (relativePath) => sha256(fs.readFileSync(path.join(ROOT, relativePath)));
const stableJson = (value) => JSON.stringify(value);
const asciiSlug = (value) => value.normalize('NFKD')
  .replace(/[^\x00-\x7F]/g, '')
  .toLowerCase()
  .replace(/[^a-z0-9]+/g, '_')
  .replace(/^_+|_+$/g, '');

const existingGroups = (evidence) => new Map(
  evidence.source_label_mapping
    .filter((row) => row.diagnosis_group_code !== 'unknown')
    .map((row) => [row.diagnosis_group_label, row.diagnosis_group_code]),
);

const deterministicCode = (label) => `dx_${asciiSlug(label)}_${sha256(label).slice(0, 10)}`;
const codeFor = (label, existing) => existing.get(label) ?? deterministicCode(label);

const family = (label, existing, basis, reviewStatus = 'accepted_deterministic', extra = {}) => ({
  diagnosis_group_code: label === 'Unknown diagnosis' ? 'unknown' : codeFor(label, existing),
  diagnosis_group_label: label,
  decision_basis: basis,
  review_status: reviewStatus,
  ...extra,
});

const identity = (label, existing, basis = 'Explicit source diagnosis retained as an identity group. No broader merge is made without a dominant root.') => family(
  label,
  existing,
  basis,
  'identity_group',
  { identity_group: true },
);

const IDENTITY_2025 = new Set([
  'A/C joint stress/overuse injury',
  'Achilles enthesopathy with retrocalcaneal bursitis',
  'Buttock Pain not otherwise specified',
  'Chronic lateral instability',
  'Complication of finger MCP joint sprain',
  'Complication of foot laceration incl infection',
  'Delayed onset muscle soreness',
  'Functional head pain',
  'Hamstring Soft Tissue Dysfunction',
  'Lumbar Pain/ Injury nor otherwise specified',
  'Metacarpophalangeal ulnar collateral ligament sprain',
  'Mixed osteochondral and meniscal injury of the knee',
  'Neck Injuries',
  'Neck Soft Tissue Dysfunction',
  'Other hand or finger ligament tear',
  'Other Wrist Injury not otherwise specified',
  'Post open shoulder stabilisation',
  'Shoulder Soft Tissue Dysfunction',
  'Thigh pain/Injury Not otherwise specified',
  'Wrist or hand pain undiagnosed',
]);

const COMPOUND_IDENTITY_2024 = new Set([
  'Abdominal muscle soreness or spasm',
  'ACL or PCL sprain of the knee',
  'Buttock Muscle Strain/Spasm/Trigger Points',
  'Elbow UCL injury and common flexor origin tear',
  'Foot Muscle Strain/Spasm/trigger Points',
  'Forearm muscle soreness',
  'Knee ligament sprain involving the ACL, PCL or a collateral ligament',
  'Lumbar Spine muscle and Tendon Strain/Spasm/Trigger Points',
  'Lumbar soreness or muscle spasm',
  'Neck muscle and/or tendon strain/spasm/trigger points',
  'Neck muscle soreness/spasm/torticollis',
  'Rectus abdominis trigger points or spasm',
  'Sports hernia or abdominal tendinopathy',
  'Thigh Muscle strain/Spasm/Trigger Points',
  'Thoracic Muscle Strain/Spasm/Trigger Points',
]);

const SAFE_2025 = new Map([
  ['Acute Concussion', 'Concussion'],
  ['Ankle fracture with diastasis of syndesmosis', 'Ankle fracture'],
  ['Adductor longus tendon injury', 'Adductor tendon injury'],
  ['Adductor muscle haematoma', 'Adductor muscle injury'],
  ['Ankle joint synovitis', 'Ankle impingement or synovitis'],
  ['Anterior cruciate ligament (ACL) injury', 'ACL injury'],
  ['Anterior instability of shoulder', 'Shoulder instability'],
  ['Anteroinferior instability of shoulder', 'Shoulder instability'],
  ['Bruising buttock/ pelvis not otherwise specified', 'Buttock contusion'],
  ['Cheek laceration not requiring suturing', 'Head and facial laceration'],
  ['Chest muscle strain', 'Chest muscle injury'],
  ['Chronic PCL insufficiency', 'PCL injury'],
  ['Deltoid haematoma', 'Deltoid contusion'],
  ['DIP joint dislocation middle finger', 'Finger joint dislocation'],
  ['DIP joint dislocation ring finger', 'Finger joint dislocation'],
  ['Dislocation of midfoot through tarsometatarsal (TMT) joints/Lisfranc dislocation', 'Lisfranc injury'],
  ['Distal interphalangeal (DIP) joint dislocation index finger', 'Finger joint dislocation'],
  ['Dorsal hand laceration', 'Hand/wrist laceration or abrasion'],
  ['Ear laceration requiring suturing', 'Head and facial laceration'],
  ['Eye bruising/haematoma', 'Eye contusion'],
  ['Finger bruising/haematoma', 'Finger contusion'],
  ['Fracture 5th metatarsal shaft', 'Metatarsal fracture'],
  ['Fracture distal pole scaphoid', 'Scaphoid fracture'],
  ['Fractured calcaneus', 'Foot fracture'],
  ['Fractured midshaft tibia and fibula', 'Lower-leg fracture'],
  ['Fractured phalanx', 'Finger fracture'],
  ['Gastrocnemius muscle injury/strain', 'Gastrocnemius muscle injury'],
  ['Glenohumeral ligament sprain', 'Shoulder ligament injury'],
  ['Haematoma lesser toes', 'Toe contusion'],
  ['Hamstring strain/tear', 'Hamstring muscle injury'],
  ['Hip and Groin Muscle Strain/Tear', 'Hip and groin muscle injury'],
  ['Hip joint sprain/jar', 'Hip joint injury'],
  ['Inferior shoulder dislocation', 'Shoulder dislocation'],
  ['Knee - Joint sprain', 'Knee ligament injury, unspecified'],
  ['Knee Meniscal cartilage injury', 'Meniscal injury'],
  ['Lisfranc Sprain', 'Lisfranc injury'],
  ['Lumbar disc injury with associated L5 nerve root injury', 'Lumbar disc injury'],
  ['Middle finger flexor tendon rupture', 'Finger flexor tendon injury'],
  ['Nose contusion/haematoma', 'Nose contusion'],
  ['Other chronic subacromial impingement', 'Shoulder impingement'],
  ['Other gluteal muslce trigger points', 'Other gluteal muslce trigger points'],
  ['Other shin soft tissue bruising/haematoma not otherwise specified', 'Lower leg contusion'],
  ['Partial ACL tear', 'ACL injury'],
  ['Patellar contusion', 'Patellar contusion'],
  ['Rectus abdominus strain', 'Abdominal muscle injury'],
  ['Ring finger flexor tendon rupture', 'Finger flexor tendon injury'],
  ['Shoulder impingement/Synovitis', 'Shoulder impingement'],
  ['Shoulder muscle haematoma', 'Shoulder muscle contusion'],
  ['Sprain 1st MTP joint with volar plate rupture', 'First MTP joint sprain'],
  ['Thigh contusion or haematoma', 'Thigh contusion/haematoma'],
  ['Transversus abdominis muscle strain', 'Abdominal muscle injury'],
  ['Upper arm muscle bruising/haematoma', 'Upper arm soft tissue contusion or haematoma'],
  ['Wrist Soft Tissue Bruising/Haematoma', 'Wrist contusion'],
]);

const ILLNESS_ONLY_2025 = new Set([
  'Asthma/allergy/hay fever/respiratory',
  'Diarrhoea',
  'Influenza virus',
  'Other skin infection not specifically mentioned',
  'Other upper respiratory tract infection',
]);

const MIXED_2025 = new Set([
  'Complication of foot laceration incl infection',
  'Complication of laceration incl. infection',
]);

const CONCUSSION_INCLUDED = new Set([
  'Acute Concussion',
  'Acute Concussion with visual symptoms',
  'Concussion',
  'Concussion/Brain Injury',
  'Concussion in a player with a concerning history',
  'Concussion with Criteria 1 video signs',
  'Concussion with Criteria 2 video signs',
  'Concussion with delayed symptom presentation',
  'Concussion with imaging abnormality',
  'Concussion with no concerning history or signs',
]);

const CONCUSSION_2025 = new Set([
  ...CONCUSSION_INCLUDED,
]);

const HAMSTRING_MUSCLE_2024_2025 = new Set([
  'Biceps femoris strain grade 1 - 2',
  'Grade 3 hamstring strain',
  'Hamstring strain or tear',
  'Hamstring strain/tear',
  'Semimembranosis/tendinosis strain (grade 1 - 2)',
]);

const HEAD_IMPACT_NON_CONCUSSION = new Set([
  'Head impact (not concussion) with Criteria 2 video signs',
  'Head/neck impact not diagnosed as concussion',
]);

const HAMSTRING_EXCLUDED = new Set([
  'Back referred hamstring tightness',
  'Hamstring cramping during exercise',
  'Hamstring origin tendon rupture',
  'Hamstring origin tendinopathy',
  'Hamstring Soft Tissue Dysfunction',
  'Hamstring tendinopathy with ischial bursitis',
  'Hamstring tendon injury',
  'Lateral hamstring insertion tendonitis',
  'Lateral hamstring tendon rupture at knee',
  'Lateral hamstring trigger points',
  'Lumbar pain with hamstring referral',
  'Medial hamstring insertion tendonitis/pes anserinus bursitis',
  'Medial hamstring tendon strain at knee',
]);

const HAMSTRING_TENDON_2024 = new Set([
  'Hamstring origin tendinopathy',
  'Hamstring tendon injury',
  'Hamstring tendinopathy with ischial bursitis',
  'Lateral hamstring insertion tendonitis',
  'Medial hamstring insertion tendonitis/pes anserinus bursitis',
  'Medial hamstring tendon strain at knee',
]);

const ILLNESS_2025_GROUPS = new Map([
  ['Other upper resp tract infection [N/A]', 'Upper respiratory infection'],
  ['Allergy - rhinitis/sinusitis/hayfever', 'Allergic rhinitis/hay fever'],
  ['Respiratory tract infection (bacterial or viral) [N/A]', 'Respiratory infection unspecified'],
  ['Skin infection toenail - incl infected ingrown toenail [Right]', 'Skin infection'],
  ['Asthma and/or allergy [N/A]', 'Respiratory illness'],
  ['Dermatitis [Bilateral]', 'Dermatitis/eczema'],
  ['Dermatitis [N/A]', 'Dermatitis/eczema'],
  ['Herpes simplex (incl scrum pox) [Right]', 'Herpes infection'],
  ['Herpes simplex (incl scrum pox) [N/A]', 'Herpes infection'],
  ['Infection', 'Infection, unspecified'],
  ['Influenza (A/B) [N/A]', 'Influenza'],
  ['Influenza (A/B) [Center]', 'Influenza'],
  ['Middle ear infection', 'Middle ear infection'],
  ['Secondary Insomnia (incl other assoc. diagnosis)', 'Insomnia'],
  ['Systemic Viral Infection (excl viruses localised to one area) [N/A]', 'Systemic viral infection'],
  ['Vasovagal Syncope [N/A]', 'Vasovagal syncope'],
  ['Abcess Finger(s) (excl. Joint)', 'Skin infection'],
  ['Abcess Lower Leg', 'Skin infection'],
  ['Allergic Reaction [N/A]', 'Allergic reaction'],
  ['Allergy - rhinitis/ sinusitis/ hayfever (for urticaria see MDUX) [N/A]', 'Allergic rhinitis/hay fever'],
  ['Anxiety/ panic disorder [N/A]', 'Anxiety or related disorder'],
  ['Atopic dermatitis / eczema', 'Dermatitis/eczema'],
  ['Cellulitis/ Abcess Finger(s) (excl. Joint)', 'Skin infection'],
  ['Cellulitis/ Abcess Head/ Face/ Neck', 'Skin infection'],
  ['Cellulitis/Abcess Knee (excl. Joint)', 'Skin infection'],
  ['Confirmed COVID-19 infection (Symptomatic)', 'COVID-19 infection'],
  ['Conjunctivitis', 'Conjunctivitis'],
  ['Conjunctivitis (Viral/ Bacterial) [Right]', 'Conjunctivitis'],
  ['ENT Illness including dental (excl sinusitis - see MPAL) [Right]', 'ENT or dental illness'],
  ['Exercise associated gastritis/reflux', 'Gastritis or peptic ulcer disease'],
  ['Folliculitis', 'Folliculitis'],
  ['Foot pain undiagnosed', 'Foot pain, undiagnosed'],
  ['Gout in ankle/foot (incl big toe)', 'Gout'],
  ['Haematemesis/melaena/GI bleeding', 'Gastrointestinal bleeding'],
  ['Headaches', 'Headache'],
  ['Infected knee joint', 'Knee joint infection'],
  ['Infective conjunctivitis', 'Conjunctivitis'],
  ['Lymphadenopathy secondary to skin infection', 'Lymphadenopathy'],
  ['Medical Illness [N/A]', 'Medical illness'],
  ['Molluscum Contagiosum [Left]', 'Molluscum contagiosum'],
  ['Otalgia', 'Otalgia'],
  ['Otalgia [Right]', 'Otalgia'],
  ['Otitis externa', 'Otitis externa'],
  ['Otitis externa [Right]', 'Otitis externa'],
  ['Prepatellar bursitis', 'Prepatellar bursitis'],
  ['Respiratory system infection', 'Respiratory infection unspecified'],
  ['Shingles (Zoster Virus) [Left]', 'Shingles (zoster virus)'],
  ['Sinus headache [Left]', 'Headache'],
  ['Skin infection elbow', 'Skin infection'],
  ['Skin Infection/ Cellulitis/ Abscess/ Infected Bursa - bacterial (excl infection complicating laceration - see ? KXQ) [Left]', 'Skin infection'],
  ['Sleep Disorder(s) [N/A]', 'Sleep disorder'],
  ['Tired athlete undiagnosed', 'Fatigue, undiagnosed'],
  ['Upper respiratory tract infection', 'Upper respiratory infection'],
  ['Urinary problem [N/A]', 'Urinary problem, unspecified'],
  ['Urinary Tract Infection', 'Urinary tract infection'],
]);

const ILLNESS_2025_IDENTITY_GROUPS = new Map([
  ['Unknown', 'Unknown illness'],
  ['Unknown diagnosis', 'Unknown illness'],
  ['Otalgia [Right]', 'Otalgia'],
  ['Otitis externa [Right]', 'Otitis externa'],
]);

const ILLNESS_2025_IDENTITY = new Set([
  'Infection',
  'ENT Illness including dental (excl sinusitis - see MPAL) [Right]',
  'Folliculitis',
  'Foot pain undiagnosed',
  'Haematemesis/melaena/GI bleeding',
  'Infected knee joint',
  'Lymphadenopathy secondary to skin infection',
  'Molluscum Contagiosum [Left]',
  'Otalgia',
  'Otitis externa',
  'Prepatellar bursitis',
  'Shingles (Zoster Virus) [Left]',
  'Sleep Disorder(s) [N/A]',
  'Tired athlete undiagnosed',
  'Urinary problem [N/A]',
  'Vasovagal Syncope [N/A]',
]);

const GASTROCNEMIUS_MUSCLE_2024 = new Set([
  'Gastrocnemius muscle injury or strain',
  'Lateral gastroc strain',
  'Lateral gastrocnemius strain',
  'Medial gastroc strain',
  'Medial gastrocnemius strain',
]);

const GASTROCNEMIUS_TRIGGER_2024 = new Set([
  'Gastroc muscle trigger points/spasm',
  'Lateral gastrocnemius trigger points or spasm',
  'Medial gastrocnemius trigger points or spasm',
]);

const GROIN_MUSCLE_2024 = new Set(['Adductor longus strain', 'Adductor magnus strain']);
const GROIN_TRIGGER_2024 = new Set(['Groin soreness or trigger points', 'Proximal adductor trigger points']);
const BICEPS_MUSCLE_2024 = new Set(['Biceps haematoma', 'Biceps muscle strain']);
const BICEPS_TENDON_2024 = new Set(['Distal biceps tendon rupture', 'Proximal biceps tendon injury']);
const GLUTEAL_MUSCLE_2024 = new Set(['Gluteal muscle strain', 'Gluteus maximus strain', 'Gluteus medius/minimus strain']);
const GLUTEAL_TRIGGER_2024 = new Set(['Gluteal muscle trigger points', 'Piriformis trigger points']);
const MCL_STRUCTURAL_2024 = new Set(['Grade 1 MCL tear knee', 'Grade 2 MCL tear knee', 'Knee medial collateral ligament (MCL) injury', 'MCL rupture knee']);
const MCL_COMPOUND_2024 = new Set(['MCL strain/rupture with chondral/meniscal damage knee', 'Medial collateral ligament strain or rupture with chondral or meniscal damage of the knee']);

const corrected2024Family = (label, existing) => {
  if (CONCUSSION_2025.has(label) || label === 'Concussion with Criteria 2 video signs' || label === 'Concussion with delayed symptom presentation') {
    return family('Concussion', existing, 'Confirmed concussion root diagnosis. Qualifiers do not displace the root diagnosis.');
  }
  if (HEAD_IMPACT_NON_CONCUSSION.has(label)) return family('Head impact, non-concussion', existing, 'Explicitly recorded as not concussion.');
  if (COMPOUND_IDENTITY_2024.has(label)) return identity(label, existing, 'Compound label has no single dominant tissue or pathology. Preserve it as an identity group. No broader merge is made without a dominant root.');
  if (HAMSTRING_MUSCLE_2024_2025.has(label)) return family('Hamstring muscle injury', existing, 'Explicit hamstring muscle strain/tear root. Grade, named muscle and added tendinosis do not displace it.');
  if (HAMSTRING_TENDON_2024.has(label)) return family('Hamstring tendon injury', existing, 'Primary hamstring tendon pathology remains separate from muscle injury.');
  if (label === 'Lateral hamstring trigger points') return identity(label, existing, 'Trigger points are not a structural muscle injury.');
  if (label === 'Hamstring cramping during exercise') return family('Hamstring cramp/spasm', existing, 'Cramp/spasm remains separate from structural muscle injury.');
  if (GASTROCNEMIUS_MUSCLE_2024.has(label)) return family('Gastrocnemius muscle injury', existing, 'Explicit gastrocnemius muscle strain root.');
  if (GASTROCNEMIUS_TRIGGER_2024.has(label)) return family('Gastrocnemius trigger points/spasm', existing, 'Trigger points/spasm remain separate from structural muscle injury.');
  if (label === 'Gastrocnemius tendon injury') return family('Gastrocnemius tendon injury', existing, 'Primary tendon pathology remains separate from muscle injury.');
  if (label === 'Calf cramping during exercise' || label === 'Calf muscle cramps/spasm') return family('Calf cramp/spasm', existing, 'Cramp/spasm remains separate from structural muscle injury.');
  if (label === 'Soleus Trigger points/Spasm') return family('Soleus trigger points/spasm', existing, 'Trigger points/spasm remain separate from structural muscle injury.');
  if (label === 'Soleus muscle strain') return family('Soleus injury', existing, 'Explicit soleus muscle strain root.');
  if (GROIN_MUSCLE_2024.has(label)) return family('Adductor muscle injury', existing, 'Explicit adductor muscle strain root.');
  if (label === 'Adductor longus tendon strain' || label === 'Adductor origin tendinopathy') return family('Adductor tendon injury', existing, 'Primary adductor tendon pathology remains separate from muscle injury.');
  if (GROIN_TRIGGER_2024.has(label)) return identity(label, existing, 'Trigger points/soreness remain separate from structural muscle injury.');
  if (BICEPS_MUSCLE_2024.has(label)) return family('Biceps muscle injury', existing, 'Explicit biceps muscle injury or haematoma root.');
  if (BICEPS_TENDON_2024.has(label)) return family('Biceps tendon injury', existing, 'Primary biceps tendon pathology remains separate from muscle injury.');
  if (GLUTEAL_MUSCLE_2024.has(label)) return family('Gluteal muscle injury', existing, 'Explicit gluteal muscle strain root.');
  if (GLUTEAL_TRIGGER_2024.has(label)) return identity(label, existing, 'Trigger points remain separate from structural muscle injury.');
  if (label === 'Buttock Muscle Strain/Spasm/Trigger Points') return identity(label, existing, 'Compound label has no single dominant root.');
  if (label === 'Supraspinatus tendon tear partial thickness') return family('Supraspinatus tendon injury', existing, 'Primary supraspinatus tendon pathology remains separate from rotator cuff muscle injury.');
  if (MCL_STRUCTURAL_2024.has(label)) return family('MCL injury', existing, 'Explicit MCL structural injury root.');
  if (label === 'Knee MCL contusion') return family('Knee contusion', existing, 'Contusion is a different primary pathology from structural MCL injury.');
  if (MCL_COMPOUND_2024.has(label)) return family('MCL injury', existing, 'Explicit MCL strain/rupture root. Associated chondral or meniscal findings do not displace it.');
  if (label === 'Glenohumeral joint sprain with chondral or labral damage' || label === 'Glenohumeral joint sprain with chondral/labral damage (incl SLAP tear)') return family('Shoulder joint injury', existing, 'Explicit glenohumeral joint sprain root. Associated chondral or labral findings do not displace it.');
  if (label === 'Lisfranc sprain with associated fracture') return family('Lisfranc injury', existing, 'Explicit Lisfranc sprain root. The associated fracture does not displace it.');
  if (label === 'Lumbar disc injury with L4 nerve root injury' || label === 'Lumbar disc injury with S1 nerve root injury') return family('Lumbar disc injury', existing, 'Explicit lumbar disc injury root. The associated nerve-root finding does not displace it.');
  if (label === 'Neck soft-tissue dysfunction') return family('Neck soft tissue dysfunction', existing, 'Normalised punctuation variant retained as the explicit dysfunction diagnosis.');
  return null;
};

const build2024Rows = (evidence, existing) => {
  const byLabel = new Map();
  for (const row of evidence.rows) {
    const current = byLabel.get(row.specific_diagnosis_source_label) ?? {
      injury_rows: 0,
      illness_rows: 0,
      groups: new Set(),
    };
    if (row.problem_type === 'Injury') current.injury_rows += 1;
    if (row.problem_type === 'Illness') current.illness_rows += 1;
    current.groups.add(row.diagnosis_group_label);
    byLabel.set(row.specific_diagnosis_source_label, current);
  }

  return evidence.source_label_mapping.map((source) => {
    const counts = byLabel.get(source.specific_diagnosis_source_label);
    if (!counts) throw new Error(`2024 source label has no evidence rows: ${source.specific_diagnosis_source_label}`);
    const scope = counts.injury_rows && counts.illness_rows ? 'mixed' : counts.injury_rows ? 'injury' : 'illness';
    const corrected = scope === 'illness' ? null : corrected2024Family(source.specific_diagnosis_source_label, existing);
    const mapped = corrected ?? (scope === 'illness' ? null : family(source.diagnosis_group_label, existing, 'Inherited from the hash-bound 2024 reviewed source mapping.'));
    return {
      season: '2024-25',
      source_label: source.specific_diagnosis_source_label,
      source_group_code: source.diagnosis_group_code,
      source_group_label: source.diagnosis_group_label,
      diagnosis_group_code: mapped?.diagnosis_group_code ?? null,
      diagnosis_group_label: mapped?.diagnosis_group_label ?? null,
      illness_group_code: counts.illness_rows ? source.diagnosis_group_code : null,
      illness_group_label: counts.illness_rows ? source.diagnosis_group_label : null,
      problem_type_scope: scope,
      injury_metric_eligible: Boolean(counts.injury_rows),
      row_filter_required: scope === 'mixed',
      source_row_counts: { injury: counts.injury_rows, illness: counts.illness_rows },
      review_status: mapped?.review_status ?? 'out_of_scope',
      decision_basis: mapped?.decision_basis ?? 'Canonical Problem type is Illness. Retain the source label unchanged and exclude it from injury-family metrics.',
      mapping_source: corrected ? 'cross-season adjudication v1' : '2024 reviewed source mapping',
      identity_group: mapped?.identity_group ?? false,
    };
  });
};

const normalizeIllnessLabel = (label) => label
  .normalize('NFKD')
  .replace(/\s+\[(?:N\/A|Right|Left|Bilateral|Center)\]\s*$/i, '')
  .toLowerCase()
  .replace(/abcess/g, 'abscess')
  .replace(/[^a-z0-9]+/g, ' ')
  .replace(/\s+/g, ' ')
  .trim();

const buildIllnessLookup2024 = (rows2024) => {
  const byExact = new Map();
  const byNormalized = new Map();
  for (const row of rows2024.filter((candidate) => candidate.illness_group_code)) {
    const decision = {
      illness_group_code: row.illness_group_code,
      illness_group_label: row.illness_group_label,
    };
    byExact.set(row.source_label, decision);
    const key = normalizeIllnessLabel(row.source_label);
    const candidates = byNormalized.get(key) ?? new Map();
    candidates.set(`${decision.illness_group_code}:${decision.illness_group_label}`, decision);
    byNormalized.set(key, candidates);
  }
  return { byExact, byNormalized };
};

const parseIllnessMetric = (value, label, key) => {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0) throw new Error(`Invalid 2025 illness ${key}: ${label}`);
  return parsed;
};

const build2025IllnessRows = (inventory, rows2024, existing) => {
  const lookup = buildIllnessLookup2024(rows2024);
  return inventory.map((source) => {
    const sourceLabel = source.source_label;
    if (!sourceLabel || typeof sourceLabel !== 'string') throw new Error('2025 illness inventory has a blank source label');
    const exact = lookup.byExact.get(sourceLabel);
    const normalizedCandidates = lookup.byNormalized.get(normalizeIllnessLabel(sourceLabel));
    const inherited = exact ?? (normalizedCandidates?.size === 1 ? [...normalizedCandidates.values()][0] : null);
    const destination = ILLNESS_2025_GROUPS.get(sourceLabel);
    let mapped;
    let mappingSource;
    if (inherited) {
      mapped = family(inherited.illness_group_label, existing, 'Reused from the corrected 2024 illness mapping. Laterality and data-entry qualifiers do not change the illness group.');
      mappingSource = exact ? 'exact corrected 2024 illness mapping' : 'normalised corrected 2024 illness mapping';
    } else if (ILLNESS_2025_IDENTITY_GROUPS.has(sourceLabel)) {
      mapped = identity(ILLNESS_2025_IDENTITY_GROUPS.get(sourceLabel), existing, 'No broader illness root is established. Strip data-entry qualifiers and preserve the conservative identity group.');
      mappingSource = '2025 illness identity preservation';
    } else if (ILLNESS_2025_IDENTITY.has(sourceLabel)) {
      mapped = identity(sourceLabel, existing, 'No broader illness root is established. Preserve the source label as an identity group.');
      mappingSource = '2025 illness identity preservation';
    } else if (destination) {
      mapped = family(destination, existing, 'Explicit illness root or clinically coherent illness group. Qualifiers do not change the illness group.');
      mappingSource = '2025 illness adjudication';
    } else {
      mapped = identity(sourceLabel, existing, 'No dominant illness root is established. Preserve the source label as an identity group.');
      mappingSource = '2025 illness identity preservation';
    }
    if (mapped.diagnosis_group_code === 'unknown') mapped.diagnosis_group_code = deterministicCode(mapped.diagnosis_group_label);
    return {
      season: '2025-26',
      source_label: sourceLabel,
      illness_group_code: mapped.diagnosis_group_code,
      illness_group_label: mapped.diagnosis_group_label,
      review_status: mapped.review_status,
      decision_basis: mapped.decision_basis,
      mapping_source: mappingSource,
      identity_group: mapped.identity_group ?? false,
      metrics: {
        recorded_illnesses: parseIllnessMetric(source.recorded_illnesses, sourceLabel, 'recorded_illnesses'),
        known_duration_illnesses: parseIllnessMetric(source.known_duration_illnesses, sourceLabel, 'known_duration_illnesses'),
        days_lost: parseIllnessMetric(source.days_lost, sourceLabel, 'days_lost'),
      },
    };
  });
};

const sourceMap2024 = (rows) => new Map(rows.map((row) => [row.source_label, row]));

const make2025Mapped = (profile, source2024, existing) => {
  const sourceLabel = profile.label;
  if (ILLNESS_ONLY_2025.has(sourceLabel)) return {
    diagnosis_group_code: null,
    diagnosis_group_label: null,
    review_status: 'out_of_scope',
    decision_basis: 'Known illness label. It remains unchanged and is excluded from injury-family metrics.',
    identity_group: false,
  };
  if (MIXED_2025.has(sourceLabel)) return {
    ...identity(sourceLabel, existing, 'Mixed injury/illness wording. Keep the label as an identity group with row filtering. No broader merge is made without a dominant root.'),
    row_filter_required: true,
  };
  if (CONCUSSION_2025.has(sourceLabel)) return family('Concussion', existing, 'Confirmed concussion root diagnosis. Qualifiers do not displace the root diagnosis.');
  if (sourceLabel === 'Head impact (not concussion) with Criteria 2 video signs' || sourceLabel === 'Head/neck impact not diagnosed as concussion') return family('Head impact, non-concussion', existing, 'Explicitly recorded as not concussion.');
  if (HAMSTRING_MUSCLE_2024_2025.has(sourceLabel)) return family('Hamstring muscle injury', existing, 'Explicit hamstring muscle strain/tear root. Grade, named muscle and added tendinosis do not displace it.');
  if (SAFE_2025.has(sourceLabel)) {
    const destination = SAFE_2025.get(sourceLabel);
    return family(destination, existing, 'Safe destination from the cross-season diagnosis inventory.');
  }
  if (source2024?.diagnosis_group_code === 'unknown' || sourceLabel === 'Unknown' || sourceLabel === 'Unknown diagnosis') return family('Unknown diagnosis', existing, 'Unknown source diagnosis remains a non-front-facing identity group.');
  if (source2024) {
    const corrected = corrected2024Family(sourceLabel, existing);
    if (corrected) return corrected;
    if (source2024.problem_type_scope === 'illness') return {
      diagnosis_group_code: null,
      diagnosis_group_label: null,
      review_status: 'out_of_scope',
      decision_basis: 'Inherited known illness label. It remains unchanged and is excluded from injury-family metrics.',
      identity_group: false,
    };
    return family(source2024.diagnosis_group_label, existing, 'Exact source label inherits its corrected 2024 mapping.');
  }
  if (IDENTITY_2025.has(sourceLabel)) return identity(sourceLabel, existing, 'No dominant root is established by the released label. Preserve it as an identity group. No broader merge is made without a dominant root.');
  return identity(sourceLabel, existing);
};

const build2025Rows = (report, rows2024, existing) => {
  const source2024 = sourceMap2024(rows2024);
  const profiles = report.injury_profiles.filter((row) => row.dimension === 'diagnosis' && row.setting === 'all');
  return profiles.map((profile) => {
    const sourceRow2024 = source2024.get(profile.label);
    const mapped = make2025Mapped(profile, sourceRow2024, existing);
    const inheritedIllness = sourceRow2024?.illness_group_code ? sourceRow2024 : null;
    const problemTypeScope = mapped.review_status === 'out_of_scope'
      ? 'illness'
      : MIXED_2025.has(profile.label)
        ? 'mixed'
        : 'injury_or_unresolved';
    return {
      season: '2025-26',
      source_label: profile.label,
      source_profile_code: profile.code,
      diagnosis_group_code: mapped.diagnosis_group_code ?? null,
      diagnosis_group_label: mapped.diagnosis_group_label ?? null,
      illness_group_code: inheritedIllness?.illness_group_code ?? null,
      illness_group_label: inheritedIllness?.illness_group_label ?? null,
      problem_type_scope: problemTypeScope,
      injury_metric_eligible: mapped.review_status === 'out_of_scope' ? false : mapped.row_filter_required ? false : true,
      row_filter_required: mapped.row_filter_required ?? false,
      review_status: mapped.review_status,
      decision_basis: mapped.decision_basis,
      mapping_source: sourceRow2024 ? 'exact 2024 source-label inheritance' : SAFE_2025.has(profile.label) ? '2025 inventory safe destination' : 'identity-preservation rule',
      identity_group: mapped.identity_group ?? false,
      metrics: {
        recorded_injuries: profile.recorded_injuries,
        time_loss_injuries: profile.time_loss_injuries,
        days_lost: profile.days_lost,
      },
    };
  });
};

const sumFamily = (rows, label) => rows
  .filter((row) => row.diagnosis_group_label === label && row.injury_metric_eligible)
  .reduce((totals, row) => ({
    recorded_injuries: totals.recorded_injuries + row.metrics.recorded_injuries,
    time_loss_injuries: totals.time_loss_injuries + row.metrics.time_loss_injuries,
    days_lost: totals.days_lost + row.metrics.days_lost,
  }), { recorded_injuries: 0, time_loss_injuries: 0, days_lost: 0 });

const sumProfiles = (profiles, labels) => profiles
  .filter((profile) => labels.has(profile.label))
  .reduce((totals, profile) => ({
    recorded_injuries: totals.recorded_injuries + profile.recorded_injuries,
    time_loss_injuries: totals.time_loss_injuries + profile.time_loss_injuries,
    days_lost: totals.days_lost + profile.days_lost,
  }), { recorded_injuries: 0, time_loss_injuries: 0, days_lost: 0 });

export const buildLedger = () => {
  const evidence = readJson(INPUTS.evidence2024);
  const illnessInventory2025 = readJson(INPUTS.illnessInventory2025);
  const report2024 = readJson(INPUTS.report2024);
  const report2025 = readJson(INPUTS.report2025);
  const existing = existingGroups(evidence);
  const rows2024 = build2024Rows(evidence, existing);
  const rows2025 = build2025Rows(report2025, rows2024, existing);
  const illnessRows2025 = build2025IllnessRows(illnessInventory2025, rows2024, existing);
  const diagnosisProfiles2025 = report2025.injury_profiles.filter((row) => row.dimension === 'diagnosis' && row.setting === 'all');
  const rows = [...rows2024, ...rows2025];
  const mappingRows = rows.map(({ season, source_label, diagnosis_group_code, diagnosis_group_label, problem_type_scope, review_status, row_filter_required, injury_metric_eligible }) => ({
    season,
    source_label,
    diagnosis_group_code,
    diagnosis_group_label,
    problem_type_scope,
    review_status,
    row_filter_required,
    injury_metric_eligible,
  }));
  const totals2025 = {
    concussion: sumFamily(rows2025, 'Concussion'),
    hamstring_muscle_injury: sumFamily(rows2025, 'Hamstring muscle injury'),
  };
  const inputTotals2025 = {
    concussion: sumProfiles(diagnosisProfiles2025, CONCUSSION_2025),
    hamstring_muscle_injury: sumProfiles(diagnosisProfiles2025, HAMSTRING_MUSCLE_2024_2025),
  };
  const profilesForSetting = (setting) => report2025.injury_profiles
    .filter((row) => row.dimension === 'diagnosis' && row.setting === setting);
  const inputTotals2025BySetting = {
    overall: inputTotals2025.concussion,
    match: sumProfiles(profilesForSetting('match'), CONCUSSION_2025),
    training: sumProfiles(profilesForSetting('training'), CONCUSSION_2025),
  };
  const published = (report, label) => report.injury_profiles
    .filter((row) => row.dimension === 'diagnosis' && row.setting === 'all' && row.label === label)
    .map((row) => ({ recorded_injuries: row.recorded_injuries, time_loss_injuries: row.time_loss_injuries, days_lost: row.days_lost }));
  const sourceLabelMapping = evidence.source_label_mapping.map((row) => ({
    source_label: row.specific_diagnosis_source_label,
    diagnosis_group_code: row.diagnosis_group_code,
    diagnosis_group_label: row.diagnosis_group_label,
  }));
  const mappingHash = sha256(stableJson(mappingRows));
  const illnessMappingRows = illnessRows2025.map(({ season, source_label, illness_group_code, illness_group_label, review_status, identity_group }) => ({
    season,
    source_label,
    illness_group_code,
    illness_group_label,
    review_status,
    identity_group,
  }));
  const illnessTotals2025 = illnessRows2025.reduce((totals, row) => ({
    recorded_illnesses: totals.recorded_illnesses + row.metrics.recorded_illnesses,
    known_duration_illnesses: totals.known_duration_illnesses + row.metrics.known_duration_illnesses,
    days_lost: totals.days_lost + row.metrics.days_lost,
  }), { recorded_illnesses: 0, known_duration_illnesses: 0, days_lost: 0 });
  return {
    schema_version: 'urc_diagnosis_family_adjudication_v1',
    status: 'local_candidate_not_executed',
    scope: {
      seasons: ['2024-25', '2025-26'],
      source_label_counts: { '2024-25': rows2024.length, '2025-26': rows2025.length },
      rule: 'An explicit root diagnosis determines the family. Grade, laterality, symptoms, imaging, history and associated findings do not displace it. A different primary tissue or pathology does.',
      illness_rule: 'Illness labels remain unchanged and never enter injury-family reconciliation. Mixed wording requires row filtering.',
    },
    rules: {
      concussion: {
        family_label: 'Concussion',
        included: [...CONCUSSION_INCLUDED].sort(),
        excluded: [...HEAD_IMPACT_NON_CONCUSSION].sort(),
      },
      hamstring_muscle_injury: {
        family_label: 'Hamstring muscle injury',
        included: [...HAMSTRING_MUSCLE_2024_2025].sort(),
        excluded: [...HAMSTRING_EXCLUDED].sort(),
      },
    },
    source_artifacts: {
      '2024-25_evidence': { path: INPUTS.evidence2024, sha256: fileSha256(INPUTS.evidence2024) },
      '2025-26_illness_inventory': { path: INPUTS.illnessInventory2025, sha256: fileSha256(INPUTS.illnessInventory2025) },
      '2024-25_public_payload': { path: INPUTS.report2024, sha256: fileSha256(INPUTS.report2024) },
      '2025-26_public_payload': { path: INPUTS.report2025, sha256: fileSha256(INPUTS.report2025) },
    },
    source_mapping: {
      source_label_count: sourceLabelMapping.length,
      source_label_mapping_sha256: sha256(stableJson(sourceLabelMapping)),
      source_label_mapping: sourceLabelMapping,
    },
    illness_mapping: {
      '2025-26_source_label_count': illnessRows2025.length,
      '2025-26_source_label_mapping_sha256': sha256(stableJson(illnessMappingRows)),
      '2025-26_source_label_mapping': illnessMappingRows,
      '2025-26_inventory_reconciliation': illnessTotals2025,
    },
    reconciliation: {
      current_public_input: {
        '2024-25': {
          concussion: published(report2024, 'Concussion')[0],
          hamstring_injury: published(report2024, 'Hamstring injury')[0],
        },
        '2025-26': {
          diagnosis_profile_labels: diagnosisProfiles2025.length,
          before_mapping: {
            concussion_family: inputTotals2025.concussion,
            hamstring_muscle_injury_family: inputTotals2025.hamstring_muscle_injury,
            concussion_family_by_setting: inputTotals2025BySetting,
          },
          after_mapping: {
            concussion_family: totals2025.concussion,
            hamstring_muscle_injury_family: totals2025.hamstring_muscle_injury,
          },
        },
      },
      pinned_2025_26: {
        concussion: inputTotals2025BySetting,
        hamstring_muscle_injury: { overall: inputTotals2025.hamstring_muscle_injury },
      },
      illness: {
        '2024-25': { recorded_illnesses: evidence.aggregate_reconciliation.illness_rows_excluded_from_injury_metrics },
        '2025-26': illnessTotals2025,
      },
    },
    mapping_hashes: {
      mapping_rows_sha256: mappingHash,
      complete_ledger_sha256: sha256(stableJson(rows)),
      illness_mapping_rows_sha256: sha256(stableJson(illnessMappingRows)),
      illness_ledger_sha256: sha256(stableJson(illnessRows2025)),
    },
    illness_rows_2025: illnessRows2025,
    rows,
  };
};

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const ledger = buildLedger();
  fs.writeFileSync(path.join(ROOT, OUTPUT), `${JSON.stringify(ledger, null, 2)}\n`);
  console.log(JSON.stringify({ output: OUTPUT, rows: ledger.rows.length, mapping_rows_sha256: ledger.mapping_hashes.mapping_rows_sha256 }));
}
