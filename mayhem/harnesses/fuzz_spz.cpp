// SPZ gaussian-splat container (external/spz) as loaded by src/io/formats/spz.cpp.
#include "load-spz.h"

#include <cstddef>
#include <cstdint>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size < 16 || size > (1u << 21)) return -1;
    try {
        spz::UnpackOptions opts;
        auto cloud = spz::loadSpz(data, size, opts);
        volatile int32_t n = cloud.numPoints;
        (void)n;
    } catch (...) {
    }
    return 0;
}
