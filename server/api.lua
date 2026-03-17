--[[
    CDECAD Sync - API Handler
    Handles all HTTP requests to the CDECAD backend
]]

local API = {}

-- HTTP request queue for rate limiting
local requestQueue = {}
local isProcessing = false
local lastRequestTime = 0
local MIN_REQUEST_INTERVAL = 100 -- ms between requests

-- Make an HTTP request to CDECAD
local function MakeRequest(method, endpoint, data, callback)
    local url = Config.API_URL .. endpoint

    local headers = {
        ['Content-Type'] = 'application/json',
        ['x-api-key'] = Config.API_KEY
    }

    if Config.Debug.LogRequests then
        print('[CDECAD-API] ' .. method .. ' ' .. url)
        if data then
            print('[CDECAD-API] Body: ' .. json.encode(data))
        end
    end

    local requestCallback = function(statusCode, responseText, responseHeaders)
        if Config.Debug.LogResponses then
            print('[CDECAD-API] Response ' .. tostring(statusCode) .. ': ' .. tostring(responseText))
        end

        local success = statusCode >= 200 and statusCode < 300
        local responseData = nil

        if responseText and responseText ~= '' then
            local ok, decoded = pcall(json.decode, responseText)
            if ok then
                responseData = decoded
            end
        end

        if callback then
            callback(success, responseData, statusCode)
        end
    end

    if method == 'GET' then
        PerformHttpRequest(url, requestCallback, 'GET', '', headers)
    else
        local body = data and json.encode(data) or ''
        PerformHttpRequest(url, requestCallback, method, body, headers)
    end
end

-- Queue a request (helps with rate limiting)
local function QueueRequest(method, endpoint, data, callback)
    table.insert(requestQueue, {
        method = method,
        endpoint = endpoint,
        data = data,
        callback = callback
    })

    if not isProcessing then
        ProcessQueue()
    end
end

-- Process the request queue
function ProcessQueue()
    if #requestQueue == 0 then
        isProcessing = false
        return
    end

    isProcessing = true
    local now = GetGameTimer()
    local waitTime = MIN_REQUEST_INTERVAL - (now - lastRequestTime)

    if waitTime > 0 then
        SetTimeout(waitTime, ProcessQueue)
        return
    end

    local request = table.remove(requestQueue, 1)
    lastRequestTime = GetGameTimer()

    MakeRequest(request.method, request.endpoint, request.data, function(success, data, statusCode)
        if request.callback then
            request.callback(success, data, statusCode)
        end
        ProcessQueue()
    end)
end

-- =============================================================================
-- CIVILIAN ENDPOINTS
-- =============================================================================

-- Create a new civilian in CDECAD (uses FiveM-specific endpoint)
function API.CreateCivilian(civilianData, callback)
    Utils.Debug('Creating civilian:', civilianData.firstName, civilianData.lastName)

    local payload = {
        firstName = civilianData.firstName,
        lastName = civilianData.lastName,
        dateOfBirth = civilianData.dateOfBirth,
        gender = civilianData.gender,
        nationality = civilianData.nationality or 'American',
        phone = civilianData.phone,
        ssn = civilianData.ssn or civilianData.identifier,
        communityId = Config.COMMUNITY_ID,
        discordId = civilianData.discordId,
        -- Optional fields
        race = civilianData.race,
        hairColor = civilianData.hairColor,
        eyeColor = civilianData.eyeColor,
        height = civilianData.height,
        weight = civilianData.weight,
        address = civilianData.address,
        mugshotUrl = civilianData.mugshotUrl,
        placeOfBirth = civilianData.placeOfBirth
    }

    -- Use the FiveM-specific sync endpoint (API key auth, not user auth)
    QueueRequest('POST', '/civilian/fivem-sync-character', payload, callback)
end

-- Update an existing civilian (uses FiveM-specific endpoint)
function API.UpdateCivilian(civilianId, updateData, callback)
    Utils.Debug('Updating civilian:', civilianId)
    updateData.communityId = Config.COMMUNITY_ID
    QueueRequest('PUT', '/civilian/fivem-update-character/' .. civilianId, updateData, callback)
end

-- Get civilian by ID
function API.GetCivilian(civilianId, callback)
    MakeRequest('GET', '/civilian/' .. civilianId, nil, callback)
end

-- Get civilian by SSN/Identifier (for FiveM lookups)
function API.GetCivilianBySSN(ssn, callback)
    MakeRequest('GET', '/civilian/fivem-civilian/' .. ssn .. '?communityId=' .. Config.COMMUNITY_ID, nil, callback)
end

-- Delete a civilian (uses FiveM-specific endpoint)
function API.DeleteCivilian(identifier, callback)
    Utils.Debug('Deleting civilian:', identifier)
    QueueRequest('DELETE', '/civilian/fivem-delete-character/' .. identifier .. '?communityId=' .. Config.COMMUNITY_ID, nil, callback)
end

-- =============================================================================
-- VEHICLE ENDPOINTS
-- =============================================================================

-- Register a vehicle
function API.RegisterVehicle(vehicleData, callback)
    Utils.Debug('Registering vehicle:', vehicleData.plate)

    local payload = {
        plate = vehicleData.plate,
        ownerId = vehicleData.ownerId,
        communityId = Config.COMMUNITY_ID,
        make = vehicleData.make or 'Unknown',
        model = vehicleData.model,
        color = vehicleData.color or 'Unknown',
        year = vehicleData.year or os.date('%Y')
    }

    QueueRequest('POST', '/civilian/fivem-register-vehicle', payload, callback)
end

-- Get vehicle by plate
function API.GetVehicle(plate, callback)
    local encodedPlate = plate:gsub(' ', '%%20')
    MakeRequest('GET', '/civilian/fivem-vehicle/' .. encodedPlate .. '?communityId=' .. Config.COMMUNITY_ID, nil, callback)
end

-- Report vehicle stolen
function API.ReportVehicleStolen(vehicleId, stolen, description, callback)
    Utils.Debug('Reporting vehicle stolen:', vehicleId, stolen)

    local payload = {
        stolen = stolen,
        stolenDescription = description,
        stolenDate = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        communityId = Config.COMMUNITY_ID
    }

    QueueRequest('PUT', '/civilian/vehicle/' .. vehicleId .. '/stolen', payload, callback)
end

-- Bulk sync vehicles for a single player
function API.BulkSyncVehicles(identifier, vehicles, callback)
    Utils.Debug('Bulk syncing ' .. #vehicles .. ' vehicles for:', identifier)

    local payload = {
        communityId = Config.COMMUNITY_ID,
        ownerId = identifier,
        vehicles = vehicles
    }

    QueueRequest('POST', '/civilian/fivem-sync-vehicles', payload, callback)
end

-- Force sync ALL characters from the ESX database
function API.ForceSyncAllCharacters(characters, callback)
    Utils.Debug('Force syncing ' .. #characters .. ' characters to CAD')

    local payload = {
        communityId = Config.COMMUNITY_ID,
        characters = characters
    }

    MakeRequest('POST', '/civilian/fivem-force-sync-characters', payload, callback)
end

-- Force sync ALL vehicles from the ESX database
function API.ForceSyncAllVehicles(vehicles, callback)
    Utils.Debug('Force syncing ' .. #vehicles .. ' vehicles to CAD')

    local payload = {
        communityId = Config.COMMUNITY_ID,
        vehicles = vehicles
    }

    MakeRequest('POST', '/civilian/fivem-force-sync-vehicles', payload, callback)
end

-- =============================================================================
-- 911 CALL ENDPOINTS
-- =============================================================================

-- Send a 911 call
function API.Send911Call(callData, callback)
    Utils.Debug('Sending 911 call:', callData.callType)

    local payload = {
        callType = callData.callType or 'Emergency',
        location = callData.location or 'Unknown',
        callerName = callData.callerName or 'Anonymous',
        communityId = Config.COMMUNITY_ID,
        coords = callData.coords,
        x = callData.x,
        y = callData.y,
        z = callData.z,
        postal = callData.postal,
        isAnonymous = callData.isAnonymous,
        isNPC = callData.isNPC,
        reportType = callData.reportType
    }

    QueueRequest('POST', '/civilian/fivem-911-call', payload, callback)
end

-- Get active 911 markers (for live map)
function API.Get911Markers(callback)
    MakeRequest('GET', '/civilian/911-markers/' .. Config.COMMUNITY_ID, nil, callback)
end

-- =============================================================================
-- LICENSE ENDPOINTS
-- =============================================================================

-- Update license status
function API.UpdateLicense(civilianId, licenseType, status, callback)
    Utils.Debug('Updating license:', civilianId, licenseType, status)

    local payload = {
        licenseType = licenseType,
        status = status
    }

    QueueRequest('PUT', '/civilian/' .. civilianId .. '/license', payload, callback)
end

-- =============================================================================
-- MISSING PERSON / STOLEN VEHICLE ALERTS
-- =============================================================================

-- Report missing person
function API.ReportMissing(civilianId, missingData, callback)
    Utils.Debug('Reporting missing:', civilianId)

    local payload = {
        missingPerson = true,
        missingDate = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        lastSeenLocation = missingData.lastSeenLocation,
        description = missingData.description
    }

    QueueRequest('PUT', '/civilian/' .. civilianId .. '/missing', payload, callback)
end

-- Get stolen vehicles in community
function API.GetStolenVehicles(callback)
    MakeRequest('GET', '/civilian/stolen-vehicles/' .. Config.COMMUNITY_ID, nil, callback)
end

-- Get missing persons in community
function API.GetMissingPersons(callback)
    MakeRequest('GET', '/civilian/missing-persons/' .. Config.COMMUNITY_ID, nil, callback)
end

-- =============================================================================
-- HEALTH CHECK
-- =============================================================================

-- Check if CAD is online
function API.HealthCheck(callback)
    PerformHttpRequest(Config.API_URL:gsub('/api', ''), function(statusCode, responseText, responseHeaders)
        local online = statusCode and statusCode >= 200 and statusCode < 500
        if callback then
            callback(online, statusCode)
        end
    end, 'GET', '', {})
end

-- Export the API module
_G.CDECAD_API = API

return API
