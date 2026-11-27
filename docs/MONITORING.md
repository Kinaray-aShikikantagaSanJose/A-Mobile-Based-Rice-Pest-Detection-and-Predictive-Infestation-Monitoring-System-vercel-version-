# Palay Patrol: monitoring rules and calculations

This page describes what the system calculates and how. Each rule points to
the code that implements it. Anything marked **PROVISIONAL** has not been
confirmed by an agronomist or agriculturist. It is a working default that can
be changed, and must not be presented as established science.

---

## 1. Which records count

| Use | Records used |
|---|---|
| Official records, maps, hotspots, monthly/quarterly summaries, spread, exports | **Validated** observations only (`validation_status = 'validated'`) |
| Review queues | `pending` (the "Not Validated" queue) and `escalated` (the "To Be Validated" queue) |
| Treatment outcomes | Treatments whose follow-up observation was **reviewed** (see §7) |

Technicians see only their coverage area: the municipality, plus the covered
barangays if any are set. Agriculturists see every area. The server applies
this scope to every list, map and export (`observations.scope_sql`,
`observations.in_scope`), not just the screens.

Sample map data (the dashboard's "Preview with sample data") is generated in
the browser and is always labelled *SAMPLE DATA*. It is never sent to the
server and never used for spread, hotspots or exports.

## 2. Review workflow (one set of statuses)

```
submitted ──► pending  ("Not Validated": first review by the area's technician,
   │                    or by an agriculturist when no technician covers the area)
   │            ├─► validated   (level confirmed; diagnosis/guidance optional)
   │            ├─► returned    (photo unclear: the farmer retakes it)
   │            └─► escalated   ("To Be Validated": an agriculturist decides)
   │                              └─► validated (diagnosis AND guidance required)
   └──► no_pests (the model ran on a clear, relevant-looking photo and saw no insect at all)
```

* There are no extra statuses: "Not Validated" and "To Be Validated" are the
  names of the `pending` and `escalated` queues (`observations.QUEUE_*`).
* **Reviewer note.** Every validation needs the reviewer's own note: what was
  checked and why that level was chosen. It must be at least 10 characters
  and two real words, and must not be a copy of the diagnosis or guidance.
  It is kept in the review history (`scan_reviews.reviewer_note`). The farmer
  never sees it as advice. A return needs a clear reason (at least 6
  characters, two words). An escalation needs one sentence (at least 10
  characters, two words).
* **Diagnosis and guidance** are required when an agriculturist resolves an
  escalated case. They are optional otherwise.
* **Recommendations** are options the reviewer picks from the **approved**
  treatment library for the confirmed pest (`scan_recommendations`). They are
  stored separately from **treatments applied**, which record what the farmer
  actually did, on which date (`treatments`).
* **Follow-up** is due 7 days after the application date by default
  (`observations.FOLLOW_UP_DAYS`). A technician (in their area) or an
  agriculturist may change it. The date can't be before the application, and
  can't change once the follow-up has been sent.
* Every review and land type correction is logged in `scan_reviews` and in
  the activity log.

## 3. Infestation level (LOW / MEDIUM / HIGH)

The level on a record is always the **reviewer's decision**. The system only
suggests a level (`levels.suggest`):

1. **Count step.** If the photo was countable and thresholds exist for the
   pest and crop stage (falling back to the "any stage" row), then count ≥ `high_from` gives HIGH,
   ≥ `medium_from` gives MEDIUM, otherwise LOW. With no reliable count (or no
   thresholds), it starts at LOW.
2. **Damage step.** Each damage indicator the reviewer ticks raises the
   suggestion by one level, capped at HIGH.

**PROVISIONAL: all count thresholds.** The seeded rows in
`SQL/01_level_criteria_data.sql` are labelled "PhilRice/IRRI IPM Standard".
They are counts *per photo* by crop stage, though, and no matching published
table has been found to check them against. Since update 2026-12, every
threshold carries `provisional = true` until an agriculturist confirms it on
the Criteria page with the source used (`POST /dashboard/criteria/{id}/confirm`).
Editing the numbers makes a row provisional again. Suggestions based on a
provisional row say so. **PROVISIONAL:** the "+1 level per indicator" rule
is a design choice, not an agronomic standard.

### Damage indicators (checked by people, not by the model)

| Pest key | Indicators (exact values stored on the record) |
|---|---|
| brown_planthopper | Hopperburn (yellowing and drying patches) · Honeydew or sooty mold at the plant base · Plants wilting or lodging |
| green_leafhopper | Yellow-orange leaf discoloration (possible tungro) · Stunted plants · Reduced tillering |
| rice_bug | Empty or unfilled grains · Brown spots on grains · Offensive rice-bug odor in the field |
| rice_stem_borer | Deadhearts (dead central tiller) · Whiteheads (empty white panicles) · Bore holes or frass on stems |
| other | Visible feeding damage on leaves · Plants wilting or dying · Damage spread across much of the field |

The values stay in English, because they are stored. The apps show translated
labels (`indicator_labels`).

## 4. Photo checks done on upload (`app/detector.py`)

1. **Image relevance (screening only).** Measures the share of plant-coloured
   pixels: hue 35–170°, saturation ≥ 0.18, brightness ≥ 0.12, on a 256 px copy.
   A photo with less than **0.10** (**PROVISIONAL**, env
   `RELEVANCE_MIN_PLANT_FRACTION`) and no insect detected is marked
   `possibly_unrelated`. It goes to a technician like any other observation,
   with a warning. It is **never** closed as "no pests found" and **never**
   deleted automatically. A detected insect always counts as evidence that the
   photo is relevant. The cut-off was measured on the photos available (see
   `rice-pest-api/models/MODEL_SELECTION.md`). It is a colour heuristic, not
   a trained classifier.
2. **Pest detection.** The YOLO26s model runs on the photo and its mirror
   image. A box must reach 0.40 (or 0.65 without the mirror match). The pest
   is named only on solid evidence (`NAME_*` constants). Counting needs clear,
   separated insects (`COUNT_*`). These thresholds were chosen to prefer "not
   sure" over a wrong answer. They are **not** calibrated probabilities.
3. **Unverified class labels.** For this model family, outputs `rice_bug` and
   `rice_stem_borer` do not reliably match the pests they are named after
   (`MODEL_SELECTION.md`, "Class label check"). Their boxes are kept for the
   technician, but the pest is not named automatically
   (`DETECTOR_UNVERIFIED_CLASSES`).
4. **"No pests found"** needs all of the following: a relevant-looking photo;
   no quality problem (too dark < 40 brightness, washed out > 225, blurry
   Laplacian variance < 60); a short side of at least 480 px; and no box of
   any class above 0.12 in either orientation (**PROVISIONAL**, env
   `NO_PEST_MAX_SCORE`). In the new model's measurements, pest-free symptom
   photos scored mostly 0.001–0.10, and the lowest real pest photo scored 0.33.
   "Failed" and "uncertain" are never treated as pest-free.

## 5. Hotspots (`insights.hotspots`)

A barangay is an **active hotspot** if it has at least one validated, located
observation in the last **30 days** (`HOTSPOT_DAYS`, **PROVISIONAL**). Its
colour is the highest confirmed level among those records. The marker sits at
the average of their coordinates. The heatmap uses the same validated points,
weighted by count or by level.

## 6. Directional spread (`insights.spread`, `GET /analytics/spread`)

* **Periods:** two consecutive windows of 7, 14 or 30 days ending on the "To"
  date. Alternatively, a **custom range** ("From"–"To", 2–366 days) split
  into two halves; when the number of days is odd, the later half gets the
  extra day.
* **Cases used:** validated observations of the pest, with a **reliable
  location**. That means coordinates are present; the point is inside Antique
  (in a barangay polygon, or within 300 m of one); it is not marked
  outside/no-GPS; and the phone-reported accuracy, when present, is no worse
  than 150 m (`GEO_MAX_ACCURACY_M`). All other cases are left out and counted
  as "excluded".
* **Minimum:** at least **3** reliable cases in **each** period
  (`SPREAD_MIN_RECORDS`, **PROVISIONAL**). Below that the result is "Cannot
  be determined".
* **Centre:** the plain average of the coordinates in each period. Movement
  under 100 m counts as "no clear movement" (GPS noise).
* **Direction:** the compass point (8 sectors) of the bearing from centre 1
  to centre 2.
* **Barangay names:** a centre is named only if it lies at least 25 m inside a
  barangay polygon *and* that period has a case located in the same barangay.
  Otherwise that end "cannot be determined". The system never guesses a
  barangay. The polygons come from `antique_barangays.geojson` (PSGC-coded,
  simplified source maps).
* The output includes the observation period, the case counts per period,
  and the number excluded. It describes past reported cases. **It is not a
  forecast.**

## 7. Treatment outcomes (`insights.treatment_followups`)

An outcome is classified only from **comparable, reviewed evidence**:

| Situation | Outcome |
|---|---|
| No follow-up yet | `awaiting follow-up`, or `overdue` after the due date (pending) |
| Follow-up not reviewed yet | `follow-up in review` (pending) |
| Follow-up closed as "no pests found" by the model | `not comparable`: a pest-free photo of one spot is **not** proof that the treatment worked |
| A different pest confirmed on the follow-up | `not comparable` |
| Both reviewed, levels differ | `improved` / `worsened` |
| Both reviewed, same level, both countable, count changed ≥ 30 % | `improved` / `worsened` (`COUNT_CHANGE_PCT`, **PROVISIONAL**) |
| Both reviewed, same level otherwise | `no change` |

Pending outcomes stay pending. The summary counts only the three final
outcomes as "compared".

## 8. Quarterly patterns (`insights.quarterly_patterns`)

For each municipality and pest, the selected quarter is compared with the
previous quarter, using pest counts when any exist and record counts
otherwise. A change of ±25 % or more counts as increasing or decreasing
(`TREND_THRESHOLD_PCT`, **PROVISIONAL**). "Recurring" means records exist in
the same quarter of the previous year. These describe past records, not forecasts.
The weekly trend line on the dashboard (`trend_service.py`) is an ordinary
least-squares line through past weekly counts. It is labelled as a projection
of past records.

## 9. Land classification (`app/land.py`)

| Key | Meaning (to be confirmed by the agriculturist) |
|---|---|
| `upland` | Rice on sloping or high ground with naturally drained soil; no bunds or standing water; rain only |
| `rainfed_lowland` | Bunded, level paddies holding water part of the season from rain or run-off only |
| `irrigated_lowland` | Bunded, level paddies with an irrigation supply (canal, NIA/communal system, pump) |

* **Recorded** when the observation is made (required in the app), and kept
  in the offline outbox until it is sent.
* **Elevation hint:** ≥ **100 m** above sea level suggests upland
  (**PROVISIONAL** pending expert confirmation; env `UPLAND_MIN_ELEVATION_M`).
  Elevation can't tell rainfed from irrigated, so the person always picks.
* **Editable where authorized** (`PATCH /sync/scans/{id}/land-type`):
  * the submitter, while the observation is pending or returned;
  * a technician, for observations in their area (and their own);
  * an agriculturist, for any observation.
  Each change records who made it and when, and adds a `land_type_changed`
  entry to the history.
* **Filterable and exportable** on records, maps, spread and exports. Records
  saved before the field existed show as "Not recorded".

## 10. Paging and exports

Long lists are filtered, sorted and paged on the server (`limit`/`offset`,
with the id as tie-breaker so pages never overlap). They report the total
number of matching rows. CSV exports use **the same filters and sort** and
contain **every** matching row. Export headers and labels follow the chosen
language. Codes (ids, dates, coordinates) are unchanged.
