# CL Drone Warfare Patch Notes

## Unreleased

### Random Infantry Skirmish (RIS) Drone Kill Scoring & Attribution

- Fixed drone kills not counting toward score, multi-kills, cash rewards, or weapon progression in RIS games:
  - **Root Cause**: RIS processes scores and kills via `RSTFM_fnc_unitKilled` / `RSTFM_fnc_vehicleKilled`, which reads the killer from `param [2]` (`_instigator`). For drone detonations, explosive scripted charges, and UAV crashes, the engine reports `_instigator` as `objNull` (or a destroyed UAV hull whose side is `sideUnknown`), causing RIS to discard the kill event without invoking the gamemode score callbacks.
  - **Function Wrapping**: Wrapped `RSTFM_fnc_unitKilled`, `RSTF_fnc_unitKilled`, `RSTFM_fnc_vehicleKilled`, and `RSTF_fnc_vehicleKilled` in `fn_droneLoop.sqf` to dynamically resolve the human or AI operator via `CLDW_fnc_resolveDroneKiller`, substituting the operator as both killer and instigator before delegating to RIS.
  - **Gamemode Score & Progression Compatibility**: Correctly updates `RSTF_SCORE` for both Friendly and Enemy sides, awards player cash (`RSTFM_fnc_addPlayerMoney`), triggers kill popups ("+100 Kill"), tracks multi-kill streaks, and advances weapon progression in Gun Game mode (`RSTF_MODE_GUN_GAME_addKill`).
  - **Drone Detonation Area Tagging**: When a drone is destroyed or detonates, all entities within a 35m radius are immediately tagged with `CLDW_LastDroneAttacker`, ensuring explosive splash casualties are reliably attributed to the operator even if the drone hull is deleted before victim death events fire.
  - **Server-Authoritative Fallback**: Added a server-side safety check in `EntityKilled` (guarded by `CLDW_RIS_Scored`) to process any drone kills that did not trigger unit-level handlers, eliminating dropped kills without risk of double scoring.
  - **Player UAV Connection Tracking**: Added a `UAVConnection` mission event handler and connection poller to ensure players manually flying drones via UAV terminals are tracked as `CLDW_CurrentOperator` and `CLDW_LastController`.
  - **Bomber Ordnance Tagging**: Dropped bombs, shells, and fired IEDs in `DDT_fnc_GuideToTargetBomber` now inherit the operator so bomber drone kills are credited identically to FPV strikes.

### Undercover-Aware Targeting (Antistasi / Antistasi Ultimate)

- FPV and bomber drones now respect the Antistasi undercover mechanic:
  - Antistasi (and Antistasi Ultimate) marks undercover players with `setCaptive true`, so `captive` is read as the live undercover state. Target validation in `getTargetsAT`, `getSoftTargets`, and `isEnemy` skips any unit (or vehicle carrying a captive crew member) the mission marked as undercover, and drones already on an attack run break off automatically and return to their squad.
  - Vehicles carrying any undercover crew member are protected as a whole, so drones never detonate on civilian cars with undercover passengers. Captive-marked (surrendered) AI are likewise spared.
  - Note: the engine also reports units concealed inside civilian vehicles as `captive`; those are protected as well, which matches Antistasi's civilian-vehicle concealment rules.
- Antistasi Ultimate's **Rivals** faction is the deliberate exception for extra difficulty: Rivals recognise their own and keep hunting undercover operatives. Rival operators are identified by the mission-assigned `isRival` unit variable and `loadouts_riv_` unit-type prefix, which distinguishes them from conventional Occupants and Invaders even though Rivals share the east engine side with Invaders.
- Cost is one `captive` check per candidate target per acquisition cycle; operator/faction resolution only runs for undercover candidates.

### Loitering Altitude Guard (Performance)

- Fixed the issue where targetless loitering drones slowly climbed to extreme altitudes (1km+ observed during long missions such as Antistasi, where squads idle in CARELESS mode for extended periods):
  - Root cause: `flyInHeight` is only a floor for vanilla AI pilots ("fly at this height or higher") and nothing ever commands descent, while the low `forceSpeed` loiter governors make AI pilots pitch up and climb to shed excess speed. Idle drones therefore ballooned upward indefinitely.
  - The idle monitor now actively commands any non-engaged drone that drifts more than 60m above its role cruise altitude (35m FPV / 40m recon / 80m dropper) back down: it cancels the speed governor for the cycle, re-asserts the cruise `flyInHeight`, damps upward momentum (hard descent for extreme excursions above 150m overage), and issues a descent `doMove` to loiter altitude above the operator.
  - The same guard was added to the disengage return flight, where the speed governor previously remained active for up to 60 seconds.
  - Active engagements (`ddtBusy` bombing runs), drones tracking live targets, and player-controlled UAVs are never interrupted by the guard.
- Cost is negligible: a few position/velocity reads per drone per monitor tick.

### Dedicated Server Stability

- Restricted AI inventory assignment, drone spawning, and drone guidance to the server so clients no longer run competing copies of the authoritative logic.
- Retained client-side team-switch protection for UAV crew units.
- Added validation before spawning derived drone vehicle classes. Invalid backpack-to-vehicle mappings are now written to the server RPT instead of being passed to `createVehicle`.
- Guarded optional Drongo's Drone Tweaks scripts so missing script files no longer produce repeated execution errors.
- Improved support for dedicated servers running missions with multiple connected clients.

### Engagement Range

- Increased the default drone targeting range from 750 metres to 2,000 metres.
- Increased the maximum configurable targeting range to 5,000 metres.
- Target acquisition, re-engagement, active guidance, and runaway protection now consistently use the configured range.
- Removed remaining hardcoded 750-metre acquisition limits.

### Mod Fallback Prevention

- Prevented vanilla UAV backpacks (AR-2 Darter / AL-6) from being distributed when Reaction Forces is loaded.
- Added a CBA setting `CLDW_Setting_AllowVanillaFallback` (default: false) allowing users to explicitly control whether vanilla fallback UAVs should ever be distributed.
- Reaction Forces soldiers will now receive their RC-40 drone ammunition without being assigned unwanted vanilla UAV backpacks.

### Vehicle & Helicopter Dive Distance

- Increased terminal dive initiation distance to 500m for all combat vehicles (tanks, APCs, trucks, cars, naval craft) and airborne helicopters.
- Drones maintain high-altitude cruise (70m AGL above target/terrain) until reaching 500m, then smoothly descend along a Hermite glide corridor directly into the vehicle or helicopter.
- Airborne helicopters are intercepted seamlessly at their target altitude.

### Visual Flight Physics & Tilt Bug Fix

- Fixed the visual bug where drones tilted backwards when chasing a target.
- Suppressed conflicting vanilla AI pilot cyclic braking during active script guidance (`disableAI "MOVE"` / `disableAI "PATH"`).
- Applied realistic 3D orientation (`setVectorDirAndUp`) every tick:
  - 20° nose-down forward pitch during horizontal high-speed cruise for authentic FPV flight.
  - Smooth nose-down dive alignment along the 3D glide slope into the target during terminal dives.
  - Dynamic banking (up to 25° roll) into turns based on yaw rate demand.
  - Smooth angular blending eliminating visual snapping or angular jitter.
- Restored AI pilot pathing and movement cleanly upon target impact, disengagement, or player takeover.

### Active Squad Target Hunting & Idle Loiter

- Resolved instances of drones hovering idly without actively seeking targets engaged by their squad:
  - Expanded candidate acquisition to include the operator's entire squad (`units _opGrp`), squad leadership `nearTargets`, and active combat enemies (`findNearestEnemy`).
  - Added approach-altitude vantage checks for squad-identified targets, allowing drones to take off and engage even when stationary near low ground obstacles (bushes, fences, low walls).
  - Newly deployed drones and returning/disengaged drones now actively follow their squad in formation loiter (~35m AGL) rather than freezing stationary in the air.
  - The idle monitor now actively commands drones to stay in formation with moving squads.

### Realistic Flight Profiles & Speed Separation for Dropper Drones

- Separated flight speed and loitering profiles by drone operational role (`SUICIDE` vs `DROPPER` vs `NONCOMBAT`):
  - **FPV Suicide Drones**: Retain high racing speeds (150 km/h, 41.6 m/s top strike speed; 97.5 km/h cruise) in `FULL` speed mode.
  - **Dropper / Bomber Drones** (Western Sahara IED drones, Mavic droppers, Drongo's `DRA_UAV_01G`, Baba Yaga, R-18, etc.): Now fly at realistic, calm cruising and loitering speeds (35 km/h, ~9.7 m/s) with `NORMAL` engine speed mode and steady 80m AGL bombing altitude. They no longer dart across the sky like agile FPV quads.
  - **Non-Combat Utility / Recon Drones** (AL-6 Pelican, AR-2 Darter, Black Hornet, medical/cargo): Cruising speed locked to 38 km/h (~10.5 m/s) in `NORMAL` speed mode at 40m AGL.
- Added a new CBA setting `CLDW_Setting_DropperSpeed` (default: 35 km/h, configurable from 15 to 80 km/h) under "Flight Profile".
- Fixed an issue where active bombing runs by dropper drones were interrupted by squad recall logic, preventing oscillation and unnatural speed surges.
- Overrode Drongo's `DDT_fnc_GuideToTargetBomber` to enforce realistic 35 km/h level-flight bombing runs and eliminated post-drop `forceSpeed -1` / `setSpeedMode "FULL"` throttle bursts.

### Vehicle Pursuit & Terminal Impact Damage Fix

- Fixed an issue where FPV drones chasing moving vehicles lagged behind, detonated prematurely into empty air behind the rear bumper, and dealt zero damage to the vehicle:
  - **Predictive Intercept Lead for Moving Vehicles**: Lowered the moving vehicle threshold from 80 km/h to 8 km/h and applied exact quadratic time-to-intercept calculations. Drones now lead moving vehicles along their velocity vector right up to contact, rather than reverting to zero-lead aim inside the commit distance.
  - **Correct 3D Aim Height**: Fixed aim coordinates for vehicles to target the vehicle's true 3D bounding center and upper chassis/engine deck (+0.2m), eliminating the negative height offset that forced drones to dive into the dirt/road beneath or behind the car.
  - **Terminal Contact Threshold**: Dynamically adjusted the detonation distance for moving vehicles based on their physical bounding box, ensuring guidance continues until the drone penetrates the vehicle's bounding volume rather than exiting 6 metres early in empty air.
  - **Terrain Proximity Guard Tuning**: Refined the terrain threat guard so drones diving towards low-profile vehicles within 40 metres are not prematurely aborted.
  - **Vehicle Damage Assurance**: Implemented a damage assurance watcher on terminal contact that guarantees warhead and component damage (engine destruction, tire blowouts, occupant injury/casualty, and hull damage) if the vehicle moves away from the native mod's blast center without taking damage.

### Fixed Attack Profile Values

The following internal attack values are intentionally hardcoded and are no longer exposed as CBA settings:

| Behaviour | Value |
| --- | ---: |
| Moving-vehicle threshold | 8 km/h |
| Moving-vehicle forward lead | 1.2 m |
| Prediction time limit | 2.5 s |
| Vehicle & Heli dive start distance | 500 m |
| Vehicle aim-height correction | +0.2 m (aims at roof/hood/engine deck) |
| Guidance direction check interval | 50 ms (20 Hz in terminal dive) |
| Infantry wind-up duration | 3 s |
| Infantry wind-up distance | 150 m |
| Infantry speed multiplier | 0.70 |

The overall targeting range and maximum drone speed remain configurable through CBA settings.

### Validation

- Verified balanced braces, brackets, and parentheses in the modified SQF and configuration files.
- Verified the working diff with `git diff --check`.
- A live Arma 3 dedicated-server test is still recommended for final release validation.
