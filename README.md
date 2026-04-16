# NicknameMod — BeamMP Server Plugin

A BeamMP server plugin that allows players to set a custom display nickname, independent of their BeamMP account name. Nicknames are synchronized across all connected clients in real time.

---

## Installation

1. Copy `Server/NicknameMod/` into your BeamMP server's `Resources/Server/` directory.
2. Copy `Client/NicknameModClient/` into your BeamMP server's client mod `Ressources/Client/` directory, or package it as a `.zip` mod for distribution.
3. Start or restart the server.

---

## How It Works

### Architecture

The mod is split into two components:

- Server : It holds the authoritative nickname registry, handles chat commands, and dispatches network events to clients.
- Client : It receives nickname data from the server and applies it to the in-game player list every frame.

### Server Side

The server maintains two in-memory tables:

- `nickDB` — maps player IDs (as string keys) to their chosen nicknames.
- `nameDB` — maps player IDs to their original BeamMP account names, captured at join time.

On joining, each player is sent the full nickname table (`nickBulk`) and native name table (`nativeNames`). On disconnect, the player's nickname entry is cleared and a `nickRemove` event is broadcast to all clients.

Whenever a vehicle spawns, BeamMP resets the player name on all clients, so the server responds by re-broadcasting the full nickname table to everyone (`broadcastBulk`).

Chat commands are intercepted server-side. If a player has a nickname, their chat messages are re-sent under that nickname (the original message is suppressed).

### Client Side

The GE extension registers handlers for four server events:

| Event | Description |
|---|---|
| `nickBulk` | Receives the full nickname table on join or vehicle spawn |
| `nickSet` | Receives a single nickname update |
| `nickRemove` | Restores a player's original name |
| `nativeNames` | Receives the original BeamMP names table |

On `onClientStartMission`, a 3-second timer fires before the client requests the full nickname state from the server (`requestAll`). This delay is intended to let the player list stabilize before the first sync.

Every frame, `onUpdate` calls `applyAll()` if the nickname table is non-empty. This corrects `players[id].name` whenever BeamMP or a vehicle spawn resets it back to the native name.

---

## Chat Commands

| Command | Description |
|---|---|
| `!setname <nickname>` | Set a nickname (alias: `!name`) |
| `!resetname` | Remove your nickname and restore your native name |
| `!myname` | Display your current nickname |
| `!nickhelp` | Show available commands |

### Nickname Validation Rules

- Minimum 2 characters, maximum 20 characters.
- Allowed characters: letters, digits, `-`, `_`, `.`
- Nicknames are case-insensitively unique — no two players can share the same nickname.

---

## Strengths

- **Persistent sync on vehicle spawn.** BeamMP resets player names each time a vehicle is spawned. The mod counters this by re-broadcasting the full nickname table on every `onVehicleSpawn` event, and by re-applying nicknames every frame on the client.
- **Clean name restoration.** When a nickname is removed (via `!resetname` or player disconnect), the player's original BeamMP name is properly restored from `nameDB`, not lost.
- **Lightweight per-frame cost.** The `applyAll` loop only runs when `nickTable` is non-empty, and its per-player cost is a single table lookup and string comparison.
- **No external dependencies.** The plugin uses only BeamMP and GE Lua built-in APIs. No database, no file I/O, no third-party libraries.
- **Collision protection.** The server rejects nicknames already in use by another connected player (case-insensitive).
- **Graceful initial request.** The 3-second delay before `requestAll` helps avoid race conditions with the player list not yet being populated.
- **Chat identity spoofing prevention.** Chat messages from players with nicknames are re-sent by the server under that nickname, so the displayed sender always matches the in-game name.

---

## Weaknesses & Known Limitations

- **No persistence across sessions.** Nicknames are stored in memory only. If the server restarts, all nicknames are lost and players must set them again.
- **String key inconsistency.** `nickDB` and `nameDB` use string keys (`idKey(playerID)`), while the client-side `nickTable` uses numeric keys. This asymmetry is harmless in practice but makes the codebase harder to reason about and maintain.
- **`broadcastBulk` on every vehicle spawn is expensive at scale.** Every vehicle spawn triggers a full re-send of both `nickDB` and `nameDB` to all connected players. On a server with many players or frequent vehicle spawns, this generates unnecessary network traffic.
- **`getPlayersRef` uses debug upvalue introspection.** The client locates the internal `players` table by iterating over the upvalues of `MPVehicleGE.setPlayerNickPrefix`. This is fragile and may break silently if BeamMP updates change that function's closure structure.
- **Per-frame `applyAll` without rate limiting.** The client corrects nicknames on every single update tick. Even though the cost per player is low, calling this unconditionally at 60+ FPS is wasteful when corrections are needed only after specific events (joins, vehicle spawns).
- **No admin commands.** There is no way for a server admin to forcibly set or remove another player's nickname, or to view all active nicknames from the console.
- **No nickname blocklist or profanity filter.** The validation only enforces character set and length rules; no filtering of reserved words or offensive names.
- **`onNickCmd` is reachable by all clients.** The `nickCmd` server event handler does not restrict `set` and `reset` to the player's own ID. A malicious client could theoretically attempt to send a crafted `set` payload for another player ID (though BeamMP's event system typically binds events to the sender's player ID — this depends on BeamMP's internal routing).
- **`ui_message` only shown to the local player.** Nickname confirmation feedback (`[NicknameMod] Nickname: ...`) is only visible to the player whose nick was changed, which is correct — but it relies on `MPConfig.getPlayerServerID()` being available at the time of the event, which may not always be the case early in a session.

---

## License

No liscence, only pleasure to share somehting could be used and appreciate by other people
