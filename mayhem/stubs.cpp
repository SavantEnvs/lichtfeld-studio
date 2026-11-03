// Link-time stand-in for the one core symbol lfs::Error (src/core/error.cpp) needs from the crash
// handler / CUDA side of the app. Everything else is real project code.
#include "core/failure_report.hpp"

#include <cstdio>
#include <cstdlib>
#include <string_view>

namespace lfs::core::detail {
    [[noreturn]] void assertion_failed(std::string_view contract, std::string_view expression,
                                       std::string_view message, SourceSite) {
        std::fprintf(stderr, "LFS assertion failed: %.*s %.*s %.*s\n",
                     static_cast<int>(contract.size()), contract.data(),
                     static_cast<int>(expression.size()), expression.data(),
                     static_cast<int>(message.size()), message.data());
        std::abort();
    }
} // namespace lfs::core::detail
