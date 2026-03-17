--[[
    CDECAD Sync - Main Server Script for ESX
    Handles ESX events and syncs data to CDECAD
]]

-- Get ESX object
local ESX = exports['es_extended']:getSharedObject()

-- Load VehicleUtils module directly (shared_script globals not accessible in async callbacks)
local VehicleUtils = load(LoadResourceFile(GetCurrentResourceName(), 'shared/vehicles.lua'))()

-- Store synced civilians (identifier -> CAD civilian ID)
local syncedCivilians = {}
local syncedVehicles = {}

-- Forward declarations (functions defined later)
local SyncPlayerVehicles

-- =============================================================================
-- ESX HELPER FUNCTIONS
-- =============================================================================

local function GetPlayer(source)
    return ESX.GetPlayerFromId(source)
end

local function GetAllPlayers()
    return ESX.GetExtendedPlayers()
end

-- =============================================================================
-- CHARACTER SYNC FUNCTIONS
-- =============================================================================

-- Build civilian data from ESX player data
local function BuildCivilianData(source, xPlayer)
    -- Get the player's Discord ID
    local discordId = nil
    local identifiers = GetPlayerIdentifiers(source)
    for _, id in ipairs(identifiers) do
        if string.find(id, 'discord:') then
            discordId = id:gsub('discord:', '')
            break
        end
    end

    -- ESX stores character info differently than QBCore
    -- In ESX Legacy, getName() returns the RP name set via esx_identity
    -- The identifier is typically license:xxxx or steam:xxxx
    local identifier = xPlayer.getIdentifier()
    local playerName = xPlayer.getName()

    -- Try to split the name into first and last
    local firstName = playerName
    local lastName = ''
    if playerName then
        local parts = {}
        for word in playerName:gmatch('%S+') do
            table.insert(parts, word)
        end
        if #parts >= 2 then
            firstName = parts[1]
            lastName = table.concat(parts, ' ', 2)
        elseif #parts == 1 then
            firstName = parts[1]
            lastName = ''
        end
    end

    -- Try to get additional data from ESX metadata or variables
    local dateOfBirth = xPlayer.get('dateofbirth') or nil
    local sex = xPlayer.get('sex') or nil
    local height = xPlayer.get('height') or nil
    local phoneNumber = xPlayer.get('phone_number') or nil

    -- Convert gender
    local gender = 'male'
    if sex then
        gender = Utils.ConvertGender(sex)
    end

    return {
        firstName = firstName,
        lastName = lastName,
        dateOfBirth = Utils.FormatDate(dateOfBirth),
        gender = gender,
        nationality = 'American',
        phone = phoneNumber,
        identifier = identifier,
        ssn = identifier,          -- Use identifier as SSN
        discordId = discordId,     -- Link to CAD account
        height = height,
    }
end

-- Sync a character to CDECAD
local function SyncCharacter(source, xPlayer, isNew)
    print('[CDECAD-SYNC] SyncCharacter called for source: ' .. tostring(source))

    if not xPlayer then
        print('[CDECAD-SYNC] ERROR: No player data to sync')
        return
    end

    local identifier = xPlayer.getIdentifier()
    print('[CDECAD-SYNC] Player identifier: ' .. tostring(identifier))
    print('[CDECAD-SYNC] Player name: ' .. tostring(xPlayer.getName()))

    -- Check Discord role eligibility
    if not CDECAD_Discord.ShouldSyncPlayer(source) then
        print('[CDECAD-SYNC] Player has excluded Discord role, skipping sync')
        return
    end

    local civilianData = BuildCivilianData(source, xPlayer)

    print('[CDECAD-SYNC] Syncing character: ' .. tostring(identifier) .. ' - ' .. tostring(civilianData.firstName) .. ' ' .. tostring(civilianData.lastName))
    print('[CDECAD-SYNC] Discord ID: ' .. tostring(civilianData.discordId))

    -- Check if already synced (we track by identifier)
    if syncedCivilians[identifier] and not isNew then
        print('[CDECAD-SYNC] Character already synced, updating...')
        CDECAD_API.UpdateCivilian(identifier, civilianData, function(success, data, statusCode)
            if success then
                print('[CDECAD-SYNC] Character updated successfully')
                if Config.Sync.OnCharacterUpdate then
                    TriggerClientEvent('cdecad-sync:client:notify', source, 'success', Config.Locale['sync_success'])
                end
            else
                print('[CDECAD-SYNC] Failed to update character: ' .. tostring(statusCode))
            end
        end)
    else
        print('[CDECAD-SYNC] Creating/syncing civilian in CAD...')
        CDECAD_API.CreateCivilian(civilianData, function(success, data, statusCode)
            print('[CDECAD-SYNC] CreateCivilian callback - success: ' .. tostring(success) .. ', statusCode: ' .. tostring(statusCode))
            if data then
                print('[CDECAD-SYNC] Response data: ' .. json.encode(data))
            end

            if success and data then
                if data.civilian then
                    syncedCivilians[identifier] = data.civilian._id
                elseif data._id then
                    syncedCivilians[identifier] = data._id
                else
                    syncedCivilians[identifier] = true
                end

                local action = data.action or 'synced'
                print('[CDECAD-SYNC] Character ' .. action .. ' successfully')
                TriggerClientEvent('cdecad-sync:client:notify', source, 'success', Config.Locale['sync_success'])

                -- Sync any existing vehicles
                if Config.Sync.SyncVehicles then
                    SyncPlayerVehicles(source, xPlayer)
                end
            else
                print('[CDECAD-SYNC] Failed to create character: ' .. tostring(statusCode))
                TriggerClientEvent('cdecad-sync:client:notify', source, 'error', Config.Locale['sync_failed'])
            end
        end)
    end
end

-- Sync player's vehicles from ESX database
SyncPlayerVehicles = function(source, xPlayer)
    local identifier = xPlayer.getIdentifier()

    Utils.Debug('Syncing vehicles for:', identifier)

    -- Query owned_vehicles table from ESX's MySQL database
    exports.oxmysql:execute('SELECT plate, vehicle FROM owned_vehicles WHERE owner = ?', { identifier }, function(vehicles)
        if not vehicles or #vehicles == 0 then
            Utils.Debug('No vehicles found for:', identifier)
            return
        end

        Utils.Debug('Found ' .. #vehicles .. ' vehicles for:', identifier)

        local vehicleList = {}
        for _, v in ipairs(vehicles) do
            -- ESX stores vehicle data as JSON in the 'vehicle' column
            -- This contains the vehicle properties including model hash, colors, etc.
            local spawnName = 'Unknown'
            local color = 'Unknown'

            if v.vehicle then
                local ok, vehProps = pcall(json.decode, v.vehicle)
                if ok and vehProps then
                    -- ESX vehicle properties structure
                    if vehProps.model then
                        -- Model is stored as a hash, try to get display name
                        spawnName = tostring(vehProps.model)
                    end

                    -- Try to resolve color from vehicle properties
                    if vehProps.color1 then
                        -- color1 can be a number (color index) or a table
                        color = VehicleUtils.ResolveColor(vehProps.color1)
                    elseif vehProps.colorPrimary then
                        color = VehicleUtils.ResolveColor(vehProps.colorPrimary)
                    end
                end
            end

            local make, model = VehicleUtils.ResolveMakeModel(spawnName)

            table.insert(vehicleList, {
                citizenid = identifier, -- Use 'citizenid' key for API compatibility
                plate = v.plate,
                model = model,
                make = make,
                color = color,
                year = os.date('%Y')
            })
        end

        -- Use bulk sync endpoint
        CDECAD_API.BulkSyncVehicles(identifier, vehicleList, function(success, data, statusCode)
            if success then
                Utils.Debug('Bulk vehicle sync successful for:', identifier)
                for _, v in ipairs(vehicleList) do
                    syncedVehicles[v.plate] = true
                end
            else
                print('[CDECAD-SYNC] Bulk vehicle sync failed for: ' .. identifier .. ' (HTTP ' .. tostring(statusCode) .. ')')
                if data then
                    print('[CDECAD-SYNC] Vehicle sync error response: ' .. json.encode(data))
                else
                    print('[CDECAD-SYNC] Vehicle sync error: no response data')
                end
            end
        end)
    end)
end

-- =============================================================================
-- ESX EVENT HANDLERS
-- =============================================================================

-- Player loaded (selected character)
RegisterNetEvent('esx:playerLoaded', function(playerId, xPlayer, isNew)
    local source = playerId or source
    print('[CDECAD-SYNC] esx:playerLoaded triggered for source: ' .. tostring(source))

    local player = GetPlayer(source)

    if not player then
        print('[CDECAD-SYNC] ERROR: Could not get player for source: ' .. tostring(source))
        return
    end

    print('[CDECAD-SYNC] Player found: ' .. tostring(player.getIdentifier()))

    if Config.Sync.OnCharacterLoad then
        -- Small delay to ensure everything is loaded
        SetTimeout(2000, function()
            local p = GetPlayer(source)
            if p then
                SyncCharacter(source, p, isNew or false)
            end
        end)
    end
end)

-- Also listen with AddEventHandler (for internal triggers)
AddEventHandler('esx:playerLoaded', function(playerId, xPlayer, isNew)
    local source = playerId or source
    print('[CDECAD-SYNC] AddEventHandler esx:playerLoaded triggered for source: ' .. tostring(source))

    local player = GetPlayer(source)

    if not player then
        print('[CDECAD-SYNC] ERROR: Could not get player for source: ' .. tostring(source))
        return
    end

    if Config.Sync.OnCharacterLoad then
        SetTimeout(2000, function()
            local p = GetPlayer(source)
            if p then
                SyncCharacter(source, p, isNew or false)
            end
        end)
    end
end)

-- Player dropped / logged out
AddEventHandler('esx:playerDropped', function(playerId, reason)
    Utils.Debug('Player dropped:', playerId)
    CDECAD_Discord.ClearCache(playerId)
end)

-- Job update
RegisterNetEvent('esx:setJob', function(playerId, job, lastJob)
    Utils.Debug('Job update for:', playerId, job.name)
    -- Civilians remain synced regardless of job
end)

-- =============================================================================
-- VEHICLE EVENT HANDLERS
-- =============================================================================

-- Vehicle purchased/registered
-- Hook into esx_vehicleshop if you want automatic registration
RegisterNetEvent('cdecad-sync:server:registerVehicle', function(vehicleData)
    local source = source
    local xPlayer = GetPlayer(source)

    if not xPlayer or not Config.Sync.SyncVehicles then return end

    local identifier = xPlayer.getIdentifier()

    Utils.Debug('Registering vehicle:', vehicleData.plate)

    local cadVehicleData = {
        plate = vehicleData.plate,
        ownerId = identifier,
        make = vehicleData.make or vehicleData.brand,
        model = vehicleData.model,
        color = vehicleData.color,
        year = vehicleData.year or os.date('%Y')
    }

    CDECAD_API.RegisterVehicle(cadVehicleData, function(success, data)
        if success then
            Utils.Debug('Vehicle registered in CAD')
            syncedVehicles[vehicleData.plate] = data.vehicleId
            TriggerClientEvent('cdecad-sync:client:notify', source, 'success', Config.Locale['vehicle_registered'])
        else
            Utils.Debug('Failed to register vehicle in CAD')
        end
    end)
end)

-- Vehicle reported stolen
RegisterNetEvent('cdecad-sync:server:reportStolen', function(plate, description)
    local source = source
    local xPlayer = GetPlayer(source)

    if not xPlayer or not Config.Sync.SyncVehicleStatus then return end

    Utils.Debug('Reporting vehicle stolen:', plate)

    CDECAD_API.GetVehicle(plate, function(success, vehicleData)
        if success and vehicleData then
            CDECAD_API.ReportVehicleStolen(vehicleData.id, true, description, function(stealSuccess)
                if stealSuccess then
                    TriggerClientEvent('cdecad-sync:client:notify', source, 'success', Config.Locale['vehicle_reported_stolen'])
                end
            end)
        end
    end)
end)

-- =============================================================================
-- 911 CALL HANDLER
-- =============================================================================

RegisterNetEvent('cdecad-sync:server:911call', function(callData)
    local source = source
    local xPlayer = GetPlayer(source)

    if not Config.Calls.Enabled then return end

    -- Rate limiting
    local canCall, remaining = Utils.CheckRateLimit('911_' .. source, Config.Calls.Cooldown)
    if not canCall then
        TriggerClientEvent('cdecad-sync:client:notify', source, 'error',
            Config.Locale['911_cooldown']:gsub('{time}', tostring(remaining)))
        return
    end

    local callerName = 'Anonymous'
    if xPlayer and not callData.anonymous then
        callerName = xPlayer.getName() or 'Unknown'
    end

    local cadCallData = {
        callType = callData.callType or 'Emergency Call',
        location = callData.location or callData.street or 'Unknown',
        callerName = callerName,
        coords = callData.coords,
        x = callData.coords and callData.coords.x,
        y = callData.coords and callData.coords.y,
        z = callData.coords and callData.coords.z,
        postal = callData.postal,
        isAnonymous = callData.anonymous,
        isNPC = false,
        reportType = 'Player'
    }

    CDECAD_API.Send911Call(cadCallData, function(success, data)
        if success then
            Utils.Debug('911 call sent successfully')
            if Config.Calls.NotifyOnSuccess then
                TriggerClientEvent('cdecad-sync:client:notify', source, 'success', Config.Locale['911_sent'])
            end
        else
            Utils.Debug('Failed to send 911 call')
            TriggerClientEvent('cdecad-sync:client:notify', source, 'error', Config.Locale['cad_offline'])
        end
    end)
end)

-- =============================================================================
-- NPC REPORTS (Automated witness reports)
-- =============================================================================

RegisterNetEvent('cdecad-sync:server:npcReport', function(reportData)
    local source = source

    if not Config.NPCReports.Enabled then return end

    -- Rate limiting based on location
    local locationKey = 'npc_' .. reportData.reportType .. '_' ..
        math.floor(reportData.coords.x / 100) .. '_' ..
        math.floor(reportData.coords.y / 100)

    local cooldown = Config.NPCReports[reportData.reportType] and
        Config.NPCReports[reportData.reportType].Cooldown or 60

    local canReport = Utils.CheckRateLimit(locationKey, cooldown)
    if not canReport then return end

    local cadCallData = {
        callType = reportData.callType or 'Suspicious Activity',
        location = reportData.location or reportData.street or 'Unknown',
        callerName = 'Anonymous Witness',
        coords = reportData.coords,
        x = reportData.coords.x,
        y = reportData.coords.y,
        z = reportData.coords.z,
        postal = reportData.postal,
        isAnonymous = true,
        isNPC = true,
        reportType = reportData.reportType or 'NPC'
    }

    CDECAD_API.Send911Call(cadCallData, function(success)
        if success then
            Utils.Debug('NPC report sent:', reportData.reportType)
        end
    end)
end)

-- =============================================================================
-- LOOKUP CALLBACKS
-- =============================================================================

-- Civilian lookup (for MDT integration)
lib.callback.register('cdecad-sync:server:lookupCivilian', function(source, identifier)
    local result = nil
    local completed = false

    CDECAD_API.GetCivilianBySSN(identifier, function(success, data)
        result = success and data or nil
        completed = true
    end)

    while not completed do
        Wait(10)
    end

    return result
end)

-- Vehicle lookup
lib.callback.register('cdecad-sync:server:lookupVehicle', function(source, plate)
    local result = nil
    local completed = false

    CDECAD_API.GetVehicle(plate, function(success, data)
        result = success and data or nil
        completed = true
    end)

    while not completed do
        Wait(10)
    end

    return result
end)

-- =============================================================================
-- EXPORTS
-- =============================================================================

-- Allow other resources to sync characters
exports('SyncCharacter', function(source)
    local xPlayer = GetPlayer(source)
    if xPlayer then
        SyncCharacter(source, xPlayer, false)
        return true
    end
    return false
end)

-- Allow other resources to send 911 calls
exports('Send911Call', function(callData)
    CDECAD_API.Send911Call(callData, function(success)
        Utils.Debug('Export 911 call result:', success)
    end)
end)

-- Get synced civilian ID
exports('GetSyncedCivilianId', function(identifier)
    return syncedCivilians[identifier]
end)

-- Manual sync trigger
exports('ForceSync', function(source)
    local xPlayer = GetPlayer(source)
    if xPlayer then
        SyncCharacter(source, xPlayer, true)
        return true
    end
    return false
end)

-- =============================================================================
-- STARTUP
-- =============================================================================

CreateThread(function()
    -- Wait for other resources
    Wait(5000)

    print('[CDECAD-SYNC] Using ESX framework')

    -- Health check
    CDECAD_API.HealthCheck(function(online, statusCode)
        if online then
            print('[CDECAD-SYNC] Connected to CDECAD API')
        else
            print('[CDECAD-SYNC] WARNING: Unable to connect to CDECAD API (Status: ' .. tostring(statusCode) .. ')')
        end
    end)

    -- Sync any already-online players
    if Config.Sync.OnCharacterLoad then
        local players = GetAllPlayers()
        for _, xPlayer in pairs(players) do
            local src = xPlayer.source
            if src then
                SyncCharacter(src, xPlayer, false)
            end
        end
    end
end)

print('[CDECAD-SYNC] Server script loaded (ESX)')
