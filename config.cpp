class CfgPatches
{
    class CL_DroneWarfare_Main
    {
        name = "CL Drone Warfare Framework";
        author = "Carl Lorenzo";
        url = "";
        requiredVersion = 2.02;
        requiredAddons[] = {"cba_main", "cba_xeh"};
        // Optional soft dependency: Ukraine FPV Drone mod (3475006113)
        // Drones from fpv_ua are included in pool when the mod is loaded
        optionalAddons[] = {"fpv_ua"};
        units[] = {};
        weapons[] = {};
    };
};

class Extended_PreInit_EventHandlers {
    class CL_DroneWarfare_Settings_Init {
        // Restored absolute path mapping to match your new folder name
        init = "call compile preprocessFileLineNumbers '\CL_DroneWarfare\XEH_preInit.sqf'";
    };
};

class Extended_Init_EventHandlers {
    class Air {
        class CLDW_SuppressLaser {
            init = "params ['_veh']; if (_veh isKindOf 'UAV') then { _veh setVariable ['ace_markinglaser_hasLaser', false]; };";
        };
    };
};

class CfgFunctions
{
    class CLDW
    {
        class DroneLogic
        {
            // Restored absolute path mapping to your functions directory
            file = "\CL_DroneWarfare\functions";
            class getTargetsAT {}; 
            class getSoftTargets {};
            class droneLoop { postInit = 1; }; 
            class guideToTarget {};
            class predictImpactPoint {};
            class move {};
            class disengage {};
            class droneGroupAlive {};
            class isEnemy {};
            class isAPDrone {};
            class canAttackVehicle {};
            class isUndercoverProtected {};
            class resolveDroneKiller {};
            class getDroneRole {};
            class classifyDroneRole {};
            class supplyRC40 {};
            class getDronePools {};
            class assignSquad {};
            class supplyInventory {};
            class queueSquad {};
            class canLaunch {};
            class deploy {};
            class droneTick {};
            class watchdog {};
            class retireOrphan {};
            class retireOrphanCrew {};
            class rejoinSquad {};
            class playerPiloting {};
            class hasVisualTarget {};
            class visibleAimPoint {};
            class clearFlightPath {};
            class terrainLookahead {};
            class findSafeApproach {};
            class planAttack {};
            class searchFlight {};
            class startController {};
            class guideFlight {};
            class returnFlight {};
            class bomberFlight {};
            class getEWState {};
            class registerEWAdapter {};
            class initRuntime { postInit = 1; };

        };
    };
};


// These entrypoints validate server origin and current ownership themselves.
class CfgRemoteExec {
    class Functions {
        class CLDW_fnc_supplyRC40 { allowedTargets = 0; jip = 0; };
        class CLDW_fnc_supplyInventory { allowedTargets = 0; jip = 0; };
        class CLDW_fnc_droneTick { allowedTargets = 0; jip = 0; };
        class CLDW_fnc_retireOrphan { allowedTargets = 0; jip = 0; };
        class CLDW_fnc_retireOrphanCrew { allowedTargets = 0; jip = 0; };
        class CLDW_fnc_startController { allowedTargets = 0; jip = 0; };
        class CLDW_fnc_move { allowedTargets = 0; jip = 0; };
        class CLDW_fnc_rejoinSquad { allowedTargets = 2; jip = 0; };
    };
};
