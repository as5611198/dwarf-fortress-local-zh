local mod=reqscript('df-local-zh-core/mod')
local cases={
    {'silt loam Up/Down Stairway','粉質壤土上/下行樓梯'},
    {'silt loam Downward Stairway','粉質壤土下行樓梯'},
    {'silt loam Upward Stairway','粉質壤土上行樓梯'},
    {'silt loam up/down stairway','粉質壤土上/下行樓梯'},
    {'granite Up/Down Stairway','花崗岩上/下行樓梯'},
    {'Warm Damp silt loam Downward Stairway','溫暖潮溼粉質壤土下行樓梯'},
    {'Fighting','戰鬥'}, {'Profession changes','專業變更'},
    {'Important','重要'}, {'Medical alerts','醫療警報'},
    {'Masterpieces','傑作誕生'}, {'Job failures','工作失敗'},
    {'General','常規'}, {'World','世界'}, {'Environment','環境'},
    {'Arrivals','抵達'}, {'Attacks','攻擊'}, {'Creatures','生物'},
    {'Date: 18th Granite, 250','日期：250年花崗岩月18日'},
    {'Date: 1st Slate, 251','日期：251年板岩月1日'},
    {'Date: 22nd Opal, 252','日期：252年蛋白石月22日'},
}
for _,row in ipairs(cases) do
    assert(mod.sync_translate(row[1])==row[2],'Missing native translation: '..row[1])
end
print('PASS fortress stair composition and announcement tabs in native translator')
