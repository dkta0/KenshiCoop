// Portable host + two-client session topology smoke test.
// Build: clang++ -std=c++03 -Wall -Wextra -pedantic src/sessiontest/main.cpp -o sessiontest

#ifndef _MSC_VER
#define __int64 long long
#endif

#include "../netproto/SessionTopology.h"
#include "../plugin/core/OwnRanks.h"
#include "../plugin/sync/ChangeGate.h"

#include <cstdio>
#include <cstdlib>
#include <map>
#include <set>
#include <vector>

namespace {

void check(bool condition, const char* label) {
    if (condition) {
        std::printf("PASS %s\n", label);
        return;
    }
    std::fprintf(stderr, "FAIL %s\n", label);
    std::exit(1);
}

struct SimClient {
    coop::u32 id;
    std::vector<coop::u32> relayedOwners;
};

// Models NetLink's host receive boundary: authenticate the packet owner, retain
// it on the host, then fan join-authored state to every other connected join.
bool hostReceive(SimClient& sender, const void* packet, unsigned int len,
                 std::vector<SimClient*>& clients,
                 std::vector<coop::u32>& hostOwners,
                 bool hostAuthority = false) {
    coop::u8 type = coop::packetType(packet, len);
    coop::u32 owner = 0;
    unsigned int offset = 0;
    bool carriesOwner = coop::packetOwnerOffset(type, &offset);
    if (carriesOwner &&
        (!coop::readPacketOwner(type, packet, len, &owner) || owner != sender.id))
        return false;
    if (hostAuthority && !coop::hostAuthorityAllowsClientPacket(type))
        return false;
    if (carriesOwner) hostOwners.push_back(owner);
    if (coop::relayClientPacket(type)) {
        for (size_t i = 0; i < clients.size(); ++i)
            if (clients[i]->id != sender.id)
                clients[i]->relayedOwners.push_back(owner);
    }
    return true;
}

} // namespace

int main() {
    check(sizeof(coop::WelcomePacket) == 11 &&
          sizeof(coop::LeavePacket) == 5 &&
          sizeof(coop::SaveBeginPacket) == 71 &&
          sizeof(coop::SaveFileHeader) == 23 &&
          sizeof(coop::SaveDoneHeader) == 15 &&
          sizeof(coop::LoadGoPacket) == 65 &&
          sizeof(coop::ControlCommandPacket) == 94 &&
          sizeof(coop::ControlResultPacket) == 28 &&
          sizeof(coop::ControlEpochPacket) == 9,
          "protocol 50 multiplayer packet layouts are packed");
    std::set<coop::u32> active;
    coop::u32 first = coop::assignPlayerId(active, 3);
    active.insert(first);
    coop::u32 second = coop::assignPlayerId(active, 3);
    active.insert(second);
    check(first == 1 && second == 2, "host assigns distinct lowest-free player slots");
    check(coop::assignPlayerId(active, 3) == coop::OWNER_ID_ALL,
          "configured host capacity rejects a third join");

    std::set<unsigned int> ranks1, ranks2;
    coop::resolveOwnRanks(ranks1, false, false, first);
    coop::resolveOwnRanks(ranks2, false, false, second);
    check(ranks1.count(1) == 1 && ranks2.count(2) == 1 && ranks1 != ranks2,
          "WELCOME slots map to distinct squad ranks");

    SimClient c1; c1.id = first;
    SimClient c2; c2.id = second;
    std::vector<SimClient*> clients;
    clients.push_back(&c1);
    clients.push_back(&c2);
    std::vector<coop::u32> hostOwners;

    coop::EntityBatchHeader entity;
    entity.type = (coop::u8)coop::PKT_ENTITY_BATCH;
    entity.ownerId = c1.id;
    entity.count = 0;
    entity.sendMs = 10;
    entity.epoch = 1;
    check(hostReceive(c1, &entity, sizeof(entity), clients, hostOwners),
          "host accepts client-one entity state");
    check(c2.relayedOwners.size() == 1 && c2.relayedOwners[0] == c1.id,
          "host relays client-one state to client two only");
    check(c1.relayedOwners.empty(), "host excludes authoritative sender from relay");

    coop::EventPacket eventPacket;
    std::memset(&eventPacket, 0, sizeof(eventPacket));
    eventPacket.type = (coop::u8)coop::PKT_EVENT;
    eventPacket.event = (coop::u8)coop::EVT_KNOCKOUT;
    eventPacket.ownerId = c2.id;
    check(hostReceive(c2, &eventPacket, sizeof(eventPacket), clients, hostOwners),
          "host accepts client-two reliable event");
    check(c1.relayedOwners.size() == 1 && c1.relayedOwners[0] == c2.id,
          "host relays client-two event to client one");
    check(hostOwners.size() == 2 && hostOwners[0] == c1.id && hostOwners[1] == c2.id,
          "host retains both owners for local replication");

    coop::SpeedPacket speed;
    std::memset(&speed, 0, sizeof(speed));
    speed.type = (coop::u8)coop::PKT_SPEED_REQ;
    speed.ownerId = c1.id;
    speed.speed = 2.0f;
    size_t before = c2.relayedOwners.size();
    check(hostReceive(c1, &speed, sizeof(speed), clients, hostOwners),
          "host accepts authority-only speed request");
    check(c2.relayedOwners.size() == before,
          "host-only request does not relay to other joins");

    // Protocol 50 single-authority path: a guest command authenticates at the
    // host but never relays to another guest as state. The host admits only the
    // actor in the sender's assigned rank and applies each sequence once.
    coop::ControlCommandPacket command;
    std::memset(&command, 0, sizeof(command));
    command.type = (coop::u8)coop::PKT_CONTROL_COMMAND;
    command.kind = (coop::u8)coop::CONTROL_MOVE;
    command.flags = (coop::u8)coop::CONTROL_HAS_LOCATION;
    command.ownerId = c1.id;
    command.sequence = 1;
    command.epoch = 7;
    command.actor.index = 101;
    command.actor.serial = 7;
    command.x = 42.0f;
    before = c2.relayedOwners.size();
    check(hostReceive(c1, &command, sizeof(command), clients, hostOwners),
          "host authenticates client-one control command");
    check(c2.relayedOwners.size() == before,
          "control command terminates at host instead of relaying");

    std::map<coop::u32, coop::u32> actorRank;
    actorRank[101] = 1;
    actorRank[202] = 2;
    std::map<coop::u32, coop::u32> commandSeq;
    std::map<coop::u32, float> canonicalX;
    bool ownerAllowed = coop::playerControlsSquadRank(
        c1.id, actorRank[command.actor.index]);
    bool sequenceAllowed = coop::acceptControlSequence(
        commandSeq[c1.id], command.sequence);
    if (ownerAllowed && sequenceAllowed) {
        commandSeq[c1.id] = command.sequence;
        canonicalX[command.actor.index] = command.x;
    }
    check(ownerAllowed && sequenceAllowed &&
          canonicalX[command.actor.index] == 42.0f,
          "host applies admitted command to canonical state");
    check(!coop::acceptControlSequence(commandSeq[c1.id], command.sequence),
          "duplicate control sequence cannot execute twice");

    command.ownerId = c2.id;
    command.sequence = 1;
    check(!coop::playerControlsSquadRank(
              c2.id, actorRank[command.actor.index]),
          "client two cannot command client one's squad actor");
    command.actor.index = 202;
    check(coop::playerControlsSquadRank(
              c2.id, actorRank[command.actor.index]),
          "client two commands its own distinct squad actor");

    coop::ControlResultPacket result;
    std::memset(&result, 0, sizeof(result));
    result.type = (coop::u8)coop::PKT_CONTROL_RESULT;
    result.ownerId = 0;
    result.targetId = c1.id;
    result.sequence = 1;
    result.epoch = command.epoch;
    result.status = (coop::u8)coop::CONTROL_ACCEPTED;
    check(coop::packetTargetsPlayer(result.targetId, c1.id) &&
          !coop::packetTargetsPlayer(result.targetId, c2.id),
          "host command result reaches only its author");
    float clientOneLocalPrediction = 99.0f;
    clientOneLocalPrediction = canonicalX[101];
    check(clientOneLocalPrediction == 42.0f,
          "host snapshot replaces guest presentation prediction");
    check(result.epoch == command.epoch && result.epoch != command.epoch + 1,
          "control result is fenced to the current host world generation");

    entity.ownerId = c2.id;
    check(!hostReceive(c1, &entity, sizeof(entity), clients, hostOwners),
          "host rejects a spoofed owner ID");
    check(coop::relayClientPacket((coop::u8)coop::PKT_MONEY) &&
          coop::relayClientPacket((coop::u8)coop::PKT_STEALTH),
          "shared reliable and latest-wins channels fan out");
    check(!coop::relayClientPacket((coop::u8)coop::PKT_COMBAT_HIT),
          "host-authority combat reports terminate at host");
    entity.ownerId = c1.id;
    check(!hostReceive(c1, &entity, sizeof(entity), clients, hostOwners, true),
          "single-authority host drops guest entity state");
    coop::MedicalPacket medical;
    std::memset(&medical, 0, sizeof(medical));
    medical.type = (coop::u8)coop::PKT_MEDICAL;
    medical.ownerId = c1.id;
    check(!hostReceive(c1, &medical, sizeof(medical), clients, hostOwners, true),
          "single-authority host drops guest canonical vitals");
    command.ownerId = c1.id;
    command.actor.index = 101;
    check(hostReceive(c1, &command, sizeof(command), clients, hostOwners, true),
          "single-authority host admits authenticated control intents");
    check(coop::acceptControlSequence(0xFFFFFFFFu, 1u),
          "control serial accepts wrap without sender lockout");

    std::map<coop::u32, coop::u32> seqSeen;
    check(coop::sync::gateSeqAccept(seqSeen[c1.id], 1), "client-one first row accepted");
    seqSeen[c1.id] = 1;
    check(coop::sync::gateSeqAccept(seqSeen[c2.id], 1),
          "client-two independent sequence one accepted");
    seqSeen[c2.id] = 1;
    check(!coop::sync::gateSeqAccept(seqSeen[c1.id], 1),
          "duplicate sequence rejected only for its sender");
    check(coop::packetTargetsPlayer(c1.id, c1.id) &&
          !coop::packetTargetsPlayer(c1.id, c2.id) &&
          coop::packetTargetsPlayer(coop::OWNER_ID_ALL, c2.id),
          "bootstrap save targets only the new join");

    active.erase(first);
    coop::LeavePacket left;
    left.type = (coop::u8)coop::PKT_LEAVE;
    left.playerId = first;
    std::set<coop::u32> c2RemoteOwners;
    c2RemoteOwners.insert(first);
    coop::LeavePacket receivedLeft;
    if (coop::readPacket(&left, sizeof(left), &receivedLeft)) {
        coop::u32 departedId = receivedLeft.playerId;
        c2RemoteOwners.erase(departedId);
    }
    check(c2RemoteOwners.empty(),
          "host leave notice cleans departed owner on surviving client");
    check(active.count(second) == 1, "client-two survives client-one disconnect");
    check(coop::assignPlayerId(active, 3) == first,
          "disconnect cleanup releases only the departed slot");
    check(coop::clampSessionPlayers(1) == 2 &&
          coop::clampSessionPlayers(999) == coop::MAX_SESSION_PLAYERS,
          "session capacity clamps to supported bounds");

    std::printf("SESSION RESULT PASS host=1 clients=2 owners=distinct relay=bidirectional\n");
    return 0;
}
