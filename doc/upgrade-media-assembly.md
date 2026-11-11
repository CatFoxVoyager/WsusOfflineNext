# Upgrade media assembly - proven command set (spike 33-01 consignment)

Status: consigned 2026-11-11 by the Phase 33 spike (plan 33-01) on a real UUP set -
Windows 11 25H2, build 26200.9974, amd64, en-us, edition=0 (multi-edition:
core / coren / professional / professionaln + LanguagePack ESD), 196 payloads /
10,902,883,408 bytes, every file sha256-verified against the UUP `get.php` manifest
before any assembly probe ran (VERIFY-OK count=196 bytes=10902883408).

The consigned evidence lives in `.planning/tmp/33-spike/` (33-SPIKE-RECORD.md,
dism-probes.log, acquisition-transcript.md). This doc is the tracked summary of
what plan 33-04 and later media work may build on.

## The winning command set

The spike's answer is SPLIT - one proven DISM command, one consigned DISM failure,
one document-only fallback:

1. **PROVEN (PASS, 3 s, elevated):** extract the media scaffold from the metadata ESD's
   index 1 with in-box DISM:

   ```text
   dism /Apply-Image /ImageFile:D:\wou-spike\<set>\professional_en-us.esd ^
        /Index:1 /ApplyDir:D:\wou-spike\<media-root>
   ```

   This produces the complete setup tree in one step: `setup.exe` at the media root,
   `sources\` with the full setup binary set (setup.exe, setuphost.exe, setupprep.exe,
   setupcore.dll, dism.exe, ...), `boot\`, `efi\`, `support\`, `autorun.inf`,
   `bootmgr`, `bootmgr.efi`. Authenticode census of the scaffold's executables:
   207 embedded-signed; the 51 unsigned rows are `.mui` resources plus one
   catalog-signed migration DLL - the normal Microsoft media signing convention.
   Core setup binaries are all embedded-signed (`bin\sigcheck64.exe -accepteula -q
   -nobanner -utf8 -c -e -s <media>\sources`).

2. **CONSIGNED FAILURE (exit 1812, hr 0x80070714, `CWimManager::InternalCmdExport`):**
   in-box DISM cannot produce `sources\install.esd` from the metadata ESD:

   ```text
   dism /Export-Image /SourceImageFile:<metadata-esd> /SourceIndex:3 ^
        /DestinationImageFile:<media-root>\sources\install.esd /Compress:recovery
   ```

   The export reaches ~99% and fails with "image did not contain a resource section"
   (Win32 1812). The OS image (index 3) of a UUP metadata ESD references its payload
   blobs externally - they live in the sibling component cabs of the set - and DISM's
   documented option set has no reference-resolution equivalent. The failure occurred
   with ALL 196 sibling payload files present in the SAME directory as the metadata
   ESD, so no file-layout workaround exists. The multi-edition append probe and the
   `.swm` split probe are BLOCKED by this prerequisite failure (no install.esd exists
   to append to or split).

3. **CONSEQUENCE (resolved by the vendoring decision):** a complete DISM-only assembly
   path does not exist for UUP sets. The owner's 2026-11-11 decision (plan 33-04) vendored
   wimlib-imagex, so `sources\install.esd` IS now produced by this toolchain: the shipped
   assembly stage is `cmd\UpgradePayloads.cmd :UpgAssembleMedia`, which runs the wimlib
   sequences below through the vendored binaries (scaffold apply from index 1, install.esd
   export per edition with --ref globs, info census). The consigned DISM failure stands as
   the reason the in-box path is not used for the export step.

## wimlib-imagex (vendored per the owner decision of 2026-11-11 - the shipped mechanism)

The reference implementations (uup-dump converter `convert.sh` v0.7.3, both the Linux
and the Windows package path) assemble UUP sets with wimlib, not DISM. The owner's
2026-11-11 decision (plan 33-04 of milestone v5.0) accepted the GPLv3+ obligations and
VENDORED the wimlib-imagex Windows binaries into `bin\wimlib\` (x64 + x86, version
1.14.5 from https://wimlib.net/downloads/, COPYING texts verbatim, provenance in
`bin\wimlib\LICENSE-NOTES`, SHA256 pins in `bin\wimlib\SHA256SUMS`, fail-closed
verification before any invocation, no UPX). License boundary per ACQ-03
("licence vérifiée avant vendoring"): the CLI is GPLv3+, the library LGPLv3+, and the
license documentation ships beside the binaries.

The reference sequences (transcribed from the converter source read at research time)
are what the shipped assembly stage implements through the vendored binaries -
executed for the first time against the real 26200 set on 2026-11-11 (158 component
cabs converted, 4 editions exported into a 2.5 GB multi-edition install.esd, census
green):

```bash
# media tree from index 1
wimlib-imagex apply "$firstMetadata" 1 ISODIR --no-acls --no-attributes
# component cabs are converted to ESDs first (extract -> wimlib-imagex capture),
# then one export per edition metadata ESD; repeated export appends indexes
wimlib-imagex export "$metadata" 3 ISODIR/sources/install.esd "$editionName" \
  --solid --ref="$uupDir"/*.esd
```

`--ref` globs are exactly what DISM lacks - they resolve the external blob references
that killed the DISM export. Windows-side measured facts baked into the shipped stage:
the Windows wimlib build's `--ref` IS the glob form (there is no `--ref-glob` there),
its glob rejects `[eE]` character classes and `..` path segments (plain `*.esd`
patterns against clean absolute paths only - Windows globbing is case-insensitive so
the .ESD payload files are covered), and component-cab extraction uses the in-box
`System32\expand.exe` (no cabextract on Windows generators). The assembly needs NO
elevation - the DEC-33-13 targeted-RunAs policy (built for in-box DISM) has no surface
on the shipped path; its fail-closed refusal discipline is preserved on every
tool-gate failure.

## FAT32 / exFAT-NTFS guidance (ACQ-05, DEC-33-11)

Recommended: stage the assembled media on **exFAT or NTFS** - the media's dominant
artifacts (install.esd of a multi-edition set, and the 4.4 GiB cumulative MSU present
in the raw set) exceed FAT32's 4 GiB-per-file limit.

FAT32 alternative: the `.swm` split path is documented but its evidence is BLOCKED -
the spike could not measure `dism /Split-Image` on an ESD because no install.esd could
be produced (probe failure above). The reference command, to be proven only after a
working install.esd assembly exists:

```text
dism /Split-Image /ImageFile:<media>\sources\install.esd ^
     /SWMFile:<media>\sources\install.swm /FileSize:3800
```

DISM documents Split-Image "for WIM"; whether it splits an ESD cleanly is exactly the
unproven edge the research flagged. Do not rely on it until measured; exFAT/NTFS is
the owner-accepted path in the meantime.

## Revision churn (ACQ-08 / DEC-33-08)

UUP revisions for a target build churn weekly (the spike's uuid was researched and
executed on the same day and was still current; older revisions age out of the API
list). The purge contract - keep exactly one revision per target x lang x arch, keyed
on the staged manifest uuid, running only after successful assembly + verification -
is owned by plan 33-04; `client/upgrade/` is deliberately invisible to the existing
cleanup walk and gets its own purge step, never a cleanup-hook retrofit.
