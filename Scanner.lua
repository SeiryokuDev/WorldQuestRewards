local _, addonTable = ...

---@type table
local WQR = addonTable

---@type table
DevTool = DevTool or {}

function WQR:UpdateWorldQuestData()
    local data = {}
    local seen = {}

    -- Scan enabled expansions/zones
    for _, continentID in ipairs(self.continentOrder) do
        local zoneMapIDs = self.uiMapIDs[continentID]
        for _, mapID in ipairs(zoneMapIDs or {}) do
            local tasks = C_TaskQuest.GetQuestsOnMap(mapID)
            if tasks then
                for _, task in pairs(tasks) do
                    local questID = task.questID
                    local questMapID = task.mapID or mapID -- Prioritze the task's registered mapID

                    if C_QuestLog.IsWorldQuest(questID)
                        and not C_QuestLog.IsQuestFlaggedCompleted(questID)
                        and not seen[questID]
                    then
                        self:ScanQuest(continentID, questMapID, questID, data)
                        seen[questID] = true
                    end
                end
            end
        end
    end

    self.data = data
    self:UpdateDisplay()
    if self.config.debug then
        DevTool:AddData(data, "WQR data")
    end
end

-- ============================================================================
-- Scan a single quest
-- ============================================================================

local function InitQuestTable(data, continentID, mapID, questID)
    local cont = data[continentID] or {}
    data[continentID] = cont

    local map = cont[mapID] or {}
    cont[mapID] = map

    local quest = map[questID] or {}
    map[questID] = quest

    return quest
end

function WQR:ScanQuest(continentID, mapID, questID, data)
    if not GetQuestLink(questID) then return end

    -- --------------------------------------------------
    -- Item rewards
    -- --------------------------------------------------
    local numItems = GetNumQuestLogRewards(questID)
    for i = 1, numItems do
        local name, texture, count, _, _, itemID =
            GetQuestLogRewardInfo(i, questID)

        if itemID then
            local config = self:GetRewardConfig(itemID)
            if config and (config.minAmount == 0 or count >= config.minAmount) then
                local questRewards = InitQuestTable(data, continentID, mapID, questID)
                questRewards[tostring(itemID)] = {
                    itemName = name,
                    numItems = count,
                    texture  = texture,
                }
            end
        end
    end

    -- --------------------------------------------------
    -- Currency rewards
    -- --------------------------------------------------
    local currencies = C_QuestInfoSystem.GetQuestRewardCurrencies(questID)
    for _, cur in pairs(currencies or {}) do
        if cur and cur.currencyID then
            local config = self:GetRewardConfig(cur.currencyID)
            if config and
                (config.minAmount == 0 or cur.totalRewardAmount >= config.minAmount)
            then
                local questRewards = InitQuestTable(data, continentID, mapID, questID)
                questRewards[tostring(cur.currencyID)] = {
                    itemName = cur.name,
                    numItems = cur.totalRewardAmount,
                    texture  = cur.texture,
                }
            end
        end
    end

    -- --------------------------------------------------
    -- Reputation rewards
    -- --------------------------------------------------
    local _, factionID = C_TaskQuest.GetQuestInfoByQuestID(questID)
    if factionID then
        local config = self:GetRewardConfig(factionID)
        if config and C_QuestLog.DoesQuestAwardReputationWithFaction(questID, factionID) then
            local info = C_Reputation.GetFactionDataByID(factionID)
            local questRewards = InitQuestTable(data, continentID, mapID, questID)
            questRewards[tostring(factionID)] = {
                itemName = (info and info.name or "Faction") .. " rep",
                numItems = 0,
                texture  = nil,
            }
        end
    end

    -- --------------------------------------------------
    -- Gold rewards
    -- --------------------------------------------------
    local gold = GetQuestLogRewardMoney(questID)
    if gold and gold > 0 then
        local config = self:GetRewardConfig("gold")
        local goldAmount = gold / 10000
        if config and (config.minAmount == 0 or goldAmount >= config.minAmount) then
            local questRewards = InitQuestTable(data, continentID, mapID, questID)
            questRewards["gold"] = {
                itemName = "Gold",
                numItems = goldAmount,
                texture  = "Interface\\Icons\\INV_Misc_Coin_01",
            }
        end
    end
end

function WQR:ActiveTasksInCurrentMap()
    local list = {}

    if self.data and next(self.data) then
        for _, continentID in ipairs(self.continentOrder) do
            local zoneMapIDs = self.uiMapIDs[continentID]
            local contData   = self.data[continentID]

            if zoneMapIDs and contData then
                for _, zoneID in ipairs(zoneMapIDs) do
                    if WQR:MapIsCurrent(zoneID) or self:MapSharesContinent(zoneID) then
                        local quests = contData[zoneID]
                        if quests then
                            for questID in pairs(quests) do
                                table.insert(list, questID)
                            end
                        end
                    end
                end
            end
        end
    end

    return #list > 0 and list or nil
end

function WQR:QuestIsPetBattle(questID)
    local info = C_QuestLog.GetQuestTagInfo(questID)
    return info and info.worldQuestType == 4
end
