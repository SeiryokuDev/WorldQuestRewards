local ADDON_NAME, addonTable = ...

---@type table
local WQR = addonTable

-- ============================================================================
-- Registration
-- ============================================================================

function WQR:RegisterSettings()
    self:BuildOptions()

    self.AceConfig:RegisterOptionsTable(ADDON_NAME, self.options)

    local _, categoryID = self.AceConfigDialog:AddToBlizOptions(ADDON_NAME, ADDON_NAME)
    self.settingsCategoryID = categoryID

    self:BuildCacheOptions()

    self.AceConfig:RegisterOptionsTable(
        ADDON_NAME .. "_Cache",
        self.cacheOptions
    )

    local _, cacheCategoryID = self.AceConfigDialog:AddToBlizOptions(
        ADDON_NAME .. "_Cache",
        "Quest Cache",
        categoryID
    )

    self.cacheSettingsCategoryID = cacheCategoryID
end

-- ============================================================================
-- Options builder
-- ============================================================================

function WQR:BuildOptions()
    if self.options then
        return self.options
    end

    self.options = {
        name = ADDON_NAME,
        handler = self,
        type = "group",
        args = {
            -- ============================================================
            -- General
            -- ============================================================
            generalHeader = {
                type = "header",
                name = "General Options",
                order = 1,
            },

            enabled = {
                type = "toggle",
                name = "Enable " .. ADDON_NAME,
                desc = "Enable or disable " .. ADDON_NAME .. " entirely",
                width = "full",
                get = function() return WQR.db.global.enabled end,
                set = function(_, val)
                    WQR:SetEnabled(val)
                end,
                order = 2,
            },

            displayEnabled = {
                type = "toggle",
                name = "Enable Display",
                desc = "Show or hide the World Quest display",
                width = "full",
                get = function() return WQR.db.profile.displayEnabled end,
                set = function(_, val)
                    WQR.db.profile.displayEnabled = val
                    WQR:ToggleDisplay(val)
                end,
                order = 3,
            },

            fontFile = {
                type = "select",
                name = "Font",
                desc = "Select font",
                dialogControl = "LSM30_Font",
                values = WQR.LSM:HashTable("font"),
                get = function()
                    return WQR.db.profile.fontFile
                end,
                set = function(_, key)
                    WQR.db.profile.fontFile = key
                    local fontPath = WQR.LSM:Fetch("font", key)
                    if WQR.title then
                        WQR.title:SetFont(
                            fontPath,
                            WQR.db.profile.fontSize + 2,
                            WQR.db.profile.fontOutline
                        )
                    end
                    if WQR.content then
                        WQR.content:SetFont(
                            fontPath,
                            WQR.db.profile.fontSize,
                            WQR.db.profile.fontOutline
                        )
                    end
                end,
                order = 4
            },

            fontSize = {
                type = "range",
                name = "Font Size",
                desc = "Select font size",
                min = 8,
                max = 32,
                step = 1,
                get = function()
                    return WQR.db.profile.fontSize
                end,
                set = function(_, val)
                    WQR.db.profile.fontSize = val
                    local fontPath = WQR.LSM:Fetch("font", WQR.db.profile.fontFile)
                    if WQR.title then
                        WQR.title:SetFont(
                            fontPath,
                            val + 2,
                            WQR.db.profile.fontOutline
                        )
                    end
                    if WQR.content then
                        WQR.content:SetFont(
                            fontPath,
                            val,
                            WQR.db.profile.fontOutline
                        )
                    end
                end,
                order = 5
            },

            anchorSettings = {
                type = "group",
                name = "Anchor settings",
                inline = true,
                order = 6,
                args = {
                    enabled = {
                        type = "toggle",
                        name = "Use custom anchor",
                        desc = "",
                        width = "full",
                        get = function() return WQR.db.profile.customAnchorEnabled end,
                        set = function(_, val)
                            WQR.db.profile.customAnchorEnabled = val
                            WQR:SetParentFrame(WQR.frame)
                            WQR.AceConfigRegistry:NotifyChange(ADDON_NAME)
                        end,
                        order = 1
                    },
                    customFrame = {
                        type = "input",
                        name = "Custom anchor frame",
                        desc = "Name of the frame to anchor to",
                        width = "normal",
                        disabled = function() return not WQR.db.profile.customAnchorEnabled end,
                        get = function() return WQR.db.profile.customParentFrame end,
                        set = function(_, val)
                            WQR.db.profile.customParentFrame = val
                            WQR:SetParentFrame(WQR.frame)
                        end,
                        validate = function(_, val)
                            return val == nil or val == "" or _G[val] ~= nil
                        end,
                        order = 2
                    }
                }
            },

            verbose = {
                type = "toggle",
                name = "Verbose",
                desc = "Print messages on automated actions",
                width = "full",
                get = function() return WQR.db.profile.verbose end,
                set = function(_, val)
                    WQR.db.profile.verbose = val
                end,
                order = 7,
            },

            debug = {
                type = "toggle",
                name = "Debug",
                width = "full",
                get = function() return WQR.db.profile.debug end,
                set = function(_, val)
                    WQR.db.profile.debug = val
                end,
                order = 8,
            },
        },
    }

    -- Inject sub-sections
    self:AddIntegrationOptions()
    self:AddExpansionOptions()
    self:AddRewardFilterOptions()

    return self.options
end

function WQR:BuildCacheOptions()
    if self.cacheOptions then
        return self.cacheOptions
    end

    self.cacheSearch = ""

    self.cacheOptions = {
        name = "Quest Cache",
        type = "group",
        childGroups = "tree",
        args = {
            search = {
                type = "input",
                name = "Search",
                desc = "Search cached world quests by quest ID or name.",
                width = "full",
                get = function()
                    return self.cacheSearch
                end,
                set = function(_, value)
                    self.cacheSearch = value
                    self:RebuildCacheOptions()
                    self.AceConfigRegistry:NotifyChange(ADDON_NAME .. "_Cache")
                end,
                order = 1,
            },
        },
    }

    self:RebuildCacheOptions()

    return self.cacheOptions
end

-- ============================================================================
-- Integrations
-- ============================================================================

function WQR:AddIntegrationOptions()
    local args = self.options.args
    local shouldLoad = false

    if C_AddOns.IsAddOnLoaded("Rematch") then
        shouldLoad = true
        args.rematch = {
            type = "toggle",
            name = "Enable Rematch integration",
            desc = "Automatically load pet battle teams when entering a zone with a known pet battle world quest",
            order = 21,
            get = function() return WQR.db.profile.rematch end,
            set = function(_, val)
                WQR.db.profile.rematch = val
            end,
        }
    end

    if C_AddOns.IsAddOnLoaded("TomTom") then
        shouldLoad = true
        args.tomtom = {
            type = "toggle",
            name = "Enable TomTom integration",
            desc = "Automatically add a TomTom waypoint when entering a zone with a tracked world quest",
            order = 22,
            get = function() return WQR.db.profile.tomtom end,
            set = function(_, val)
                WQR.db.profile.tomtom = val
            end,
        }
    end

    if shouldLoad then
        args.integrationHeader = {
            type = "header",
            name = "Integrations",
            order = 20,
        }
    end
end

-- ============================================================================
-- Expansions
-- ============================================================================

function WQR:AddExpansionOptions()
    local args = self.options.args

    args.expansionHeader = {
        type = "header",
        name = "Expansions",
        order = 40,
    }

    local expansionNames = {
        "Legion",
        "Battle for Azeroth",
        "Shadowlands",
        "Dragonflight",
        "The War Within",
        "Midnight"
    }

    for i, name in ipairs(expansionNames) do
        args["expansion_" .. i] = {
            type = "toggle",
            name = name,
            desc = "Enable World Quest tracking for the " .. name .. "expansion",
            width = "normal",
            order = 40 + i,
            get = function()
                return WQR.db.profile.expansions[i]
            end,
            set = function(_, val)
                WQR.db.profile.expansions[i] = val
                WQR:PopulateZoneList()
                WQR:UpdateWorldQuestData()
            end,
        }
    end
end

-- ============================================================================
-- Rewards Filter
-- ============================================================================

function WQR:AddRewardFilterOptions()
    local args = self.options.args

    args.rewards = {
        type = "group",
        name = "Rewards Filter",
        inline = true,
        order = 80,
        args = {},
    }

    self:RebuildRewardFilterOptions()
end

function WQR:RebuildRewardFilterOptions()
    local rewardsGroup = self.options.args.rewards
    if not rewardsGroup then return end

    rewardsGroup.args = {}

    for i, reward in ipairs(self.config.rewards) do
        rewardsGroup.args["rewardDivider_" .. i] = {
            type = "header",
            name = "",
            order = i * 10
        }
        rewardsGroup.args["reward_" .. i] = {
            type = "group",
            name = "",
            inline = true,
            order = i * 10 + 1,
            args = {
                name = {
                    type = "description",
                    name = function()
                        return reward.name or ((reward.id ~= "") and reward.id or "New Reward")
                    end,
                    width = "half",
                    order = 1
                },

                id = {
                    type = "input",
                    name = "Reward",
                    desc = "Item Link, Item ID, Currency ID, Faction ID or \"gold\"",
                    width = "normal",
                    get = function() return tostring(reward.id or "") end,
                    set = function(_, val)
                        reward.id = val
                        WQR:ResolveRewardName(reward)
                        WQR:UpdateWorldQuestData()
                        WQR.AceConfigRegistry:NotifyChange(ADDON_NAME)
                    end,
                    order = 2,
                },

                minAmount = {
                    type = "range",
                    name = "Minimum Amount",
                    desc = "Hide world quests below this reward amount",
                    min = 0,
                    max = 10000,
                    step = 1,
                    width = "normal",
                    get = function() return reward.minAmount or 0 end,
                    set = function(_, val)
                        reward.minAmount = val
                        WQR:UpdateWorldQuestData()
                    end,
                    order = 3,
                },

                enabled = {
                    type = "toggle",
                    name = "Enabled",
                    width = "normal",
                    get = function() return reward.enabled end,
                    set = function(_, val)
                        reward.enabled = val
                        WQR:UpdateWorldQuestData()
                    end,
                    order = 4,
                },

                remove = {
                    type = "execute",
                    name = "Remove",
                    confirm = true,
                    confirmText = "Remove this reward filter?",
                    func = function()
                        table.remove(WQR.db.profile.rewards, i)
                        WQR:UpdateWorldQuestData()
                        WQR:RebuildRewardFilterOptions()
                        WQR.AceConfigRegistry:NotifyChange(ADDON_NAME)
                    end,
                    order = 5,
                },
            },
        }
    end

    -- Add button
    rewardsGroup.args.addRewardDivider = {
        type = "header",
        name = "",
        order = 999
    }
    rewardsGroup.args.addReward = {
        type = "execute",
        name = "+ Add Reward",
        order = 1000,
        func = function()
            table.insert(WQR.db.profile.rewards, {
                id = "",
                name = "New Reward",
                minAmount = 0,
                enabled = true,
            })
            WQR:RebuildRewardFilterOptions()
            WQR.AceConfigRegistry:NotifyChange(ADDON_NAME)
        end,
    }
end

-- ============================================================================
-- Cache
-- ============================================================================

function WQR:RebuildCacheOptions()
    if not self.cacheOptions then
        return
    end

    local cache = self.db.global.questCache
    local args = {
        search = self.cacheOptions.args.search,
    }

    local search = strlower(strtrim(self.cacheSearch or ""))
    local questIDs = {}

    for questID in pairs(cache) do
        questIDs[#questIDs + 1] = tonumber(questID)
    end

    table.sort(questIDs)

    for _, questID in ipairs(questIDs) do
        local questInfo = cache[questID]

        local questName = C_QuestLog.GetTitleForQuestID(questID)

        if not questName or questName == "" then
            questName = "Quest " .. questID
        end

        local questIDString = tostring(questID)

        local matchesSearch =
            search == ""
            or strfind(strlower(questName), search, 1, true)
            or strfind(questIDString, search, 1, true)

        if matchesSearch then
            args["quest_" .. questID] = self:BuildCachedQuestOptions(
                questID,
                questInfo,
                questName
            )
        end
    end

    self.cacheOptions.args = args
end

function WQR:BuildCachedQuestOptions(questID, questInfo, questName)
    return {
        type = "group",
        name = questName .. " (" .. questID .. ")",
        args = {
            questID = {
                type = "description",
                name = "Quest ID: " .. questID,
                order = 1,
            },

            mapID = {
                type = "input",
                name = "Map ID",
                desc = "The uiMapID containing the quest location.",
                get = function()
                    local position = questInfo.position

                    if not position or not position.zone then
                        return ""
                    end

                    return tostring(position.zone)
                end,
                set = function(_, value)
                    local mapID = tonumber(value)

                    if not mapID then
                        return
                    end

                    questInfo.position = questInfo.position or {}
                    questInfo.position.zone = mapID
                end,
                order = 2,
            },

            x = {
                type = "input",
                name = "X",
                desc = "X coordinate as a percentage of the map.",
                get = function()
                    local position = questInfo.position

                    if not position or not position.x then
                        return ""
                    end

                    return tostring(position.x)
                end,
                set = function(_, value)
                    local x = tonumber(value)

                    if not x then
                        return
                    end

                    questInfo.position = questInfo.position or {}
                    questInfo.position.x = x
                end,
                order = 3,
            },

            y = {
                type = "input",
                name = "Y",
                desc = "Y coordinate as a percentage of the map.",
                get = function()
                    local position = questInfo.position

                    if not position or not position.y then
                        return ""
                    end

                    return tostring(position.y)
                end,
                set = function(_, value)
                    local y = tonumber(value)

                    if not y then
                        return
                    end

                    questInfo.position = questInfo.position or {}
                    questInfo.position.y = y
                end,
                order = 4,
            },

            remove = {
                type = "execute",
                name = "Remove",
                confirm = true,
                confirmText = "Remove this quest from the cache?",
                func = function()
                    self.db.global.questCache[questID] = nil

                    self:RebuildCacheOptions()
                    self.AceConfigRegistry:NotifyChange(ADDON_NAME .. "_Cache")
                end,
                order = 5,
            },
        },
    }
end

-- ============================================================================
-- Helper functions
-- ============================================================================

function WQR:ResolveRewardName(reward)
    local id = self:GetIDFromLink(reward.id) or tonumber(reward.id)
    if id then
        local itemName = C_Item.GetItemInfo(id)
        if itemName then
            reward.id = id
            reward.name = itemName
            return
        end

        local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(id)
        if currencyInfo then
            reward.id = id
            reward.name = currencyInfo.name
            return
        end

        local factionInfo = C_Reputation.GetFactionDataByID(id)
        if factionInfo then
            reward.name = factionInfo.name .. " rep"
            return
        end
    end

    if reward.id == "gold" then
        reward.name = "Gold"
        return
    end

    if reward.id ~= "" and reward.id ~= nil then
        reward.name = "Invalid identifier"
        return
    end

    reward.name = nil
end

function WQR:GetIDFromLink(link)
    if not link then return nil end

    local id = link:match("item:(%d+)") or link:match("currency:(%d+)")
    if id then
        return tonumber(id)
    end

    return nil
end

-- ============================================================================
-- Reward config lookup
-- ============================================================================
function WQR:GetRewardConfig(id)
    if not id then return nil end
    for _, reward in ipairs(self.config.rewards) do
        if reward.enabled and tostring(reward.id) == tostring(id) then
            return reward
        end
    end
    return nil
end
