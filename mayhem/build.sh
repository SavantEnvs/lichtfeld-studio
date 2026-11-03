#!/usr/bin/env bash
#
# mayhem/build.sh — LichtFeld Studio fuzz harnesses + KAT probe.
#
# The full app needs CUDA, libtorch, Vulkan and vcpkg, none of which exist in the CPU-only base, so
# this compiles the app's CPU-only, self-contained parsing sources (and the vendored parsers they sit
# on) directly from the tree: the same translation units the app links, with the same defines.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
M="$SRC/mayhem"
OUT="$SRC/build-mayhem"
rm -rf "$OUT"
mkdir -p "$OUT"

INC=(-I"$SRC/src/core/include" -I"$SRC/src" -I"$SRC/src/io/include" -I"$SRC/src/io/formats"
     -I"$SRC/src/python" -I"$SRC/external" -I"$SRC/external/spz"
     -I"$SRC/external/OpenMesh/src" -I"$SRC/external/tinyusdz/src")
TU="$SRC/external/tinyusdz/src"
TS="$SRC/external/tree-sitter"
TSP="$SRC/external/tree-sitter-python"

# Compile every source listed in $1 (lines: "<lang> <src> <obj> [extra flags...]") with $2 as base flags.
run_jobs() {
    local list="$1" flags="$2"
    xargs -P "$MAYHEM_JOBS" -L 1 bash -c '
        lang=$0; src=$1; obj=$2; shift 2
        if [ "$lang" = c ]; then
            '"$CC"' '"$flags"' -std=c11 "$@" -c "$src" -o "$obj"
        else
            '"$CXX"' '"$flags"' "$@" -c "$src" -o "$obj"
        fi' < "$list"
}

# Build every library the harnesses need into $1 with base flags $2.
build_libs() {
    local d="$1" flags="$2"
    mkdir -p "$d/obj"
    local list="$d/jobs.txt"; : > "$list"
    add() {
        local line="$1 $2 $d/obj/$3.o"
        if [ "$#" -gt 3 ]; then line+=" ${*:4}"; fi
        echo "$line" >> "$list"
    }

    # core: lfs::Error + MemoryDomain; stubs.cpp stands in for the crash-handler assertion sink
    add cxx "$SRC/src/core/error.cpp" core_error -std=c++23 "${INC[@]}"
    add cxx "$SRC/src/core/memory_domain.cpp" core_memory_domain -std=c++23 "${INC[@]}"
    add cxx "$M/stubs.cpp" mayhem_stubs -std=c++23 "${INC[@]}"

    # tinyusdz (flags as in src/io/CMakeLists.txt lfs_tinyusdz) + the app's usd_flat readers
    for f in ascii-parser-basetype ascii-parser-timesamples-array ascii-parser-timesamples ascii-parser \
             asset-resolution crate-format crate-reader io-util linear-algebra lz4-compression path-util \
             pprinter prim-reconstruct prim-types stage str-util tiny-format usda-reader value-pprint \
             value-types xform; do
        add cxx "$TU/$f.cc" "tusdz_$f" -std=c++14 -fno-exceptions -DTINYUSDZ_NO_BUILTIN_IMAGE_LOADER \
            -Dnsel_CONFIG_SELECT_EXPECTED=1 -I"$TU"
    done
    add cxx "$TU/integerCoding.cpp" tusdz_integerCoding -std=c++14 -fno-exceptions \
        -DTINYUSDZ_NO_BUILTIN_IMAGE_LOADER -Dnsel_CONFIG_SELECT_EXPECTED=1 -I"$TU"
    add c "$TU/lz4/lz4.c" tusdz_lz4
    for f in crate usda_read; do
        add cxx "$SRC/src/io/formats/usd_flat/$f.cpp" "usdflat_$f" -std=c++23 \
            -DTINYUSDZ_NO_BUILTIN_IMAGE_LOADER -Dnsel_CONFIG_SELECT_EXPECTED=1 "${INC[@]}"
    done

    # tree-sitter + tree-sitter-python + the editor's buffer analysis
    # -fno-sanitize=function (vendored C only): tree-sitter calls the grammar's scanner hooks through
    # typed pointers, but tree-sitter-python/src/scanner.c defines them unprototyped (`f()`), so UBSan
    # halts at external/tree-sitter/lib/src/parser.c:380:46 on every input, including both seeds.
    # ASan and every other UBSan check stay halting.
    for f in alloc get_changed_ranges language lexer node parser point query stack subtree tree tree_cursor wasm_store; do
        add c "$TS/lib/src/$f.c" "ts_$f" -fno-sanitize=function -D_POSIX_C_SOURCE=200112L -D_DEFAULT_SOURCE \
            -I"$TS/lib/include" -I"$TS/lib/src"
    done
    for f in parser scanner; do
        add c "$TSP/src/$f.c" "tspy_$f" -fno-sanitize=function -I"$TSP/src" -I"$TSP/bindings/c" -I"$TS/lib/include"
    done
    add cxx "$SRC/src/python/python_buffer_analysis.cpp" python_buffer_analysis -std=c++23 \
        -I"$TS/lib/include" -I"$TSP/bindings/c" "${INC[@]}"

    # tinyply and stb_image implementation units exactly as the app builds them
    add cxx "$SRC/src/io/tinyply.cpp" io_tinyply -std=c++23 "${INC[@]}"
    add cxx "$SRC/src/io/stb_image_impl.cpp" io_stb_image -std=c++23 "${INC[@]}"

    # project-file chapter DOM
    add cxx "$SRC/src/io/json_chapter_dom.cpp" json_chapter_dom -std=c++23 "${INC[@]}"

    # SPZ (as in src/io/CMakeLists.txt spz_lib)
    for f in load-spz splat-types splat-c-types splat-extensions coordinate-system-adobe \
             safe-orbit-camera-adobe provenance-lichtfeld; do
        add cxx "$SRC/external/spz/$f.cc" "spz_$f" -std=c++23 -DSPZ_BUILD_EXTENSIONS -I"$SRC/external/spz"
    done

    # OpenMesh Core (vendored)
    while IFS= read -r f; do
        add cxx "$f" "om_$(basename "$f" .cc)" -std=c++17 -w -DNDEBUG -DNO_DECREMENT_DEPRECATED_WARNINGS \
            -I"$SRC/external/OpenMesh/src"
    done < <(find "$SRC/external/OpenMesh/src/OpenMesh/Core" -name '*.cc' | sort)

    run_jobs "$list" "$flags"
    rm -f "$d"/lib*.a
    ar rcs "$d/libcore.a" "$d"/obj/core_*.o "$d"/obj/mayhem_stubs.o
    ar rcs "$d/libusd.a"  "$d"/obj/tusdz_*.o "$d"/obj/usdflat_*.o
    ar rcs "$d/libpy.a"   "$d"/obj/ts_*.o "$d"/obj/tspy_*.o "$d"/obj/python_buffer_analysis.o
    ar rcs "$d/libmisc.a" "$d"/obj/io_*.o
    ar rcs "$d/libjson.a" "$d"/obj/json_chapter_dom.o
    ar rcs "$d/libspz.a"  "$d"/obj/spz_*.o
    ar rcs "$d/libom.a"   "$d"/obj/om_*.o
}

# 1) Fuzz libs: instrumented project code, DWARF 3.
FUZZ_FLAGS="-O1 $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link"
build_libs "$OUT/fuzz" "$FUZZ_FLAGS"

# 2) Harnesses: each linked twice (libFuzzer + standalone run-once driver).
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OUT/standalone_main.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -std=c++23 -c "$M/lsan_off.cc" -o "$OUT/lsan_off.o"

LIBS_COMMON="$OUT/fuzz/libcore.a"
declare -A HLIBS=(
    [fuzz_usdc]="$OUT/fuzz/libusd.a $LIBS_COMMON"
    [fuzz_usda]="$OUT/fuzz/libusd.a $LIBS_COMMON"
    [fuzz_python_syntax]="$OUT/fuzz/libpy.a"
    [fuzz_json_chapter]="$OUT/fuzz/libjson.a $LIBS_COMMON"
    [fuzz_tinyply]="$OUT/fuzz/libmisc.a"
    [fuzz_stb_image]="$OUT/fuzz/libmisc.a"
    [fuzz_spz]="$OUT/fuzz/libspz.a -lzstd -ltbb -lz -lpthread"
    [fuzz_openmesh_obj]="-Wl,--whole-archive $OUT/fuzz/libom.a -Wl,--no-whole-archive"
    [fuzz_openmesh_off]="-Wl,--whole-archive $OUT/fuzz/libom.a -Wl,--no-whole-archive"
    [fuzz_openmesh_stl]="-Wl,--whole-archive $OUT/fuzz/libom.a -Wl,--no-whole-archive"
    [fuzz_openmesh_ply]="-Wl,--whole-archive $OUT/fuzz/libom.a -Wl,--no-whole-archive"
)
declare -A HSRC=(
    [fuzz_openmesh_obj]=fuzz_openmesh [fuzz_openmesh_off]=fuzz_openmesh
    [fuzz_openmesh_stl]=fuzz_openmesh [fuzz_openmesh_ply]=fuzz_openmesh
)
declare -A HDEF=(
    [fuzz_openmesh_obj]="-DNDEBUG -DFORMAT_EXT=\"obj\"" [fuzz_openmesh_off]="-DNDEBUG -DFORMAT_EXT=\"off\""
    [fuzz_openmesh_stl]="-DNDEBUG -DFORMAT_EXT=\"stl\"" [fuzz_openmesh_ply]="-DNDEBUG -DFORMAT_EXT=\"ply\""
)
HFLAGS="-O1 $SANITIZER_FLAGS $DEBUG_FLAGS -std=c++23 -w -DNO_DECREMENT_DEPRECATED_WARNINGS"
HFLAGS="$HFLAGS -I$SRC/external/tinyusdz/src -Dnsel_CONFIG_SELECT_EXPECTED=1"
HFLAGS="$HFLAGS -I$TS/lib/include -I$TSP/bindings/c -DSPZ_BUILD_EXTENSIONS"

link_one() {
    local name="$1"
    local src="$M/harnesses/${HSRC[$name]:-$name}.cpp"
    # shellcheck disable=SC2086
    $CXX $HFLAGS ${HDEF[$name]:-} "${INC[@]}" -fsanitize=fuzzer-no-link -c "$src" -o "$OUT/$name.o"
    # shellcheck disable=SC2086
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$OUT/$name.o" ${HLIBS[$name]} \
        "$OUT/lsan_off.o" -o "$SRC/$name"
    # shellcheck disable=SC2086
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$OUT/$name.o" "$OUT/standalone_main.o" ${HLIBS[$name]} \
        "$OUT/lsan_off.o" -o "$SRC/$name-standalone"
}
for name in "${!HLIBS[@]}"; do link_one "$name"; done

# 3) Test oracle: the same project sources built with NORMAL flags (no sanitizers) and a dynamically
#    linked KAT probe that prints known-input -> known-output facts for mayhem/test.sh to compare.
build_libs "$OUT/plain" "-O1 -g0 $COVERAGE_FLAGS"
# shellcheck disable=SC2086
$CXX -O1 -g0 $COVERAGE_FLAGS -std=c++23 -w -DNDEBUG -DNO_DECREMENT_DEPRECATED_WARNINGS \
    -Dnsel_CONFIG_SELECT_EXPECTED=1 -DSPZ_BUILD_EXTENSIONS -I"$TS/lib/include" -I"$TSP/bindings/c" "${INC[@]}" \
    "$M/kat/kat_probe.cpp" \
    "$OUT/plain/libusd.a" "$OUT/plain/libpy.a" "$OUT/plain/libjson.a" "$OUT/plain/libspz.a" \
    -Wl,--whole-archive "$OUT/plain/libom.a" -Wl,--no-whole-archive "$OUT/plain/libmisc.a" "$OUT/plain/libcore.a" -lzstd -ltbb -lz -lpthread -o "$SRC/lfs_kat_probe"

echo "build.sh: done"
