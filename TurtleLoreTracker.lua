-- Turtle Lore Tracker
-- Turtle WoW 1.12 / Lua 5.0
-- Depends on: pfQuest + pfQuest-turtle

local function TLT_Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TLT:|r " .. tostring(msg))
  end
end

-- ############################################################
-- SavedVariables
-- ############################################################

TurtleLoreTrackerDB = TurtleLoreTrackerDB or {}
local db
local totalQuests = 0

local function TLT_InitDB()
  if type(TurtleLoreTrackerDB) ~= "table" then
    TurtleLoreTrackerDB = {}
  end
  if type(TurtleLoreTrackerDB.completed) ~= "table" then
    TurtleLoreTrackerDB.completed = {}
  end
  if type(TurtleLoreTrackerDB.importedOnce) ~= "boolean" then
    TurtleLoreTrackerDB.importedOnce = false
  end
  db = TurtleLoreTrackerDB
end

-- ############################################################
-- pfQuest helpers
-- ############################################################

local function TLT_PfQuestReady()
  return pfDB and pfDB["quests"]
end

-- One-time import from pfQuest_history into our own DB
local function TLT_ImportPfQuestHistory()
  if not db or db.importedOnce then return end
  if type(pfQuest_history) ~= "table" then return end

  local completed = db.completed
  for qid, _ in pairs(pfQuest_history) do
    local id = tonumber(qid)
    if id then
      completed[id] = true
    end
  end

  db.importedOnce = true
end

-- Count how many quests exist in pfQuest's DB
local function TLT_BuildQuestCount()
  totalQuests = 0
  if not TLT_PfQuestReady() then return end

  local q = pfDB["quests"]
  local src = q["data"] or q["enUS"] or q["loc"] or q

  if type(src) ~= "table" then return end

  for id, _ in pairs(src) do
    if type(id) == "number" then
      totalQuests = totalQuests + 1
    end
  end
end

-- How many completions we know about (client-side)
local function TLT_CountCompleted()
  if not db or type(db.completed) ~= "table" then return 0 end
  local c = 0
  for _, v in pairs(db.completed) do
    if v then c = c + 1 end
  end
  return c
end

-- ############################################################
-- UI (lazy-created)
-- ############################################################

local uiFrame, progressFS, infoFS, bodyFS, resyncBtn

local function TLT_UpdateDisplay()
  if not uiFrame then return end

  if not db then
    progressFS:SetText("Database not ready.")
    infoFS:SetText("")
    bodyFS:SetText("")
    return
  end

  if totalQuests == 0 then
    progressFS:SetText("pfQuest data not ready.")
    infoFS:SetText("")
    bodyFS:SetText("Make sure pfQuest and pfQuest-turtle are enabled,\nthen click |cffffffffResync|r.")
    return
  end

  local done = TLT_CountCompleted()
  if done > totalQuests then
    done = totalQuests
  end

  local pct = 0
  if totalQuests > 0 then
    pct = math.floor((done / totalQuests) * 1000) / 10 -- 1 decimal place
  end

  local missing = totalQuests - done

  progressFS:SetText(string.format(
    "Lorekeeper Progress: |cff00ff00%d|r / %d (%.1f%%)",
    done, totalQuests, pct
  ))

  infoFS:SetText(string.format(
    "Client-tracked completions. Missing (not known here): |cffff6666%d|r",
    missing
  ))

  bodyFS:SetText(
    "What this addon does:\n" ..
    "• Counts quests from pfQuest.\n" ..
    "• On |cffffffffResync|r, imports known completed quest IDs\n" ..
    "  from pfQuest_history into its own database.\n" ..
    "• Your Lorekeeper data here survives if you clear or break pfQuest.\n\n" ..
    "Why it may not match /played:\n" ..
    "• 1.12 offers no full quest-history API to addons.\n" ..
    "• Quests done before pfQuest/TLT or after wipes may be missing.\n\n" ..
    "How to use for a Lorekeeper run:\n" ..
    "1) Keep pfQuest enabled.\n" ..
    "2) Quest normally.\n" ..
    "3) Press |cffffffffResync|r occasionally to lock progress into TLT."
  )
end

local function TLT_CreateUI()
  if uiFrame then return end

  local frame = CreateFrame("Frame", "TurtleLoreTrackerFrame", UIParent)
  uiFrame = frame

  frame:SetWidth(360)
  frame:SetHeight(260)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() this:StartMoving() end)
  frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  frame:Hide()

  frame:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile     = true,
    tileSize = 16,
    edgeSize = 16,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0, 0, 0, 0.9)

  -- Title
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", frame, "TOP", 0, -10)
  title:SetText("Turtle Lore Tracker")

  -- Progress line
  progressFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  progressFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -40)
  progressFS:SetJustifyH("LEFT")

  -- Info line
  infoFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  infoFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -60)
  infoFS:SetJustifyH("LEFT")

  -- Body text (give it a bit more space above the hint)
  bodyFS = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  bodyFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -84)
  bodyFS:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 36)
  bodyFS:SetJustifyH("LEFT")
  bodyFS:SetJustifyV("TOP")
  bodyFS:SetNonSpaceWrap(true)

  -- Close button (pulled slightly inward)
  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

  -- Resync button
  resyncBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  resyncBtn:SetText("Resync")
  resyncBtn:SetWidth(80)
  resyncBtn:SetHeight(22)
  resyncBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)

  resyncBtn:SetScript("OnClick", function()
    TLT_ImportPfQuestHistory()
    TLT_BuildQuestCount()
    TLT_UpdateDisplay()
    TLT_Print("Resynced from pfQuest_history into TurtleLoreTrackerDB.")
  end)

  -- Hint text (short + fully visible)
  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("BOTTOMLEFT", resyncBtn, "BOTTOMRIGHT", 10, 2)
  hint:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
  hint:SetJustifyH("LEFT")
  hint:SetText("Resync now and then to save progress.")

  TLT_UpdateDisplay()
end

-- ############################################################
-- Events
-- ############################################################

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function()
  if event == "PLAYER_LOGIN" then
    TLT_InitDB()

    if TLT_PfQuestReady() then
      TLT_ImportPfQuestHistory()
      TLT_BuildQuestCount()
      TLT_Print("Loaded. Type /tlt to view Lorekeeper progress.")
    else
      TLT_Print("Loaded. pfQuest not ready; /tlt will still open the tracker.")
    end
  end
end)

-- ############################################################
-- Slash command
-- ############################################################

SLASH_TURTLELORETRACKER1 = "/tlt"

SlashCmdList["TURTLELORETRACKER"] = function()
  TLT_CreateUI()
  TLT_UpdateDisplay()

  if uiFrame:IsShown() then
    uiFrame:Hide()
  else
    uiFrame:Show()
  end
end
