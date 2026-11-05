# First publication

Repository name: **WsusOfflineNext**.

Target remote: `https://github.com/CatFoxVoyager/WsusOfflineNext`.

The first push must publish **one initial commit**, containing the final project snapshot. Intermediate development commits and inherited Git ancestry must not appear in the published branch's history.

Perform the consolidation immediately before the requested first push:

1. Finish the intended changes and verification. Include the English README, screenshots, LinkedIn and Liberapay links, and release notes in the final snapshot.
2. Preserve a local recovery reference for the existing history and any pending work before rewriting history.
3. Create a parentless initial commit from the reviewed final snapshot, retaining source files, licenses, credits, and the historical changelog. Suggested message: `Initial release of WsusOfflineNext`.
4. Verify that the publication branch contains exactly one commit and that its tree matches the intended snapshot. Confirm the target repository and branch before pushing.
5. Push only the publication branch when requested. Do not include old development branches or tags that would expose the intermediate history.

This preparation does not itself publish a GitHub release. Use [the release notes](../RELEASE_NOTES.md) when preparing the release description.

## Pre-train FP-reputation gate (VirusTotal + WDSI)

Every release train scans its four primary shipped executables with VirusTotal
BEFORE tagging and publishing, and assembles the WDSI submission packet. The
gate lives in the monthly train workflow
(`.github/workflows/monthly-updates.yml`, step `FP-reputation gate (VT scan +
WDSI packet)`), between the release-archive verification and the tag step.

### Per-train flow

1. The workflow sha256-hashes each of the four primary shipped exes
   (`UpdateGeneratorModern.exe`, `client/UpdateInstallerModern.exe`,
   `client/UpdateInstallerLegacy.exe`, `client/UpdateInstallerLegacy64.exe`),
   uploads each to the VirusTotal v3 API, polls the report, and archives the
   sha-named verdict JSONs inside the `wdsi-packet` workflow artifact.
2. The gate FAILS CLOSED - naming the engine and the verdict - on any
   `malicious` verdict, with one adjudicated exception (below). A red or
   unavailable VT call also fails the train closed: a stalled release is
   safer than an unscanned one.
3. The same step assembles the `wdsi-packet` artifact: per-arch submission
   notes quoting each binary's `StringFileInfo` strings (never the fixed-info
   numeric build slot - it carries the `+YYYY.MM` tail digits and is not
   stable across rebuilds), the sha256 manifest, the verdict summary, and the
   submission checklist.

### Adjudicated FP policy (owner decision, 2026-11-05)

Malicious verdicts from the engine **APEX** consisting of the bare, nameless
string `Malicious` (no signature name) on the .NET single-file hosts are the
documented baseline class and do NOT fail the train:

- Baseline provenance: the Phase 23 toolchain scan measured the C#
  self-contained prototype at 1/68 (Bkav); the 27-01 rehearsal archived the
  first shipped-binary-level verdicts of the .NET pair (`1b8bd158…`,
  `e470231e…`), each flagged by APEX only, bare `Malicious`, 70/71 engines
  undetected. APEX emits content-agnostic generic verdicts on .NET
  single-file bundles; rebuilding does not clear them.
- Everything else fails the train closed. Verdicts are archived on every
  train either way, so drift away from (or toward) the baseline is visible.

### Manual WDSI submission (per train)

The workflow's VT verdict is the train gate; the WDSI submission is the manual
half of the FP-hygiene loop (the owner submits the flagged .NET pair every
train, pre-creating Microsoft reputation - same channel as the FPC packets):

1. Download the `wdsi-packet` workflow artifact.
2. Submit each binary through the [Microsoft WDSI file submission
   portal](https://www.microsoft.com/en-us/wdsi/filesubmission), quoting the
   binary's `StringFileInfo` strings in the notes field.
3. Record the ticket number and date in the packet's checklist table.
4. Expected turnaround: 24-72h (community range: 24h to weeks - do not gate
   the release on WDSI alone).

### Credential handling

- `VT_API_KEY` lives as a GitHub Actions repository secret and, locally, in
  `HKCU\Environment` since Phase 23 - never printed, never committed.
  Rotation means updating both places.
- The WDSI portal needs no credential beyond the operator's Microsoft account.

### False-positive response notes (Pitfall 10)

- Rebuilding is a legitimate FP response: per-build ML verdicts are
  stochastic (`!ml`) and a fresh hash re-rolls them.
- NEVER pack with UPX - it is a standing FP amplifier prohibition in this
  project.
- Binary hygiene is the durable mitigation: rich VERSIONINFO, embedded
  manifest, standard PE layout, no embedded script payloads.
