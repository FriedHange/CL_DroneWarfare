params [["_drone", objNull], ["_man", objNull]];

if (isNull _drone) exitWith { false };

// Resolve operator dynamically if dead/null (teleport/despawn guard)
if (isNull _man || {!alive _man}) then {
    private _opGrp = _drone getVariable ["CLDW_OperatorGroup", grpNull];
    if (!isNull _opGrp) then {
        private _aliveUnits = (units _opGrp) select { alive _x };
        if (count _aliveUnits > 0) then {
            _man = leader _opGrp;
        };
    };
};

// Update heartbeat to indicate AI_FPV script is active
_drone setVariable ["CLDW_FPV_Running", time + 5, true];

if (!isNull _man) then {
    _drone setVariable ["CLDW_CurrentOperator", _man, true];
    _drone setVariable ["CLDW_OperatorGroup", group _man, true];
};

if (_drone getVariable ["CLDW_Disengaged", false]) exitWith { false };

if (!alive _drone) exitWith { false };
if ((count (crew _drone)) < 1) exitWith { false };
if (isPlayer (getConnectedUAV _drone)) exitWith { true };
if (isNull _man || {!alive _man}) exitWith {
    _drone setVariable ["ddtExclude", true, true];
    {deleteVehicle _x} forEach (crew _drone);
    false
};
true
