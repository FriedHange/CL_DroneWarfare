params [["_man", objNull], ["_rangeInput", 2000]];

// If _man is a group, resolve it to the group leader unit
if (_man isEqualType grpNull) then { _man = leader _man; };
if (isNull _man) exitWith { [] };

// If _man is a vehicle (e.g. UAV itself), resolve it to its crew or driver
if (_man isKindOf "AllVehicles" && {!(_man isKindOf "Man")}) then {
    private _crew = crew _man;
    if (count _crew > 0) then {
        _man = _crew select 0;
    } else {
        _man = driver _man;
    };
};
if (isNull _man) exitWith { [] };

private _maxRangeSetting = missionNamespace getVariable ["CLDW_Setting_MaxRange", 1500];
private _range = _maxRangeSetting;
if (!isNil "_rangeInput" && { _rangeInput isEqualType 0 }) then {
    _range = _rangeInput min (round _maxRangeSetting);
};

private _targets = _man targets [true, _range];
private _out = [];
private _threshold = missionNamespace getVariable ["ddtSoftThreshold", 100];
private _manSide = side _man;

{
    private _v = vehicle _x;
    private _vSide = side _v;
    if ((_man distance _v) <= _range && { (_manSide getFriend _vSide < 0.6) && _v isKindOf "MAN" }) then {
        _out pushBackUnique _v;
    } else {
        if ((_man distance _v) <= _range && { (_manSide getFriend _vSide < 0.6) && isTouchingGround _v }) then {
            if ((getNumber(configFile >> "CfgVehicles" >> (typeOf _v) >> "armor")) > _threshold) exitWith {};
            _out pushBackUnique _v;
        };
    };
} forEach _targets;

if !(_out isEqualTo []) then {
    private _uav = objNull;
    if (vehicle _man != _man) then {
        _uav = vehicle _man;
    } else {
        _uav = getConnectedUAV _man;
    };
    if (isNull _uav) then {
        private _manStr = str _man;
        private _nearUAVs = vehicles select { 
            (_x isKindOf "UAV" || _x isKindOf "Air") && 
            { (_x getVariable ["ddtOwner", ""]) == _manStr } 
        };
        if (count _nearUAVs > 0) then {
            _uav = _nearUAVs select 0;
        };
    };
    
    if (!isNull _uav) then {
        private _closestTarget = objNull;
        private _minDist = 999999;
        {
            private _d = _man distance _x;
            if (_d < _minDist) then {
                _minDist = _d;
                _closestTarget = _x;
            };
        } forEach _out;
        
        if (!isNull _closestTarget) then {
            _uav setVariable ["CLDW_CurrentTarget", _closestTarget, true];
            _uav setVariable ["CLDW_CurrentOperator", _man, true];
        };
    };
};

_out
