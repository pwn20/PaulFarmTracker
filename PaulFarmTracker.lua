-- ============================================================================
-- PaulFarmTracker Addon
-- ============================================================================

local addonName, addon = ...
PFT = {}

-- Make the addon's table global for the keybinding
local PFT = PFT

-- ============================================================================
-- Configuration & Session Data
-- ============================================================================

PFT.chatPrefix = "|cff3399ffPFT|r: "
PFT.sessionTotal = 0
PFT.lastPrintedTotal = 0
PFT.goalReached = false
PFT.cheapestPrice = 0

-- Gear sets for swapping
PFT.gloveSets = {
    ["tichdh"] = {
        { id = 161029, label = "Skinning" },
        { id = 174146, label = "Herbalism" }
    },
    ["zuljindh"] = {
        { id = 24696, label = "Skinning" }, -- "Bonechewer Spikegloves of the Quickblade" (skin) on my zuljin DH
        { id = 154738, label = "Herbalism" } -- "Illidari Gloves (herb)" on my zuljin DH
    }
}

local function Print(message)
    print(PFT.chatPrefix .. message)
end

-- ============================================================================
-- UI Creation & Management
-- ============================================================================

-- NEW: This function creates all the UI elements for our tracker window.
function PFT:CreateUI()
    -- Main Frame
    PFT.frame = CreateFrame("Frame", "PFT_MainFrame", UIParent, "BackdropTemplate")
	local frame = PFT.frame
    frame:SetSize(220, 145) -- Slightly taller for set name
    
    -- Load saved position or center it if none exists
    if PaulFarmTrackerDB and PaulFarmTrackerDB.framePoint then
        frame:SetPoint(unpack(PaulFarmTrackerDB.framePoint))
    else
        frame:SetPoint("CENTER")
    end
    
    frame:SetBackdrop({
        bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)

    -- Make the frame movable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save the frame's position when the user stops dragging it
        PaulFarmTrackerDB.framePoint = {self:GetPoint()}
    end)
    frame:SetClampedToScreen(true) -- Keep it on the screen

    -- Title Text
    frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -16)
    frame.title:SetText("Paul's Farm Tracker")

    -- Item and Progress (Total / Goal)
    frame.progress = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.progress:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -40)

    -- Price Per Item
    frame.price = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.price:SetPoint("TOPLEFT", frame.progress, "BOTTOMLEFT", 0, -8)
    
    -- Total Gold Value
    frame.totalValue = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.totalValue:SetPoint("TOPLEFT", frame.price, "BOTTOMLEFT", 0, -8)

    -- Equipped Gloves
    frame.equippedGloves = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.equippedGloves:SetPoint("TOPLEFT", frame.totalValue, "BOTTOMLEFT", 0, -8)

    -- Active Set Name
    frame.activeSet = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.activeSet:SetPoint("TOPLEFT", frame.equippedGloves, "BOTTOMLEFT", 0, -4)
	
    -- Hide frame by default, let the DB setting determine visibility
    frame:Hide()
end

-- NEW: This function updates the text on our UI frame.
function PFT:UpdateDisplay()
    local frame = PFT_MainFrame
    if not frame then return end -- Don't do anything if the frame doesn't exist

    local itemID = PaulFarmTrackerDB.itemId
    local itemName = GetItemInfo(itemID) or PaulFarmTrackerDB.itemName -- Fallback to saved name
    local currentTotal = PFT.sessionTotal
    local goal = PaulFarmTrackerDB.goal
    local price = PaulFarmTrackerDB.price
    local totalValue = currentTotal * price

    -- Line 1: Item Name: Current / Goal
    frame.progress:SetText(string.format("%s: |cffffffff%d / %d|r", itemName, currentTotal, goal))
    
    -- Line 2: Price per item
    frame.price:SetText(string.format("Price/ea: |cFFebeb42%.2fg|r", price))

    -- Line 3: Total estimated value
    frame.totalValue:SetText(string.format("Est. Value: |cFFebeb42%.2fg|r", totalValue))

    -- Line 4: Equipped Gloves
    local handsSlotId = GetInventorySlotInfo("HANDSSLOT")
    local equippedGloveID = GetInventoryItemID("player", handsSlotId)
    local equippedGloveName = "None"
    
    -- Try to find a label from the active set
    local activeSetName = PaulFarmTrackerDB.activeGloveSet or "default"
    local activeSet = PFT.gloveSets[activeSetName]
    
    if equippedGloveID and equippedGloveID ~= 0 then
        if activeSet then
            for _, gloveData in ipairs(activeSet) do
                if gloveData.id == equippedGloveID then
                    equippedGloveName = gloveData.label or GetItemInfo(equippedGloveID)
                    break
                end
            end
        end
        
        -- Fallback to item name if no label found in active set
        if equippedGloveName == "None" then
            equippedGloveName = GetItemInfo(equippedGloveID) or "Unknown Item"
        end
    end
	
    frame.equippedGloves:SetText(string.format("Gloves: |cffffffff%s|r", equippedGloveName))

    -- Line 5: Active Set Name
    frame.activeSet:SetText(string.format("Set: |cff999999%s|r", activeSetName))
end

-- ============================================================================
-- Core Functions
-- ============================================================================

function PFT:ScanBagsForItem(itemId)
    return C_Item.GetItemCount(itemId)
end

function PFT:QueryAuctionHouse()
    local itemID = PaulFarmTrackerDB.itemId
    if not itemID then return end

    local _, itemLink = GetItemInfo(itemID)
    if not itemLink then return end

    -- Priority 1: Check for Auctionator API
    if AUCTIONATOR_API_GetPrice and type(AUCTIONATOR_API_GetPrice) == "function" then
        local price = AUCTIONATOR_API_GetPrice(itemLink)
        if price and price > 0 then
            PFT.cheapestPrice = price / 10000 -- Convert from copper
            Print(string.format("Cheapest '%s' (from Auctionator) found for |cFFebeb42%.2fg|r.", PaulFarmTrackerDB.itemName, PFT.cheapestPrice))
        end
    -- Priority 2: Check for Standard Blizzard API
    elseif C_AuctionHouse and C_AuctionHouse.Query then
        C_AuctionHouse.Query({itemLink = itemLink})
    end
end

function PFT:UpdateAuctionData()
    if not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then return end

    local results = C_AuctionHouse.GetBrowseResults()
    
    -- Guard against nil or irrelevant results
    if not results or not results[1] or not results[1].itemKey or results[1].itemKey.itemID ~= PaulFarmTrackerDB.itemId then
        return
    end

    local cheapest = nil

    for _, result in ipairs(results) do
        if result.minPrice and result.minPrice > 0 then
            local pricePer = result.minPrice
            if not cheapest or pricePer < cheapest then
                cheapest = pricePer
            end
        end
    end

    if cheapest then
        PFT.cheapestPrice = cheapest / 10000 -- convert from copper
        Print(string.format("Cheapest '%s' found for |cFFebeb42%.2fg|r.", PaulFarmTrackerDB.itemName, PFT.cheapestPrice))
    end
end

function PFT:SwapGloves()
    local activeSetName = PaulFarmTrackerDB.activeGloveSet or "default"
    local activeSet = PFT.gloveSets[activeSetName]

    if not activeSet or #activeSet == 0 then
        Print(string.format("Error: Glove set '|cffff0000%s|r' not found or empty.", activeSetName))
        return
    end

    local handsSlotId = GetInventorySlotInfo("HANDSSLOT")
    local equippedItemID = GetInventoryItemID("player", handsSlotId)
    local itemToEquipID

    if #activeSet == 1 then
        itemToEquipID = activeSet[1].id
    elseif not equippedItemID or equippedItemID == 0 then
        itemToEquipID = activeSet[1].id
    else
        if equippedItemID == activeSet[1].id then
            itemToEquipID = activeSet[2].id
        else
            itemToEquipID = activeSet[1].id
        end
    end

    if itemToEquipID then
        local itemName = GetItemInfo(itemToEquipID)
        EquipItemByName(itemToEquipID)
        -- Print(string.format("Equipped: |cFFebeb42%s|r", itemName))
        PFT:UpdateDisplay()
    else
        Print("No item to equip.")
    end
end

function PFT:SwapAndAnnounce()
    local activeSetName = PaulFarmTrackerDB.activeGloveSet or "default"
    local activeSet = PFT.gloveSets[activeSetName]

    if not activeSet or #activeSet == 0 then
        Print(string.format("Error: Glove set '|cffff0000%s|r' not found or empty.", activeSetName))
        return
    end

    -- Swaps to the second item in the set (or first if only one) and announces it
    local targetIndex = (#activeSet >= 2) and 2 or 1
    local itemToEquipID = activeSet[targetIndex].id
    
    if itemToEquipID then
        local itemName, itemLink = GetItemInfo(itemToEquipID)
        EquipItemByName(itemToEquipID)
        
        if itemName then
            RaidNotice_AddMessage(RaidWarningFrame, "Equipped: " .. itemName, {r=0, g=1, b=0})
        end
        
        PFT:UpdateDisplay()
    end
end

function PFT:FindGloves()
    local handsSlotId = GetInventorySlotInfo("HANDSSLOT")
    local equippedGloveID = GetInventoryItemID("player", handsSlotId)
    
    if equippedGloveID and equippedGloveID ~= 0 then
        local name = GetItemInfo(equippedGloveID)
        Print(string.format("Currently Equipped Gloves: |cFF00ff00%s|r (ID: |cffffffff%d|r)", name or "Unknown", equippedGloveID))
    else
        Print("No gloves are currently equipped.")
    end
end

-- ============================================================================
-- Event Handling
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        PFT:OnAddonLoaded()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "CHAT_MSG_LOOT" then
        PFT:OnChatMsgLoot(arg1)
    elseif event == "AUCTION_HOUSE_SHOW" then
        PFT:QueryAuctionHouse()
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        PFT:UpdateAuctionData()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Print("Equipment has changed.")
		PFT:UpdateDisplay()
    end
end)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CHAT_MSG_LOOT")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

function PFT:OnAddonLoaded()
    PaulFarmTrackerDB = PaulFarmTrackerDB or {
        itemId = 168649,
        itemName = "Dredged Leather",
        price = 10,
        goal = 1000,
        framePoint = nil, -- NEW: For saving frame position
        isShown = true,   -- NEW: To remember if the frame should be shown
        activeGloveSet = "default" -- NEW: Store the name of the active glove set
    }

    -- Migration: ensure activeGloveSet exists if DB was already present
    if not PaulFarmTrackerDB.activeGloveSet then
        PaulFarmTrackerDB.activeGloveSet = "default"
    end

    local initialCount = PFT:ScanBagsForItem(PaulFarmTrackerDB.itemId)
    PFT.sessionTotal = initialCount
    PFT.lastPrintedTotal = initialCount
    
    SlashCmdList["PFT"] = PFT.SlashCmdHandler
    SLASH_PFT1 = "/pft"

    -- NEW: Create and update the UI
    PFT:CreateUI()
    PFT:UpdateDisplay()
    
    -- NEW: Show or hide the frame based on the saved setting
    if PaulFarmTrackerDB.isShown then
        PFT_MainFrame:Show()
    end

    Print("PaulFarmTracker loaded. Type /pft help for commands.")
end

function PFT:OnChatMsgLoot(message)
    if string.find(message, PaulFarmTrackerDB.itemName) then
        local currentTotal = PFT:ScanBagsForItem(PaulFarmTrackerDB.itemId)
        PFT.sessionTotal = currentTotal
        PFT:UpdateDisplay()

        if PFT.sessionTotal >= PFT.lastPrintedTotal + 100 then
            local totalValue = PFT.sessionTotal * PaulFarmTrackerDB.price
            local status = string.format("Update: %d / %d (Est. Value: |cFFebeb42%.2fg|r)", PFT.sessionTotal, PaulFarmTrackerDB.goal, totalValue)
            Print(status)
            PFT.lastPrintedTotal = PFT.sessionTotal
        end

        if PFT.sessionTotal >= PaulFarmTrackerDB.goal and not PFT.goalReached then
            Print(string.format("|cff00ff00GOAL REACHED!|r You have farmed |cFFebeb42%s|r / |cFFebeb42%d|r %s!", PFT.sessionTotal, PaulFarmTrackerDB.goal, PaulFarmTrackerDB.itemName))
            PFT.goalReached = true
        end
    end
end

-- ============================================================================
-- Slash Command Handler
-- ============================================================================

function PFT.SlashCmdHandler(msg)
    local args = {}
    for word in string.gmatch(string.lower(msg), "[^%s]+") do
        table.insert(args, word)
    end
    
    local command = args[1]

    if command == "status" or command == nil then
        local goal = PaulFarmTrackerDB.goal
        local price = PaulFarmTrackerDB.price
        local totalValue = (PFT.sessionTotal * price)
        local percentage = (goal > 0 and (PFT.sessionTotal / goal) * 100 or 0)
        
		Print("---")
        Print(string.format("Tracking: |cFFebeb42%s|r", PaulFarmTrackerDB.itemName))
        Print(string.format("Session: |cFFebeb42%d|r / |cFFebeb42%d|r (|cFFebeb42%.1f%%|r)", PFT.sessionTotal, goal, percentage))
        Print(string.format("Est. Value: |cFFebeb42%.2fg|r", totalValue))
        if PFT.cheapestPrice > 0 then
            Print(string.format("AH Cheapest: |cFFebeb42%.2fg|r", PFT.cheapestPrice))
        end

    elseif command == "set" then
        local option = args[2]
        local value = tonumber(args[3]) or args[3] -- Keep value as string if it's not a number

        if option == "goal" and tonumber(value) and value > 0 then
            PaulFarmTrackerDB.goal = value
            PFT.goalReached = PFT.sessionTotal >= PaulFarmTrackerDB.goal
            Print(string.format("Goal updated to |cFFebeb42%d|r.", value))
        elseif option == "price" and tonumber(value) and value >= 0 then
            PaulFarmTrackerDB.price = value
            Print(string.format("Price per item updated to |cFFebeb42%.2fg|r.", value))
        elseif option == "total" and tonumber(value) and value >= 0 then
            PFT.sessionTotal = value
            PFT.lastPrintedTotal = value
            PFT.goalReached = PFT.sessionTotal >= PaulFarmTrackerDB.goal
            Print(string.format("Session total manually set to |cFFebeb42%d|r.", value))
        elseif option == "itemid" and tonumber(value) and value >= 0 then
            PaulFarmTrackerDB.itemId = value
            local newItemName = GetItemInfo(value)
            if newItemName then
                PaulFarmTrackerDB.itemName = newItemName
                Print(string.format("New item set to: |cFFebeb42%s|r (%d)", newItemName, value))
            else
                Print(string.format("New itemId set to |cFFebeb42%d|r. Name will update shortly.", value))
            end
        else
            Print("Invalid set command. Use: /pft set [goal|price|total|itemid] [number]")
        end
        PFT:UpdateDisplay() -- MODIFIED: Update display after any 'set' command

    elseif command == "reset" then
        PFT.sessionTotal = 0
        PFT.lastPrintedTotal = 0
        PFT.goalReached = false
        Print("Session total has been reset to 0.")
        PFT:UpdateDisplay() -- MODIFIED: Update display after reset
    
    -- NEW: Commands to show/hide the UI
    elseif command == "show" then
        PFT_MainFrame:Show()
        PaulFarmTrackerDB.isShown = true
        Print("Tracker window shown.")
        
    elseif command == "hide" then
        PFT_MainFrame:Hide()
        PaulFarmTrackerDB.isShown = false
        Print("Tracker window hidden.")

    elseif command == "swap" then
        PFT:SwapGloves()

    elseif command == "setgloves" then
        local setName = args[2]
        if not setName then
            Print("Usage: /pft setgloves [set_name]")
            return
        end

        if PFT.gloveSets[setName] then
            PaulFarmTrackerDB.activeGloveSet = setName
            Print(string.format("Active glove set changed to: |cFFebeb42%s|r", setName))
            PFT:UpdateDisplay()
        else
            Print(string.format("Error: Set '|cffff0000%s|r' not found in configuration.", setName))
        end

    elseif command == "listgloves" then
        Print("Available Glove Sets:")
        for name, set in pairs(PFT.gloveSets) do
            local itemsLine = ""
            for i, data in ipairs(set) do
                local label = data.label or ("ID:" .. data.id)
                itemsLine = itemsLine .. (i > 1 and " / " or "") .. label
            end
            Print(string.format("- |cFFebeb42%s|r: %s", name, itemsLine))
        end

    elseif command == "help" then
        Print("Available Commands:")
        Print("|cff00ff00/pft|r |cFFebeb42status|r - Shows current farming progress.")
        Print("|cff00ff00/pft|r |cFFebeb42set goal [number]|r - Sets your farming goal.")
        Print("|cff00ff00/pft|r |cFFebeb42set price [number]|r - Sets the price per item.")
        Print("|cff00ff00/pft|r |cFFebeb42set total [number]|r - Manually sets the current session count.")
        Print("|cff00ff00/pft|r |cFFebeb42set itemid [number]|r - Change/set the ID of the item to be tracked.")
        Print("|cff00ff00/pft|r |cFFebeb42reset|r - Resets the current session's count to 0.")
        Print("|cff00ff00/pft|r |cFFebeb42show|r/|cFFebeb42hide|r - Shows or hides the tracker window.")
        Print("|cff00ff00/pft|r |cFFebeb42swap|r - Swaps between your two defined glove sets.")
        Print("|cff00ff00/pft|r |cFFebeb42setgloves [name]|r - Selects which glove set to use.")
        Print("|cff00ff00/pft|r |cFFebeb42listgloves|r - Lists all configured glove sets.")
        Print("|cff00ff00/pft|r |cFFebeb42findgloves|r - Scans bags for glove IDs.")

	elseif command == "findgloves" then
		PFT:FindGloves()

	elseif command == "debug" then
		Print(string.format("sessionTotal: %d, lastPrintedTotal: %d.", PFT.sessionTotal, PFT.lastPrintedTotal));
		local activeSetName = PaulFarmTrackerDB.activeGloveSet or "default"
		local activeSet = PFT.gloveSets[activeSetName]
		if activeSet then
			Print(string.format("Active Set (|cFFebeb42%s|r):", activeSetName))
			for i, data in ipairs(activeSet) do
				Print(string.format("  %d: %s (ID: %d)", i, data.label or "No Label", data.id))
			end
		end

    else
        Print(string.format("Unknown command: '%s'. Type |cFFebeb42/pft help.|r", command))
    end
end