# Privoice — Testing & Quality Strategy

**Goal:** world-class quality for a privacy-first, on-device-ML app. Because the core value (STT + LLM) runs on the user's own hardware, **real-device testing across a tier matrix is not optional** — emulators cannot tell us the truth about speed, RAM, thermal, or battery. This doc defines the full suite; STATUS.md tracks progress (see the "Testing & Quality" workstream).

---

## 1. The test pyramid (in-repo, runs in CI)

| Layer | What | Tooling | Where |
|-------|------|---------|-------|
| **Unit** | Pure logic: map-reduce chunking, prompt building, repository CRUD, WAV/config, benchmark math | `flutter test` | every `packages/*` |
| **Widget** | Screens render + behave with fakes (Home/Record/Transcript/Ask); loading/empty/error states | `flutter test` + fakes | `apps/mobile/test` |
| **Golden** | Visual regression of key screens & components in light+dark (calm theme stays consistent) | `flutter test` golden files | `apps/mobile/test/golden` |
| **Integration** | Real flows on a device/emulator: record→transcribe, summarize, ask; offline (airplane-mode) invariant | `integration_test` | `apps/mobile/integration_test` |

**Principles:** each package unit-testable without a device (fakes for `MeetingRepository`, `SttEngine`, `AiEngine`). Fast layers gate every PR; device layers run on the matrix (below).

---

## 2. On-device ML quality (the differentiator)

### 2.1 STT accuracy (WER)
- **Corpus:** a curated set of real/representative meeting clips — varied accents (incl. GCC English/Arabic), 2–6 speakers, crosstalk, near/far mic, background noise — each with a human reference transcript.
- **Metric:** Word Error Rate per clip + aggregate, plus per-condition breakdown. Track over time; regression gate.
- **Harness:** `tools/` script runs the model over the corpus on a real device, emits WER + RTF.

### 2.2 LLM minutes quality
- **Eval set:** transcripts (short + long, to exercise map-reduce) each with a reference/rubric.
- **Rubric:** coverage of decisions/action-items, faithfulness (no hallucinations), structure, conciseness. Scored 1–5.
- **Method:** golden expected-shape checks + an LLM-as-judge pass (a stronger model scores outputs). Track per model tier (1B/2B/3B).

### 2.3 Performance / thermal / battery
Per device tier, capture:
- **RTF** (STT + LLM), **model load time**, **peak RAM (PSS/RSS)**, **device temperature rise**, **battery drain per processed hour**, **sustained RTF on 1-hour audio** (throttling), **app size**.
- Output: the **device-tier → model mapping** table (which drives auto model selection in S5). Data-driven, not guessed.

---

## 3. Real-device matrix (online / cloud device farms)

Test on real phones across tiers and OS versions — via a cloud device farm so we cover hardware we don't own.

**Android tiers**
| Tier | Example chips | Example devices |
|------|---------------|-----------------|
| Low | MediaTek Helio G, Snapdragon 4xx | Redmi 15C (have), Galaxy A1x |
| Mid | Snapdragon 6xx/7xx, Dimensity 7xxx | Redmi Note, Galaxy A5x, Pixel a |
| High | Snapdragon 8-class, Dimensity 9xxx | Pixel 9, Galaxy S2x, OnePlus |

**iOS tiers** (when iOS lands): iPhone SE (small/older), iPhone mid, iPhone Pro — across the two latest iOS majors.

**Farm options (pick one primary + one fallback):**
- **Firebase Test Lab** — real Android devices, integrates with `integration_test` + Gradle; good CI story; free tier. *(recommended primary for Android)*
- **BrowserStack App Automate** / **AWS Device Farm** — larger device catalog incl. iOS; good for the broad matrix.
- **Genymotion Cloud** — emulators at scale (functional only, not perf).

**What runs on the farm:** the `integration_test` suite per device + the performance/thermal capture (§2.3). Nightly + pre-release.

---

## 4. CI/CD

- **On every PR:** `melos run analyze` + unit + widget + golden tests + `flutter build apk --debug` (catches native-build breakage, e.g. sherpa/fllama). Fast (<10 min).
- **Nightly / pre-release:** integration suite on the Firebase Test Lab device matrix + WER/LLM-quality + perf capture; publish a dashboard.
- **Release:** signed build, size check, changelog, staged rollout.
- **Runner:** GitHub Actions or **Codemagic** (Flutter-native, has device testing + code signing). Decide in T2.

---

## 5. Non-functional quality gates

- **Privacy verification (critical):** an automated test asserting **zero network traffic** during offline record→transcribe→summarize (airplane-mode integration test + a network-interceptor assertion). This is the product's core promise — it must be a hard gate.
- **Accessibility:** screen-reader labels, min contrast, dynamic text scaling, large-tap targets; `flutter test` semantics + manual TalkBack/VoiceOver pass.
- **i18n / RTL:** the app targets the GCC market — verify **Arabic / RTL** layout and locale formatting early, even before full translation.
- **Robustness:** long recordings, low storage, permission-denied, model-missing, interrupted recording, backgrounding mid-transcription.
- **Crash/error telemetry:** privacy-respecting and **opt-in only** (offline-first). No transcript/audio ever in telemetry.

---

## 6. Test data & corpora

- `test-data/` (git-ignored / DVC or external) — consented meeting audio + reference transcripts (WER) and reference minutes (LLM eval).
- Small fixture clips checked in for CI integration tests; the large corpus lives externally.
- Synthetic transcripts (varied length/topic) generated for map-reduce and edge cases.

---

## 7. Release gates (definition of "world-class ready")

A build ships only when:
1. Unit + widget + golden + integration suites green.
2. Privacy (zero-network) gate green.
3. WER within target on the corpus; LLM minutes rubric ≥ threshold per supported tier.
4. Perf/thermal within budget on every supported device tier (no thermal runaway on 1-hour audio).
5. a11y + RTL smoke passes.
6. Crash-free session rate ≥ target on the device matrix.

---

## Phased rollout (tracked in STATUS.md → Testing & Quality)

- **T0** — Test foundation: fakes for repo/STT/AI; expand unit tests; widget tests for the 3 screens.
- **T1** — Golden tests (light/dark) + integration tests for summarize + the airplane-mode privacy gate.
- **T2** — CI pipeline (analyze + tests + debug build) on PRs; choose runner.
- **T3** — Firebase Test Lab device matrix (nightly integration + perf capture).
- **T4** — STT WER harness + real-meeting corpus.
- **T5** — LLM minutes quality eval (rubric + judge).
- **T6** — Perf/thermal/battery harness → device-tier table (feeds S5).
- **T7** — a11y + Arabic/RTL pass.
- **T8** — Release gates automated + dashboard.
