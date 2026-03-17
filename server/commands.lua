--[[
    CDECAD Sync - Server Commands for ESX
    Admin and player commands for CAD integration
]]

-- Get ESX object
local ESX = exports['es_extended']:getSharedObject()

-- Load VehicleUtils module directly (shared_script globals not accessible in async callbacks)
local VehicleUtils = load(LoadResourceFile(GetCurrentResourceName(), 'shared/vehicles.lua'))()

-- Helper function to get player
local function GetPlayer(source)
    return ESX.GetPlayerFromId(source)
end

-- Helper function to get all players
local function GetAllPlayers()
    return ESX.GetExtendedPlayers()
end

-- =============================================================================
-- PLAYER COMMANDS
-- =============================================================================

-- 911 Emergency Call
if Config.Calls.Enabled then
    RegisterCommand(Config.Calls.Command, function(source, args)
        if source == 0 then return end -- Console

        local message = table.concat(args, ' ')
        if message == '' then
            TriggerClientEvent('cdecad-sync:client:notify', source, 'error', Config.Locale['911_invalid'])
            return
        end

        TriggerClientEvent('cdecad-sync:client:prepare911', source, message, false)
    end, false)

    -- Alternate command
    if Config.Calls.AlternateCommand then
        RegisterCommand(Config.Calls.AlternateCommand, function(source, args)
            if source == 0 then return end

            local message = table.concat(args, ' ')
            if message == '' then
                TriggerClientEvent('cdecad-sync:client:notify', source, 'error', Config.Locale['911_invalid'])
                return
            end

            TriggerClientEvent('cdecad-sync:client:prepare911', source, message, false)
        end, false)
    end

    -- Anonymous 911
    if Config.Calls.AllowAnonymous then
        RegisterCommand(Config.Calls.AnonymousCommand, function(source, args)
            if source == 0 then return end

            local message = table.concat(args, ' ')
            if message == '' then
                TriggerClientEvent('cdecad-sync:client:notify', source, 'error', Config.Locale['911_invalid'])
                return
            end

            TriggerClientEvent('cdecad-sync:client:prepare911', source, message, true)
        end, false)
    end
end

-- Report stolen vehicle
RegisterCommand('reportstolen', function(source, args)
    if source == 0 then return end

    local xPlayer = GetPlayer(source)
    if not xPlayer then return end

    local description = table.concat(args, ' ')

    TriggerClientEvent('cdecad-sync:client:reportStolenVehicle', source, description)
end, false)

-- =============================================================================
-- ADMIN COMMANDS
-- =============================================================================

-- Force sync a player's character
RegisterCommand('cadsync', function(source, args)
    local targetSource = source

    -- If admin with target ID
    if args[1] then
        targetSource = tonumber(args[1])
    end

    if targetSource == 0 then
        print('[CDECAD-SYNC] Cannot sync console')
        return
    end

    local xPlayer = GetPlayer(targetSource)
    if not xPlayer then
        if source > 0 then
            TriggerClientEvent('cdecad-sync:client:notify', source, 'error', 'Player not found')
        else
            print('[CDECAD-SYNC] Player not found: ' .. tostring(targetSource))
        end
        return
    end

    exports[GetCurrentResourceName()]:ForceSync(targetSource)

    if source > 0 then
        TriggerClientEvent('cdecad-sync:client:notify', source, 'success', 'Syncing player to CAD...')
    else
        print('[CDECAD-SYNC] Syncing player ' .. targetSource .. ' to CAD')
    end
end, true) -- Restricted to admins

-- Check CAD connection status
RegisterCommand('cadstatus', function(source, args)
    CDECAD_API.HealthCheck(function(online, statusCode)
        local message = online
            and 'CAD is online (Status: ' .. tostring(statusCode) .. ')'
            or 'CAD is offline (Status: ' .. tostring(statusCode) .. ')'

        if source > 0 then
            TriggerClientEvent('cdecad-sync:client:notify', source, online and 'success' or 'error', message)
        else
            print('[CDECAD-SYNC] ' .. message)
        end
    end)
end, true)

-- Lookup civilian in CAD
RegisterCommand('cadlookup', function(source, args)
    if not args[1] then
        if source > 0 then
            TriggerClientEvent('cdecad-sync:client:notify', source, 'error', 'Usage: /cadlookup [identifier or plate]')
        else
            print('[CDECAD-SYNC] Usage: /cadlookup [identifier or plate]')
        end
        return
    end

    local searchTerm = args[1]:upper()

    -- Try vehicle lookup first (if it looks like a plate)
    if #searchTerm <= 8 then
        CDECAD_API.GetVehicle(searchTerm, function(success, data)
            if success and data then
                local info = string.format('Vehicle: %s %s %s | Owner: %s | Stolen: %s',
                    data.year or '?',
                    data.color or '?',
                    data.model or '?',
                    data.owner or 'Unknown',
                    data.stolen and 'YES' or 'No'
                )

                if source > 0 then
                    TriggerClientEvent('cdecad-sync:client:notify', source, 'info', info)
                else
                    print('[CDECAD-SYNC] ' .. info)
                end
            else
                -- Try civilian lookup
                CDECAD_API.GetCivilianBySSN(searchTerm, function(civSuccess, civData)
                    if civSuccess and civData then
                        local info = string.format('Civilian: %s | DOB: %s | Phone: %s',
                            civData.name or 'Unknown',
                            civData.dob or '?',
                            civData.phone or '?'
                        )

                        if source > 0 then
                            TriggerClientEvent('cdecad-sync:client:notify', source, 'info', info)
                        else
                            print('[CDECAD-SYNC] ' .. info)
                        end
                    else
                        if source > 0 then
                            TriggerClientEvent('cdecad-sync:client:notify', source, 'error', 'No records found')
                        else
                            print('[CDECAD-SYNC] No records found for: ' .. searchTerm)
                        end
                    end
                end)
            end
        end)
    end
end, true)

-- Sync ALL characters from ESX database to CAD (not just online players)
RegisterCommand('cadsyncall', function(source, args)
    local msg = 'Querying all characters from database...'
    if source > 0 then
        TriggerClientEvent('cdecad-sync:client:notify', source, 'info', msg)
    else
        print('[CDECAD-SYNC] ' .. msg)
    end

    -- Build a lookup of online players' Discord IDs by identifier
    local onlineDiscordIds = {}
    local onlinePlayers = GetAllPlayers()
    for _, xPlayer in pairs(onlinePlayers) do
        local src = xPlayer.source
        if src then
            local identifier = xPlayer.getIdentifier()
            local identifiers = GetPlayerIdentifiers(src)
            for _, id in ipairs(identifiers) do
                if string.find(id, 'discord:') then
                    onlineDiscordIds[identifier] = id:gsub('discord:', '')
                    break
                end
            end
        end
    end

    -- Query ALL characters from ESX's users table
    -- ESX Legacy stores firstname, lastname, dateofbirth, sex directly in columns
    exports.oxmysql:execute('SELECT identifier, firstname, lastname, dateofbirth, sex, phone_number FROM users', {}, function(rows)
        if not rows or #rows == 0 then
            local errMsg = 'No characters found in database'
            if source > 0 then
                TriggerClientEvent('cdecad-sync:client:notify', source, 'error', errMsg)
            else
                print('[CDECAD-SYNC] ' .. errMsg)
            end
            return
        end

        local characterList = {}
        for _, row in ipairs(rows) do
            if row.identifier then
                local gender = 'male'
                if row.sex and (row.sex == 'f' or row.sex == 'female') then
                    gender = 'female'
                end

                table.insert(characterList, {
                    firstName = row.firstname or 'Unknown',
                    lastName = row.lastname or '',
                    dateOfBirth = Utils.FormatDate(row.dateofbirth),
                    gender = gender,
                    nationality = 'American',
                    phone = row.phone_number,
                    ssn = row.identifier,
                    discordId = onlineDiscordIds[row.identifier] -- nil for offline players
                })
            end
        end

        local infoMsg = 'Found ' .. #characterList .. ' characters. Syncing to CAD...'
        if source > 0 then
            TriggerClientEvent('cdecad-sync:client:notify', source, 'info', infoMsg)
        else
            print('[CDECAD-SYNC] ' .. infoMsg)
        end

        CDECAD_API.ForceSyncAllCharacters(characterList, function(success, data)
            local resultMsg
            if success then
                local stats = ''
                if data then
                    stats = string.format(' (Created: %s, Updated: %s, Skipped: %s)',
                        tostring(data.created or 0),
                        tostring(data.updated or 0),
                        tostring(data.skipped or 0)
                    )
                end
                resultMsg = 'Character sync complete!' .. stats
            else
                resultMsg = 'Character sync failed. Check server console.'
            end

            if source > 0 then
                TriggerClientEvent('cdecad-sync:client:notify', source, success and 'success' or 'error', resultMsg)
            else
                print('[CDECAD-SYNC] ' .. resultMsg)
            end
        end)
    end)
end, true)

-- Force sync ALL vehicles from ESX database to CAD
RegisterCommand('cadforcesyncvehicles', function(source, args)
    local message = 'Querying all player vehicles from database...'
    if source > 0 then
        TriggerClientEvent('cdecad-sync:client:notify', source, 'info', message)
    else
        print('[CDECAD-SYNC] ' .. message)
    end

    -- Query ALL vehicles from ESX's owned_vehicles table
    exports.oxmysql:execute('SELECT owner, plate, vehicle FROM owned_vehicles', {}, function(vehicles)
        if not vehicles or #vehicles == 0 then
            local msg = 'No vehicles found in database'
            if source > 0 then
                TriggerClientEvent('cdecad-sync:client:notify', source, 'error', msg)
            else
                print('[CDECAD-SYNC] ' .. msg)
            end
            return
        end

        local vehicleList = {}
        for _, v in ipairs(vehicles) do
            local spawnName = 'Unknown'
            local color = 'Unknown'

            -- ESX stores vehicle properties as JSON in the 'vehicle' column
            if v.vehicle then
                local ok, vehProps = pcall(json.decode, v.vehicle)
                if ok and vehProps then
                    if vehProps.model then
                        spawnName = tostring(vehProps.model)
                    end
                    if vehProps.color1 then
                        color = VehicleUtils.ResolveColor(vehProps.color1)
                    elseif vehProps.colorPrimary then
                        color = VehicleUtils.ResolveColor(vehProps.colorPrimary)
                    end
                end
            end

            local make, model = VehicleUtils.ResolveMakeModel(spawnName)

            table.insert(vehicleList, {
                citizenid = v.owner, -- Use 'citizenid' key for API compatibility
                plate = v.plate,
                model = model,
                make = make,
                color = color,
                year = os.date('%Y')
            })
        end

        local msg = 'Found ' .. #vehicleList .. ' vehicles. Syncing to CAD...'
        if source > 0 then
            TriggerClientEvent('cdecad-sync:client:notify', source, 'info', msg)
        else
            print('[CDECAD-SYNC] ' .. msg)
        end

        CDECAD_API.ForceSyncAllVehicles(vehicleList, function(success, data)
            local resultMsg
            if success then
                local stats = ''
                if data then
                    stats = string.format(' (Created: %s, Updated: %s, Skipped: %s)',
                        tostring(data.created or 0),
                        tostring(data.updated or 0),
                        tostring(data.skipped or 0)
                    )
                end
                resultMsg = 'Vehicle force sync complete!' .. stats
            else
                resultMsg = 'Vehicle force sync failed. Check server console.'
            end

            if source > 0 then
                TriggerClientEvent('cdecad-sync:client:notify', source, success and 'success' or 'error', resultMsg)
            else
                print('[CDECAD-SYNC] ' .. resultMsg)
            end
        end)
    end)
end, true) -- Restricted to admins

-- Clear Discord role cache
RegisterCommand('cadclearcache', function(source, args)
    CDECAD_Discord.ClearAllCache()

    local message = 'Discord role cache cleared'

    if source > 0 then
        TriggerClientEvent('cdecad-sync:client:notify', source, 'success', message)
    else
        print('[CDECAD-SYNC] ' .. message)
    end
end, true)

-- =============================================================================
-- SUGGESTIONS (Tab completion)
-- =============================================================================

if Config.Calls.Enabled then
    TriggerEvent('chat:addSuggestion', '/' .. Config.Calls.Command, '911 Emergency Call', {
        { name = 'message', help = 'Describe your emergency' }
    })

    if Config.Calls.AllowAnonymous then
        TriggerEvent('chat:addSuggestion', '/' .. Config.Calls.AnonymousCommand, 'Anonymous 911 Call', {
            { name = 'message', help = 'Describe your emergency (anonymous)' }
        })
    end
end

TriggerEvent('chat:addSuggestion', '/reportstolen', 'Report your vehicle as stolen', {
    { name = 'description', help = 'Where/when was it stolen?' }
})

TriggerEvent('chat:addSuggestion', '/cadforcesyncvehicles', 'Force sync all ESX vehicles to CAD (Admin)', {})

print('[CDECAD-SYNC] Commands registered (ESX)')
