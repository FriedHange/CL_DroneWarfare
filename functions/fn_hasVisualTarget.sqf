// Actual, current camera/eye visibility. Squad knowledge supplies candidates,
// but never lets a drone see through foliage, structures, or terrain.
params [["_observer",objNull],["_target",objNull]];
!(([_observer,_target] call CLDW_fnc_visibleAimPoint) isEqualTo [])
