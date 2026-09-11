params [["_drone", objNull], ["_man", objNull]];

if (isNull _drone) exitWith { false };

// Resolve operator dynamically if dead/null (teleport/despawn guard)
if (isNull _man || {!alive _man}) then {
    private _ownerVar = _drone getVariable ["ddtOwner", objNull];
    if (_ownerVar isEqualType objNull && {!isNull _ownerVar}) then {
        _man = _ownerVar;
    } else {
        if (_ownerVar isEqualType "" && {_ownerVar != ""}) then {
            { if (str _x == _ownerVar) exitWith { _man = _x; }; } forEach allUnits;
        };
    };
    if (isNull _man || {!alive _man}) then {
        private _opGrp = _drone getVariable ["CLDW_OperatorGroup", grpNull];
        if (!isNull _opGrp) then {
            private _aliveUnits = (units _opGrp) select { alive _x };
            if (count _aliveUnits > 0) then {
                _man = leader _opGrp;
            };
        };
    };
};

// Update heartbeat to indicate AI_FPV script is active
_drone setVariable ["CLDW_FPV_Running", time + 5, true];

if (!isNull _man) then {
    _drone setVariable ["CLDW_CurrentOperator", _man, true];
    _drone setVariable ["CLDW_OperatorGroup", group _man, true];
    _drone setVariable ["ddtOwner", _man, true];
    _drone setVariable ["ddtOwner", str _man, true];
};

if (_drone getVariable ["CLDW_Disengaged", false]) exitWith { false };

if (!alive _drone) exitWith { false };
if ((count (crew _drone)) < 1) exitWith { false };
if ({getConnectedUAV _x == _drone} count allPlayers > 0 || {isPlayer (uavControl _drone select 0)}) exitWith { true };

// Keep active strike drones alive to complete their attack run even if operator dies
private _currentTarget = _drone getVariable ["CLDW_CurrentTarget", objNull];
if (!isNull _currentTarget && {alive _currentTarget}) exitWith { true };

if (isNull _man || {!alive _man}) exitWith {
    _drone setVariable ["ddtExclude", true, true];
    {deleteVehicle _x} forEach (crew _drone);
    false
};
true
