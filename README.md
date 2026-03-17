# CDECAD-Sync for ESX

A comprehensive FiveM resource that automatically syncs ESX character data to your CDECAD system.

## Features

- **Automatic Character Sync**: Characters are automatically synced to CDECAD when created/loaded
- **Discord Account Linking**: Links FiveM characters to users' CAD accounts via Discord ID
- **Discord Role Integration**: Filter syncing based on Discord roles (exclude LEO/EMS characters)
- **Vehicle Registration**: Automatically register vehicles when purchased
- **911 Call System**: Full 911 call integration with coordinates and postal codes
- **NPC Witness Reports**: Automated crime reports when NPCs witness crimes
- **Admin Commands**: Full admin tools for manual syncing and lookups

## Requirements

- [ESX Legacy (es_extended)](https://github.com/esx-framework/esx_core)
- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- [Badger_Discord_API](https://github.com/JaredScar/Badger_Discord_API) (Optional, recommended)
- [NearestPostal](https://forum.cfx.re/t/release-nearest-postal-script/293511) (Optional, recommended)

## Installation

1. Download and extract to your resources folder as `cdecad-sync-esx`
2. Configure `shared/config.lua` with your API settings
3. Add `ensure cdecad-sync-esx` to your server.cfg (after es_extended and ox_lib)
4. Restart your server

## Configuration

Edit `shared/config.lua`:

```lua
-- API Settings
Config.API_URL = 'https://your-cdecad-instance.com/api'
Config.API_KEY = 'your-fivem-api-key'
Config.COMMUNITY_ID = 'your-discord-guild-id'  -- Your Discord SERVER ID

-- Sync Settings
Config.Sync.OnCharacterLoad = true      -- Sync when player loads character
Config.Sync.OnCharacterCreate = true    -- Sync new characters
Config.Sync.SyncVehicles = true         -- Sync vehicle registrations
```

## Commands

### Player Commands
| Command | Description |
|---------|-------------|
| `/911 [message]` | Send emergency call |
| `/call911` | Interactive 911 call |
| `/911anon [message]` | Anonymous emergency call |
| `/reportstolen` | Report current vehicle stolen |
| `/panic` | Send panic alert (if enabled) |

### Admin Commands
| Command | Description |
|---------|-------------|
| `/cadsync [playerid]` | Force sync a player |
| `/cadsyncall` | Sync all characters from database |
| `/cadforcesyncvehicles` | Force sync all vehicles from database |
| `/cadstatus` | Check API connection status |
| `/cadlookup [id/plate]` | Lookup civilian or vehicle |
| `/cadclearcache` | Clear Discord role cache |

## ESX Player Data Structure

This resource uses the standard ESX player data:

```lua
xPlayer.getIdentifier()    -- Unique player identifier (license:xxx)
xPlayer.getName()          -- Player RP name (from esx_identity)
xPlayer.getJob()           -- Job object { name, label, grade, grade_name, ... }
xPlayer.getAccounts()      -- Account balances (money, bank, black_money)
xPlayer.get('dateofbirth') -- Date of birth (from esx_identity)
xPlayer.get('sex')         -- Gender ('m' or 'f')
xPlayer.get('height')      -- Height
```

### ESX Database Tables Used

| Table | Purpose |
|-------|---------|
| `users` | Character data (identifier, firstname, lastname, dateofbirth, sex) |
| `owned_vehicles` | Vehicle ownership (owner, plate, vehicle JSON) |

## Exports

```lua
-- Sync a player's character
exports['cdecad-sync-esx']:SyncCharacter(source)

-- Send a 911 call
exports['cdecad-sync-esx']:Send911Call(callData)

-- Get synced civilian ID
exports['cdecad-sync-esx']:GetSyncedCivilianId(identifier)

-- Force sync
exports['cdecad-sync-esx']:ForceSync(source)
```

## Key Differences from QBCore Version

| Feature | QBCore | ESX |
|---------|--------|-----|
| Player ID | `citizenid` | `identifier` (license:xxx) |
| Character Data | `charinfo` JSON | `users` table columns |
| Gender | `0`/`1` (number) | `'m'`/`'f'` (string) |
| Vehicle Table | `player_vehicles` | `owned_vehicles` |
| Vehicle Data | `mods` JSON | `vehicle` JSON (properties) |
| Player Object | `QBCore.Functions.GetPlayer(src)` | `ESX.GetPlayerFromId(src)` |
| Player Load Event | `QBCore:Server:OnPlayerLoaded` | `esx:playerLoaded` |

## Troubleshooting

### Characters not syncing
1. Check `Config.API_URL` is correct (no trailing slash)
2. Verify `Config.API_KEY` matches your backend's FiveM API Key
3. Ensure `Config.COMMUNITY_ID` is your Discord Server ID (not a user ID)
4. Make sure `esx_identity` is installed (provides firstname, lastname, etc.)
5. Check F8 console and server console for errors

### 401 Unauthorized
- Your API key doesn't match. Check both FiveM config, and CDE CAD Community Admin Panel.

### Community not found
- Your `Config.COMMUNITY_ID` doesn't match any community's `guildId` in the database

### Missing character data (name shows as "Unknown")
- ESX requires `esx_identity` for character names. Ensure it's installed and running.
- Check that the `users` table has `firstname` and `lastname` columns populated.
