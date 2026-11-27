# Glossary: English · Filipino · Kinaray-a

> **Translation status:** the Filipino and Kinaray-a text in the apps, the
> notifications, the guide and the exports is **machine-assisted** and has
> **not been reviewed** by a language expert or an agriculturist. Ask a
> native Kinaray-a speaker from Antique, and the provincial agriculture
> office, to review it before you rely on it. Where a local name is not
> widely known, the English term is kept in brackets so a technician can
> match it.

Internal codes are never translated: `pending`, `escalated`, `rice_bug`,
`upland` and the rest stay as they are in the database and API. Only the
labels people see are translated.

| English (term used everywhere) | Filipino | Kinaray-a | Meaning |
|---|---|---|---|
| Observation | Obserbasyon | Obserbasyon | A photo and details from one field on one day |
| Not Validated (queue) | Hindi pa Na-validate | Wara pa Na-validate | Status `pending`: waiting for the first review |
| To Be Validated (queue) | Ive-validate pa | Pagavalidaron pa | Status `escalated`: an agriculturist decides |
| Validated | Na-validate | Na-validate | Pest, count and level confirmed by a reviewer |
| Returned | Ibinalik | Ginbalik | The farmer is asked for a new photo |
| No pests found | Walang nakitang peste | Wara it nakita nga peste | The model saw no insect on a clear, relevant photo |
| Possibly unrelated photo | Posibleng hindi kaugnay na litrato | Posible nga indi angot nga litrato | The photo may not show a crop; a technician checks it. **Not** the same as "no pests found" |
| Infestation level: LOW / MEDIUM / HIGH | MABABA / KATAMTAMAN / MATAAS | MANUBO / TUNGA-TUNGA / MATAAS | Confirmed by the reviewer |
| Provisional | Pansamantala | Temporaryo | Not yet confirmed by an expert |
| Reviewer note | Tala ng nagsuri | Tala it nag-usisa | The reviewer's own note on the decision (not advice to the farmer) |
| Diagnosis | Diagnosis | Diagnosis | What the problem is |
| Guidance | Payo | Tugon | What the farmer is advised to do |
| Recommendation | Rekomendasyon | Rekomendasyon | An option from the approved list, suggested by the reviewer |
| Treatment applied | Lunas na ginawa | Bulong nga ginhimo | What the farmer actually did, with the date |
| Follow-up | Follow-up | Follow-up | A new photo of the same field after a treatment (7 days by default) |
| Improved / No change / Worsened / Not comparable | Bumuti / Walang pagbabago / Lumala / Hindi maihahambing | Nagmayad / Wara it pagbag-o / Naglala / Indi maikumparar | Outcome of a treatment (see MONITORING.md §7) |
| Hotspot | Hotspot | Hotspot | A barangay with validated cases in the last 30 days |
| Direction of spread | Direksyon ng pagkalat | Direksyon it paglapta | Where validated cases moved between two periods (not a forecast) |
| Land type | Uri ng lupa | Klase it duta | Upland / rainfed lowland / irrigated lowland |
| Upland | Upland (mataas na lupa) | Upland (mataas nga duta) | |
| Rainfed lowland | Sahod-ulan na mababang lupa | Sahod-uran nga manubo nga duta | |
| Irrigated lowland | Patubig na mababang lupa | Ginapatubigan nga manubo nga duta | |
| Crop stage: Vegetative / Reproductive / Ripening | (kept in English, with a short explanation) | (kept in English, with a short explanation) | |
| Brown planthopper | Brown planthopper (kayumangging hanip) | Brown planthopper (kayumanggi nga hanip) | |
| Green leafhopper | Green leafhopper (berdeng leafhopper) | Green leafhopper (berde nga leafhopper) | |
| Rice bug | Atangya (rice bug) | Tiyangaw (rice bug) | |
| Rice stem borer | Aksip (stem borer) | Uod sa tangkay (stem borer) | |
| Municipality | Munisipyo | Banwa | |
| Barangay | Barangay | Barangay | |

Where the text lives:

| Text | File |
|---|---|
| Dashboard | `web-dashboard/src/i18n/parts/*.js` |
| Mobile app | `mobile-app/lib/l10n/parts/*.dart` |
| Notifications, spread texts, level reasons, export headers | `rice-pest-api/app/i18n.py` |
| Guide text, damage indicators, glossary | `rice-pest-api/app/i18n_guide.py` |

Tests check that every key has both languages with the same placeholders:
`tests/test_monitoring_update.py`, `web-dashboard/src/test/dashboard.test.jsx`
and `mobile-app/test/feature_update_test.dart`.
