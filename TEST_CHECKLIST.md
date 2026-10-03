# In-game test checklist

Use a fresh mission or newly spawned squads after changing squad supply settings. Configure settings on the server through CBA Addon Options. Test with the same drone addons and mission framework you plan to use in play.

## Squad allocation and backpacks

- [ ] With defaults, a six-person eligible AI squad selects 1-2 drone operators and receives 1-4 drones total, shared among those operators.
- [ ] With **Replace Existing Backpacks** off, all soldiers keep their original backpacks while selected operators can still deploy drones.
- [ ] With replacement on, only selected operators receive drone bags; the other squad members keep their original backpacks.
- [ ] Set maximum operators to 1, then 2. New squads roll 1 through the maximum, limited by eligible soldiers and stock.
- [ ] Set maximum drones per squad to 1, then 4. New squads roll 1 through the maximum; stock does not refill on rescans or casualties outside RIS.
- [ ] An operator cannot keep multiple drones active at once. After a drone is destroyed, any remaining stock can be launched.

## Random Infantry Skirmish

- [ ] In a RIS battle, let a supplied squad use all its stock. Once its last active drone is gone and 120 seconds have passed since its allocation, the surviving squad gets a new spawn-chance roll and can launch again. Check the RPT for `CLDW [RIS]: Reissuing drone supply`.
- [ ] Keep one drone alive after its squad uses the rest of its stock. The squad receives no new allocation until that drone is gone.
- [ ] Kill an infantry enemy with a rifle and check RIS's kill counter and reward: each death counts once. Repeat with a drone and check both the count and operator credit.

## Active-drone limits and load

- [ ] Set the global active cap to 2. With at least three supplied squads, no more than two CLDW drones are active at once; a blocked squad keeps its stock and can launch after capacity frees up.
- [ ] Set NATO cap to 1, global cap to 4, and launch delay to 0. Queue several NATO squads together; only one NATO drone may be active.
- [ ] Set a side cap to 1. That side can launch only one drone at a time, even if the global cap is higher. Check another side separately.
- [ ] Lower a cap below the current active count. Existing drones remain; new launches wait. A cap of 0 blocks new launches.
- [ ] In an Antistasi or other large scenario, compare server FPS/script load with the cap at 12 and a higher value while 20+ squads request drones. Check that idle drones do not climb indefinitely and destroyed drone wrecks are cleaned up.
- [ ] With the cap set to 1, observe a drone that becomes stuck. It should first attempt to return, then replace its AI pilot in place if it remains stuck. If recovery still fails, the pilot temporarily joins the operator's squad and the drone flies back physically; the pilot separates again within about 35 m. The drone must never jump to the squad, disappear, or free its cap slot while alive.
- [ ] Take manual UAV control and test inside a jammer field. The movement watchdog should leave player-controlled and actively jammed drones alone. If a drone's AI pilot dies outside a jammer field, a replacement pilot should board after about five seconds and the drone should resume flying.

## FPV guidance and damage

- [ ] Watch a moving drone in a UAV terminal and switch feeds. It keeps flying and attacking; taking driver controls yields AI piloting until released.
- [ ] Briefly hide infantry or an occupied vehicle during an attack, then reappear. The FPV should keep its assigned target and resume the attack without entering search. If sight stays broken for more than 10 seconds, it should search the last confirmed area for about 60 seconds at roughly 30 m AGL and no more than 35 km/h, without following unseen movement.
- [ ] Watch KVN, Ukraine FPV, and Crocus searches from a UAV terminal. The drone should turn and face its travel direction instead of sliding sideways; reacquiring infantry should keep the controlled 15 m/s attack limit nearby.
- [ ] Hide under a decon tent, then repeat in a cargo house and a larger building near the drone's last confirmed view. The FPV should move outside each footprint, descend to roughly 6 m, and aim for 55-70 km/h on clear exterior passes. It should attack only after obtaining a clear view through an opening.
- [ ] Lose a target among two to four buildings within roughly 60 m. The FPV should inspect each building once, aim its camera or fixed-camera nose toward the building while circling, use clear exterior transit legs before descending, and attack another enemy only after a clear view. The entire search still ends after about one minute.
- [ ] Reappear directly behind a searching drone. It should slow to roughly 20 km/h, turn level above the ground, then accelerate once facing you; it should not loop into the ground.
- [ ] With two KVN drones active, make one lose LOS. If its native pilot stalls, the RPT should report `CLDW [Search]` once and the same drone should continue a slow search without being deleted or losing its active-cap slot.
- [ ] Deploy a drone with no known targets. It climbs to its role's cruise altitude and loiters around its operator; move the squad and confirm the loiter area follows.
- [ ] Watch idle KVN and Ukraine FPV drones from a UAV terminal. Their pilots should follow native waypoints without rapid hull jitter. If one stalls, it should retry native orders, repair its pilot or group in place, and retain the same hull and cap slot.
- [ ] Break off an attack or move the target out of range. The drone returns within about 35 m of its operator before resuming idle loiter, even when the squad moves during its return.
- [ ] Hide behind a tree or wall during an infantry attack. The drone should slow, steer through a clear nearby path, and accelerate only when the direct corridor to a visible target opens. It should not dive straight through the obstacle.
- [ ] Break line of sight repeatedly while the drone searches. It should enter search from its current position without a high pull-up or reversed staging route, and the original one-minute search deadline should not restart after each brief reacquisition.
- [ ] Place an infantry target on an upper floor or in a room with a visible opening. A small FPV should line up outside, slow down, and enter only if it fits through the opening. Repeat behind a solid wall or a narrow opening; the drone should search outside instead of diving into the wall.
- [ ] Repeat the building-entry test with an open hangar, a tent, a rotated structure, and a large building with no `buildingPos` markers. The drone should use a low reachable opening and reach close contact without a fixed pull-up over the roof; an opening narrower than the drone must be rejected.
- [ ] In an Altis metal hut, interrupt the drone's view while it crosses a window or doorway. It should hold the verified entry line at about 8 m/s; a newly blocked opening should cause braking and search rather than a full-speed roof strike.
- [ ] Aim an FPV toward infantry on an Altis hillside from low altitude. It should start climbing before the rise and slow on a steep approach, without jittering against the slope or jumping upward after a stall.
- [ ] Let a KVN or UAFPV disengage and return across the same hill. It should keep making horizontal progress while climbing; it should not stop and rise vertically to cruising altitude first.
- [ ] Kill an AI drone operator during an attack, then repeat while its drone searches. Despawn that operator in Antistasi as well. In each case the AI crew should die promptly, a surviving squadmate should not inherit the drone, the hull should stay where it is, and a released active-cap slot should permit a new launch without refunding the spent drone.
- [ ] While a drone searches for a soldier, have the soldier board an occupied wheeled APC, a tracked IFV, and an MBT. AP drones may follow the first two when visible; the MBT should remain an AT target. Repeat with the vehicle hidden and empty.
- [ ] Move that target out of the building during the one-minute search. The drone should reacquire it after gaining a real view; moving the target to another unseen room should not make the drone track its hidden position.
- [ ] While the drone circles a building, send a different enemy into its view. It should switch from search to a moving attack on that enemy. If no target appears before the minute ends, a Crocus should physically return; if native return stalls, the RPT should report `CLDW [ReturnFallback]` and the drone should move without teleporting.
- [ ] Watch a covered target who shifts after the drone chooses an opening. The drone should abandon an obstructed entry, keep its active-drone slot, and continue the exterior search. Check a few different building models, since their collision geometry differs.
- [ ] At default **100% prediction strength** and **0.10 s aim interval**, attack a stationary vehicle and a vehicle moving at about 100 km/h. Record drone type, target type, hit/miss, and whether the explosion occurs on the hull.
- [ ] Repeat the 100 km/h run against a NATO MRAP from behind and from the side. Check that drones close the gap, turn toward the vehicle, and make hull contact rather than releasing above the roof.
- [ ] Repeat at 0% and 100% prediction strength, then at 0.05 s and 1.0 s aim interval. Compare long-range pursuit; close-range vehicle guidance refreshes every flight tick by design.
- [ ] Check an infantry target, a stationary vehicle, and a moving vehicle with both AP and AT FPV types. Native warhead/fuze behavior still decides damage and duds.
- [ ] Take manual UAV control during an AI attack; scripted guidance should yield to the player. Release control and check normal AI recovery.
- [ ] Check that bomber/dropper and recon drones do not perform FPV suicide dives.

## Electronic warfare

- [ ] With **Sania & Volnorez** active, fly a CLDW drone into a jammer's effective area. Guidance stops when its native jam/crew-kill effect applies. Test outside the area to confirm normal flight.
- [ ] With **EW Drone Jammer by Noriso** active, test soft jam, hard kill, and release. CLDW guidance and bomber release stop while jammed; native return-home behavior remains available when configured.
- [ ] If the jammer has an **affect AI** option, turn it off and confirm CLDW follows the addon's AI exemption.
- [ ] Test each EW addon separately before combining them. **Electronic Warfare REDUX** and other EW addons do not yet have a verified dedicated adapter in this update.

## Multiplayer and headless clients

- [ ] On a dedicated server with no HC, drones acquire targets and attack normally.
- [ ] Connect an idle HC while ACE HC AI transfer is off. Drones continue attacking; merely connecting the HC does not transfer them.
- [ ] Explicitly transfer a drone's AI group to the HC. It continues its current attack; after HC disconnect/reconnect, control resumes on the current owner.
- [ ] With its crew on the HC, despawn the drone's original AI operator. The crew should die on the HC, no new pilot should appear, the hull should remain, and its active-cap slot should be released.
- [ ] Join in progress, launch a drone, and take manual UAV control. Check inventory/stock and operator attribution after the ownership changes.

Record your mod versions, CBA settings, target/drone class names, and server RPT alongside any failed box. The automated regression suite checks stock/caps and MRAP aim prediction; **visual hit placement, native EW effects, and HC handoff need these in-game checks**.
