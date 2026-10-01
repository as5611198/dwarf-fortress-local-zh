local function bindings(module)
    local found,seen={},{}
    local function visit(fn)
        if seen[fn] or debug.getinfo(fn,'S').what=='C' then return end
        seen[fn]=true
        for index=1,100 do
            local name,value=debug.getupvalue(fn,index)
            if not name then break end
            local old=found[name]
            assert(not old or debug.upvalueid(old.fn,old.index)==debug.upvalueid(fn,index),
                'Ambiguous runtime binding: '..name)
            found[name]={fn=fn,index=index,value=value}
            if type(value)=='function' then visit(value) end
        end
    end
    for _,fn in pairs(module) do if type(fn)=='function' then visit(fn) end end
    return found
end

return function(running,fresh,locals,exports)
    local old,new=bindings(running),bindings(fresh)
    local updates={}
    for _,name in ipairs(locals) do
        assert(old[name] and new[name] and type(new[name].value)=='function','Missing local: '..name)
        updates[#updates+1]={name=name,fn=new[name].value,slot=old[name]}
    end
    for _,name in ipairs(exports) do
        assert(type(running[name])=='function' and type(fresh[name])=='function','Missing export: '..name)
        updates[#updates+1]={name=name,fn=fresh[name],export=true}
    end
    -- Validate every dependency before touching the running module's shared cells.
    local joins={}
    for _,update in ipairs(updates) do
        for index=1,100 do
            local name=debug.getupvalue(update.fn,index)
            if not name then break end
            assert(old[name],'Missing running dependency: '..name)
            joins[#joins+1]={fn=update.fn,index=index,slot=old[name]}
        end
    end
    for _,join in ipairs(joins) do debug.upvaluejoin(join.fn,join.index,join.slot.fn,join.slot.index) end
    for _,update in ipairs(updates) do
        if update.export then running[update.name]=update.fn
        else debug.setupvalue(update.slot.fn,update.slot.index,update.fn) end
    end
    return #updates
end
