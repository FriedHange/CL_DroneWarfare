DDT_fnc_getTargetsAT = {  
    private _man = _this select 0;  
    private _range = (_this select 1) min (round CLDW_Setting_MaxRange); 
    DDT_fnc_getTargetsAT_version = 3;  
  
    missionNamespace setVariable ["ddtCooldownValue", 0, true];  
    missionNamespace setVariable ["ddtCycleAttack", 5, true];  
  
    private _man_side = side _man;  
    private _uav = connectedUAV _man;  
    private _isAPDrone = false;

    if (!isNull _uav) then {
        private _uavClass = typeOf _uav;
        // Vanilla AP check: classname contains "_AP_" (e.g. B_Crocus_AP_F)
        // UA FPV AP check: classname ends with "_AP" (e.g. B_UAFPV_IED_AP, B_UAFPV_OG7V_AP, B_UAFPV_RKG_AP)
        if (_uavClass typeOf "B_Crocus_AP_F" || _uavClass typeOf "O_Crocus_AP_F" || _uavClass typeOf "I_Crocus_AP_F" || ["_AP_", _uavClass] call BIS_fnc_inString || ["UAFPV_IED_AP", _uavClass] call BIS_fnc_inString || ["UAFPV_OG7V_AP", _uavClass] call BIS_fnc_inString || ["UAFPV_RKG_AP", _uavClass] call BIS_fnc_inString) then {
            _isAPDrone = true;
        };
    };

    private _rawTargets = _man targets [true, _range];  
    private _validTargets = [];

    {  
        private _t = vehicle _x;  
        if ((side _t) getFriend _man_side < 0.6) then {
            if (_isAPDrone) then {
                // AP TARGETING: Explicitly target infantry foot soldiers
                if (_t isKindOf "MAN") then { _validTargets pushBackUnique _t; };
            } else {
                // AT TARGETING: Explicitly target heavy armor assets, ignoring pure infantry crew entities
                if (_t isKindOf "Tank" || _t isKindOf "Car" || _t isKindOf "Wheeled_APC_F") then {
                    if (isTouchingGround _t) then { _validTargets pushBackUnique _t; };
                };
            };
        };
    } forEach _rawTargets;  
  
    // EMERGENCY FALLBACK: If specialized target sets are blank, grab any hostile ground asset to prevent idling
    if (_validTargets isEqualTo []) then {
        _validTargets = _rawTargets select {
            private _t = vehicle _x;
            ((side _t) getFriend _man_side < 0.6) && {isTouchingGround _t || _t isKindOf "MAN"}
        };
    };

    if (_validTargets isEqualTo []) exitWith {
        // GROUND-STUCK RECOVERY: If the drone has no targets and is still on the ground,
        // issue a vertical launch command so it doesn't stay permanently stuck trying to
        // navigate to a stale ground-level move order it physically cannot execute.
        if (!isNull _uav && {alive _uav}) then {
            private _uavAlt = (getPosATL _uav) select 2;
            private _uavSpeed = speed _uav;
            // Consider "on the ground" as below 3m ASL and barely moving
            if (_uavAlt < 3 && _uavSpeed < 2) then {
                private _launchPos = (getPosATL _uav) vectorAdd [0, 0, 50];
                _uav flyInHeightASL [50, 50, 50];
                (driver _uav) doMove _launchPos;
            };
        };
        []
    };
  
    // Sort all valid hostiles by proximity to nab the closest threat
    _validTargets = [_validTargets, [], { _man distance _x }, "ASCEND"] call BIS_fnc_sortBy;  
    private _closestTarget = _validTargets select 0;  
  
    _man reveal [_closestTarget, 4];  
    
    if (!isNull _uav) then {  
        _uav reveal [_closestTarget, 4];  
        _uav doWatch _closestTarget;  
        
        if (CLDW_Setting_ForceDirectMove) then {
            private _targetPos = getPosATL _closestTarget;

            if !(_targetPos isEqualTo [0,0,0]) then {
                (group _uav) setBehaviour "COMBAT";

                // DYNAMIC ALTITUDE SAFEGUARDS: Force clean clearance horizons over obstacles
                if (_isAPDrone) then {
                    // AP Drones fly at 35m to clear trees and rooftops
                    _uav flyInHeightASL [35, 35, 35];
                } else {
                    // AT Drones fly slightly higher (45m) to safely scale over large armor silhouettes 
                    // and dive-bomb straight into the thinner top armor plates of tanks!
                    _uav flyInHeightASL [45, 45, 45];
                };

                (driver _uav) doMove _targetPos;  
            };
        };
    };  
  
    [_closestTarget]  
};