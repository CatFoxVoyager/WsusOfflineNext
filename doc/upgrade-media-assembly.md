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

3. **CONSEQUENCE (the wimlib-only disposition):** a complete DISM-only assembly path
   does not exist for UUP sets. Until (and unless) wimlib-imagex is vendored under the
   license decision below, this toolchain can acquire, hash-verify, stage the raw set
   (plans 33-02/33-03) and extract the scaffold (command 1) - but `sources\install.esd`
   itself remains a documented external dependency, not a produced artifact.

## wimlib-imagex fallback (document-only - NOT EXECUTED IN THIS REPO)

The reference implementations (uup-dump converter `convert.sh` v0.7.3, both the Linux
and the Windows package path) assemble UUP sets with wimlib, not DISM. Reference
sequences, transcribed from the converter source read at research time:

```bash
# media tree from index 1
wimlib-imagex apply "$firstMetadata" 1 ISODIR --no-acls --no-attributes
# winre from index 2
wimlib-imagex export "$firstMetadata" 2 "$tempDir/winre.wim" --compress=maximum --boot
# component cabs are converted to ESDs first (cabextract -> wimlib-imagex capture),
# then one export per edition metadata ESD; repeated export appends indexes
wimlib-imagex export "$metadata" 3 ISODIR/sources/install.esd "$editionName" \
  --ref="$uupDir"/*.[eE][sS][dD]
```

`--ref` globs are exactly what DISM lacks - they resolve the external blob references
that killed the DISM export. These sequences are NOT EXECUTED IN THIS REPO: wimlib is
GPLv3+ (license verified from the upstream COPYING), and vendoring GPLv3+ binaries into
the distributed zip carries obligations the project has not accepted. Boundary per
ACQ-03: "licence vérifiée avant vendoring" - any future vendoring is an owner decision
that updates the consigned record first and the code after; wimlib stays un-vendored
this phase.

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
