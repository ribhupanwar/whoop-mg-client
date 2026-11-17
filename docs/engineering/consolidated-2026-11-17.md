# Consolidated engineering batch — 17 November 2026

## Data safety and delivery

Based on main d7dcf44; preserves 19fe2ee and d7dcf44. Compared
ui/dsta-dashboard-polish: its older persistence/correction paths remove safeguards
already present on main. No divergent branch merge or duplicate cherry-picks.
Raw SQLite rows, WAL and manual correction keys are retained. Failed writes keep
pending records and reopen only the database connection; retries are transactional.
All behavior changes require simulator tests and unsigned IPA archive success
on the verification branch before main is advanced.

## Live heart rate

Validated existing Type-40 layout against dsta's WhoopBluetoothManager and existing
protocol fixtures; no invented streaming opcodes or sensor meanings. Vendor and
standard notifications are armed; silent streams receive bounded rearming then
reconnection. Command deadlines prevent stuck write queues. An 806-second old
sample cannot appear live. The retained horizontal blue line and white endpoint
share the large display's fresh BPM and fixed vertical scale. Physical-band
stream longevity still requires a real connected device; CI covers parsing,
recovery decisions, stale rejection and simulator layout.

## Paired sleep investigation

User identifies the morning of 17 November 2026:

| | WHOOP | STRAP |
|---|---|---|
| Window | 16 Nov 23:28–17 Nov 07:32 | 16 Nov 23:42–17 Nov 07:38 |
| Asleep | 7:23 | approximately 7:24 |
| Awake | 0:41 | 0:31 |
| Light | 3:28 | 2:40 |
| Deep | 2:02 | 1:53 |
| REM | 1:53 | 2:52 |
| RHR / HRV | 76 bpm / 28 ms | 63 bpm / 28 ms |

Timezone and timestamped raw data for this night are not yet available. Earlier
uploaded CSV is a different night and must not be substituted. WHOOP stage sums
match 7:23 asleep and 8:04 in bed. STRAP displayed stages sum to 7:25 asleep,
7:56 including awake; minute rounding could explain the approximate 7:24 label.

Current STRAP onset requires five contiguous minutes of positive band sleep
state for evening candidates; it retains the beginning of that run. A sustained
explicit up-state trims wake time; mere stillness can extend an unconfirmed end.
Those gates can differ from WHOOP's undisclosed detector; they do not establish
why this particular night differs without raw state/motion/HR at the boundaries.

Next reproducible comparison must use exactly WHOOP's 23:28–07:32 bounds, with
explicit timezone, retained raw coverage and manual correction, then re-run all
staging/RHR/HRV/recovery. The edit fixes persist those bounds, load retained data
outside the in-memory window, reject older asynchronous results, and clear
obsolete nightly metrics rather than carry them into the new window.

STRAP RHR uses minimum contiguous 300-second quiet HR, not whole-night mean.
A synthetic regression demonstrates 63 minimum versus 76 whole-window mean,
without asserting that WHOOP uses the latter. A second regression verifies
28-ms alternating RR differences remain 28-ms RMSSD and log(28) lnRMSSD.

REM differs by 59 minutes, while the two windows' symmetric difference is only
20 minutes. Therefore boundaries alone cannot explain all 59 minutes under
unchanged per-second stage labels. Re-staging can also change interior labels:
STRAP uses session-relative features, latency priors and HMM continuity. No
REM threshold or RHR offset was tuned to these totals. Epoch-level aligned
raw data/reference labels are required before validating an estimator change.

## Health Monitor and zones

Personal ranges use at least seven distinct earlier qualified nights; current
and future nights cannot establish their own baseline. Recorded min/max is
explicitly a personal empirical range, not a fabricated medical normal range.
Temperature deviation uses matching source, sufficient quiet on-wrist coverage
and prior-night mean. Offset-65 temperature and oxygen remain candidates and
never gain a verified green check. Missing/legacy provenance stays unavailable
or calibrating. No baseline is synthesized from screenshot values.

Weekly zones retain disjoint live workouts outside a known raw-sync interval;
overlapping or legacy unknown coverage is not counted twice. Verified overnight
RHR can supply zone calibration even when awake quiet data is absent. Zone 0
means below the first reserve zone, configured maximum belongs to Zone 5,
and above-maximum readings are not mislabeled Zone 0. Long gaps and repeated
seconds do not create exercise duration.
