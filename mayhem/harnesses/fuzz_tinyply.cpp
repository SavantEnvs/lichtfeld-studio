// PLY point-cloud parsing as LichtFeld Studio's loader uses it (src/io/formats/ply.cpp): tinyply header
// parse, vertex/colour/normal property requests, and the data read.
#include "tinyply.hpp"

#include <cstddef>
#include <cstdint>
#include <exception>
#include <sstream>
#include <string>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size < 16 || size > (1u << 20)) return -1;
    std::istringstream in(std::string(reinterpret_cast<const char*>(data), size), std::ios::binary);
    try {
        tinyply::PlyFile ply;
        if (!ply.parse_header(in)) return 0;
        std::shared_ptr<tinyply::PlyData> v, c, n, f;
        v = ply.request_properties_from_element("vertex", {"x", "y", "z"});
        try { c = ply.request_properties_from_element("vertex", {"red", "green", "blue"}); } catch (...) {}
        try { n = ply.request_properties_from_element("vertex", {"nx", "ny", "nz"}); } catch (...) {}
        try { f = ply.request_properties_from_element("face", {"vertex_indices"}, 3); } catch (...) {}
        ply.read(in);
        volatile size_t cnt = v->count;
        (void)cnt;
    } catch (const std::exception&) {
    }
    return 0;
}
