import sys
from lupa import LuaRuntime
addon_dir, variant = sys.argv[1], sys.argv[2]
lua = LuaRuntime(unpack_returned_tuples=True)
src = open(sys.argv[3]).read()
# run mock.lua as a chunk with arguments (dir, variant)
fn = lua.eval("function(src, a, b) local f, e = load(src, 'mock.lua'); if not f then error(e) end; return f(a, b) end")
try:
    fn(src, addon_dir, variant)
except Exception as e:
    print("LUA ERROR:", e)
