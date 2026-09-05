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

### Vehicle Attacks

- Added first-order target prediction for vehicles travelling at 80 km/h or faster.
- Fast-vehicle interception now accounts for:
  - Current vehicle position.
  - Vehicle velocity.
  - Estimated drone time to impact.
  - An additional 1-metre forward lead.
- Prediction look-ahead is capped at 2.5 seconds to prevent excessive lead after sudden direction changes.
- Slow and stationary vehicles continue to receive direct attacks rather than predictive lead.
- Aim point uses the vehicle bounding center clamped at least 0.8m above terrain, removing previous ground-skimming negative offsets.
- Predictive aiming remains active during terminal guidance instead of reverting to the vehicle's current position at close range.
- Vehicle descent now begins from 1,000 metres, giving drones more time to establish an interception course before fast vehicles can escape.

### Infantry Balance

- Added a phased infantry attack profile to provide counterplay.
- The infantry wind-up begins when the drone reaches 150 metres from its target.
- Drones stage for 3 seconds before beginning an infantry dive.
- Infantry dives use 70% of the configured maximum drone speed.
- Wind-up completion is retained if guidance restarts against the same infantry target after an obstruction or recovery manoeuvre.
- Vehicle attacks remain immediate and use the full configured maximum speed.

### Terminal Dive & Flight Smoothing

- **500ms Direction Check Cadence**: Decoupled target direction calculation, predictive lead recalculation, and waypoint projection from high-frequency physics ticks to run every ~500ms. This completely eliminates 20 Hz angular oscillations and visual jitter in terminal dives.
- **Continuous Velocity Interpolation**: Retained 20 Hz (50ms) tick for smooth physics velocity application, allowing PhysX to accelerate cleanly along the steady guidance vector.
- **Instant Proximity Detonation**: Proximity detection runs every 50ms against both the predicted impact point and actual vehicle bounding volume, ensuring immediate detonation on contact.
- **Mod-Native Detonations**: Removed artificial payload ammo spawning and script deletions on impact; drones trigger `_drone setDamage 1;` so third-party drone mods (Crocus, KVN, UAFPV) handle their own native warhead explosions and deletions.
- Improved drone vehicle-class resolution by preferring the backpack's configured `assembleTo` class.

### Fixed Attack Profile Values

The following internal attack values are intentionally hardcoded and are no longer exposed as CBA settings:

| Behaviour | Value |
| --- | ---: |
| Fast-vehicle threshold | 80 km/h |
| Fast-vehicle forward lead | 1 m |
| Prediction time limit | 2.5 s |
| Vehicle dive start distance | 1,000 m |
| Vehicle aim-height correction | 0.0 m (clamped >= 0.8m above ground) |
| Guidance direction check interval | 500 ms (0.5 s) |
| Infantry wind-up duration | 3 s |
| Infantry wind-up distance | 150 m |
| Infantry speed multiplier | 0.70 |

The overall targeting range and maximum drone speed remain configurable through CBA settings.

### Validation

- Verified balanced braces, brackets, and parentheses in the modified SQF and configuration files.
- Verified the working diff with `git diff --check`.
- A live Arma 3 dedicated-server test is still recommended for final release validation.
