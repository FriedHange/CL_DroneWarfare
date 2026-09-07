# CL Drone Warfare Patch Notes

## Unreleased

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

### Fixed Attack Profile Values

The following internal attack values are intentionally hardcoded and are no longer exposed as CBA settings:

| Behaviour | Value |
| --- | ---: |
| Fast-vehicle threshold | 80 km/h |
| Fast-vehicle forward lead | 1 m |
| Prediction time limit | 2.5 s |
| Vehicle & Heli dive start distance | 500 m |
| Vehicle aim-height correction | 0.0 m (clamped >= 0.8m above ground) |
| Guidance direction check interval | 50 ms (20 Hz in terminal dive) |
| Infantry wind-up duration | 3 s |
| Infantry wind-up distance | 150 m |
| Infantry speed multiplier | 0.70 |

The overall targeting range and maximum drone speed remain configurable through CBA settings.

### Validation

- Verified balanced braces, brackets, and parentheses in the modified SQF and configuration files.
- Verified the working diff with `git diff --check`.
- A live Arma 3 dedicated-server test is still recommended for final release validation.
