local _, addonTable = ...

---@type table
local WQR = addonTable

---@type table
TomTom = TomTom or {}

---@type table
Rematch = Rematch or {}

---@type table
RematchSettings = RematchSettings or {}

function WQR:OnZoneChanged()
    self:UpdateWorldQuestData()
    local activeTasks = self:ActiveTasksInCurrentMap()
    if not activeTasks then return end

    if self.config.displayEnabled then
        for _, questID in pairs(activeTasks) do
            if self.config.rematch then
                self:LoadRematchTeam(questID)
            end

            if self.config.tomtom then
                self:AddWaypoint(questID)
            end
        end
    end

    if TomTom then
        self:ClearRemovedWaypoints()
        TomTom:SetClosestWaypoint(false)
    end
end

function WQR:LoadRematchTeam(questID)
    if not Rematch or not RematchSettings then return end
    if not self:QuestIsPetBattle(questID) then return end

    local cache = self.db.global.questCache
    local questInfo = cache[questID]
    if not questInfo or not questInfo.npc then return end
    local npc = questInfo.npc
    -- if correct team already loaded, return
    if RematchSettings.loadedTeam == npc.ID then return end

    if not self.rematchLastAttempt or self.rematchLastAttempt < GetTime() - 1 then
        self.rematchLastAttempt = GetTime()
        Rematch:LoadTeam(npc.ID)

        if RematchSettings.loadedTeam == npc.ID then
            self:Message(string.format("Rematch team for %s successfully loaded",
                WrapTextInColorCode(npc.name, "ffffff00")))

            C_Timer.After(1, function()
                for slot = 1, 3 do
                    local petID = C_PetJournal.GetPetLoadOutInfo(slot)
                    if petID and C_PetJournal.PetIsHurt(petID) then
                        self:Message("One or more pets not at full health", true)
                    end
                end
            end)
        else
            -- if failed, allow for subsequent calls to try again. If no success after 20 seconds, print warning
            if not self.rematchLastFail or self.rematchLastFail < GetTime() - 20 then
                self.rematchLastFail = GetTime()
                self:Warning("Rematch team failed to load")
            end
        end
    end
end

function WQR:AddWaypoint(questID)
    if not TomTom then return end

    local cache = self.db.global.questCache
    local questInfo = cache[questID]
    if not questInfo or not questInfo.position then return end
    local position = questInfo.position
    -- if waypoint already set, return
    if questInfo.waypoint then return end

    local questName = C_TaskQuest.GetQuestInfoByQuestID(questID)
    if not questName then return end

    local waypointOptions = { title = string.format("WQR: %s", questName), persistent = false }
    questInfo.waypoint = TomTom:AddWaypoint(position.zone, position.x / 100, position.y / 100, waypointOptions)

    self:Message(string.format("Adding waypoint to %s", GetQuestLink(questID)))

    return true
end

function WQR:RemoveWaypoint(questID)
    if not questID or not TomTom then return end

    local cache = self.db.global.questCache
    local questInfo = cache[questID]

    if questInfo and questInfo.waypoint then
        self:Message(string.format("Removing waypoint for %s", GetQuestLink(questID)))

        TomTom:RemoveWaypoint(questInfo.waypoint)
        if TomTom:IsValidWaypoint(questInfo.waypoint) then
            self:Error("Failed to remove waypoint")
        else
            questInfo.waypoint = nil
        end
    end
end

function WQR:ClearRemovedWaypoints()
    if not TomTom then return end

    local cache = self.db.global.questCache
    for _, questInfo in pairs(cache) do
        if questInfo and questInfo.waypoint then
            if not TomTom:IsValidWaypoint(questInfo.waypoint) then
                questInfo.waypoint = nil
            end
        end
    end
end
