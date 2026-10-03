// Preserve legacy RC-40 distribution, but change inventory on the soldier's owner.
params ["_unit"];
if (isRemoteExecuted && {remoteExecutedOwner != 2}) exitWith {};
if (isNull _unit || {!local _unit} || {!alive _unit} || {isPlayer _unit} ||
    {_unit getVariable ["CLDW_RC40_Checked", false]}) exitWith {};
_unit setVariable ["CLDW_RC40_Checked", true, true];
private _groupSide = side group _unit;
private _weapon = primaryWeapon _unit;
private _hasGL = false;
if (_weapon != "") then {
    private _muzzles = getArray (configFile >> "CfgWeapons" >> _weapon >> "muzzles");
    if (count _muzzles > 1) then {
        {
            if (_x != "this" && {_x != _weapon}) then {
                private _lowerMuzzle = toLower _x;
                if (("ugl" in _lowerMuzzle) || ("eglm" in _lowerMuzzle) || ("gl" in _lowerMuzzle) || ("gp" in _lowerMuzzle) || ("3gl" in _lowerMuzzle) || ("m203" in _lowerMuzzle) || ("m320" in _lowerMuzzle)) then {
                    _hasGL = true;
                };
            };
            if (_hasGL) exitWith {};
        } forEach _muzzles;
    };

    if (_hasGL) then {
        private _ammoCount = round (missionNamespace getVariable ["CLDW_Setting_RC40_Count", 2]);
        private _hasAssignedDrone = false;
        {
            _x params ["_settingVar", "_magClass"];
            private _chance = missionNamespace getVariable [_settingVar, 0];
            if (_chance > 0 && {random 100 < _chance}) then {
                if !(_unit canAdd _magClass) then {
                    if (backpack _unit == "") then {
                        private _bagClass = switch (_groupSide) do {
                            case west:  { "B_AssaultPack_mcamo" };
                            case east:  { "B_AssaultPack_ocamo" };
                            default     { "B_AssaultPack_dgtl" };
                        };
                        if (!isClass (configFile >> "CfgVehicles" >> _bagClass)) then {
                            _bagClass = "B_AssaultPack_khk";
                        };
                        _unit addBackpack _bagClass;
                    } else {
                        private _mags = magazines _unit;
                        private _limit = 5;
                        while {!(_unit canAdd _magClass) && {_limit > 0} && {count _mags > 0}} do {
                            private _toRemove = _mags deleteAt 0;
                            _unit removeMagazine _toRemove;
                            _limit = _limit - 1;
                        };
                    };
                };

                private _addedCount = 0;
                for "_i" from 1 to _ammoCount do {
                    _unit addMagazine _magClass;
                    _addedCount = _addedCount + 1;
                };

                if (_addedCount > 0) then { _hasAssignedDrone = true; };

                if (missionNamespace getVariable ["ddtDebug", false]) then {
                    systemChat format ["CLDW: Added %1x RC-40 mag %2 to %3.", _addedCount, _magClass, name _unit];
                };
            };
        } forEach [
            ["CLDW_Setting_RC40_HE",         "1Rnd_RC40_HE_shell_RF"],
            ["CLDW_Setting_RC40_Recon",       "1Rnd_RC40_shell_RF"],
            ["CLDW_Setting_RC40_SmokeBlue",   "1Rnd_RC40_SmokeBlue_shell_RF"],
            ["CLDW_Setting_RC40_SmokeGreen",  "1Rnd_RC40_SmokeGreen_shell_RF"],
            ["CLDW_Setting_RC40_SmokeOrange", "1Rnd_RC40_SmokeOrange_shell_RF"],
            ["CLDW_Setting_RC40_SmokeRed",    "1Rnd_RC40_SmokeRed_shell_RF"],
            ["CLDW_Setting_RC40_SmokeWhite",  "1Rnd_RC40_SmokeWhite_shell_RF"]
        ];

        if (_hasAssignedDrone && {backpack _unit != ""}) then {
            if (missionNamespace getVariable ["CLDW_Setting_GiveAITerminal", true]) then {
                private _terminalClass = switch (_groupSide) do {
                    case west:  { "B_UavTerminal" };
                    case east:  { "O_UavTerminal" };
                    default     { "I_UavTerminal" };
                };
                if !(_terminalClass in (assignedItems _unit)) then {
                    _unit linkItem _terminalClass;
                };
            };


        };
    };
};
