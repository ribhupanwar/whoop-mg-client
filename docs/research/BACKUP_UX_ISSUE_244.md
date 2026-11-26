# Backup settings clarity — issue #244

Verified against `ios/Strap/Analysis/DailyLocalBackup.swift` and `ios/Strap/MoreView.swift`:

- Backup archives currently live in the app's Application Support/daily-backups directory, not a user-selected Files folder.
- The backup interval is evaluated when the app is active; iOS does not guarantee a wall-clock background backup.
- Retention values 7 and 30 mean age in days, not number of copies. A zero retention value disables age-based expiry. The newest archive is protected.
- The existing subtitle 'retain last 3 local copies' is incorrect and must be removed.
- A folder picker requires a security-scoped folder bookmark and explicit authorization; never imply Files/iCloud export exists before implementation.

Acceptance: a separate Backup & Restore screen, explicit schedule/retention labels, choose-folder handling, restore safety, migration tests, and successful exact-head iOS CI. This document is a baseline for the implementation; it does not complete issue #244.
