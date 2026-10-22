# Release notes

[Back to the project](README.md) · [Quick start](README.md#quick-start) · [Support development](https://liberapay.com/Jeremie/) · [LinkedIn](https://www.linkedin.com/in/jeremiedufault)

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

See the [coverage matrix](README.md#coverage) for product-specific qualifications.

### Validation

The English UI refresh passed both TypeScript/Vite builds and both .NET 8 publications. Browser checks covered all six Generator tabs, both consoles, and Installer options; an isolated bridge stub verified selection and message handling. Source comparisons preserved 134 selection/IPC identifiers, and documentation checks validated local links and screenshot dimensions.

These checks did not perform real update downloads, installations, or restarts. They do not establish end-to-end servicing compatibility for every listed Windows or Office version.

### Credits and license

Thanks to Torsten Wittrock and the WSUS Offline Update Community Edition contributors for the foundation of this project. The supplied license is [GNU GPLv3](doc/license.txt). Earlier upstream changes remain documented in [the historical changelog](doc/history.txt).
