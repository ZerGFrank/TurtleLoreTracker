-- TurtleLoreTracker.lua
-- Lorekeeper helper for Turtle WoW
-- Requires: pfQuest + pfQuest-turtle

local ADDON_NAME = "TurtleLoreTracker"

-- local refs for tiny perf / clarity
local pairs, ipairs, type, tonumber, tostring = pairs, ipairs, type, tonumber, tostring
local floor = math.floor

TurtleLoreTrackerDB = TurtleLoreTrackerDB or {}

local frame = CreateFrame("Frame")
local enabled = true
local charDB
local questIndexByZone = {}
local totalQuests = 0

-- simple prefix print
local function TLT_Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TLT:|r " .. tostring(msg))
  end
end

-- per-character DB
local function TLT_GetCharDB()
  local realm = GetRealmName() or "Unknown"
  local name = UnitName("player") or "Unknown"

  local rdb = TurtleLoreTrackerDB[realm]
  if not rdb then
    rdb = {}
    TurtleLoreTrackerDB[realm] = rdb
  end

  local cdb = rdb[name]
  if not cdb then
    cdb = { completed = {} }
    rdb[name] = cdb
  end

  cdb.completed = cdb.completed or {}
  return cdb
end

-- pfQuest / pfQuest-turtle presence & db sanity
local function TLT_PfQuestReady()
  return pfQuest and pfDatabase and pfDB
     and pfDB["quests"] and pfDB["quests"]["loc"]
end

-- import pfQuest_history into our DB
local function TLT_SyncFromPfQuestHistory()
  if not TLT_PfQuestReady() then return end
  if not pfQuest_history then return end
  if not charDB then return end

  local completed = charDB.completed
  for qid, _ in pairs(pfQuest_history) do
    local id = tonumber(qid)
    if id then
      completed[id] = true
    end
  end
end

-- build: zoneKey -> { quests = { [id] = title }, completed = n }
-- notes:
-- - Uses pfDB["quests"]["loc"] for titles.
-- - Tries to derive a "zone/sort" from pfDB["quests"]["data"][id].
-- - Falls back to "Unknown" when structure isn't obvious.
local function TLT_BuildQuestIndex()
  questIndexByZone = {}
  totalQuests = 0

  if not TLT_PfQuestReady() then
    return
  end

  local loc = pfDB["quests"]["loc"]
  if not loc then return end

  local data = pfDB["quests"]["data"]
  local zonesLoc = pfDB["zones"] and pfDB["zones"]["loc"]

  for qid, entry in pairs(loc) do
    local id = tonumber(qid)
    if id then
      local title = (type(entry) == "table" and (entry.T or entry[1])) or ("Quest " .. id)
      local zoneKey = "Unknown"

      if data and data[id] then
        local d = data[id]

        -- pfQuest DB uses compact encodings; we keep this intentionally loose
        if type(d) == "table" then
          local sort = d[1]
          if zonesLoc and sort and zonesLoc[sort] then
            zoneKey = zonesLoc[sort]
          elseif sort then
            zoneKey = tostring(sort)
          end
        end
        -- if it's a string encoding, we skip parsing to stay robust
      end

      if not questIndexByZone[zoneKey] then
        questIndexByZone[zoneKey] = { quests = {}, completed = 0 }
      end

      questIndexByZone[zoneKey].quests[id] = title
      totalQuests = totalQuests + 1
    end
  end

  -- count completed per-zone based on our completed set
  local completed = charDB and charDB.completed or {}
  for zone, info in pairs(questIndexByZone) do
    local c = 0
    for id in pairs(info.quests) do
      if completed[id] then
        c = c + 1
      end
    end
    info.completed = c
  end
end

-- total progress
local function TLT_GetProgress()
  local completed = 0
  local completedSet = charDB and charDB.completed or {}

  for _, done in pairs(completedSet) do
    if done then completed = completed + 1 end
  end

  local pct = 0
  if totalQuests > 0 then
    pct = floor((completed / totalQuests) * 100)
  end

  return completed, totalQuests, pct
end

-- ===== UI =====

local ui = {
  frame = nil,
  summary = nil,
  scroll = nil,
  rows = {},
  rowsCount = 12,
}

local function TLT_ShowMissingOnMap(zoneKey)
  if not TLT_PfQuestReady() then
    TLT_Print("pfQuest not ready, cannot show quests on map.")
    return
  end

  local bucket = questIndexByZone[zoneKey]
  if not bucket then return end

  local completed = charDB.completed
  local added = 0

  if pfDatabase and pfDatabase.SearchQuestID then
    for id, _ in pairs(bucket.quests) do
      if not completed[id] and not (pfQuest.questlog and pfQuest.questlog[id]) then
        pfDatabase:SearchQuestID(id, { ["addon"] = "TLT" })
        added = added + 1
      end
    end
  end

  if added > 0 then
    TLT_Print("Showing " .. added .. " missing quests in " .. zoneKey .. " via pfQuest.")
  else
    TLT_Print("No missing quests found for " .. zoneKey .. ".")
  end
end

local function TLT_GetSortedZones()
  local list = {}
  local completed = charDB.completed

  for zone, info in pairs(questIndexByZone) do
    local total = 0
    for _ in pairs(info.quests) do total = total + 1 end

    local missing = total - (info.completed or 0)
    list[table.getn(list) + 1] = {
      zone = zone,
      total = total,
      completed = info.completed or 0,
      missing = missing,
    }
  end

  table.sort(list, function(a, b)
    -- prioritize zones with more missing quests
    if a.missing ~= b.missing then
      return a.missing > b.missing
    end
    return (a.zone or "") < (b.zone or "")
  end)

  return list
end

function TurtleLoreTracker_RefreshRows()
  if not ui.frame or not ui.frame:IsShown() then return end

  local zones = TLT_GetSortedZones()
  local numZones = table.getn(zones)

  FauxScrollFrame_Update(ui.scroll, numZones, ui.rowsCount, 18)

  local offset = FauxScrollFrame_GetOffset(ui.scroll)

  for i = 1, ui.rowsCount do
    local row = ui.rows[i]
    local index = i + offset
    local data = zones[index]

    if data then
      row.zoneKey = data.zone

      local color
      if data.missing > 0 then
        color = "|cffff8080" -- red-ish for missing
      else
        color = "|cff80ff80" -- green for complete
      end

      row.text:SetText(string.format(
        "%s%s|r  -  %d / %d  (missing %d)",
        color, data.zone or "Unknown",
        data.completed, data.total, data.missing
      ))
      row:Show()
    else
      row.zoneKey = nil
      row.text:SetText("")
      row:Hide()
    end
  end
end

function TurtleLoreTracker_UpdateUI()
  if not ui.frame then return end
  local done, total, pct = TLT_GetProgress()
  ui.summary:SetText(
    string.format("Lorekeeper Progress: |cff33ff99%d|r / %d  (%d%%)", done, total, pct)
  )
  TurtleLoreTracker_RefreshRows()
end

local function TLT_CreateUI()
  if ui.frame then return end

  local frame = CreateFrame("Frame", "TurtleLoreTrackerFrame", UIParent)
  frame:SetWidth(260)
  frame:SetHeight(320)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() this:StartMoving() end)
  frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  frame:Hide()

  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0, 0, 0, 0.85)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", frame, "TOP", 0, -10)
  title:SetText("Turtle Lore Tracker")

  local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  summary:SetPoint("TOP", title, "BOTTOM", 0, -6)
  summary:SetText("...")

  local scroll = CreateFrame("ScrollFrame", "TurtleLoreTrackerScroll", frame, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -40)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 40)

  local rows = {}
  local rowsCount = ui.rowsCount

  for i = 1, rowsCount do
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(18)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -40 - (i - 1) * 18)
    row:SetPoint("RIGHT", frame, "RIGHT", -30, 0)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetAllPoints()
    row.text:SetJustifyH("LEFT")

    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:GetHighlightTexture():SetAlpha(0.25)

    row:SetScript("OnClick", function()
      if row.zoneKey then
        TLT_ShowMissingOnMap(row.zoneKey)
      end
    end)

    rows[i] = row
  end

  -- 1.12-compatible scroll handling
  scroll:SetScript("OnVerticalScroll", function()
    FauxScrollFrame_OnVerticalScroll(this, arg1, 18, TurtleLoreTracker_RefreshRows)
  end)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)

  local resync = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  resync:SetWidth(80)
  resync:SetHeight(18)
  resync:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
  resync:SetText("Resync")
  resync:SetScript("OnClick", function()
    TLT_SyncFromPfQuestHistory()
    TLT_BuildQuestIndex()
    TurtleLoreTracker_UpdateUI()
    TLT_Print("Synced with pfQuest history.")
  end)

  local help = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  help:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 10)
  help:SetText("Click a zone to show missing via pfQuest")

  ui.frame = frame
  ui.summary = summary
  ui.scroll = scroll
  ui.rows = rows
  ui.rowsCount = rowsCount
end

-- ===== Slash commands =====

SLASH_TURTLELORETRACKER1 = "/tlt"
SLASH_TURTLELORETRACKER2 = "/turtlelore"

SlashCmdList["TURTLELORETRACKER"] = function(msg)
  msg = msg and string.lower(msg) or ""

  if msg == "" or msg == "show" or msg == "toggle" then
    if not TLT_PfQuestReady() then
      TLT_Print("pfQuest + pfQuest-turtle required.")
      return
    end
    if not ui.frame then
      TLT_CreateUI()
      TurtleLoreTracker_UpdateUI()
    end
    if ui.frame:IsShown() then
      ui.frame:Hide()
    else
      ui.frame:Show()
      TurtleLoreTracker_UpdateUI()
    end

  elseif msg == "resync" or msg == "sync" then
    if not TLT_PfQuestReady() then
      TLT_Print("pfQuest not ready; cannot resync.")
      return
    end
    TLT_SyncFromPfQuestHistory()
    TLT_BuildQuestIndex()
    TurtleLoreTracker_UpdateUI()
    TLT_Print("Synced with pfQuest history.")

  else
    TLT_Print("Usage: /tlt [show|resync]")
  end
end

-- ===== Events =====

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_SYSTEM") -- we don't parse it; pfQuest does, we just sync

frame:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    charDB = TLT_GetCharDB()

  elseif event == "PLAYER_LOGIN" then
    charDB = charDB or TLT_GetCharDB()

    if not TLT_PfQuestReady() then
      enabled = false
      TLT_Print("pfQuest + pfQuest-turtle not detected. Tracker idle.")
      return
    end

    enabled = true
    TLT_SyncFromPfQuestHistory()
    TLT_BuildQuestIndex()
    TLT_CreateUI()
    TurtleLoreTracker_UpdateUI()
    TLT_Print("Loaded. Use /tlt to view Lorekeeper progress.")

  elseif not enabled then
    return

  elseif event == "QUEST_LOG_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
    -- pfQuest updates pfQuest_history asynchronously; we just mirror
    TLT_SyncFromPfQuestHistory()
    TLT_BuildQuestIndex()
    TurtleLoreTracker_UpdateUI()

  elseif event == "CHAT_MSG_SYSTEM" then
    -- pfQuest already listens; our regular sync will pick up any changes.
  end
end)