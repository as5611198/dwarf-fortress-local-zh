--@module=true

local fixed={
    dwarf='矮人', human='人類', elf='精靈', goblin='哥布林', kobold='狗頭人',
    animal='動物', undead='不死生物', ['night creature']='夜行生物',
}

function label(source, index)
    local key=string.lower(source or ''):gsub('_',' ')
    return fixed[key] or ('種族 '..tostring(index))
end

function filter(figures, race, search)
    local wanted=string.lower(search or '')
    local result={}
    for id,figure in pairs(figures) do
        local name=figure.name or ''
        local matches=wanted=='' or (wanted:find('[\128-\255]') and require('utils').search_text(name,wanted))
            or string.find(string.lower(name),wanted,1,true)
        if (race < 0 or figure.race == race) and matches then
            result[#result+1]=id
        end
    end
    table.sort(result)
    return result
end

