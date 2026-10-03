--@module=true
local function chinese(point)
    return point>=0x3100 and point<=0x312f or point>=0x3400 and point<=0x9fff or point>=0x20000 and point<=0x323af
end
function decode(value)
    value=tostring(value or '')
    if utf8.len(value) then
        for _,point in utf8.codes(value) do
            if chinese(point) then return value end
        end
    end
    -- Native names concatenate UTF-8 nicknames and legacy CP437 surnames.
    -- Preserve complete CJK sequences while converting only the legacy runs.
    local parts,start,offset={},1,1
    while offset<=#value do
        local lead=value:byte(offset)
        local width=lead>=0xe0 and lead<=0xef and 3 or lead>=0xf0 and lead<=0xf4 and 4 or 1
        local part=width>1 and value:sub(offset,offset+width-1) or nil
        if part and #part==width and utf8.len(part)==1 and chinese(utf8.codepoint(part)) then
            if start<offset then parts[#parts+1]=dfhack.df2utf(value:sub(start,offset-1)) end
            parts[#parts+1]=part;offset=offset+width;start=offset
        else offset=offset+1 end
    end
    if start<=#value then parts[#parts+1]=dfhack.df2utf(value:sub(start)) end
    return table.concat(parts)
end
