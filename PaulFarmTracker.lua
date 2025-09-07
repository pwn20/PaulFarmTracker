-- ============================================================================
-- PaulFarmTracker Addon
-- ============================================================================

local addonName, addon = ...
local PFT = {}

-- ============================================================================
-- Configuration & Session Data
-- ============================================================================

PFT.chatPrefix = "|cff3399ff[PFT]|r "
PFT.sessionTotal = 0
PFT.lastPrintedTotal = 0 -- NEW: Tracks the total when the last update was printed.
PFT.goalReached = false

local function Print(message)
    print(PFT.chatPrefix .. message)
end

-- ============================================================================
-- Core Functions
-- ============================================================================

function PFT:ScanBagsForItem(itemId)
    return C_Item.GetItemCount(itemId)
end

-- ============================================================================
-- Event Handling
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        PFT:OnAddonLoaded()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "LOOT_OPENED" then
        PFT:OnLootOpened()
    end
end)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("LOOT_OPENED")

function PFT:OnAddonLoaded()
    PaulFarmTrackerDB = PaulFarmTrackerDB or {
        itemId = 168649,
        itemName = "Dredged Leather",
        price = 0,
        goal = 1000
    }

    local initialCount = PFT:ScanBagsForItem(PaulFarmTrackerDB.itemId)
    PFT.sessionTotal = initialCount
    PFT.lastPrintedTotal = initialCount -- MODIFIED: Initialize the last printed total.
    
    SlashCmdList["PFT"] = PFT.SlashCmdHandler
    SLASH_PFT1 = "/pft"

    Print("PaulFarmTracker loaded. Type /pft help for commands.")
    -- Print(string.format("Found %d %s in your bags to start.", initialCount, PaulFarmTrackerDB.itemName))
end

-- MODIFIED: This is the main logic change for your request.
function PFT:OnLootOpened()
    if not IsModifiedClick("AUTOLOOTTOGGLE") then
        local numLootItems = GetNumLootItems()
        for i = 1, numLootItems do
            local itemLink = GetLootSlotLink(i)
            if itemLink then
                local _, _, quantity = GetLootSlotInfo(i)
                local lootedItemId = GetItemInfoFromHyperlink(itemLink)

                if lootedItemId == PaulFarmTrackerDB.itemId then
                    -- First, update the session total as usual.
                    PFT.sessionTotal = PFT.sessionTotal + quantity

                    -- NEW LOGIC: Check if we have crossed the 100-item threshold.
                    if PFT.sessionTotal >= PFT.lastPrintedTotal + 100 then
                        local totalValue = PFT.sessionTotal * PaulFarmTrackerDB.price                     
                        local status = string.format("Update: %d / %d (Est. Value: |cFFebeb42%.2fg|r)", PFT.sessionTotal, PaulFarmTrackerDB.goal, totalValue)
                        Print(status)
                        
                        -- Crucially, update the last printed total to the current total.
                        PFT.lastPrintedTotal = PFT.sessionTotal
                    end

                    -- The goal reached message is a separate check and still fires once.
                    if PFT.sessionTotal >= PaulFarmTrackerDB.goal and not PFT.goalReached then
                        Print(string.format("|cff00ff00GOAL REACHED!|r You have farmed |cFFebeb42%s|r / |cFFebeb42%d|r %s!", PFT.sessionTotal, PaulFarmTrackerDB.goal, PaulFarmTrackerDB.itemName))
                        PFT.goalReached = true
                    end
                end
            end
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
        
        Print(string.format("Tracking: |cFFebeb42%s|r", PaulFarmTrackerDB.itemName))
        Print(string.format("Session: |cFFebeb42%d|r / |cFFebeb42%d|r (|cFFebeb42%.1f%%|r)", PFT.sessionTotal, goal, percentage))
        Print(string.format("Est. Value: |cFFebeb42%.2fg|r", totalValue))

    elseif command == "set" then
        local option = args[2]
        local value = tonumber(args[3])

        if option == "goal" and value and value > 0 then
            PaulFarmTrackerDB.goal = value
            PFT.goalReached = PFT.sessionTotal >= PaulFarmTrackerDB.goal
            Print(string.format("Goal updated to |cFFebeb42%d|r.", value))
        elseif option == "price" and value and value >= 0 then
            PaulFarmTrackerDB.price = value
            Print(string.format("Price per item updated to |cFFebeb42%.2fg|r.", value))
        elseif option == "total" and value and value >= 0 then
            PFT.sessionTotal = value
            PFT.lastPrintedTotal = value -- MODIFIED: Update last printed total on manual set.
            PFT.goalReached = PFT.sessionTotal >= PaulFarmTrackerDB.goal
            Print(string.format("Session total manually set to |cFFebeb42%d|r.", value))
        else
            Print("Invalid set command. Use: /pft set [goal|price|total] [number]")
        end

    elseif command == "reset" then
        PFT.sessionTotal = 0
        PFT.lastPrintedTotal = 0 -- MODIFIED: Reset the last printed total as well.
        PFT.goalReached = false
        Print("Session total has been reset to 0.")

    elseif command == "help" then
        Print("Available Commands:")
        Print("|cff00ff00/pft|r |cFFebeb42status|r - Shows current farming progress.")
        Print("|cff00ff00/pft|r |cFFebeb42set goal [number]|r - Sets your farming goal.")
        Print("|cff00ff00/pft|r |cFFebeb42set price [number]|r - Sets the price per item.")
        Print("|cff00ff00/pft|r |cFFebeb42set total [number]|r - Manually sets the current session count.")
        Print("|cff00ff00/pft|r |cFFebeb42reset|r - Resets the current session's count to 0.")

	elseif command == "debug" then
		Print(string.format("sessionTotal: %d, lastPrintedTotal: %d.", PFT.sessionTotal, PFT.lastPrintedTotal));

    else
        Print(string.format("Unknown command: '%s'. Type |cFFebeb42/pft help.|r", command))
    end
end