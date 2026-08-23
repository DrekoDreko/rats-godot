# Network Robustness — Manual Test Plan (Card 14)

This document covers the manual verification required by Card 14.
**Goal:** confirm that no disconnection scenario leaves the match stuck.

---

## Setup

1. Open **two instances** of the game (two Steam accounts or one account + editor).
2. Instance A creates a lobby → Instance B joins it.
3. Both enter the van (`Lobby_Van`).

---

## Test 1 — Client disconnects during LOBBY

1. Both players are in the parked van (`Lobby_Van`).
2. **Kill Instance B's process** (Task Manager → End Process).
3. **Verify on Instance A (host):**
   - B's avatar disappears from the van.
   - The HUD player list no longer shows B.
   - B's colour swatch is freed on the colour panel.
   - If B was marked ready, the ready counter updates (e.g. `0/1 READY`).
   - Host can still create a new lobby, invite someone else, or play solo.

**Expected result:** ✅ Host continues without freezing.

---

## Test 2 — Client disconnects during TRAVEL

1. Both players advance to the travel phase (van moving, 120s timer).
2. **Kill Instance B's process.**
3. **Verify on Instance A (host):**
   - B's avatar disappears.
   - Timer continues counting down normally.
   - Ready counter updates to `X/1`.
   - If A was the only one not ready, and B leaving made everyone ready, the phase advances.
   - Host can still buy items at the shop.
   - Phase advances normally when timer reaches zero or host marks ready.

**Expected result:** ✅ Host continues without freezing.

---

## Test 3 — Client disconnects during SURVEY

1. Both players advance to the house survey phase (60s timer).
2. B places a trap somewhere in the house.
3. **Kill Instance B's process.**
4. **Verify on Instance A (host):**
   - B's avatar disappears.
   - B's trap **remains in place** — it is not removed.
   - Timer continues counting down.
   - Ready counter updates.
   - A can still place traps and interact normally.
   - Phase advances to HUNT when timer expires or A marks ready.

**Expected result:** ✅ Host continues; traps persist.

---

## Test 4 — Client disconnects during HUNT

1. Both players advance to the hunt phase (rats spawned, no timer).
2. **Kill Instance B's process.**
3. **Verify on Instance A (host):**
   - B's avatar disappears.
   - Rats remain active and can still be hunted.
   - B's traps remain and can still catch rats.
   - When all rats are eliminated, the phase advances to RESULT.

**Expected result:** ✅ Host continues; hunt completes normally.

---

## Test 5 — Host disconnects during LOBBY

1. Both players are in the parked van.
2. **Kill Instance A's (host) process.**
3. **Verify on Instance B (client):**
   - An error message appears: "The host left the lobby." (or similar).
   - B is returned to the lobby browser screen (`lobby.tscn`).
   - The status line on the lobby screen shows the reason in red.
   - B can create a new lobby or join another one immediately.

**Expected result:** ✅ Client returns to lobby screen with clear message.

---

## Test 6 — Host disconnects during TRAVEL

1. Both players advance to the travel phase.
2. **Kill Instance A's (host) process.**
3. **Verify on Instance B (client):**
   - Same as Test 5: error message, return to lobby screen, can start again.

**Expected result:** ✅ Client returns to lobby screen.

---

## Test 7 — Host disconnects during SURVEY

1. Both players advance to the house survey phase.
2. **Kill Instance A's (host) process.**
3. **Verify on Instance B (client):**
   - Same as Test 5: error message, return to lobby screen, can start again.

**Expected result:** ✅ Client returns to lobby screen.

---

## Test 8 — Host disconnects during HUNT

1. Both players advance to the hunt phase.
2. **Kill Instance A's (host) process.**
3. **Verify on Instance B (client):**
   - Same as Test 5: error message, return to lobby screen, can start again.

**Expected result:** ✅ Client returns to lobby screen.

---

## Summary Checklist

| Scenario | Host continues? | Client returns home? | Match stuck? |
|---|---|---|---|
| Client drops in LOBBY | ✅ | N/A | ❌ No |
| Client drops in TRAVEL | ✅ | N/A | ❌ No |
| Client drops in SURVEY | ✅ | N/A | ❌ No |
| Client drops in HUNT | ✅ | N/A | ❌ No |
| Host drops in LOBBY | N/A | ✅ | ❌ No |
| Host drops in TRAVEL | N/A | ✅ | ❌ No |
| Host drops in SURVEY | N/A | ✅ | ❌ No |
| Host drops in HUNT | N/A | ✅ | ❌ No |
