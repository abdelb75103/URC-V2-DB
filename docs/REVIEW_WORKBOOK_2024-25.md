# 2024-25 authoritative review workbook

## Use this file

The authoritative workbook for current 2024-25 human review is:

`data/2024-25/review/urc_injury_master_review_2024-25.xlsx`

Do not use a workbook under `data/2024-25/archive/review-workbooks/` for a
current judgement. Those files are retained only as historical evidence.

## Provenance

- Source: the Google Sheet titled `urc_injury_master_2024-25.xlsx` at
  `https://docs.google.com/spreadsheets/d/1QEauOrDMMgkHJjcG9q-0pirV8kyhuq3Z/edit?gid=731315872#gid=731315872`
- Retrieved as an Excel workbook on 2026-08-24.
- SHA-256: `ac8a486cf8181d8d06a4c50e1ffbc154dc895c88f74129b661ede1b1694f84b6`
- Workbook shape: `Injury Master` with 3,060 data rows and 28 columns, plus
  `Fixtures` with 151 data rows and 7 columns.
- The review reason in `Injury Master!AB2` is
  `Outside official analysis window`.

Verify the local file with:

```bash
shasum -a 256 data/2024-25/review/urc_injury_master_review_2024-25.xlsx
```

## Reconciliation with the pinned generated workbook

The Drive-derived workbook was compared with
`data/2024-25/master/urc_injury_master_workbook_2024-25.xlsx` on 2026-08-24.

- All 3,060 injury data rows match across columns A to AA.
- The only non-review wording difference is the column C header:
  `Received At Club` became `Reporting At Club`.
- Column AB has 398 updated cells. Each update adds
  `Outside official analysis window`, retaining any existing exclusion reason.
- The Drive-derived workbook contains the two sheets used for current review.
  The pinned generated workbook also contains three pipeline QA sheets.
- The workbook contains no formulas. Two hundred literal `#REF!` values remain
  in the Orchard Code column; they are unchanged from the pinned generated
  workbook and are source-data values, not broken export formulas.
- Both sheets were rendered and visually checked after the local cutover. The
  review colours, headers, dates, and exclusion-reason presentation were
  preserved.

This makes the Drive-derived file the source of truth for manual workbook
review. It is not a replacement for the analytical lineage. The append-only
master JSON, decision ledger, accepted inclusion CSV, and approved reporting
views remain authoritative for replay and published analysis. A workbook
judgement affects analysis only after it is recorded through the governed
ledger or versioned reporting rule.

## Specific Diagnosis promotion

The authoritative workbook was promoted on 2026-08-26 after the Specific
Diagnosis review recorded in
`data/2024-25/review/specific_diagnosis_review_summary_2024-25.md`.

- The exact adjudication baseline SHA-256 is
  `87ebb569afc45ef28116df98dc83c2d8799139eaecd1c249372c209fa783f155`.
- The current authoritative workbook SHA-256 is
  `4f1db130f9f5aff23c3473eb2ab64a467f739a0b6ac7e4f170ca0383d9072b73`.
- `Injury Master` still has 3,060 data rows. The promotion added
  `Specific Diagnosis` as column AC and extended the table and filter through
  `AC3061`.
- Existing columns A to AB, the row set, row order, `Fixtures` content and
  sheet order are unchanged. The 32 adjudication row references therefore
  remain valid against the promoted workbook.
- On 2026-08-26, a focused legacy-code recovery updated only column AC for 56
  rows: 37 included and 19 excluded. The pre-recovery workbook hash was
  `60326e5b8a3dd5ae978d13bad08f2492ff328940a068e6dd52ae0461c9305d8a`.
- Ten included records remain without a defensible structure or pathology and
  are listed in the local grouped summary workbook's `Unresolved Review`
  sheet.
- The master opens with all 3,060 rows visible. The 1,008 excluded rows retain
  their red review formatting. Inclusion-only review remains in the grouped
  summary workbook rather than the master workbook's saved filter state.

Retain both hashes. The baseline hash binds the reviewed row judgements, while
the current hash identifies the workbook used for any further human review.

## Retained pinned render

`data/2024-25/master/urc_injury_master_workbook_2024-25.xlsx` remains in place
only because `baseline_record.json` and `ledger.json` pin its path and exact
hash. Do not use it as the current human-review workbook.
