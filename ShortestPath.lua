-- CloudeMap_ShortestPath: Shortest Path Forever on CloudeMap's map.
--
-- The journey is read through Shortest Path's public API (ShortestPathForever.API: Journey,
-- Guidance, Subscribe, Navigate) and drawn through CloudeMap's (CloudeMap.Map and the pin
-- registry); neither addon's frames or functions are touched. The transports come from a copy of
-- Shortest Path's data (Transit.lua), since its own tables are private.
--
--   the walk under way follows the arrow's own path; later legs run straight from end to end in
--   Shortest Path's colours, the destination gets its pin (tooltip: the steps and their times)
--   Shift+click on CloudeMap plans a journey there, as on the game's map
--   docks (boats, zeppelins, lifts, the tram) and portals as pins; hovering a dock shows its route
--
-- Read when the journey changes (Shortest Path's Subscribe), drawn again when the map zooms or
-- changes zone: no timer of its own.
local _, ns = ...

local OWNER, CAT = "CloudeMap", "spf"
local s = { polys = {}, hover = {}, lines = {}, shown = 0 }
ns.state = s

-- Shortest Path's own colours (UI/Route.lua): the walk in the colour picked in its settings
local WALK = { gold = { 1, 0.82, 0 }, white = { 1, 1, 1 }, cyan = { 0.2, 0.9, 1 }, green = { 0.3, 1, 0.35 }, magenta = { 1, 0.35, 1 } }
local MODE = {
    flight = { 0.2, 1, 0.35 }, boat = { 0, 0.75, 1 }, zeppelin = { 1, 0.35, 0.1 }, lift = { 1, 0.5, 0.25 },
    tram = { 1, 0.5, 0.25 }, portal = { 0.85, 0.35, 1 }, passage = { 0.85, 0.35, 1 }, teleport = { 0.85, 0.35, 1 },
}
-- the pins never smaller than this on screen, however far out the map is zoomed: half the
-- player's arrow (32)
local MIN_PIN = 16
local LATER = 0.45              -- legs after the one under way recede, as on Shortest Path's map
local STEP = 4                  -- screen pixels between the points of a drawn walk
local MAX_LINES = 1500

local function Map() local cm = rawget(_G, "CloudeMap"); return cm and cm.Map end
local function CM() return rawget(_G, "CloudeMap") end
local function API()
    local t = rawget(_G, "ShortestPathForever")
    local api = type(t) == "table" and rawget(t, "API")
    if type(api) == "table" and type(api.Journey) == "function" then return api end
end
local function SPDB()
    local db = rawget(_G, "ShortestPathForeverDB")
    return type(db) == "table" and db or {}
end
local function WalkColour() return WALK[SPDB().routeColor or "gold"] or WALK.gold end

local function Canvas(place)
    if type(place) ~= "table" then return end
    local M = Map()
    if M then return M.ToCanvas(place.map, place.x, place.y) end
end

---------------------------------------------------------------------------
-- Lines: polylines in canvas units, laid on CloudeMap's pin layer at its zoom
---------------------------------------------------------------------------
local function Poly(colour, alpha)
    local p = { colour[1], colour[2], colour[3], alpha }
    s.polys[#s.polys + 1] = p
    return p
end
local function Add(p, place)
    local x, y = Canvas(place)
    if x then p[#p + 1] = x; p[#p + 1] = y end
end

local function Line(i)
    local l = s.lines[i]
    if not l then
        l = { o = s.frame:CreateLine(nil, "ARTWORK", nil, 1), c = s.frame:CreateLine(nil, "ARTWORK", nil, 2) }
        l.o:SetThickness(5)
        l.c:SetThickness(2.5)
        s.lines[i] = l
    end
    return l
end

local function Draw()
    local M = Map()
    if not M then return end
    local view, layer, sc, level = M.View()
    if not view then return end
    if not s.frame then
        s.frame = CreateFrame("Frame", nil, view)
        s.frame:SetAllPoints(view)
        s.frame:SetFrameLevel(level)            -- under the pins
        s.frame:EnableMouse(false)
    end
    local used = 0
    for li = 1, 2 do
        for _, p in ipairs(li == 1 and s.polys or s.hover) do
            local ax, ay = p[5], p[6]
            local n = #p
            for i = 7, n, 2 do
                local bx, by = p[i], p[i + 1]
                local dx, dy = (bx - ax) * sc, (by - ay) * sc
                if i + 1 == n or dx * dx + dy * dy >= STEP * STEP then
                    if used >= MAX_LINES then break end
                    used = used + 1
                    local l = Line(used)
                    l.o:SetStartPoint("TOPLEFT", layer, ax * sc, -ay * sc); l.o:SetEndPoint("TOPLEFT", layer, bx * sc, -by * sc)
                    l.c:SetStartPoint("TOPLEFT", layer, ax * sc, -ay * sc); l.c:SetEndPoint("TOPLEFT", layer, bx * sc, -by * sc)
                    l.o:SetColorTexture(0, 0, 0, 0.7 * p[4])
                    l.c:SetColorTexture(p[1], p[2], p[3], p[4])
                    l.o:Show(); l.c:Show()
                    ax, ay = bx, by
                end
            end
        end
    end
    for i = used + 1, s.shown do s.lines[i].o:Hide(); s.lines[i].c:Hide() end
    s.shown, s.scale = used, sc
end

---------------------------------------------------------------------------
-- Ship paths on the seamless map. Shortest Path's paths are the transports' own recorded
-- positions, one continent at a time: a crossing that has a loading screen jumps from one
-- continent's sea to the other's. Here both continents lie on one map, so the jump is bridged by
-- a smooth curve over the sea that leaves the way the ship was heading and arrives the way it
-- goes on. The tram runs inside its own instance, which has no place on the map: a straight
-- line between its two stations.
---------------------------------------------------------------------------
local BRIDGE_STEPS = 24

-- a route's sea lanes (Lanes.lua, by route ID): drawn round the land at its jumps
local laneOf
local function Lanes(r)
    if not laneOf then
        laneOf = {}
        for id, route in pairs(ns.TRANSIT.routes) do laneOf[route] = ns.LANES and ns.LANES[id] or false end
    end
    return laneOf[r] or nil
end

-- the route's points on the canvas (nil where the game cannot place one), worked out once. A lane
-- { from, to, continent, x, y, ... } is drawn after path point from and takes the place of the
-- points between from and to (going round), the stretch where the ship heads away from it.
local function RoutePoints(r)
    if r.cv then return r.cv end
    local M, pts, cv, lanes = Map(), r[5], {}, Lanes(r)
    local n, skip, after = #pts / 4, {}, {}
    for _, lane in ipairs(lanes or {}) do
        after[lane[1]] = lane
        local k = lane[1] % n + 1
        while k ~= lane[2] do skip[k], k = true, k % n + 1 end
    end
    for k = 1, n do
        if not skip[k] then
            local i = k * 4 - 3
            local x, y = M.WorldToCanvas(pts[i], pts[i + 1], pts[i + 2])
            cv[#cv + 1] = { x = x, y = y, c = pts[i], t = pts[i + 3] }
            local lane = after[k]
            for q = 3, lane and #lane or 0, 3 do
                local lx, ly = M.WorldToCanvas(lane[q], lane[q + 1], lane[q + 2])
                cv[#cv + 1] = { x = lx, y = ly, c = lane[q], lane = true }
            end
        end
    end
    r.cv = cv
    return cv
end

-- a cubic curve from a to b, leaving a along (a - before) and reaching b along (after - b); across
-- the strait between two lanes the pull is the strait's width only, so the curve stays over the sea
local function Bridge(poly, before, a, b, after)
    local dx, dy = b.x - a.x, b.y - a.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len == 0 then return end
    local function Dir(p, q)
        if not (p and q and p.x and q.x) then return dx / len, dy / len end
        local ux, uy = q.x - p.x, q.y - p.y
        local l = math.sqrt(ux * ux + uy * uy)
        if l == 0 then return dx / len, dy / len end
        return ux / l, uy / l
    end
    local ax, ay = Dir(before, a)
    local bx, by = Dir(b, after)
    local k = (a.lane and b.lane) and math.abs(dx) * 0.35 or len * 0.35
    local p1x, p1y = a.x + ax * k, a.y + ay * k
    local p2x, p2y = b.x - bx * k, b.y - by * k
    for i = 1, BRIDGE_STEPS do
        local t = i / BRIDGE_STEPS
        local u = 1 - t
        poly[#poly + 1] = u * u * u * a.x + 3 * u * u * t * p1x + 3 * u * t * t * p2x + t * t * t * b.x
        poly[#poly + 1] = u * u * u * a.y + 3 * u * u * t * p1y + 3 * u * t * t * p2y + t * t * t * b.y
    end
end

-- the route from path point i to j (going round; i == j: the whole loop) as polylines
local function Trace(r, i, j, alpha)
    local cv = RoutePoints(r)
    local n = #cv
    if n < 2 then return {} end
    local colour = MODE[r[1]] or WALK.gold
    local out, cur, prev, prevAt = {}, nil, nil, nil
    local at, steps = i, 0
    while true do
        local p = cv[at]
        if p.x then
            if not cur then
                cur = { colour[1], colour[2], colour[3], alpha }
                out[#out + 1] = cur
                cur[5], cur[6] = p.x, p.y
            elseif prev.c ~= p.c then
                Bridge(cur, cv[(prevAt - 2) % n + 1], prev, p, cv[at % n + 1])
            else
                cur[#cur + 1] = p.x
                cur[#cur + 1] = p.y
            end
            prev, prevAt = p, at
        else
            cur, prev = nil, nil                -- a point the game cannot place: a gap
        end
        if steps > 0 and at == j then break end
        if steps > n then break end
        at, steps = at % n + 1, steps + 1
    end
    return out
end

-- the path point where the route calls at a stop (its arrival time)
local function StopPoint(r, arrive)
    for k, p in ipairs(RoutePoints(r)) do if p.t == arrive then return k end end
end

local function Dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- a boat or zeppelin leg of the journey along the ship's own path: the route and its two calls
-- nearest the leg's ends
local function LegPath(leg, alpha)
    local data = ns.TRANSIT
    if not (data and (leg.mode == "boat" or leg.mode == "zeppelin")) then return end
    local fx, fy = Canvas(leg.from)
    local tx, ty = Canvas(leg.to)
    if not (fx and tx) then return end
    local M, best, bestScore, bi, bj = Map(), nil, nil, nil, nil
    for _, r in pairs(data.routes) do
        if r[1] == leg.mode then
            local st = r[4]
            for a = 1, #st, 3 do
                for b = 1, #st, 3 do
                    local da, db = data.docks[st[a]], data.docks[st[b]]
                    if a ~= b and da and db then
                        local ax, ay = M.WorldToCanvas(da[1], da[2], da[3])
                        local bx, by = M.WorldToCanvas(db[1], db[2], db[3])
                        if ax and bx then
                            local score = Dist(fx, fy, ax, ay) + Dist(tx, ty, bx, by)
                            if not bestScore or score < bestScore then
                                best, bestScore, bi, bj = r, score, st[a + 1], st[b + 1]
                            end
                        end
                    end
                end
            end
        end
    end
    -- (not this route at all when its calls lie well away from the leg's ends)
    if not best or bestScore > 0.25 * Dist(fx, fy, tx, ty) then return end
    local i, j = StopPoint(best, bi), StopPoint(best, bj)
    if not (i and j) then return end
    return Trace(best, i, j, alpha)
end

---------------------------------------------------------------------------
-- The journey
---------------------------------------------------------------------------
local GoalEnter, GoalLeave, GoalClick        -- (the goal pin's tooltip and click, further down)

local function Clear()
    if #s.polys > 0 or s.goalKey then
        s.polys, s.goalKey = {}, nil
        CM().SetPins(CAT, {})
        Draw()
    end
end

local function Time(secs)
    return SecondsToTime and SecondsToTime(secs) or (math.floor(secs) .. " s")
end

local function Read()
    local api, cm = API(), CM()
    if not (api and cm and cm.cats[CAT] and cm.IsEnabled(CAT)) then Clear() return end
    local okJ, j = pcall(api.Journey)
    if not (okJ and type(j) == "table" and type(j.goal) == "table") then Clear() return end
    s.polys = {}
    local walk, legs = WalkColour(), type(j.legs) == "table" and j.legs or {}
    local first = legs[1]               -- (the legs start at the one under way)
    local skipFirst
    if first and first.mode == "walk" then
        local okG, g = pcall(api.Guidance)
        local w = okG and type(g) == "table" and g.waypoints
        if type(w) == "table" and #w > 0 then
            local p = Poly(walk, 1)
            for i = math.max(1, (tonumber(g.index) or 1) - 1), #w do Add(p, w[i]) end
            skipFirst = true
        end
    end
    local steps = {}
    for i, leg in ipairs(legs) do
        if type(leg) == "table" then
            if not (i == 1 and skipFirst) and leg.from and leg.to then
                local alpha = i == 1 and 1 or LATER
                local ship = LegPath(leg, alpha)
                if ship and #ship > 0 then
                    for _, p in ipairs(ship) do s.polys[#s.polys + 1] = p end
                else
                    local p = Poly(leg.mode == "walk" and walk or MODE[leg.mode] or walk, alpha)
                    Add(p, leg.from); Add(p, leg.to)
                end
            end
            if type(leg.text) == "string" and #steps < 12 then
                local secs = tonumber(leg.seconds)
                steps[#steps + 1] = leg.text
            end
        end
    end
    local _, _, gm, gx, gy = Map().ToCanvas(j.goal.map, j.goal.x, j.goal.y)
    local key = gm and ("%d:%.4f:%.4f:%s:%s:%s"):format(gm, gx, gy, table.concat(steps, "|"), tostring(j.owner), tostring(j.secondsLeft))
    if key ~= s.goalKey then
        s.goalKey = key
        local left = tonumber(j.secondsLeft)
        cm.SetPins(CAT, gm and { { map = gm, x = gx, y = gy, steps = steps, left = left and left > 0 and Time(left) or nil,
            mine = j.owner == OWNER, name = type(j.goal.title) == "string" and j.goal.title or "Destination",
            onEnter = GoalEnter, onLeave = GoalLeave, onClick = GoalClick } } or {})
    end
    Draw()
end

-- Navigate answers a bare false; its gates (Core/API.lua NavigateRoute) are read back here to say which one
local function Refusal(map, x, y)
    if SPDB().journey == false then return "Journeys are turned off in Shortest Path's settings" end
    if InCombatLockdown() then return "in combat" end
    local px, py = UnitPosition("player")
    local open = rawget(_G, "canaccessvalue")
    if open and not (open(px) and open(py)) or not (px and py) then return "no player position here" end
    local ok, continent = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if not (ok and continent) then return ("map %d at %.3f, %.3f has no world position"):format(map, x, y) end
    return "refused"
end

-- asks Shortest Path for a journey to map x, y and says in the chat when it can't plan one
local function StartJourney(map, x, y)
    local api = API()
    if not (api and type(api.Navigate) == "function") then return end
    local ok, started, why = pcall(api.Navigate, OWNER, map, x, y)
    if ok and started == false and not why then why = Refusal(map, x, y) end
    s.last = ("map %d %.3f %.3f: %s"):format(map, x, y,
        ok and (tostring(started) .. (why and (" (" .. tostring(why) .. ")") or "")) or ("error " .. tostring(started)))
    if not ok or started == false or (started == nil and why) then
        local reason = not ok and tostring(started) or why or "refused"
        print(("|cff66ccffCloudeMap:|r Shortest Path couldn't plan that journey (map %d, %s)"):format(map, reason))
    end
end

-- Shift+click on CloudeMap: a journey there. In a fight Shortest Path refuses other addons, so the
-- click is held by CloudeMap (Map.AfterFight, where it has it) and the newest one runs when the fight ends.
local function Click(btn, cx, cy, shift, ctrl, alt)
    if btn ~= "LeftButton" or not shift or ctrl or alt then return end
    local api, M = API(), Map()
    if not (api and type(api.Navigate) == "function" and M) then return end
    local map, x, y = M.MapAt(cx, cy)
    if not map then return end
    if InCombatLockdown() and type(M.AfterFight) == "function" and SPDB().journey ~= false then
        M.AfterFight(function() StartJourney(map, x, y) end, "journey")
        s.last = ("map %d %.3f %.3f: held for the fight's end"):format(map, x, y)
        print("|cff66ccffCloudeMap:|r journey queued until the fight ends")
        return true
    end
    StartJourney(map, x, y)
    return true
end

---------------------------------------------------------------------------
-- Tooltips, worded as Shortest Path words them on the game's map (UI/Map.lua, UI/StopPin.lua)
---------------------------------------------------------------------------
local WHITE, GOLD, GREY = { 1, 1, 1 }, { 1, 0.82, 0 }, { 0.5, 0.5, 0.5 }
local function Title(text, right)
    -- (GameTooltip_SetTitle's colour: white)
    if right then GameTooltip:AddDoubleLine(text, right, 1, 1, 1, 1, 1, 1)
    else GameTooltip:AddLine(text, 1, 1, 1) end
end
local function TipLine(text, c) GameTooltip:AddLine(text, (c or GOLD)[1], (c or GOLD)[2], (c or GOLD)[3], true) end
local function Instruction(text) GameTooltip:AddLine(text, 0.1, 1, 0.1, true) end
-- "Shift-click to plan a journey here", while Shortest Path's own hint setting is on
local function JourneyHint()
    local db = SPDB()
    if db.journey ~= false and db.journeyHint ~= false then Instruction("Shift-click to plan a journey here") end
end

-- the goal pin: its title and the time left, the steps when there is more than one, how to clear it
function GoalEnter(frame, pin)
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    Title(pin.name, pin.left)
    if #pin.steps > 1 then
        for i, step in ipairs(pin.steps) do TipLine(step, i == 1 and WHITE or GOLD) end
    end
    if pin.mine then
        GameTooltip:AddLine(" ")
        TipLine("Right-click to clear")
    end
    GameTooltip:Show()
end
function GoalLeave() GameTooltip:Hide() end
function GoalClick(pin, btn)
    local api = API()
    if btn == "RightButton" and pin.mine and api and api.Cancel then pcall(api.Cancel, OWNER) end
end

---------------------------------------------------------------------------
-- Transports, from the copy of Shortest Path's data: a pin per dock (landings too close to tell
-- apart share one), its routes drawn while it is hovered. Shortest Path's settings decide, as on
-- its map: boats and zeppelins, lifts and the tram, portals, the other faction's routes. Departure
-- times are worked out from the sightings Shortest Path saves (ShortestPathForeverDB.anchors), as
-- its timetable does.
---------------------------------------------------------------------------
local ATLAS = { boat = "flightmasterferry", lift = "poi-door-arrow-up", tram = "poi-door-arrow-down",
    portal = "TaxiNode_Continent_Neutral" }
local ZEPPELIN = "Interface\\AddOns\\ShortestPathForever\\media\\Zeppelin"
local TO = { boat = "Boat to %s", zeppelin = "Zeppelin to %s", lift = "Lift to %s", tram = "Tram to %s" }
local KINDS = { boat = "Boats", zeppelin = "Zeppelins", lift = "Lifts", tram = "Deeprun Tram" }
local ORDER = { "boat", "zeppelin", "lift", "tram" }
local HERE = { boat = "docked", zeppelin = "docked", lift = "here", tram = "boarding" }
local LANDING = { boat = "%s pier", zeppelin = "%s tower", lift = "%s landing", tram = "%s station" }
local COMPASS = { "east", "northeast", "north", "northwest", "west", "southwest", "south", "southeast" }
local FILTER = { boat = "pins", zeppelin = "pins", lift = "transit", tram = "transit" }
local t = { built = false, zones = {} }

local function Named(map)
    local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    return info and info.name or UNKNOWN or "?"
end
local function RouteShown(r)
    local db = SPDB()
    return db[FILTER[r[1]]] ~= false and (db.otherFaction or not r[2] or r[2] == (UnitFactionGroup and UnitFactionGroup("player")))
end
-- where a dock is shown: its pier, or a tram station's entrance
local function DockAt(id)
    local d = ns.TRANSIT.docks[id]
    if d then return Map().WorldToCanvas(d[6], d[7], d[8]) end
end
local function DockZone(id)
    if t.zones[id] == nil then
        local _, _, map = DockAt(id)
        t.zones[id] = map and Named(map) or false
    end
    return t.zones[id] or UNKNOWN or "?"
end
-- a dock as a destination: a lift's landing or a tram station by name, a pier by its zone
local function DockLabel(id)
    local d = ns.TRANSIT.docks[id]
    return d and d[5] or DockZone(id)
end

-- the server's time in ms, steady between whole seconds (Shortest Path's NowMs)
local offset
local function NowMs()
    local lead = GetServerTime() - GetTime()
    if not offset or lead > offset or offset - lead > 2 then offset = lead end
    return (GetTime() + offset) * 1000
end
local function Countdown(ms)
    local sec = math.max(0, math.ceil(ms / 1000))
    return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end
-- the next call at a stop: docked now (leaves in), or arrives in and leaves in (Model.Visit)
local function Visit(period, arrive, depart, phase)
    local stay = (depart - arrive) % period
    local since = (phase - arrive) % period
    if since < stay then return true, nil, stay - since end
    local arriveIn = (arrive - phase) % period
    return false, arriveIn, arriveIn + stay
end

-- what leaves a dock, one line per destination, soonest first (Timetable.ByDestination)
local function Departures(id)
    local data, anchors = ns.TRANSIT, SPDB().anchors
    anchors = type(anchors) == "table" and anchors or {}
    local list, now, serverNow = {}, NowMs(), GetServerTime()
    for routeID, r in pairs(data.routes) do
        if RouteShown(r) then
            local st = r[4]
            local n = #st / 3
            for i = 0, n - 1 do
                if st[i * 3 + 1] == id then
                    local to, seen = {}, { [id] = true }
                    for o = 1, n - 1 do
                        local dock = st[((i + o) % n) * 3 + 1]
                        if not seen[dock] then to[#to + 1] = dock; seen[dock] = true end
                    end
                    local dep = { route = routeID, kind = r[1], to = to, known = false }
                    local a = anchors[routeID]
                    if type(a) == "table" and type(a.epoch) == "number" then
                        dep.known = true
                        dep.docked, dep.arriveIn, dep.departIn = Visit(r[3], st[i * 3 + 2], st[i * 3 + 3], (now - a.epoch) % r[3])
                        dep.seen = serverNow - (a.seen or serverNow)
                    end
                    list[#list + 1] = dep
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.known ~= b.known then return a.known end
        return (a.departIn or 0) < (b.departIn or 0) or (a.departIn == b.departIn and a.route < b.route)
    end)
    local merged, first = {}, {}
    for _, dep in ipairs(list) do
        local labels = {}
        for _, to in ipairs(dep.to) do labels[#labels + 1] = DockLabel(to) end
        local key = table.concat(labels, ",")
        local lead = first[key]
        if not lead then
            first[key] = dep
            merged[#merged + 1] = dep
        elseif lead.known and dep.known and not lead.thenIn then
            lead.thenIn = dep.departIn
        end
    end
    return merged
end
local function Destination(dep)
    local text
    for _, to in ipairs(dep.to) do text = text and (text .. ", then " .. DockLabel(to)) or DockLabel(to) end
    return text or ""
end
local function Status(dep)
    if not dep.known then return "no sighting yet" end
    local leaves = dep.thenIn and ("leaves %s, then %s"):format(Countdown(dep.departIn), Countdown(dep.thenIn))
        or ("leaves %s"):format(Countdown(dep.departIn))
    if dep.docked then return HERE[dep.kind] .. " · " .. leaves end
    return ("arrives %s · %s"):format(Countdown(dep.arriveIn), leaves)
end

-- which of a pin's docks this is: a landing by name (with its site where sites differ), else its
-- zone, and which way it lies from the pin where the zones are the same
local function LandingName(pin, dock, kind)
    local data = ns.TRANSIT.docks
    local d = data[dock.id]
    if d[4] then
        for _, other in ipairs(pin.docks) do
            if data[other.id][4] ~= d[4] then return d[4] .. ", " .. d[5] end
        end
        return d[5]
    end
    local zone, shared = DockZone(dock.id), false
    for _, other in ipairs(pin.docks) do shared = shared or (other ~= dock and DockZone(other.id) == zone) end
    if not shared then return zone end
    local angle = math.atan2(pin.cy - dock.cy, dock.cx - pin.cx)
    local name = LANDING[kind]:format(COMPASS[math.floor(angle / (2 * math.pi) * 8 + 0.5) % 8 + 1])
    return #pin.docks > 2 and (zone .. ", " .. name) or (name:gsub("^%l", string.upper))
end

local function DockTooltip(pin)
    local all, groups = {}, {}
    for _, dock in ipairs(pin.docks) do
        local deps = Departures(dock.id)
        if #deps > 0 then
            groups[#groups + 1] = { dock = dock, deps = deps }
            for _, dep in ipairs(deps) do all[#all + 1] = dep end
        end
    end
    if #all == 1 then
        local dep = all[1]
        Title((TO[dep.kind] or "%s"):format(Destination(dep)))
        TipLine((Status(dep):gsub("^%l", string.upper)), dep.known and WHITE or GREY)
    else
        local titles = {}
        for _, kind in ipairs(ORDER) do if pin.kinds[kind] then titles[#titles + 1] = KINDS[kind] end end
        Title(table.concat(titles, " & "))
        for _, g in ipairs(groups) do
            if #groups > 1 then TipLine(LandingName(pin, g.dock, g.deps[1].kind), WHITE) end
            for _, dep in ipairs(g.deps) do
                local c = dep.known and WHITE or GREY
                GameTooltip:AddDoubleLine("to " .. Destination(dep), Status(dep), GOLD[1], GOLD[2], GOLD[3], c[1], c[2], c[3])
            end
        end
    end
    local freshest
    for _, dep in ipairs(all) do
        if dep.known and (not freshest or dep.seen < freshest.seen) then freshest = dep end
    end
    if freshest then
        local ago = SecondsToTime and SecondsToTime(math.max(freshest.seen, 60), true, false, 1) or (math.floor(freshest.seen / 60) .. " min")
        TipLine(("Last seen %s ago"):format(ago), GREY)
    end
    JourneyHint()
end

-- the route under a hovered dock, and its countdowns ticking (a frame of this plugin's own that
-- runs only while a dock is hovered)
local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", function(self, elapsed)
    self.acc = (self.acc or 0) + elapsed
    if self.acc < 1 then return end
    self.acc = 0
    if not (self.pin and GameTooltip:IsOwned(self.owner)) then self:Hide() return end
    GameTooltip:ClearLines()
    DockTooltip(self.pin)
    GameTooltip:Show()
end)

-- a hovered dock's routes: the ship's whole loop, the tram between its stations
local function RoutePolys(r)
    if r.polys then return r.polys end
    if r[1] == "tram" then
        local st, colour = r[4], MODE.tram
        local p = { colour[1], colour[2], colour[3], 0.9 }
        for a = 1, #st, 3 do
            local x, y = DockAt(st[a])
            if x then p[#p + 1] = x; p[#p + 1] = y end
        end
        r.polys = { p }
    else
        r.polys = Trace(r, 1, 1, 0.9)
    end
    return r.polys
end

local function DockEnter(frame, pin)
    s.hover = {}
    for _, r in pairs(pin.routes) do
        for _, p in ipairs(RoutePolys(r)) do if #p >= 8 then s.hover[#s.hover + 1] = p end end
    end
    Draw()
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    DockTooltip(pin)
    GameTooltip:Show()
    ticker.pin, ticker.owner, ticker.acc = pin, frame, 0
    ticker:Show()
end
local function DockLeave()
    ticker.pin = nil
    ticker:Hide()
    if #s.hover > 0 then s.hover = {}; Draw() end
    GameTooltip:Hide()
end

local function PortalEnter(frame, pin)
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    Title(pin.name)
    TipLine(("to %s"):format(pin.to))
    JourneyHint()
    GameTooltip:Show()
end

local function Filters()
    local db = SPDB()
    return ("%s%s%s%s"):format(tostring(db.otherFaction), tostring(db.portals), tostring(db.pins), tostring(db.transit))
end

local OVERLAP = 0.0008          -- landings closer than this on the canvas (a lift's floors) share a pin

local function BuildTransit()
    local data, M, cm = ns.TRANSIT, Map(), CM()
    if not (data and M and cm) then return end
    local db, pins, docksShown = SPDB(), {}, {}
    for _, r in pairs(data.routes) do
        if RouteShown(r) then
            local st = r[4]
            for i = 1, #st, 3 do docksShown[st[i]] = docksShown[st[i]] or {}; docksShown[st[i]][r] = true end
        end
    end
    for id, routes in pairs(docksShown) do
        local cx, cy, m, x, y = DockAt(id)
        if m then
            local pin
            for _, other in ipairs(pins) do
                if math.abs(other.cx - cx) < OVERLAP and math.abs(other.cy - cy) < OVERLAP then pin = other break end
            end
            if not pin then
                pin = { map = m, x = x, y = y, cx = cx, cy = cy, docks = {}, kinds = {}, routes = {},
                    onEnter = DockEnter, onLeave = DockLeave }
                pins[#pins + 1] = pin
            end
            pin.docks[#pin.docks + 1] = { id = id, cx = cx, cy = cy }
            for r in pairs(routes) do pin.routes[r] = r; pin.kinds[r[1]] = true end
        end
    end
    for _, pin in ipairs(pins) do
        -- the icon of the first kind in Shortest Path's order; a lift's or the tram's arrows drawn smaller
        for _, kind in ipairs(ORDER) do
            if pin.kinds[kind] then
                if kind == "zeppelin" then pin.texture = ZEPPELIN else pin.atlas = ATLAS[kind] end
                pin.size = (kind == "lift" or kind == "tram") and 15 or 20
                break
            end
        end
    end
    local portals, mine = {}, UnitFactionGroup and UnitFactionGroup("player")
    if db.portals ~= false then
        for _, p in ipairs(data.portals) do
            -- (portals only: the tram's entrances already show as tram pins)
            if p[2] == "portal" and (not p[3] or p[3] == mine) then
                local _, _, m, x, y = M.WorldToCanvas(p[4], p[5], p[6])
                if m then
                    local _, _, tm = M.WorldToCanvas(p[7], p[8], p[9])
                    portals[#portals + 1] = { map = m, x = x, y = y, name = p[1], atlas = ATLAS.portal,
                        to = tm and Named(tm) or (UNKNOWN or "?"), onEnter = PortalEnter, onLeave = GoalLeave }
                end
            end
        end
    end
    if #pins == 0 and #portals == 0 then return end         -- (CloudeMap's map is not built yet)
    t.built, t.key = true, Filters()
    cm.SetPins(CAT .. "docks", pins)
    cm.SetPins(CAT .. "portals", portals)
end

---------------------------------------------------------------------------
-- Hooking up, once both addons are there
---------------------------------------------------------------------------
local function Redraw(scale)
    if (#s.polys > 0 or #s.hover > 0) and scale ~= s.scale then Draw() end
    if s.dirty then s.dirty = nil; Read() end
    if not t.built or t.key ~= Filters() then BuildTransit() end
end

local function Hook()
    local api, cm, M = API(), CM(), Map()
    if s.hooked or not (api and type(api.Subscribe) == "function" and cm and M and M.version >= 1) then return end
    cm.RegisterCategory(CAT, { name = "Shortest Path: journey", addon = "ShortestPathForever", order = 430, minScale = 0,
        size = 26, minSize = MIN_PIN, always = true, texture = "Interface\\AddOns\\ShortestPathForever\\media\\Pin" })
    cm.RegisterCategory(CAT .. "docks", { name = "Shortest Path: boats, zeppelins, lifts, tram", addon = "ShortestPathForever",
        order = 431, minScale = 0, size = 20, minSize = MIN_PIN, always = true })
    cm.RegisterCategory(CAT .. "portals", { name = "Shortest Path: portals", addon = "ShortestPathForever",
        order = 432, minScale = 0, size = 20, minSize = MIN_PIN, always = true })
    M.OnRedraw(Redraw)
    M.OnClick(Click)
    M.OnToggle(function(id) if id == CAT then Read() end end)
    M.Status(function()
        return ("Shortest Path: %d lines, transports %s, last shift+click %s"):format(s.shown or 0,
            t.built and "shown" or "not built yet", tostring(s.last or "none"))
    end)
    s.hooked = pcall(api.Subscribe, function()
        if M.View() then Read() else s.dirty = true end
    end)
    s.dirty = true
    Read()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self)
    pcall(Hook)
    self:UnregisterAllEvents()
end)
