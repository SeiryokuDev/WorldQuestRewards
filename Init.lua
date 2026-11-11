local ADDON_NAME, addonTable = ...

---@class table
local WQR = addonTable

local AceAddon        = LibStub("AceAddon-3.0")

_G.WQR                = WQR
WQR.ADDON_NAME_PRINT  = "[" .. WrapTextInColorCode(ADDON_NAME, "ffE6CC80") .. "]"

---Print standard message, can override verbose setting with "force"
---@param text string
---@param force? boolean If true, override verbose setting
function WQR:Message(text, force)
    if self.config.verbose or force then
        print(string.format("%s %s", self.ADDON_NAME_PRINT, text))
    end
end

---Print warning message with orange color, override verbose by default
---@param text string
---@param force? boolean If false, respect verbose setting
function WQR:Warning(text, force)
    force = force ~= false
    if self.config.verbose or force then
        print(string.format("%s %s", self.ADDON_NAME_PRINT, WrapTextInColorCode(text, "FFFF7700")))
    end
end

---Print error message with red color, override verbose by default
---@param text string
---@param force? boolean If false, respect verbose setting
function WQR:Error(text, force)
    force = force ~= false
    if self.config.verbose or force then
        print(string.format("%s %s", self.ADDON_NAME_PRINT, WrapTextInColorCode(text, "FFFF0000")))
    end
end

AceAddon:NewAddon(
    WQR,
    ADDON_NAME,
    "AceEvent-3.0",
    "AceConsole-3.0"
)

WQR.AceConfig = LibStub("AceConfig-3.0")
WQR.AceConfigDialog = LibStub("AceConfigDialog-3.0")
WQR.AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
WQR.LSM = LibStub("LibSharedMedia-3.0")

WQR.defaults = {
    global = {
        enabled = true,

        dbVersion = 1,
        questCache = {}
    },
    profile = {
        displayEnabled = true,
        frameLocked = false,

        fontFile = WQR.LSM:GetDefault("font"),
        fontSize = 14,
        fontOutline = "OUTLINE",

        offsetX = 0,
        offsetY = 0,

        width = 400,
        height = 300,

        customAnchorEnabled = false,
        customParentFrame = nil,

        verbose = true,
        debug = true,

        tomtom = true,
        rematch = true,

        expansions = {
            true, -- Legion
            true, -- BFA
            true, -- Shadowlands
            true, -- Dragonflight
            true, -- The War Within
            true, -- Midnight
        },

        rewards = {
            { id = "gold", name = "Gold", minAmount = 0, enabled = true },
        }
    }
}

-- --------------------------------------------------
-- Initialization
-- --------------------------------------------------
local function SanitizeQuestCache()
    local cache = WQR.db.global.questCache
    for questID, info in pairs(cache) do
        -- Remove non-pet NPCs
        if info.npc and WQR:QuestIsPetBattle(questID) == false then
            info.npc = nil
        end

        -- Remove "false" waypoints
        if info.waypoint == false then
            info.waypoint = nil
        end

        -- Remove stale flags
        info.active = nil

        -- Remove empty entries
        if not info.position and not info.npc and not info.waypoint then
            cache[questID] = nil
        end
    end
end

local function MigrateQuestCacheIfNeeded()
    if WQR.db.global.dbVersion < 2 then
        SanitizeQuestCache()
        WQR.db.global.dbVersion = 2
    end
end

function WQR:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("WQRDB", self.defaults, true)
    self.config = self.db.profile

    self:RegisterChatCommand("worldquestrewards", "HandleSlash")
    self:RegisterChatCommand("wqr", "HandleSlash")

    self:PopulateZoneList()

    self:RegisterSettings()

    if not self.db.global.enabled then
        self:Disable()
    end
end

-- --------------------------------------------------
-- Enable / Disable
-- --------------------------------------------------

function WQR:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateWorldQuestData")
    self:RegisterEvent("QUEST_LOG_UPDATE", "UpdateWorldQuestData")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "GetLastTargetedNPC")
    self:RegisterEvent("QUEST_TURNED_IN", function(_, questID)
        if questID then
            self:CacheQuest(questID)
            self:RemoveWaypoint(questID)
        end
    end)
    self:RegisterEvent("ZONE_CHANGED", function()
        self:OnZoneChanged()
        self:UpdateDisplay()
    end)
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
        self:OnZoneChanged()
        self:UpdateDisplay()
    end)

    self:CreateDisplay()
    self:ToggleDisplay(self.config.displayEnabled)
    self:UpdateWorldQuestData()

    self:Message("enabled")
end

function WQR:OnDisable()
    self:UnregisterAllEvents()
    self:ToggleDisplay(false)

    self:Message("disabled")
end

function WQR:SetEnabled(value)
    local enabled = not not value
    self.db.global.enabled = enabled

    if enabled then
        self:Enable()
    else
        self:Disable()
    end
end

function WQR:HandleSlash(arg)
    local cmd, extra = strsplit(" ", arg, 2)
    if cmd == "config" then
        self.AceConfigDialog:Open(ADDON_NAME)
    elseif cmd == "enable" then
        self:SetEnabled(true)
    elseif cmd == "disable" then
        self:SetEnabled(false)
    elseif cmd == "update" then
        self:UpdateWorldQuestData()
    elseif cmd == "findfaction" then
        self:FindFactionByName(extra)
    else
        self:ToggleDisplay()
    end

    self.AceConfigRegistry:NotifyChange(ADDON_NAME)
end

-- --------------------------------------------------
-- Populate list of zones to scan per expansion
-- --------------------------------------------------
function WQR:PopulateZoneList()
    self.uiMapIDs = {}
    self.continentOrder = {}
    self.mapToContinent = {}

    local expansions = self.config.expansions

    -- Legion
    if expansions[1] then
        self.uiMapIDs[1] = { -- Broken Isles
            627,             -- Dalaran
            630,             -- Azsuna
            790,             -- Eye of Azshara
            641,             -- Val'sharah
            650,             -- Highmountain
            634,             -- Stormheim
            680,             -- Suramar
            646,             -- Broken Shore
            830,             -- Krokuun
            882,             -- Eredath
            885,             -- Antoran Wastes
        }
    end

    -- Battle for Azeroth
    if expansions[2] then
        self.uiMapIDs[2] = { -- Kalimdor
            1527,            -- Uldum
        }
        self.uiMapIDs[3] = { -- Pandaria
            1530,            -- Vale of Eternal Blossoms
        }
        self.uiMapIDs[4] = { -- Zandalar
            862,             -- Zuldazar
            863,             -- Nazmir
            864,             -- Vol'dun
            1355,            -- Nazjatar
        }
        self.uiMapIDs[5] = { -- Kul Tiras
            895,             -- Tiragarde Sound
            896,             -- Drustvar
            942,             -- Stormsong Valley
            1462,            -- Mechagon Island
        }
    end

    -- Shadowlands
    if expansions[3] then
        self.uiMapIDs[6] = { -- Shadowlands
            1525,            -- Revendreth
            1536,            -- Maldraxxus
            1565,            -- Ardenweald
            1569,            -- Bastion
        }
    end

    -- Dragonflight
    if expansions[4] then
        self.uiMapIDs[7] = { -- Dragon Isles
            2022,            -- The Waking Shores
            2023,            -- Ohn'Aran Plains
            2024,            -- The Azure Span
            2025,            -- Thaldraszus
            2151,            -- The Forbidden Reach
            2133,            -- Zaralek Cavern
        }
    end

    -- The War Within
    if expansions[5] then
        self.uiMapIDs[8] = { -- Khaz Algar
            2214,            -- The Ringing Deeps
            2215,            -- Hallowfall
            2248,            -- Isle of Dorn
            2255,            -- Azj-Kahet
            2256,            -- Azj-Kahet - Lower
            2369,            -- Siren's Isle
            2346,            -- Undermine
            2371,            -- K'aresh
            2472,            -- Tazavesh
        }
    end

    -- Midnight
    if expansions[6] then
        self.uiMapIDs[9] = { -- Eastern Kingdoms
            241,             -- Twilight Highlands (prepatch)
            2393,            -- Silvermoon
            2395,            -- Eversong Woods
            2405,            -- Voidstorm
            2413,            -- Harandar
            2424,            -- Isle of Quel'Danas
            2437,            -- Zul'Aman
            2509,            -- Vaults of Atal'Utek
            2512,            -- The Coiled Isle
        }
    end

    for contID in pairs(self.uiMapIDs) do
        table.insert(self.continentOrder, contID)
    end

    table.sort(self.continentOrder)

    for continentID, zones in pairs(self.uiMapIDs) do
        for _, mapID in ipairs(zones) do
            self.mapToContinent[mapID] = continentID
        end
    end
end
