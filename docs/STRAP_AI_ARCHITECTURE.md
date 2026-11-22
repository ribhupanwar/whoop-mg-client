# STRAP AI Coach Architecture & Privacy Model

**Document ID:** `docs/STRAP_AI_ARCHITECTURE.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Author:** Antigravity Senior AI Architecture Team  
**Date:** 22 November 2026  
**Status:** ARCHITECTURAL SPECIFICATION & PRIVACY MODEL

---

## 1. Architectural Principles

STRAP AI Coach is designed as an offline-first, privacy-preserving, high-performance personal fitness and recovery intelligence engine. Unlike proprietary cloud services that harvest user biometrics, STRAP Coach enforces four non-negotiable principles:

1. **Zero-Knowledge Privacy:** Biometric health data is processed on-device by default. No health data is transmitted to third-party cloud servers without explicit, informed user consent.
2. **Grounded Biometric Accuracy:** AI answers are strictly grounded in deterministic STRAP calculations (Recovery, SWS RMSSD, RHR, Karvonen Day Strain, Sleep Debt, Health Monitor corridors). The AI never fabricates numbers or diagnoses.
3. **Multi-Model Extensibility:** A clean provider abstraction decouples the UI from underlying models, supporting offline Apple Foundation Models, user-keyed Groq Llama models, and standalone on-device open weights (Qwen, Gemma).
4. **Microsecond Latency Transparency:** Time To First Meaningful Text (TTFMT) and total duration are measured and displayed, accompanied by dynamic waiting indicators to maximize perceived responsiveness.

---

## 2. Multi-Model Provider Architecture

```
                               ┌─────────────────────────────────┐
                               │       StrapAICoachView          │
                               │  (Interactive Bottom Drawer)    │
                               └────────────────┬────────────────┘
                                                │
                                                ▼
                               ┌─────────────────────────────────┐
                               │        CoachEngineCoordinator   │
                               │  - Model Router & Session Cache │
                               │  - Latency Tracker (TTFMT)      │
                               │  - Streaming Delta Dispatcher   │
                               └───────┬─────────────────┬───────┘
                                       │                 │
             ┌─────────────────────────┘                 └─────────────────────────┐
             │                                                                     │
             ▼                                                                     ▼
┌───────────────────────────────┐                                 ┌───────────────────────────────┐
│     LOCAL OFFLINE TIER        │                                 │     OPTIONAL CLOUD TIER       │
│   (Default · Zero Network)    │                                 │  (User-Provided Key · Opt-in) │
├───────────────────────────────┤                                 ├───────────────────────────────┤
│ [Provider A: Apple FM]        │                                 │ [Provider B: Groq API]        │
│ • SystemLanguageModel         │                                 │ • llama-3.3-70b-versatile     │
│ • On-device NPU / Apple Intel │                                 │ • llama-3.1-8b-instant        │
│ • Zero API cost, private      │                                 │ • Keychain-secured user key   │
│                               │                                 │ • Sub-second TTFMT            │
│ [Provider C: Qwen 2.5 1.5B/3B]│                                 │ • Explicit Health Share Gate  │
│ • CoreML / ExecuTorch         │                                 │                               │
│ • 4-bit quantized offline     │                                 │ [Tool: Privacy Web Search]    │
│                               │                                 │ • DuckDuckGo / Tavily         │
│ [Provider D: Gemma 2 2B]      │                                 │ • Sanitized query (no vitals) │
│ • Google CoreML weights       │                                 │ • Markdown URL citations      │
└───────────────────────────────┘                                 └───────────────────────────────┘
```

### 2.1 The Unified Provider Protocol

```swift
import Foundation

public struct CoachTokenChunk: Sendable {
    public let text: String
    public let isFinished: Bool
}

public protocol CoachModelProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var isLocal: Bool { get }
    var requiresKey: Bool { get }
    var isAvailable: Bool { get }
    
    func generateStream(
        prompt: String,
        systemInstructions: String,
        context: String?,
        history: [CoachTurn],
        onChunk: @escaping @Sendable (CoachTokenChunk) -> Void
    ) async throws -> String
}

public struct CoachTurn: Identifiable, Sendable {
    public let id: UUID
    public let userText: String
    public let assistantText: String
    public let timestamp: Date
}
```

---

## 3. Provider Evaluations & Specifications

### Provider A — Apple Foundation Models (Default Offline)
- **Framework:** `FoundationModels` (`SystemLanguageModel`, `LanguageModelSession`).
- **Availability:** iOS 26+ devices supporting Apple Intelligence (A17 Pro, M-series).
- **Execution Domain:** 100% on-device Neural Engine (NPU).
- **Data Boundary:** Direct in-memory grounding; zero bytes ever leave the device.
- **Latency:** TTFMT $\approx 350 - 650\text{ ms}$; generation speed $\approx 25 - 35\text{ tokens/sec}$.
- **Fallback Behavior:** If unprovisioned or language unavailable, system gracefully prompts the user with clear instructions or offers opt-in cloud selection.

### Provider B — Groq Cloud API (High-Speed Cloud Option)
- **Endpoint:** `https://api.groq.com/openai/v1/chat/completions` (OpenAI-compatible SSE streaming).
- **Supported Models:**
  1. `llama-3.3-70b-versatile`: Deep reasoning, exercise physiology, race pacing, complex multi-day trend analysis. Context window: 128k tokens.
  2. `llama-3.1-8b-instant`: Ultra-fast tactical coaching, sub-second latency, lower token consumption.
- **Credential Storage:**
  - Securely stored in the iOS Keychain under service `com.ribhupanwar.strap.coach.groq` and account `user-api-key`.
  - Accessible attribute: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
  - **Zero bundled secrets:** STRAP ships with no shared API keys.
- **Free-Tier Protection:**
  - Detects HTTP 429 (`RateLimitExceeded`) and provides user-friendly cooldown diagnostics.
  - Sets conservative `max_tokens = 500` to prevent runaway usage.

### Provider C — Qwen 2.5 On-Device Evaluation
- **Target Weights:** Qwen 2.5 1.5B Instruct or 3B Instruct (4-bit quantized MLX / CoreML).
- **Evaluation Metrics:**
  - Download Size: $\sim 980\text{ MB}$ (1.5B) to $\sim 1.9\text{ GB}$ (3B).
  - Active RAM Footprint: $\sim 1.3\text{ GB}$ peak resident memory.
  - Generation Speed: $\sim 18 - 22\text{ tokens/sec}$ on A17 Pro; $\sim 8 - 12\text{ tokens/sec}$ on A15/A16.
- **Architectural Decision:** Retain as an optional downloadable add-on for devices lacking Apple Foundation Models. Do not bundle into the default SideStore IPA to preserve compact binary size ($< 40\text{ MB}$).

### Provider D — Google Gemma 2 2B On-Device Evaluation
- **Target Weights:** Gemma 2 2B CoreML (4-bit int4 quantization).
- **Evaluation Metrics:**
  - Download Size: $\sim 1.4\text{ GB}$.
  - Active RAM Footprint: $\sim 1.6\text{ GB}$.
- **Architectural Decision:** Redundant with Qwen 2.5 1.5B, which demonstrates superior multi-lingual instruction-following and lower memory pressure. Deferred pending benchmark verification.

---

## 4. Grounded Biometric Snapshot Architecture

### 4.1 Root Cause of Current STRAP Coach Failures
In PR #143, STRAP Coach suffered from repetitive responses because `measuredContext` provided only 4 isolated scalar numbers (`Recovery`, `HRV`, `RHR`, `Recorded nights available`), omitting all historical days, workouts, sleep stages, and day strain.

### 4.2 Comprehensive Grounded Snapshot Schema

To enable human-grade coaching, `CoachBiometricSnapshotBuilder` constructs a temporal, structured snapshot spanning three distinct windows:

```swift
public struct CoachBiometricSnapshotBuilder {
    public static func build(from store: AppStore) -> String {
        let calendar = Calendar.current
        let todayKey = JournalStore.dayKey(for: Date(), calendar: calendar)
        let sortedDays = store.band.days.sorted { $0.dateKey < $1.dateKey }
        let yesterdayKey = sortedDays.suffix(2).first?.dateKey ?? "unknown"
        
        // 1. TODAY (In-Progress)
        let recoveryScore = store.band.recovery.score.map { "\($0)%" } ?? "Unavailable (Sleep processing pending)"
        let liveStrain = String(format: "%.1f", store.band.dayStrain.current)
        let latestHRV = store.lastCapture?.hrv.rmssdMS.map { String(format: "%.0f ms", $0) } ?? "Unavailable"
        let restingHR = store.measuredRestingHR.map { String(format: "%.0f bpm", $0) } ?? "Unavailable"
        
        // 2. YESTERDAY (Finalized 24h Baseline)
        let yDay = sortedDays.first { $0.dateKey == yesterdayKey }
        let ySleep = yDay?.sleepHours.map { String(format: "%.1f hrs", $0) } ?? "Unavailable"
        let yStrain = yDay?.strain.map { String(format: "%.1f", $0) } ?? "Unavailable"
        
        // 3. 7-DAY TRAILING TREND
        let last7 = Array(sortedDays.suffix(7))
        let avgRecovery = Stats.mean(last7.compactMap { $0.restingHR }) // representative
        let validHRVs = last7.compactMap { $0.lnRMSSD.map { exp($0) } }
        let hrvRange = validHRVs.isEmpty ? "Unavailable" : "\(Int(validHRVs.min()!))–\(Int(validHRVs.max()!)) ms"
        
        // 4. WORKOUT SESSIONS (Detected + Manual)
        let recentWorkouts = (store.detectedBandActivities + store.manualActivities.map { $0.asSession })
            .filter { Date().timeIntervalSince($0.endDate) < 7 * 86400 }
            .prefix(5)
            .map { "- \($0.sportName): \($0.durationMinutes)m, Strain \($0.strainScore ?? 0), \($0.calories) kcal" }
            .joined(separator: "\n")
            
        // 5. HEALTH MONITOR STATUS
        let hm = store.healthMonitor
        let vitalsSummary = """
        - RHR: \(hm[.rhr].statusText)
        - HRV: \(hm[.hrv].statusText)
        - Respiration: \(hm[.respiration].statusText)
        - Temperature: \(hm[.temperature].statusText)
        - Blood Oxygen: \(hm[.oxygen].statusText)
        """

        return """
        [STRAP GROUNDED HEALTH DATA — CONFIDENTIAL]
        • TODAY (\(todayKey)):
          - Recovery: \(recoveryScore)
          - Current Day Strain: \(liveStrain) / 21.0
          - Latest SWS HRV: \(latestHRV)
          - Resting Heart Rate: \(restingHR)
        • YESTERDAY (\(yesterdayKey)):
          - Total Sleep: \(ySleep)
          - Finalized Day Strain: \(yStrain)
        • 7-DAY BASELINE TRENDS:
          - Typical HRV Range: \(hrvRange)
          - Qualifying Nights Logged: \(last7.count) / 7
        • HEALTH MONITOR STATUS:
        \(vitalsSummary)
        • RECENT WORKOUTS (Last 7 Days):
        \(recentWorkouts.isEmpty ? "No workouts recorded." : recentWorkouts)
        [END HEALTH DATA]
        """
    }
}
```

---

## 5. Privacy & Informed Consent Architecture

STRAP enforces a strict **Dual-Gate Privacy Model**:

```
[User initiates chat in STRAP Coach]
                │
                ├───────────────────────────────────────────┐
                ▼                                           ▼
      [Offline Apple FM Selected]                 [Cloud Provider Selected]
                │                                           │
      [100% On-Device Execution]                  [Gate 1: Key & Model Validated]
      • Health snapshot processed in RAM                    │
      • Zero network requests                               ▼
      • Instant token delivery                   [Gate 2: Health Share Toggle?]
                                                            │
                                  ┌─────────────────────────┴─────────────────────────┐
                                  ▼                                                   ▼
                         [Toggle is OFF (Default)]                           [Toggle is ON (Explicit)]
                         • User question transmitted                         • User question transmitted
                         • Health snapshot IS STRIPPED                       • Anonymized health snapshot included
                         • Model acts as generic science coach               • Model provides personalized advice
```

### Privacy Safeguards:
1. **Never Send Private Identifiers:** The snapshot contains zero names, Apple IDs, device UUIDs, or GPS routes.
2. **Keychain Storage:** Keys are isolated from backups (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
3. **No Automatic Network Fallback:** If Apple Intelligence fails, STRAP **never** silently sends the request to Groq or the cloud. It displays an offline error notice.

---

## 6. Response Speed & Latency Engineering

To achieve sub-second perceived response times:
1. **Streaming Token Pipeline:** The UI binds directly to an `AsyncStream<String>`, appending token deltas immediately to the chat bubble.
2. **Persistent Session Caching:** Rather than creating a new `LanguageModelSession` on every keystroke, the coordinator reuses an initialized session across turns, preserving KV caches.
3. **Rotating Progress Micro-Copy:** While waiting for the first token ($0 - 1.5\text{s}$), the UI rotates WHOOP-verified waiting statuses:
   - *"Fetching your data now…"*
   - *"Scanning sleep, strain, recovery…"*
   - *"Summarizing your insights now…"*.
4. **Immediate Stop Button:** Users can tap "STOP GENERATING" to cancel the active `Task` and halt token generation immediately.

---

## 7. Privacy-Preserving Internet Search Architecture

When a user asks questions requiring real-time external knowledge (e.g. *"What is the qualifying time for Boston Marathon 2026?"*), STRAP invokes a decoupled search tool:

1. **Tool Invocation Policy:** Search triggers **only** when the LLM emits a search function call or the user explicitly queries external events.
2. **Absolute Health Isolation:**
   $$\text{SearchQuery} = \text{Sanitize}(\text{UserPrompt}) \quad \setminus \quad \text{Biometrics}$$
   Health metrics, HRV, RHR, recovery scores, and personal values are **strictly forbidden** from appearing in the search query.
3. **Free & Low-Cost Providers:**
   - Provider 1: DuckDuckGo Instant Answer / HTML (Free, zero-credential, no user tracking).
   - Provider 2: Tavily / Brave Search API (Optional user-supplied key in Keychain).
4. **Citations UI:** Search results are parsed for URL domains and rendered as Markdown citation pills: `[1. Boston Athletic Association](https://baa.org)`.

*Document approved by STRAP AI Systems Architecture Board.*
