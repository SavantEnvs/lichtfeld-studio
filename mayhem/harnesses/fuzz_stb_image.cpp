// Image decoding as LichtFeld Studio configures stb_image (src/io/stb_image_impl.cpp).
#include "stb_image.h"

#include <cstddef>
#include <cstdint>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size < 8 || size > (1u << 22)) return -1;
    int w = 0, h = 0, c = 0;
    if (!stbi_info_from_memory(data, static_cast<int>(size), &w, &h, &c)) return 0;
    if (w <= 0 || h <= 0 || static_cast<int64_t>(w) * h > (1 << 22)) return 0;
    if (stbi_uc* px = stbi_load_from_memory(data, static_cast<int>(size), &w, &h, &c, 3)) {
        stbi_image_free(px);
    }
    return 0;
}
