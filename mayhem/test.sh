#!/usr/bin/env bash
#
# mayhem/test.sh — known-answer oracle for the LichtFeld Studio parsers (probe built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# lfs_kat_probe (built by build.sh with normal flags, dynamically linked) runs the app's real parsers on
# fixed inputs and prints what they return. Each section's output must equal the known answer below, so
# a patch that makes a parser exit early, return nothing or return the wrong values fails here.
PROBE="$SRC/lfs_kat_probe"
if [ ! -x "$PROBE" ]; then echo "FAIL: $PROBE missing — mayhem/build.sh did not build it" >&2; emit_ctrf "lfs-kat" 0 1 0; exit 1; fi

passed=0; failed=0
check() {
  local name="$1" expected="$2" actual
  actual="$("$PROBE" "$name" 2>&1)"
  if [ "$actual" = "$expected" ]; then passed=$((passed+1)); echo "PASS $name"
  else failed=$((failed+1)); echo "FAIL $name"; diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | head -20; fi
}

check usd 'usda.up_axis=Z
usda.meters_per_unit=0.01
usda.default_prim=/Root
usda.prims=2
usda.prim=/Root:Xform
usda.prim=/Root/Splats:ParticleField
usda.attr=opacities:float[]:1:0.25,0.75,
usda.attr=orientations:quatf[]:4:1,0,0,0,0,1,0,0,
usda.attr=positions:point3f[]:3:0,0,0,1,2,3,
usdc.garbage=rejected'

check python 'py.good.clean=1
py.symbol=2:import os@0
py.symbol=1:A@2
py.symbol=0:f@3
py.symbol=3:y@6
py.scope_at_return=A.f
py.bad.clean=0
py.bad.issues=1'

check json 'json.dump_bytes=54
json.dump={
  "b": 1,
  "a": [
    true,
    null,
    "x"
  ]
}
json.truncated=rejected'

check ply 'ply.count=3
ply.values=1,2,3,4,5,6,7,8,9,'

check stb 'stb.dims=2x1x3
stb.pixels=255,0,0,0,0,255
stb.junk=rejected'

check spz 'spz.points=2
spz.sh_degree=0
spz.positions=1.00,-2.00,0.50,0.00,3.00,-1.50,'

check openmesh 'om.obj=1:4:2:5
om.off=1:4:1
om.stl=1:3:1
om.ply=1:3:1'

emit_ctrf "lfs-kat" "$passed" "$failed" 0
