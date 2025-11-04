# Roblox Party Game Scripts

This repository contains Roblox Lua scripts for fast-paced party experiences. Two game modes are currently included:

- `DeathDate` – a cinematic countdown elimination system.
- `ChairTag` – a chaotic musical-chairs survival round with traps, hazards, and shoving.


## Chair Tag

Chair Tag is designed to plug directly into an experience without requiring pre-built assets. The server script will generate an arena floor and spawn the required chairs automatically.

```
roblox/ChairTag/
  ServerScriptService/
    ChairTagController.server.lua
  StarterPlayerScripts/
    ChairTagClient.client.lua
```

### Installation

1. In Studio, create folders `ChairTag` under both `ServerScriptService` and `StarterPlayerScripts` (to mirror the repo structure).
2. Copy `ChairTagController.server.lua` into `ServerScriptService/ChairTag`.
3. Copy `ChairTagClient.client.lua` into `StarterPlayerScripts/ChairTag`.
4. Publish or play test the experience. The first time it runs the controller will create a simple floor and place chairs automatically.
5. Optionally, add a custom folder `Workspace.ChairTagArena` with decorative geometry. Any anchored part tagged with the attribute `ChairTagSafe` will be ignored by hazards.

### Core Features

- 60-second rounds where players must sit before time expires or be eliminated.
- Pushing mechanic (default key `Q` / gamepad `RB`) with server-side cooldown and multi-target knockback.
- Fake/vanishing chairs that collapse after a brief delay when used.
- Rotating random hazards (chair shuffle, gusts, meteor rain, trap surge) broadcast to all clients.
- Client HUD for countdowns, alive counts, hazard toasts, and push cooldown feedback.

### Configuration Highlights

Adjust the constants at the top of `ChairTagController.server.lua` to tune the experience:

- `ROUND_MIN_PLAYERS`, `ROUND_PREP_TIME`, `ROUND_DURATION`, `ROUND_INTERMISSION` – flow settings.
- `PUSH_COOLDOWN`, `PUSH_RADIUS`, `PUSH_FORCE` – push combat tuning.
- `FAKE_CHAIR_RATIO`, `FAKE_CHAIR_MIN`, `FAKE_CHAIR_DELAY` – trap behaviour.
- `HAZARD_MIN_DELAY`, `HAZARD_MAX_DELAY` – hazard cadence.


## Death Date

The original countdown elimination system lives under `roblox/DeathDate/`. It still functions independently and can be dropped into an experience alongside Chair Tag if desired. Follow the inline script comments for setup instructions.