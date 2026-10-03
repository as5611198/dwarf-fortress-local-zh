local source=...
local env=setmetatable({},{__index=_G})
assert(loadfile(source..'/df-local-zh-unicode.lua','t',env))()
assert(env.decode("'測試𠮷A1' Nos"..string.char(0x8c)..'milral')=="'測試𠮷A1' Nosîmilral",
    'Mixed Chinese nickname and CP437 surname must decode independently')
assert(env.decode(string.char(0x82)..' A')=='é A')
assert(env.decode('鐵匠𠮷 A1')=='鐵匠𠮷 A1')
print('UNICODE_MIXED PASS')
