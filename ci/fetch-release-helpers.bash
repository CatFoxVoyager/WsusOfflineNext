#!/usr/bin/env bash
#
# ci/fetch-release-helpers.bash — fetch the runtime helpers a fresh checkout lacks
#
# Usage: bash ci/fetch-release-helpers.bash
#
# A git checkout ships the tracked tools (client/bin/hashdeep*, IfAdmin*,
# vendored bin/ tools) but NOT the runtime-downloaded extras: the Sysinternals
# zips with their extracted exes and mkisofs.exe. This script fetches exactly
# those, from the same sources the pipeline itself uses, so a CI-built release
# zip matches a dev-machine-built one.
#
# Canonical layout (mirrors sh/download-updates-tasks/20-get-sysinternals-helpers.bash):
#   bin/AutoLogon.zip, Sigcheck.zip, Streams.zip   — the archives
#   bin/sigcheck*.exe, bin/streams*.exe            — client-side signature checks
#   client/bin/Autologon*.exe                      — automatic post-reboot relaunch
#   client/bin/unzip.exe                           — client-side zip unpacking
#   bin/mkisofs.exe                                — ISO creation
#   bin/odt/setup.exe                              — Office Deployment Tool (WR-11)
#
# ODT fetch (WR-11; option A locked in the phase 16 context): the offline
# client can never re-download, so a dev zip that ships bin/odt/setup.exe and
# a CI zip that ships without it is a product divergence on every Office C2R
# target. The fetch therefore lives here, and the client's fallback path
# (client/cmd/InstallOfficeUpdate.cmd) resolves exactly the file this script
# integrates. The URL, the carve and the signature logic are ports of
# cmd/DownloadOfficeC2R.cmd: byte-identical ODT_URL, the MSCF carve, the
# two-tier sigcheck gate.
#
# Carve mechanics: the upstream self-extracting installer embeds a CAB payload
# after an executable stub; the first MSCF marker (located with `grep -abo
# MSCF`) is the CAB start and the payload is carved with `tail -c +<offset+1>`
# — the same byte arithmetic the CMD source applies in PowerShell. A missing
# marker is a hard refusal (exit 1): CI never executes the upstream installer,
# unlike the CMD's silent-installer fallback.
#
# Extractor resolution order: `command -v cabextract` first (the self-hosted
# Linux image ships it), else the Windows CAB expander by its ABSOLUTE System32
# path, with cygpath-converted CAB and destination paths. The bare name
# `expand` is never consulted: on git-bash hosts it resolves to GNU coreutils
# and refuses -F.
#
# Signature position (cmd/DownloadOfficeC2R.cmd:101-114, ported): the two-tier
# Authenticode gate runs on the extracted setup.exe whenever bin/sigcheck64.exe
# exists, passes its own MZ header check AND the host is a Windows-side bash
# (WINDIR + cygpath present) — sigcheck is a Windows PE, so a Linux host that
# merely downloaded it takes the documented skip line instead of a false red.
# -accepteula is added so a fresh CI host is never stuck on the EULA prompt
# (deviation from the CMD flags, which rely on a dev machine's EULA state), and
# the fallback tier strips NUL bytes before grepping "Signed" (sigcheck emits
# UTF-16 output; the CMD's findstr matches it natively). A sigcheck64.exe that
# is absent or not a PE logs ONE skip line and the SHA256 pins remain the sole
# integrity authority: MSYS executes any existing .exe as a silent rc=0 no-op,
# so the MZ check is what keeps the tier honest offline. The metadata files the
# extractor produces alongside setup.exe (EULA, sample configuration XML in the
# probed build) move into bin/odt/ ungated — pins gate executables.
#
# Integrity (CIWF-06, finding IN-04): every downloaded helper is verified
# against the pinned SHA256 list in ci/release-helper-hashes.sha256
# (sha256sum format: 64 hex chars, two spaces, basename) BEFORE anything is
# unpacked or integrated. The pins were seeded from fresh upstream downloads
# (2026-10-29); the mkisofs pin was cross-checked with certutil, and the two
# ODT pins (installer exe plus the setup.exe carved out of it) from a full
# real-chain probe on 2026-10-30.
#
# Atomic download (CISC-04, findings WR-12 and WR-04): bin/mkisofs.exe is
# fetched into a temp file and moved into place only after the transfer
# succeeded AND the SHA256 gate passed on the temp - a mid-transfer failure
# never leaves a partial, and a content mismatch never leaves an unpinned
# binary that the existence guard would bless on the next run.
#
# Refresh procedure: when verification fails the script exits 1 and prints
# both the expected pin and the observed digest. Verify the new build's
# provenance from the official source (download.sysinternals.com for the
# Sysinternals archives, gitlab.com/wsusoffline/wsusoffline-sdd for
# mkisofs.exe, download.microsoft.com for the ODT installer), then update the
# pin in a dedicated commit. An upstream ODT rotation moves BOTH ODT pins at
# once (installer exe and carved setup.exe) and follows the same procedure:
# re-probe the full chain, pin the new digests, dedicated commit. Until then
# the release stays red: the workflow's Fetch runtime helpers step
# (monthly-updates.yml) fails before MakeRelease runs, so a modified,
# corrupted or unpinned helper never enters the published zip.

# ===== Configuration =====
readonly script_version="1.4"
MKISOFS_URL="https://gitlab.com/wsusoffline/wsusoffline-sdd/-/raw/master/mkisofs.exe"
ODT_URL="https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_20430-20146.exe"
readonly hashes_file="ci/release-helper-hashes.sha256"

# ===== Global variables =====
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
wget_bin=""
unzip_bin=""
sha256_bin=""
cab_bin=""
cab_kind=""
odt_tmp_work=""
odt_tmp_installer=""

# ===== Functions =====

function resolve_tools ()
{
  if [ -x "${repo_root}/bin/wget64.exe" ]; then wget_bin="${repo_root}/bin/wget64.exe";
  else wget_bin="$(command -v wget || true)"; fi
  if [ -x "${repo_root}/bin/unzip.exe" ]; then unzip_bin="${repo_root}/bin/unzip.exe";
  else unzip_bin="$(command -v unzip || true)"; fi
  [ -n "${wget_bin}" ] || { echo "fetch-release-helpers: no wget found" >&2; exit 1; }
  [ -n "${unzip_bin}" ] || { echo "fetch-release-helpers: no unzip found" >&2; exit 1; }
  sha256_bin="$(command -v sha256sum || true)"
  [ -n "${sha256_bin}" ] || { echo "fetch-release-helpers: no sha256sum found" >&2; exit 1; }
}

# CIWF-06: fail-closed integrity gate. First argument: the artifact basename
# as pinned in the sidecar. Optional second argument: the path to hash —
# defaults to the installed location bin/<basename>; a caller verifying a
# NOT-YET-INSTALLED temp file passes that path (WR-04: the pin is keyed by
# basename, so the temp can be gated before the atomic move into bin/), and
# the ODT block passes the canonical installed home bin/odt/<basename> for
# its post-block re-gate. A missing sidecar and a missing pin take the same
# failure path: the helper is refused, never shipped unverified. On any
# refusal a non-canonical (temp) path is removed from the tree — no failure
# path leaves a residue (CISC-04 discipline); an installed artifact (either
# canonical home) is left in place for diagnosis, since the post-install
# gate owns that case.
function verify_helper_hash ()
{
  local artifact_name="$1"
  local artifact_path="${2:-bin/${artifact_name}}"
  local hashes_path="${repo_root}/${hashes_file}"
  local expected_pin=""
  local observed_hash=""

  if [ -f "${hashes_path}" ]; then
    expected_pin="$(tr -d '\r' < "${hashes_path}" | grep -E "^[0-9a-f]{64}  ${artifact_name}\$" | cut -d' ' -f1)"
  fi
  if [ -z "${expected_pin}" ]; then
    echo "fetch-release-helpers: no SHA256 pin for ${artifact_name} - refusing an unpinned helper" >&2
    if [ "${artifact_path}" != "bin/${artifact_name}" ] && [ "${artifact_path}" != "bin/odt/${artifact_name}" ]; then
      rm -f "${artifact_path}"
    fi
    exit 1
  fi
  observed_hash="$("${sha256_bin}" "${artifact_path}" | cut -d' ' -f1)"
  if [ "${observed_hash}" != "${expected_pin}" ]; then
    echo "fetch-release-helpers: SHA256 MISMATCH for ${artifact_name}" >&2
    echo "  expected: ${expected_pin}" >&2
    echo "  observed: ${observed_hash}" >&2
    echo "  if upstream rotated this helper, verify the new build's provenance from the official source, then update the pin in a dedicated commit" >&2
    if [ "${artifact_path}" != "bin/${artifact_name}" ] && [ "${artifact_path}" != "bin/odt/${artifact_name}" ]; then
      rm -f "${artifact_path}"
    fi
    exit 1
  fi
  echo "fetch-release-helpers: SHA256 OK ${artifact_name}"
}

# ODT block residue (CISC-04 discipline): every failure path must leave no temp
# behind, and the gates that exit from inside verify_helper_hash cannot be
# reached by the caller's inline rm. The temps are therefore cleaned by this
# EXIT trap, armed for the duration of the ODT block and disarmed on success.
function odt_cleanup ()
{
  [ -n "${odt_tmp_work:-}" ] && rm -rf "${odt_tmp_work}"
  [ -n "${odt_tmp_installer:-}" ] && rm -f "${odt_tmp_installer}"
  return 0
}

# ===== Main program =====

resolve_tools
cd "${repo_root}" || exit 1
mkdir -p bin client/bin

# Sysinternals zips -> bin/; AutoLogon unpacks into client/bin (canonical),
# Sigcheck and Streams unpack into bin/
while IFS= read -r url; do
  [ -n "${url}" ] || continue
  zip_name="$(basename "${url}")"
  echo "fetch-release-helpers: ${url} -> bin/${zip_name}"
  "${wget_bin}" -N -q -P bin "${url}" \
    || { echo "fetch-release-helpers: download failed: ${url}" >&2; exit 1; }
  # CIWF-06: a tampered archive must never be unpacked - gate before the unzip
  verify_helper_hash "${zip_name}"
  case "${zip_name}" in
    AutoLogon.zip) dest="client/bin" ;;
    *)             dest="bin" ;;
  esac
  "${unzip_bin}" -o -q "bin/${zip_name}" -x "Eula.txt" -d "${dest}" \
    || { echo "fetch-release-helpers: unzip failed: ${zip_name}" >&2; exit 1; }
# The URL list is read CR-normalised at this one site: .gitattributes
# materialises *.txt as CRLF on a fresh checkout, and a CR surviving in the
# URL corrupts zip_name (the download would even land as a CR-named file in
# bin/) and silently misses every SHA256 pin ("refusing an unpinned helper")
# under a strict (Linux) grep - ubuntu-latest, run 41012438351.
done < <(tr -d '\r' < static/StaticDownloadLinks-sysinternals.txt | grep -E '^https?://' | cut -d',' -f1)

# The client installer unpacks zip-packaged updates with its own unzip copy
if [ -f bin/unzip.exe ] && [ ! -f client/bin/unzip.exe ]; then
  cp bin/unzip.exe client/bin/unzip.exe
  echo "fetch-release-helpers: bin/unzip.exe -> client/bin/unzip.exe"
fi

if [ ! -f bin/mkisofs.exe ]; then
  echo "fetch-release-helpers: mkisofs.exe"
  # CISC-04 (WR-12): wget -O truncates the target BEFORE the transfer, so a
  # mid-transfer failure used to leave a partial that the [ ! -f ] guard would
  # bless forever. Download into a sibling temp file and move atomically; every
  # failure path removes the temp BEFORE exiting (fail-closed).
  tmp_bin="$(mktemp "${repo_root}/bin/mkisofs.exe.XXXXXX")" \
    || { echo "fetch-release-helpers: mkisofs: cannot create temp file" >&2; exit 1; }
  "${wget_bin}" -q -O "${tmp_bin}" "${MKISOFS_URL}" \
    || { rm -f "${tmp_bin}"; echo "fetch-release-helpers: mkisofs download failed" >&2; exit 1; }
  # early-detection net: an empty or non-PE stream is refused before the move.
  # The SHA256 pin below stays the integrity authority (CIWF-06) - these checks
  # catch a dead or wrong-content stream before it is ever installed.
  if [ ! -s "${tmp_bin}" ]; then
    rm -f "${tmp_bin}"
    echo "fetch-release-helpers: mkisofs: empty download" >&2
    exit 1
  fi
  if [ "$(head -c 2 "${tmp_bin}")" != "MZ" ]; then
    rm -f "${tmp_bin}"
    echo "fetch-release-helpers: mkisofs: not a PE binary (missing MZ header)" >&2
    exit 1
  fi
  # CIWF-06 (WR-04): gate the TEMP file on the pin BEFORE the move — on a
  # mismatch the unpinned binary must never reach bin/ (header invariant:
  # verified BEFORE anything is unpacked or integrated). The gate removes
  # the temp itself on refusal (fail-closed, no residue).
  verify_helper_hash "mkisofs.exe" "${tmp_bin}"
  mv -f "${tmp_bin}" bin/mkisofs.exe
fi

# CIWF-06: hash-gate mkisofs.exe in BOTH cases - freshly downloaded above
# (gated pre-install since WR-04; this second gate re-verifies the installed
# bytes) or previously cached (the existence-only guard would otherwise bless
# the cache).
verify_helper_hash "mkisofs.exe"

# ---- ODT (WR-11): fetch -> carve -> extract -> gate -> integrate bin/odt/setup.exe ----
# Placed AFTER the mkisofs re-gate so the sysinternals loop above has already
# produced bin/sigcheck64.exe by the time the Authenticode tier is evaluated.
if [ ! -f bin/odt/setup.exe ]; then
  echo "fetch-release-helpers: ODT setup.exe"
  odt_installer_name="$(basename "${ODT_URL}")"
  mkdir -p bin/odt
  odt_tmp_work=""
  odt_tmp_installer="$(mktemp "${repo_root}/bin/odt/${odt_installer_name}.XXXXXX")" \
    || { echo "fetch-release-helpers: odt: cannot create temp file" >&2; exit 1; }
  trap odt_cleanup EXIT
  "${wget_bin}" -q -O "${odt_tmp_installer}" "${ODT_URL}" \
    || { echo "fetch-release-helpers: odt: download failed: ${ODT_URL}" >&2; exit 1; }
  if [ ! -s "${odt_tmp_installer}" ]; then
    echo "fetch-release-helpers: odt: empty download" >&2
    exit 1
  fi
  # T-16-04: gate the installer temp on its pin BEFORE any other use — a
  # tampered installer is never carved and never executed.
  verify_helper_hash "${odt_installer_name}" "${odt_tmp_installer}"
  # Carve the inner CAB at the first MSCF marker (the CMD source's byte
  # arithmetic, ported to bash). No marker: hard refusal — CI never executes
  # the upstream installer.
  odt_tmp_work="$(mktemp -d)" \
    || { echo "fetch-release-helpers: odt: cannot create work directory" >&2; exit 1; }
  mscf_off="$(grep -abo MSCF "${odt_tmp_installer}" | head -n 1 | cut -d: -f1)"
  if [ -z "${mscf_off}" ]; then
    echo "fetch-release-helpers: odt: no MSCF offset in the installer - refusing to carve" >&2
    exit 1
  fi
  tail -c "+$((mscf_off + 1))" "${odt_tmp_installer}" > "${odt_tmp_work}/odt_inner.cab" \
    || { echo "fetch-release-helpers: odt: carve failed" >&2; exit 1; }
  # Extractor resolution: cabextract first (the self-hosted Linux image ships
  # it), else the Windows CAB expander by ABSOLUTE System32 path — never the
  # bare name, which resolves to GNU coreutils on git-bash hosts and refuses -F.
  cab_bin=""
  cab_kind=""
  if command -v cabextract >/dev/null 2>&1; then
    cab_bin="$(command -v cabextract)"
    cab_kind="cabextract"
  elif command -v cygpath >/dev/null 2>&1 && [ -n "${WINDIR:-}" ] \
       && [ -f "$(cygpath -u "${WINDIR}")/System32/expand.exe" ]; then
    cab_bin="$(cygpath -u "${WINDIR}")/System32/expand.exe"
    cab_kind="expand"
  fi
  if [ -z "${cab_bin}" ]; then
    echo "fetch-release-helpers: odt: no cab extractor (cabextract or System32 expand.exe) - refusing to extract" >&2
    exit 1
  fi
  if [ "${cab_kind}" = "cabextract" ]; then
    "${cab_bin}" -q -d "${odt_tmp_work}" "${odt_tmp_work}/odt_inner.cab" \
      || { echo "fetch-release-helpers: odt: extraction failed" >&2; exit 1; }
  else
    "${cab_bin}" "-F:*" "$(cygpath -w "${odt_tmp_work}/odt_inner.cab")" "$(cygpath -w "${odt_tmp_work}")" \
      || { echo "fetch-release-helpers: odt: extraction failed" >&2; exit 1; }
  fi
  odt_setup_tmp="${odt_tmp_work}/setup.exe"
  if [ ! -f "${odt_setup_tmp}" ]; then
    echo "fetch-release-helpers: odt: setup.exe missing after extraction" >&2
    exit 1
  fi
  if [ "$(head -c 2 "${odt_setup_tmp}")" != "MZ" ]; then
    echo "fetch-release-helpers: odt: not a PE binary (missing MZ header)" >&2
    exit 1
  fi
  # T-16-04, second tier: the two-tier Authenticode gate ported from
  # cmd/DownloadOfficeC2R.cmd:101-114, run only when a PE sigcheck64.exe exists
  # on a Windows-side bash host (see the header for the host condition).
  if [ -f bin/sigcheck64.exe ] && [ "$(head -c 2 bin/sigcheck64.exe)" = "MZ" ] \
     && [ -n "${WINDIR:-}" ] && command -v cygpath >/dev/null 2>&1; then
    echo "fetch-release-helpers: odt: verifying Authenticode signature (sigcheck64)"
    sig_target="$(cygpath -w "${odt_setup_tmp}")"
    if "${repo_root}/bin/sigcheck64.exe" -accepteula -q -vt "${sig_target}" >/dev/null 2>&1; then
      :
    elif "${repo_root}/bin/sigcheck64.exe" -accepteula -q "${sig_target}" 2>/dev/null | tr -d '\0' | grep -iq signed; then
      :
    else
      echo "fetch-release-helpers: odt: signature verification failed" >&2
      exit 1
    fi
  else
    echo "fetch-release-helpers: odt: no executable sigcheck on this host - Authenticode tier skipped, SHA256 pins are the integrity authority"
  fi
  # T-16-04: gate the extracted setup.exe on its pin (temp-path form) BEFORE
  # any move; on refusal verify_helper_hash exits and the EXIT trap cleans up.
  verify_helper_hash "setup.exe" "${odt_setup_tmp}"
  # Integrate: ungated metadata first (EULA, sample configuration XML — the
  # carved CAB never moves, it stays in the work dir), the pinned executable
  # LAST, atomic mv. Then the success path removes its own residue (work dir
  # with the carved CAB, installer temp) before disarming the trap.
  find "${odt_tmp_work}" -maxdepth 1 -type f ! -name setup.exe ! -name '*.cab' -exec mv -f '{}' bin/odt/ \; >/dev/null 2>&1 || true
  mv -f "${odt_setup_tmp}" bin/odt/setup.exe
  rm -rf "${odt_tmp_work}"
  rm -f "${odt_tmp_installer}"
  odt_tmp_work=""
  odt_tmp_installer=""
  trap - EXIT
fi

# CIWF-06: hash-gate setup.exe in BOTH cases - freshly extracted above (the
# temp-path gate is the pre-install form) or previously cached (existence alone
# must never bless the cache - same double-gate shape as mkisofs above). The
# explicit second argument names the canonical installed home bin/odt/, so the
# gate hashes the INTEGRATED bytes (a bare "setup.exe" default would hash
# bin/setup.exe, a path this layout never uses).
verify_helper_hash "setup.exe" "bin/odt/setup.exe"

echo "fetch-release-helpers: done — client/bin/Autologon.exe: $([ -f client/bin/Autologon.exe ] && echo OK || echo MISSING), client/bin/unzip.exe: $([ -f client/bin/unzip.exe ] && echo OK || echo MISSING), bin/mkisofs.exe: $([ -f bin/mkisofs.exe ] && echo OK || echo MISSING), bin/odt/setup.exe: $([ -f bin/odt/setup.exe ] && echo OK || echo MISSING)"
[ -f client/bin/Autologon.exe ] && [ -f client/bin/unzip.exe ] && [ -f bin/mkisofs.exe ] && [ -f bin/odt/setup.exe ]
