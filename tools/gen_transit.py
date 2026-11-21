import sys
from lupa import LuaRuntime
src, out, version = sys.argv[1], sys.argv[2], sys.argv[3]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('ns = { Docks = {}, Routes = {} }')
for f in ("Data/Routes.lua", "Data/Transports.lua", "Data/Portals.lua"):
    lua.globals().CODE = open(f"{src}/{f}").read()
    lua.execute('local fn = assert(load(CODE)); fn("ShortestPathForever", ns)')
g = lua.globals().ns
def num(v): return ("%.1f" % v).rstrip('0').rstrip('.')
def s(v): return '"' + str(v).replace('\\','\\\\').replace('"','\\"') + '"'
def opt(v): return s(v) if v else 'false'
L = []
L.append('-- CloudeMap_ShortestPath: boats, zeppelins, lifts, the tram and portals, for the transport pins.')
L.append(f'-- Generated from Shortest Path Forever {version} by cjber (github.com/cjber/shortest-path-forever),')
L.append('-- GPL-3.0-or-later; its own sources: wago.tools DB2 and CMaNGOS classic-db. Do not edit by hand.')
L.append('-- World positions are continent, x (north), y (west). Times are milliseconds.')
L.append('local _, ns = ...')
L.append('ns.TRANSIT = {')
L.append('    -- [dock] = { continent, x, y, site, name, shown at: continent, x, y (the pier, or a station\'s entrance) }')
L.append('    docks = {')
for k in sorted(g.Docks.keys()):
    d = g.Docks[k]
    p = d.pin or d.walk or d
    L.append(f'        [{k}] = {{ {d.map}, {num(d.x)}, {num(d.y)}, {opt(d.site)}, {opt(d.name)}, {p.map}, {num(p.x)}, {num(p.y)} }},')
L.append('    },')
L.append('    -- [route] = { kind, faction, period, { dock, arrive, depart, ... }, { path: continent, x, y, ms into the loop, ... } }')
L.append('    routes = {')
for k in sorted(g.Routes.keys()):
    r = g.Routes[k]
    stops = ', '.join(f'{st.dock}, {st.arrive}, {st.depart}' for st in r.stops.values())
    pts, last = [], None
    if r.frames:
        for fr in r.frames.values():
            pt = f'{fr[3]}, {num(fr[4])}, {num(fr[5])}'
            if pt != last: pts.append(pt + f', {fr[1]}')
            last = pt
    L.append(f'        [{k}] = {{ {s(r.kind)}, {opt(r.faction)}, {r.period}, {{ {stops} }}, {{ {", ".join(pts)} }} }},')
L.append('    },')
L.append('    -- { name, kind, faction, from: continent, x, y, to: continent, x, y }')
L.append('    portals = {')
for p in g.Portals.values():
    L.append(f'        {{ {s(p.name)}, {s(p.kind)}, {opt(p.faction)}, {p["from"].map}, {num(p["from"].x)}, {num(p["from"].y)}, {p.to.map}, {num(p.to.x)}, {num(p.to.y)} }},')
L.append('    },')
L.append('}')
open(out, 'w').write('\n'.join(L) + '\n')
