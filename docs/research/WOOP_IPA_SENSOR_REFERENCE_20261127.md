# Woop IPA sensor reference — issue #252

User supplied iOS.zip containing Woop-ios-unsigned-4a3ef0e.ipa. IPA SHA-256: 3f06fe8b24a36861a92553ea27e9bbe949fabfd8d7d566dc7dbca37894c31c5c. Bundled WhoopProtocol_WhoopProtocol.bundle/whoop_protocol.json SHA-256: c187c53bed823e9b96299798a0eed5c4ff8ca1002ce7ad263a5063fa4056daf2. The binary is not committed.

## Source evidence
The bundled JSON explicitly uses frame-absolute historical offsets. Its V24 WHOOP 4.0 layout identifies red/IR ADCs at 68/70, skin temperature raw ADC at 72 (not centidegrees), and notes Gen5/MG V18 temperature at frame offset 73 in centidegrees. It does not supply a V18 field table or calibrated red/IR mapping. STRAP's existing V18Decoder uses inner-record offset 65 for centidegrees, auxiliary offsets 61/63 for deci-degrees, and candidate oxygen byte 74. Do not transplant frame offsets into the inner buffer or Gen4 calibration into Gen5.

The Mach-O symbol table contains StrandAnalytics skinTempFunnel, SkinTempBackfill.computeNight and resolveAnchor, nightlySkinTempC, SkinTempRelative, nightlySpo2CandidateMean, nightlySpo2CeilingMean, and WhoopStore LiveCapabilities.withoutCalibratedSpo2. Symbols support existence of these paths, not their exact implementation or clinical validity. No numeric calibration curve or paired reference data is established by this inspection.

## STRAP integration
Independent first-failure temperature funnel over canonical in-session seconds, exported in existing recovery JSON alongside a candidate-only oxygen summary. Existing 300-second minimum, motion and wear checks, source and baseline gates are preserved. A malformed nonnil out-of-band stored oxygen candidate cannot displace a valid candidate in the same-second replay selector. No oxygen value is promoted to measured SpO2. No firmware writes or historical data mutation.

## Remaining validation
Collect the new recovery JSON and sleep sensor CSV from a real night, compare persisted and recomputed temperature, inspect each rejection category, and verify temperature source, sleep reliability and 7 earlier-night baseline separately. For SpO2, require independently validated wavelength mapping and calibration or a verified device-produced percentage, with paired physical reference measurements. Do not infer calibration from symbols or candidate averages. Run exact-head protocol and native iOS CI before merge.
