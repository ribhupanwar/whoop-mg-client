# Remaining icon artwork source audit — 2026-11-28

Baseline STRAP main: 6042129b00f7bc3cc31bada53a74ace9242a694f. #322 routed existing bundled assets without changing sport IDs. Owner requested remaining icon work against WHOOP IPA and Woop iOS ZIP.

## Inspected owner-supplied source
- iOS(7).zip contains Woop-ios-unsigned-4a3ef0e.ipa and an installation guide.
- The nested IPA contains 440 archive entries, including 114 PNG and 266 WebP files. Most loose images are band/charging or onboarding media (not verified activity glyphs).
- App Assets.car: 2,302,808 bytes; widget Assets.car: 763,336 bytes.
- WoopEngine-LICENSE.txt explicitly applies to original NOOP source and documentation only, not third-party components. It is not proof of rights to redistribute each artwork rendition.
- The separate official WHOOP 5.80.2 IPA was not available in this inspection. No compiled CAR renditions decoded, no proprietary art copied, and no exact-match visual claim.

## Remaining work
Use macOS asset catalog inspection or source asset manifests to identify rendition names, template status, scale and appearance variants; pair each with the exact screen usage. Record actual asset provenance and permission before redistributing. Prefer original independently drawn glyphs if rights are not established. Keep sport IDs, labels and fallback behavior unchanged. Cover all 137 current ActivityKind cases, imported sports, Health, More, battery/device, tab bar, charts, alarms and widgets. Compare real screenshots and ensure all mapped assets are actually bundled. Do not claim completion based on names alone.
