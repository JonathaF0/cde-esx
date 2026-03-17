--[[
    CDECAD Sync - 911 & NPC Reports Client for ESX
    Handles automatic NPC witness reports for crimes
]]

-- =============================================================================
-- NPC GUNSHOT DETECTION
-- =============================================================================

local lastGunshotReport = 0
local GUNSHOT_COOLDOWN = Config.NPCReports.Gunshots and Config.NPCReports.Gunshots.Cooldown or 60
local GUNSHOT_RADIUS = Config.NPCReports.Gunshots and Config.NPCReports.Gunshots.Radius or 200.0

-- Weapon hash lookup for gunshots
local GunWeapons = {
    [`WEAPON_PISTOL`] = true,
    [`WEAPON_PISTOL_MK2`] = true,
    [`WEAPON_COMBATPISTOL`] = true,
    [`WEAPON_APPISTOL`] = true,
    [`WEAPON_PISTOL50`] = true,
    [`WEAPON_SNSPISTOL`] = true,
    [`WEAPON_SNSPISTOL_MK2`] = true,
    [`WEAPON_HEAVYPISTOL`] = true,
    [`WEAPON_VINTAGEPISTOL`] = true,
    [`WEAPON_MARKSMANPISTOL`] = true,
    [`WEAPON_REVOLVER`] = true,
    [`WEAPON_REVOLVER_MK2`] = true,
    [`WEAPON_DOUBLEACTION`] = true,
    [`WEAPON_CERAMICPISTOL`] = true,
    [`WEAPON_NAVYREVOLVER`] = true,
    [`WEAPON_GADGETPISTOL`] = true,
    [`WEAPON_MICROSMG`] = true,
    [`WEAPON_SMG`] = true,
    [`WEAPON_SMG_MK2`] = true,
    [`WEAPON_ASSAULTSMG`] = true,
    [`WEAPON_COMBATPDW`] = true,
    [`WEAPON_MACHINEPISTOL`] = true,
    [`WEAPON_MINISMG`] = true,
    [`WEAPON_RAYCARBINE`] = true,
    [`WEAPON_PUMPSHOTGUN`] = true,
    [`WEAPON_PUMPSHOTGUN_MK2`] = true,
    [`WEAPON_SAWNOFFSHOTGUN`] = true,
    [`WEAPON_ASSAULTSHOTGUN`] = true,
    [`WEAPON_BULLPUPSHOTGUN`] = true,
    [`WEAPON_MUSKET`] = true,
    [`WEAPON_HEAVYSHOTGUN`] = true,
    [`WEAPON_DBSHOTGUN`] = true,
    [`WEAPON_AUTOSHOTGUN`] = true,
    [`WEAPON_COMBATSHOTGUN`] = true,
    [`WEAPON_ASSAULTRIFLE`] = true,
    [`WEAPON_ASSAULTRIFLE_MK2`] = true,
    [`WEAPON_CARBINERIFLE`] = true,
    [`WEAPON_CARBINERIFLE_MK2`] = true,
    [`WEAPON_ADVANCEDRIFLE`] = true,
    [`WEAPON_SPECIALCARBINE`] = true,
    [`WEAPON_SPECIALCARBINE_MK2`] = true,
    [`WEAPON_BULLPUPRIFLE`] = true,
    [`WEAPON_BULLPUPRIFLE_MK2`] = true,
    [`WEAPON_COMPACTRIFLE`] = true,
    [`WEAPON_MILITARYRIFLE`] = true,
    [`WEAPON_MG`] = true,
    [`WEAPON_COMBATMG`] = true,
    [`WEAPON_COMBATMG_MK2`] = true,
    [`WEAPON_GUSENBERG`] = true,
    [`WEAPON_SNIPERRIFLE`] = true,
    [`WEAPON_HEAVYSNIPER`] = true,
    [`WEAPON_HEAVYSNIPER_MK2`] = true,
    [`WEAPON_MARKSMANRIFLE`] = true,
    [`WEAPON_MARKSMANRIFLE_MK2`] = true,
    [`WEAPON_MINIGUN`] = true,
}

-- Check if weapon is a gun
local function IsGunWeapon(weaponHash)
    return GunWeapons[weaponHash] == true
end

-- Get nearby NPCs
local function GetNearbyPeds(coords, radius)
    local peds = {}
    local handle, ped = FindFirstPed()
    local success = true

    repeat
        local pedCoords = GetEntityCoords(ped)
        local distance = #(coords - pedCoords)

        if distance <= radius and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped) then
            table.insert(peds, ped)
        end

        success, ped = FindNextPed(handle)
    until not success

    EndFindPed(handle)
    return peds
end

-- Report gunshots if NPCs are nearby
local function CheckGunshotReport()
    if not Config.NPCReports.Enabled or not Config.NPCReports.Gunshots.Enabled then
        return
    end

    local now = GetGameTimer()
    if now - lastGunshotReport < GUNSHOT_COOLDOWN * 1000 then
        return
    end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local nearbyPeds = GetNearbyPeds(playerCoords, GUNSHOT_RADIUS)

    if #nearbyPeds > 0 then
        lastGunshotReport = now

        local street = exports['cdecad-sync']:GetLocationInfo().street
        local postal = nil

        pcall(function()
            postal = exports['nearest-postal']:getPostal()
        end)

        TriggerServerEvent('cdecad-sync:server:npcReport', {
            reportType = 'Gunshots',
            callType = 'Shots Fired',
            location = street or 'Unknown Location',
            coords = playerCoords,
            postal = postal and tostring(postal) or nil
        })

        Utils.Debug('NPC Gunshot report triggered')
    end
end

-- Monitor for gunshots
if Config.NPCReports.Enabled and Config.NPCReports.Gunshots and Config.NPCReports.Gunshots.Enabled then
    CreateThread(function()
        while true do
            Wait(100)

            local playerPed = PlayerPedId()

            if IsPedShooting(playerPed) then
                local weapon = GetSelectedPedWeapon(playerPed)
                if IsGunWeapon(weapon) then
                    CheckGunshotReport()
                end
            end
        end
    end)
end

-- =============================================================================
-- VEHICLE THEFT DETECTION
-- =============================================================================

local lastVehicleTheftReport = 0
local THEFT_COOLDOWN = Config.NPCReports.VehicleTheft and Config.NPCReports.VehicleTheft.Cooldown or 120
local trackedVehicles = {}

if Config.NPCReports.Enabled and Config.NPCReports.VehicleTheft and Config.NPCReports.VehicleTheft.Enabled then
    CreateThread(function()
        while true do
            Wait(1000)

            local playerPed = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(playerPed, false)

            if vehicle ~= 0 then
                local vehicleId = NetworkGetNetworkIdFromEntity(vehicle)

                if not trackedVehicles[vehicleId] then
                    local plate = GetVehicleNumberPlateText(vehicle)

                    trackedVehicles[vehicleId] = {
                        plate = plate,
                        entered = GetGameTimer()
                    }
                end
            end
        end
    end)
end

-- =============================================================================
-- FIGHT DETECTION
-- =============================================================================

local lastFightReport = 0
local FIGHT_COOLDOWN = Config.NPCReports.Fights and Config.NPCReports.Fights.Cooldown or 60

if Config.NPCReports.Enabled and Config.NPCReports.Fights and Config.NPCReports.Fights.Enabled then
    CreateThread(function()
        while true do
            Wait(500)

            local playerPed = PlayerPedId()

            if IsPedInMeleeCombat(playerPed) then
                local now = GetGameTimer()

                if now - lastFightReport > FIGHT_COOLDOWN * 1000 then
                    local playerCoords = GetEntityCoords(playerPed)
                    local nearbyPeds = GetNearbyPeds(playerCoords, 50.0)

                    if #nearbyPeds > 0 then
                        lastFightReport = now

                        local street = exports['cdecad-sync']:GetLocationInfo().street

                        TriggerServerEvent('cdecad-sync:server:npcReport', {
                            reportType = 'Fighting',
                            callType = 'Assault/Fight',
                            location = street or 'Unknown Location',
                            coords = playerCoords
                        })

                        Utils.Debug('NPC Fight report triggered')
                    end
                end
            end
        end
    end)
end

-- =============================================================================
-- SPEED CAMERA SYSTEM (Optional)
-- =============================================================================

if Config.NPCReports.Enabled and Config.NPCReports.SpeedCamera and Config.NPCReports.SpeedCamera.Enabled then
    local SpeedCameras = {
        -- Example locations - add your own
        -- { coords = vector3(x, y, z), speedLimit = 50, name = "Los Santos Freeway" },
    }

    local lastSpeedReport = {}

    CreateThread(function()
        while true do
            Wait(1000)

            local playerPed = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(playerPed, false)

            if vehicle ~= 0 then
                local speed = GetEntitySpeed(vehicle) * 2.236936 -- Convert to mph
                local playerCoords = GetEntityCoords(playerPed)

                for i, camera in ipairs(SpeedCameras) do
                    local distance = #(playerCoords - camera.coords)

                    if distance < 50.0 and speed > camera.speedLimit then
                        local now = GetGameTimer()

                        if not lastSpeedReport[i] or now - lastSpeedReport[i] > 60000 then
                            lastSpeedReport[i] = now

                            local plate = GetVehicleNumberPlateText(vehicle)

                            TriggerServerEvent('cdecad-sync:server:npcReport', {
                                reportType = 'SpeedCamera',
                                callType = 'Speeding Vehicle',
                                location = camera.name or 'Speed Camera Zone',
                                coords = playerCoords,
                                metadata = {
                                    plate = plate,
                                    speed = math.floor(speed),
                                    limit = camera.speedLimit
                                }
                            })

                            Utils.Debug('Speed camera triggered:', plate, speed)
                        end
                    end
                end
            end
        end
    end)
end

-- =============================================================================
-- PANIC BUTTON (For LEO/EMS)
-- =============================================================================

RegisterCommand('panic', function()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local street = exports['cdecad-sync']:GetLocationInfo().street

    local ESX = exports['es_extended']:getSharedObject()
    local playerData = ESX.GetPlayerData()
    local job = playerData and playerData.job

    if not job then return end

    local callerInfo = string.format('%s (%s)',
        GetPlayerName(PlayerId()),
        job.label or job.name
    )

    TriggerServerEvent('cdecad-sync:server:911call', {
        callType = 'Officer Down / Panic',
        location = street .. ' - EMERGENCY PANIC BUTTON',
        callerName = callerInfo,
        coords = { x = playerCoords.x, y = playerCoords.y, z = playerCoords.z },
        priority = 'critical'
    })

    lib.notify({
        title = 'PANIC',
        description = 'Emergency signal sent!',
        type = 'error',
        duration = 5000
    })
end, false)

TriggerEvent('chat:addSuggestion', '/panic', 'Send emergency panic signal', {})

print('[CDECAD-SYNC] 911 Client script loaded (ESX)')
