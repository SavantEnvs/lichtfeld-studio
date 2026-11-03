// LichtFeld Studio USD ASCII (.usda) reader: src/io/formats/usd_flat/usda_read.cpp over tinyusdz.
#include "usd_flat/usda_read.hpp"

#include <cstddef>
#include <cstdint>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size < 8 || size > (1u << 20)) return -1;
    auto stage = lfs::io::usd_flat::read_usda_bytes(data, size);
    if (stage) {
        volatile size_t n = stage->prims.size();
        (void)n;
    }
    return 0;
}
