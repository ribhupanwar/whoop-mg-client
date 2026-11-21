# WHOOP activity icon provenance

Audited all fetched branch histories of `ribhupanwar/whoop-mg-client` and `ribhupanwar/dsta`. At inspection the repositories had 95 and 36 branch heads, spanning 1,355 and 1,085 reachable commits respectively. The audit covers reachable Git history. Files that were never tracked or were removed from all reachable refs are outside that evidence.

| Evidence | Result |
|---|---|
| STRAP commit `b156517` | Present. Introduces Phase 17 UI forensic reports. |
| `docs/research/whoop_5802/symbols_5802.json` | 301 records, 300 distinct symbol names. |
| `docs/research/phase17/ghidra_ui_symbols.json` | 1,795 records, 928 distinct names. Together the two exports contain 1,228 distinct names. These include implementation symbols and labels. |
| `docs/research/whoop_5802/strings_5802.json` | 474 string records. |
| `sports.json`, `WhoopUIForensicExtractor.java`, `Whoop5802Extractor.java` | No matching tracked path in the fetched histories. The STRAP Phase 17 report names `WhoopUIForensicExtractor.java` without supplying its source. |
| STRAP and DSTA asset catalogs | No sport-specific asset in the tracked image history. DSTA has a PulseForge app icon. STRAP has existing band and wordmark catalogs. |
| `domain_strings_all.json` | The exact evidenced CDN activity image is `nap.png`. An HTTP retrieval verified a 60 × 60 grayscale PNG with alpha. No redistribution grant was established. The asset is excluded from source and app packaging. |
| WHOOP workout developer documentation | 122 distinct legacy sport IDs. Sleep and Nap have separate evidence rows without invented sport IDs. |

## Existing non-activity artwork

STRAP commit `3541f1005c6bf82cab1bde4d6a50ba8e70790dbc` introduced the two asset sets below. Xcode declares universal 1×, 2× and 3× PNG variants. The catalog records format and scale and does not establish licensing.

| Catalog | RGBA raster sizes | This change |
|---|---|---|
| `WhoopWordmark.imageset` | 160 × 26, 320 × 52, 480 × 78 px | STRAP wordmark remains on Home. |
| `WhoopBandHardware.imageset` | 250 × 277, 500 × 555, 750 × 832 px | Existing references stay in place. |

## Integration

The accompanying TSV lists all documented legacy IDs and two sleep-related references. The app maps 53 legacy IDs to existing STRAP activity kinds. Its runtime registry resolves documented IDs and modern sport names without changing the original stored activity names. Unknown IDs use the Other icon as presentation only. Existing archived workouts decode when an ID is absent. A later API refresh preserves an ID already saved.

Home uses the same activity kind icons as manual selection and editing. The fallback icon set distinguishes Weightlifting and Strength Trainer, and gives Yoga, Pilates, Meditation, Elliptical, Functional Fitness, Basketball and Football distinct glyphs. Sleep and Nap retain their own glyphs. Icons render with Apple system symbols using STRAP’s tint and shared row layout. New original WHOOP icons bundled total zero. Other navigation, alarm and device glyphs retain their established implementations because the evidence did not establish authorized replacements.

Sources [WHOOP workout sport table](https://developer.whoop.com/docs/developing/user-data/workout/#whoop-sports) · [WHOOP API terms](https://developer.whoop.com/api-terms-of-use/) · [STRAP Phase 17 icon report](https://github.com/ribhupanwar/whoop-mg-client/blob/main/docs/research/phase17/PHASE17_ICON_INVENTORY.md) · [DSTA](https://github.com/ribhupanwar/dsta)

## Public-source follow-up

Public code and web searches found five CDN mappings in the WhoopAPI-Wrapper example output and the Weightlifting mapping in the Whoop-Data-Access API guide. Rowing uses the filename stem `crew`. The public CDN returned all six PNG/SVG pairs and the previously tracked Nap PNG. The bucket index returned HTTP 403. No dated public archive result supplied the missing filename-to-ID mappings. No authenticated private endpoints were queried. [Wrapper examples](https://github.com/colinmacon/WhoopAPI-Wrapper) · [Weightlifting API example](https://github.com/guglielmofonda/Whoop-Data-Access/blob/main/WHOOP_API_GUIDE.md)

| Activity asset count | Result |
|---|---|
| FOUND | 7 evidenced activity icon families, including Nap, with 13 published file URLs. |
| VERIFIED | 13 valid files from the canonical CDN, comprising seven 60 × 60 transparent PNGs and six SVGs with a 32 × 32 viewBox. Each object has a distinct SHA-256. PNG and SVG variants are grouped by family. |
| LICENSED | 0 activity families with confirmed redistribution rights for STRAP. |
| INTEGRATED | 0 recovered WHOOP activity files. STRAP maps 53 legacy IDs to existing activity kinds using Apple platform symbols. |
| MISSING | 116 of the 122 legacy IDs have no verified original icon mapping in this audit. Sleep is separate and no original Sleep file was verified. |

The Weightlifting PNG depicts a white athlete holding an overhead barbell and is visually consistent with the supplied WHOOP Home row. The Running PNG is a dark runner silhouette. The supplied Running row is partly covered by navigation, so exact in-app tint and glyph identity cannot be established. The samples for Baseball, Basketball, Cycling, Rowing and Nap have no unobstructed comparison tile in the supplied Home references. The file inventory preserves direct URLs and content hashes without bundling the bytes.

NOOP has its own typed sport icon catalog. Its current PolyForm Noncommercial license does not establish reuse rights for WHOOP artwork. OpenStrap's standalone icon repository describes its own 512 px light/dark WebP illustrations. The standalone package had no root LICENSE at inspection, and OpenStrap Edge's AGPL does not establish rights to WHOOP art. [NOOP sport icons](https://github.com/ryanbr/noop/blob/main/Packages/StrandDesign/Sources/StrandDesign/SportIcon.swift) · [NOOP license](https://github.com/ryanbr/noop/blob/main/LICENSE) · [OpenStrap icons](https://github.com/OpenStrap/icons) · [OpenStrap Edge license](https://github.com/OpenStrap/edge/blob/main/LICENSE)

WHOOP's developer Design Guidelines identify official wordmark and puck distributions and minimum widths of 100 px and 30 px. The static puck is a brand mark. The in-app refresh animation, Health Monitor pictograms and navigation states remain unresolved as reusable files. The developer branding offer is subject to its terms and is not evidence of authorization to recreate the WHOOP app in STRAP. [Design guidelines](https://developer.whoop.com/docs/developing/design-guidelines/) · [WHOOP developer terms](https://developer.whoop.com/api-terms-of-use/)
