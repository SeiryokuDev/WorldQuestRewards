local ADDON_NAME, addonTable = ...

---@type table
local WQR = addonTable

---@type table
ElvUI = ElvUI or {}

-- --------------------------------------------------
-- Create main display frame
-- --------------------------------------------------

function WQR:CreateDisplay()
    if self.frame then return end

    local f = CreateFrame("Frame", ADDON_NAME .. "Frame", UIParent, "BackdropTemplate")
    self:SetParentFrame(f)

    -- ---------------------------
    -- Apply styling
    -- ---------------------------

    if not C_AddOns.IsAddOnLoaded("ElvUI") then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 }
        })
        f:SetBackdropColor(0, 0, 0, 0.7)
    end

    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, top = self:GetCenter()

        local parentLeft, parentTop = UIParent:GetCenter()

        local offsetX = left - parentLeft
        local offsetY = top - parentTop

        WQR.db.profile.offsetX = offsetX
        WQR.db.profile.offsetY = offsetY

        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
    end)

    f:SetResizable(not self.config.frameLocked)
    f:SetResizeBounds(250, 150)

    -- ---------------------------
    -- Title element
    -- ---------------------------
    local title = f:CreateFontString(nil, "OVERLAY")
    local titleFont = self.LSM:Fetch("font", self.config.fontFile)
    title:SetFont(titleFont or "Fonts\\FRIZQT__.TTF", self.config.fontSize + 2, self.config.fontOutline) -- slightly bigger
    title:SetPoint("TOP", f, "TOP", 0, 0)
    title:SetJustifyH("CENTER")
    title:SetText(ADDON_NAME)

    -- ---------------------------
    -- Close button
    -- ---------------------------
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    closeBtn:SetScript("OnClick", function()
        WQR:ToggleDisplay(false)
    end)

    -- Resize handle
    local resize = CreateFrame("Button", nil, f)
    resize:SetSize(16, 16)
    resize:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    resize:SetScript("OnMouseDown", function()
        if not WQR.config.frameLocked then
            if WQR.config.customAnchorEnabled then
                f:StartSizing("BOTTOM")
            else
                f:StartSizing("BOTTOMRIGHT")
            end
        end
    end)

    resize:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
    end)

    f:SetScript("OnSizeChanged", function(_, w, h)
        if not WQR.config.customAnchorEnabled then
            WQR.config.width = w
        end

        WQR.config.height = h

        WQR:UpdateDisplay()
    end)

    -- ScrollFrame
    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -24)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 10)

    -- Scroll child frame
    local contentFrame = CreateFrame("Frame", nil, scrollFrame)
    contentFrame:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(contentFrame)

    -- FontString inside scroll child frame
    local content = contentFrame:CreateFontString(nil, "OVERLAY")
    local fontPath = self.LSM:Fetch("font", self.config.fontFile)
    content:SetFont(fontPath or "Fonts\\FRIZQT__.TTF", self.config.fontSize, self.config.fontOutline)
    content:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    content:SetJustifyH("LEFT")
    content:SetJustifyV("TOP")
    content:SetWidth(scrollFrame:GetWidth())
    content:SetTextColor(1, 1, 1, 1)

    -- Store references
    self.frame = f
    self.title = title
    self.closeButton = closeBtn
    self.scrollFrame = scrollFrame
    self.contentFrame = contentFrame
    self.content = content

    -- Apply ElvUI skinning if found
    if C_AddOns.IsAddOnLoaded("ElvUI") then
        local E = unpack(ElvUI)
        local S = E:GetModule("Skins")

        f:SetTemplate("Transparent")

        if S and S.HandleCloseButton then
            S:HandleCloseButton(closeBtn, f)
        end

        if S and S.HandleScrollBar then
            S:HandleScrollBar(scrollFrame.ScrollBar)
        end
    end

    f:Hide()
end

function WQR:SetParentFrame(frame, i)
    i = i or 0
    frame:ClearAllPoints()
    if self.config.customAnchorEnabled
        and (self.config.customParentFrame ~= nil and self.config.customParentFrame ~= "")
        and i < 5
    then
        local parent = _G[self.config.customParentFrame]
        if parent then
            frame:SetSize(parent:GetWidth(), self.config.height)
            frame:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, 0)

            frame:SetMovable(true)
            frame:EnableMouse(false)

            if not frame._parentHooked then
                parent:HookScript("OnSizeChanged", function(_, w)
                    frame:SetWidth(w)
                end)
                frame._parentHooked = true
            end
            return
        else
            C_Timer.After(1, function()
                i = i + 1
                WQR:SetParentFrame(WQR.frame, i)
            end)
        end
    end
    frame:SetSize(self.config.width, self.config.height)
    frame:SetPoint("CENTER", UIParent, "CENTER", self.config.offsetX, self.config.offsetY)

    frame:SetMovable(not self.config.frameLocked)
    frame:EnableMouse(not self.config.frameLocked)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
end

-- --------------------------------------------------
-- Build display text from cached world quests
-- --------------------------------------------------

function WQR:BuildDisplayText()
    local lines = {}
    local total = {}

    if not self.data or not next(self.data) then
        table.insert(lines, "No tracked world quests active")
        return table.concat(lines, "\n")
    end

    for _, continentID in ipairs(self.continentOrder) do
        local zoneMapIDs = self.uiMapIDs[continentID]
        local contData   = self.data[continentID]

        if zoneMapIDs and contData then
            for _, zoneID in ipairs(zoneMapIDs) do
                local quests = contData[zoneID]
                if quests then
                    local mapInfo = C_Map.GetMapInfo(zoneID)
                    local mapName = mapInfo and mapInfo.name or ("Zone " .. zoneID)

                    local color
                    if self:MapIsCurrent(zoneID) then
                        color = "0000FF00" -- green
                    elseif self:MapSharesContinent(zoneID) then
                        color = "00FFA500" -- orange
                    end
                    mapName = color and WrapTextInColorCode(mapName, color) or mapName

                    table.insert(lines, string.format("%s:", mapName))

                    for questID, rewards in pairs(quests) do
                        local questLink = GetQuestLink(questID) or ("Quest " .. questID)
                        local petIcon = self:QuestIsPetBattle(questID) and "|T613074:15|t" or ""

                        local rewardStrings = {}
                        for itemID, info in pairs(rewards) do
                            if info.itemName then
                                if info.numItems and info.numItems > 0 then
                                    table.insert(rewardStrings,
                                        string.format("|T%s:15|t x%d", info.texture, info.numItems))
                                else
                                    table.insert(rewardStrings, info.itemName)
                                end

                                -- update totals
                                total[itemID] = total[itemID] or { itemName = info.itemName, count = 0 }
                                total[itemID].count = total[itemID].count + (info.numItems or 0)
                            end
                        end

                        local rewardsText = ""
                        if #rewardStrings > 0 then
                            rewardsText = table.concat(rewardStrings, ", ")
                            table.insert(lines, string.format("%s%s - %s", questLink, petIcon, rewardsText))
                        end
                    end

                    table.insert(lines, "") -- empty line after zone
                end
            end
        end
    end

    -- Totals
    table.insert(lines, "Total:")

    local warModeActive = C_PvP.IsWarModeActive()
    local warModeBonus = C_PvP.GetWarModeRewardBonus() / 100 or 0


    for itemID, info in pairs(total) do
        local bonusAmount = 0

        if warModeActive then
            local currencyID = tonumber(itemID)

            if itemID == "gold" or
                (currencyID and C_CurrencyInfo.DoesWarModeBonusApply(currencyID))
            then
                bonusAmount = math.floor(info.count * warModeBonus + 0.5)
            end
        end

        local bonusText = ""

        if bonusAmount > 0 then
            bonusText = string.format(
                " (%s)",
                WrapTextInColorCode("+" .. bonusAmount, "FF00FF00")
            )
        end

        table.insert(lines, string.format(
            "%s: x%d%s",
            info.itemName,
            info.count,
            bonusText
        ))
    end

    return table.concat(lines, "\n")
end

-- --------------------------------------------------
-- Utility functions
-- --------------------------------------------------
function WQR:MapIsCurrent(mapID)
    return mapID == self:GetEffectivePlayerMap()
end

function WQR:GetEffectivePlayerMap()
    local mapID = C_Map.GetBestMapForUnit("player")
    while mapID do
        if self.mapToContinent[mapID] then
            return mapID
        end
        local info = C_Map.GetMapInfo(mapID)
        mapID = info and info.parentMapID
    end
end

function WQR:MapSharesContinent(mapID)
    local playerMap = self:GetEffectivePlayerMap()
    if not playerMap then return false end

    return self.mapToContinent[mapID]
        and self.mapToContinent[mapID] == self.mapToContinent[playerMap]
end

-- --------------------------------------------------
-- Update the displayed text
-- --------------------------------------------------

function WQR:UpdateDisplay()
    if not self.frame then self:CreateDisplay() end
    if not self.db.global.enabled then
        self.content:SetText(self.disabledText)
    else
        local text = self:BuildDisplayText()
        self.content:SetText(text)
    end

    -- Adjust height based on content
    local width = self.scrollFrame:GetWidth()
    self.content:SetWidth(width)
    self.content:SetNonSpaceWrap(true)
    self.content:SetHeight(0)

    local textHeight = self.content:GetStringHeight() or 1
    self.content:SetHeight(textHeight)
    self.contentFrame:SetHeight(textHeight)
end

-- --------------------------------------------------
-- Toggle frame visibility
-- --------------------------------------------------

function WQR:ToggleDisplay(val)
    if not self.frame then return end
    if val == nil then
        local shown = self.frame:IsShown()
        self.frame:SetShown(not shown)
    else
        self.frame:SetShown(val)
    end

    self.config.displayEnabled = self.frame:IsShown()
    self.AceConfigRegistry:NotifyChange(ADDON_NAME)
end
