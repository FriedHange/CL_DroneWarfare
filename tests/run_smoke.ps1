param(
    [Parameter(Mandatory=$true)][string]$ArmaDir,
    [int]$Port = 24382,
    [int]$TimeoutSeconds = 120,
    [switch]$WithHC,
    [switch]$WithExtraFPV,
    [switch]$SearchOnly,
    [switch]$BuildingOnly,
    [switch]$HillOnly
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$runDir = Join-Path $env:TEMP ('CLDW-smoke-' + [guid]::NewGuid().ToString('N'))
$sourceDir = Join-Path $runDir 'CL_DroneWarfare'
$modDir = Join-Path $runDir '@CL_DroneWarfare'
$modAddons = Join-Path $modDir 'addons'
$profileDir = Join-Path $runDir 'profiles'
$missionRelative = 'CLDW_Validation\' + [guid]::NewGuid().ToString('N')
$missionRoot = Join-Path $ArmaDir $missionRelative
$worldName = if ($HillOnly) {'Altis'} else {'VR'}
$missionName = "CLDW_Smoke.$worldName"
$missionDir = Join-Path $missionRoot $missionName
New-Item -ItemType Directory -Path $sourceDir,$modAddons,$profileDir,$missionDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'config.cpp'),(Join-Path $repo 'XEH_preInit.sqf') -Destination $sourceDir
Copy-Item -LiteralPath (Join-Path $repo 'functions') -Destination $sourceDir -Recurse
$fileBank = Join-Path $ArmaDir '..\Arma 3 Tools\FileBank\FileBank.exe'
$builder = Start-Process -FilePath $fileBank -ArgumentList @('-property','prefix=CL_DroneWarfare','-dst',('"' + $modAddons + '"'),('"' + $sourceDir + '"')) -WorkingDirectory $runDir -WindowStyle Hidden -Wait -PassThru
if ($builder.ExitCode -ne 0) {throw "FileBank failed: $($builder.ExitCode)"}
$pbo = Join-Path $modAddons 'CL_DroneWarfare.pbo'
if (!(Test-Path -LiteralPath $pbo)) {throw "Missing packaged addon: $pbo"}
$missionText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mission.sqm') -Raw
if ($HillOnly) {$missionText = $missionText.Replace('A3_Map_VR','A3_Map_Altis')}
$missionText | Set-Content -LiteralPath (Join-Path $missionDir 'mission.sqm')
if ($HillOnly) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'hill.sqf') -Destination $missionDir
    '[] execVM "hill.sqf";' | Set-Content -LiteralPath (Join-Path $missionDir 'initServer.sqf')
} else {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'smoke.sqf') -Destination $missionDir
    ('CLDW_SMOKE_ExpectHC = ' + $(if ($WithHC) {'true'} else {'false'}) + '; CLDW_SMOKE_ExtraFPV = ' + $(if ($WithExtraFPV) {'true'} else {'false'}) + '; CLDW_SMOKE_SearchOnly = ' + $(if ($SearchOnly) {'true'} else {'false'}) + '; CLDW_SMOKE_BuildingOnly = ' + $(if ($BuildingOnly) {'true'} else {'false'}) + '; [] execVM "smoke.sqf";') | Set-Content -LiteralPath (Join-Path $missionDir 'initServer.sqf')
}
'author="CLDW"; onLoadName="CLDW addon smoke"; class Header {gameType=COOP; minPlayers=1; maxPlayers=2;};' | Set-Content -LiteralPath (Join-Path $missionDir 'description.ext')
@'
hostname="CLDW local smoke";
password="cldw-local-smoke";
passwordAdmin="cldw-local-smoke-admin";
BattlEye=0;
verifySignatures=0;
persistent=1;
maxPlayers=2;
headlessClients[]={"127.0.0.1"};
localClient[]={"127.0.0.1"};
class Missions {class Validation {template="MISSION_TEMPLATE"; difficulty="Regular";};};
'@ | Set-Content -LiteralPath (Join-Path $runDir 'server.cfg')
(Get-Content -LiteralPath (Join-Path $runDir 'server.cfg') -Raw).Replace('MISSION_TEMPLATE',$missionName) | Set-Content -LiteralPath (Join-Path $runDir 'server.cfg')
$workshop = Join-Path $ArmaDir '!Workshop'
$modPaths = @(
    (Join-Path $workshop '@CBA_A3'),
    (Join-Path $workshop '@ace'),
    'D:\SteamLibrary\steamapps\workshop\content\107410\3147611501',
    'D:\SteamLibrary\steamapps\workshop\content\107410\3804407201',
    (Join-Path $workshop '@FPV Drone Crocus'),
    $modDir
)
if ($WithExtraFPV) {
    $modPaths += (Join-Path $workshop '@KVN Fiber-Optic FPV Drone')
    $modPaths += (Join-Path $workshop '@Ukraine FPV Drone (edited)')
}
$mods = $modPaths -join ';'
$arguments = @(
    '-autoInit','-noSound','-filePatching','-ip=127.0.0.1',"-port=$Port",
    ('-config="' + (Join-Path $runDir 'server.cfg') + '"'),
    ('-profiles="' + $profileDir + '"'),
    ('-mpmissions="' + $missionRelative + '"'),
    ('-mod="' + $mods + '"')
)
$process = Start-Process -FilePath (Join-Path $ArmaDir 'arma3server_x64.exe') -ArgumentList $arguments -WorkingDirectory $ArmaDir -WindowStyle Hidden -PassThru
Write-Output "Smoke PID $($process.Id); package: $pbo; logs: $profileDir"
$hcProcess = $null
if ($WithHC) {
    $readyDeadline = [DateTime]::UtcNow.AddSeconds(45)
    $serverReady = $false
    while ([DateTime]::UtcNow -lt $readyDeadline -and !$process.HasExited) {
        $readyRpt = Get-ChildItem -LiteralPath $profileDir -Filter '*.rpt' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($readyRpt -and ((Get-Content -LiteralPath $readyRpt.FullName -Raw) -match 'Starting mission:')) {
            $serverReady = $true
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if (!$serverReady) {throw "Server never reached mission start. Inspect $profileDir"}
    $hcProfile = Join-Path $runDir 'hc-profiles'
    New-Item -ItemType Directory -Path $hcProfile -Force | Out-Null
    $hcArgs = @('-client','-noSound','-world=empty','-connect=127.0.0.1',"-port=$Port",
        '-password=cldw-local-smoke','-name=CLDWTestHC',
        ('-profiles="' + $hcProfile + '"'),('-mod="' + $mods + '"'))
    $hcProcess = Start-Process -FilePath (Join-Path $ArmaDir 'arma3_x64.exe') -ArgumentList $hcArgs -WorkingDirectory $ArmaDir -WindowStyle Hidden -PassThru
    Write-Output "HC PID $($hcProcess.Id); logs: $hcProfile"
}
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$passed = $false
try {
    while ([DateTime]::UtcNow -lt $deadline -and !$process.HasExited) {
        Start-Sleep -Seconds 1
        $rpt = Get-ChildItem -LiteralPath $profileDir -Filter '*.rpt' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($rpt) {
            $log = Get-Content -LiteralPath $rpt.FullName -Raw
            if ($log -match 'CLDW_SMOKE DONE failures=(\d+)') {
                $passed = $Matches[1] -eq '0' -and !($log -match 'Error in expression|Error position|Error Undefined|Unknown enum value')
                $log -split [Environment]::NewLine | Where-Object {$_ -match 'CLDW_SMOKE|Error in expression|Error position|Error Undefined|Unknown enum value'}
                break
            }
        }
    }
} finally {
    if ($hcProcess) {
        if (!$hcProcess.HasExited) {Stop-Process -Id $hcProcess.Id -Force}
        $hcProcess.WaitForExit(15000) | Out-Null
    }
    if (!$process.HasExited) {Stop-Process -Id $process.Id -Force}
    $process.WaitForExit(15000) | Out-Null
    $checkedRoot = [IO.Path]::GetFullPath($missionRoot)
    $expectedParent = [IO.Path]::GetFullPath((Join-Path $ArmaDir 'CLDW_Validation')) + '\'
    if (!$checkedRoot.StartsWith($expectedParent, [StringComparison]::OrdinalIgnoreCase)) {throw 'Unexpected validation directory'}
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        try {Remove-Item -LiteralPath $checkedRoot -Recurse -Force -ErrorAction Stop; break}
        catch {
            if ($attempt -eq 9) {throw}
            Start-Sleep -Milliseconds 500
        }
    }
}
if (!$passed) {throw "Addon smoke failed or timed out. Inspect $profileDir"}
