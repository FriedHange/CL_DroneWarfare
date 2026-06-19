params [["_drone", objNull], ["_lastSeenPos", [0,0,0]], ["_man", objNull]];

if (isNull _drone || {!alive _drone}) exitWith {};

// Resolve operator dynamically if dead/null (teleport/despawn guard)
if (isNull _man || {!alive _man}) then {
    private _opGrp = _drone getVariable ["CLDW_OperatorGroup", grpNull];
    if (!isNull _opGrp) then {
        private _aliveUnits = (units _opGrp) select { alive _x };
        if (count _aliveUnits > 0) then {
            _man = leader _opGrp;
            _drone setVariable ["CLDW_CurrentOperator", _man, true];
        };
    };
};

// Leave the operator group to prevent overwriting squad waypoints
private _side = side _drone;
private _grp = createGroup _side;
(crew _drone) joinSilent _grp;
_grp setVariable ["daoExclude", true, true];
_grp setVariable ["dceExclude", true, true];
_grp setVariable ["Vcm_Disable", true, true];

// -----------------------------------------------------------------------
// HANDOFF - Do NOT fight the physics engine with manual velocity control.
// The drone already has kinetic energy from the dive.  Simply re-enable AI
// with an immediate destination; the UAV flight model will arc the drone
// toward it naturally using its own inertia, producing a smooth pull-out.
// -----------------------------------------------------------------------
_drone enableAI "PATH";
_drone enableAI "MOVE";
_drone doWatch objNull;
_grp setBehaviour "AWARE";
_grp setCombatMode "BLUE";

if (!isNull _man && {alive _man}) then {
    // Set destination immediately so the drone never hovers during the first sleep gap
    private _manPos2DImmediate = [getPosATL _man select 0, getPosATL _man select 1, 0];
    private _wpImmediate = _grp addWaypoint [_manPos2DImmediate, 15];
    _wpImmediate setWaypointType "MOVE";
    _wpImmediate setWaypointSpeed "FULL";
    _drone doMove _manPos2DImmediate;
    _drone flyInHeight 25;

    private _timeout = time + 45;
    waitUntil {
        sleep 1;

        // Resolve operator dynamically if they die or teleport during flight
        if (isNull _man || {!alive _man}) then {
            private _opGrp = _drone getVariable ["CLDW_OperatorGroup", grpNull];
            if (!isNull _opGrp) then {
                private _aliveUnits = (units _opGrp) select { alive _x };
                if (count _aliveUnits > 0) then {
                    _man = leader _opGrp;
                    _drone setVariable ["CLDW_CurrentOperator", _man, true];
                };
            };
        };

        if (isNull _man || {!alive _man}) exitWith { true };
        if (isNull _drone || {!alive _drone}) exitWith { true };

        private _manPos2D = [getPosATL _man select 0, getPosATL _man select 1, 0];

        // Update return waypoint and move order dynamically so the drone tracks a moving squad
        if (count (wayPoints _grp) > 0) then {
            (wayPoints _grp select 0) setWPPos _manPos2D;
        } else {
            private _wpReturn = _grp addWaypoint [_manPos2D, 15];
            _wpReturn setWaypointType "MOVE";
        };
        _drone doMove _manPos2D;

        ((getPosVisual _drone) distance2D _manPos2D < 35) || {time > _timeout}
    };

    if (!alive _drone || isNull _drone) exitWith {};

    if (isNull _man || {!alive _man}) exitWith {
        if (missionNamespace getVariable ["ddtDebug", false]) then {
            systemChat "Drone returning: Operator died during flight, deleting crew to crash.";
        };
        { deleteVehicle _x } forEach (crew _drone);
        deleteGroup _grp;
    };

    if (missionNamespace getVariable ["ddtDebug", false]) then {
        systemChat "Drone disengaging: Returned to squad. Rejoining group...";
    };

    private _opGrp = group _man;
    if (!isNull _opGrp) then {
        (crew _drone) joinSilent _opGrp;

        // Wait for async joinSilent to complete before deleting temp group
        private _crew = crew _drone;
        if (count _crew > 0) then {
            private _joinTimeout = time + 5;
            waitUntil {
                sleep 0.1;
                (group (_crew select 0) == _opGrp) || {time > _joinTimeout}
            };
        };
    };

    _drone setVariable ["CLDW_Disengaged", false, true];
    _drone setVariable ["CLDW_CurrentTarget", objNull, true];

    sleep 1;
    deleteGroup _grp;

    [_drone, _man] execVM "DrongosDroneTweaks\Scripts\Drones\AI_FPV.sqf";
} else {
    // Operator is dead — delete crew so drone crashes
    if (missionNamespace getVariable ["ddtDebug", false]) then {
        systemChat "Drone disengaging: Operator dead, deleting crew to crash.";
    };
    { deleteVehicle _x } forEach (crew _drone);
    deleteGroup _grp;
};
