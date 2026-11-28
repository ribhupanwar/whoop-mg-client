import Foundation

/// Read-only calibration evidence. No production health metric, stage,
/// recovery or HRV/RHR consumes these candidates.
enum SensorCalibrationResearch {
    struct OpticalWindow: Equatable {
        let deviceID: String
        let firmware: String
        let startUnix: Int
        let sampleRateHz: Double
        let redADC: [Double]
        let infraredADC: [Double]
        // The caller must establish channel identity and simultaneous sample
        // alignment independently. A V22 numeric channel is NOT a wavelength.
        let mappingEvidenceID: String
        let railOrGapObserved: Bool
        let motionG: Double?
    }

    struct OpticalRatioEvidence: Codable, Equatable {
        let ratioOfRatios: Double
        let redACOverDC: Double
        let infraredACOverDC: Double
        let sampleCount: Int
        let sampleRateHz: Double
        let mappingEvidenceID: String
    }

    /// Standard ratio-of-ratios substrate, not SpO2. The ADC must be a verified
    /// positive DC-referenced intensity signal, not signed raw deltas or an
    /// unknown gain/offset. No caller is wired to unresolved WHOOP channels.
    /// Optical AC proxy is RMS about DC over a concurrent quiet window.
    static func opticalRatio(_ w: OpticalWindow) -> OpticalRatioEvidence? {
        guard !w.deviceID.isEmpty, !w.firmware.isEmpty,
              !w.mappingEvidenceID.isEmpty, !w.railOrGapObserved,
              w.startUnix >= 0, w.sampleRateHz.isFinite, (25...200).contains(w.sampleRateHz),
              let motion = w.motionG, motion.isFinite, (0...0.05).contains(motion),
              w.redADC.count == w.infraredADC.count,
              Double(w.redADC.count) >= w.sampleRateHz * 10,
              Double(w.redADC.count) <= w.sampleRateHz * 60 else { return nil }
        func modulation(_ codes: [Double]) -> Double? {
            guard codes.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 1e9 }) else { return nil }
            let dc = codes.reduce(0, +) / Double(codes.count)
            let ac = sqrt(codes.reduce(0) { $0 + ($1-dc)*($1-dc) } / Double(codes.count))
            let fraction = ac / dc
            // Provisional engineering bounds; reject flat or grossly
            // modulated signals rather than interpreting them as oxygen.
            return fraction.isFinite && (0.0001...0.2).contains(fraction) ? fraction : nil
        }
        guard let red = modulation(w.redADC), let infrared = modulation(w.infraredADC) else { return nil }
        let ratio = red / infrared
        guard ratio.isFinite, ratio > 0 else { return nil }
        return OpticalRatioEvidence(ratioOfRatios: ratio, redACOverDC: red,
            infraredACOverDC: infrared, sampleCount: w.redADC.count,
            sampleRateHz: w.sampleRateHz, mappingEvidenceID: w.mappingEvidenceID)
    }

    struct TemperatureChannel: Codable, Equatable {
        let source: String
        let eligibleSeconds: Int
        let decodedMedian: Double?
        let decodedMinimum: Double?
        let decodedMaximum: Double?
    }

    struct NightEvidence: Codable, Equatable {
        let observedQuietSeconds: Int
        let temperatureChannels: [TemperatureChannel]
        let oxygenRawByteCounts: [Int: Int]
        let oxygenCalibrationStatus: String
        let temperatureCalibrationStatus: String
    }

    /// Preserve field identity, count missingness separately, never combine
    /// auxiliary temperatures with the offset-65 skin candidate.
    static func nightEvidence(samples: [V18Sample], startUnix: Int, endUnix: Int) -> NightEvidence {
        let selected = HistoricalCaptureRecovery.merged(samples.filter {
            startUnix <= $0.unix && $0.unix < endUnix
        }).values.filter {
            guard $0.wearing, (35...220).contains($0.heartRate),
                  let motion = $0.dynamicAccelG, motion.isFinite,
                  (0...Hrv.restingQuietAccelG).contains(motion) else { return false }
            return true
        }
        func channel(_ source: String, _ field: (V18Sample) -> Double?) -> TemperatureChannel {
            let values = selected.compactMap(field).filter { $0.isFinite && (-20...80).contains($0) }
            let supported = values.count >= 300
            return TemperatureChannel(source: source, eligibleSeconds: values.count,
                decodedMedian: supported ? Stats.median(values) : nil,
                decodedMinimum: supported ? values.min() : nil,
                decodedMaximum: supported ? values.max() : nil)
        }
        var oxygen: [Int: Int] = [:]
        for row in selected {
            if let raw = row.spo2CandidateRaw, (0...255).contains(raw) { oxygen[raw, default: 0] += 1 }
        }
        return NightEvidence(observedQuietSeconds: selected.count, temperatureChannels: [
            channel("v18-offset65-decoded-candidate", { $0.skinTempC }),
            channel("v18-offset61-decoded-auxiliary", { $0.tempAux1C }),
            channel("v18-aux2-decoded-auxiliary", { $0.tempAux2C })
        ], oxygenRawByteCounts: oxygen,
        oxygenCalibrationStatus: "unverified wavelength mapping and reference calibration; no absolute SpO2 inferred",
        temperatureCalibrationStatus: "decoded candidate fields only; physical sensor mapping and conversion unverified")
    }

    struct TemperatureNight: Equatable {
        let dayID: String
        let deviceID: String
        let firmware: String
        let fieldSource: String
        let decodedMedian: Double
        let observedSeconds: Int
    }

    /// Relative decoded-field deviation only, from explicitly matched
    /// device/firmware/source prior nights. Not a clinical temperature.
    /// Caller provides prior nights, never the current or future night.
    static func temperatureDeviation(current: TemperatureNight,
                                     prior: [TemperatureNight]) -> Double? {
        func valid(_ n: TemperatureNight) -> Bool {
            !n.dayID.isEmpty && !n.deviceID.isEmpty && !n.firmware.isEmpty
                && !n.fieldSource.isEmpty && n.observedSeconds >= 300
                && n.decodedMedian.isFinite && (20...43).contains(n.decodedMedian)
        }
        guard valid(current) else { return nil }
        let groups = Dictionary(grouping: prior.filter {
            valid($0) && $0.dayID < current.dayID && $0.deviceID == current.deviceID
                && $0.firmware == current.firmware && $0.fieldSource == current.fieldSource
        }, by: { $0.dayID })
        let values = groups.values.compactMap { group -> Double? in
            guard let row = group.first, group.allSatisfy({ $0 == row }) else { return nil }
            return row.decodedMedian
        }
        guard values.count >= 7 else { return nil }
        return current.decodedMedian - Stats.median(values)
    }
}
