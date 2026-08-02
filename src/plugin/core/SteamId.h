// SteamId - parse a host Steam ID from noisy clipboard text.
//
// The F2 panel lets every guest paste the host's ID instead of editing
// coop_config.json. This logic is shared by EngineUi and prototest.
//
// A Steam community ID (SteamID64) is a 17-digit decimal that begins with the
// individual-account prefix 76561 (base 0x0110000100000000). We require exactly
// 17 digits and that prefix so arbitrary clipboard junk is rejected.

#ifndef COOP_STEAM_ID_H
#define COOP_STEAM_ID_H

#include <string>

namespace coop {

// Parse a SteamID64 out of arbitrary text: keep only decimal digits, then accept
// it iff it is exactly 17 digits and starts with "76561" (the community-ID
// prefix). On success writes the value to out and returns true; otherwise leaves
// out untouched and returns false. Pure - safe to unit-test without the game.
inline bool parseSteamId64(const std::string& text, unsigned long long& out) {
    std::string digits;
    digits.reserve(text.size());
    for (size_t i = 0; i < text.size(); ++i) {
        char ch = text[i];
        if (ch >= '0' && ch <= '9') digits += ch;
    }
    if (digits.size() != 17) return false;
    if (digits.compare(0, 5, "76561") != 0) return false;
    unsigned long long v = 0;
    for (size_t i = 0; i < digits.size(); ++i) {
        v = v * 10ull + (unsigned long long)(digits[i] - '0');
    }
    out = v;
    return true;
}

} // namespace coop

#endif // COOP_STEAM_ID_H
