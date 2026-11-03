// Project-file chapter DOM: src/io/json_chapter_dom.cpp (strict JSON parse, canonical dump, typed reads).
#include "io/json_chapter_dom.hpp"

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size == 0 || size > (1u << 20)) return -1;
    auto dom = lfs::io::JsonChapterDom::parse(
        std::string_view(reinterpret_cast<const char*>(data), size));
    if (!dom) return 0;
    const std::string once = dom->dump();
    auto again = lfs::io::JsonChapterDom::parse(once);
    if (!again) __builtin_trap(); // dump() must always re-parse
    if (again->dump() != once) __builtin_trap(); // parse(dump(x)).dump() is stable
    return 0;
}
