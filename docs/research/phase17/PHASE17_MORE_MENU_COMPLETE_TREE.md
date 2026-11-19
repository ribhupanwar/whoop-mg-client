# Phase 17 — WHOOP More Menu Complete Forensic Hierarchy

**Classification:** `VERIFIED_ASSET` + `VERIFIED_BINARY`  
**Bundle Origin:** `WhoopMenu_WhoopMenu.bundle`  
**Localization Files:** `MainMenu.strings`, `SettingsDetailView.strings`, `DeviceSettings.strings`

---

## 1. Top Profile Header (`MyAccountHeader`)

- **User Avatar:** Circular profile image (56 pt diameter) with camera edit badge.
- **Member Name:** `ProximaNova-Bold` 18 pt, `#FFFFFF`.
- **Membership Status / Badge:**
  - Free Trial: `"Free Trial"`, Subtitle: `"Your trial ends on: <Date>"`, CTA: `"END FREE TRIAL"`.
  - Active: `"WHOOP MEMBER SINCE <Year>"`.
  - Expiring: `"MEMBERSHIP EXPIRES SOON"`, Subtitle: `"Your membership expires <Date>. Tap here to renew."`.

---

## 2. Complete Navigation Tree

### SECTION 1: `SHOP & GIFT` (`MainMenu.ShopAndGiftSectionHeader`)

| Menu Entry Name | String Key | Icon / Type | Subtitle / Description | Destination |
|---|---|---|---|---|
| **GIFT WHOOP** | `MainMenu.GiftShopTitle` | Gift box icon | `"Gift health with memberships, labs, and gift cards"` | Gifting Hub View |
| **PARTNER OFFERS** | `MainMenu.PartnerOffersTitle` | Tag / Badge icon | `"Explore curated perks for WHOOP Members"` | Partner Offers Web / In-app |
| **WHOOP ACCESSORIES** | `MainMenu.WhoopStoreTitle` | Shopping bag icon | `"Shop bands, apparel, and hardware accessories"` | In-App Store (`WhoopStore`) |
| **REFER A FRIEND** | `MainMenu.ReferAFriendTitle` | Share / Gift icon | `"Get a 1 month credit for each friend you refer"` | Refer-A-Friend Sheet |

---

### SECTION 2: `ACCOUNT & SETTINGS` (`MainMenu.AccountAndSettingsSectionHeader`)

#### 1. **MY ACCOUNT** (`MainMenu.MyAccountTitle`)
- Chevron navigation leading to `SettingsDetailView` (`MyAccount` group):
  - **WHOOP MEMBERSHIP** (`SettingsDetailView.MyAccount.MembershipAndBilling.Title`): Manage subscription, plan tier.
  - **MEMBERSHIP EXTENSIONS** (`SettingsDetailView.MyAccount.NativeExtendMembership.Title`): `"Add months to your membership and save"`.
  - **PAYMENT METHOD** (`SettingsDetailView.MyAccount.PaymentMethod.Title`): Card on file, expiration alerts.
  - **EARN WHOOP CREDITS** (`SettingsDetailView.MyAccount.EarnSection.Title`): Referral balance, credits.
  - **PERSONAL INFORMATION** (`SettingsDetailView.MyAccount.PersonalInformation.Title`): Name, DOB, sex, height, weight.
  - **PROFILE INFORMATION** (`SettingsDetailView.MyAccount.ProfileInformation.Title`): Username, bio, public toggle.
  - **REDEEM GIFT EXTENSION** (`SettingsDetailView.MyAccount.RedeemGiftExtension.Title`): Promo / gift code input.
  - **CHANGE PASSWORD** (`SettingsDetailView.MyAccount.ChangePassword.Title`): Password reset modal.
  - **EMAIL** (`SettingsDetailView.MyAccount.ChangeEmail.Title`): Update account email.
  - **PAUSE MEMBERSHIP** / **RESUME MEMBERSHIP**
  - **CANCEL MEMBERSHIP** (`SettingsDetailView.MyAccount.CancelMembership.Title`): Retention cancellation flow.

#### 2. **DEVICE SETTINGS** (`MainMenu.DeviceSettingsTitle`)
- Chevron navigation leading to `DeviceSettingsView`:
  - **Connected Device Card:** Image of band, connection status (`"CONNECTED TO"` / `"NOT CONNECTED TO"`), last sync time (`"LAST SYNC"`), battery level percentage.
  - **Hardware Name:** `"WHOOP MG"` (`DeviceSettings.maverickName`), `"WHOOP 5.0"` (`DeviceSettings.gooseName`), `"WHOOP 4.0"` (`DeviceSettings.Harvard`).
  - **Broadcast Heart Rate:** Toggle switch to enable BLE standard HR profile broadcasting.
  - **Device Location:** Wrist placement (`"Left wrist"`, `"Right wrist"`).
  - **FIRMWARE CHECK:** Current version, update status (`"CHECKING NOW"`, `"UP TO DATE"`, `"UPDATE AVAILABLE"`).
  - **Advanced Device Actions:**
    - `"REBOOT DEVICE"` (`DeviceAdvancedSettings.REBOOT DEVICE`)
    - `"POWER CYCLE"` (`DeviceAdvancedSettings.POWER CYCLE`)
    - `"RECALIBRATE OPTICAL SENSOR"`
    - `"RECONFIGURE BATTERY"`
    - `"PAIR A DEVICE"` / `"UNPAIR DEVICE"`
    - `"EMAIL DIAGNOSTIC DATA"`
    - `"ERASE DEVICE DATA"`

#### 3. **ACTIVITY SETTINGS** (`MainMenu.ActivitySettingsTitle`)
- Auto-detection sensitivity toggles (Running, Cycling, Walking, Gym, etc.).
- GPS tracking permissions and live activity options.

#### 4. **JOURNAL** (`MainMenu.JournalTitle`)
- Customize daily journal questions (behaviors: alcohol, caffeine, screen time, supplements, meditation, etc.).

#### 5. **INTEGRATIONS** (`MainMenu.IntegrationsTitle`)
- Apple HealthKit sync permissions (Read/Write HR, Sleep, Workouts).
- Strava sync.
- TrainingPeaks, Garmin, Wahoo integrations.

#### 6. **EXPORT WHOOP DATA** (`MainMenu.DataExportTitle`)
- Export historical metrics to CSV / JSON / Health report.

#### 7. **NOTIFICATIONS** (`MainMenu.NotificationSettingsTitle`)
- Push notification preferences (Sleep need, Bedtime reminder, Daily summary, Strain targets, Team chat).

#### 8. **AI SETTINGS** (`MainMenu.WHOOPCoach`)
- WHOOP Coach / AI insights preferences, voice interaction, personalized recommendations.

#### 9. **HORMONAL INSIGHTS / PREGNANCY INSIGHTS**
- Menstrual cycle coaching, pregnancy tracking phases, trimester settings.

#### 10. **HIDE METRICS** (`MainMenu.StealthMode`)
- Privacy toggle to blur or conceal live heart rate and strain in public spaces.

#### 11. **PRIVACY SETTINGS** (`MainMenu.PrivacySettingsTitle`)
- Data sharing permissions, team leaderboard visibility, analytics opt-out.

#### 12. **DIGITAL WHOOP LABS** (`MainMenu.WhoopLabsTitle`)
- Beta features, experimental biomarker tracking, study participation.

---

### SECTION 3: `SUPPORT` (`MainMenu.SupportSectionHeader`)

| Menu Entry Name | String Key | Destination | Notes |
|---|---|---|---|
| **MEMBERSHIP SERVICES** | `MainMenu.MembershipServicesTitle` | In-app Help / Support Chat | Zendesk / StreamChat integration |
| **TUTORIALS** | `MainMenu.TutorialsTitle` | Submenu | Strap Tutorial, How to Wear, Pairing Mode |
| **ABOUT** | `MainMenu.AboutTitle` | Submenu | Privacy Policy, Terms of Use, Open Source Licenses, Patents, Regulatory Labels |
| **LOGOUT** | `MainMenu.LogoutTitle` | Confirmation Dialog | `"Are you sure you want to log out?"` |
| **APP VERSION / BUILD** | `MainMenu.BuildAndVersionText` | Footer label | `"APP VERSION: 5.75.0 (BUILD 738478)"` |

---

## 3. STRAP Implementation & Parity Strategy

For STRAP:
1. **Section Structure:** Implement identical 3-section layout (`SHOP & GIFT` / `ACCOUNT & SETTINGS` / `SUPPORT`).
2. **Branding Translation:** Replace `"WHOOP"` with `"STRAP"`.
3. **Truth in Advertising:**
   - Active Working Settings: `DEVICE SETTINGS` (BLE reconnect, battery, firmware, wrist position), `EXPORT DATA` (GPX, FIT, CSV), `APP SETTINGS`, `ABOUT`.
   - Unsupported / Cloud-only WHOOP Services (e.g. `GIFT WHOOP`, `STORE`, `WHOOP LABS`): Mark with a subtle `"STRAP Local"` tag or appropriate informational sheet explaining local-only functionality, preventing false promises.
