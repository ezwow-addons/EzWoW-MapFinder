--===========================================================================
-- EzWoW - Map Finder
-- Modules/ZoneExits.lua : where the roads lead into the next zone
--===========================================================================
-- The game has no data on where a zone's roads, passes and tunnels lead into
-- the next zone. This character notes the spot each time it walks, rides or
-- swims over a zone border: two position samples half a second apart, one
-- on each side, close together and no farther apart than the character's
-- own speed allows (a flight, a boat, a teleport and a ghost's run are left
-- out). Spots closer than SAME yards are one exit.
-- The spots are shared with the other EzWoW users (record kind "X":
-- "fromMap,toMap,continent,x,y,dir,2[,w]"; 2 is the record format, w marks
-- a crossing made swimming). A spot is used from the first report; one only
-- crossed swimming (a way over water is seldom a road) needs two players.
-- Older versions did not tell swims apart: their spots are used from the
-- first report too, and the few found over the sea are listed in the shipped
-- data ("exitsBlocked") and never shown.
-- They are also shipped with the addon (Database/ShareSeed.lua, "exits").
-- Zone maps show a door mark with an arrow (dir: u/d/l/r on the map) at each
-- spot, on the maps of both zones; a click opens the other zone's map
-- (Modules/MapEnhancements.lua draws them with the boat and portal marks).
-- store X: ["from>to"] = { own = { {continent, x, y, dir, n}, ... },
--                          peers = { {continent, x, y, dir, n = votes, by = {}, land, water, ok}, ... } }
-- (own spots noted by these rules carry the format as their 6th value and
-- true as the 7th while they were only crossed swimming; a peer spot gets
-- land = true once someone sent it as crossed on land, water = true once
-- someone sent it as swum)
local _, ns = ...

local KIND = "X"
local SAMPLE = 0.5        -- seconds between position samples
local MAX_GAP = 1.5       -- seconds: samples farther apart in time are not compared
local MAX_STEP = 40       -- yards: a longer jump between the two samples is not walking
local SAME = 60           -- yards: crossings this close are one exit
local MAX_OWN = 6         -- own exit spots kept per zone pair
local MAX_PEERS = 8       -- spots from others kept per zone pair
local MAX_VOTERS = 8
local FORMAT = 2          -- record format: tells land and water crossings apart, never a ghost's run
local ZONE_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3

local isSecret = _G.issecretvalue or function() return false end
local sqrt, floor, abs = math.sqrt, math.floor, math.abs

local ZoneExits = {}
ns.ZoneExits = ZoneExits

local function share()
    return ns.Share
end

local function store()
    local s = share()
    if not (s and type(s.Store) == "function") then return nil end
    local ok, t = pcall(s.Store, KIND)
    return ok and type(t) == "table" and t or nil
end

local function round1(v)
    return floor(v * 10 + 0.5) / 10
end

local function near(c1, x1, y1, c2, x2, y2, yards)
    if c1 ~= c2 or type(x1) ~= "number" or type(y1) ~= "number" or type(x2) ~= "number" or type(y2) ~= "number" then
        return false
    end
    local dx, dy = x1 - x2, y1 - y2
    return dx * dx + dy * dy <= yards * yards
end

-----------------------------------------------------------------------------
-- Zone maps
-----------------------------------------------------------------------------
local zoneOfCache, isZoneCache = {}, {}

local function mapInfo(mapID)
    if type(mapID) ~= "number" or isSecret(mapID) or not (C_Map and C_Map.GetMapInfo) then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    if not ok or type(info) ~= "table" then return nil end
    return info
end

-- true for a zone map (the kind of map exits are shown and noted on)
local function isZoneMap(mapID)
    if type(mapID) ~= "number" then return false end
    local cached = isZoneCache[mapID]
    if cached ~= nil then return cached end
    local info = mapInfo(mapID)
    local result = info ~= nil and info.mapType == ZONE_TYPE
    isZoneCache[mapID] = result
    return result
end
ZoneExits.IsZoneMap = isZoneMap

-- the zone map a map lies in (caves and town detail maps lead up to it)
local function zoneOf(mapID)
    if type(mapID) ~= "number" or isSecret(mapID) then return nil end
    local cached = zoneOfCache[mapID]
    if cached ~= nil then return cached or nil end
    local id, result = mapID, false
    for _ = 1, 8 do
        local info = mapInfo(id)
        if not info or type(info.mapType) ~= "number" or isSecret(info.mapType) then break end
        if info.mapType == ZONE_TYPE then result = id break end
        if info.mapType < ZONE_TYPE then break end
        id = info.parentMapID
        if type(id) ~= "number" or id == 0 then break end
    end
    zoneOfCache[mapID] = result
    return result or nil
end

local function mapName(mapID)
    local info = mapInfo(mapID)
    local name = info and info.name
    if type(name) ~= "string" or name == "" or isSecret(name) then return nil end
    return name
end
ZoneExits.MapName = mapName

-----------------------------------------------------------------------------
-- What is shown: own spots, confirmed spots of others, shipped spots
-----------------------------------------------------------------------------
local OPPOSITE = { u = "d", d = "u", l = "r", r = "l" }
local forMapCache = {}

-- a spot from others is shown from the first report, unless it was only
-- ever sent as swum: then once two players sent it
local function shown(sp)
    local n = tonumber(sp.n) or 0
    if sp.water == true and sp.land ~= true then return n >= 2 end
    return n >= 1
end

-- spots shared by mistake before swims were told apart (one over the sea):
-- never shown, in either direction (Database/ShareSeed.lua "exitsBlocked")
local function blocked(from, to, c, x, y)
    local s = ns.Share
    local list = s and type(s.Seed) == "function" and s.Seed("exitsBlocked")
    if type(list) ~= "table" then return false end
    for _, key in ipairs({ from .. ">" .. to, to .. ">" .. from }) do
        for _, sp in ipairs(type(list[key]) == "table" and list[key] or {}) do
            if type(sp) == "table" and near(sp[1], sp[2], sp[3], c, x, y, SAME) then return true end
        end
    end
    return false
end

local function changed()
    forMapCache = {}
    if ns.RefreshTransitPins and WorldMapFrame and WorldMapFrame:IsShown() then pcall(ns.RefreshTransitPins) end
end

-- every known spot of every zone pair: calls fn(from, to, continent, x, y, dir)
local function eachSpot(fn)
    for key, row in pairs(store() or {}) do
        local from, to
        if type(key) == "string" then from, to = key:match("^(%d+)>(%d+)$") end
        from, to = tonumber(from), tonumber(to)
        if from and to and type(row) == "table" then
            for _, sp in ipairs(type(row.own) == "table" and row.own or {}) do
                if type(sp) == "table" then fn(from, to, sp[1], sp[2], sp[3], sp[4]) end
            end
            for _, sp in ipairs(type(row.peers) == "table" and row.peers or {}) do
                if type(sp) == "table" and shown(sp) then
                    fn(from, to, sp[1], sp[2], sp[3], sp[4])
                end
            end
        end
    end
    local s = share()
    local seed = s and type(s.Seed) == "function" and s.Seed("exits")
    for key, spots in pairs(type(seed) == "table" and seed or {}) do
        local from, to
        if type(key) == "string" then from, to = key:match("^(%d+)>(%d+)$") end
        from, to = tonumber(from), tonumber(to)
        if from and to and type(spots) == "table" then
            for _, sp in ipairs(spots) do
                if type(sp) == "table" then fn(from, to, sp[1], sp[2], sp[3], sp[4]) end
            end
        end
    end
end

-- the exits on one zone map: { { x, y (percent of the map), dest = other zone, dir }, ... }
function ZoneExits.ForMap(mapID)
    if not isZoneMap(mapID) then return {} end
    local cached = forMapCache[mapID]
    if cached then return cached end
    local list, kept = {}, {}
    local toMapPos = C_Map and C_Map.GetMapPosFromWorldPos
    eachSpot(function(from, to, c, x, y, dir)
        local dest
        if from == mapID then dest = to elseif to == mapID then dest = from; dir = OPPOSITE[dir] end
        if not dest or dest == mapID or type(c) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return end
        if blocked(from, to, c, x, y) then return end
        -- the same way out found twice (both directions, several players): one mark
        for _, k in ipairs(kept) do
            if k.dest == dest and near(k.c, k.wx, k.wy, c, x, y, SAME) then return end
        end
        if not (toMapPos and CreateVector2D) then return end
        local ok, _, pos = pcall(toMapPos, c, CreateVector2D(x, y), mapID)
        if not ok or type(pos) ~= "table" then return end
        local okXY, mx, my = pcall(pos.GetXY, pos)
        if not okXY or type(mx) ~= "number" or type(my) ~= "number" or isSecret(mx) or isSecret(my) then return end
        if mx < -0.02 or mx > 1.02 or my < -0.02 or my > 1.02 then return end
        mx = math.max(0.01, math.min(0.99, mx))
        my = math.max(0.01, math.min(0.99, my))
        kept[#kept + 1] = { dest = dest, c = c, wx = x, wy = y }
        list[#list + 1] = { exit = true, kind = "exit", x = mx * 100, y = my * 100, dest = dest,
            dir = OPPOSITE[dir] and dir or nil }
    end)
    forMapCache[mapID] = list
    return list
end

-----------------------------------------------------------------------------
-- Noting this character's own crossings
-----------------------------------------------------------------------------
-- u/d/l/r on the map for a move in the world (world x points north = up,
-- world y points west = left)
local function direction(dx, dy)
    if abs(dx) >= abs(dy) then return dx >= 0 and "u" or "d" end
    return dy >= 0 and "l" or "r"
end

local function noteCrossing(from, to, c, x, y, dir, water)
    local t = store()
    if not t then return end
    local key = from .. ">" .. to
    local row = type(t[key]) == "table" and t[key] or {}
    row.own = type(row.own) == "table" and row.own or {}
    for _, sp in ipairs(row.own) do
        if type(sp) == "table" and near(sp[1], sp[2], sp[3], c, x, y, SAME) then
            sp[5] = math.min((tonumber(sp[5]) or 1) + 1, 999)
            -- crossed again by the current rules on land: sent in the current
            -- format as a land crossing from now on. Swum again, it stays as it
            -- was (an older spot keeps the old form, so others keep showing it)
            if not water then
                sp[6] = FORMAT
                sp[7] = nil
            end
            t[key] = row
            return
        end
    end
    if #row.own >= MAX_OWN then return end
    row.own[#row.own + 1] = { c, round1(x), round1(y), dir, 1, FORMAT, water or nil }
    t[key] = row
    changed()
end

local function truthy(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, ...)
    return ok and not isSecret(value) and value and true or false
end

local last   -- the previous sample: { zone, c, x, y, t, speed }

local function sample()
    if truthy(IsInInstance) or truthy(UnitOnTaxi, "player") or truthy(UnitInVehicle, "player")
        or truthy(UnitIsDeadOrGhost, "player") then
        last = nil
        return
    end
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then return end
    local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not okMap or type(mapID) ~= "number" or isSecret(mapID) then last = nil return end
    local okPos, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not okPos or not pos then last = nil return end
    local okWorld, c, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, pos)
    if not okWorld or type(c) ~= "number" or isSecret(c) or type(world) ~= "table" then last = nil return end
    local x, y = world.x, world.y
    if type(x) ~= "number" or type(y) ~= "number" or isSecret(x) or isSecret(y) then last = nil return end
    local speed = 0
    if type(GetUnitSpeed) == "function" then
        local okSpeed, s = pcall(GetUnitSpeed, "player")
        if okSpeed and type(s) == "number" and not isSecret(s) then speed = s end
    end
    local now = GetTime()
    local zone = zoneOf(mapID)
    local swimming = truthy(IsSwimming)
    local prev = last
    last = { zone = zone, c = c, x = x, y = y, t = now, speed = speed, swim = swimming }
    if not (prev and zone and prev.zone and zone ~= prev.zone and prev.c == c) then return end
    local dt = now - prev.t
    if dt <= 0 or dt > MAX_GAP then return end
    local dx, dy = x - prev.x, y - prev.y
    local dist = sqrt(dx * dx + dy * dy)
    -- moving on its own (a boat moves a standing player) and no faster than that
    local moving = math.max(prev.speed or 0, speed)
    if moving <= 0 or dist > MAX_STEP or dist > moving * dt * 1.5 + 3 then return end
    local dir
    if dist >= 0.5 then
        dir = direction(dx, dy)
    else
        local okFacing, facing = pcall(GetPlayerFacing)
        if not okFacing or type(facing) ~= "number" or isSecret(facing) then return end
        dir = direction(math.cos(facing), math.sin(facing))
    end
    noteCrossing(prev.zone, zone, c, (prev.x + x) / 2, (prev.y + y) / 2, dir, (swimming or prev.swim) and true or nil)
end

if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(SAMPLE, function() pcall(sample) end)
end

-----------------------------------------------------------------------------
-- Sharing
-----------------------------------------------------------------------------
local s = share()
if s and type(s.RegisterKind) == "function" then
    s.RegisterKind(KIND, {
        own = function()
            local out = {}
            for key, row in pairs(store() or {}) do
                local from, to
                if type(key) == "string" then from, to = key:match("^(%d+)>(%d+)$") end
                if from and type(row) == "table" then
                    for _, sp in ipairs(type(row.own) == "table" and row.own or {}) do
                        if type(sp) == "table" and type(sp[1]) == "number" and type(sp[2]) == "number"
                            and type(sp[3]) == "number" and OPPOSITE[sp[4]] then
                            local formatField = ""
                            if sp[6] == FORMAT then formatField = "," .. FORMAT .. (sp[7] == true and ",w" or "") end
                            out[#out + 1] = string.format("%s,%s,%d,%.1f,%.1f,%s%s", from, to, sp[1], sp[2], sp[3], sp[4], formatField)
                        end
                    end
                end
            end
            return out
        end,
        -- a spot is used from the first report, one only ever swum from the
        -- second player (the library's "needed" is not applied)
        receive = function(text, hash)
            local from, to, c, x, y, dir, recordFormat, waterMark = text:match("^(%d+),(%d+),(%d+),(%-?[%d%.]+),(%-?[%d%.]+),([udlr]),(%d+),?(w?)$")
            if not from then
                from, to, c, x, y, dir = text:match("^(%d+),(%d+),(%d+),(%-?[%d%.]+),(%-?[%d%.]+),([udlr])$")
            end
            from, to, c, x, y = tonumber(from), tonumber(to), tonumber(c), tonumber(x), tonumber(y)
            if not (from and to and c and x and y) or from == to or from > 100000 or to > 100000 or c > 10000
                or abs(x) > 100000 or abs(y) > 100000 then return false end
            -- both sides must be zone maps of this client
            if not (isZoneMap(from) and isZoneMap(to)) then return false end
            -- a spot taken off in the data (in the sea and the like) is not kept
            if blocked(from, to, c, x, y) then return false end
            local t = store()
            if not t then return false end
            local key = from .. ">" .. to
            local row = type(t[key]) == "table" and t[key] or {}
            for _, sp in ipairs(type(row.own) == "table" and row.own or {}) do
                if type(sp) == "table" and near(sp[1], sp[2], sp[3], c, x, y, SAME) then return false end
            end
            row.peers = type(row.peers) == "table" and row.peers or {}
            local found
            for _, sp in ipairs(row.peers) do
                if type(sp) == "table" and near(sp[1], sp[2], sp[3], c, x, y, SAME) then found = sp break end
            end
            if not found then
                if #row.peers >= MAX_PEERS then
                    -- the oldest unconfirmed report makes room for a new one
                    local drop
                    for i = #row.peers, 1, -1 do
                        if type(row.peers[i]) ~= "table" or not shown(row.peers[i]) then drop = i break end
                    end
                    if not drop then return false end
                    table.remove(row.peers, drop)
                end
                found = { c, round1(x), round1(y), dir, by = {}, n = 0 }
                table.insert(row.peers, 1, found)
            end
            t[key] = row
            local wasShown = shown(found)
            if tonumber(recordFormat) == FORMAT then
                if waterMark == "w" then found.water = true else found.land = true end
            end
            found.by = type(found.by) == "table" and found.by or {}
            local h = tostring(hash or "?")
            if not found.by[h] and (found.n or 0) < MAX_VOTERS then
                found.by[h] = true
                found.n = (found.n or 0) + 1
            end
            local nowShown = shown(found)
            found.ok = nowShown or nil
            if nowShown and not wasShown then
                changed()
                return true
            end
            -- no longer shown (the only sender now says it was swum): maps again
            if wasShown and not nowShown then changed() end
            -- kept until another player sends it
            if not nowShown then return "wait" end
            return false
        end,
        describe = function(text)
            local from, to = text:match("^(%d+),(%d+),")
            if not from then return nil end
            return (mapName(tonumber(from)) or from) .. " > " .. (mapName(tonumber(to)) or to)
        end,
        -- for the shared records window: spots from others in use now (shown
        -- by the rules above and not among the blocked ones)
        used = function()
            local n = 0
            for key, row in pairs(store() or {}) do
                local from, to
                if type(key) == "string" then from, to = key:match("^(%d+)>(%d+)$") end
                from, to = tonumber(from), tonumber(to)
                if from and to and type(row) == "table" then
                    for _, sp in ipairs(type(row.peers) == "table" and row.peers or {}) do
                        if type(sp) == "table" and shown(sp) and not blocked(from, to, sp[1], sp[2], sp[3]) then
                            n = n + 1
                        end
                    end
                end
            end
            return n
        end,
    })
end

-- shipped spots arrive with the data; records may come in after the map was drawn
if s and type(s.RegisterCallback) == "function" then
    s.RegisterCallback("EzWoW-MapFinder-Exits", function(kinds)
        if type(kinds) == "table" and kinds[KIND] then forMapCache = {} end
    end)
end
