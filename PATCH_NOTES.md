# CL Drone Warfare Patch Notes

## Unreleased

### Finite Squad Supply, Active Caps, and Owner-Local Control

- Supplied squads now roll 1 to the configured maximum for operators and total
  stock (defaults 2 operators and 4 drones). Minimum sliders were removed.
  Exhaustion and casualties do not generate replacement supplies.
- Disabled backpack replacement preserves operators' bags and uses scripted stock;
  enabled replacement affects only selected operators.
- Added simultaneous limits: 12 globally and 6 per side. Both are checked at launch;
  blocked launches retain stock and queued requests rotate fairly.
- Reconciled living CLDW drones into the server cap registry before launch checks;
  zero launch stagger cannot bypass a faction cap. Rate-limited server logs show
  effective counts when a launch is blocked.
- UAV-terminal viewing no longer halts autonomous flight. Only a player taking
  driver controls interrupts AI piloting.
- Reduced default engagement range from 2000 m to 750 m. Acquisition requires
  current visibility rather than projected altitude or squad knowledge
  overriding cover. Lost-target FPVs search the last seen area for 60 seconds
  using vanilla AI patrol orders at up to 35 km/h and about 30 m AGL before returning.
  Infantry reacquisition resumes controlled attack guidance; a target
  behind the drone triggers a slow, level turn before acceleration.
- When the last confirmed position is in or beside a building, a lost-target
  FPV inspects up to four nearby buildings within 60 m during the same one-minute
  search. It sizes each perimeter to the building footprint, approaches a
  clear exterior point before descending, and circles at about 6 m AGL. Clear
  exterior passes aim for 55-70 km/h on a turn-safe radius, while blocked legs
  widen around neighboring geometry. It still needs real line of sight before attacking.
  KVN and Ukraine FPV can ignore native orders while other drones are active;
  a slow, heading-aligned recovery activates only after seven seconds without progress.
- Cleared stale target/controller intent when a loitering drone can no longer
  validate it. During an attack, a drone keeps the last confirmed target position
  for 10 seconds, with no more than two seconds of observed velocity prediction.
  A close miss turns into another attack pass while the target remains visible;
  hidden targets cannot trigger a blind terminal strike.
  The original target or another visible enemy in the search area can be
  acquired during the timed orbit.
- FPV infantry attacks now choose a short, geometry-checked approach instead
  of diving solely because the drone is close. Crocus, KVN, and Ukraine FPV
  can slow down and enter a room when the soldier is visible through an opening
  large enough for the drone. Blocked routes return to exterior search, and
  emerging soldiers are checked at multiple visible body points. Building
  geometry and native warhead behavior can still prevent a kill.
- Building entry now samples low, hull-clear corridors around the actual
  structure geometry, including buildings without indoor position markers.
  It no longer adds a fixed roof-height staging climb before a visible indoor
  strike. Guidance slows at the opening and checks the actual next motion
  while turning into it. Open hangars can admit a close attack; narrow windows are rejected
  when the drone cannot physically fit.
- Outdoor infantry attacks now use short, obstacle-checked course corrections
  near cover. They slow while finding a clear path through trees or around
  walls and accelerate only on a verified direct corridor. Aborted attacks
  enter search at the last confirmed position without a scripted 45 m pull-up
  or reverse staging route. Search-to-attack handoffs share one 60-second
  search window, so repeated brief sightings cannot restart it.
- Infantry FPVs now stay on a verified hut-entry line through brief visibility
  interruptions, checking their actual hull clearance throughout. Nearby
  attacks are limited to 15 m/s outdoors and 8 m/s through narrow openings;
  blocked entries brake before resuming exterior search. Search follows a
  boarded target into a visible, occupied vehicle when payload rules allow it.
  AP drones can target wheeled APCs and tracked IFVs, but not main battle tanks.
- Low attack runs and scripted returns now sample the ground ahead, climb
  before a hill crest, and slow when the remaining distance cannot support a
  safe climb. A stalled attack disengages without the watchdog's upward
  velocity kick; the bounded search fallback also checks rising terrain.
- A CLDW drone retains its original AI operator identity during UAV-terminal
  viewing. If that operator dies or despawns, the server retires its AI crew
  on the current drone owner. The inert hull stays in place but releases its
  active-drone slot; spent squad stock is not refunded.
- Removed unconditional HC offloading. Flight and inventory run on their actual owner,
  with controller and inventory-retry guards.
- Added separate FPV prediction-strength and aim-refresh settings.
- Improved fast-vehicle interception: longer AT lead, more closing speed and
  tighter terminal turns. Vehicle aim now uses the bounding-box hull center,
  and guidance continues until native hull contact instead of stopping above it.
- Newly deployed drones receive an idle patrol order when no target is present.
  Disengaging drones keep return priority until they reach the squad; recovery
  searches no longer get interrupted by the regular target scan.
- Idle Crocus, KVN, and Ukraine FPV drones use native AI waypoints. A stuck
  native pilot gets a bounded order retry, then in-place pilot/group recovery;
  scripted idle flight is removed; attack guidance and bounded search/return
  recovery keep their existing scripted control.
- Added an owner-local progress watchdog for CLDW FPV drones. If a drone makes
  no progress for 12 seconds, it attempts to return; a stalled Crocus switches
  to physical scripted return flight after six seconds of ignored native orders.
  Continued failure replaces the AI pilot in place. If it still cannot move,
  its pilot temporarily joins the operator's squad until the drone flies within
  35 m, then separates into a UAV group. Recovery never teleports a living drone
  and keeps the same hull, stock, and cap slot. A missing pilot is replaced
  after a five-second grace period; player-controlled and jammed drones are exempt.
- Added inspected Sania (3147611501) and EW Drone Jammer (3804407201) adapters.
  The supplied latter mod is not Electronic Warfare REDUX; older Redux remains unverified.
- Native crew death and suppression stop scripted flight. Removed artificial vehicle
  damage that bypassed native warhead/fuze behavior.
- Cached pools/roles, staggered work, moved collision setup out of repeated pair scans,
  and corrected wreck cleanup ordering.
- Added an isolated dedicated-server regression suite. See UPDATE_GUIDE.md for
  settings, integration API, persistence limits, and multiplayer acceptance checks.


### Random Infantry Skirmish (RIS) Drone Kill Scoring & Attribution

- RIS squads that exhaust their stock can receive another allocation after 120 seconds,
  once their active drones have gone. New allocations still honor the spawn chance,
  operator limit, stock maximum, and live-drone caps.
- Removed the extra RIS score callback from `EntityKilled`. The installed RIS build
  declares its kill handlers `final`, so attempts to wrap them were rejected and the
  fallback could award duplicate kills. RIS now owns scoring; drone credit should be
  checked separately in the running mission.
- Drone detonation tagging and player UAV connection tracking remain for death-camera
  attribution.

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
