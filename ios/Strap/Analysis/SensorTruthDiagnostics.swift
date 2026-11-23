import Foundation
import CryptoKit

/// Sensor Truth & Data Integrity Verification System.
/// Establishes whether STRAP receives, decodes, timestamps, stores, and analyzes
/// WHOOP sensor data with complete mathematical fidelity.
///
/// Designed to provide privacy-preserving diagnostics without exporting raw biometric PII.
public struct SensorTruthReport: Codable, Equatable {
    public struct TransmissionStats: Codable, Equatable {
        public let rawPacketsReceived: Int
        public let rawBytesReceived: Int
        public let framingChecksumFailures: Int
    }

    public struct DecodingStats: Codable, Equatable {
        public let framesReassembled: Int
        public let samplesDecoded: Int
        public let undecodableFrames: Int
        public let droppedBytes: Int
        public let declaredRRBeats: Int
        public let validRRBeats: Int
        public let rejectedRRBeats: Int
        public let rejectedRRReasons: [String: Int]
    }

    public struct PersistenceStats: Codable, Equatable {
        public let uniqueRecordsPersisted: Int
        public let duplicateRecordsFiltered: Int
        public let timestampCollisionsResolved: Int
        public let missingRecordIndexGaps: Int
        public let missingRecordIndexCount: Int
        public let timestampGaps: Int
        public let rtcDiscontinuities: Int
    }

    public struct AnalysisStats: Codable, Equatable {
        public let recordsQueried: Int
        public let wearingSamples: Int
        public let offWristSamples: Int
        public let quietMotionSamples: Int
        public let swsDeepSleepSamples: Int
        public let acceptedNNBeats: Int
        public let rejectedEctopicBeats: Int
        public let rejectedSeedBeats: Int
        public let consecutiveNNPairs: Int
        public let calculatedRMSSD: Double?
        public let calculatedRHR: Double?
    }

    public struct QualityMetrics: Codable, Equatable {
        public let decodeSuccessRate: Double
        public let recordContiguityRate: Double
        public let rrAcceptanceRate: Double
        public let wearingQualityRate: Double
    }

    public let generatedAt: Date
    public let windowStartUnix: Int?
    public let windowEndUnix: Int?
    public let durationSeconds: Int
    public let transmission: TransmissionStats
    public let decoding: DecodingStats
    public let persistence: PersistenceStats
    public let analysis: AnalysisStats
    public let quality: QualityMetrics
    public let provenanceDigest: String
}

public enum SensorTruthDiagnostics {
    /// Audits a collection of decoded samples and pipeline telemetry to generate
    /// an end-to-end Sensor Truth and Data Integrity Report.
    public static func audit(
        samples: [V18Sample],
        rawPacketsCount: Int = 0,
        rawBytesCount: Int = 0,
        droppedBytes: Int = 0,
        undecodableFrames: Int = 0,
        checksumFailures: Int = 0,
        duplicatesCount: Int = 0,
        swsDeepEpochs: [ClosedRange<Int>] = []
    ) -> SensorTruthReport {
        let sortedSamples = samples.sorted { $0.unix < $1.unix }
        let windowStart = sortedSamples.first?.unix
        let windowEnd = sortedSamples.last?.unix
        let duration = (windowStart != nil && windowEnd != nil) ? max(0, windowEnd! - windowStart! + 1) : 0

        // 1. Transmission & Decoding
        let declaredRRBeats = sortedSamples.reduce(0) { $0 + $1.rrIntervalsMS.count }
        var validRRBeats = 0
        var rejectedRRBeats = 0
        var rejectionReasons: [String: Int] = [:]

        for sample in sortedSamples {
            for rr in sample.rrIntervalsMS {
                if (V18Decoder.minRRMS...V18Decoder.maxRRMS).contains(rr) {
                    validRRBeats += 1
                } else {
                    rejectedRRBeats += 1
                    rejectionReasons["outOfPlausibleRange", default: 0] += 1
                }
            }
        }

        // 2. Persistence & Sequence Analysis
        var uniqueIndices = Set<UInt32>()
        var duplicateRecordIndexCount = 0
        var missingRecordIndexGaps = 0
        var missingRecordIndexCount = 0
        var timestampGaps = 0
        var rtcDiscontinuities = 0

        var previousRecordIndex: UInt32?
        var previousUnix: Int?
        var previousSubsecQ15: Int?

        var timestampCollisionCount = 0
        var seenUnixTimestamps = Set<Int>()

        for sample in sortedSamples {
            let idx = sample.header.recordIndex
            let u = sample.unix
            let sub = sample.header.subsecQ15

            if !seenUnixTimestamps.insert(u).inserted {
                timestampCollisionCount += 1
            }

            if !uniqueIndices.insert(idx).inserted {
                duplicateRecordIndexCount += 1
            }

            if let prevIdx = previousRecordIndex {
                if idx > prevIdx + 1 {
                    missingRecordIndexGaps += 1
                    missingRecordIndexCount += Int(idx - prevIdx - 1)
                }
            }

            if let prevU = previousUnix {
                if u > prevU + 1 {
                    timestampGaps += 1
                    // Check if this is an RTC rollover anomaly:
                    // If recordIndex is strictly sequential but unix jumped by 2 seconds with subsecQ15 rolling over,
                    // it is an internal clock step.
                    if let prevIdx = previousRecordIndex, idx == prevIdx + 1,
                       let prevSub = previousSubsecQ15, prevSub > 25000 && sub < 5000 {
                        rtcDiscontinuities += 1
                    }
                } else if u < prevU {
                    rtcDiscontinuities += 1 // Backwards clock step
                }
            }

            previousRecordIndex = idx
            previousUnix = u
            previousSubsecQ15 = sub
        }

        // 3. Analysis Consumption & Biometric Provenance
        let wearingSamples = sortedSamples.filter { $0.wearing }
        let offWristSamples = sortedSamples.count - wearingSamples.count
        let quietSamples = wearingSamples.filter { ($0.dynamicAccelG ?? Double.infinity) <= Hrv.restingQuietAccelG }

        // SWS Deep sleep samples
        let swsSamples: [V18Sample]
        if !swsDeepEpochs.isEmpty {
            swsSamples = sortedSamples.filter { sample in
                swsDeepEpochs.contains { $0.contains(sample.unix) }
            }
        } else {
            // Check sleepState from band v18 or staging if available
            swsSamples = sortedSamples.filter { $0.sleepState == 2 }
        }

        // Detailed NN beat provenance across quiet contiguous runs
        let quietRuns = Hrv.contiguousRuns(quietSamples)
        var totalRawBeatsInQuiet = 0
        var acceptedNNBeats = 0
        var rejectedEctopicBeats = 0
        var rejectedSeedBeats = 0
        var consecutiveNNPairs = 0
        var squaredDiffs = 0.0

        for run in quietRuns {
            var previous: Double?
            var recent: [Double] = []
            var seedCandidate: Double?
            var rejectedRun = 0

            for sample in run {
                let rrs = sample.rrIntervalsMS.map(Double.init)
                totalRawBeatsInQuiet += rrs.count
                if rrs.isEmpty {
                    previous = nil; recent.removeAll(); seedCandidate = nil; rejectedRun = 0
                    continue
                }
                for value in rrs {
                    guard value >= Double(V18Decoder.minRRMS) && value <= Double(V18Decoder.maxRRMS) else {
                        previous = nil; recent.removeAll(); seedCandidate = nil; rejectedRun = 0
                        continue
                    }
                    if recent.isEmpty {
                        guard let pending = seedCandidate else {
                            seedCandidate = value
                            continue
                        }
                        let midpoint = Stats.median([pending, value])
                        if abs(value - pending) > Hrv.nnMaxDeviation * midpoint {
                            rejectedSeedBeats += 1
                            seedCandidate = value
                            continue
                        }
                        acceptedNNBeats += 2
                        recent.append(pending)
                        recent.append(value)
                        previous = value
                        let delta = value - pending
                        squaredDiffs += delta * delta
                        consecutiveNNPairs += 1
                        seedCandidate = nil
                    } else {
                        let reference = Stats.median(recent)
                        if abs(value - reference) > Hrv.nnMaxDeviation * reference {
                            rejectedEctopicBeats += 1
                            rejectedRun += 1
                            if rejectedRun >= Hrv.nnReferenceBeats {
                                recent.removeAll()
                                previous = nil
                                seedCandidate = nil
                                rejectedRun = 0
                            }
                            continue
                        }
                        acceptedNNBeats += 1
                        recent.append(value)
                        if recent.count > Hrv.nnReferenceBeats { recent.removeFirst() }
                        rejectedRun = 0
                        if let prev = previous {
                            let delta = value - prev
                            squaredDiffs += delta * delta
                            consecutiveNNPairs += 1
                        }
                        previous = value
                    }
                }
            }
        }

        let calculatedRMSSD: Double? = consecutiveNNPairs > 0 && acceptedNNBeats >= Hrv.minCleanBeats
            ? sqrt(squaredDiffs / Double(consecutiveNNPairs))
            : nil

        let calculatedRHR = Hrv.restingHeartRate(sortedSamples, windowS: 60)

        // 4. Quality Rates
        let totalReceived = max(1, rawPacketsCount > 0 ? rawPacketsCount : sortedSamples.count)
        let decodeSuccessRate = Double(sortedSamples.count) / Double(totalReceived)
        let expectedRecords = (previousRecordIndex != nil && sortedSamples.first != nil)
            ? max(1, Int(previousRecordIndex! - sortedSamples.first!.header.recordIndex + 1))
            : max(1, sortedSamples.count)
        let recordContiguityRate = Double(sortedSamples.count) / Double(expectedRecords)
        let rrAcceptanceRate = declaredRRBeats > 0 ? Double(validRRBeats) / Double(declaredRRBeats) : 1.0
        let wearingQualityRate = sortedSamples.count > 0 ? Double(wearingSamples.count) / Double(sortedSamples.count) : 0.0

        // 5. Privacy-Preserving Provenance Digest (SHA-256 of sequence properties)
        var hasher = SHA256()
        let digestPayload = "records:\(sortedSamples.count)|nn:\(acceptedNNBeats)|rmssd:\(calculatedRMSSD ?? 0)|rhr:\(calculatedRHR ?? 0)|indices:\(sortedSamples.first?.header.recordIndex ?? 0)-\(sortedSamples.last?.header.recordIndex ?? 0)"
        hasher.update(data: Data(digestPayload.utf8))
        let digestString = hasher.finalize().map { String(format: "%02x", $0) }.joined()

        return SensorTruthReport(
            generatedAt: Date(),
            windowStartUnix: windowStart,
            windowEndUnix: windowEnd,
            durationSeconds: duration,
            transmission: SensorTruthReport.TransmissionStats(
                rawPacketsReceived: rawPacketsCount > 0 ? rawPacketsCount : sortedSamples.count,
                rawBytesReceived: rawBytesCount,
                framingChecksumFailures: checksumFailures
            ),
            decoding: SensorTruthReport.DecodingStats(
                framesReassembled: sortedSamples.count + undecodableFrames,
                samplesDecoded: sortedSamples.count,
                undecodableFrames: undecodableFrames,
                droppedBytes: droppedBytes,
                declaredRRBeats: declaredRRBeats,
                validRRBeats: validRRBeats,
                rejectedRRBeats: rejectedRRBeats,
                rejectedRRReasons: rejectionReasons
            ),
            persistence: SensorTruthReport.PersistenceStats(
                uniqueRecordsPersisted: uniqueIndices.count,
                duplicateRecordsFiltered: duplicateRecordIndexCount + duplicatesCount,
                timestampCollisionsResolved: timestampCollisionCount,
                missingRecordIndexGaps: missingRecordIndexGaps,
                missingRecordIndexCount: missingRecordIndexCount,
                timestampGaps: timestampGaps,
                rtcDiscontinuities: rtcDiscontinuities
            ),
            analysis: SensorTruthReport.AnalysisStats(
                recordsQueried: sortedSamples.count,
                wearingSamples: wearingSamples.count,
                offWristSamples: offWristSamples,
                quietMotionSamples: quietSamples.count,
                swsDeepSleepSamples: swsSamples.count,
                acceptedNNBeats: acceptedNNBeats,
                rejectedEctopicBeats: rejectedEctopicBeats,
                rejectedSeedBeats: rejectedSeedBeats,
                consecutiveNNPairs: consecutiveNNPairs,
                calculatedRMSSD: calculatedRMSSD,
                calculatedRHR: calculatedRHR
            ),
            quality: SensorTruthReport.QualityMetrics(
                decodeSuccessRate: decodeSuccessRate,
                recordContiguityRate: recordContiguityRate,
                rrAcceptanceRate: rrAcceptanceRate,
                wearingQualityRate: wearingQualityRate
            ),
            provenanceDigest: digestString
        )
    }

    /// Serializes the SensorTruthReport into a privacy-preserving JSON export.
    /// Excludes raw biometric measurements, location, or user credentials.
    public static func generatePrivacyPreservingExport(report: SensorTruthReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}
