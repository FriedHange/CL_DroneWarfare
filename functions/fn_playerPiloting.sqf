// A connected UAV-terminal viewer has role ""; only a remote driver takes
// flight control away from the AI. Gunner control leaves AI piloting active.
params [["_drone",objNull]];
if (isNull _drone) exitWith {false};
private _control = uavControl _drone;
private _piloting = false;
for "_i" from 0 to ((count _control) - 2) step 2 do {
    if ((_control select (_i + 1)) == "DRIVER" && {isPlayer (_control select _i)}) exitWith {
        _piloting = true;
    };
};
_piloting
