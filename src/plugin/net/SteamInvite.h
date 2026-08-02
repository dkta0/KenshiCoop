// SteamInvite - optional Steam lobby invite flow over the multi-peer P2P tunnel.
//
// A host creates one friends-only lobby with room for the protocol ceiling.
// The first arriving guest starts the network host; later lobby members are
// accepted into the already-running session. Guests learn the lobby owner's
// SteamID and connect to that host.
//
// Everything runs on the main thread. tick() drives Steam callbacks and polls
// membership; the resolved host is handed to Plugin.cpp's ConnectFn. Manual
// host-ID paste remains the normal fallback.

#ifndef KENSHICOOP_STEAMINVITE_H
#define KENSHICOOP_STEAMINVITE_H

namespace coop {
namespace steaminvite {

typedef unsigned long long SteamId;

// Fired (on the main thread, from the Steam callback pump / tick) when an invite
// resolves a peer. Matches Plugin.cpp's coopUiConnect(isHost, useSteam, peerId).
typedef void (*ConnectFn)(bool isHost, bool useSteam, SteamId peerId);

// Resolve ISteamMatchmaking/ISteamFriends from the game's steam_api64.dll and
// register the invite/lobby/P2P Steam callbacks. Idempotent; safe to call every
// frame. Requires steamp2p::init() to have succeeded first (shared Steam client).
// Returns false (and logs why) when the interfaces are unavailable.
bool init(ConnectFn onConnect);
bool ready();

// Host action: open the in-panel friend picker. Creates the lobby (async) and
// refreshes the friend list. (Replaces the Steam overlay invite dialog, whose
// friend list is broken by a Steam-client web-view bug on many titles.)
void beginInvite();

// Send a direct Steam lobby invite to a specific friend (from the picker). The
// friend gets a Steam notification; clicking it fires GameLobbyJoinRequested on
// their side and auto-joins. If the lobby is still being created, the invite is
// queued and sent on completion.
void inviteFriend(SteamId id);

// In-panel picker accessors (main thread). The list is cached in our own buffers
// (Steam's GetFriendPersonaName pointer is transient) and sorted in-Kenshi first.
// friendState: 0 = offline, 1 = online, 2 = currently playing Kenshi.
bool        pickerActive();
int         friendCount();
SteamId     friendId(int i);
const char* friendName(int i);
int         friendState(int i);

// Main-thread housekeeping: pumps Steam callbacks, refreshes the picker list, and
// polls host-side lobby membership for the arriving friend. Call every frame.
void tick();

// One-line human status for the panel/overlay (never null; "" when idle).
const char* status();

// Leave any lobby and clear invite state (called on disconnect / teardown).
void reset();

} // namespace steaminvite
} // namespace coop

#endif // KENSHICOOP_STEAMINVITE_H
