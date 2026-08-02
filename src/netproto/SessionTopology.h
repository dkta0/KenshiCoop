// SessionTopology - pure C++03 multiplayer slot and relay policy.
//
// Kept beside the wire contract so the plugin, protocol tests, and the portable
// session simulator share one definition of capacity, ownership, and routing.

#ifndef KENSHICOOP_SESSION_TOPOLOGY_H
#define KENSHICOOP_SESSION_TOPOLOGY_H

#include "Wire.h"
#include <set>
#include <string.h>

namespace coop {

const u32 DEFAULT_SESSION_PLAYERS = 8u;  // host + seven joins
const u32 MAX_SESSION_PLAYERS     = 32u; // bounded by squad/interest tables

inline u32 clampSessionPlayers(int requested) {
    if (requested < 2) return 2u;
    if ((u32)requested > MAX_SESSION_PLAYERS) return MAX_SESSION_PLAYERS;
    return (u32)requested;
}

// Player 0 is always the host. Joins take the lowest free positive slot so a
// disconnected player can reclaim the same squad rank on a normal reconnect.
// Returns OWNER_ID_ALL when the configured session is full.
inline u32 assignPlayerId(const std::set<u32>& active, u32 maxPlayers) {
    maxPlayers = clampSessionPlayers((int)maxPlayers);
    for (u32 id = 1; id < maxPlayers; ++id)
        if (active.find(id) == active.end()) return id;
    return OWNER_ID_ALL;
}

// Every current packet carrying an owner puts it directly after the type byte,
// except EventPacket, whose event subtype precedes ownerId. Centralizing this
// rule lets the host reject spoofed owner IDs before dispatch or relay.
inline bool packetOwnerOffset(u8 type, unsigned int* offset) {
    if (!offset) return false;
    if (type == (u8)PKT_EVENT) { *offset = 2u; return true; }
    switch (type) {
        case PKT_ENTITY_BATCH:
        case PKT_INV_SNAPSHOT:
        case PKT_WORLD_ITEM:
        case PKT_WORLD_ITEM_REMOVE:
        case PKT_WORLD_DROP:
        case PKT_WORLD_PICKUP:
        case PKT_MEDICAL:
        case PKT_TREATMENT:
        case PKT_SPEED_REQ:
        case PKT_SPEED_SET:
        case PKT_STATS:
        case PKT_STEALTH:
        case PKT_SPAWN_REQ:
        case PKT_SPAWN_INFO:
        case PKT_MONEY:
        case PKT_FACTION:
        case PKT_TIME:
        case PKT_DOOR:
        case PKT_BUILD_PLACE:
        case PKT_BUILD_STATE:
        case PKT_BUILD_DOOR:
        case PKT_BUILD_REMOVE:
        case PKT_SAVE_REQ:
        case PKT_SAVE_BEGIN:
        case PKT_SAVE_FILE:
        case PKT_SAVE_DONE:
        case PKT_SAVE_ACK:
        case PKT_LOAD_GO:
        case PKT_LOAD_REQ:
        case PKT_LOAD_NACK:
        case PKT_PROD:
        case PKT_NPC_CENSUS:
        case PKT_INV_XFER:
        case PKT_RESEARCH:
        case PKT_CAM_HINT:
        case PKT_COMBAT_HIT:
        case PKT_WORLD_ITEM_CLAIM:
            *offset = 1u;
            return true;
        default:
            return false;
    }
}

inline bool readPacketOwner(u8 type, const void* data, unsigned int len, u32* ownerId) {
    unsigned int offset = 0;
    if (!data || !ownerId || !packetOwnerOffset(type, &offset) || len < offset + sizeof(u32))
        return false;
    memcpy(ownerId, static_cast<const unsigned char*>(data) + offset, sizeof(u32));
    return true;
}

inline bool packetTargetsPlayer(u32 targetId, u32 localId) {
    return targetId == OWNER_ID_ALL || targetId == localId;
}

// Host-only requests terminate at the authority. The remaining join-authored
// state must fan out through the host so every join sees every other join.
inline bool relayClientPacket(u8 type) {
    switch (type) {
        case PKT_ENTITY_BATCH:
        case PKT_EVENT:
        case PKT_INV_SNAPSHOT:
        case PKT_WORLD_ITEM:
        case PKT_WORLD_ITEM_REMOVE:
        case PKT_WORLD_ITEM_CLAIM:
        case PKT_WORLD_DROP:
        case PKT_WORLD_PICKUP:
        case PKT_INV_XFER:
        case PKT_MEDICAL:
        case PKT_TREATMENT:
        case PKT_STATS:
        case PKT_MONEY:
        case PKT_FACTION:
        case PKT_DOOR:
        case PKT_BUILD_PLACE:
        case PKT_BUILD_STATE:
        case PKT_BUILD_DOOR:
        case PKT_BUILD_REMOVE:
        case PKT_STEALTH:
            return true;
        default:
            return false;
    }
}

} // namespace coop

#endif // KENSHICOOP_SESSION_TOPOLOGY_H
