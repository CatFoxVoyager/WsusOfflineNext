# Release notes

[Back to the project](README.md) · [Quick start](README.md#quick-start) · [Support development](https://liberapay.com/Jeremie/) · [LinkedIn](https://www.linkedin.com/in/jeremiedufault)

## 6.1.0+2026.11

**Status:** current release.

### Offline runtime bootstrap for the modern interface (headline)

- **The client now installs its own runtimes.** The adaptive client launcher gained a fifth capability gate that probes the **.NET 8 Desktop Runtime (x64)** before routing to the modern interface, and a new bootstrap helper (`client\cmd\RuntimeBootstrap.cmd`) that silently installs missing runtimes **from the offline tree itself**: .NET 8 Desktop Runtime (`client\dotnet\windowsdesktop-runtime-8.*-win-x64.exe`) and the Edge WebView2 Runtime (`client\edge\MicrosoftEdgeWebView2RuntimeInstaller*.exe`) — both downloaded by default since 6.0. Old Windows 10 machines that previously failed with "you must install .NET Desktop Runtime" now bootstrap inside the launcher's single UAC prompt and land on the modern interface with zero manual steps. Any remaining gap (runtime absent, installer absent, bootstrap failure) routes to the legacy native installer as before — the routing fails safe on every branch. ARM64 hosts probe but never install (the modern host is win-x64).
- **.NET 8 / .NET 10 detection files added:** the client-side `/updatedotnet5` MSI-detection path now carries the full `StaticUpdateIds-MSIProducts-dotNET8_*` and `dotNET10_*` old/new detection sets (24 files, harvested from winget manifests and live registry), so machines with .NET 8/10 installed are detected and the runtimes install from the tree when missing. The `_documented` provenance variants are excluded from release trees.
- The WebView2 gate now also bootstraps: below-floor or absent WebView2 with the offline installer present installs and re-probes before falling back to Legacy.

### Windows 7 (w61) update chain restored

- **IE11 upgrade flow restored** for Windows 7: w61 XSLT extraction re-registered on the generator, IE11 targets and the dedicated install section back on the client engine.
- **SHA-2 code signing pair** (KB4474419 + KB4490628) installs on w61 before the offline scan, unlocking SHA-2-signed catalogs on stock SP1.
- **WUA-SHA2 bootstrap:** when the Windows Update Agent cannot read SHA-2 catalogs, the engine installs the servicing-stack update plus the final cumulative LCU to refresh the agent. The refresh uses **KB4534314** (last public security-only update, WUA 24542) instead of the ESU rollups that CBS rolls back on unlicensed machines (0x80004002); the w61 x64/x86 static lists carry it.
- **Mandatory reboot after the SHA-2 pair lands**, with local `%TEMP%` copies before both dism `Add-Package` call sites (media-lock safe).
- **The offline scan fails loudly** — a failed scan reports the error instead of the silent "0 missing updates" that masked broken chains.
- **Identities with files missing from the medium are skipped** (aligned with the generator's superseded-exclusion list), and the `%LIST_MODE_IDS%` argument-shift is quoted away. A full Win7 run now ends in **one pass, no reboot**, with honest skip warnings.
- **The endless recall loop is gone:** `WOU_ENDLESS` is armed on every OS (w61/wxp included) and a no-progress guard turns "same file list twice inside the recall" into an explicit error instead of a 101-pass, 12-hour loop.

### Windows XP (wxp) chain validated

- XP update identity lists (`StaticUpdateIds-wxp.txt`, `-seconly`) and the XP x86 download list refresh land after a validated real run on an XP SP3 VM: IE6 → IE8 plus 11 updates installed, zero failures.
- **XP Winlogon restore fixed:** XP's `reg.exe` has no `IMPORT` (Vista+), so the pre-recall Winlogon backup was deleted without ever being restored, leaving a dead autologon and a password prompt after every run. The backup is now re-imported silently via `regedit.exe /s` (present on XP, harmlessly redundant on Vista+). Post-run Winlogon equals pre-run state.

### Native installer (classic GUI)

- Network script directories: share-root fallback, WNet star-device resolution replaced by client-side free-letter selection — the invalid WNet star device no longer breaks the GUI at startup on UNC-hosted media.
- Edge/WebView2 install offers are gated off on pre-Win10 systems where they cannot apply.
- Audit-report snapshotting (candidate paths + report copies around runs), resume-path and engine-spine updates, and 98 lines of contract-test coverage for the new behavior.

### Generator (modern + bash)

- Windows 10 **x86 rows enabled by default** (17763/14393/10240) plus 10240 x64 — x64/x86 build parity across all nine Windows 10 rows, with truthful EOL badges.
- Windows 8.1 / Server 2012 R2 legacy rows are labeled correctly (w63 no longer mislabeled).
- `SaveIniFiles` now emits `sh/windows-10-versions.ini` so the **bash pipeline mirrors the GUI's w100 build selection** (Win11 keys included; the runtime file stays out of release trees).

### Static catalogs & self-update

- **Edge Enterprise MSI links restored:** the monthly link-refresh bot had emptied `static/StaticDownloadLinks-edge-*` (it removes expired URLs and ADD is disabled), breaking the modern-extras battery since 2026-10-29. The lists carry the current Stable 157.0.4341.42 Enterprise MSI URLs resolved from the official edgeupdates feed.
- The self-update updater's csproj is re-aligned onto the version matrix — the bump gate's 25-site/15-file invariant holds again (its absence made every version bump exit 1 with a 22-site count).

### Quality gates

- The WebView2 battery gains section f: runtime-bootstrap helper pins, Gate 5 wiring, and three can-fail controls that seed their own mutations.
- The modern-extras suite checks the new detection files end to end.
- The native hygiene battery's version pin now tracks the `WSUSOFFLINE_VERSION` core (the frozen 5.2.0 pin predated the native VersionInfo joining the bump matrix and could never pass on any 6.x build).
- The strings gate is line-ending agnostic (a CRLF checkout silently dropped the final record: 64 ids vs 63 records on a valid unit).
- Spine, units, compare-versions, selfupdate-cycle/updater, webview2, modern-extras and bump-version batteries all green on the release tree.

### Screenshots

- README screenshots refreshed against real applications: the native legacy installer captured live on Windows XP, and the modern Generator 6.1.0 captured from the .NET 8 / WebView2 host.

### Requirements and upgrade guidance

- Same requirements as 6.0: the modern interfaces need the .NET 8 Desktop Runtime (x64) and WebView2 — which the client tree now installs itself (see the headline above); script-based use is unchanged.
- Media generated with this release bootstraps its own runtimes offline; older media keeps working with the legacy interface.

## 6.0.4+2026.11

**Status:** current release.

### Highlights

- **New project logo everywhere:** a dedicated WSUS Offline Next logo (update cube and refresh arrow) now appears in the README header, as the GitHub social preview, and as the application icon of all six executables — the adaptive launchers, the modern .NET 8 applications, and the legacy AutoIt GUIs.
- **Branded Generator interface:** the modern Generator header replaces the placeholder shield with the project logo, and the application window icon follows the same mark.
- **Refreshed screenshots:** all README screenshot assets were retaken against the branded interface, so documentation matches what the applications actually look like.

### Release packaging

- Fixed release packaging on Windows: `MakeRelease.cmd` now resolves 7-Zip through the scoop installation and excludes development and workspace content from the published archive.

### Requirements and upgrade guidance

- Same requirements as 2026.10.0: Windows 10 or 11 (x64) for the generator, .NET 8 and WebView2 for the modern interface, with automatic fallback to the legacy Win32 GUI otherwise.
- Drop-in replacement: replace the previous tree with this one; configuration (`UpdateGenerator.ini`, `UpdateInstaller.ini`) and existing download repositories are preserved. No configuration migration is required.

### Validation

- Full rebuild of both React frontends, both .NET 8 single-file hosts, and all four AutoIt binaries against the 2026.10.1 version metadata.
- Icons verified by extraction from the rebuilt executables; the modern Generator interface was exercised in a browser to confirm the branded header and favicon.

## 2026.10.0

**Status:** current repository snapshot. Publication and release packaging are tracked separately.

WSUS Offline Next continues the WSUS Offline Update Community Edition workflow with modern desktop applications, expanded Windows and Office servicing, and clearer offline diagnostics.

### Highlights

- **English desktop experience:** both modern applications now use English throughout their application-owned interface, including navigation, options, tooltips, status labels, and console messages. The USB-copy checkbox also has an accessible English name.
- **Compact product selection:** Windows and Office tables expose versions and architectures with bulk-selection controls. Integrated consoles provide timestamped messages, automatic scrolling, and copy/clear actions.
- **Updated project guide:** the README introduces the successor project, shows six refreshed English screenshot assets, and explains requirements, media preparation, installation, coverage, and command-line use. Screenshots are labeled browser previews with illustrative metadata.

### Windows servicing

- Shared build metadata includes Windows 11 24H2, 25H2, and 26H2, alongside Windows 10 and Windows Server servicing entries.
- Checkpoint cumulative updates are ordered before dependent updates on the 26100 servicing branch.
- Enablement-package handling checks build eligibility and prerequisites.
- Windows 11 26H1 / build 28000 has separate branch handling and is excluded from the normal enablement-upgrade path. The modern Generator has no 26H1 selection.
- Legacy Windows XP routing and selection persistence have been added to the download, media, and client scripts. A static list contains 12 English x86 package URLs, including SP3 and selected later updates. This is limited legacy preparation support; complete applicability and installation on XP have not been verified by the documentation/UI checks described below. The modern .NET 8 applications require a compatible Windows host.

### Office and optional components

- Office 2016 MSI uses the WSUS catalog download path.
- Office 2019, Office LTSC 2021, and Office LTSC 2024 use ODT staging for x86 or x64 media and offline Click-to-Run servicing on the client.
- Optional package preparation includes Microsoft Edge, WebView2, Defender definitions, Visual C++, .NET Framework, and modern .NET 8 / 10 runtimes.
- Client system-property detection checks WebView2 runtime registration in both user and machine locations, including the 32-bit registry view.

### Audit, integrity, and reporting

- `/auditonly` produces an applicability report for Windows and Office without installing packages; it still writes logs and temporary report files.
- Integrity verification, fail-closed checks in servicing paths, execution summaries, and restart-loop protection help diagnose incomplete or unusable update media.
- Audit output normally appears in `log/MissingUpdates.txt`, with a system-directory fallback. See the [command-line guide](README.md#command-line) for switches and report locations.

### Requirements and upgrade guidance

1. Preserve your existing client media, integrity databases, INI settings, and custom download/exclusion lists before replacing a working copy.
2. Install the **.NET 8 Desktop Runtime (x64)** and **WebView2 Runtime** before launching either modern application. Single-file executables still depend on these runtimes. Prepare runtime installers in advance for offline destinations.
3. When building from source, restore both npm projects and run `CompileModernApps.cmd --no-pause`. Keep the generated applications and their frontend assets with the project's scripts and data.
4. Review product selections and output paths before downloading. Transfer the **complete `client/` directory**, including Office content and integrity data, to preserve the offline installation environment.
5. Run the client with administrator privileges. Audit first when you need to review applicable updates before installation.

The English refresh preserves existing configuration keys, command arguments, and IPC action identifiers. No new configuration migration is introduced by the translation. Internal milestone numbers such as `v4.0` are development milestones; the application version remains `2026.10.0`.

### Known limitations

- The modern Generator displays Office 2016 MSI checkboxes and network/proxy fields, but its host does not currently dispatch MSI download jobs or forward the network settings. Use the corresponding scripts.
- Office-only selections do not schedule automatic ISO creation or USB copying in the modern host. Transfer the complete prepared client directory.
- Audit is available through the client command line; there is no visible audit control in the modern Installer.
- Generator catalog dates and last-run metadata currently use frontend defaults. Use repository files and logs to assess freshness, and review settings before each run.
- Generated ISO images contain update data; they are not bootable Windows installation images.
- Package availability, architecture, product entitlement, and Microsoft servicing eligibility determine what can be installed. Listed products do not imply complete update coverage or current vendor support.

See the [known limitations](README.md#known-limitations) for product-specific qualifications.

### Validation

The English UI refresh passed both TypeScript/Vite builds and both .NET 8 publications. Browser checks covered all six Generator tabs, both consoles, and Installer options; an isolated bridge stub verified selection and message handling. Source comparisons preserved 134 selection/IPC identifiers, and documentation checks validated local links and screenshot dimensions.

These checks did not perform real update downloads, installations, or restarts. They do not establish end-to-end servicing compatibility for every listed Windows or Office version.

### Credits and license

Thanks to Torsten Wittrock and the WSUS Offline Update Community Edition contributors for the foundation of this project. The supplied license is [GNU GPLv3](doc/license.txt). Earlier upstream changes remain documented in [the historical changelog](doc/history.txt).

## 2026.10.2

**Status:** current release.

### Monthly update refresh

- Static download links refreshed from the 2026-10 WSUS catalog: 0 links added, 0 retired links removed.


## 2026.11.0

**Status:** current release.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 0 retired links removed.


## 5.0.0+2026.11

**Status:** current release.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 0 retired links removed.


## 5.1.0+2026.11

**Status:** current release.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 0 retired links removed.


## 5.1.1+2026.11

**Status:** current release.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 0 retired links removed.


## 5.2.0+2026.11

**Status:** current release.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 0 retired links removed.


## 6.0.0+2026.11

**Status:** current release.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 0 retired links removed.


## 6.0.0+2026.11

**Status:** current release.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 0 retired links removed.


## 6.0.1+2026.11

**Status:** current release.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 0 retired links removed.


## 6.0.2+2026.11

**Status:** current release.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 0 retired links removed.


## 6.0.3+2026.11

**Status:** current release.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 0 retired links removed.


## 6.0.4+2026.11

**Status:** superseded by 6.1.0+2026.11.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 0 retired links removed.


## 6.1.0+2026.11

**Status:** current release.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 0 retired links removed.


## 6.1.1+2026.11

**Status:** superseded by 6.2.0+2026.11.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 2 retired links removed.

## 6.2.0+2026.11

**Status:** current release.

### Bug fix: the installer no longer crashes on machines with Office installed (issue #29)

- **Fixed a startup abort of the update engine** (`DoUpdate.cmd`) that hit every machine where an Office 2016-family product (Office 2016/2019, LTSC 2021/2024, Microsoft 365 Apps) was detected: the engine printed `) was unexpected at this time.` and exited (code 255) before installing anything. The Office information line was expanded inside a parenthesized `if` block while the Office end-of-life status itself contains parentheses ("EOL (End of Life - Oct 2025)"); the inner `)` closed the block early. The line now uses the parse-safe single-line form, and the displayed text is unchanged. A dedicated regression gate (`sh/tests/verify-office-eol-parens.bash`) replays the real engine lines against all four paren-bearing status values and both product-name shapes; it fails on the pre-fix engine (exit 255, 8/8 scenarios) and passes on the fixed one.

### Offline OS upgrades: selection, consent and acquisition (milestone v5.0, opt-in and disabled by default)

- **Windows OS upgrades are now a first-class, explicit choice.** Upgrades are never automatic: the capability stays **disabled by default** and requires explicit opt-in on every run. The generator GUI gains an **OS Upgrades tab** with a filtered list of eligible target builds (newest Enablement-first ordering), a media budget line with calm/warning/estimated states, a target-language rule, and arch-routed `/includeupgrade:<build>` spawn plumbing so the download pipeline acquires exactly the chosen upgrade payload.
- **Consent before bytes:** the installer consent surface names the target build, the deduced path, the disk cost, the estimated duration and the expected reboot count before anything is staged; the chosen-target guard in both upgrade build loops refuses any row that was not explicitly selected (CSV-only selection file, no free-form targets), and bare, colon-truncated or malformed `/upgradeos` arguments are refused at parse time with named errors.
- **UUP acquisition:** the download pipelines (CMD and bash twins) gained the upgrade acquisition task that fetches the chosen target's UUP payload and resolves its URL map, and the produced boot media carries the first-image flag (boot.wim index 9 setup requirement) so multi-edition upgrade media boots to the right image.
- **Full-upgrade mono-pass lane:** the engine wires a dedicated full-upgrade lane with an attempts ledger — write-before-launch, build-keyed stall halt, and advancement clear — plus the marker lifecycle (pose, converged clear, stall restore, stay-out) and a stub short-circuit (a 3010 stub outcome resolves to the recall-precedence exit 3011) so the recall engine and the upgrade lane can never fight after a reboot.
- **Media and gates:** the 37-link upgrade media gate (byte-frozen links 1-37, fail-closed) plus CMD/bash twin parity batteries cover the mapping, selection reader, resolver and refusal negatives (w61/wxp family exclusions, ineligible targets).

### Requirements and upgrade guidance

- Same requirements as 6.1.1: Windows 10 or 11 (x64) for the generator, .NET 8 and WebView2 for the modern interface (both bootstrapped from the tree when missing since 6.1.0), automatic fallback to the legacy native installer otherwise.
- Drop-in replacement: replace the previous tree with this one; configuration (`UpdateGenerator.ini`, `UpdateInstaller.ini`) and existing download repositories are preserved. No configuration migration is required.
- The OS-upgrade capability requires explicit opt-in and larger media budgets (the GUI budget line shows the estimate before download). Live multi-reboot upgrade acceptance runs on real VMs are still in progress and tracked in the project roadmap; until they complete, treat the upgrade lane as validated by the offline batteries and gates only.

### Validation

- Office-info regression gate: RED on the pre-fix engine (all 8 scenarios exit 255), GREEN after the fix; the merged tree passes.
- The upgrade argv acceptance battery passes on the merged engine (5/5 `/upgradeos` cases), and the 37-link media gate is green end-to-end in a single run.
- The release train runs the full batteries, the 15-file version bump, the build, the zip gates and the false-positive reputation gate before publishing.

## 6.2.0+2026.11

**Status:** current release.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 0 retired links removed.


## 6.2.1+2026.11

**Status:** current release.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 0 retired links removed.


## 6.3.0+2026.11

**Status:** current release.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 0 retired links removed.


## 6.3.1+2026.11

**Status:** superseded by 6.4.0+2026.11.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 0 retired links removed.


## 6.4.0+2026.11

**Status:** current release.

### Generator: download console no longer freezes mid-download (#47)

- The modern generator's download console kept every output line as a live interface row with no limit, and wget emits one progress line per ~50 KB — on fast connections the embedded browser view saturated after a while and the window stopped responding (and eventually stopped painting) while the download itself kept running.
- Console output is now capped to the newest 1000 entries, consecutive wget progress lines collapse into a single row with an `(xN)` repetition counter, and incoming log messages are batched into one render per 120 ms window. ERROR/WARN lines are never merged or dropped; the full history remains in `log\download.log`.

### Windows 7 / 8.1 / Server update selection restored (#45, #46)

- Restored the legacy supersession trim for w61/w63 targets: fresh trees no longer carry whole superseded security-only chains (the KB4556853 class on Windows 8.1 / Server 2012 R2), and the client-capable IE11 cumulative (KB5019958) is pinned for w63 — trees produced by 6.3.1 and earlier could produce the documented MMC/Internet Explorer breakage Microsoft itself describes for that KB.

### Client installer robustness

- Sibling `.cmd` calls now resolve through `%~dps0` (download pipeline, client installer, self-update): on hosts where `NoDefaultCurrentDirectoryInExePath=1`, bare-name calls failed silently with error 9009.
- The `UpdateInstaller.ini` rewrite keeps comment lines (`for /F eol=|`).

### Housekeeping

- Generated `iso/*-hashes.txt` digest files are now gitignored.

### Monthly update refresh

- Static download links refreshed from the 2026-11 WSUS catalog: 0 links added, 0 retired links removed.

