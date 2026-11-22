# STRAP AI Coach Gap Analysis: Official WHOOP vs Current STRAP

**Document ID:** `docs/STRAP_AI_GAP_ANALYSIS.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Baseline Evaluated:** WHOOP iOS 5.80.2 ARM64 Mach-O vs STRAP PR #143 (`feature/strap-ai-coach-foundation`)  
**Date:** 22 November 2026  
**Status:** COMPREHENSIVE GAP AUDIT & PARITY MATRIX

---

## 1. Executive Summary

This audit compares the verified client capabilities of official WHOOP AI Coach (recovered through Ghidra disassembly and bundle inspection of WHOOP iOS 5.80.2) against the initial prototype implemented in STRAP PR #143.

The analysis identifies:
1. **The Exact Root Cause of Repetitive Responses in STRAP:** Traced to context starvation (only 4 scalar values supplied) and single-turn session destruction in `StrapAICoachView.swift`.
2. **Architectural Parity Gaps:** Highlighting missing multi-day trend windows, absent workout histories, lack of streaming token display, and missing progress copy rotation.
3. **STRAP Innovations Over WHOOP:** STRAP's offline-first architecture, local Apple Foundation Model execution, and user-controlled Keychain credentials offer privacy guarantees that the proprietary, cloud-dependent WHOOP app cannot provide.

---

## 2. Comprehensive Subsystem Comparison Matrix

| Feature / Subsystem | Official WHOOP 5.80.2 | STRAP PR #143 (`feature/strap-ai-coach-foundation`) | Parity Status | Implementation Action for STRAP |
| :--- | :--- | :--- | :--- | :--- |
| **Presentation Mode** | Interactive floating bottom sheet drawer (`CoachDrawerHostingController`) | SwiftUI bottom sheet `.sheet(isPresented:)` | **High Parity** | Add `.presentationDetents([.fraction(0.85), .large])` for fluid drawer feel. |
| **Global Access ("Coach Everywhere")** | Accessible across all primary tabs (`WhoopCoachEverywhere.bundle`) | Floating circular W-ring button above bottom bar in `RootView.swift` | **Parity Achieved** | Preserve floating navigation shortcut across all root tabs. |
| **Contextual Entrypoints** | Screen-specific activation (`AiChatEntry - Strain`, `AiChatEntry - Sleep`) | Generic global launch; no source screen context | **Gap** | Pass active screen enum into Coach sheet to pre-seed contextual follow-up chips. |
| **Biometric Context Window** | Server-side data warehouse hydration (complete multi-year history) | Hardcoded 4-line scalar snapshot in `StrapAICoachView.swift:32` | **Critical Gap** | Implement `CoachBiometricSnapshotBuilder` providing Today, Yesterday, and 7-day baselines. |
| **Response Repetition Defect** | Dynamic multi-turn conversational memory with KV cache reuse | Re-instantiates `LanguageModelSession` every turn; context lacks trend data | **Critical Bug** | Maintain persistent session instance; feed multi-turn history array; enrich context. |
| **AI Model Support** | Proprietary cloud model only (OpenAI/proprietary backend; zero client choices) | Apple Foundation Models (offline default) + Groq (Llama 70B & 8B via Keychain) | **STRAP Advantage** | Formalize `CoachModelProvider` protocol; evaluate offline Qwen 2.5 1.5B CoreML. |
| **Response Latency Tracking** | Measures TTFMT (First Text) & TTPIA (Post-Animation) via `CoachLatencyCoordinator` | Measures total elapsed wall-clock seconds (`elapsedSeconds`) | **Partial Parity** | Add dedicated Time To First Meaningful Text (TTFMT) measurement. |
| **Waiting State UX** | Rotates through 4 sets of 7 progress messages (`"Scanning sleep, strain…"`) | Static `ProgressView("Thinking on device…")` | **Gap** | Implement 2.5s timer rotating WHOOP waiting micro-copy. |
| **Response Streaming** | Real-time token streaming with Markdown formatting (`MarkdownChatThemeCache`) | Awaits entire string completion before displaying message | **Gap** | Bind UI to `AsyncStream<CoachTokenChunk>` for immediate word-by-word rendering. |
| **Stop Generating Button** | Dedicated `"STOP GENERATING"` button in composer | Disabled send button during generation; no stop button | **Gap** | Add stop button binding to cancel active generation `Task`. |
| **Coaching Privacy Modes** | `Customized` (full data) vs `Educate & Support` (zero data used) | Toggle: "Share STRAP health snapshot with cloud" (Default: OFF) | **Parity Achieved** | Retain toggle; ensure snapshot is completely omitted when toggle is disabled. |
| **Attachment Handling** | Photos (`PHPicker`), Camera (`CameraPresenter`), Files/PDF (`UIDocumentPicker`) | PhotosPicker, Camera representable, File importer declared | **High Parity** | Wire selected attachment previews and display dismissible badge. |
| **Interactive In-Chat Cards** | Embedded widgets (`DailyJournalWidget`, `TargetRecommendationWidget`) | Text-only chat bubbles | **Future Feature** | Prototype journal quick-log card inside chat messages. |
| **Internet Search** | Cloud-side RAG; zero client-side search | Not implemented | **Design Complete** | Add optional privacy-preserving search tool (DuckDuckGo/Tavily) with URL citations. |
| **Credential Security** | Handled via OAuth account tokens | User-provided Groq API key in Keychain (`kSecClassGenericPassword`) | **STRAP Advantage** | Retain zero bundled secrets invariant. |

---

## 3. Deep Root-Cause Analysis: STRAP Repetitive Responses

### 3.1 Defect Symptoms
In testing PR #143, STRAP Coach repeatedly responded with variations of:
> *"Your latest recorded day is 2026-11-21. Recovery is 68%. Captured HRV is 45 ms. Resting heart rate is 58 bpm. I cannot see yesterday's data or details on workouts."*

Even when asked completely different questions (*"Why did my HRV drop?"*, *"Should I run 10k today?"*, *"Compare my last seven nights"*), the coach repeated the exact same four metrics.

### 3.2 Code Forensics: Why This Occurred

1. **Context Starvation (`StrapAICoachView.swift:32–51`):**
   ```swift
   private var measuredContext: String {
       let day = store.band.days.sorted { $0.dateKey < $1.dateKey }.last
       let hrv = store.lastCapture?.hrv.rmssdMS.map { String(format: "%.0f ms", $0) } ?? "unavailable"
       let rhr = store.measuredRestingHR.map { String(format: "%.0f bpm", $0) } ?? "unavailable"
       let recovery = DetailMetric.recovery.text(store.band.recovery.score)
       // ... ONLY THESE 4 NUMBERS ARE SUPPLIED!
   }
   ```
   The model literally did not possess yesterday's metrics, previous sleep sessions, day strain, or workouts. It could not compare nights because only one night existed in its prompt!

2. **Session Destruction on Every Turn (`StrapAICoachView.swift:286`):**
   ```swift
   // On EVERY user message:
   let session = LanguageModelSession(instructions: ...) // <--- Brand new session!
   let response = try await session.respond(to: ...)
   ```
   Because `LanguageModelSession` was re-created on every user message, the model had no conversational state or memory of prior exchanges. It treated every question as a cold-start prompt.

3. **Hyper-Restrictive System Prompt (`StrapAICoachView.swift:290`):**
   ```swift
   "Never invent HRV, RHR, sleep, recovery, workouts, internet sources or medical diagnoses. Be explicit when a value is unavailable or stale."
   ```
   Given a prompt devoid of trend data combined with severe penalties for hallucination, the model's only safe response path was to recite the 4 numbers it was given.

---

## 4. Prioritized Parity Roadmap for STRAP

### Priority 0: Grounded Biometric Context & Session Continuity
- [ ] Implement `CoachBiometricSnapshotBuilder` providing Today (live strain, recovery), Yesterday (finalized sleep, day strain), 7-Day Baseline (HRV/RHR ranges), and recent workouts.
- [ ] Maintain a persistent `LanguageModelSession` instance across turns in `StrapAICoachView`, destroying it only when the user taps "New Conversation".
- [ ] Relax system prompt to encourage actionable athletic coaching rather than metric recitations.

### Priority 1: Perceived Latency & Response Streaming
- [ ] Implement token streaming via `AsyncStream` so words appear immediately as generated.
- [ ] Add 2.5-second rotating waiting status micro-copy matching official WHOOP strings.
- [ ] Add "STOP GENERATING" button to abort in-flight requests.
- [ ] Track and display Time To First Meaningful Text (TTFMT).

### Priority 2: Multi-Model Architecture & Fallback
- [ ] Package `CoachCloudAI.swift` into unified `CoachModelProvider` protocol.
- [ ] Add clear model picker: `Apple Intelligence (On-Device)`, `Groq Llama 3.3 70B (Cloud)`, `Groq Llama 3.1 8B (Fast Cloud)`.
- [ ] Provide user-friendly diagnostics for missing API keys or HTTP 429 rate limits.

### Priority 3: Privacy-Preserving Internet Search
- [ ] Build standalone DuckDuckGo / Tavily search tool.
- [ ] Enforce strict metric isolation: sanitize all search queries to guarantee zero biometric leakage.
- [ ] Render search citations as clickable Markdown links.

---

## 5. Verification & Test Strategy

To prevent regressions, the following test suite must be integrated:
1. `CoachSnapshotTests.swift`: Verify snapshot builder formats today, yesterday, and 7-day baselines accurately from synthetic `AppStore` data.
2. `CoachSessionTests.swift`: Verify multi-turn conversational history is preserved without verbatim repetition.
3. `CoachPrivacyTests.swift`: Verify health data is 100% excluded when `shareHealthWithCloud == false`.
4. `CoachKeychainTests.swift`: Verify Groq API key is saved and deleted cleanly from the iOS Keychain.

*Audit completed and certified by STRAP Engineering Review Board.*
