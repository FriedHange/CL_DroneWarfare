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

class CfgFunctions
{
    class CLDW
    {
        class DroneLogic
        {
            // Restored absolute path mapping to your functions directory
            file = "\CL_DroneWarfare\functions";
            class getTargetsAT {}; 
            class droneLoop { postInit = 1; }; 
        };
    };
};