# whoop-mg-client

An independent, clean-room client for the biometric stream your own WHOOP
5.0 / MG strap exposes over Bluetooth LE. It reads history and live heart rate
locally, computes every metric on-device from published science, and never
talks to WHOOP's cloud, subscription or app. Not affiliated with WHOOP.

The repo holds three pieces:

| Path | What it is |
| --- | --- |
| `ios/` | SwiftUI app (iOS 18) — the actual client |
| `whoop/`, `*.py` | Python protocol/analysis reference used to verify the Swift ports |
| `tests/` | Python tests for the reference implementation |

No capture files, device identifiers or third-party source are committed;
`*.jsonl`, `*.csv` and the downloaded reference files are ignored on purpose.

## What the app does

- Scans for the strap, bonds, drains stored history and streams live HR
  (standard `0x2A37`) plus battery.
- Persists each capture locally, builds per-day metrics, and derives:
  HRV (RMSSD/SDNN/pNN50/lnRMSSD), resting HR, Karvonen zone minutes,
  Banister TRIMP strain (0–21), a baseline-relative recovery estimate,
  daytime and sleep stress shares, respiration (RSA), the band's unvalidated
  SpO₂ candidate, skin temperature, steps and detected sleep periods.
- Sleep analysis (duration, quiet-vs-movement efficiency, consistency,
  sleep stress), a four-class hypnogram estimate (awake/light/deep/REM from
  30 s epochs of HR, its variability, wrist movement and R-R breathing
  regularity, smoothed with an HMM and refused below 50 % HR coverage), and a
  bedtime coach built on the Kitamura 2016 sleep-debt model.
- Manual activity logging (sets × reps × load for lifts, minutes for cardio)
  and measured live sessions with zone-time allocation.
- Automatic run/walk/workout sessions: gait, step rate or a sustained HR rise
  open a session, 5 minutes is the floor, and detected sessions persist in the
  log so a walk from yesterday still shows on yesterday's screen.
- A VO₂ max estimate from Uth 2004 (15.3 × HRmax / HRrest): it uses a measured
  max HR when one is set and labels the age-predicted fallback, so the number
  is never passed off as a strap reading.
- An active-energy estimate (Keytel 2005 above a Mifflin–St Jeor basal rate,
  the pair NOOP and OpenStrap both use): minutes are priced only above 40 % of
  heart-rate reserve, a walk the gate refuses is priced by its measured
  cadence instead, and nothing is shown until weight and height are entered.
- A reorderable, hideable dashboard: the same row list feeds Home and the
  Dashboard tab, hidden rows keep their slot, and the arrangement is stored on
  the device.
- Optional Apple Health export (off by default): band-detected and live
  sessions become workouts with their real start, end and step count, keyed by
  an external UUID so a replay cannot duplicate them. No estimate is written
  and nothing is read back; HealthKit needs the capability in the signing
  profile.
- Honest gaps: anything the data cannot support shows an em dash with the
  reason, never a guess. The hypnogram is an approximation, not PSG-validated
  staging; the band's own sleep-state byte is never named. WHOOP's
  Recovery/Strain/Sleep scores and a validated SpO₂ remain deliberately absent.

## Protocol facts used

- Proprietary service `fd4b0001-cce1-4033-93ce-002d5875f58a`; commands are
  written to `fd4b0002`, notifications arrive on `fd4b0003` (command replies),
  `fd4b0004` (events), `fd4b0005` (data) and `fd4b0007` (memfault).
- Link order on real hardware: subscribe first, `CLIENT_HELLO` (0x91, body
  `[0x01]`, with response → just-works bond), `GET_DATA_RANGE` (0x22),
  `SEND_HISTORICAL_DATA` (0x16). Commands are spaced ~120 ms.
- Frames: `AA 01 <len u16 LE> <dir> <crc16/modbus LE>` + inner payload padded
  to a multiple of 4, with a trailing `crc32(zlib)` over the padded payload.
- History records are v18 (`0x2F`, 112 bytes): unix time, sub-second Q15,
  HR, up to four R-R intervals, accelerometer/gravity, step counter and
  cadence, activity class, aux/skin temperatures, sleep-state byte, SpO₂
  candidate byte and signal quality.
- Metadata `0x31` sub-opcode 2 signals history end; its token is echoed in
  `HISTORICAL_DATA_RESULT` (0x17, body `0x01 + token`).
- The step counter (u16 at record offset 49) is accumulated from its deltas,
  not read as an absolute total: it restarts at 0 on a re-sync, wraps at
  65,536 and sometimes catches up in one leap. Capture steps are labelled as
  the capture's steps, because a fresh session can start at 0 mid-day.

Implementations that follow the same published BLE behaviour are useful POC
references, but the code here is original; only interoperability facts were
taken from them.

## Build the app

Requirements: macOS with Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
cd ios
xcodegen generate
open Strap.xcodeproj
```

Select the `Strap` scheme and run on an iPhone (iOS 18+). The build has no
signing identity configured on purpose — set one in Xcode for a device build.
GitHub Actions (`.github/workflows/ios.yml`) builds the app, runs
`StrapTests` on a simulator and archives an unsigned IPA on every push.

Using the band: turn the iPhone's own Bluetooth pairing to the strap **off**
(BLE is one-central), put the strap on, open Settings → Strap → Connect, and
accept the pairing prompt on first write. The first drain can take up to two
minutes; live HR starts as soon as notifications are subscribed.

Wear the band overnight, then drain once in the morning: the app stages the
most recent detected sleep window on-device, so the Sleep tab shows the
hypnogram and deep/light/REM/awake minutes with no cloud round-trip. A window
with less than 50 % heart-rate coverage is refused and says why.

Two straps: Settings → Strap → **Find another band** lists every strap in
range (strongest signal first) and you tap the one on your wrist. The choice
is remembered by its Bluetooth peripheral identifier, so later connects go
straight to that band and ignore the other one.

## Python reference

```sh
pip install -r requirements.txt
python probe.py --seconds 20            # scan, bond, log notifications
python session.py --seconds 60          # drain stored history
python decode.py capture.jsonl --csv samples.csv
python report.py capture.jsonl --age 30 --sex male --rhr 55 --out dashboard.html
```

`report.py` computes the same estimators the Swift app uses and renders them
into a local HTML dashboard. Pass `--max-hr` only with a max HR you actually
measured.

## Scope and disclaimers

- Interoperability only. Nothing here copies WHOOP source, UI, assets or
  branding, and no cloud or subscription endpoint is used.
- Biometric estimates, not medical devices. Recovery, stress and strain are
  our own published-formula composites; they are not WHOOP's proprietary
  scores.
- The SpO₂ value is the band's own unvalidated candidate byte, summarised for
  curiosity only. It is never presented as clinical.
- The hypnogram is a rules-plus-HMM estimate from wrist channels, not PSG
  staging. "Restorative" here means our own deep+REM sum, not WHOOP's score.
- R22 deep-buffer NVM writes and the destructive `FORGET_BONDS` (0x0F)
  command are intentionally not implemented.
