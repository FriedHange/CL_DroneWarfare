# Finite supply and EW update

## Settings

All settings are server-authoritative CBA settings.

| Setting | Default | Range |
| --- | --- | --- |
| Maximum operators per squad | 2 | 1?10 |
| Maximum drones per squad | 4 | 1?10 |
| Maximum engagement range | 750 m | 150?5000 m |
| Maximum active CLDW drones, globally | 12 | 0?100 |
| Maximum active CLDW drones, each side | 6 | 0?100 |
| FPV prediction strength | 100% | 0?100% |
| FPV aim-update interval | 0.10 seconds | 0.05?1 second |

The squad receives a single random stock allocation, split evenly among selected operators.
Equipped bags count toward that allocation. Supply does not regenerate when operators die,
finish their stock, or move groups in ordinary missions. In RIS, a surviving squad
can receive another stock allocation 120 seconds after its previous roll, once all
its stock is spent and its drones are gone. The spawn-chance roll is repeated for
each RIS allocation.
Supply settings affect new allocations. Each supplied squad rolls 1 through
each configured maximum; existing allocations remain unchanged. Existing presets
retain CLDW_Setting_MaxDrones for maximum operators. Stored values for the
removed minimum settings are ignored.

RIS owns kill scoring. The addon no longer calls RIS kill handlers from its
`EntityKilled` hook, which previously could award a second kill for the same victim.
Drone operator tracking remains available for the RIS death camera. Verify RIS
credit for drone kills separately in your mission build.

With **Replace Existing Backpacks** off, selected operators retain their bags and deploy
from scripted stock. With it on, only selected operators receive replacement drone bags.
The next bag comes from the same finite allowance. Each operator can have one active drone.
Legacy RC-40 ammunition distribution is separate and retains its inventory behavior.

Both the global and relevant side cap must have room. Zero blocks launches. Alive
CLDW-deployed drones count while attacking, idle, jammed, or player-controlled.
If the original AI operator dies or despawns, the drone's AI crew is disabled
and its inert hull stops counting toward these caps. Spent stock is not refunded;
UAV-terminal spectators do not become the assigned operator.
Lowering a cap does not delete drones. Player-created and externally spawned drones are
outside these launch caps. Merged groups retain existing bags/stock but only the allowed
number of operators can launch.

Terminal viewing does not pause AI flight; taking driver control does. Infantry
targets require current drone visibility, even when the squad has reported them.
After 10 seconds without renewed sight during an attack, an FPV searches the last
confirmed area for 60 seconds. The native area patrol is limited to 35 km/h
and about 30 m AGL. A visible target triggers an
immediate attack; nearby outdoor infantry pursuit stays at or below 15 m/s,
while a verified room entry slows to 8 m/s. Infantry guidance tests a small set of
clear approaches and checks
the drone's body clearance before committing. A target behind solid cover remains
in the exterior search; the drone does not explore unseen rooms. Native warheads
and the building's collision model still determine whether contact causes a kill.
Near outdoor infantry cover, the FPV checks a short path ahead and maneuvers
at up to 15 m/s while the direct path is blocked. A brief loss of sight keeps
the confirmed target location, with at most two seconds of velocity prediction;
it cannot authorize a blind dive through cover. Hull clearance is checked
throughout an entry; a blocked route brakes before switching to search.
Repeated search and attack handoffs use the same 60-second deadline.
At a building near the last confirmed target position, search moves outside
the roof and inspects the perimeter at about 6 m AGL. Clear exterior legs aim
for 55-70 km/h. The orbit radius follows the rotated building bounds and the
space needed to turn, widening around neighboring obstacles. Search can inspect
up to four nearby buildings within 60 m during the same one-minute window, climbing safely
between roofs. Its pilot camera or fixed-camera nose faces inward while it
circles each building. A target behind the FPV triggers a slow,
level turn before acceleration, avoiding a full-speed loop into the ground.
Entry is conditional on a visible infantry target and a clear corridor wide
enough for the drone. The engine tests verify a decon tent opening and a cargo
house route; closed walls and obstructed doors still prevent entry.
Search also checks other visible enemies near the last-seen area. If none
appears before the minute ends, the drone returns. A Crocus whose native return
pilot stalls switches to physical scripted flight. The watchdog replaces an
unresponsive pilot in place, then temporarily joins the operator's squad if
necessary; the pilot separates again after the drone flies within 35 m. A
living drone never teleports to its operator and retains its active-cap slot.
If a searched-for soldier boards an occupied vehicle, a visible vehicle can
replace the soldier as the target. AP FPVs may attack wheeled vehicles and
IFVs, including tracked BMP-type vehicles; main battle tanks remain AT targets.
Idle FPVs use native AI waypoints. KVN and Ukraine FPV pilots that ignore
orders receive a bounded native-order retry and pilot or group repair in place.
KVN and Ukraine FPV use a slow, heading-aligned recovery path only when their
native AI pilot makes no progress for seven seconds; the existing watchdog still
handles a drone that cannot recover.

Scripted reserves cannot be looted and are not integrated with Antistasi campaign
save/load persistence. Frameworks that delete/recreate groups produce new entities;
cross-save resource conservation requires a mission-specific adapter.

## EW integrations

Hooks were inspected directly in these installed addons:

- **Sania & Volnorez**, Workshop 3147611501: reads DB_jammer_isUavJamming.
  Native AI suppression kills crew and immediately clears the flag; CLDW also stops
  control when the pilot dies. It does not revive crew or opt out of native behavior.
- **EW Drone Jammer by Noriso**, Workshop 3804407201: respects EWDJ_jamState,
  EWDJ_hardKilled, affectAI, and the optional native return-home journey.
  Classification, exclusions, frequencies, ranges, and immunity remain native.

The second supplied mod is **not Electronic Warfare REDUX** (3449308652).
That older Redux version has no verified dedicated adapter in this update.
Do not advertise blanket compatibility with every EW addon. Sania's inspected version
has no fibre-optic immunity rule; CLDW does not invent one.

Other addons can register a read-only, unscheduled predicate on every machine:

    ["MyEW", {
        params ["_drone"];
        _drone getVariable ["MyEW_ControlSuppressed", false]
    }] call CLDW_fnc_registerEWAdapter;

For mission integration, setting CLDW_EWSuppressed to true on the drone also suspends
CLDW control; set it false to release. Publish the variable for multiplayer.
Adapter results are cached for at most 0.1 seconds. Suppression stops guidance, bomber
release, movement, and recovery. CLDW no longer manufactures vehicle damage after a dud.

## Multiplayer and performance

New UAV groups stay on the server. Connecting an HC does not itself transfer them.
After external ownership transfers, the server dispatches ticks to the actual owner,
stale controllers stop, and the new owner resumes the published intent. Inventory
requests target the owning soldier and reject stale revisions.
Install the mod on server, clients, and HCs.

Remote-execution allowlists must permit CLDW_fnc_supplyInventory,
CLDW_fnc_supplyRC40, CLDW_fnc_droneTick, CLDW_fnc_startController, and CLDW_fnc_move.
Their remote entrypoints accept server-originated calls only.

Class pools/roles are cached. Intercept calculations follow the aim interval while
flight/safety ticks stay responsive. Group scans and target acquisition are staggered.
Collision pairs are initialized at creation/ownership changes. Wreck cleanup is
scheduled before pruning the active registry.

## Validation

Run tests/run_engine.ps1 with -ArmaDir pointing to Arma 3.
It launches an isolated localhost dedicated server, stages its own mission below
Arma 3\CLDW_Validation, removes that unique mission directory afterward, preserves
temporary logs, and stops only its own process. It never starts the normal mod loop.

Run tests/run_smoke.ps1 with -ArmaDir for a packaged-addon smoke test with the
installed CBA, ACE, Crocus, Sania, and EW Drone Jammer mods. Add -WithHC to
connect a real headless client and exercise ownership transfer. On this machine the
optional client did not join the localhost mission, so that HC run failed at its
connection precondition and did not validate transfer behavior. The regular packaged
smoke run passed; use the HC option on a server where a client can connect. It likewise stages a
unique mission and package, preserves logs, and stops its own local server.

The regression suite exercises actual source functions for stock, backpacks, caps, duplicate
requests, exhaustion, casualties, transfers, invalid mappings, role-cache invalidation,
adapter state, and controller lifecycle. EW providers and CBA scheduling are fixtures;
these tests do not certify native radio/physics integration. The regression mission
passed 75 checks and the packaged Crocus/KVN/Ukraine FPV smoke mission passed all
checks. The focused search and building-entry run covers boarded-target handoff,
controlled infantry speed, compound inspection, and
a Crocus slowing for a visible room and either reaching the target or retreating
alive when the corridor closed. The full run includes idle
movement, return to squad, switching from idle orbit to an infantry attack, and
repair of immobile KVN and Ukraine FPV drones that would otherwise hold the
active cap without working. The watchdog attempts a return after 12 seconds
without 8 m of horizontal progress; after another 15 seconds it moves the same
hull to clear air near the operator and rejoins its crew to the squad. Pilotless
hulls get a replacement AI pilot after a five-second grace period. Player-controlled
and actively jammed drones are exempt; repair keeps squad stock and the cap slot.

Before publishing, test an idle HC, transferred AI, HC disconnect/reconnect, and JIP.
Test each native EW addon separately, player takeovers, FPV moving/stationary targets
at accuracy extremes, bomber takeoff/release, and Antistasi with 20+ requested drones.
Compare server FPS/script time in the same mission.
