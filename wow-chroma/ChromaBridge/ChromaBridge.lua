--[[
Chroma Bridge (World of Warcraft addon)

WHY THIS EXISTS
  WoW addons run inside a locked-down Lua sandbox. They cannot open files, sockets or
  other programs, so an addon has no direct way to tell Razer's software what is
  happening in the game. What an addon *can* do is draw on the screen. This addon draws
  a tiny strip of colored pixels in the bottom-left corner, and the companion script
  chroma-bridge.ps1 takes a screenshot of just those pixels about 20 times a second,
  decodes them and drives the Razer Chroma lighting.

STRIP LAYOUT
  128 x 6 physical screen pixels, placed 8 px in from the bottom-left corner of the game
  window. X positions are counted from the strip's left edge. This layout is the "protocol"
  between the two halves: if you change it here, change chroma-bridge.ps1 (Read-Strip) too.

    x   0-5    start marker, magenta (255,0,255)  lets the bridge confirm it found the strip
    x   6-7    black gap
    x   8-107  health bar, 100 px: white fill on black, number of white pixels = health %
    x 108-109  black gap
    x 110-115  flags A, one flag per color channel:
                 R = in combat, G = dead or ghost, B = mounted
    x 116-121  flags B:
                 R = faction (255 Alliance, 128 Horde, 0 neither)
                 G = level-up flash (on for 2.5 seconds after dinging)
                 B = resting (in an inn or a city)
    x 122-127  end marker, cyan (0,255,255)

  Each block is 6 px wide so the bridge can sample its middle and ignore slightly blurred edges.

WOW ADDON BASICS USED BELOW
  * The .toc file next to this one tells WoW the addon's name and which Lua files to load.
  * A "frame" is WoW's basic UI object (like a <div>). Frames can hold "textures"
    (colored rectangles or images) and receive "events" from the game.
  * Positions and sizes are in UI units, not pixels. A frame's "scale" converts between them.
  * OnUpdate runs a function every rendered frame; OnEvent runs one when a registered
    game event fires (for example PLAYER_LEVEL_UP).
]]

local WIDTH, HEIGHT = 128, 6  -- strip size in physical pixels (see layout above)
local MARGIN = 8              -- distance from the window's bottom-left corner, in physical pixels
local THROTTLE = 0.05         -- seconds between updates (20 per second, matching the bridge's default)
local LEVEL_UP_SECONDS = 2.5  -- how long the level-up flag stays on

local PREFIX = "|cff00ffffChroma Bridge|r: " -- "|cffRRGGBB...|r" colors text in WoW's chat window

-------------------------------------------------------------------------------
-- The strip frame
-------------------------------------------------------------------------------

-- Created with no parent (rather than as a child of UIParent) so it stays visible when the
-- player hides the interface with Alt+Z. The global name "ChromaBridgeFrame" makes it easy
-- to inspect with /fstack or /dump.
local frame = CreateFrame("Frame", "ChromaBridgeFrame")

-- Strata and level control what draws on top of what. TOOLTIP is the highest normal strata,
-- so tooltips, chat bubbles and other addons' windows don't cover the strip.
frame:SetFrameStrata("TOOLTIP")
frame:SetFrameLevel(9000)
frame:SetSize(WIDTH, HEIGHT)

-- Anchored to WorldFrame (the full game viewport). The bottom-left corner is used because
-- overlays such as Razer Cortex's FPS counter usually sit along the top of the screen.
-- The margin matters in windowed mode on Windows 11, which rounds the window's corners.
frame:SetPoint("BOTTOMLEFT", WorldFrame, "BOTTOMLEFT", MARGIN, MARGIN)

-- Adds a solid-color rectangle to the strip. x and width are in strip pixels; r, g, b are 0-1.
-- Layers order textures within a frame: BACKGROUND draws beneath ARTWORK.
local function Rect(x, width, r, g, b, layer)
  local t = frame:CreateTexture(nil, layer or "ARTWORK")
  t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
  t:SetSize(width, HEIGHT)
  t:SetColorTexture(r, g, b, 1)
  return t
end

Rect(0, WIDTH, 0, 0, 0, "BACKGROUND") -- black backing for the whole strip (also fills the gaps)
Rect(0, 6, 1, 0, 1)                   -- start marker (magenta)
local flagsA = Rect(110, 6, 0, 0, 0)  -- recolored by Refresh()
local flagsB = Rect(116, 6, 0, 0, 0)  -- recolored by Refresh()
Rect(122, 6, 0, 1, 1)                 -- end marker (cyan)

-- The health bar is a StatusBar: a built-in widget that fills a fraction of its width
-- based on a value between a min and a max. WHITE8X8 is a plain white texture that ships with WoW.
local bar = CreateFrame("StatusBar", nil, frame)
bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, 0)
bar:SetSize(100, HEIGHT)
bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
bar:SetStatusBarColor(1, 1, 1, 1)
bar:SetMinMaxValues(0, 1)
bar:SetValue(0)

-------------------------------------------------------------------------------
-- Pixel-exact scaling
-------------------------------------------------------------------------------

-- WoW's UI coordinate system is always 768 units tall, whatever the real screen resolution.
-- Setting the frame's scale to 768 / (physical screen height) makes one UI unit equal exactly
-- one physical pixel, so the strip is always 128x6 real pixels and lands where the bridge
-- expects it, regardless of resolution or the player's UI Scale setting. (This works because
-- the frame has no parent, so no other scale is multiplied in.)
local function FixScale()
  local _, physicalHeight = GetPhysicalScreenSize()
  if physicalHeight and physicalHeight > 0 then
    frame:SetScale(768 / physicalHeight)
  end
end

-------------------------------------------------------------------------------
-- Writing game state into the strip
-------------------------------------------------------------------------------

local levelUpUntil = 0 -- GetTime() value until which the level-up flag stays on

local function Refresh()
  -- Health goes straight into the StatusBar with no math or comparisons of our own. Newer
  -- Retail builds can hand addons "secret" health values in combat: a StatusBar can still
  -- display them, but doing arithmetic on them or comparing them throws an error. pcall
  -- ("protected call") swallows any error so one bad update can't spam the error window.
  pcall(bar.SetMinMaxValues, bar, 0, UnitHealthMax("player"))
  pcall(bar.SetValue, bar, UnitHealth("player"))

  -- Flags A: each color channel is fully on (1) or off (0).
  -- IsMounted and IsResting are checked for existence first in case a client lacks them.
  local combat = UnitAffectingCombat("player") and 1 or 0
  local dead = UnitIsDeadOrGhost("player") and 1 or 0
  local mounted = (IsMounted and IsMounted()) and 1 or 0
  flagsA:SetColorTexture(combat, dead, mounted, 1)

  -- Flags B: faction uses three levels of the red channel (1, 0.5, 0) so one block can hold it.
  local faction = UnitFactionGroup("player")
  local factionValue = (faction == "Alliance" and 1) or (faction == "Horde" and 0.5) or 0
  local levelUp = (GetTime() < levelUpUntil) and 1 or 0
  local resting = (IsResting and IsResting()) and 1 or 0
  flagsB:SetColorTexture(factionValue, levelUp, resting, 1)
end

-- OnUpdate fires once per rendered frame (often 60-240 times a second), so count elapsed time
-- and only refresh every THROTTLE seconds. WoW stops calling OnUpdate while the frame is
-- hidden, so "/chromabridge hide" also stops all of this work.
local elapsedSince = 0
frame:SetScript("OnUpdate", function(_, elapsed)
  elapsedSince = elapsedSince + elapsed
  if elapsedSince >= THROTTLE then
    elapsedSince = 0
    Refresh()
  end
end)

-------------------------------------------------------------------------------
-- Game events
-------------------------------------------------------------------------------

-- PLAYER_ENTERING_WORLD: login, /reload and every loading screen.
-- DISPLAY_SIZE_CHANGED / UI_SCALE_CHANGED: resolution or UI Scale changed, so recompute scale.
-- PLAYER_LEVEL_UP: the player just gained a level.
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
frame:RegisterEvent("UI_SCALE_CHANGED")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LEVEL_UP" then
    levelUpUntil = GetTime() + LEVEL_UP_SECONDS
  else
    FixScale()
  end
end)

FixScale()

-------------------------------------------------------------------------------
-- Slash command: /chromabridge [show | hide | levelup]
-------------------------------------------------------------------------------

-- WoW registers slash commands through globals: SLASH_<NAME>1 is the command text and
-- SlashCmdList[<NAME>] is the function that receives whatever was typed after it.
SLASH_CHROMABRIDGE1 = "/chromabridge"
SlashCmdList.CHROMABRIDGE = function(msg)
  msg = strtrim((msg or ""):lower())
  if msg == "hide" then
    -- With the strip gone the bridge stops seeing it and hands the lights back after ~2 s.
    frame:Hide()
    print(PREFIX .. "strip hidden, lighting released. It comes back after /reload or /chromabridge show.")
  elseif msg == "show" then
    frame:Show()
    print(PREFIX .. "strip shown.")
  elseif msg == "levelup" then
    levelUpUntil = GetTime() + LEVEL_UP_SECONDS
    print(PREFIX .. "test level-up flash.")
  else
    local _, h = GetPhysicalScreenSize()
    print((PREFIX .. "strip %s, scale %.3f for a %d px tall screen. Commands: /chromabridge show | hide | levelup")
      :format(frame:IsShown() and "shown" or "hidden", frame:GetScale(), h or 0))
  end
end
