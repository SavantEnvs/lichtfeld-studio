// LichtFeld Studio USD crate (.usdc) reader: src/io/formats/usd_flat/crate.cpp over tinyusdz.
#include "usd_flat/crate.hpp"

#include <cstddef>
#include <cstdint>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size < 8 || size > (1u << 22)) return -1;
    auto stage = lfs::io::usd_flat::read_usdc_bytes(data, size);
    if (stage) {
        volatile size_t n = stage->prims.size();
        (void)n;
    }
    return 0;
}
