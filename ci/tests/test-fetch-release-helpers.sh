#!/usr/bin/env bash
# Fixture test for ci/fetch-release-helpers.bash - run from repo root.
# Offline by construction: fake wget and fake unzip are prepended to PATH for
# the script invocations only, and the sidecar is recomputed by this test from
# the same fixture bytes, so no hash is hardcoded.
# Covered behaviors: green fetch (4 pins verified), tampered pin (exit != 0,
# expected + observed digests printed), unpinned helper (exit != 0, refusal).
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
  printf '%s' "$name" > "$out"
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
    Sigcheck.zip)  printf 'sigcheck64.exe-fixture' > "$dest/sigcheck64.exe" ;;
    Streams.zip)   printf 'streams64.exe-fixture' > "$dest/streams64.exe" ;;
    *) : ;;
esac
exit 0
UNZIP_EOF

chmod +x "$STUB/wget" "$STUB/unzip"

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
    for n in AutoLogon.zip Sigcheck.zip Streams.zip mkisofs.exe; do
        h="$(printf '%s' "${n}" | sha256sum | cut -d' ' -f1)"
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

rm -rf "$STUB"
echo "PASS fetch-release-helpers fixtures (green 4 pins / tamper mismatch + observed digest / unpinned refusal, offline via stubs)"
