// Script-editor syntax analysis: src/python/python_buffer_analysis.cpp over tree-sitter-python.
#include "python_buffer_analysis.hpp"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size == 0 || size > (1u << 18)) return -1;
    const std::string_view code(reinterpret_cast<const char*>(data), size);

    const auto a = lfs::python::analyze_python_buffer(code);
    (void)a.clean();

    lfs::python::PythonSyntaxDocument doc;
    doc.reset(code);
    (void)doc.symbols();
    (void)doc.foldRanges();
    (void)doc.highlights();
    const std::size_t off = (size * 7) / 11;
    (void)doc.scopeAt(off);
    (void)doc.enclosingBlockRanges(off);

    // Incremental reparse: replace a byte range using the input's own bytes as the edit text.
    const std::size_t cut = std::min<std::size_t>(size / 3, size);
    const std::size_t end = std::min<std::size_t>(cut + size / 4, size);
    std::string edited(code);
    edited.erase(cut, end - cut);
    const auto p0 = lfs::python::python_buffer_point_at_byte(code, cut);
    const auto p1 = lfs::python::python_buffer_point_at_byte(code, end);
    lfs::python::PythonBufferEdit e;
    e.start_byte = cut;
    e.old_end_byte = end;
    e.new_end_byte = cut;
    e.start_point = p0;
    e.old_end_point = p1;
    e.new_end_point = p0;
    doc.applyEditsAndReparse(edited, std::span<const lfs::python::PythonBufferEdit>(&e, 1));
    (void)doc.symbols();
    (void)doc.highlights();
    return 0;
}
