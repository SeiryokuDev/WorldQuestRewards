local _, addonTable = ...

---@type table
local WQR = addonTable

function WQR:CacheQuest(questID)
    if not questID then return end

    local cache = self.db.global.questCache
    local questInfo = cache[questID]

    if not questInfo and C_QuestLog.IsWorldQuest(questID) then
        questInfo = {}
        cache[questID] = questInfo
    end

    if not questInfo then return end

    local map = C_Map.GetBestMapForUnit("player")
    if not map then return end

    local playerPos = C_Map.GetPlayerMapPosition(map, "player")
    if not playerPos then return end

    if not questInfo.position then
        self:Message("Adding new world quest data to cache")

        questInfo.position = {
            zone = map,
            x = playerPos.x * 100,
            y = playerPos.y * 100
        }
    end

    if self:QuestIsPetBattle(questID) then
        questInfo.npc = self.lastNPCTargeted or nil
    end
end

function WQR:GetLastTargetedNPC()
    local unit = "target"
    if UnitExists(unit) then
        local guid = UnitGUID("target")
        if not issecretvalue(guid) then
            local npcID = tonumber((guid or ""):match(".-%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
            local name = UnitName(unit)
            if npcID and npcID ~= 0 then
                self.lastNPCTargeted = { ID = npcID, name = name }
                return
            else
                return
            end
        end
    end
end
