import Foundation

/// Energy from measured heart rate: the Keytel 2005 active rate above a
/// Mifflin–St Jeor basal rate. Both are population regressions, so every number
/// here is an ESTIMATE — never a strap measurement and never a clinical claim.
///
/// The same pair is used by the two independent clients this app was checked
/// against (NOOP's `Calories`, OpenStrap's `Calories.dailyEnergy`). The active
/// part is `Keytel(kcal/min) − BMR(kcal/min)` for minutes whose heart rate is
/// above the HR-flex gate; below the gate a minute burns basal only, which is
/// what keeps ordinary low-intensity daytime HR from being billed as exercise.
///
/// The gate is 40 % of heart-rate reserve — ACSM's moderate floor and the
/// correction OpenStrap made to an earlier 30 % gate. A walk whose HR never
/// reaches it is still priced when its measured cadence says the wearer was
/// walking, on the Tudor-Locke 2019 cadence↔MET anchors; a minute is never
/// billed twice.
enum Calories {
    /// One sex's Keytel active and Harris–Benedict resting coefficients.
    struct Coefficients {
        let activeHR: Double
        let activeWeight: Double
        let activeAge: Double
        let activeAlpha: Double
        /// Revised Harris–Benedict, kept for the article's own resting arm.
        let restingAlpha: Double
        let restingWeight: Double
        let restingHeight: Double
        let restingAge: Double
    }

    static let male = Coefficients(
        activeHR: 0.6309, activeWeight: 0.1988, activeAge: 0.2017, activeAlpha: -55.0969,
        restingAlpha: 88.362, restingWeight: 13.397, restingHeight: 479.9, restingAge: 5.677
    )

    static let female = Coefficients(
        activeHR: 0.4472, activeWeight: -0.1263, activeAge: 0.0740, activeAlpha: -20.4022,
        restingAlpha: 447.593, restingWeight: 9.247, restingHeight: 309.8, restingAge: 4.33
    )

    /// NOT a published set: the element-wise mean of the male and female rows,
    /// used for "Not set" so the app never guesses a sex it was not given. The
    /// weight term (0.1988 and −0.1263) has opposite signs, so this mean belongs
    /// to neither regression — the captions call the figure an estimate either way.
    static let unspecified = Coefficients(
        activeHR: 0.53905, activeWeight: 0.03625, activeAge: 0.13785, activeAlpha: -37.74955,
        restingAlpha: 267.9775, restingWeight: 11.322, restingHeight: 394.85, restingAge: 5.0035
    )

    /// ACSM puts moderate intensity at 40–59 % of heart-rate reserve. Below the
    /// gate Keytel's exercise regression has no fitted data, so those minutes
    /// burn basal only.
    static let moderateHRRFraction = 0.40
    /// Tudor-Locke 2019's moderate cadence floor in steps per minute.
    static let walkingCadenceFloor = 100.0
    /// 60 s/min × 4.184 kJ/kcal. Keytel publishes kJ/min; this turns it into kcal/s.
    static let kJPerMinToKcalPerS = 251.04

    static func resolve(_ sex: Sex) -> Coefficients {
        switch sex {
        case .male: return male
        case .female: return female
        case .unspecified: return unspecified
        }
    }

    /// Mifflin–St Jeor 1990, kcal per whole day. Nil without usable body data —
    /// an invented basal rate would flow silently into every energy figure.
    static func bmrKcalPerDay(
        weightKg: Double, heightCm: Double, age: Double, sex: Sex
    ) -> Double? {
        guard weightKg.isFinite, (30...300).contains(weightKg),
              heightCm.isFinite, (100...250).contains(heightCm),
              age.isFinite, (5...110).contains(age) else { return nil }
        let base = 10 * weightKg + 6.25 * heightCm - 5 * age
        let sexConstant: Double
        switch sex {
        case .male: sexConstant = 5
        case .female: sexConstant = -161
        case .unspecified: sexConstant = -78
        }
        return max(0, base + sexConstant)
    }

    /// The heart rate at or above which a minute is billed the Keytel active
    /// rate. Nil when the anchors cannot define one — a meaningless gate would
    /// bill every resting minute as exercise.
    static func gateHR(restingHR: Double, maxHR: Double) -> Double? {
        guard restingHR.isFinite, maxHR.isFinite,
              restingHR > 0, maxHR > restingHR else { return nil }
        return restingHR + moderateHRRFraction * (maxHR - restingHR)
    }

    /// Keytel 2005 active energy rate, kcal per second. Heart rate is capped at
    /// the wearer's max, as the article's own range requires.
    static func keytelKcalPerS(
        hr: Double, maxHR: Double, weightKg: Double, age: Double, sex: Sex
    ) -> Double {
        let c = resolve(sex)
        let capped = min(hr, maxHR)
        let kJPerMin = c.activeHR * capped + c.activeWeight * weightKg
            + c.activeAge * age + c.activeAlpha
        return max(0, kJPerMin) / kJPerMinToKcalPerS
    }

    /// Active energy over a capture's per-minute mean heart rates, each point
    /// standing for one minute. Nil without body data or a usable gate, so the
    /// caller can say what is missing instead of showing a fabricated zero.
    static func activeKcal(
        hrPerMinute: [Double],
        restingHR: Double,
        maxHR: Double,
        weightKg: Double,
        heightCm: Double,
        age: Double,
        sex: Sex
    ) -> Double? {
        guard let bmr = bmrKcalPerDay(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex),
              let gate = gateHR(restingHR: restingHR, maxHR: maxHR) else { return nil }
        let basalPerMinute = bmr / 1440
        var active = 0.0
        for hr in hrPerMinute where hr.isFinite && hr >= gate {
            let perMinute = keytelKcalPerS(
                hr: hr, maxHR: maxHR, weightKg: weightKg, age: age, sex: sex
            ) * 60
            active += max(0, perMinute - basalPerMinute)
        }
        return active
    }

    /// ACTIVE energy of one measured session. Above the gate the session is
    /// priced at its mean heart rate for its whole duration; below it a
    /// measured walking cadence prices it instead; otherwise the session spent
    /// nothing above rest and the answer is a real zero, not a missing value.
    ///
    /// Nil only when the body data or the heart-rate anchors are missing — the
    /// caller shows "—" and names what it needs.
    static func sessionActiveKcal(
        meanHR: Double?,
        steps: Int,
        minutes: Double,
        restingHR: Double,
        maxHR: Double,
        weightKg: Double,
        heightCm: Double,
        age: Double,
        sex: Sex
    ) -> Double? {
        guard minutes > 0, minutes.isFinite,
              let bmr = bmrKcalPerDay(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex),
              let gate = gateHR(restingHR: restingHR, maxHR: maxHR) else { return nil }
        let basalPerMinute = bmr / 1440
        if let meanHR, meanHR.isFinite, meanHR >= gate {
            let perMinute = keytelKcalPerS(
                hr: meanHR, maxHR: maxHR, weightKg: weightKg, age: age, sex: sex
            ) * 60
            return max(0, perMinute - basalPerMinute) * minutes
        }
        let cadence = Double(max(0, steps)) / minutes
        guard cadence >= walkingCadenceFloor else { return 0 }
        // Tudor-Locke 2019: 100/110/120/130 spm ≈ 3/4/5/6 MET, linear between,
        // clamped at the fitted ends.
        let met = min(6, 3 + 0.1 * (cadence - walkingCadenceFloor))
        return max(0, met - 1) * basalPerMinute * minutes
    }
}
