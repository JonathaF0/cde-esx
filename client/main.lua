--[[
    CDECAD Sync - Main Client Script for ESX
    Handles client-side notifications and data gathering
]]

-- Get ESX object
local ESX = exports['es_extended']:getSharedObject()

local PlayerData = {}
local isLoggedIn = false

-- =============================================================================
-- PLAYER DATA MANAGEMENT
-- =============================================================================

-- Get player data
local function GetPlayerData()
    return ESX.GetPlayerData()
end

-- Update local player data cache
local function UpdatePlayerData()
    PlayerData = GetPlayerData() or {}
    isLoggedIn = PlayerData.identifier ~= nil
end

-- =============================================================================
-- EVENT HANDLERS
-- =============================================================================

-- Player loaded
RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    PlayerData = xPlayer
    isLoggedIn = true
    Utils.Debug('Client: Player loaded')
end)

-- Player logged out
RegisterNetEvent('esx:onPlayerLogout', function()
    PlayerData = {}
    isLoggedIn = false
    Utils.Debug('Client: Player logged out')
end)

-- Player data updated (job change, etc.)
RegisterNetEvent('esx:setJob', function(job)
    PlayerData.job = job
end)

-- =============================================================================
-- NOTIFICATIONS
-- =============================================================================

RegisterNetEvent('cdecad-sync:client:notify', function(type, message)
    if Config.Notifications.UseOxLib then
        lib.notify({
            title = 'CDECAD',
            description = message,
            type = type,
            duration = Config.Notifications.Duration,
            position = Config.Notifications.Position
        })
    else
        -- ESX native notifications
        ESX.ShowNotification(message)
    end
end)

-- =============================================================================
-- POSTAL CODE FUNCTIONS
-- =============================================================================

-- Get postal code from configured resource
function GetPostalCode()
    if not Config.Postal or not Config.Postal.Enabled then
        return nil
    end

    local postal = nil
    local resource = Config.Postal.Resource or 'nearest-postal'

    if resource == 'nearest-postal' then
        local success, result = pcall(function()
            return exports['nearest-postal']:getPostal()
        end)
        if success and result then
            postal = result
        end
    elseif resource == 'npostal' then
        local success, result = pcall(function()
            return exports.npostal:npostal()
        end)
        if success and result then
            postal = result
        end
    elseif resource == 'custom' then
        local exportName = Config.Postal.CustomExport
        local funcName = Config.Postal.CustomFunction or 'getPostal'

        if exportName then
            local success, result = pcall(function()
                return exports[exportName][funcName]()
            end)
            if success and result then
                postal = result
            end
        end
    end

    if postal then
        Utils.Debug('Got postal code:', postal)
        return tostring(postal)
    else
        Utils.Debug('No postal code available')
        return Config.Postal.FallbackText
    end
end

-- =============================================================================
-- LOCATION HELPERS
-- =============================================================================

-- Get current street name
function GetCurrentStreetName()
    local coords = GetEntityCoords(PlayerPedId())
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local streetName = GetStreetNameFromHashKey(streetHash)
    local crossingName = GetStreetNameFromHashKey(crossingHash)

    if crossingName and crossingName ~= '' then
        return streetName .. ' & ' .. crossingName
    end
    return streetName
end

-- Get current zone name
function GetCurrentZoneName()
    local coords = GetEntityCoords(PlayerPedId())
    return GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
end

-- Format location string with postal
function FormatLocationString(street, zone, postal)
    local format

    if postal and Config.Postal.IncludeInLocation then
        format = Config.Postal.LocationFormat or '{street}, {zone} (Postal: {postal})'
        format = format:gsub('{street}', street or 'Unknown')
        format = format:gsub('{zone}', zone or 'Unknown')
        format = format:gsub('{postal}', postal)
    else
        format = Config.Postal.LocationFormatNoPostal or '{street}, {zone}'
        format = format:gsub('{street}', street or 'Unknown')
        format = format:gsub('{zone}', zone or 'Unknown')
    end

    return format
end

-- Get location info for 911 calls
function GetLocationInfo()
    local coords = GetEntityCoords(PlayerPedId())
    local street = GetCurrentStreetName()
    local zone = GetCurrentZoneName()
    local postal = GetPostalCode()

    local locationString = FormatLocationString(street, zone, postal)

    return {
        street = street,
        zone = zone,
        postal = postal,
        location = locationString,
        coords = coords,
        x = coords.x,
        y = coords.y,
        z = coords.z
    }
end

-- Get current vehicle info
function GetCurrentVehicle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then
        return nil
    end

    local plate = GetVehicleNumberPlateText(vehicle)
    local model = GetEntityModel(vehicle)
    local displayName = GetDisplayNameFromVehicleModel(model)

    return {
        vehicle = vehicle,
        plate = plate:gsub('%s+', ''),
        model = displayName,
        class = GetVehicleClass(vehicle)
    }
end

-- =============================================================================
-- 911 CALL PREPARATION
-- =============================================================================

-- Prepare 911 call data
function Prepare911CallData(callType, anonymous)
    local location = GetLocationInfo()

    return {
        callType = callType,
        location = location.location,
        street = location.street,
        zone = location.zone,
        postal = location.postal,
        coords = location.coords,
        anonymous = anonymous or false
    }
end

-- =============================================================================
-- EXPORTS
-- =============================================================================

exports('GetLocationInfo', GetLocationInfo)
exports('GetCurrentVehicle', GetCurrentVehicle)
exports('Prepare911CallData', Prepare911CallData)
exports('GetPostalCode', GetPostalCode)

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

CreateThread(function()
    -- Wait for ESX to be ready
    while not ESX do
        Wait(100)
    end

    -- Wait for player to be fully loaded
    while not ESX.GetPlayerData().identifier do
        Wait(500)
    end

    UpdatePlayerData()

    -- Test postal on load
    if Config.Postal and Config.Postal.Enabled then
        Wait(2000)
        local testPostal = GetPostalCode()
        if testPostal then
            Utils.Debug('Postal integration working. Current postal:', testPostal)
        else
            Utils.Debug('Postal integration enabled but no postal returned. Check Config.Postal.Resource setting.')
        end
    end

    Utils.Debug('Client: Initialized (ESX)')
end)

print('[CDECAD-SYNC] Client script loaded (ESX)')
