--[[
    CDECAD Sync - Discord Integration
    Handles Discord role checking to determine sync eligibility
]]

local Discord = {}

-- Cache for player roles to reduce API calls
local roleCache = {}
local CACHE_DURATION = 300 -- 5 minutes

-- Check if Badger_Discord_API is available
local function HasBadgerAPI()
    return GetResourceState('Badger_Discord_API') == 'started'
end

-- Get player's Discord roles using Badger_Discord_API
local function GetRolesFromBadger(source)
    if not HasBadgerAPI() then
        return nil
    end

    local roles = exports.Badger_Discord_API:GetDiscordRoles(source)
    return roles
end

-- Get player's Discord ID
function Discord.GetDiscordId(source)
    local identifiers = GetPlayerIdentifiers(source)
    for _, id in ipairs(identifiers) do
        if string.find(id, 'discord:') then
            return id:gsub('discord:', '')
        end
    end
    return nil
end

-- Get player's Discord roles
function Discord.GetRoles(source)
    if not Config.Discord.Enabled then
        return {}
    end

    -- Check cache first
    local discordId = Discord.GetDiscordId(source)
    if discordId and roleCache[discordId] then
        local cached = roleCache[discordId]
        if os.time() - cached.time < CACHE_DURATION then
            return cached.roles
        end
    end

    local roles = {}

    if Config.Discord.UseBadgerAPI and HasBadgerAPI() then
        roles = GetRolesFromBadger(source) or {}
    end

    -- Cache the result
    if discordId then
        roleCache[discordId] = {
            roles = roles,
            time = os.time()
        }
    end

    return roles
end

-- Check if player has a specific role (by ID or name)
function Discord.HasRole(source, roleIdOrName)
    if not Config.Discord.Enabled then
        return false
    end

    local roles = Discord.GetRoles(source)

    for _, roleId in ipairs(roles) do
        -- Check by ID
        if tostring(roleId) == tostring(roleIdOrName) then
            return true
        end

        -- Check by name using Badger API
        if Config.Discord.UseBadgerAPI and HasBadgerAPI() then
            local roleName = exports.Badger_Discord_API:GetRoleNameFromRoleId(roleId)
            if roleName and roleName:lower() == tostring(roleIdOrName):lower() then
                return true
            end
        end
    end

    return false
end

-- Check if player has any of the excluded roles
function Discord.HasExcludedRole(source)
    if not Config.Discord.Enabled then
        return false
    end

    -- Check excluded role IDs
    for _, roleId in ipairs(Config.Discord.ExcludedRoleIds or {}) do
        if Discord.HasRole(source, roleId) then
            Utils.Debug('Player has excluded role ID:', roleId)
            return true
        end
    end

    -- Check excluded role names
    if Config.Discord.UseBadgerAPI and HasBadgerAPI() then
        for _, roleName in ipairs(Config.Discord.ExcludedRoles or {}) do
            if Discord.HasRole(source, roleName) then
                Utils.Debug('Player has excluded role:', roleName)
                return true
            end
        end
    end

    return false
end

-- Check if player has any force-sync roles
function Discord.HasForceSyncRole(source)
    if not Config.Discord.Enabled then
        return true -- If Discord not enabled, always sync
    end

    if Config.Discord.UseBadgerAPI and HasBadgerAPI() then
        for _, roleName in ipairs(Config.Discord.ForceSyncRoles or {}) do
            if Discord.HasRole(source, roleName) then
                Utils.Debug('Player has force-sync role:', roleName)
                return true
            end
        end
    end

    return false
end

-- Determine if player should be synced to CAD
function Discord.ShouldSyncPlayer(source)
    if not Config.Discord.Enabled then
        return true -- If Discord not enabled, sync everyone
    end

    -- If player has force-sync role, always sync
    if Discord.HasForceSyncRole(source) then
        return true
    end

    -- If player has excluded role, don't sync
    if Discord.HasExcludedRole(source) then
        return false
    end

    -- Default: sync the player
    return true
end

-- Get player's Discord name
function Discord.GetDiscordName(source)
    if not Config.Discord.Enabled then
        return nil
    end

    if Config.Discord.UseBadgerAPI and HasBadgerAPI() then
        local name = exports.Badger_Discord_API:GetDiscordName(source)
        return name
    end

    return nil
end

-- Get player's Discord avatar URL
function Discord.GetDiscordAvatar(source)
    if not Config.Discord.Enabled then
        return nil
    end

    if Config.Discord.UseBadgerAPI and HasBadgerAPI() then
        local avatar = exports.Badger_Discord_API:GetDiscordAvatar(source)
        return avatar
    end

    return nil
end

-- Clear role cache for a player
function Discord.ClearCache(source)
    local discordId = Discord.GetDiscordId(source)
    if discordId then
        roleCache[discordId] = nil
    end
end

-- Clear all role cache
function Discord.ClearAllCache()
    roleCache = {}
end

-- Export the Discord module
_G.CDECAD_Discord = Discord

return Discord
