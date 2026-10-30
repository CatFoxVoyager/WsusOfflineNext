#!/usr/bin/env bash
# Fixture test for ci/fetch-release-helpers.bash - run from repo root.
# Offline by construction: fake wget and fake unzip are prepended to PATH for
# the script invocations only, and the sidecar is recomputed by this test from
# the same fixture bytes, so no hash is hardcoded.
# Covered behaviors: green fetch (4 pins verified), tampered pin (exit != 0,
# expected + observed digests printed), unpinned helper (exit != 0, refusal),
# mid-transfer failure (CISC-04: exit != 0, NO bin/mkisofs.exe, no residue),
# non-PE stream refused even with a consistent pin (exit != 0, refusal),
# wrong mkisofs stream refused BEFORE install (WR-04: exit != 0, NO
# bin/mkisofs.exe, no residue — the pin gates the temp, not the install),
# Authenticode tier-2 refuses an "Unsigned" verdict (WR-02: the anchored
# Verified-line match must not launder what tier 1 just refused; needs a
# Windows-side bash host — documented capability skip elsewhere)
set -u
STUB="$(mktemp -d)"
mkdir -p "$STUB"

cat > "$STUB/wget" <<'WGET_EOF'
#!/usr/bin/env bash
# fake wget: writes deterministic fixture bytes keyed by the URL basename
set -u
dir=""
out=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -N|-q) shift ;;
    -P) dir="$2"; shift 2 ;;
    -O) out="$2"; shift 2 ;;
    *) url="$1"; shift ;;
  esac
done
[ -n "$url" ] || { echo "fake-wget: no URL" >&2; exit 1; }
name="$(basename "$url")"
if [ -n "$out" ]; then
  # the -O path serves mkisofs.exe and the ODT installer: bytes carry a PE
  # header because the script refuses a non-PE stream before the atomic move
  # (CISC-04); the ODT installer fixture embeds the MSCF marker at a fixed
  # offset so the carve has something to find, and the marker-less variant
  # (served only when FAKE_WGET_ODT_VARIANT=nomscf) drives the carve refusal
  if [ "$name" = "officedeploymenttool_20430-20146.exe" ] && [ -n "${ODT_FIXTURE_INSTALLER:-}" ]; then
    if [ "${FAKE_WGET_ODT_VARIANT:-}" = "nomscf" ] && [ -n "${ODT_FIXTURE_INSTALLER_NOMSCF:-}" ]; then
      cat "${ODT_FIXTURE_INSTALLER_NOMSCF}" > "$out"
    else
      cat "${ODT_FIXTURE_INSTALLER}" > "$out"
    fi
  else
    printf 'MZ%s' "$name" > "$out"
  fi
else
  printf '%s' "$name" > "$dir/$name"
fi
WGET_EOF

cat > "$STUB/unzip" <<'UNZIP_EOF'
#!/usr/bin/env bash
# fake unzip: accepts the call shape of ci/fetch-release-helpers.bash
# (-o -q -x Eula.txt -d <dest> <zip>) and creates the files the real unpack
# produces, keyed by the zip basename
set -u
zip=""
dest=""
want_dest=0
for a in "$@"; do
  case "$a" in
    -o|-q|-x|Eula.txt) ;;
    -d) want_dest=1 ;;
    *)  if [ "$want_dest" -eq 1 ]; then dest="$a"; want_dest=0; else zip="$a"; fi ;;
  esac
done
[ -n "$zip" ] && [ -n "$dest" ] || { echo "fake-unzip: need zip and -d dest" >&2; exit 1; }
# stand-in for the tracked vendored unzip: a plain (non-executable-content)
# file so the script's vendored-copy branch fires. Created here, not by the
# scaffold, because on MSYS hosts [ -x ] is TRUE for ANY existing *.exe and a
# pre-created plain bin/unzip.exe would hijack resolve_tools and silently
# no-op every unpack.
[ -f bin/unzip.exe ] || printf 'vendored-unzip-stub\n' > bin/unzip.exe
case "$(basename "$zip")" in
    AutoLogon.zip) printf 'Autologon.exe-fixture' > "$dest/Autologon.exe" ;;
    Sigcheck.zip)
        # case l knob (WR-02): serve an MZ-qualified sigcheck64 stand-in whose
        # -vt leg refuses and whose -q leg prints the real tool's UTF-16
        # unsigned verdict. Default stays the plain non-PE fixture: the tier
        # then takes its documented skip line.
        if [ -n "${SIGCHECK_STUB_FILE:-}" ]; then
            cat "${SIGCHECK_STUB_FILE}" > "$dest/sigcheck64.exe"
            chmod +x "$dest/sigcheck64.exe" 2>/dev/null || true
        else
            printf 'sigcheck64.exe-fixture' > "$dest/sigcheck64.exe"
        fi ;;
    Streams.zip)   printf 'streams64.exe-fixture' > "$dest/streams64.exe" ;;
    *) : ;;
esac
exit 0
UNZIP_EOF

cat > "$STUB/cabextract" <<'CAB_EOF'
#!/usr/bin/env bash
# fake cabextract: implements the -q -d <dest> <cab> call shape of the ODT
# block and writes the fixture setup.exe (MZ bytes + fixed text, so the
# script's MZ check passes) plus a metadata file the real extractor produces
# alongside it; cab contents are irrelevant in the stub world
set -u
dest=""
want_dest=0
for a in "$@"; do
  case "$a" in
    -q) ;;
    -d) want_dest=1 ;;
    *)  if [ "$want_dest" -eq 1 ]; then dest="$a"; want_dest=0; fi ;;
  esac
done
[ -n "$dest" ] || { echo "fake-cabextract: need -d dest" >&2; exit 1; }
mkdir -p "$dest"
cat "${ODT_FIXTURE_SETUP:?}" > "$dest/setup.exe"
printf 'odt-eula-fixture' > "$dest/EULA"
exit 0
CAB_EOF

chmod +x "$STUB/wget" "$STUB/unzip" "$STUB/cabextract"

# ODT fixtures: ONE source of truth for both the stub bytes and the scaffold
# pins (house invariant: scaffold and stub must move together, or the green
# case gates the wrong bytes). The installer fixture embeds the MSCF marker at
# offset 98 (MZ + 96 filler bytes); the marker-less variant drives the
# carve-refusal case.
ODT_FILLER="$(printf 'x%.0s' {1..96})"
printf 'MZ%sMSCFcab-content-irrelevant' "${ODT_FILLER}" > "$STUB/fixture-odt-installer.bin"
printf 'MZ%sno-cab-marker-inside' "${ODT_FILLER}" > "$STUB/fixture-odt-installer-nomscf.bin"
printf 'MZodt-setup-exe-fixture' > "$STUB/fixture-odt-setup.bin"
export ODT_FIXTURE_INSTALLER="$STUB/fixture-odt-installer.bin"
export ODT_FIXTURE_INSTALLER_NOMSCF="$STUB/fixture-odt-installer-nomscf.bin"
export ODT_FIXTURE_SETUP="$STUB/fixture-odt-setup.bin"

function scaffold ()
{
    local t="$1"
    local n
    local h
    mkdir -p "${t}/ci" "${t}/static" "${t}/bin"
    cp ci/fetch-release-helpers.bash "${t}/ci/"
    cp static/StaticDownloadLinks-sysinternals.txt "${t}/static/"
    # bin/unzip.exe is intentionally absent here: the fake unzip creates the
    # plain stand-in mid-run (see the stub), so resolve_tools falls through to
    # the PATH stub on every host and the vendored-copy branch still runs
    for n in AutoLogon.zip Sigcheck.zip Streams.zip mkisofs.exe officedeploymenttool_20430-20146.exe setup.exe; do
        # the mkisofs pin is recomputed over the SAME bytes the stub wget -O
        # writes (MZ + basename), and the two ODT pins over the SAME fixture
        # files the stubs copy: scaffold and stub must move together or the
        # green case would test the hash gate against the wrong bytes
        if [ "${n}" = "mkisofs.exe" ]; then
            h="$(printf 'MZ%s' "${n}" | sha256sum | cut -d' ' -f1)"
        elif [ "${n}" = "officedeploymenttool_20430-20146.exe" ]; then
            h="$(sha256sum "${ODT_FIXTURE_INSTALLER:?}" | cut -d' ' -f1)"
        elif [ "${n}" = "setup.exe" ]; then
            h="$(sha256sum "${ODT_FIXTURE_SETUP:?}" | cut -d' ' -f1)"
        else
            h="$(printf '%s' "${n}" | sha256sum | cut -d' ' -f1)"
        fi
        printf '%s  %s\n' "${h}" "${n}"
    done > "${t}/ci/release-helper-hashes.sha256"
}

# ---- case a: green - correct sidecar, exit 0, all four SHA256 OK lines ----
T="$(mktemp -d)"
scaffold "$T"
PATH="$STUB:$PATH" bash "${T}/ci/fetch-release-helpers.bash" > "${T}/out.log" 2>&1
rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: green case exited $rc"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
for n in AutoLogon.zip Sigcheck.zip Streams.zip mkisofs.exe; do
    grep -qF "SHA256 OK ${n}" "${T}/out.log" \
        || { echo "FAIL: green case missing SHA256 OK for ${n}"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
done
grep -qF 'Autologon.exe-fixture' "${T}/client/bin/Autologon.exe" \
    || { echo "FAIL: unzip stub did not produce the fixture exe"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
rm -rf "$T"

# ---- case b: tampered pin - Streams.zip zeroed, exit != 0, observed digest ----
T="$(mktemp -d)"
scaffold "$T"
TRUE_STREAMS="$(printf '%s' "Streams.zip" | sha256sum | cut -d' ' -f1)"
sed -i 's/^\([0-9a-f]\)[0-9a-f]\{63\}  Streams.zip/0000000000000000000000000000000000000000000000000000000000000000  Streams.zip/' "${T}/ci/release-helper-hashes.sha256"
PATH="$STUB:$PATH" bash "${T}/ci/fetch-release-helpers.bash" > "${T}/out.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: tamper case exited 0"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
grep -qF 'SHA256 MISMATCH for Streams.zip' "${T}/out.log" \
    || { echo "FAIL: tamper case missing MISMATCH line"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
grep -qF "observed: ${TRUE_STREAMS}" "${T}/out.log" \
    || { echo "FAIL: tamper case missing observed true hash"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
rm -rf "$T"

# ---- case c: unpinned helper - Sigcheck.zip pin deleted, exit != 0, refusal ----
T="$(mktemp -d)"
scaffold "$T"
sed -i '/  Sigcheck.zip$/d' "${T}/ci/release-helper-hashes.sha256"
PATH="$STUB:$PATH" bash "${T}/ci/fetch-release-helpers.bash" > "${T}/out.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: unpinned case exited 0"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
grep -qF 'no SHA256 pin for Sigcheck.zip' "${T}/out.log" \
    || { echo "FAIL: unpinned case missing refusal"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
rm -rf "$T"

# ---- case d: atomicity - mid-transfer failure leaves NO mkisofs and NO residue ----
# CISC-04 (WR-12): the -O form truncates the FINAL path before transferring, so
# a dead download used to leave a partial that the existence guard then blessed
# forever. The next run must re-download, never adopt the partial.
T="$(mktemp -d)"
STUB_D="$(mktemp -d)"
cat > "$STUB_D/wget" <<'WGET_D_EOF'
#!/usr/bin/env bash
# fake wget (atomicity case): zips behave normally, mkisofs.exe writes a
# partial then dies mid-transfer
set -u
dir=""
out=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -N|-q) shift ;;
    -P) dir="$2"; shift 2 ;;
    -O) out="$2"; shift 2 ;;
    *) url="$1"; shift ;;
  esac
done
[ -n "$url" ] || { echo "fake-wget: no URL" >&2; exit 1; }
name="$(basename "$url")"
if [ "$name" = "mkisofs.exe" ]; then
  printf 'MZpartial' > "$out"
  exit 1
fi
if [ -n "$out" ]; then
  printf 'MZ%s' "$name" > "$out"
else
  printf '%s' "$name" > "$dir/$name"
fi
WGET_D_EOF
chmod +x "$STUB_D/wget"
cp "$STUB/unzip" "$STUB_D/unzip"
scaffold "$T"
PATH="$STUB_D:$PATH" bash "${T}/ci/fetch-release-helpers.bash" > "${T}/out.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: atomicity case exited 0"; cat "${T}/out.log"; rm -rf "$T" "$STUB_D" "$STUB"; exit 1; }
[ ! -f "${T}/bin/mkisofs.exe" ] || { echo "FAIL: atomicity case left the partial at bin/mkisofs.exe (CISC-04 bite)"; cat "${T}/out.log"; rm -rf "$T" "$STUB_D" "$STUB"; exit 1; }
residue="$(cd "${T}/bin" && ls mkisofs.exe.* 2>/dev/null || true)"
[ -z "${residue}" ] || { echo "FAIL: atomicity case left temp residue: ${residue}"; cat "${T}/out.log"; rm -rf "$T" "$STUB_D" "$STUB"; exit 1; }
rm -rf "$T" "$STUB_D"

# ---- case e: PE refusal - a non-PE stream is refused EVEN WITH a consistent pin ----
# Isolates the PE check: the sidecar pin is recomputed over the notape bytes, so
# the hash gate would PASS - only the MZ check can refuse the download.
T="$(mktemp -d)"
STUB_E="$(mktemp -d)"
cat > "$STUB_E/wget" <<'WGET_E_EOF'
#!/usr/bin/env bash
# fake wget (PE-refusal case): zips behave normally, mkisofs.exe serves a
# non-PE payload and succeeds
set -u
dir=""
out=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -N|-q) shift ;;
    -P) dir="$2"; shift 2 ;;
    -O) out="$2"; shift 2 ;;
    *) url="$1"; shift ;;
  esac
done
[ -n "$url" ] || { echo "fake-wget: no URL" >&2; exit 1; }
name="$(basename "$url")"
if [ "$name" = "mkisofs.exe" ]; then
  printf 'notape' > "$out"
  exit 0
fi
if [ -n "$out" ]; then
  printf 'MZ%s' "$name" > "$out"
else
  printf '%s' "$name" > "$dir/$name"
fi
WGET_E_EOF
chmod +x "$STUB_E/wget"
cp "$STUB/unzip" "$STUB_E/unzip"
scaffold "$T"
NOTAPE_H="$(printf 'notape' | sha256sum | cut -d' ' -f1)"
grep -v '  mkisofs.exe$' "${T}/ci/release-helper-hashes.sha256" > "${T}/pins.tmp"
printf '%s  mkisofs.exe\n' "${NOTAPE_H}" >> "${T}/pins.tmp"
mv "${T}/pins.tmp" "${T}/ci/release-helper-hashes.sha256"
PATH="$STUB_E:$PATH" bash "${T}/ci/fetch-release-helpers.bash" > "${T}/out.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: PE-refusal case exited 0 (non-PE blessed)"; cat "${T}/out.log"; rm -rf "$T" "$STUB_E" "$STUB"; exit 1; }
[ ! -f "${T}/bin/mkisofs.exe" ] || { echo "FAIL: PE-refusal case left bin/mkisofs.exe in place"; cat "${T}/out.log"; rm -rf "$T" "$STUB_E" "$STUB"; exit 1; }
grep -qF 'not a PE binary' "${T}/out.log" \
    || { echo "FAIL: PE-refusal case missing PE refusal message"; cat "${T}/out.log"; rm -rf "$T" "$STUB_E" "$STUB"; exit 1; }
residue="$(cd "${T}/bin" && ls mkisofs.exe.* 2>/dev/null || true)"
[ -z "${residue}" ] || { echo "FAIL: PE-refusal case left temp residue: ${residue}"; cat "${T}/out.log"; rm -rf "$T" "$STUB_E" "$STUB"; exit 1; }
rm -rf "$T" "$STUB_E"

# ---- case f: URL list materialised CRLF (fresh checkout) must fuse cleanly ----
# .gitattributes materialise *.txt en CRLF : un CR survivant dans l'URL corrompt
# zip_name (le telechargement atterrit meme dans un fichier nomme avec CR dans
# bin/) et rate chaque pin SHA256 sous un grep strict (Linux) — run ubuntu
# 41012438351 refusait AutoLogon.zip comme unpinned. En local, le grep MSYS avale
# le CR a la lecture : ce cas mord sur ubuntu seulement (miroir 15-01 sans shim —
# il epingle que le fix ne depend pas de l'hote).
T="$(mktemp -d)"
scaffold "$T"
printf 'https://download.sysinternals.com/files/AutoLogon.zip,alias\r\nhttps://download.sysinternals.com/files/Sigcheck.zip\r\nhttps://download.sysinternals.com/files/Streams.zip\r\n' > "${T}/static/StaticDownloadLinks-sysinternals.txt"
PATH="$STUB:$PATH" bash "${T}/ci/fetch-release-helpers.bash" > "${T}/out.log" 2>&1
rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: CRLF URL-list case exited $rc"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
grep -qF 'SHA256 OK AutoLogon.zip' "${T}/out.log" \
    || { echo "FAIL: CRLF URL-list - pin AutoLogon non verifie (zip_name corrompu ?)"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
[ -f "${T}/bin/AutoLogon.zip" ] \
    || { echo "FAIL: CRLF URL-list - bin/AutoLogon.zip absent (fichier nomme avec CR ?)"; ls -b "${T}/bin"; rm -rf "$T" "$STUB"; exit 1; }
# instrument CR-safe : le glob bash pur, pas ls|grep (le ls MSYS emet des fins
# de ligne CRLF — tout nom matcherait, classe « instruments emit CRLF »)
set -- "${T}/bin/"*$'\r'*
cr_named=0
[ -f "$1" ] && cr_named=$#
[ "${cr_named}" -eq 0 ] || { echo "FAIL: CRLF URL-list - ${cr_named} fichier(s) nomme(s) avec CR dans bin/"; ls -b "${T}/bin"; rm -rf "$T" "$STUB"; exit 1; }
rm -rf "$T"

# ---- case g: hash gate BEFORE install (WR-04) - a wrong mkisofs stream must
# never reach bin/. The scaffold's pin still describes the REAL bytes while
# the stub serves tampered ones: the served bytes pass the MZ check but NOT
# the pin, so the SHA256 gate is the only refusal left (mirror of case e,
# which isolated the MZ check with a consistent pin). Pre-fix the mv ran
# first and the unpinned binary stayed installed (header invariant violated),
# and the next run's existence guard blessed it forever.
T="$(mktemp -d)"
STUB_G="$(mktemp -d)"
cat > "$STUB_G/wget" <<'WGET_G_EOF'
#!/usr/bin/env bash
# fake wget (WR-04 case): zips behave normally, mkisofs.exe serves bytes that
# pass the MZ check but not the pin
set -u
dir=""
out=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -N|-q) shift ;;
    -P) dir="$2"; shift 2 ;;
    -O) out="$2"; shift 2 ;;
    *) url="$1"; shift ;;
  esac
done
[ -n "$url" ] || { echo "fake-wget: no URL" >&2; exit 1; }
name="$(basename "$url")"
if [ "$name" = "mkisofs.exe" ]; then
  printf 'MZtampered' > "$out"
  exit 0
fi
if [ -n "$out" ]; then
  printf 'MZ%s' "$name" > "$out"
else
  printf '%s' "$name" > "$dir/$name"
fi
WGET_G_EOF
chmod +x "$STUB_G/wget"
cp "$STUB/unzip" "$STUB_G/unzip"
scaffold "$T"
PATH="$STUB_G:$PATH" bash "${T}/ci/fetch-release-helpers.bash" > "${T}/out.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: mkisofs tamper case exited 0"; cat "${T}/out.log"; rm -rf "$T" "$STUB_G" "$STUB"; exit 1; }
grep -qF 'SHA256 MISMATCH for mkisofs.exe' "${T}/out.log" \
    || { echo "FAIL: mkisofs tamper case missing MISMATCH line"; cat "${T}/out.log"; rm -rf "$T" "$STUB_G" "$STUB"; exit 1; }
[ ! -f "${T}/bin/mkisofs.exe" ] || { echo "FAIL: mkisofs tamper left the UNPINNED binary installed in bin/ (WR-04 bite)"; cat "${T}/out.log"; rm -rf "$T" "$STUB_G" "$STUB"; exit 1; }
residue="$(cd "${T}/bin" && ls mkisofs.exe.* 2>/dev/null || true)"
[ -z "${residue}" ] || { echo "FAIL: mkisofs tamper left temp residue: ${residue}"; cat "${T}/out.log"; rm -rf "$T" "$STUB_G" "$STUB"; exit 1; }
rm -rf "$T" "$STUB_G"

# ---- case h: ODT green - the full chain offline ----
# The stub wget serves the marker-embedded installer fixture, the stub
# cabextract writes the fixture setup.exe and the scaffold pins describe
# exactly those bytes: download -> installer pin -> carve -> extract -> MZ ->
# sigcheck tier -> payload pin -> integrate must run green OFFLINE. The
# plain-text sigcheck64.exe stand-in (not MZ) must take the documented skip
# line - the tier's MZ guard is what keeps the Authenticode check honest when
# only a stand-in exists (MSYS executes any existing .exe as a silent rc=0
# no-op). TMPDIR is pinned inside the temp tree so the mktemp -d work dir is
# residue-assertable like the bin/odt sibling temp.
T="$(mktemp -d)"
scaffold "$T"
mkdir -p "${T}/tmp"
TMPDIR="${T}/tmp" PATH="$STUB:$PATH" bash "${T}/ci/fetch-release-helpers.bash" > "${T}/out.log" 2>&1
rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: ODT green case exited $rc"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
cmp -s "${T}/bin/odt/setup.exe" "${ODT_FIXTURE_SETUP}" \
    || { echo "FAIL: ODT green case - bin/odt/setup.exe != fixture bytes"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
grep -qF 'SHA256 OK officedeploymenttool_20430-20146.exe' "${T}/out.log" \
    || { echo "FAIL: ODT green case missing installer SHA256 OK"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
grep -qF 'SHA256 OK setup.exe' "${T}/out.log" \
    || { echo "FAIL: ODT green case missing setup.exe SHA256 OK"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
grep -qF 'bin/odt/setup.exe: OK' "${T}/out.log" \
    || { echo "FAIL: ODT green case missing summary OK entry"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
grep -qF 'Authenticode tier skipped' "${T}/out.log" \
    || { echo "FAIL: ODT green case - non-PE sigcheck stand-in did not take the skip line"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
[ -f "${T}/bin/odt/EULA" ] \
    || { echo "FAIL: ODT green case - metadata payload not integrated"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
set -- "${T}/bin/odt/"*.XXXXXX
[ -f "$1" ] && { echo "FAIL: ODT green case left installer temp residue"; ls -A "${T}/bin/odt"; rm -rf "$T" "$STUB"; exit 1; }
[ -z "$(ls -A "${T}/tmp")" ] || { echo "FAIL: ODT green case left work-dir residue in TMPDIR"; ls -A "${T}/tmp"; rm -rf "$T" "$STUB"; exit 1; }
rm -rf "$T"

# ---- case i: tampered setup.exe pin - refusal on the TEMP, never integrated ----
# The zeroed pin (same shape as case b) must fail the temp-path gate BEFORE the
# move: exit nonzero, MISMATCH names setup.exe, no bin/odt/setup.exe, and the
# EXIT trap leaves no installer temp and no work dir behind.
T="$(mktemp -d)"
scaffold "$T"
mkdir -p "${T}/tmp"
sed -i 's/^\([0-9a-f]\)[0-9a-f]\{63\}  setup.exe/0000000000000000000000000000000000000000000000000000000000000000  setup.exe/' "${T}/ci/release-helper-hashes.sha256"
TMPDIR="${T}/tmp" PATH="$STUB:$PATH" bash "${T}/ci/fetch-release-helpers.bash" > "${T}/out.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: ODT tamper case exited 0"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
grep -qF 'SHA256 MISMATCH for setup.exe' "${T}/out.log" \
    || { echo "FAIL: ODT tamper case missing MISMATCH line"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
[ ! -f "${T}/bin/odt/setup.exe" ] || { echo "FAIL: ODT tamper case left bin/odt/setup.exe installed"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
set -- "${T}/bin/odt/"*.XXXXXX
[ -f "$1" ] && { echo "FAIL: ODT tamper case left installer temp residue"; ls -A "${T}/bin/odt"; rm -rf "$T" "$STUB"; exit 1; }
[ -z "$(ls -A "${T}/tmp")" ] || { echo "FAIL: ODT tamper case left work-dir residue in TMPDIR"; ls -A "${T}/tmp"; rm -rf "$T" "$STUB"; exit 1; }
rm -rf "$T"

# ---- case j: marker-less installer - the carve refuses ----
# CI never executes the upstream installer (deliberate divergence from the
# CMD's silent-installer fallback), so a served stream without the MSCF marker
# must exit nonzero with the carve refusal and leave no residue. The installer
# pin is recomputed over the marker-less fixture bytes so the hash gate PASSES
# and only the carve check can refuse (same isolation as case e, which
# recomputes the mkisofs pin over notape bytes).
T="$(mktemp -d)"
scaffold "$T"
mkdir -p "${T}/tmp"
NOMSCF_H="$(sha256sum "${ODT_FIXTURE_INSTALLER_NOMSCF}" | cut -d' ' -f1)"
grep -v '  officedeploymenttool_20430-20146.exe$' "${T}/ci/release-helper-hashes.sha256" > "${T}/pins.tmp"
printf '%s  officedeploymenttool_20430-20146.exe\n' "${NOMSCF_H}" >> "${T}/pins.tmp"
mv "${T}/pins.tmp" "${T}/ci/release-helper-hashes.sha256"
TMPDIR="${T}/tmp" FAKE_WGET_ODT_VARIANT=nomscf PATH="$STUB:$PATH" bash "${T}/ci/fetch-release-helpers.bash" > "${T}/out.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: ODT no-MSCF case exited 0"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
grep -qF 'no MSCF offset in the installer' "${T}/out.log" \
    || { echo "FAIL: ODT no-MSCF case missing carve refusal"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
[ ! -f "${T}/bin/odt/setup.exe" ] || { echo "FAIL: ODT no-MSCF case left bin/odt/setup.exe installed"; cat "${T}/out.log"; rm -rf "$T" "$STUB"; exit 1; }
set -- "${T}/bin/odt/"*.XXXXXX
[ -f "$1" ] && { echo "FAIL: ODT no-MSCF case left installer temp residue"; ls -A "${T}/bin/odt"; rm -rf "$T" "$STUB"; exit 1; }
[ -z "$(ls -A "${T}/tmp")" ] || { echo "FAIL: ODT no-MSCF case left work-dir residue in TMPDIR"; ls -A "${T}/tmp"; rm -rf "$T" "$STUB"; exit 1; }
rm -rf "$T"

# ---- case k: no cab extractor - resolution refusal on every host ----
# PATH without the cabextract stub AND WINDIR pointing outside any System32:
# the script never consults the bare `expand` name (GNU coreutils trap on
# git-bash hosts), so both resolution legs collapse to the same refusal on
# either host family - Linux has no cygpath, git-bash misses the stub dir.
T="$(mktemp -d)"
STUB_K="$(mktemp -d)"
cp "$STUB/wget" "$STUB/unzip" "$STUB_K/"
chmod +x "$STUB_K/wget" "$STUB_K/unzip"
scaffold "$T"
mkdir -p "${T}/tmp" "${T}/nowin"
TMPDIR="${T}/tmp" WINDIR="${T}/nowin" PATH="$STUB_K:$PATH" bash "${T}/ci/fetch-release-helpers.bash" > "${T}/out.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: ODT missing-extractor case exited 0"; cat "${T}/out.log"; rm -rf "$T" "$STUB_K" "$STUB"; exit 1; }
grep -qF 'no cab extractor' "${T}/out.log" \
    || { echo "FAIL: ODT missing-extractor case missing extractor refusal"; cat "${T}/out.log"; rm -rf "$T" "$STUB_K" "$STUB"; exit 1; }
[ ! -f "${T}/bin/odt/setup.exe" ] || { echo "FAIL: ODT missing-extractor case left bin/odt/setup.exe installed"; cat "${T}/out.log"; rm -rf "$T" "$STUB_K" "$STUB"; exit 1; }
set -- "${T}/bin/odt/"*.XXXXXX
[ -f "$1" ] && { echo "FAIL: ODT missing-extractor case left installer temp residue"; ls -A "${T}/bin/odt"; rm -rf "$T" "$STUB_K" "$STUB"; exit 1; }
[ -z "$(ls -A "${T}/tmp")" ] || { echo "FAIL: ODT missing-extractor case left work-dir residue in TMPDIR"; ls -A "${T}/tmp"; rm -rf "$T" "$STUB_K" "$STUB"; exit 1; }
rm -rf "$T" "$STUB_K"

# ---- case l: Authenticode tier-2 must NOT launder an unsigned binary (WR-02) ----
# The MZ-qualified sigcheck64 stand-in refuses tier 1 (-vt) and answers tier 2
# (-q) with the real tool's UTF-16 "Verified: <TAB> Unsigned" verdict: the
# script must refuse (rc != 0, refusal line, nothing integrated, no residue).
# Pre-fix the unanchored `grep -iq signed` matched the "signed" SUBSTRING of
# "Unsigned" and tier 2 blessed exactly the binaries tier 1 had refused.
# Windows-side bash hosts only (the tier needs WINDIR + cygpath): elsewhere
# the case takes a documented capability skip. The stand-in's executability is
# PROBED, not assumed (an MSYS-class host that no-ops non-PE .exe files would
# silently pass tier 1 and turn this case into a false red).
T="$(mktemp -d)"
scaffold "$T"
mkdir -p "${T}/tmp"
cat > "${STUB}/fixture-sigcheck-unsigned.exe" <<'SIGCHECK_L_EOF'
MZ() { :; }
# fake sigcheck64 (WR-02 case): MZ stays the first two bytes - the script's
# MZ guard is what qualifies the stand-in for the tier at all. Call shapes to
# model: tier 1 "-accepteula -q -vt <target>" (verify mode, rc 1 on unsigned),
# tier 2 "-accepteula -q <target>" (quiet dump of the UTF-16 verdict text).
vt=""
for a in "$@"; do
  case "$a" in
    -vt) vt=1 ;;
    -probe) echo PROBE-OK; exit 0 ;;
  esac
done
if [ -n "${vt}" ]; then
  exit 1
fi
printf 'Signing Certificate Chain:\0\n\0Verified:\tUnsigned\r\0\n\0'
exit 0
SIGCHECK_L_EOF
chmod +x "${STUB}/fixture-sigcheck-unsigned.exe" 2>/dev/null || true
probe_out="$("${STUB}/fixture-sigcheck-unsigned.exe" -accepteula -probe 2>/dev/null || true)"
if [ -z "${WINDIR:-}" ] || ! command -v cygpath >/dev/null 2>&1; then
    echo "SKIP case l: Authenticode tier needs a Windows-side bash host (WINDIR + cygpath) - documented host skip"
    rm -rf "${T}"
elif [ "${probe_out}" != "PROBE-OK" ]; then
    echo "SKIP case l: host cannot execute the MZ-prefixed stand-in (silent no-op class) - documented host skip"
    rm -rf "${T}"
else
    SIGCHECK_STUB_FILE="${STUB}/fixture-sigcheck-unsigned.exe" TMPDIR="${T}/tmp" PATH="$STUB:$PATH" \
        bash "${T}/ci/fetch-release-helpers.bash" > "${T}/out.log" 2>&1
    rc=$?
    [ "$rc" -ne 0 ] || { echo "FAIL: ODT unsigned-binary case exited 0 - tier 2 laundered what tier 1 refused (WR-02)"; cat "${T}/out.log"; rm -rf "${T}" "$STUB"; exit 1; }
    grep -qF 'signature verification failed' "${T}/out.log" \
        || { echo "FAIL: ODT unsigned-binary case missing the tier refusal line"; cat "${T}/out.log"; rm -rf "${T}" "$STUB"; exit 1; }
    [ ! -f "${T}/bin/odt/setup.exe" ] \
        || { echo "FAIL: ODT unsigned-binary case integrated setup.exe despite the unsigned verdict"; cat "${T}/out.log"; rm -rf "${T}" "$STUB"; exit 1; }
    residue="$(ls -A "${T}/bin/odt" 2>/dev/null || true)"
    [ -z "${residue}" ] || { echo "FAIL: ODT unsigned-binary case left bin/odt residue: ${residue}"; cat "${T}/out.log"; rm -rf "${T}" "$STUB"; exit 1; }
    rm -rf "${T}"
fi

rm -rf "$STUB"
echo "PASS fetch-release-helpers fixtures (green 6 pins / tamper mismatch + observed digest / unpinned refusal / atomicity no-partial / PE refusal / CRLF URL list / mkisofs gate pre-install WR-04 / ODT green offline + tier skip / ODT tampered payload pin / ODT no-MSCF carve refusal / ODT missing extractor / ODT unsigned verdict refused WR-02, offline via stubs)"
