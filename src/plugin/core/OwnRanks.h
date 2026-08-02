// OwnRanks.h - squad-tab ownership resolution (pure, zero game/Win32 deps).
//
// The ownership partition decides which squad tabs a player controls locally
// and streams (its own) versus drives from remote streams. Player slot N owns
// squad-tab rank N by default (the host is slot 0); an explicit
// KENSHICOOP_OWN_SQUAD/OWN_RANK env override wins. This logic is shared by:
//   * Config.cpp   - initial resolution at load
//   * Plugin.cpp   - re-resolution on role changes and WELCOME assignment
//   * prototest    - the no-game unit layer that guards assignment semantics
//
// Before the handshake a join uses slot 1 as a harmless provisional default.
// WELCOME supplies its real slot, and Plugin.cpp resolves again before the first
// game-thread replication pass.

#ifndef COOP_OWN_RANKS_H
#define COOP_OWN_RANKS_H

#include <set>
#include <string>

namespace coop {

// Parse a CSV of unsigned ints ("0", "1", "1,2") into out. Tolerant of spaces
// or any non-digit separator. Returns true if at least one rank was parsed.
inline bool parseRankList(const std::string& csv, std::set<unsigned int>& out) {
    unsigned int v = 0; bool have = false; bool any = false;
    for (size_t i = 0; i < csv.size(); ++i) {
        char ch = csv[i];
        if (ch >= '0' && ch <= '9') { v = v * 10u + (unsigned int)(ch - '0'); have = true; }
        else if (have) { out.insert(v); any = true; v = 0; have = false; }
    }
    if (have) { out.insert(v); any = true; }
    return any;
}

// Resolve the ownership ranks a session should hold for a role/player slot.
//   fromEnv == true : ranks came from an explicit env override - preserve them.
//   fromEnv == false: own the assigned slot's squad rank (host is always rank 0).
// Safe to call repeatedly on role switches and reconnect assignments.
inline void resolveOwnRanks(std::set<unsigned int>& ranks, bool isHost, bool fromEnv,
                            unsigned int assignedPlayer = 1u) {
    if (fromEnv) return;
    ranks.clear();
    ranks.insert(isHost ? 0u : (assignedPlayer == 0u ? 1u : assignedPlayer));
}

} // namespace coop

#endif // COOP_OWN_RANKS_H
