-- Minimal WoW API mock to smoke-test CloudeMap outside the game.
-- Usage: lua mock.lua <addon dir> <variant>   (variant: "yx" = world pos vec.x is the vertical axis)
local dir, variant = ...
variant = variant or "xy"

pu, pv = 0.5, 0.5
apiMode = os.getenv('MOCK_API') or 'full'
unitFirstIsVecY = (os.getenv('MOCK_UNIT') or 'b') == 'a'
local out = {}
function print(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring((select(i, ...))) end out[#out+1] = table.concat(t, " ") end

-- generic frame / texture object -------------------------------------------------
local Obj = {}
Obj.__index = function(t, k)
    if Obj[k] then return Obj[k] end
    return function() end            -- every unknown method is a no-op
end
local created = { frames = 0, textures = 0 }
local function new(kind)
    local o = setmetatable({ kind = kind, w = 0, h = 0, shown = true, scripts = {}, points = {}, scale = 1 }, Obj)
    return o
end
function Obj:SetSize(w, h) self.w, self.h = w, h; if self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, w, h) end end
function Obj:SetWidth(w) self.w = w end
function Obj:SetHeight(h) self.h = h end
function Obj:GetSize() return self.w, self.h end
function Obj:GetWidth() return self.w end
function Obj:GetHeight() return self.h end
function Obj:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function Obj:Hide() self.shown = false end
function Obj:IsShown() return self.shown end
function Obj:SetScript(n, f) self.scripts[n] = f end
function Obj:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Obj:ClearAllPoints() self.points = {} end
function Obj:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Obj:SetScale(s) self.scale = s end
function Obj:GetEffectiveScale() return 1 end
function Obj:GetLeft() return 100 end
function Obj:GetTop() return 500 end
function Obj:GetRect() return 100, 100, self.w, self.h end
function Obj:IsMouseOver() return true end
function Obj:GetFrameLevel() return 1 end
function Obj:SetTexture(t) self.tex = t end
function Obj:SetGradient(o, a, b) self.grad = { o, a.a, b.a } end
function Obj:SetAlpha(a) self.alpha = a end
function Obj:SetRotation(r) self.rot = r end
function Obj:SetVertexColor(r,g,b,a) self.vc = {r,g,b,a} end
allTex = {}
function Obj:CreateTexture() created.textures = created.textures + 1; local t = new("tex"); allTex[#allTex+1] = t; return t end
function Obj:SetDrawLayer(l, sub) self.sub = sub end
function Obj:SetTexCoord(a,b,c,d) self.tc = {a,b,c,d} end
allFS = {}
function Obj:CreateFontString() local f = new("fs"); allFS[#allFS+1] = f; return f end
function Obj:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
function Obj:SetText(t) self.text = t end
function Obj:GetEffectiveAlpha() return 1 end

local allFrames = {}
function CreateFrame(kind, name, parent, template)
    created.frames = created.frames + 1
    local o = new("frame")
    o.parent = parent
    allFrames[#allFrames + 1] = o
    if name then _G[name] = o end
    return o
end
UIParent = new("frame"); UIParent.w, UIParent.h = 1920, 1080
function GetCursorPosition() return curX or 300, curY or 300 end
UISpecialFrames = {}
SlashCmdList = {}
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function CreateVector2D(x, y) return { x = x, y = y } end
Enum = { UIMapType = { Continent = 2, Zone = 3 } }
function debugstack() return "" end

-- fake map data -------------------------------------------------------------------
local CWc, CHc = 4096, 2731
local conts = {
    [1414] = { inst = 1, name = "Kalimdor",         rect = { -761 / CWc, (-761 + 3359) / CWc, 185 / CHc, (185 + 2240) / CHc }, hx = { 19200, -19200 }, vy = { 12800, -12800 } },
    [1415] = { inst = 0, name = "Eastern Kingdoms", rect = { 1522 / CWc, (1522 + 3226) / CWc, 223 / CHc, (223 + 2151) / CHc }, hx = { 19200, -19200 }, vy = { 12800, -12800 } },
}
local zones = {}  -- zone mapID -> {parent, l,r,t,b}
local zid = 1500
local pids = {} for pid in pairs(conts) do pids[#pids+1] = pid end table.sort(pids)
for _, pid in ipairs(pids) do
    local c = conts[pid]
    c.zones = {}
    for i = 0, 23 do
        zid = zid + 1
        local col, row = i % 6, math.floor(i / 6)
        local l = 0.25 + col * 0.08
        local t = 0.1 + row * 0.2
        zones[zid] = { parent = pid, l = l, r = l + 0.14, t = t, b = t + 0.22 }
        c.zones[#c.zones + 1] = { mapID = zid }
    end
end
zones[1530] = zones[1530]  -- city sample
local cityId = 1453; zones[cityId] = { parent = 1415, l = 0.34, r = 0.39, t = 0.15, b = 0.18 }
conts[1415].zones[#conts[1415].zones + 1] = { mapID = cityId }

local function layers() return { [1] = { [1] = { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } } end
C_Map = {
    GetFallbackWorldMapID = function() return 947 end,
    GetMapInfo = function(id)
        local parent = 947
        if zones[id] then parent = zones[id].parent end
        if id == 947 then parent = 946 end
        return { name = (conts[id] and conts[id].name) or ("Map" .. id), mapID = id, parentMapID = parent }
    end,
    GetMapArtLayers = layers,
    GetMapArtLayerTextures = function(id, layer)
        local t = {} for i = 1, 12 do t[i] = id * 100 + i end return { t }
    end,
    GetMapChildrenInfo = function(id, mtype, all)
        if id == 947 then local r = {} for k in pairs(conts) do r[#r + 1] = { mapID = k } end table.sort(r, function(a, b) return a.mapID < b.mapID end) return r end
        if conts[id] then return conts[id].zones end
        return {}
    end,
    GetMapRectOnMap = function(child, parent)
        if parent == 947 then local r = conts[child].rect return r[1], r[2], r[3], r[4] end
        local z = zones[child]; return z.l, z.r, z.t, z.b
    end,
    GetWorldPosFromMapPos = function(id, v)
        local c = conts[id]
        local h = c.hx[1] + (c.hx[2] - c.hx[1]) * v.x        -- west axis, larger at left
        local vv = c.vy[1] + (c.vy[2] - c.vy[1]) * v.y       -- north axis, larger at top
        if variant == "yx" then return c.inst, { x = vv, y = h } end
        return c.inst, { x = h, y = vv }
    end,
    GetMapArtID = function(id)
        if not zones[id] then return nil end
        local ids = { 1194, 1200, 1202, 1205, 1206 }
        return ids[(id % #ids) + 1]
    end,
    GetBestMapForUnit = function() if os.getenv('MOCK_CITY') then return 1453 end return 1501 end,
    GetPlayerMapPosition = function(id)
        if apiMode == "unit" then return nil end
        return { GetXY = function() if os.getenv('MOCK_CITY') and id == 1453 then return 0.5, 0.5 end if id == 1501 then return pu, pv end return 0, 0 end }
    end,
}

C_TaxiMap = { GetTaxiNodesForMap = function(id)
    if id == 1415 then return { { nodeID = 1, name = "Stormwind", position = { x = 0.4, y = 0.5 }, faction = 1 }, { nodeID = 2, name = "Ironforge", position = { x = 0.45, y = 0.4 } } } end
    if id == 1414 then return { { nodeID = 3, name = "Orgrimmar", position = { x = 0.32, y = 0.21 } } } end
    return {}
end }
C_EncounterJournal = { GetDungeonEntrancesForMap = function(id)
    if id == 1501 then return { { name = "Deadmines", position = { x = 0.5, y = 0.5 }, atlasName = "Dungeon", journalInstanceID = 63, description = "d" } } end
    return {}
end }
C_AreaPoiInfo = { GetAreaPOIForMap = function(id) if id == 1501 then return { 7 } end return {} end,
                  GetAreaPOIInfo = function(id, pid) return { name = "Town", position = { x = 0.3, y = 0.3 }, textureIndex = 5 } end }
Enum.FlightPathFaction = { Alliance = 1, Horde = 2 }
function UnitFactionGroup() return "Alliance" end
GameTooltip = setmetatable({}, { __index = function() return function() end end })
C_MapExplorationInfo = {
    GetExploredMapTextures = function(id)
        return { { textureWidth = 300, textureHeight = 200, offsetX = 100, offsetY = 150, fileDataIDs = { 1, 2, 3, 4 } },
                 { textureWidth = 128, textureHeight = 128, offsetX = 600, offsetY = 300, fileDataIDs = { 5 } },
                 { textureWidth = 128, textureHeight = 110, offsetX = 464, offsetY = 33, fileDataIDs = { 271427 } },
                 { textureWidth = 90, textureHeight = 90, offsetX = 10, offsetY = 10, isShownByMouseOver = true, fileDataIDs = { 9 } } }
    end,
}

-- player is at zone 1501 centre; zone rect is relative to its continent
function UnitPosition()
    local z = zones[1501]; local c = conts[1414]
    local u = z.l + (z.r - z.l) * pu
    local v = z.t + (z.b - z.t) * pv
    local h = c.hx[1] + (c.hx[2] - c.hx[1]) * u
    local vv = c.vy[1] + (c.vy[2] - c.vy[1]) * v
    local vecx, vecy = h, vv
    if variant == "yx" then vecx, vecy = vv, h end
    if unitFirstIsVecY then return vecy, vecx, 0, 1 end
    return vecx, vecy, 0, 1
end
function GetPlayerFacing() return 1.0 end


-- bridge test doubles
local mockNow, tickers = 100, {}
function GetTime() mockNow = mockNow + 0.7 return mockNow end
function hooksecurefunc(t, k, fn) local o = t[k]; t[k] = function(...) local a, b, c = o(...); fn(...); return a, b, c end end
C_Timer = C_Timer or {}
C_Timer.NewTicker = function(_, fn) tickers[#tickers + 1] = fn end
local fakeTex = { GetTexture = function() return "Interface\\Foo" end, GetTexCoord = function() return 0,0,0,1,1,0,1,1 end,
                  GetVertexColor = function() return 1,1,1,1 end, GetAtlas = function() return nil end }
local entered = 0
local function fakeIcon() return { texture = fakeTex, GetWidth = function() return 16 end, GetScale = function() return 1 end,
    GetScript = function(_, n) if n == "OnEnter" then return function() entered = entered + 1 end end end } end
local hbdp = { worldmapPinRegistry = {} }
function hbdp:AddWorldMapIconMap(ref, icon, m, x, y) self.worldmapPinRegistry[ref] = self.worldmapPinRegistry[ref] or {}; self.worldmapPinRegistry[ref][icon] = { uiMapID = m } end
function hbdp:RemoveWorldMapIcon(ref, icon) self.worldmapPinRegistry[ref][icon] = nil end
C_Map.GetMapInfoAtPosition = function(m, x, y) return { mapID = 1501 } end
LibStub = setmetatable({ libs = { ["HereBeDragons-Pins-2.0"] = hbdp } }, { __call = function() return nil end })
local preIcon = fakeIcon(); preIcon.UiMapID, preIcon.x, preIcon.y = 1501, 40, 40
hbdp.worldmapPinRegistry["TomTom"] = { [preIcon] = { uiMapID = 1501 } }
local hnEntered = 0
HandyNotes = { plugins = { Treasures = {
    GetNodes2 = function(self, mapID) local done = mapID ~= 1501
        return function() if not done then done = true return 45005500, nil, { icon = "Interface\\Bar", tCoordLeft = 0, tCoordRight = 1, tCoordTop = 0, tCoordBottom = 1 }, 1.5, 1 end end end,
    OnEnter = function() hnEntered = hnEntered + 1 end } }, db = { profile = { enabledPlugins = {} } } }


Questie = {}
local qtex = { GetTexture = function() return "Interface\\AddOns\\Questie\\Icons\\available.blp" end }
QFrame1 = { x = 50, y = 50, UiMapID = 1501, texture = qtex, data = { Type = "available", Name = "Giver", QuestData = { Id = 5, name = "A Quest" } } }
QFrame2 = { x = 51, y = 51, UiMapID = 1501, texture = qtex, data = { Type = "monster", Name = "Boar", QuestData = { Id = 6, name = "Boars" }, ObjectiveData = { Description = "Slay 5" } } }
QFrame3 = { x = 52, y = 52, UiMapID = 1501, texture = qtex, hidden = true, data = { Type = "monster", QuestData = { Id = 7 } } }
QFrame4 = { x = 53, y = 53, UiMapID = 1501, texture = qtex, data = { Type = "manual", ManualTooltipData = { Title = "Mailbox", Body = {} } } }
QuestieLoader = { ImportModule = function(self, n)
    if n == "QuestieMap" then return { questIdFrames = { [5] = { "QFrame1" }, [6] = { "QFrame2", "QFrame3" } }, manualFrames = { x = { [1] = { "QFrame4" } } } } end
    return {} end }

C_QuestLog = { GetNumQuestLogEntries = function() return 3 end,
    GetInfo = function(i) return ({ { isHeader = true }, { questID = 11 }, { questID = 12 } })[i] end,
    GetQuestsOnMap = function(m) if m == 1501 then return { { questID = 11, x = 0.4, y = 0.4 }, { questID = 12, x = 0.6, y = 0.6 } } end return {} end,
    GetSelectedQuest = function() return 11 end, GetTitleForQuestID = function(q) return "Quest " .. q end,
    GetQuestObjectives = function() return { { text = "0/3 Things", finished = false } } end }

GatherMate2 = { db_types = { "Herb Gathering", "Mining" }, nodeTextures = { ["Herb Gathering"] = { [1] = "Interface\\Herb" }, Mining = {} },
    GetNodesForZone = function(self, zone, t) local i = 0 return function() i = i + 1 if zone == 1501 and i <= 3 then return 5000 * i * 1000000 + 400000, 1 end end end,
    DecodeLoc = function(self, c) return math.floor(c / 1000000) / 100000, 0.4 end, GetNameForNode = function() return "Peacebloom" end }
Spy = { NearbyList = { Bob = 1 }, ActiveList = { Bob = 1 } }
SpyPerCharDB = { PlayerData = { Bob = { mapID = 1501, mapX = 0.3, mapY = 0.3, level = 30, class = "Mage" } }, KOSData = { Bob = 1 } }
strsplit = strsplit or function(d, str) local a, b = str:match("^(.-)" .. d .. "(.*)$") return a, b end
local rsActive, rsTips = false, 0
RSEntityPinMixin = {
    ShowOverlay = function(self)
        for pin in self:GetMap():EnumeratePinsByTemplate("RSOverlayTemplate") do if pin:GetEntityID() == 1 then return end end
        rsActive = true
        for _, c in ipairs({ "2100-2200", "2300-2400" }) do
            local x, y = strsplit("-", c)
            self:GetMap():AcquirePin("RSOverlayTemplate", tonumber(x) / 10000, tonumber(y) / 10000, 1, 0, 0, self.groupPin and self.POI or self, self.groupPin)
        end
    end,
    OnMouseEnter = function(self) rsTips = rsTips + 1; assert(self.POI.name == "Rare"); assert(self.Texture and self.ShowPingAnim) ; self.tooltip = {} end,
    OnMouseLeave = function(self) self.tooltip = nil end,
    OnMouseDown = function(self, button)
        if rsActive then
            for pin in self:GetMap():EnumeratePinsByTemplate("RSOverlayTemplate") do self:GetMap():RemovePin(pin) end
            rsActive = false
        else self:ShowOverlay() end
    end }
RareScannerDataProviderMixin = { RefreshAllData = function(self)
    self:GetMap():RemoveAllPinsByTemplate("RSEntityPinTemplate")
    local map = self:GetMap()
    if map:GetMapID() == 1501 then
        local pin = map:AcquirePin("RSEntityPinTemplate", { x = 2000, y = 2000, name = "Rare", entityID = 1, Texture = "Interface\\Rare" }, self)
        pin.ShowSearchAnim:Play()
        if rsActive then pin:ShowOverlay() end
    end
    if self:GetMap():GetMapFrame():IsShown() then error("should not be shown") end
end }
RS_TEST = function() return rsTips, rsActive end
-- load the addon files ---------------------------------------------------------------
function Obj:CreateLine() local l = new("line"); allLines = allLines or {}; allLines[#allLines+1] = l; return l end
function Obj:SetStartPoint(_, _, x, y) self.sp = {x, y} end
function Obj:SetEndPoint(_, _, x, y) self.ep = {x, y} end
local subs = {}
navigated = nil
ShortestPathForeverDB = { routeColor = "cyan" }
ShortestPathForever = { API = {
    Journey = function() return { goal = { map = 1501, x = 0.8, y = 0.2, title = "Ratchet" }, index = 1, secondsLeft = 125,
        legs = { { mode = "walk", text = "Walk to the flight master", seconds = 40, from = { map = 1501, x = 0.5, y = 0.5 }, to = { map = 1501, x = 0.6, y = 0.4 } },
                 { mode = "flight", text = "Fly to Ratchet", seconds = 80, from = { map = 1501, x = 0.6, y = 0.4 }, to = { map = 1501, x = 0.8, y = 0.2 } },
                 { mode = "walk", text = "Walk to the goal", seconds = 5, from = { map = 1501, x = 0.8, y = 0.2 }, to = { map = 99999, x = 0.5, y = 0.5 } } } } end,
    Guidance = function() local w = {} for i = 0, 40 do w[#w+1] = { map = 1501, x = 0.5 + i * 0.0025, y = 0.5 - i * 0.0025 } end return { waypoints = w, index = 3, leg = 1 } end,
    Subscribe = function(cb) subs[#subs+1] = cb; return function() end end,
    Navigate = function(owner, m, x, y) navigated = ("%s %d %.3f %.3f"):format(owner, m, x, y); return true end,
} }
SPF_SUBS = subs
local ns = {}
local function load(name) local f = assert(loadfile(dir .. "/" .. name)); f("CloudeMap", ns) end
load("Tiles.lua")
load("Reveal.lua")
load("Guide.lua")
load("Pins.lua")
load("Leylines.lua")
load("Bridge.lua")
load("CloudeMap.lua")



local ev
for _, f in ipairs(allFrames) do if f.scripts.OnEvent then ev = f end end
assert(ev, "event frame not found")
ev.scripts.OnEvent(ev, "ADDON_LOADED", "CloudeMap")
ev.scripts.OnEvent(ev, "PLAYER_LOGIN")
PNS = {}
for _, n in ipairs({ "Transit.lua", "Lanes.lua", "ShortestPath.lua" }) do local f = assert(loadfile((os.getenv("PLUGIN_DIR") or (dir .. "/../CloudeMap_ShortestPath")) .. "/" .. n)); f("CloudeMap_ShortestPath", PNS) end

local view
for _, f in ipairs(allFrames) do if f.scripts.OnUpdate and f.scripts.OnMouseWheel then view = f end end
assert(view, "no OnUpdate frame: window was not created")
local function frames(n, dt) for i = 1, n do view.scripts.OnUpdate(view, dt or 0.1) end end

local function stats(tag)
    local area, n, bad = {}, {}, 0
    local amax = {}
    local dim
    for _, t in ipairs(allTex) do
        local sub, tex, c = rawget(t, "sub"), rawget(t, "tex"), rawget(t, "tc")
        if rawget(t, "shown") and sub and t.w > 0 and tex then
            n[sub] = (n[sub] or 0) + 1
            local vc = rawget(t, "vc")
            if vc and vc[1] < 0.999 then dim = dim or {}; dim[sub] = (dim[sub] or 0) + 1 end
            local a = rawget(t, "alpha") or 1
            amax[sub] = math.max(amax[sub] or 0, a)
            if c and (c[1] < -1e-9 or c[2] > 1 + 1e-9 or c[3] < -1e-9 or c[4] > 1 + 1e-9 or c[1] >= c[2] or c[3] >= c[4]) then bad = bad + 1 end
        end
    end
    local keys = {} for k in pairs(n) do keys[#keys+1] = k end table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts+1] = ("sub%d:%d(a%.2f%s)"):format(k, n[k], amax[k], (dim and dim[k]) and (" dim" .. dim[k]) or "") end
    out[#out+1] = ("%-28s %s%s"):format(tag, table.concat(parts, " "), bad > 0 and ("  BAD TEXCOORDS " .. bad) or "")
end

-- zoom ladder: wheel steps from fully out to fully in, log what is drawn
SlashCmdList.CLOUDEMAP("reset"); frames(3)
for i = 1, 40 do view.scripts.OnMouseWheel(view, -1); frames(1) end
frames(10); stats("min zoom")
for step = 1, 34 do
    view.scripts.OnMouseWheel(view, 1); frames(12)
    stats("zoom in step " .. step)
end
out[#out+1] = "--- debug at deep zoom"
SlashCmdList.CLOUDEMAP("debug")

-- modes: parchment only in map mode, satellite tiles only in satellite mode
SlashCmdList.CLOUDEMAP("map"); SlashCmdList.CLOUDEMAP("me"); frames(12)
curX, curY = 356, 344
stats("MAP   fit zone")
for i = 1, 4 do view.scripts.OnMouseWheel(view, 1); frames(10); stats("MAP   +" .. i) end
SlashCmdList.CLOUDEMAP("sat"); frames(12)
stats("SAT   same view")
for i = 1, 3 do view.scripts.OnMouseWheel(view, 1); frames(10); stats("SAT   +" .. i) end
for i = 1, 6 do view.scripts.OnMouseWheel(view, -1); frames(10) end
stats("SAT   zoomed out")
SlashCmdList.CLOUDEMAP("mode"); frames(12)
stats("MAP   back by /stitch mode")
for i = 1, 40 do view.scripts.OnMouseWheel(view, 1); frames(1) end
SlashCmdList.CLOUDEMAP("debug")
SlashCmdList.CLOUDEMAP("sat"); frames(3)
for i = 1, 40 do view.scripts.OnMouseWheel(view, 1); frames(1) end
SlashCmdList.CLOUDEMAP("debug")
curX, curY = nil, nil
SlashCmdList.CLOUDEMAP("map")

-- zoom read-out
for _, f in ipairs(allFS) do local t = rawget(f, "text") if type(t) == "string" and t:match("^zoom") then out[#out+1] = "title bar: " .. t end end

-- player marker
local mark
for _, t in ipairs(allTex) do if rawget(t, "tex") == "Interface\\Minimap\\MinimapArrow" then mark = t end end
out[#out+1] = ("marker texture found=%s shown=%s rot=%s size=%sx%s"):format(tostring(mark ~= nil), tostring(mark and mark.shown), tostring(mark and mark.rot), tostring(mark and mark.w), tostring(mark and mark.h))
if mark then
    local p = mark.points[#mark.points]
    out[#out+1] = ("marker anchor: %s %s %s"):format(tostring(p and p[1]), tostring(p and p[4]), tostring(p and p[5]))
end

-- Me button + follow
SlashCmdList.CLOUDEMAP("me"); frames(12)
stats("after Me")
curX, curY = 356, 344     -- cursor on the view centre
for step = 1, 14 do
    view.scripts.OnMouseWheel(view, 1); frames(12)
    local dbg_n = #out
    SlashCmdList.CLOUDEMAP("debug")
    local sc
    for i = dbg_n + 1, #out do local v = out[i]:match("scale ([%d%.]+) %(min") if v then sc = v end end
    for i = #out, dbg_n + 1, -1 do out[i] = nil end
    stats("player zoom +" .. step .. " (scale " .. tostring(sc) .. ")")
end
curX, curY = nil, nil
frames(2)
pu, pv = 0.8, 0.3; frames(3)   -- the player walks
local p2 = mark and mark.points[#mark.points]
out[#out+1] = ("follow (default on): marker offset after move: %s %s (view centre is 256, -156)"):format(tostring(p2 and p2[4]), tostring(p2 and p2[5]))
SlashCmdList.CLOUDEMAP("follow")
SlashCmdList.CLOUDEMAP("layer"); SlashCmdList.CLOUDEMAP("layer zone"); frames(2); stats("zone layer off")
SlashCmdList.CLOUDEMAP("fog"); SlashCmdList.CLOUDEMAP("fog 0.8"); frames(2); stats("fog 0.8"); SlashCmdList.CLOUDEMAP("layer fog"); frames(2); stats("fog layer hidden"); SlashCmdList.CLOUDEMAP("layer fog"); SlashCmdList.CLOUDEMAP("layer zone"); SlashCmdList.CLOUDEMAP("dot"); SlashCmdList.CLOUDEMAP("dot")
SlashCmdList.CLOUDEMAP("hide"); SlashCmdList.CLOUDEMAP("show"); frames(2)


if os.getenv("MOCK_SWEEP") then
    SlashCmdList.CLOUDEMAP("reset"); frames(2)
    SlashCmdList.CLOUDEMAP("me"); frames(15)
    local function focusNow()
        local n0 = #out
        SlashCmdList.CLOUDEMAP("debug")
        local f
        for i = n0 + 1, #out do local id = out[i]:match("focus zone: %[(%d+)%]") if id then f = id end end
        return f
    end
    local seq, last, changes = {}, nil, 0
    -- view spans x 104..616 (frame at 100, PAD 4); sweep right then back left, 6 frames per step
    local path = {}
    for x = 110, 610, 10 do path[#path+1] = x end
    for x = 610, 110, -10 do path[#path+1] = x end
    for _, x in ipairs(path) do
        curX, curY = x, 300
        frames(6)
        local f = focusNow()
        if f ~= last then changes = changes + 1; seq[#seq+1] = ("x=%d->%s"):format(x, tostring(f)); last = f end
    end
    out[#out+1] = ("focus changes during sweep: %d | %s"):format(changes, table.concat(seq, " "))
end

-- base parchment: off by default for zones with reveal data, on with /stitch base
do
    local function subCount(sub)
        local c = 0
        for _, t in ipairs(allTex) do
            if rawget(t, "shown") and rawget(t, "sub") == sub and t.w > 0 and rawget(t, "tex") then c = c + 1 end
        end
        return c
    end
    SlashCmdList.CLOUDEMAP("reset"); frames(2)
    SlashCmdList.CLOUDEMAP("map"); SlashCmdList.CLOUDEMAP("me"); frames(15)
    curX, curY = 356, 344
    for i = 1, 6 do view.scripts.OnMouseWheel(view, 1); frames(12) end
    out[#out+1] = ("BASE default: zone sprites (sub-1) %d, overlays (sub0/1) %d/%d"):format(subCount(-1), subCount(0), subCount(1))
    SlashCmdList.CLOUDEMAP("base"); frames(6)
    out[#out+1] = ("BASE on:      zone sprites (sub-1) %d, overlays (sub0/1) %d/%d"):format(subCount(-1), subCount(0), subCount(1))
    SlashCmdList.CLOUDEMAP("base"); frames(6)
    out[#out+1] = ("BASE off:     zone sprites (sub-1) %d"):format(subCount(-1))
    curX, curY = nil, nil
    local n0 = #out
    SlashCmdList.CLOUDEMAP("debug")
    for i = n0 + 1, #out do if out[i]:match("base parchment") then print(out[i]) end end
    for i = #out, n0 + 1, -1 do out[i] = nil end
end

-- pins
do
    local function pinBtnsShown()
        local n = 0
        for _, f in ipairs(allFrames) do if rawget(f, "pin") and f.shown then n = n + 1 end end
        return n
    end
    out[#out+1] = "=== PINS ==="
    pu, pv = 0.5, 0.5
    SlashCmdList.CLOUDEMAP("reset"); frames(2)
    SlashCmdList.CLOUDEMAP("map"); SlashCmdList.CLOUDEMAP("me"); frames(10)
    for i = 1, 8 do view.scripts.OnMouseWheel(view, -1); frames(3) end
    local n0 = #out
    SlashCmdList.CLOUDEMAP("debug")
    for i = n0 + 1, #out do if out[i]:match("pins:") then print(out[i]) end end
    for i = #out, n0 + 1, -1 do out[i] = nil end
    out[#out+1] = "pin frames shown (zoomed out): " .. pinBtnsShown()
    for i = 1, 14 do view.scripts.OnMouseWheel(view, 1); frames(3) end
    out[#out+1] = "scale check: " .. tostring(allFS[1] and "") ; for _, f in ipairs(allFS) do local t = rawget(f, "text") if type(t) == "string" and t:match("^zoom") then out[#out+1] = t end end
    out[#out+1] = "pin frames shown (zoomed in): " .. pinBtnsShown()
    do SlashCmdList.CLOUDEMAP("debug") end
    CloudeMap.SetEnabled("flight", false); frames(3)
    out[#out+1] = "flights off: " .. pinBtnsShown()
    CloudeMap.SetEnabled("flight", true)
    CloudeMap.RegisterCategory("test", { name = "Herbs", minScale = 0 })
    CloudeMap.SetPins("test", { { map = 1501, x = 0.5, y = 0.5, name = "Peacebloom", onClick = function() end } })
    frames(3)
    out[#out+1] = "after third-party category: " .. pinBtnsShown()
    -- click while dragging must not fire
    local clicked = false
    CloudeMap.SetPins("test", { { map = 1501, x = 0.5, y = 0.5, name = "X", onClick = function() clicked = true end } }); frames(3)
    for _, f in ipairs(allFrames) do if rawget(f, "pin") and f.shown and f.pin.name == "X" then f.scripts.OnClick(f, "LeftButton") end end
    out[#out+1] = "click fired: " .. tostring(clicked)
    for _, f in ipairs(allFrames) do if rawget(f, "pin") and f.shown then f.scripts.OnEnter(f); f.scripts.OnLeave(f) end end
end

do
    out[#out+1] = "=== BRIDGE ==="
    local late = fakeIcon()
    hbdp:AddWorldMapIconMap("TomTom", late, 1501, 0.6, 0.6)
    for i = 1, 6 do for _, t in ipairs(tickers) do t() end frames(2) end
    for _, id in ipairs(CloudeMap.order) do
        if id:find("^addon:") or id:find("^hn:") then print("bridge cat", id, #CloudeMap.cats[id].pins, CloudeMap.cats[id].name) end
    end
    for _, f in ipairs(allFrames) do if rawget(f, "pin") and f.shown and (f.pin.src or f.pin.handler) then f.scripts.OnEnter(f); f.scripts.OnLeave(f); f.scripts.OnClick(f, "LeftButton") end end
    print("bridge hover: hbd", entered, "hn", hnEntered, "err", tostring(ns.bridge.err))
    for _, id in ipairs({"gm:Herb Gathering","gm:Mining","rarescanner","spy"}) do print("extra cat", id, CloudeMap.cats[id] and #CloudeMap.cats[id].pins) end
    do
        local c = CloudeMap.cats.rarescanner
        local p = c.pins[#c.pins]
        local btn = CreateFrame("Button")
        p.onEnter(btn, p); p.onLeave(btn, p); p.onClick(p, "LeftButton", btn)
        for i = 1, 3 do for _, t in ipairs(tickers) do t() end frames(2) end
        print("rs after click: pins", #c.pins, "tips/active", RS_TEST())
        local q = c.pins[#c.pins]
        q.onClick(q, "LeftButton", btn)
        for i = 1, 3 do for _, t in ipairs(tickers) do t() end frames(2) end
        print("rs after 2nd click: pins", #c.pins, "tips/active", RS_TEST())
    end
    print(ns.bridge.Status())
    for _, id in ipairs({"questie","questie_avail","questie_town"}) do print("questie cat", id, CloudeMap.cats[id] and #CloudeMap.cats[id].pins) end
    hbdp:RemoveWorldMapIcon("TomTom", late)
    for i = 1, 4 do for _, t in ipairs(tickers) do t() end frames(2) end
    print("after remove", #CloudeMap.cats["addon:TomTom"].pins)
end

if os.getenv("MOCK_CITY") then
    local function citySprites()
        local n, amax = 0, 0
        for _, t in ipairs(allTex) do
            if rawget(t, "shown") and rawget(t, "sub") == 3 and t.w > 0 and rawget(t, "tex") then
                n = n + 1; amax = math.max(amax, rawget(t, "alpha") or 1)
            end
        end
        return n, amax
    end
    local function dbgLine(pat)
        local n0 = #out
        SlashCmdList.CLOUDEMAP("debug")
        local r
        for i = n0 + 1, #out do local v = out[i]:match(pat) if v then r = v end end
        for i = #out, n0 + 1, -1 do out[i] = nil end
        return r
    end
    out[#out+1] = "=== CITY TEST (player inside city 1453) ==="
    SlashCmdList.CLOUDEMAP("reset"); frames(2)
    SlashCmdList.CLOUDEMAP("me"); frames(15)
    out[#out+1] = "cities line: " .. tostring(dbgLine("(cities with their own map: .*)"))
    local bad, seq, last = 0, {}, nil
    local path = {}
    for x = 110, 610, 25 do path[#path+1] = x end
    for x = 610, 110, -25 do path[#path+1] = x end
    for _, x in ipairs(path) do
        for _, y in ipairs({ 40, 300, 440 }) do
            curX, curY = x, y; frames(4)
            local n, a = citySprites()
            if n == 0 or a < 0.99 then bad = bad + 1 end
            local f = dbgLine("focus zone: %[(%d+)%]")
            if f ~= last then seq[#seq+1] = ("x=%d,y=%d->%s"):format(x, y, tostring(f)); last = f end
        end
    end
    out[#out+1] = ("following in city: city sprites missing/faded in %d sweep samples | zone focus: %s"):format(bad, table.concat(seq, " "))
    out[#out+1] = "city focus: " .. tostring(dbgLine("(city focus: .*)"))
    -- not following: pointer inside, then clearly outside, then back
    SlashCmdList.CLOUDEMAP("follow"); frames(2)
    curX, curY = 356, 344; frames(15)
    local n1, a1 = citySprites()
    out[#out+1] = ("free, pointer on city: sprites %d alpha %.2f | %s"):format(n1, a1, tostring(dbgLine("(city focus: .*)")))
    curX, curY = 120, 44; frames(40)
    local n2, a2 = citySprites()
    out[#out+1] = ("free, pointer far outside: sprites %d | %s"):format(n2, tostring(dbgLine("(city focus: .*)")))
    SlashCmdList.CLOUDEMAP("map")
    curX, curY = nil, nil
    -- and satellite mode must not draw the city
    SlashCmdList.CLOUDEMAP("me"); frames(15)
    SlashCmdList.CLOUDEMAP("sat"); frames(10)
    local n3 = citySprites()
    out[#out+1] = "satellite mode city sprites: " .. n3
    SlashCmdList.CLOUDEMAP("map"); frames(10)
end

do
    UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = { x = x, y = y } } end }
    local wp
    C_Map.SetUserWaypoint = function(p) wp = p end
    C_Map.GetUserWaypoint = function() return wp end
    C_Map.ClearUserWaypoint = function() wp = nil end
    ns.onCtrlClick(1000, 1000, 1)
    wp = nil
    IsControlKeyDown = function() return true end
    view.scripts.OnMouseUp(view, "RightButton")
    out[#out+1] = "ctrl+right click set: " .. tostring(wp and wp.uiMapID)
    wp = nil
    view.scripts.OnMouseDown(view, "LeftButton"); view.scripts.OnMouseUp(view, "LeftButton")
    out[#out+1] = "ctrl+left click set (must be nil): " .. tostring(wp and wp.uiMapID)
    IsControlKeyDown = function() return false end
    out[#out+1] = "waypoint set: " .. tostring(wp and wp.uiMapID) .. " " .. tostring(wp and wp.position.x); frames(3); out[#out+1] = "waypoint pin cat: " .. #CloudeMap.cats.waypoint.pins
end

SlashCmdList.CLOUDEMAP("where")
do
    for _, f in ipairs(allFrames) do local sc = rawget(f, "scripts"); if sc and sc.OnEvent then pcall(sc.OnEvent, f, "PLAYER_LOGIN") end end
    frames(3)
    local function count() local n = 0 for _, l in ipairs(allLines or {}) do if rawget(l, "shown") and rawget(l, "sp") then n = n + 1 end end return n end
    out[#out+1] = "spf subscribed: " .. #SPF_SUBS .. " | lines shown: " .. count() .. " | goal pins: " .. #(CloudeMap.cats.spf and CloudeMap.cats.spf.pins or {})
    local gp = CloudeMap.cats.spf and CloudeMap.cats.spf.pins[1]
    if gp then out[#out+1] = "goal: " .. gp.name .. " | " .. table.concat(gp.steps, " / ") .. " | left " .. tostring(gp.left) end
    local before = count()
    SlashCmdList.CLOUDEMAP("me"); view.scripts.OnMouseWheel(view, 1); frames(3)
    out[#out+1] = "after zoom lines: " .. count() .. " (before " .. before .. ")"
    CloudeMap.SetEnabled("spf", false); frames(2)
    out[#out+1] = "toggled off lines: " .. count() .. " pins: " .. #CloudeMap.cats.spf.pins
    CloudeMap.SetEnabled("spf", true); frames(2)
    out[#out+1] = "toggled on lines: " .. count()
    IsShiftKeyDown = function() return true end
    IsAltKeyDown = function() return false end
    IsControlKeyDown = function() return false end
    curX, curY = 300, 300
    view.scripts.OnMouseDown(view, "LeftButton"); view.scripts.OnMouseUp(view, "LeftButton")
    out[#out+1] = "shift click navigated: " .. tostring(navigated)
    IsShiftKeyDown = function() return false end
    UnitFactionGroup = function() return "Horde" end
    CreateVector2D = function(x, y) return { x = x, y = y } end
    C_Map.GetMapPosFromWorldPos = function(c, v) if c == 369 then return nil end local x, y = 0.1 + (c == 0 and 0.5 or 0) + ((-v.y) % 4000) / 12000, 0.1 + ((-v.x) % 4000) / 12000; return 1501, { x = x, y = y } end
    frames(3); SlashCmdList.CLOUDEMAP("me"); view.scripts.OnMouseWheel(view, -1); frames(3)
    out[#out+1] = "build: " .. "n/a" .. " TRANSIT " .. tostring(PNS.TRANSIT ~= nil)
    local d, p = CloudeMap.cats.spfdocks, CloudeMap.cats.spfportals
    out[#out+1] = ("transit docks pins %d, portal pins %d"):format(d and #d.pins or -1, p and #p.pins or -1)
    if d and d.pins[1] then
        local pin = d.pins[1]
        TIP = {}
        GameTooltip.AddLine = function(_, t) TIP[#TIP+1] = t end
        GameTooltip.AddDoubleLine = function(_, a, b) TIP[#TIP+1] = a .. " || " .. b end
        GameTooltip.ClearLines = function() TIP = {} end
        GameTooltip.IsOwned = function() return true end
        GetServerTime = function() return 1800000000 end
        ShortestPathForeverDB.anchors = {}
        for id in pairs(PNS.TRANSIT.routes) do ShortestPathForeverDB.anchors[id] = { epoch = 1799990000000, seen = 1799999000 } break end
        for i, pp in ipairs(d.pins) do TIP = {}; pp.onEnter(view, pp); pp.onLeave(view, pp); out[#out+1] = "dock tip " .. i .. ": " .. table.concat(TIP, " / ") end
        local g = CloudeMap.cats.spf.pins[1]; TIP = {}; g.onEnter(view, g); out[#out+1] = "goal tip: " .. table.concat(TIP, " / ")
        local pp = CloudeMap.cats.spfportals.pins[1]; if pp then TIP = {}; pp.onEnter(view, pp); out[#out+1] = "portal tip: " .. table.concat(TIP, " / ") end
        local before = 0 for _, l in ipairs(allLines) do if rawget(l, "shown") then before = before + 1 end end
        pin.onEnter(view, pin)
        local n = 0 for _, l in ipairs(allLines) do if rawget(l, "shown") then n = n + 1 end end
        pin.onLeave(view, pin)
        local m = 0 for _, l in ipairs(allLines) do if rawget(l, "shown") then m = m + 1 end end
        out[#out+1] = ("lines before hover %d, hovered %d, after %d"):format(before, n, m)
    end
    ShortestPathForeverDB.otherFaction = true; frames(2); SlashCmdList.CLOUDEMAP("me"); view.scripts.OnMouseWheel(view, 1); frames(3)
    local function rc() local n = 0 for _, p in ipairs(CloudeMap.cats.spfdocks.pins) do n = n + #p.routes end return n end
    out[#out+1] = ("with other faction: docks %d routes %d"):format(#CloudeMap.cats.spfdocks.pins, rc())
    ShortestPathForeverDB.otherFaction = true; SlashCmdList.CLOUDEMAP("me"); view.scripts.OnMouseWheel(view, 1); frames(3); view.scripts.OnMouseWheel(view, -1); frames(3); out[#out+1] = ("direct other: routes %d"):format(rc())
    ShortestPathForeverDB.otherFaction = false; SlashCmdList.CLOUDEMAP("me"); view.scripts.OnMouseWheel(view, 1); frames(3); view.scripts.OnMouseWheel(view, -1); frames(3); out[#out+1] = ("own faction: docks %d routes %d"):format(#CloudeMap.cats.spfdocks.pins, rc())
    do
        local r = PNS.TRANSIT.routes[241]
        local d1, d2 = PNS.TRANSIT.docks[1], PNS.TRANSIT.docks[2]
        local _, p1 = C_Map.GetMapPosFromWorldPos(d1[1], { x = d1[2], y = d1[3] })
        local _, p2 = C_Map.GetMapPosFromWorldPos(d2[1], { x = d2[2], y = d2[3] })
        local J = ShortestPathForever.API.Journey
        ShortestPathForever.API.Journey = function() return { goal = { map = 1501, x = p2.x, y = p2.y, title = "Booty Bay" }, index = 1, secondsLeft = 300,
            legs = { { mode = "boat", text = "Boat to Booty Bay", seconds = 200, from = { map = 1501, x = p1.x, y = p1.y }, to = { map = 1501, x = p2.x, y = p2.y } } } } end
        local G = ShortestPathForever.API.Guidance
        ShortestPathForever.API.Guidance = function() return nil end
        for _, cb in ipairs(SPF_SUBS) do cb({}) end
        local polys = PNS.state.polys
        local n = 0 for _, p in ipairs(polys) do n = n + (#p - 4) / 2 end
        out[#out+1] = ("boat leg: %d polylines, %d points (path points in route: %d)"):format(#polys, n, #r[5] / 4)
        local cv = r.cv; local jumps = 0 for k = 2, #cv do if cv[k].c ~= cv[k-1].c then jumps = jumps + 1 end end
        out[#out+1] = "route continent changes: " .. jumps
        ShortestPathForever.API.Journey, ShortestPathForever.API.Guidance = J, G
    end
    for _ = 1, 15 do view.scripts.OnMouseWheel(view, -1) end frames(5)
    local mn, mx, cnt = 999, 0, 0
    for _, f in ipairs(allFrames) do local p = rawget(f, "pin"); if p and rawget(f, "shown") and p.routes then cnt = cnt + 1; mn = math.min(mn, f.w); mx = math.max(mx, f.w) end end
    out[#out+1] = ("zoomed out: %d dock pins, sizes %s..%s"):format(cnt, mn, mx)
    out[#out+1] = "STATUS " .. tostring(ns.bridge.PluginStatus())
    for _, f in ipairs({ view.scripts.OnMouseUp, ns.onMapClick }) do
        local i = debug.getinfo(f, "uS"); out[#out+1] = ("nups line %d: %d"):format(i.linedefined, i.nups)
    end
end
for _, l in ipairs(out) do io.write(l, "\n") end
io.write(("frames=%d textures=%d\n"):format(created.frames, created.textures))do
    local sent, sounds = {}, {}
    C_ChatInfo = { SendAddonMessage = function(p, t, ch) sent[#sent + 1] = p .. " " .. t .. " " .. ch; return true end, RegisterAddonMessagePrefix = function() end }
    PlaySound = function(id) sounds[#sounds + 1] = id end
    IsInGroup = function() return true end
    IsInRaid = function() return false end
    IsAltKeyDown = function() return true end
    UnitName = function() return "Andy" end
    Ambiguate = function(n) return (n:gsub("%-.*", "")) end
    frames(2)
    rawset(view, 'w', 600); rawset(view, 'h', 600)
    -- alt click in the middle of the view
    curX, curY = 300, 300
    view.scripts.OnMouseDown(view, "LeftButton")
    view.scripts.OnMouseUp(view, "LeftButton")
    io.write("sent: ", table.concat(sent, " | "), "\n")
    -- a party member pings a spot on a zone far away
    local out0 = #out
    for _, f in ipairs(allFrames) do local sc = rawget(f, "scripts"); if sc and sc.OnEvent then pcall(sc.OnEvent, f, "CHAT_MSG_ADDON", "CloudeMap", "P:1501:0.9900:0.0100", "PARTY", "Bob-Realm") end end
    for i = out0 + 1, #out do io.write("chat: ", out[i], "\n") end
    io.write("sounds: ", table.concat(sounds, ","), "\n")
    -- run the ping animation a frame
    for _, f in ipairs(allFrames) do local sc = rawget(f, "scripts"); if sc and sc.OnUpdate and f ~= view then pcall(sc.OnUpdate, f, 0.1) end end
    local arrows, shown = 0, 0
    for _, f in ipairs(allFrames) do if rawget(f, "arrow") and rawget(f, "shown") then shown = shown + 1; if rawget(f.arrow, "shown") then arrows = arrows + 1 end end end
    io.write("pings shown: ", shown, ", with edge arrow: ", arrows, "\n")
end
