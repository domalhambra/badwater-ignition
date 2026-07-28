# Data Provenance & Verification

Because Plateworks Ignition is used to make fireline decisions, the table data is
treated as safety-critical. This document records exactly where each value came
from and how it was verified.

## Source

All Fine Fuel Moisture / Probability of Ignition data is transcribed from the
**NWCG Incident Response Pocket Guide (IRPG), PMS 461**, Fire Environment
section, pages 44–49:

- **Table A — Reference Fuel Moisture** (p. 45): 6 temperature bands × 21
  humidity bands.
- **Tables B / C / D — 1-hr Fuel Moisture Corrections** (pp. 46–48): each with an
  Unshaded section (8 aspect×slope rows) and a Shaded section (4 aspect rows),
  across 6 time bands × 3 elevation-delta (B/L/A) columns.
- **Probability of Ignition Table** (p. 44): Unshaded and Shaded variants, 9
  temperature bands × 16 fine-fuel-moisture columns.
- **Fine Fuel Moisture and Fire Behavior** interpretation (p. 49).

Relative-humidity elevation bands and station pressures are from the NWCG
temperature/RH/dew-point tables, **PMS 437**.

The IRPG and PMS 437 are U.S. government works in the public domain. Plateworks
Ignition is independent and **not affiliated with or endorsed by the NWCG.**

## Transcription method

1. The relevant IRPG pages were rendered from the official PDF at 300–600 DPI and
   rotated upright (the tables print in landscape).
2. A lead transcription was made cell-by-cell into a structured dataset.
3. **Adversarial verification:** each of the 9 table grids was independently
   re-transcribed by three separate vision agents, reading the high-resolution
   crops blind (without seeing the lead transcription).
4. All three independent reads plus the lead draft were reconciled
   **cell-by-cell** in code. Any cell where the four sources did not unanimously
   agree was flagged and adjudicated by eye against the source image.
5. The final values are additionally guarded by property tests
   (`Tests/PlateworksCoreTests/TableMonotonicityTests.swift`):
   - Table A is non-decreasing as humidity rises.
   - PIG is non-increasing as fine fuel moisture rises (both variants).
   - All values fall within the printed envelopes (RFM 1–14, corrections 0–6,
     PIG decades 10–100).

## Known quirks preserved faithfully

- **Table A row labels** print as `… 90-109, 109+`, overlapping at 109. Read as
  `90-109` and `110+`.
- **The `5*` asterisk** appears on the Shaded / 0800-0959 / L cell of Tables
  B, C, and D with no footnote printed on the table pages. The numeric value (5)
  is used; the asterisk is retained as metadata rather than guessed at.
- **Nighttime** uses the explicit p. 45 rule (Reference Fuel Moisture + 5). Table
  D annotates its 0800-0959 column "(+ night)"; that winter nuance is flagged for
  subject-matter review rather than silently assumed. See `IgnitionCalculator`.
- **Interpretation PIG bands** jump from "50 to 70%" to "80 to 100%". Since
  computed PIG is always a multiple of 10, "Very high" is extended to cover
  < 80% so 70 → Very high and 80 → Extreme, with no gap.

## Verification result

The 9 table grids were transcribed by **3 independent blind vision agents each
(27 transcriptions total)** and reconciled cell-by-cell against the lead draft (a
4th independent read).

| Grid | Cells | Independent reads agreeing | Conflicts |
|---|---|---|---|
| Table A (Reference Fuel Moisture) | 126 | draft + 2 agents on all cells¹ | 0 |
| PIG — Unshaded | 144 | draft + 3 agents | 0 |
| PIG — Shaded | 144 | draft + 3 agents | 0 |
| Table B — Unshaded / Shaded | 144 + 72 | draft + 3 agents | 0 |
| Table C — Unshaded / Shaded | 144 + 72 | draft + 3 agents | 0 |
| Table D — Unshaded / Shaded | 144 + 72 | draft + 3 agents | 0 |

**Zero genuine cell conflicts.** Eight of the nine grids were unanimous across the
draft and all three agents on every cell.

¹ For Table A, one of the three agents truncated its output at column 14 (it
transcribed 14 of 21 columns); on the 14 columns it produced it agreed with the
draft, and the other two agents plus the draft agreed on all 21. No agent ever
produced a *conflicting* value.

Two notable confirmations from the run:

- The **shaded ≥ unshaded PIG inversion at 30-39 °F / FFM 3** (shaded 80 vs
  unshaded 70) was read identically by all three independent agents — it is a
  genuine feature of the printed table, not a transcription slip, so it is
  preserved and deliberately not asserted away by a monotonicity test.
- The reconciliation ran deterministically in code (not by an agent), so the
  "agree / conflict" counts are exact.

