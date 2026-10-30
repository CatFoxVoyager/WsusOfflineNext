#!/usr/bin/env bash
# Fixture test for self-hosted/runner/entrypoint.sh - run from repo root.
# Offline by construction: fake curl, fake jq, fake config.sh and fake run.sh
# drive a sandbox copy of the REAL entrypoint (the shipped bytes, never a
# re-implementation), so no network call and no runner registration is ever
# attempted (the live-fleet docker stop / re-registration proof is the
# operator checkpoint of plan 16-03, not this battery).
# Covered behaviors (plan 16-01):
#   a. PAT happy path - registration token travels to config.sh on stdin, the
#      credential flag never reaches the configure argv, no Bearer literal in
#      curl argv, no PAT in the run.sh environment, header file mode 600 then
#      deleted by the cleanup, remove-token called exactly once
#   b. TERM forwarded - entrypoint exits 143 and the cleanup ran (both
#      markers); the child-receipt marker is asserted where the host delivers
#      signals from a trap context (ubuntu CI) and documented local-pass on
#      MSYS, which hard-kills/recycles children (spikes 2-3, 2026-10-30)
#   c. token mode byte-preservation - configure argv matches the HEAD shape
#      exactly (credential argument + non-interactive flag + replace, no
#      ephemeral flag, nothing on stdin) and remove-token is never called
#   d. exit propagation - child exit 7 becomes the entrypoint exit code,
#      cleanup ran first
#   e. fail-closed - no credential variable: French refusal, zero API calls,
#      no header file residue
#   f. remove-token API failure (WR-01) - network down at docker stop: the
#      cleanup skips the config.sh remove leg but removes the Authorization
#      header file UNCONDITIONALLY (pre-fix, `|| return 0` left the Bearer
#      file on disk; bite-proofed against the HEAD bytes before the fix)
# WR-04 disposition (2026-10-30 fix round): the PAT-stdin registration contract
# is exercised HERE only against the config.sh STUB - the live fleet runs token
# mode, and automating a real registration would burn a registration token and
# create a real runner on every battery run. One-off live validation procedure
# (run manually when the PAT mode changes; record date + outcome in the phase
# record):
#   1. mint a short-expiry fine-grained PAT (Administration: Read and write)
#      against a DISPOSABLE repo;
#   2. start the runner container once with a temporary override
#      (docker compose run -e RUNNER_PAT=<pat> -e REPO_SLUG=<disposable repo>
#      catalog-runner) - the override is never written to compose.env or .env;
#   3. confirm the promptless stdin registration: configure output reports
#      success and the runner is listed in the disposable repo's settings;
#   4. docker stop the container: the runner disappears (remove-token leg) and
#      no Authorization header file remains in the container filesystem;
#   5. revert the override (nothing to clean if step 2 used `compose run`).
# The stub battery stays the automated guard for the contract's shape (argv,
# stdin, header-file hygiene); this procedure covers the one thing stubs cannot
# prove: the real Runner.Listener's stdin prompt semantics.
# Host note (mode-600 tier): MSYS stat reports 644 even after chmod 600, so
# the strong "600" assertion runs only on hosts where a control file proves
# the mode is representable; elsewhere the battery asserts equality with that
# control (same mktemp + chmod 600 path). ubuntu-latest, the automation home
# of this battery, takes the strong tier.
set -u
STUB="$(mktemp -d)"

# control file for the mode-600 tier decision (see header note)
CTL="$(mktemp)"
chmod 600 "${CTL}"
CTL_MODE="$(stat -c '%a' "${CTL}")"
rm -f "${CTL}"

REPO="stub-owner/stub-repo"
RNAME="stub-runner"
PATVAL="stub-pat-secret-value-xyz"
REG_TOKEN="stub-reg-token-0123456789abcdef"
REM_TOKEN="stub-remove-token-fedcba9876543210"
TOK_TOKEN="stub-registration-token-head-shape-9876"

cat > "${STUB}/jq" <<'JQ_EOF'
#!/usr/bin/env bash
# fake jq: exact for the stub-curl bodies ({"token":"..."} one-liners). The
# entrypoint needs jq on PATH and dev hosts do not all ship it; the battery
# is offline-by-construction, so the shadow is deliberate on every host.
set -u
sed -n 's/^{"token":"\([0-9A-Za-z_.-]*\)"}$/\1/p'
JQ_EOF

cat > "${STUB}/curl" <<'CURL_EOF'
#!/usr/bin/env bash
# fake curl: handles the exact call shape of self-hosted/runner/entrypoint.sh
# (-fsSL -X POST -H @file -H Accept URL). Records full argv (the battery
# greps it for a Bearer literal - the argv-hygiene bite), the @file header
# path + mode + content, and every request URL; serves deterministic bodies
# keyed by endpoint; records a violation if a Bearer literal reaches argv.
set -u
REC="${STUB_REC:?STUB_REC manquant}"
want_hdr=0
want_method=0
url=""
printf '%s\n' "$@" >> "${REC}/curl-argv.txt"
for a in "$@"; do
  if [ "${want_hdr}" -eq 1 ]; then
    want_hdr=0
    case "${a}" in
      @*)
        printf '%s\n' "${a#@}" > "${REC}/curl-header-path.txt"
        stat -c '%a' "${a#@}" > "${REC}/curl-header-mode.txt"
        cat "${a#@}" > "${REC}/curl-header-content.txt"
        ;;
      *Bearer*)
        printf '%s\n' "${a}" >> "${REC}/curl-violations.txt"
        ;;
    esac
    continue
  fi
  if [ "${want_method}" -eq 1 ]; then
    want_method=0
    continue
  fi
  case "${a}" in
    -f|-s|-S|-L|-fsSL|-fs|-sl) ;;
    -X) want_method=1 ;;
    -H) want_hdr=1 ;;
    *) url="${a}" ;;
  esac
done
printf '%s\n' "${url}" >> "${REC}/curl-requests.txt"
case "${url}" in
  *"/actions/runners/registration-token") body="{\"token\":\"${STUB_REG_TOKEN}\"}" ;;
  *"/actions/runners/remove-token")
    # case f knob: the API is unreachable at docker stop (curl rc 56) - the
    # request above is still recorded, no body is served
    [ -n "${STUB_CURL_FAIL_REMOVE:-}" ] && exit 56
    body="{\"token\":\"${STUB_REMOVE_TOKEN}\"}" ;;
  *)                                      body="{}" ;;
esac
printf '%s\n' "${body}"
exit 0
CURL_EOF

cat > "${STUB}/config.sh" <<'CONF_EOF'
#!/usr/bin/env bash
# fake config.sh: one argv file + one stdin file per invocation; the remove
# subcommand writes a marker; the per-mode contract writes violations the
# battery treats as FAIL. stdin is always consumed (the PAT-mode caller pipes
# the token into it; a blocking reader would hang the entrypoint).
set -u
REC="${STUB_REC:?STUB_REC manquant}"
contract="${STUB_CONTRACT:-none}"
n=0
[ -f "${REC}/config-count.txt" ] && n="$(cat "${REC}/config-count.txt")"
n=$(( n + 1 ))
printf '%s\n' "${n}" > "${REC}/config-count.txt"
{
  for a in "$@"; do
    printf '%s\n' "${a}"
  done
} > "${REC}/config-argv-${n}.txt"
cat > "${REC}/config-stdin-${n}.txt"
if [ "${1:-}" = "remove" ]; then
  : > "${REC}/remove-ran.marker"
else
  if [ "${contract}" = "pat" ]; then
    # stdin contract: the PAT configure must not carry the credential flag
    grep -qx -- '--token' "${REC}/config-argv-${n}.txt" \
      && printf '%s\n' "configure PAT avec credential sur argv" >> "${REC}/contract-violations.txt"
  elif [ "${contract}" = "token" ]; then
    # byte-preservation contract: HEAD shape = credential argument +
    # non-interactive flag + replace present, no ephemeral flag
    grep -qx -- '--token' "${REC}/config-argv-${n}.txt" \
      || printf '%s\n' "configure token sans credential argument" >> "${REC}/contract-violations.txt"
    grep -qx -- '--unattended' "${REC}/config-argv-${n}.txt" \
      || printf '%s\n' "configure token sans unattended" >> "${REC}/contract-violations.txt"
    grep -qx -- '--replace' "${REC}/config-argv-${n}.txt" \
      || printf '%s\n' "configure token sans replace" >> "${REC}/contract-violations.txt"
    grep -qx -- '--ephemeral' "${REC}/config-argv-${n}.txt" \
      && printf '%s\n' "configure token avec ephemeral" >> "${REC}/contract-violations.txt"
  fi
fi
exit 0
CONF_EOF

cat > "${STUB}/run.sh" <<'RUN_EOF'
#!/usr/bin/env bash
# fake run.sh: records its pid, dumps the environment the entrypoint handed
# it (the battery greps it for the PAT variable - the unset bite), marks the
# start, then either exits with the scripted code or sleeps until signalled.
# On TERM it records receipt (child-receipt marker, CI-tier assertion).
set -u
REC="${STUB_REC:?STUB_REC manquant}"
printf '%s\n' "$$" > "${REC}/run-pid.txt"
env | LC_ALL=C sort > "${REC}/run-env.txt"
: > "${REC}/run-started.marker"
trap 'echo term > "${REC}/run-term.marker"; exit 143' TERM
if [ "${STUB_RUN_SLEEP:-0}" = "1" ]; then
  while :; do
    sleep 0.1
  done
fi
exit "${STUB_RUN_EXIT:-0}"
RUN_EOF

chmod +x "${STUB}/jq" "${STUB}/curl" "${STUB}/config.sh" "${STUB}/run.sh"

export PATH="${STUB}:${PATH}"
export REPO_SLUG="${REPO}" RUNNER_NAME="${RNAME}"
export STUB_REG_TOKEN="${REG_TOKEN}" STUB_REMOVE_TOKEN="${REM_TOKEN}"

function fail_case ()
{
    local msg="$1"
    shift
    echo "FAIL: ${msg}"
    rm -rf "$@"
    exit 1
}

function grep_count ()   # $1 pattern, $2 file -> count (0 when file absent)
{
    local n=""
    [ -f "${2}" ] || { printf '0\n'; return 0; }
    n="$(grep -c -- "${1}" "${2}" 2>/dev/null || true)"
    [ -n "${n}" ] || n=0
    printf '%s\n' "${n}"
}

function count_requests ()   # $1 rec dir, $2 url fragment -> count
{
    grep_count "${2}" "${1}/curl-requests.txt"
}

function assert_no_violations ()   # $1 rec dir, $2 case label, $3+ dirs
{
    local rec="$1" label="$2"
    shift 2
    [ ! -f "${rec}/contract-violations.txt" ] \
        || fail_case "${label} - violation de contrat stub : $(cat "${rec}/contract-violations.txt")" "$@"
    [ ! -f "${rec}/curl-violations.txt" ] \
        || fail_case "${label} - violation argv curl : $(cat "${rec}/curl-violations.txt")" "$@"
}

function scaffold ()
{
    local t="$1"
    mkdir -p "${t}/rec"
    # the sandbox drives the SHIPPED bytes, never a re-implementation
    cp self-hosted/runner/entrypoint.sh "${t}/entrypoint.sh"
    cp "${STUB}/config.sh" "${t}/config.sh"
    cp "${STUB}/run.sh" "${t}/run.sh"
    chmod +x "${t}/config.sh" "${t}/run.sh"
}

# ---- case a: PAT happy path - stdin registration, header-file auth, cleanup ----
T="$(mktemp -d)"
scaffold "${T}"
export STUB_REC="${T}/rec" STUB_CONTRACT=pat STUB_RUN_EXIT=0 STUB_RUN_SLEEP=0
export RUNNER_PAT="${PATVAL}"
( cd "${T}" && bash entrypoint.sh > out.log 2>&1 < /dev/null; printf '%s\n' "$?" > rc.txt )
rc="$(cat "${T}/rc.txt")"
[ "${rc}" -eq 0 ] || { cat "${T}/out.log"; fail_case "case a - exit ${rc}, attendu 0" "${T}" "${STUB}"; }
assert_no_violations "${T}/rec" "case a" "${T}" "${STUB}"
[ "$(count_requests "${T}/rec" "actions/runners/registration-token")" -eq 1 ] \
    || fail_case "case a - registration-token appele $(count_requests "${T}/rec" "actions/runners/registration-token") fois, attendu 1" "${T}" "${STUB}"
[ "$(count_requests "${T}/rec" "actions/runners/remove-token")" -eq 1 ] \
    || fail_case "case a - remove-token appele $(count_requests "${T}/rec" "actions/runners/remove-token") fois, attendu 1 (cleanup vivant)" "${T}" "${STUB}"
[ -f "${T}/rec/remove-ran.marker" ] \
    || fail_case "case a - config.sh remove pas execute au cleanup" "${T}" "${STUB}"
[ "$(grep_count '.' "${T}/rec/config-count.txt")" -ge 1 ] || fail_case "case a - config.sh jamais invoque" "${T}" "${STUB}"
[ "$(cat "${T}/rec/config-count.txt")" -eq 2 ] \
    || fail_case "case a - config.sh invoque $(cat "${T}/rec/config-count.txt") fois, attendu 2 (configure + remove)" "${T}" "${STUB}"
argv="${T}/rec/config-argv-1.txt"
tok_n="$(grep_count -- '--token' "${argv}")"
[ "${tok_n}" -eq 0 ] || fail_case "case a - credential sur l'argv du configure PAT (${tok_n} occurrences, attendu 0)" "${T}" "${STUB}"
grep -qx -- '--ephemeral' "${argv}" || fail_case "case a - ephemeral absent de l'argv du configure PAT (position HEAD)" "${T}" "${STUB}"
grep -qx -- '--replace' "${argv}" || fail_case "case a - replace absent de l'argv du configure PAT (position HEAD)" "${T}" "${STUB}"
grep -qx -- '--unattended' "${argv}" \
    && fail_case "case a - le configure PAT porte encore le mode non interactif (doit passer par stdin)" "${T}" "${STUB}"
grep -qF "${REG_TOKEN}" "${T}/rec/config-stdin-1.txt" \
    || fail_case "case a - le token d'enregistrement n'est pas arrive par stdin" "${T}" "${STUB}"
grep -qF "${REM_TOKEN}" "${T}/rec/config-argv-2.txt" \
    || fail_case "case a - le remove n'a pas consomme le token servi par le stub curl" "${T}" "${STUB}"
bearer_n="$(grep_count 'Bearer' "${T}/rec/curl-argv.txt")"
[ "${bearer_n}" -eq 0 ] || fail_case "case a - Bearer en clair dans l'argv du stub curl (${bearer_n} occurrences, attendu 0)" "${T}" "${STUB}"
pat_n="$(grep_count 'RUNNER_PAT' "${T}/rec/run-env.txt")"
[ "${pat_n}" -eq 0 ] || fail_case "case a - RUNNER_PAT present dans l'environnement de run.sh (${pat_n}, attendu 0)" "${T}" "${STUB}"
patv_n="$(grep_count "${PATVAL}" "${T}/rec/run-env.txt")"
[ "${patv_n}" -eq 0 ] || fail_case "case a - la valeur du PAT fuite dans l'environnement de run.sh (${patv_n}, attendu 0)" "${T}" "${STUB}"
[ -f "${T}/rec/curl-header-path.txt" ] || fail_case "case a - le stub curl n'a recu aucun @file" "${T}" "${STUB}"
hdr_path="$(cat "${T}/rec/curl-header-path.txt")"
hdr_mode="$(cat "${T}/rec/curl-header-mode.txt")"
if [ "${CTL_MODE}" = "600" ]; then
    [ "${hdr_mode}" = "600" ] || fail_case "case a - mode du fichier d'en-tetes ${hdr_mode}, attendu 600" "${T}" "${STUB}"
else
    [ "${hdr_mode}" = "${CTL_MODE}" ] \
        || fail_case "case a - mode du fichier d'en-tetes ${hdr_mode} != controle ${CTL_MODE} (hote ou chmod 600 n'est pas representable)" "${T}" "${STUB}"
fi
grep -qF "Authorization: Bearer ${PATVAL}" "${T}/rec/curl-header-content.txt" \
    || fail_case "case a - le fichier d'en-tetes ne porte pas la ligne Authorization attendue" "${T}" "${STUB}"
[ ! -f "${hdr_path}" ] || fail_case "case a - le fichier d'en-tetes n'a pas ete supprime par le cleanup" "${T}" "${STUB}"
rm -rf "${T}"

# ---- case b: TERM forwarded - exit 143, cleanup ran ----
T="$(mktemp -d)"
scaffold "${T}"
export STUB_REC="${T}/rec" STUB_CONTRACT=pat STUB_RUN_SLEEP=1 STUB_RUN_EXIT=0
( cd "${T}" && exec bash entrypoint.sh > out.log 2>&1 < /dev/null ) &
bpid=$!
i=0
while [ ! -f "${T}/rec/run-started.marker" ] && [ "${i}" -lt 100 ]; do
    sleep 0.1
    i=$(( i + 1 ))
done
[ -f "${T}/rec/run-started.marker" ] || { kill -9 "${bpid}" 2>/dev/null; fail_case "case b - run.sh jamais demarre" "${T}" "${STUB}"; }
i=0
while kill -0 "${bpid}" 2>/dev/null && [ "${i}" -lt 100 ]; do
    sleep 0.1
    i=$(( i + 1 ))
done
kill -0 "${bpid}" 2>/dev/null || fail_case "case b - l'entrypoint est sorti avant le TERM" "${T}" "${STUB}"
kill -TERM "${bpid}"
i=0
while kill -0 "${bpid}" 2>/dev/null && [ "${i}" -lt 100 ]; do
    sleep 0.1
    i=$(( i + 1 ))
done
if kill -0 "${bpid}" 2>/dev/null; then
    run_pid="$(cat "${T}/rec/run-pid.txt" 2>/dev/null || true)"
    [ -n "${run_pid}" ] && kill -9 "${run_pid}" 2>/dev/null
    kill -9 "${bpid}" 2>/dev/null
    wait "${bpid}" 2>/dev/null
    fail_case "case b - entrypoint toujours vivant 10 s apres TERM (cycle de vie bloque ?)" "${T}" "${STUB}"
fi
wait "${bpid}"
rc=$?
[ "${rc}" -eq 143 ] || { cat "${T}/out.log"; fail_case "case b - exit ${rc}, attendu 143" "${T}" "${STUB}"; }
assert_no_violations "${T}/rec" "case b" "${T}" "${STUB}"
[ "$(count_requests "${T}/rec" "actions/runners/remove-token")" -eq 1 ] \
    || fail_case "case b - remove-token pas appele au TERM (cleanup mort sur signal ?)" "${T}" "${STUB}"
[ -f "${T}/rec/remove-ran.marker" ] \
    || fail_case "case b - config.sh remove pas execute au TERM" "${T}" "${STUB}"
# child receipt: strong bite where signals delivered from a trap context
# reach the child (ubuntu CI). MSYS hard-kills or recycles children here, so
# the receipt check is a documented local-pass (spikes 2-3, 2026-10-30).
case "$(uname -s)" in
    MSYS*|MINGW*|CYGWIN*) : ;;
    *)
        i=0
        while [ ! -f "${T}/rec/run-term.marker" ] && [ "${i}" -lt 20 ]; do
            sleep 0.1
            i=$(( i + 1 ))
        done
        [ -f "${T}/rec/run-term.marker" ] \
            || fail_case "case b - run.sh n'a pas recu le TERM transmis" "${T}" "${STUB}"
        ;;
esac
run_pid="$(cat "${T}/rec/run-pid.txt" 2>/dev/null || true)"
[ -n "${run_pid}" ] && kill -9 "${run_pid}" 2>/dev/null
rm -rf "${T}"

# ---- case c: token mode - configure argv byte-preserved from HEAD ----
T="$(mktemp -d)"
scaffold "${T}"
export STUB_REC="${T}/rec" STUB_CONTRACT=token STUB_RUN_EXIT=0 STUB_RUN_SLEEP=0
unset RUNNER_PAT
export RUNNER_TOKEN="${TOK_TOKEN}"
( cd "${T}" && bash entrypoint.sh > out.log 2>&1 < /dev/null; printf '%s\n' "$?" > rc.txt )
rc="$(cat "${T}/rc.txt")"
[ "${rc}" -eq 0 ] || { cat "${T}/out.log"; fail_case "case c - exit ${rc}, attendu 0" "${T}" "${STUB}"; }
assert_no_violations "${T}/rec" "case c" "${T}" "${STUB}"
[ "$(cat "${T}/rec/config-count.txt")" -eq 1 ] \
    || fail_case "case c - config.sh invoque $(cat "${T}/rec/config-count.txt") fois, attendu 1" "${T}" "${STUB}"
argv="${T}/rec/config-argv-1.txt"
grep -qx -- '--token' "${argv}" || fail_case "case c - credential argument absent de l'argv token (branche HEAD modifiee ?)" "${T}" "${STUB}"
grep -qF "${TOK_TOKEN}" "${argv}" || fail_case "case c - la valeur du token d'enregistrement n'est pas sur l'argv (branche HEAD modifiee ?)" "${T}" "${STUB}"
grep -qx -- '--unattended' "${argv}" || fail_case "case c - mode non interactif absent de l'argv token (branche HEAD modifiee ?)" "${T}" "${STUB}"
grep -qx -- '--replace' "${argv}" || fail_case "case c - replace absent de l'argv token (position HEAD)" "${T}" "${STUB}"
grep -qx -- '--ephemeral' "${argv}" \
    && fail_case "case c - la branche token porte ephemeral (HEAD : non)" "${T}" "${STUB}"
[ -s "${T}/rec/config-stdin-1.txt" ] \
    && fail_case "case c - la branche token consomme stdin (HEAD : argv seul)" "${T}" "${STUB}"
[ "$(count_requests "${T}/rec" "actions/runners/remove-token")" -eq 0 ] \
    || fail_case "case c - remove-token appele en mode token (le cleanup ne doit pas exister ici)" "${T}" "${STUB}"
[ ! -f "${T}/rec/curl-header-path.txt" ] \
    || fail_case "case c - un fichier d'en-tetes a ete cree hors mode PAT" "${T}" "${STUB}"
rm -rf "${T}"
unset RUNNER_TOKEN

# ---- case d: exit propagation - child exit 7, cleanup first ----
T="$(mktemp -d)"
scaffold "${T}"
export STUB_REC="${T}/rec" STUB_CONTRACT=pat STUB_RUN_EXIT=7 STUB_RUN_SLEEP=0
export RUNNER_PAT="${PATVAL}"
( cd "${T}" && bash entrypoint.sh > out.log 2>&1 < /dev/null; printf '%s\n' "$?" > rc.txt )
rc="$(cat "${T}/rc.txt")"
[ "${rc}" -eq 7 ] || { cat "${T}/out.log"; fail_case "case d - exit ${rc}, attendu 7 (le code de sortie de l'enfant doit se propager)" "${T}" "${STUB}"; }
assert_no_violations "${T}/rec" "case d" "${T}" "${STUB}"
[ -f "${T}/rec/remove-ran.marker" ] \
    || fail_case "case d - cleanup pas execute apres la sortie de l'enfant" "${T}" "${STUB}"
[ "$(count_requests "${T}/rec" "actions/runners/remove-token")" -eq 1 ] \
    || fail_case "case d - remove-token pas appele apres la sortie de l'enfant" "${T}" "${STUB}"
rm -rf "${T}"

# ---- case e: fail-closed - no credential variable, no residue ----
T="$(mktemp -d)"
scaffold "${T}"
export STUB_REC="${T}/rec" STUB_CONTRACT=none STUB_RUN_EXIT=0 STUB_RUN_SLEEP=0
unset RUNNER_PAT RUNNER_TOKEN
( cd "${T}" && bash entrypoint.sh > out.log 2>&1 < /dev/null; printf '%s\n' "$?" > rc.txt )
rc="$(cat "${T}/rc.txt")"
[ "${rc}" -ne 0 ] || fail_case "case e - exit 0 sans aucun credential (doit refuser)" "${T}" "${STUB}"
grep -qF 'Ni RUNNER_TOKEN ni RUNNER_PAT fourni' "${T}/out.log" \
    || fail_case "case e - message de refus français absent de la sortie" "${T}" "${STUB}"
[ "$(count_requests "${T}/rec" "api.github.com")" -eq 0 ] \
    || fail_case "case e - des requetes API ont ete emises sans credential" "${T}" "${STUB}"
[ ! -f "${T}/rec/curl-header-path.txt" ] \
    || fail_case "case e - un fichier d'en-tetes a ete cree sans mode PAT" "${T}" "${STUB}"
[ ! -f "${T}/rec/config-count.txt" ] \
    || fail_case "case e - config.sh invoque dans le cas fail-closed" "${T}" "${STUB}"
residue=""
while IFS= read -r -d '' f; do
    grep -q 'Authorization: Bearer' "${f}" 2>/dev/null && residue="${residue} ${f}"
done < <(find "${T}" -type f ! -name '*.sh' ! -name 'out.log' ! -name 'rc.txt' -print0 2>/dev/null)
[ -z "${residue}" ] || fail_case "case e - residu Authorization apres la sortie :${residue}" "${T}" "${STUB}"
rm -rf "${T}"

# ---- case f: remove-token API failure - the header file must still die ----
# WR-01: the stub curl exits 56 on remove-token (network down at docker stop).
# The cleanup may skip the config.sh remove leg (no token came back) but must
# remove the Authorization header file UNCONDITIONALLY - pre-fix, the
# `|| return 0` short-circuit left the Bearer file on disk for the rest of
# the container's life, silently (the entrypoint still exited 0).
T="$(mktemp -d)"
scaffold "${T}"
export STUB_REC="${T}/rec" STUB_CONTRACT=pat STUB_RUN_EXIT=0 STUB_RUN_SLEEP=0
export STUB_CURL_FAIL_REMOVE=1
export RUNNER_PAT="${PATVAL}"
( cd "${T}" && bash entrypoint.sh > out.log 2>&1 < /dev/null; printf '%s\n' "$?" > rc.txt )
rc="$(cat "${T}/rc.txt")"
[ "${rc}" -eq 0 ] || { cat "${T}/out.log"; fail_case "case f - exit ${rc}, attendu 0 (l'echec de l'API ne doit pas casser le cycle)" "${T}" "${STUB}"; }
[ "$(count_requests "${T}/rec" "actions/runners/remove-token")" -eq 1 ] \
    || fail_case "case f - remove-token pas tente (l'appel API reste tente)" "${T}" "${STUB}"
[ ! -f "${T}/rec/remove-ran.marker" ] \
    || fail_case "case f - config.sh remove execute alors que l'API a echoue (jambe a sauter)" "${T}" "${STUB}"
[ -f "${T}/rec/curl-header-path.txt" ] || fail_case "case f - le stub curl n'a recu aucun @file" "${T}" "${STUB}"
hdr_path="$(cat "${T}/rec/curl-header-path.txt")"
[ ! -f "${hdr_path}" ] \
    || fail_case "case f - le fichier d'en-tetes PAT survit a l'echec API remove-token (WR-01 bite)" "${T}" "${STUB}"
unset RUNNER_PAT STUB_CURL_FAIL_REMOVE
rm -rf "${T}"

rm -rf "${STUB}"
if [ "${CTL_MODE}" = "600" ]; then
    tier="mode-600 assure strictement"
else
    tier="mode-600 assure relativement au controle (${CTL_MODE}) - hote MSYS"
fi
echo "PASS runner-entrypoint fixtures (PAT stdin + header-file hygiene + cleanup vivant / TERM 143 + cleanup / branche token forme HEAD preservee / propagation exit 7 / refus fail-closed / echec API remove-token: fichier d'en-tetes quand meme supprime WR-01, offline via stubs [${tier}])"
