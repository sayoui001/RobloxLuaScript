# AAAutoPlay — Phase 3 Modular Build

Production `AAAutoPlay.lua` stays unchanged.

## Module layout
- `src/Main.luau`: startup, UI, scheduler, spawn verification and feature integrations
- `src/Core/RoadDetector.luau`: Lane 1 waypoint path and road distance
- `src/Core/PlacementEngine.luau`: candidate grid, per-type anchor planning, side direction, ground validation and spacing
- `build.json`: explicit module registry
- `tools/build.py`: deterministic bundled single-file output
- `dist/AAAutoPlay.lua`: generated test version

## Build / test
```powershell
cd C:\Work\RobloxLuaScript\AA
python tools\build.py
python tools\build.py --check
python -m unittest discover -s tests -v
```

Tests check source extraction identity, correct module bindings, and deterministic output. They do not execute Luau or confirm live placement.

## Before promoting
Run `dist/AAAutoPlay.lua` in Roblox PREVIEW, compare road and placement candidates, LEFT/CENTER/RIGHT and Slow/Farm behavior against the baseline. Only after successful runtime regression should production be replaced.

## Pending
Spawn verification, `app:Run`, AutoUpgrade, AutoSkill and UI remain in Main. Multi-lane road support is deferred.
