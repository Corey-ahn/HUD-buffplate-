if API_TYPE == nil then
	ADDON:ImportAPI(8)
	X2Chat:DispatchChatMessage(CMF_SYSTEM,
		"[이름표버프] globals 폴더가 없다. Addon 폴더에 globals 를 같이 넣어라")
	return
end

ADDON:ImportObject(OBJECT_TYPE.TEXT_STYLE)
ADDON:ImportObject(OBJECT_TYPE.BUTTON)
ADDON:ImportObject(OBJECT_TYPE.DRAWABLE)
ADDON:ImportObject(OBJECT_TYPE.NINE_PART_DRAWABLE)
ADDON:ImportObject(OBJECT_TYPE.COLOR_DRAWABLE)
ADDON:ImportObject(OBJECT_TYPE.ICON_DRAWABLE)
ADDON:ImportObject(OBJECT_TYPE.IMAGE_DRAWABLE)
ADDON:ImportObject(OBJECT_TYPE.WINDOW)
ADDON:ImportObject(OBJECT_TYPE.LABEL)
ADDON:ImportObject(OBJECT_TYPE.EDITBOX)
ADDON:ImportObject(OBJECT_TYPE.X2_EDITBOX)

ADDON:ImportAPI(API_TYPE.CHAT.id)
ADDON:ImportAPI(API_TYPE.UNIT.id)
ADDON:ImportAPI(API_TYPE.SKILL.id)
ADDON:ImportAPI(API_TYPE.COMBAT_RESOURCE.id)

local SAVE_KEY = "buffplate_state"

local ICON_SIZE = 32
local ICON_TEX = "Addon/buffplate/Icones/Main.dds"

local PLATE_SIZE = 25
local PLATE_MIN, PLATE_MAX = 16, 48
local LIFT = 110
local LIFT_MIN, LIFT_MAX = 0, 300
local SAVE_VER = 4

local DEAD_PX = 2
local SMOOTH = 0.35
local SNAP_PX = 60
local SLOTS = 10
local HORIZ = 1
local SKILL_TEXT = 1
local SKILL_FS = 12
local SKILL_FS_MIN, SKILL_FS_MAX = 10, 40
local GAP = 4

local ROWS = 10
local ROW_H = 26
local WIN_W = 620
local LIST_TOP = 152
local WIN_H = LIST_TOP + ROWS * ROW_H + 158
local LIST_MAX = 40

local DATA_MS = 250
local LIST_MS = 500

local DEFIANCE_ID = 22969
local DEFIANCE_FIX_MS = 1440000

BPLT_DEFAULT = {
	{ id = 22969, name = "패기" },
	{ id = 23214, name = "남겨진 서고의 방패 면역" },
	{ id = 27128, name = "열망하는 안식의 방패 면역" },
	{ id = 24405, name = "남겨진 심연의 서고 방패 면역" },
	{ id = 32871, name = "방패 당기기 면역" },
}

local UNITS = { "player", "target" }
local TABS = { "player", "target", "myskill", "skill" }
local UNIT_NAME = { player = "나", target = "대상", myskill = "내 스킬", skill = "상대 스킬" }
local SKILL_OF = { player = "myskill", target = "skill" }
local PLATE_OF = { myskill = "player", skill = "target", player = "player", target = "target" }
local function IsSkillTab(t) return t == "skill" or t == "myskill" end
local ON_LABEL = { player = "내 버프", target = "대상 버프", myskill = "내 스킬", skill = "상대 스킬" }

local C_TEXT = { 0.10, 0.08, 0.05, 1 }
local C_DIM  = { 0.40, 0.34, 0.26, 1 }
local C_HEAD = { 0.13, 0.22, 0.45, 1 }
local C_ON   = { 0.05, 0.45, 0.12, 1 }
local C_BAD  = { 0.66, 0.11, 0.06, 1 }

local S_TIME  = { 1.00, 1.00, 1.00, 1 }
local S_STACK = { 0.35, 1.00, 1.00, 1 }
local S_SKILL = { 1.00, 0.80, 0.30, 1 }

local cfg = {}
local sel = {}
local hid = {}
local query = nil
local iconDir = nil
local cur = {}
local plate = {}
local tab = "player"
local page = 1
local accData, accList = 0, 0

local mainWindow, iconBtn, iconDraw
local iconShown = true
local showGauge = 1
local usedVariant = {}
local aliasMap = {}
local ALIAS_MAX = 4
local aliasTarget = nil
local rowW = {}
local tabBtn = {}
local onBtn, allBtn, whoLabel, pageLabel, noteLabel, sizeLabel, liftLabel, layoutBtn, searchEdit, gaugeBtn
local skTextBtn, fsEdit
local RefreshWin, FillPlate, FillGauges
local COL_X
local SlotText, LayoutTextRow

for _, u in ipairs(TABS) do
	cfg[u] = { list = {}, hide = {}, on = 1, all = 0 }
	sel[u] = { ids = {}, names = {} }
	hid[u] = { ids = {}, names = {} }
	cur[u] = {}
end

local function Say(msg)
	pcall(function()
		X2Chat:DispatchChatMessage(CMF_SYSTEM, "[이름표버프] " .. tostring(msg))
	end)
end

local noteIsHint = true
local function Note(msg)
	noteIsHint = (msg == nil or msg == "")
	if noteIsHint then return end
	pcall(function() if noteLabel ~= nil then noteLabel:SetText(tostring(msg)) end end)
end

local function Short(ms)
	if ms == nil then return "" end
	local s = math.floor(ms / 1000)
	if s < 0 then return "" end
	if s < 60 then return tostring(s) end
	if s < 3600 then return string.format("%d:%02d", math.floor(s / 60), s % 60) end
	return math.floor(s / 3600) .. "h"
end

local function Dur(ms)
	if ms == nil then return "" end
	local s = math.floor(ms / 1000)
	if s <= 0 then return "0초" end
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	local sec = s % 60
	if h > 0 then return h .. "시간 " .. m .. "분" end
	if m > 0 then return m .. "분 " .. sec .. "초" end
	return sec .. "초"
end

local function Clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function MakeSet(list)
	local set = { ids = {}, names = {} }
	for _, it in ipairs(list) do
		if it.byname == 1 and type(it.name) == "string" then
			set.names[it.name] = true
		elseif it.id ~= nil then
			set.ids[it.id] = true
		end
	end
	return set
end

local function RebuildSel(u)
	sel[u] = MakeSet(cfg[u].list)
	hid[u] = MakeSet(cfg[u].hide)
end

local function InSet(set, id, name)
	if id ~= nil and set.ids[id] then return true end
	if type(name) == "string" and set.names[name] then return true end
	return false
end

local function IconPos(btn)
	local x, y = btn:GetOffset()
	pcall(function()
		local cx, cy = btn:CorrectOffsetByScreen()
		if tonumber(cx) ~= nil and tonumber(cy) ~= nil then x, y = cx, cy end
	end)
	return x, y
end

local function Save()
	pcall(function()
		local d = { psize = PLATE_SIZE, lift = LIFT, ver = SAVE_VER, horiz = HORIZ, gauge = showGauge,
			used = usedVariant, sktext = SKILL_TEXT, alias = aliasMap, skfs = SKILL_FS,
			shown = iconShown and 1 or 0 }
		for _, u in ipairs(TABS) do
			d[u] = { list = cfg[u].list, hide = cfg[u].hide, on = cfg[u].on, all = cfg[u].all }
		end
		if iconBtn ~= nil then
			local x, y = IconPos(iconBtn)
			d.x = x
			d.y = y
		end
		ADDON:ClearData(SAVE_KEY)
		ADDON:SaveData(SAVE_KEY, d)
	end)
end

local function Num(t, k)
	if type(t) ~= "table" then return nil end
	local v = tonumber(t[k])
	if type(v) ~= "number" then return nil end
	return v
end

local function ReadList(src, dest)
	if type(src) ~= "table" then return end
	for _, it in ipairs(src) do
		if type(it) == "table" and #dest < LIST_MAX then
			local id = Num(it, "id")
			local nm = nil
			if type(it.name) == "string" and it.name ~= "" then nm = it.name end
			if Num(it, "byname") == 1 and nm ~= nil then
				table.insert(dest, { id = id, name = nm, byname = 1 })
			elseif id ~= nil then
				table.insert(dest, { id = id, name = nm })
			end
		end
	end
end

local function Load()
	local saved = nil
	pcall(function() saved = ADDON:LoadData(SAVE_KEY) end)
	local fresh = (type(saved) ~= "table")
	for _, u in ipairs(TABS) do
		local s = nil
		if not fresh then s = saved[u] end
		if type(s) == "table" and type(s.list) == "table" then
			ReadList(s.list, cfg[u].list)
			ReadList(s.hide, cfg[u].hide)
			local on = Num(s, "on")
			local all = Num(s, "all")
			if on ~= nil then cfg[u].on = (on ~= 0) and 1 or 0 end
			if all ~= nil then cfg[u].all = (all ~= 0) and 1 or 0 end
			if u == "target" and (Num(saved, "ver") or 1) < 4 then cfg[u].all = 0 end
		elseif not IsSkillTab(u) then
			for _, d in ipairs(BPLT_DEFAULT) do
				table.insert(cfg[u].list, { id = d.id, name = d.name })
			end
		end
		RebuildSel(u)
	end
	local ps = Num(saved, "psize")
	if ps ~= nil then PLATE_SIZE = Clamp(math.floor(ps), PLATE_MIN, PLATE_MAX) end
	if type(saved) == "table" and type(saved.used) == "table" then
		for k, v in pairs(saved.used) do
			if type(k) == "string" and type(v) == "string" then usedVariant[k] = v end
		end
	end
	if type(saved) == "table" and type(saved.alias) == "table" then
		for k, v in pairs(saved.alias) do
			if type(k) == "string" and type(v) == "string" and v ~= "" then aliasMap[k] = v end
		end
	end
	local sf = Num(saved, "skfs")
	if sf ~= nil then SKILL_FS = Clamp(math.floor(sf), SKILL_FS_MIN, SKILL_FS_MAX) end
	local st = Num(saved, "sktext")
	if st ~= nil then SKILL_TEXT = (st ~= 0) and 1 or 0 end
	local gz = Num(saved, "gauge")
	if gz ~= nil then showGauge = (gz ~= 0) and 1 or 0 end
	local hz = Num(saved, "horiz")
	if hz ~= nil then HORIZ = (hz ~= 0) and 1 or 0 end
	local lf = Num(saved, "lift")
	local ver = Num(saved, "ver") or 1
	if lf ~= nil and ver >= 2 then LIFT = Clamp(math.floor(lf), LIFT_MIN, LIFT_MAX) end
	return saved
end

local function Collect(unit)
	local out = {}
	local function grab(kind, cntFn, exFn, tipFn)
		local okc, n = pcall(cntFn)
		if not okc or type(n) ~= "number" then return end
		for i = 1, n do
			local oke, ex = pcall(exFn, i)
			local okt, tip = pcall(tipFn, i)
			if oke and type(ex) == "table" then
				local id = tonumber(ex.buff_id)
				if id ~= nil then
					local e = { id = id, kind = kind, path = ex.path }
				if iconDir == nil and type(ex.path) == "string" then
					iconDir = string.match(ex.path, "^(.*[/\\])")
				end
					if okt and type(tip) == "table" then
						if type(tip.name) == "string" then e.name = tip.name end
						e.ms = tonumber(tip.timeLeft)
						e.stack = tonumber(tip.stack)
					end
					if id == DEFIANCE_ID and e.ms ~= nil then e.ms = e.ms - DEFIANCE_FIX_MS end
					out[#out + 1] = e
				end
			end
		end
	end
	grab("buff", function() return X2Unit:UnitBuffCount(unit) end,
		function(i) return X2Unit:UnitBuff(unit, i) end,
		function(i) return X2Unit:UnitBuffTooltip(unit, i) end)
	grab("debuff", function() return X2Unit:UnitDeBuffCount(unit) end,
		function(i) return X2Unit:UnitDeBuff(unit, i) end,
		function(i) return X2Unit:UnitDeBuffTooltip(unit, i) end)
	grab("hidden", function() return X2Unit:UnitHiddenBuffCount(unit) end,
		function(i) return X2Unit:UnitHiddenBuff(unit, i) end,
		function(i) return X2Unit:UnitHiddenBuffTooltip(unit, i) end)
	return out
end

local nowMs = 0
local skillInfo = {}
local cds = {}
local recent = {}
local RECENT_MAX = 30

local function SkillInfo(id)
	id = tonumber(id)
	if id == nil or id <= 0 then return nil end
	local v = skillInfo[id]
	if v ~= nil and not v.fail then return v end
	if v ~= nil and v.fail and nowMs - v.at < 10000 then return nil end
	local ok, info = pcall(function() return X2Skill:Info(id) end)
	if ok and type(info) == "table" then
		v = { cd = tonumber(info.cooldownTime) or 0, icon = info.iconPath, name = info.name }
	else
		v = { fail = true, at = nowMs }
	end
	skillInfo[id] = v
	if v.fail then return nil end
	return v
end

local function Remember(id, name, mine)
	for i, r in ipairs(recent) do
		if r.name == name and r.mine == mine then
			table.remove(recent, i)
			break
		end
	end
	table.insert(recent, 1, { id = id, name = name, mine = mine })
	while #recent > RECENT_MAX do table.remove(recent) end
end

local playerSkill = nil
local function CatalogId(name)
	if playerSkill == nil then
		playerSkill = {}
		if type(BPLT_SKILLS) == "table" then
			for _, r in ipairs(BPLT_SKILLS) do playerSkill[r[1]] = r[2] end
		end
		if type(BPLT_ITEMS) == "table" then
			for _, r in ipairs(BPLT_ITEMS) do
				if playerSkill[r[2]] == nil then playerSkill[r[2]] = r[3] end
			end
		end
	end
	return playerSkill[name]
end

local function IsPlayerSkill(id, name)
	if CatalogId(name) ~= nil then return true end
	return (tonumber(id) or 0) >= 8000000
end

local HIT_EVENTS = { SPELL_DAMAGE = true, SPELL_MISSED = true, SPELL_HEALED = true }

local REHIT_MS = 3500

local TRACE_MAX = 400
local trace = {}
local function Trace(ev, id, name, what)
	trace[#trace + 1] = string.format("%9.2f  %-20s %-9s %-24s %s", nowMs / 1000, tostring(ev),
		tostring(id), tostring(name), what)
	if #trace > TRACE_MAX then table.remove(trace, 1) end
end

local function MyName()
	local me = nil
	pcall(function() me = X2Unit:UnitName("player") end)
	return me
end

local function StartCd(src, id, name)
	local info = SkillInfo(id)
	if info == nil then return false, "쿨 정보 없음(X2Skill:Info(" .. tostring(id) .. ") = nil)" end
	if (info.cd or 0) <= 0 then return false, "쿨 0 (안 센다)" end
	cds[src] = cds[src] or {}
	cds[src][name] = { id = tonumber(id), name = name, path = info.icon, endMs = nowMs + info.cd,
		startMs = nowMs }
	Remember(tonumber(id), name, src == MyName())
	return true, "쿨 " .. math.floor(info.cd / 1000) .. "초"
end

local function Family(name)
	if type(name) ~= "string" then return name end
	return string.match(name, "^(.-):%s") or name
end

local function LearnVariant(name)
	if CatalogId(name) == nil then return end
	local f = Family(name)
	if usedVariant[f] ~= name then
		usedVariant[f] = name
		Trace("배움", nil, name, "이 계열은 이제 '" .. name .. "' 만 띄운다")
		Save()
	end
end

local function OnCombat(_, ev, src, _, id, name)
	if type(src) ~= "string" or type(name) ~= "string" or name == "" then return end
	local mine = (src == MyName())
	if mine and (ev == "SPELL_CAST_SUCCESS" or HIT_EVENTS[ev]) then LearnVariant(name) end
	if ev == "SPELL_CAST_SUCCESS" then
		if not IsPlayerSkill(id, name) then
			if mine then Trace(ev, id, name, "무시: 플레이어 스킬 목록에 없음") end
			return
		end
		local okS, why = StartCd(src, id, name)
		if mine then Trace(ev, id, name, (okS and "시작(시전) " or "못 셈: ") .. why) end
	elseif HIT_EVENTS[ev] then
		local rid = CatalogId(name)
		if rid == nil then
			if mine then Trace(ev, id, name, "무시: 목록에 없는 이름") end
			return
		end
		local e = cds[src] and cds[src][name]
		if e ~= nil and e.endMs > nowMs and (nowMs - (e.startMs or 0)) < REHIT_MS then
			if mine then
				Trace(ev, id, name, string.format("무시: 뒤따르는 타격 (시작 %.1f초 뒤)", (nowMs - (e.startMs or 0)) / 1000))
			end
			return
		end
		local again = (e ~= nil and e.endMs > nowMs)
		local okS, why = StartCd(src, rid, name)
		if mine then
			Trace(ev, id, name, (okS and (again and "다시 시작(쿨이 기본보다 짧다) " or "시작(첫 타격) ") or "못 셈: ") .. why)
		end
	end
end

local pollRaw = {}

local function ToMs(a, b, baseMs)
	a, b = tonumber(a), tonumber(b)
	if a == nil or a <= 0 then return nil end
	baseMs = tonumber(baseMs)
	local probe = (b ~= nil and b > 0) and b or a
	if baseMs ~= nil and baseMs > 0 then
		local asMs = math.abs(probe - baseMs)
		local asSec = math.abs(probe * 1000 - baseMs)
		if asSec < asMs then return a * 1000 end
		return a
	end
	if probe >= 1000 then return a end
	return a * 1000
end

local function PollMyCd()
	local me = MyName()
	if me == nil then return end
	for _, it in ipairs(cfg.myskill.list) do
		local name = it.name
		local id = (type(name) == "string" and CatalogId(name)) or it.id
		if id ~= nil and type(name) == "string" then
			local ok, a, b = pcall(function() return X2Skill:GetCooldown(id, true) end)
			local raw = ok and (tostring(a) .. " / " .. tostring(b)) or "오류"
			if pollRaw[id] ~= raw then
				pollRaw[id] = raw
				Trace("GetCooldown", id, name, "게임이 준 값 = " .. raw)
			end
			if ok then
				local info = SkillInfo(id)
				local left = ToMs(a, b, info and info.cd)
				local e = cds[me] and cds[me][name]
				if left ~= nil then
					cds[me] = cds[me] or {}
					cds[me][name] = { id = id, name = name, path = info and info.icon, endMs = nowMs + left,
						startMs = (e and e.startMs) or nowMs, polled = true }
				elseif e ~= nil and e.polled and e.endMs > nowMs then
					e.endMs = nowMs
				end
			end
		end
	end
end

local LOG_FILE = "../Documents/Addon/buffplate/debug.txt"
local function DumpTrace()
	local lines = { "# buffplate 진단  (내 전투 기록 + 판단, 최근 " .. #trace .. "개)",
		"# 시각(초)  이벤트  스킬id  이름  판단", "" }
	for _, l in ipairs(trace) do lines[#lines + 1] = l end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "# 지금 골라둔 내 스킬"
	for _, it in ipairs(cfg.myskill.list) do lines[#lines + 1] = "   " .. tostring(it.name) .. "  id=" .. tostring(it.id) end
	lines[#lines + 1] = "# 지금 도는 내 쿨"
	local me = MyName()
	if cds[me] ~= nil then
		for nm, e in pairs(cds[me]) do
			lines[#lines + 1] = string.format("   %s  남은 %.1f초", nm, (e.endMs - nowMs) / 1000)
		end
	end
	local ok = pcall(function()
		local fh = io.open(LOG_FILE, "w")
		if fh == nil then error("열 수 없다") end
		fh:write(table.concat(lines, "\n"))
		fh:write("\n")
		fh:close()
	end)
	return ok
end

local function BuildSkillCur()
	local out, mine = {}, {}
	local tn, me = nil, nil
	pcall(function() tn = X2Unit:UnitName("target") end)
	pcall(function() me = X2Unit:UnitName("player") end)
	for who, list in pairs(cds) do
		local any = false
		for nm, e in pairs(list) do
			local left = e.endMs - nowMs
			if left <= -60000 then
				list[nm] = nil
			else
				any = true
				if left > 0 then
					local row = { id = e.id, name = e.name, path = e.path, ms = left, kind = "skill" }
					if who == tn and who ~= me then out[#out + 1] = row end
					if who == me then mine[#mine + 1] = row end
				end
			end
		end
		if not any then cds[who] = nil end
	end
	local byFam, order = {}, {}
	for _, r in ipairs(mine) do
		local f = Family(r.name)
		local pref = usedVariant[f]
		local function rank(x)
			if x.name == pref then return 0 end
			if x.name == f then return 1 end
			return 2
		end
		if byFam[f] == nil then
			order[#order + 1] = f
			byFam[f] = r
		elseif rank(r) < rank(byFam[f]) then
			byFam[f] = r
		end
	end
	mine = {}
	for _, f in ipairs(order) do mine[#mine + 1] = byFam[f] end
	table.sort(out, function(a, b) return a.ms < b.ms end)
	table.sort(mine, function(a, b) return a.ms < b.ms end)
	cur.skill = out
	cur.myskill = mine
end

local function TargetIsMe()
	local ok, same = pcall(function()
		local t = X2Unit:UnitName("target")
		return t ~= nil and t == X2Unit:UnitName("player")
	end)
	return ok and same == true
end

local function MakeLabel(parent, id, text, size, color, align)
	local l = parent:CreateChildWidget("label", id, 0, true)
	l:SetText(text or "")
	l.style:SetFontSize(size or 13)
	l.style:SetAlign(align or ALIGN_LEFT)
	l.style:SetColor(color[1], color[2], color[3], color[4])
	return l
end

local function IsTextRow(r) return r == 3 and SKILL_TEXT == 1 end
local function CellW(r)
	if IsTextRow(r) then return math.floor(PLATE_SIZE * 3.2) end
	return PLATE_SIZE
end

local function PlaceSlot(p, r, s, x, y, wOverride)
	local w = wOverride or CellW(r)
	pcall(function()
		s.icon:SetExtent(PLATE_SIZE, PLATE_SIZE)
		s.icon:AddAnchor("TOPLEFT", p.win, x, y)
		if IsTextRow(r) then
			s.time:SetExtent(w, math.max(PLATE_SIZE, SKILL_FS + 6))
			s.time:AddAnchor("TOPLEFT", p.win, x, y + 4)
		else
			s.time:SetExtent(PLATE_SIZE + 12, PLATE_SIZE)
			s.time:AddAnchor("TOPLEFT", p.win, x - 6, y + 4)
		end
		s.stack:SetExtent(PLATE_SIZE, 12)
		s.stack:AddAnchor("TOPLEFT", p.win, x + 2, y - 4)
	end)
end

local function LayoutRow(p, r, n, lvl)
	lvl = lvl or r
	local step = CellW(r) + GAP
	local x0 = -math.floor((n * step - GAP) / 2)
	local y = -(lvl * PLATE_SIZE + (lvl - 1) * 12) - (p.base or 0)
	for k = 1, SLOTS do
		PlaceSlot(p, r, p.row[r][k], x0 + (k - 1) * step, y)
	end
end

local function LayoutCol(p, r, x)
	for k = 1, SLOTS do
		PlaceSlot(p, r, p.row[r][k], x, -(k * (PLATE_SIZE + GAP)) - (p.base or 0))
	end
end

COL_X = {
	function() return -PLATE_SIZE - 3 end,
	function() return -2 * PLATE_SIZE - 3 - GAP end,
	function() return 3 end,
}

local SKILL_ROW = 3
local GAUGE_MAX = 3
local GAUGE_GAP = 5
local function GW() return math.floor(PLATE_SIZE * 7) end
local function GH() return math.max(10, math.floor(PLATE_SIZE * 0.64 + 0.5)) end
local function GF() return 12 + math.floor(PLATE_SIZE / 12) end

local function BuildPlate(unit)
	local w = CreateEmptyWindow("bpltPlate_" .. unit, "UIParent")
	w:Show(false)
	pcall(function() w:Clickable(false) end)
	local nrow = SKILL_ROW
	local p = { win = w, row = {}, n = { -1, -1, -1 }, lv3 = -1, base = 0, shown = false, any = false }
	for r = 1, nrow do
		p.row[r] = {}
		for k = 1, SLOTS do
			local s = { on = false }
			s.icon = w:CreateIconDrawable("artwork")
			s.icon:SetExtent(PLATE_SIZE, PLATE_SIZE)
			s.icon:SetVisible(false)
			local tag = unit .. "_" .. r .. "_" .. k
			local tc = (r == SKILL_ROW) and S_SKILL or S_TIME
			s.time = MakeLabel(w, "bpltTime_" .. tag, "", 12, tc, ALIGN_CENTER)
			s.stack = MakeLabel(w, "bpltStack_" .. tag, "", 11, S_STACK, ALIGN_RIGHT)
			pcall(function() s.time.style:SetOutline(true) end)
			pcall(function() s.stack.style:SetOutline(true) end)
			s.time:Show(false)
			s.stack:Show(false)
			p.row[r][k] = s
		end
	end
	if unit == "player" then
		p.gauge = {}
		for i = 1, GAUGE_MAX do
			local g = {}
			pcall(function()
				g.bg = w:CreateColorDrawable(0, 0, 0, 0.55, "background")
				g.bg:SetExtent(GW(), GH())
				g.bg:SetVisible(false)
				g.fill = w:CreateColorDrawable(0.8, 0.2, 0.2, 0.95, "artwork")
				g.fill:SetExtent(1, GH())
				g.fill:SetVisible(false)
			end)
			g.text = MakeLabel(w, "bpltGauge_" .. i, "", GF(), S_TIME, ALIGN_CENTER)
			pcall(function() g.text.style:SetOutline(true) end)
			g.text:Show(false)
			p.gauge[i] = g
		end
	end
	plate[unit] = p
end

local function Utf8Head(str, n)
	local out, k, i = {}, 0, 1
	while i <= #str and k < n do
		local c = string.byte(str, i)
		local len = 1
		if c >= 240 then len = 4 elseif c >= 224 then len = 3 elseif c >= 192 then len = 2 end
		out[#out + 1] = string.sub(str, i, i + len - 1)
		i = i + len
		k = k + 1
	end
	return table.concat(out)
end

local function ShortName(name)
	if type(name) ~= "string" then return "?" end
	local base = string.match(name, "^(.-):%s") or name
	if aliasMap[base] ~= nil then return aliasMap[base] end
	base = string.gsub(base, "%s", "")
	return Utf8Head(base, 2)
end

SlotText = function(e) return ShortName(e.name) .. " " .. Short(e.ms) end

local TEXT_GAP = 8
local function TextW(str)
	local w, i = 0, 1
	while i <= #str do
		local c = string.byte(str, i)
		local len = 1
		if c >= 240 then len = 4 elseif c >= 224 then len = 3 elseif c >= 192 then len = 2 end
		w = w + ((len >= 2) and SKILL_FS or math.floor(SKILL_FS * 7 / 12 + 0.5))
		i = i + len
	end
	return w + 4
end

LayoutTextRow = function(p, list, lvl)
	local r = SKILL_ROW
	local ws, total = {}, 0
	for k = 1, SLOTS do
		local e = list[k]
		ws[k] = (e ~= nil) and TextW(SlotText(e)) or PLATE_SIZE
		if e ~= nil then total = total + ws[k] end
	end
	total = total + math.max(0, #list - 1) * TEXT_GAP
	if HORIZ == 1 then
		local x = -math.floor(total / 2)
		local y = -(lvl * PLATE_SIZE + (lvl - 1) * 12) - (p.base or 0)
		y = y - math.max(0, SKILL_FS + 6 - PLATE_SIZE)
		for k = 1, SLOTS do
			PlaceSlot(p, r, p.row[r][k], x, y, ws[k])
			x = x + ws[k] + TEXT_GAP
		end
	else
		for k = 1, SLOTS do
			local step = math.max(PLATE_SIZE, SKILL_FS + 6) + GAP
			PlaceSlot(p, r, p.row[r][k], COL_X[r](), -(k * step) - (p.base or 0), ws[k])
		end
	end
end

local function FillSlots(p, r, list)
	for k = 1, SLOTS do
		local s = p.row[r][k]
		local e = list[k]
		pcall(function()
			if e == nil then
				if s.on then
					s.icon:SetVisible(false)
					s.time:Show(false)
					s.stack:Show(false)
					s.on = false
				end
			else
				if s.path ~= e.path then
					s.icon:ClearAllTextures()
					if e.path ~= nil then s.icon:AddTexture(e.path) end
					s.path = e.path
				end
				if not s.on then
					s.icon:SetVisible(true)
					s.time:Show(true)
					s.stack:Show(true)
					s.on = true
				end
				local want = IsTextRow(r) and SKILL_FS or 12
				if s.fs ~= want then
					s.fs = want
					s.time.style:SetFontSize(want)
				end
				if IsTextRow(r) then
					s.icon:SetVisible(false)
					s.time:SetText(SlotText(e))
				else
					s.icon:SetVisible(true)
					s.time:SetText(Short(e.ms))
				end
				local st = ""
				if e.stack ~= nil and e.stack > 1 then st = tostring(e.stack) end
				s.stack:SetText(st)
			end
		end)
	end
end

local GAUGE_COLOR = {
	vocation = { 0.30, 0.90, 0.85 }, romance = { 0.95, 0.45, 0.80 }, madness = { 0.90, 0.25, 0.20 },
}
local gauges = {}

local function GaugeNames(tip)
	local names = {}
	if type(tip) ~= "string" then return names end
	local head = string.match(tip, "^[^\r\n]*") or ""
	for nm in string.gmatch(head, "|c%x%x%x%x%x%x%x%x(.-)|r") do names[#names + 1] = nm end
	return names
end

local function ColorOf(key)
	if type(key) == "string" then
		for k, c in pairs(GAUGE_COLOR) do
			if string.find(key, k, 1, true) then return c end
		end
	end
	return { 0.95, 0.75, 0.30 }
end

local function ReadGauges()
	local out = {}
	local ok, info = pcall(function() return X2CombatResource:GetCombatResourceInfo() end)
	if not ok or type(info) ~= "table" then
		gauges = out
		return
	end
	for _, g in ipairs(info) do
		if type(g) == "table" then
			local names = GaugeNames(g.tooltip)
			for i = 1, 2 do
				local cv = tonumber(g["resource" .. i .. "Current"])
				local mx = tonumber(g["resource" .. i .. "Max"])
				if cv ~= nil and mx ~= nil and mx > 0 and cv > 0 then
					out[#out + 1] = { name = names[i] or "", cur = cv, max = mx,
						color = ColorOf(g["resource" .. i .. "ColorKey"]) }
				end
			end
		end
	end
	gauges = out
end

FillGauges = function(p)
	local n = 0
	for i = 1, GAUGE_MAX do
		local slot = p.gauge[i]
		local gd = (showGauge == 1) and gauges[i] or nil
		pcall(function()
			if gd == nil then
				if slot.on then
					slot.bg:SetVisible(false)
					slot.fill:SetVisible(false)
					slot.text:Show(false)
					slot.on = false
				end
				return
			end
			n = n + 1
			local gw, gh = GW(), GH()
			local y = -(i * (gh + GAUGE_GAP))
			local x = -math.floor(gw / 2)
			slot.bg:SetExtent(gw, gh)
			slot.bg:AddAnchor("TOPLEFT", p.win, x, y)
			slot.fill:AddAnchor("TOPLEFT", p.win, x, y)
			local wFill = math.floor(gw * math.min(gd.cur, gd.max) / gd.max + 0.5)
			if wFill < 1 then wFill = 1 end
			slot.fill:SetExtent(wFill, gh)
			slot.fill:SetColor(gd.color[1], gd.color[2], gd.color[3], 0.95)
			if slot.fs ~= GF() then
				slot.fs = GF()
				slot.text.style:SetFontSize(slot.fs)
			end
			slot.text:SetExtent(gw + 60, gh + 6)
			slot.text:AddAnchor("TOPLEFT", p.win, x - 30, y - 3)
			slot.text:SetText(gd.name .. " " .. gd.cur .. "/" .. gd.max)
			if not slot.on then
				slot.bg:SetVisible(true)
				slot.fill:SetVisible(true)
				slot.text:Show(true)
				slot.on = true
			end
		end)
	end
	return n
end

local function Wanted(key, e)
	if cfg[key].all == 1 then return not InSet(hid[key], e.id, e.name) end
	return InSet(sel[key], e.id, e.name)
end

FillPlate = function(unit)
	unit = PLATE_OF[unit] or unit
	local p = plate[unit]
	if p == nil then return end
	local c = cfg[unit]
	local picks = { {}, {}, {} }
	local blocked = (unit == "target" and TargetIsMe())
	if c.on == 1 and not blocked then
		local buffs, debuffs = {}, {}
		for _, e in ipairs(cur[unit]) do
			local alive = (e.ms == nil or e.ms >= 0)
			if alive and Wanted(unit, e) then
				if e.kind == "debuff" then
					debuffs[#debuffs + 1] = e
				else
					buffs[#buffs + 1] = e
				end
			end
		end
		local all = {}
		for _, e in ipairs(buffs) do all[#all + 1] = e end
		for _, e in ipairs(debuffs) do all[#all + 1] = e end
		for i, e in ipairs(all) do
			local r = (i <= SLOTS) and 1 or 2
			if #picks[r] < SLOTS then table.insert(picks[r], e) end
		end
	end
	local sk = SKILL_OF[unit]
	if sk ~= nil and cfg[sk].on == 1 and not blocked then
		for _, e in ipairs(cur[sk]) do
			if (e.ms or 0) > 0 and Wanted(sk, e) and #picks[SKILL_ROW] < SLOTS then
				table.insert(picks[SKILL_ROW], e)
			end
		end
	end
	local nG = 0
	if p.gauge ~= nil then nG = FillGauges(p) end
	local base = (nG > 0) and (nG * (GH() + GAUGE_GAP) + 2) or 0
	if base ~= p.base then
		p.base = base
		p.n = { -1, -1, -1 }
		p.lv3 = -1
	end
	if p.mode ~= HORIZ or p.stext ~= SKILL_TEXT then
		p.mode = HORIZ
		p.stext = SKILL_TEXT
		p.n = { -1, -1, -1 }
		p.lv3 = -1
	end
	for r = 1, 2 do
		local n = #picks[r]
		if p.n[r] ~= n then
			if HORIZ == 1 then LayoutRow(p, r, n) else LayoutCol(p, r, COL_X[r]()) end
			p.n[r] = n
		end
		FillSlots(p, r, picks[r])
	end
	if p.row[SKILL_ROW] ~= nil and IsTextRow(SKILL_ROW) then
		local lvl = 0
		if #picks[2] > 0 then lvl = 2 elseif #picks[1] > 0 then lvl = 1 end
		LayoutTextRow(p, picks[SKILL_ROW], lvl + 1)
		p.n[SKILL_ROW] = -1
		p.lv3 = -1
		FillSlots(p, SKILL_ROW, picks[SKILL_ROW])
	elseif p.row[SKILL_ROW] ~= nil then
		local n = #picks[SKILL_ROW]
		if HORIZ == 1 then
			local lvl = 0
			if #picks[2] > 0 then lvl = 2 elseif #picks[1] > 0 then lvl = 1 end
			if p.n[SKILL_ROW] ~= n or p.lv3 ~= lvl then
				LayoutRow(p, SKILL_ROW, n, lvl + 1)
				p.n[SKILL_ROW] = n
				p.lv3 = lvl
			end
		elseif p.n[SKILL_ROW] ~= n then
			LayoutCol(p, SKILL_ROW, COL_X[SKILL_ROW]())
			p.n[SKILL_ROW] = n
		end
		FillSlots(p, SKILL_ROW, picks[SKILL_ROW])
	end
	p.any = (#picks[1] + #picks[2] + #picks[3] + nG) > 0
end

local function Follow(unit, dt)
	local p = plate[unit]
	if p == nil then return end
	local show = p.any
	local x, y, z = nil, nil, nil
	if show then
		local ok, a, b, c = pcall(function() return X2Unit:GetUnitScreenPosition(unit) end)
		x, y, z = tonumber(a), tonumber(b), tonumber(c)
		if not ok or x == nil or y == nil or z == nil or z <= 0 then show = false end
	end
	pcall(function()
		if show then
			local dx = (p.sx ~= nil) and (x - p.sx) or 0
			local dy = (p.sy ~= nil) and (y - p.sy) or 0
			if p.sx == nil or not p.shown or math.abs(dx) > SNAP_PX or math.abs(dy) > SNAP_PX then
				p.sx, p.sy = x, y
			elseif math.abs(dx) > DEAD_PX or math.abs(dy) > DEAD_PX then
				local k = 1 - (1 - SMOOTH) ^ ((tonumber(dt) or 16) / 16)
				if k > 1 then k = 1 end
				p.sx = p.sx + dx * k
				p.sy = p.sy + dy * k
			end
			local ax = math.floor(p.sx + 0.5)
			local ay = math.floor(p.sy + 0.5) - LIFT
			if ax ~= p.ax or ay ~= p.ay then
				p.win:AddAnchor("TOPLEFT", "UIParent", ax, ay)
				p.ax, p.ay = ax, ay
			end
		end
		if show ~= p.shown then
			p.win:Show(show)
			p.shown = show
		end
	end)
end

local function Entry(id, name)
	if type(name) == "string" and name ~= "" then return { id = id, name = name, byname = 1 } end
	return { id = id }
end

local function RemoveFrom(list, id, name)
	for i = #list, 1, -1 do
		local it = list[i]
		if (id ~= nil and it.id == id) or
			(type(name) == "string" and it.byname == 1 and it.name == name) then
			table.remove(list, i)
		end
	end
end

local function Toggle(u, id, name)
	local allMode = (cfg[u].all == 1)
	local list = allMode and cfg[u].hide or cfg[u].list
	local set = allMode and hid[u] or sel[u]
	local label = name or ("#" .. tostring(id))
	if InSet(set, id, name) then
		RemoveFrom(list, id, name)
		Note(label .. (allMode and "  다시 띄운다" or "  이름표에서 내렸다"))
	else
		if #list >= LIST_MAX then
			Note("[!]" .. LIST_MAX .. "개까지다. 안 쓰는 걸 먼저 빼라")
			return
		end
		local e = Entry(id, name)
		table.insert(list, e)
		if allMode then
			Note(label .. "  숨겼다")
		else
			Note(label .. "  이름표에 띄운다" .. (e.byname == 1 and "  (같은 이름 전부)" or ""))
		end
	end
	RebuildSel(u)
	Save()
	FillPlate(u)
	RefreshWin()
end

local SEARCH_MAX = 200
local searchRows, searchCut = nil, false

local function SearchRows(q)
	local out = {}
	local isSkill = IsSkillTab(tab)
	local src = isSkill and BPLT_SKILLS or BPLT_NAMES
	if type(src) ~= "table" then return out, false end
	local exact, head, rest = {}, {}, {}
	for _, r in ipairs(src) do
		local n = r[1]
		if n == q then
			exact[#exact + 1] = r
		elseif string.sub(n, 1, #q) == q then
			head[#head + 1] = r
		elseif string.find(n, q, 1, true) then
			rest[#rest + 1] = r
		end
	end
	local iex, ihead, irest = {}, {}, {}
	if isSkill and type(BPLT_ITEMS) == "table" then
		for _, r in ipairs(BPLT_ITEMS) do
			local n = r[1]
			if n == q or r[2] == q then
				iex[#iex + 1] = r
			elseif string.sub(n, 1, #q) == q then
				ihead[#ihead + 1] = r
			elseif string.find(n, q, 1, true) or string.find(r[2], q, 1, true) then
				irest[#irest + 1] = r
			end
		end
	end
	local function add(r, item)
		if item then
			out[#out + 1] = { name = r[2], label = r[1], id = r[3], catalog = true, skill = true, item = true }
		elseif isSkill then
			out[#out + 1] = { name = r[1], id = r[2], catalog = true, skill = true }
		else
			out[#out + 1] = { name = r[1], icon = r[2], variants = r[3], catalog = true }
		end
	end
	for _, grp in ipairs({ { exact, false }, { iex, true }, { head, false }, { ihead, true },
		{ rest, false }, { irest, true } }) do
		for _, r in ipairs(grp[1]) do
			if #out >= SEARCH_MAX then return out, true end
			add(r, grp[2])
		end
	end
	return out, false
end

local aliasEdit = nil
local function PickAlias(e)
	if not IsSkillTab(tab) or e == nil or type(e.name) ~= "string" then return end
	aliasTarget = string.match(e.name, "^(.-):%s") or e.name
	pcall(function() aliasEdit:SetText(aliasMap[aliasTarget] or "") end)
	Note("'" .. aliasTarget .. "' 별칭을 오른쪽 칸에 쓰고 엔터  (" .. ALIAS_MAX .. "글자까지, 비우면 원래대로)")
end

local function ApplyAlias()
	if aliasTarget == nil then
		Note("[!]먼저 스킬 줄을 오른쪽 클릭해서 고르라")
		return
	end
	local t = nil
	pcall(function() t = aliasEdit:GetText() end)
	t = string.match(tostring(t or ""), "^%s*(.-)%s*$")
	if t == "" then
		aliasMap[aliasTarget] = nil
		Note("'" .. aliasTarget .. "' 별칭을 지웠다 (원래 줄임말로)")
	else
		t = Utf8Head(t, ALIAS_MAX)
		aliasMap[aliasTarget] = t
		Note("'" .. aliasTarget .. "' -> '" .. t .. "'")
	end
	Save()
	for _, u in ipairs(UNITS) do FillPlate(u) end
	RefreshWin()
end

local function DoSearch()
	local q = nil
	pcall(function() q = searchEdit:GetText() end)
	q = string.match(tostring(q or ""), "^%s*(.-)%s*$")
	if q == "" then
		query, searchRows, searchCut = nil, nil, false
	else
		query = q
		searchRows, searchCut = SearchRows(q)
	end
	page = 1
	Note("")
	RefreshWin()
end

local function ClearSearch()
	pcall(function() searchEdit:SetText("") end)
	query, searchRows, searchCut = nil, nil, false
	page = 1
	Note("")
	RefreshWin()
end

local function ListRows()
	if query ~= nil and searchRows ~= nil then return searchRows end
	local out, seenId, seenName = {}, {}, {}
	for _, e in ipairs(cur[tab]) do
		if not seenId[e.id] then
			seenId[e.id] = true
			if e.name ~= nil then seenName[e.name] = true end
			out[#out + 1] = e
		end
	end
	local keep = (cfg[tab].all == 1) and cfg[tab].hide or cfg[tab].list
	for _, it in ipairs(keep) do
		local dup = (it.id ~= nil and seenId[it.id]) or (it.name ~= nil and seenName[it.name])
		if not dup then
			if it.id ~= nil then seenId[it.id] = true end
			if it.name ~= nil then seenName[it.name] = true end
			out[#out + 1] = { id = it.id, name = it.name, absent = true }
		end
	end
	if IsSkillTab(tab) then
		local wantMine = (tab == "myskill")
		for _, r in ipairs(recent) do
			if (r.mine == true) == wantMine and not seenName[r.name] then
				seenName[r.name] = true
				out[#out + 1] = { id = r.id, name = r.name, absent = true, recent = true }
			end
		end
	end
	return out
end

local function PageCount(n)
	local pc = math.floor((n + ROWS - 1) / ROWS)
	if pc < 1 then pc = 1 end
	return pc
end

local function OnOff(v) return (v == 1) and "켜짐" or "꺼짐" end

RefreshWin = function()
	if mainWindow == nil or not mainWindow:IsVisible() then return end
	local c = cfg[tab]
	pcall(function()
		for _, u in ipairs(TABS) do
			local b = tabBtn[u]
			if b ~= nil then
				b:SetText(u == tab and ("[ " .. UNIT_NAME[u] .. " ]") or UNIT_NAME[u])
			end
		end
		onBtn:SetText(ON_LABEL[tab] .. " 표시: " .. OnOff(c.on))
		allBtn:SetText((IsSkillTab(tab) and "쓴 것 전부: " or "걸린 것 전부: ") .. OnOff(c.all))
		gaugeBtn:SetText("게이지: " .. OnOff(showGauge))
		sizeLabel:SetText("아이콘 " .. PLATE_SIZE)
		liftLabel:SetText("높이 " .. LIFT)
		layoutBtn:SetText(HORIZ == 1 and "배치: 가로" or "배치: 세로")
		skTextBtn:SetText(SKILL_TEXT == 1 and "스킬: 이름" or "스킬: 아이콘")
	end)
	pcall(function()
		if noteLabel ~= nil and noteIsHint then
			local h
			if query ~= nil then
				h = "누르면 그 이름을 [" .. UNIT_NAME[tab] .. "] 쪽에 등록한다  (같은 이름 전부)"
			elseif tab == "skill" then
				h = "대상이 쓴 스킬·물약 쿨이 대상 이름표에 뜬다.  줄 오른쪽 클릭 = 별칭"
			elseif tab == "myskill" then
				h = "내가 쓴 스킬·물약 쿨이 내 이름표에 뜬다.  줄 오른쪽 클릭 = 별칭"
			elseif c.all == 1 then
				h = "전부 띄우는 중.  줄을 누르면 그것만 숨긴다"
			else
				h = "줄을 누르면 이름표 위에 뜬다.  싸우기 전에 위에서 이름으로 찾아 골라둬라"
			end
			noteLabel:SetText(h)
		end
	end)
	local rows = ListRows()
	pcall(function()
		if query ~= nil then
			whoLabel:SetText("검색 '" .. query .. "'  " .. #rows .. "개" ..
				(searchCut and (" (앞 " .. SEARCH_MAX .. "개만)") or "") .. "   -  [지우기] 로 돌아간다")
			whoLabel.style:SetColor(C_HEAD[1], C_HEAD[2], C_HEAD[3], C_HEAD[4])
		elseif tab == "target" or tab == "skill" then
			local nm = nil
			pcall(function() nm = X2Unit:UnitName("target") end)
			if nm == nil or nm == "" then
				whoLabel:SetText("대상이 없다.  (골라둔 목록은 그대로 보인다)")
				whoLabel.style:SetColor(C_DIM[1], C_DIM[2], C_DIM[3], C_DIM[4])
			else
				whoLabel:SetText((tab == "skill") and ("대상: " .. tostring(nm) .. "  -  위에서 스킬·아이템 이름으로 골라둔다")
					or ("대상: " .. tostring(nm)))
				whoLabel.style:SetColor(C_HEAD[1], C_HEAD[2], C_HEAD[3], C_HEAD[4])
			end
		elseif tab == "myskill" then
			whoLabel:SetText("내가 쓴 스킬·물약  -  위에서 스킬·아이템 이름으로 골라둔다")
			whoLabel.style:SetColor(C_HEAD[1], C_HEAD[2], C_HEAD[3], C_HEAD[4])
		else
			whoLabel:SetText("내게 걸린 것  -  줄을 누르면 내 이름표 위에 뜬다")
			whoLabel.style:SetColor(C_HEAD[1], C_HEAD[2], C_HEAD[3], C_HEAD[4])
		end
	end)
	local pc = PageCount(#rows)
	if page > pc then page = pc end
	if page < 1 then page = 1 end
	pcall(function() pageLabel:SetText(page .. " / " .. pc .. "   (" .. #rows .. "개)") end)
	local allMode = (c.all == 1)
	for i = 1, ROWS do
		local w = rowW[i]
		if w == nil then break end
		local e = rows[(page - 1) * ROWS + i]
		w.entry = e
		pcall(function()
			if e == nil then
				w.frame:Show(false)
				return
			end
			w.frame:Show(true)
			local on
			if allMode then on = not InSet(hid[tab], e.id, e.name)
			else on = InSet(sel[tab], e.id, e.name) end
			local path = nil
			local sk = nil
			if e.skill or IsSkillTab(tab) then sk = SkillInfo(e.id) end
			if e.catalog and not e.skill then
				if iconDir ~= nil and type(e.icon) == "string" and e.icon ~= "" then
					path = iconDir .. e.icon
				end
			elseif sk ~= nil and sk.icon ~= nil then
				path = sk.icon
			elseif not e.absent then
				path = e.path
			end
			if path ~= nil then
				if w.path ~= path then
					w.icon:ClearAllTextures()
					w.icon:AddTexture(path)
					w.path = path
				end
				w.icon:SetVisible(true)
			else
				w.icon:SetVisible(false)
			end
			local nm = e.label or e.name or ("#" .. tostring(e.id))
			if IsSkillTab(tab) and type(e.name) == "string" then
				local al = aliasMap[string.match(e.name, "^(.-):%s") or e.name]
				if al ~= nil then nm = nm .. "  [" .. al .. "]" end
			end
			w.name:SetText(nm)
			local col = C_TEXT
			if e.absent then col = C_DIM elseif e.kind == "debuff" then col = C_BAD end
			w.name.style:SetColor(col[1], col[2], col[3], col[4])
			local kind = ""
			if e.item then
				kind = "아이템"
			elseif e.catalog and e.skill then
				if sk ~= nil and (sk.cd or 0) > 0 then kind = "쿨 " .. Dur(sk.cd) end
			elseif e.catalog then
				if (e.variants or 1) > 1 then kind = e.variants .. "종" end
			elseif e.recent then kind = "최근 봄"
			elseif e.kind == "skill" then kind = "쿨 도는 중"
			elseif e.absent then kind = "지금 없음"
			elseif e.kind == "debuff" then kind = "디버프"
			elseif e.kind == "hidden" then kind = "숨은 버프"
			else kind = "버프" end
			w.kind:SetText(kind)
			if e.item then
				w.left:SetText((sk ~= nil and (sk.cd or 0) > 0) and ("쿨 " .. Dur(sk.cd)) or "")
			else
				w.left:SetText((e.absent or e.catalog) and "" or Dur(e.ms))
			end
			if on then
				w.mark:SetText("V 띄우는 중")
				w.mark.style:SetColor(C_ON[1], C_ON[2], C_ON[3], C_ON[4])
			elseif allMode then
				w.mark:SetText("X 숨김")
				w.mark.style:SetColor(C_BAD[1], C_BAD[2], C_BAD[3], C_BAD[4])
			else
				w.mark:SetText("")
			end
		end)
	end
end

local function TextButton(parent, id, text, wdt, hgt)
	local b = parent:CreateChildWidget("button", id, 0, true)
	b:SetExtent(wdt, hgt or 28)
	b:SetStyle("text_default")
	b:SetAutoResize(false)
	b:SetText(text)
	b:SetExtent(wdt, hgt or 28)
	return b
end

local function RowLabel(parent, id, text, wdt, color, align)
	local l = MakeLabel(parent, id, text, 13, color, align)
	l:SetExtent(wdt, 28)
	return l
end

local function OnLeft(b, fn)
	b:SetHandler("OnClick", function(_, arg)
		if arg ~= "RightButton" then fn() end
	end)
end

local function ChangeSize(d)
	PLATE_SIZE = Clamp(PLATE_SIZE + d, PLATE_MIN, PLATE_MAX)
	for _, u in ipairs(UNITS) do
		if plate[u] ~= nil then
			plate[u].n = { -1, -1, -1 }
			plate[u].lv3 = -1
		end
		FillPlate(u)
	end
	Save()
	RefreshWin()
end

local function ChangeLift(d)
	LIFT = Clamp(LIFT + d, LIFT_MIN, LIFT_MAX)
	Save()
	RefreshWin()
end

local function BuildWindow()
	mainWindow = CreateEmptyWindow("bpltWindow", "UIParent")
	mainWindow:SetExtent(WIN_W, WIN_H)
	mainWindow:AddAnchor("CENTER", "UIParent", 0, -100)
	mainWindow:EnableDrag(true)
	mainWindow:Clickable(true)
	mainWindow:SetCloseOnEscape(true)
	mainWindow:Show(false)
	pcall(function()
		local bg = mainWindow:CreateDrawable("ui/common/default.dds", "main_bg", "background")
		bg:AddAnchor("TOPLEFT", mainWindow, -5, -5)
		bg:AddAnchor("BOTTOMRIGHT", mainWindow, 5, 5)
	end)
	mainWindow:SetHandler("OnDragStart", function(self) self:StartMoving() end)
	mainWindow:SetHandler("OnDragStop", function(self) self:StopMovingOrSizing() end)

	local title = MakeLabel(mainWindow, "bpltTitle", "이름표 버프", 18, C_HEAD)
	title:AddAnchor("TOPLEFT", mainWindow, 14, 12)

	local close = mainWindow:CreateChildWidget("button", "bpltClose", 0, true)
	close:AddAnchor("TOPRIGHT", mainWindow, 3, -3)
	close:SetStyle("btn_close_default")
	OnLeft(close, function() mainWindow:Show(false) end)

	local prev = nil
	for _, u in ipairs(TABS) do
		local b = TextButton(mainWindow, "bpltTab_" .. u, UNIT_NAME[u], IsSkillTab(u) and 84 or 64)
		if prev == nil then
			b:AddAnchor("TOPLEFT", mainWindow, 14, 40)
		else
			b:AddAnchor("LEFT", prev, "RIGHT", 6, 0)
		end
		local uu = u
		OnLeft(b, function()
			tab = uu
			page = 1
			if query ~= nil then searchRows, searchCut = SearchRows(query) end
			Note("")
			RefreshWin()
		end)
		tabBtn[u] = b
		prev = b
	end

	onBtn = TextButton(mainWindow, "bpltOn", "", 132)
	onBtn:AddAnchor("LEFT", prev, "RIGHT", 14, 0)
	OnLeft(onBtn, function()
		local c = cfg[tab]
		c.on = (c.on == 1) and 0 or 1
		Save()
		FillPlate(tab)
		RefreshWin()
	end)

	allBtn = TextButton(mainWindow, "bpltAll", "", 132)
	allBtn:AddAnchor("LEFT", onBtn, "RIGHT", 6, 0)
	OnLeft(allBtn, function()
		local c = cfg[tab]
		c.all = (c.all == 1) and 0 or 1
		Note("")
		Save()
		FillPlate(tab)
		RefreshWin()
	end)

	local okEdit, editErr = pcall(function()
		local editType = UOT_X2_EDITBOX or 53
		searchEdit = mainWindow:CreateChildWidgetByType(editType, "bpltSearch", 0, true)
		searchEdit:SetExtent(220, 28)
		searchEdit:AddAnchor("TOPLEFT", mainWindow, 16, 84)
		searchEdit:SetInset(5, 5, 5, 5)
		searchEdit:EnableFocus(true)
		searchEdit:UseSelectAllWhenFocused(true)
		searchEdit:SetMaxTextLength(30)
		searchEdit:SetGuideText("버프 이름 (예: 기절)")
		searchEdit.style:SetAlign(ALIGN_LEFT)
		searchEdit.style:SetColor(C_TEXT[1], C_TEXT[2], C_TEXT[3], C_TEXT[4])
		local seBg = searchEdit:CreateDrawable("ui/common/default.dds", "editbox_df", "background")
		seBg:AddAnchor("TOPLEFT", searchEdit, 0, 0)
		seBg:AddAnchor("BOTTOMRIGHT", searchEdit, 0, 0)
		searchEdit:SetHandler("OnEnterPressed", function() DoSearch() end)
	end)
	if okEdit then
		local findBtn = TextButton(mainWindow, "bpltFind", "찾기", 60)
		findBtn:AddAnchor("LEFT", searchEdit, "RIGHT", 6, 0)
		OnLeft(findBtn, DoSearch)
		local clrBtn = TextButton(mainWindow, "bpltClear", "지우기", 60)
		clrBtn:AddAnchor("LEFT", findBtn, "RIGHT", 6, 0)
		OnLeft(clrBtn, ClearSearch)
		local okA = pcall(function()
			local editType = UOT_X2_EDITBOX or 53
			aliasEdit = mainWindow:CreateChildWidgetByType(editType, "bpltAlias", 0, true)
			aliasEdit:SetExtent(110, 28)
			aliasEdit:AddAnchor("LEFT", clrBtn, "RIGHT", 16, 0)
			aliasEdit:SetInset(5, 5, 5, 5)
			aliasEdit:EnableFocus(true)
			aliasEdit:UseSelectAllWhenFocused(true)
			aliasEdit:SetMaxTextLength(8)
			aliasEdit:SetGuideText("별칭")
			aliasEdit.style:SetAlign(ALIGN_LEFT)
			aliasEdit.style:SetColor(C_TEXT[1], C_TEXT[2], C_TEXT[3], C_TEXT[4])
			local aBg = aliasEdit:CreateDrawable("ui/common/default.dds", "editbox_df", "background")
			aBg:AddAnchor("TOPLEFT", aliasEdit, 0, 0)
			aBg:AddAnchor("BOTTOMRIGHT", aliasEdit, 0, 0)
			aliasEdit:SetHandler("OnEnterPressed", function() ApplyAlias() end)
		end)
		if okA then
			local aBtn = TextButton(mainWindow, "bpltAliasBtn", "별칭", 60)
			aBtn:AddAnchor("LEFT", aliasEdit, "RIGHT", 6, 0)
			OnLeft(aBtn, ApplyAlias)
		else
			aliasEdit = nil
		end
	else
		searchEdit = nil
		Say("[!]검색칸을 못 만들었다: " .. tostring(editErr))
	end

	whoLabel = MakeLabel(mainWindow, "bpltWho", "", 14, C_HEAD)
	whoLabel:AddAnchor("TOPLEFT", mainWindow, 16, 126)
	whoLabel:SetWidth(WIN_W - 32)

	local listArea = mainWindow:CreateChildWidget("window", "bpltList", 0, true)
	listArea:SetExtent(WIN_W - 28, ROWS * ROW_H)
	listArea:AddAnchor("TOPLEFT", mainWindow, 14, LIST_TOP)
	for i = 1, ROWS do
		local f = listArea:CreateChildWidget("button", "bpltRow" .. i, 0, true)
		f:SetExtent(WIN_W - 28, ROW_H)
		f:AddAnchor("TOPLEFT", listArea, 0, (i - 1) * ROW_H)
		f:SetText("")
		f:Show(false)
		pcall(function()
			if i % 2 == 0 then
				local stripe = f:CreateColorDrawable(0.35, 0.25, 0.10, 0.07, "background")
				stripe:AddAnchor("TOPLEFT", f, 0, 0)
				stripe:AddAnchor("BOTTOMRIGHT", f, 0, 0)
				f:SetNormalBackground(stripe)
			end
			local hl = f:CreateColorDrawable(0.45, 0.62, 0.90, 0.22, "background")
			hl:AddAnchor("TOPLEFT", f, 0, 0)
			hl:AddAnchor("BOTTOMRIGHT", f, 0, 0)
			f:SetHighlightBackground(hl)
		end)
		local w = { frame = f }
		w.icon = f:CreateIconDrawable("artwork")
		w.icon:SetExtent(ROW_H - 4, ROW_H - 4)
		w.icon:AddAnchor("LEFT", f, 4, 0)
		w.icon:SetVisible(false)
		w.name = MakeLabel(f, "bpltName" .. i, "", 14, C_TEXT)
		w.name:AddAnchor("LEFT", f, ROW_H + 6, 0)
		w.name:SetWidth(190)
		w.kind = MakeLabel(f, "bpltKind" .. i, "", 12, C_DIM)
		w.kind:AddAnchor("LEFT", f, 230, 0)
		w.kind:SetWidth(64)
		w.left = MakeLabel(f, "bpltLeft" .. i, "", 12, C_DIM)
		w.left:AddAnchor("LEFT", f, 294, 0)
		w.left:SetWidth(70)
		w.mark = MakeLabel(f, "bpltMark" .. i, "", 12, C_ON)
		w.mark:AddAnchor("LEFT", f, 362, 0)
		w.mark:SetWidth(72)
		f:SetHandler("OnClick", function(_, arg)
			local e = w.entry
			if e == nil then return end
			if arg == "RightButton" then
				PickAlias(e)
			else
				Toggle(tab, e.id, e.name)
			end
		end)
		rowW[i] = w
	end

	local LINE = 40
	local y1 = LIST_TOP + ROWS * ROW_H + 10

	local prevBtn = TextButton(mainWindow, "bpltPrev", "이전", 60)
	prevBtn:AddAnchor("TOPLEFT", mainWindow, 14, y1)
	OnLeft(prevBtn, function()
		page = page - 1
		RefreshWin()
	end)
	pageLabel = RowLabel(mainWindow, "bpltPage", "", 120, C_DIM, ALIGN_CENTER)
	pageLabel:AddAnchor("LEFT", prevBtn, "RIGHT", 6, 0)
	local nextBtn = TextButton(mainWindow, "bpltNext", "다음", 60)
	nextBtn:AddAnchor("LEFT", pageLabel, "RIGHT", 6, 0)
	OnLeft(nextBtn, function()
		page = page + 1
		RefreshWin()
	end)

	sizeLabel = RowLabel(mainWindow, "bpltSize", "", 90, C_TEXT)
	sizeLabel:AddAnchor("TOPLEFT", mainWindow, 18, y1 + LINE)
	local sMinus = TextButton(mainWindow, "bpltSizeMinus", "작게", 60)
	sMinus:AddAnchor("LEFT", sizeLabel, "RIGHT", 6, 0)
	OnLeft(sMinus, function() ChangeSize(-2) end)
	local sPlus = TextButton(mainWindow, "bpltSizePlus", "크게", 60)
	sPlus:AddAnchor("LEFT", sMinus, "RIGHT", 6, 0)
	OnLeft(sPlus, function() ChangeSize(2) end)

	liftLabel = RowLabel(mainWindow, "bpltLift", "", 90, C_TEXT)
	liftLabel:AddAnchor("TOPLEFT", mainWindow, 18, y1 + LINE * 2)
	local lDown = TextButton(mainWindow, "bpltLiftDown", "아래로", 60)
	lDown:AddAnchor("LEFT", liftLabel, "RIGHT", 6, 0)
	OnLeft(lDown, function() ChangeLift(-10) end)
	local lUp = TextButton(mainWindow, "bpltLiftUp", "위로", 60)
	lUp:AddAnchor("LEFT", lDown, "RIGHT", 6, 0)
	OnLeft(lUp, function() ChangeLift(10) end)

	gaugeBtn = TextButton(mainWindow, "bpltGaugeBtn", "", 110)
	gaugeBtn:AddAnchor("LEFT", sPlus, "RIGHT", 16, 0)
	OnLeft(gaugeBtn, function()
		showGauge = (showGauge == 1) and 0 or 1
		FillPlate("player")
		Save()
		RefreshWin()
	end)

	local fsLabel = RowLabel(mainWindow, "bpltFsLabel", "스킬 글자", 64, C_TEXT)
	fsLabel:AddAnchor("LEFT", gaugeBtn, "RIGHT", 16, 0)
	pcall(function()
		local editType = UOT_X2_EDITBOX or 53
		fsEdit = mainWindow:CreateChildWidgetByType(editType, "bpltSkFs", 0, true)
		fsEdit:SetExtent(46, 28)
		fsEdit:AddAnchor("LEFT", fsLabel, "RIGHT", 4, 0)
		fsEdit:SetInset(5, 5, 5, 5)
		fsEdit:EnableFocus(true)
		fsEdit:UseSelectAllWhenFocused(true)
		fsEdit:SetMaxTextLength(2)
		fsEdit.style:SetAlign(ALIGN_CENTER)
		fsEdit.style:SetColor(C_TEXT[1], C_TEXT[2], C_TEXT[3], C_TEXT[4])
		local fBg = fsEdit:CreateDrawable("ui/common/default.dds", "editbox_df", "background")
		fBg:AddAnchor("TOPLEFT", fsEdit, 0, 0)
		fBg:AddAnchor("BOTTOMRIGHT", fsEdit, 0, 0)
		fsEdit:SetText(tostring(SKILL_FS))
		fsEdit:SetHandler("OnEnterPressed", function()
			local v = nil
			pcall(function() v = tonumber(fsEdit:GetText()) end)
			if v == nil then
				Note("[!]숫자를 써라 (" .. SKILL_FS_MIN .. "~" .. SKILL_FS_MAX .. ")")
			else
				SKILL_FS = Clamp(math.floor(v), SKILL_FS_MIN, SKILL_FS_MAX)
				Note("스킬 글자 크기 " .. SKILL_FS)
				Save()
				for _, u in ipairs(UNITS) do FillPlate(u) end
			end
			pcall(function() fsEdit:SetText(tostring(SKILL_FS)) end)
			RefreshWin()
		end)
	end)

	layoutBtn = TextButton(mainWindow, "bpltLayout", "", 100)
	layoutBtn:AddAnchor("LEFT", lUp, "RIGHT", 16, 0)
	OnLeft(layoutBtn, function()
		HORIZ = (HORIZ == 1) and 0 or 1
		for _, u in ipairs(UNITS) do FillPlate(u) end
		Save()
		RefreshWin()
	end)

	skTextBtn = TextButton(mainWindow, "bpltSkText", "", 100)
	skTextBtn:AddAnchor("LEFT", layoutBtn, "RIGHT", 6, 0)
	OnLeft(skTextBtn, function()
		SKILL_TEXT = (SKILL_TEXT == 1) and 0 or 1
		for _, u in ipairs(UNITS) do FillPlate(u) end
		Save()
		RefreshWin()
	end)

	noteLabel = MakeLabel(mainWindow, "bpltNote",
		"줄을 누르면 이름표 위에 뜬다.  다시 누르면 내린다", 12, C_DIM)
	noteLabel:AddAnchor("BOTTOMLEFT", mainWindow, 16, -12)
	noteLabel:SetWidth(WIN_W - 32)
end

local function ToggleWindow()
	if mainWindow == nil then
		Say("창을 못 만들었다. ArcheRage.log 를 봐라")
		return
	end
	local v = not mainWindow:IsVisible()
	mainWindow:Show(v)
	if v then
		for _, u in ipairs(UNITS) do cur[u] = Collect(u) end
		pcall(BuildSkillCur)
		RefreshWin()
	end
end

local function BuildIcon(px, py)
	local icon = UIParent:CreateWidget("button", "bpltIcon", "UIParent", "")
	icon:SetExtent(ICON_SIZE, ICON_SIZE)
	icon:AddAnchor("TOPLEFT", "UIParent", px, py)
	icon:SetText("")
	icon:Show(true)
	icon:EnableDrag(true)
	iconBtn = icon
	local ok = pcall(function()
		local d = icon:CreateIconDrawable("artwork")
		d:SetExtent(ICON_SIZE, ICON_SIZE)
		d:AddAnchor("CENTER", icon, 0, 0)
		d:SetVisible(true)
		d:AddTexture(ICON_TEX)
		iconDraw = d
	end)
	if not ok then
		pcall(function()
			local plateBg = icon:CreateColorDrawable(0.30, 0.22, 0.12, 0.85, "background")
			plateBg:AddAnchor("TOPLEFT", icon, -2, -2)
			plateBg:AddAnchor("BOTTOMRIGHT", icon, 2, 2)
			icon:SetNormalBackground(plateBg)
		end)
		icon:SetExtent(84, 26)
		icon:SetStyle("text_default")
		icon:SetAutoResize(false)
		icon:SetText("이름표버프")
	end
	OnLeft(icon, ToggleWindow)
	icon:SetHandler("OnDragStart", function(self) self:StartMoving() end)
	icon:SetHandler("OnDragStop", function(self)
		self:StopMovingOrSizing()
		Save()
	end)
end

local function OnChat(channel, relation, name, message)
	if name ~= X2Unit:UnitName("player") then return end
	if type(message) ~= "string" then return end
	local kw = string.match(message, "^!bp%s*(.*)$")
	if kw == nil then return end
	kw = kw:match("^%s*(.-)%s*$")
	if kw == "log" then
		if DumpTrace() then
			Say("진단 기록 " .. #trace .. "개를 적었다: Documents\\ArcheRage\\Addon\\buffplate\\debug.txt")
		else
			Say("[!]진단 기록을 못 적었다")
		end
		return
	end
	if kw == "reset" then
		pcall(function()
			iconBtn:AddAnchor("TOPLEFT", "UIParent", 400, 300)
			Save()
		end)
		Say("아이콘을 화면 가운데 근처로 옮겼다")
		return
	end
	ToggleWindow()
end

local saved = Load()

for _, u in ipairs(UNITS) do
	local okP, errP = pcall(BuildPlate, u)
	if not okP then
		plate[u] = nil
		Say("[!]" .. UNIT_NAME[u] .. " 이름표 칸을 못 만들었다: " .. tostring(errP))
	end
end

local okWin, errWin = pcall(BuildWindow)
if not okWin then
	mainWindow = nil
	Say("[!]창을 못 만들었다: " .. tostring(errWin))
end

local okIcon, errIcon = pcall(function()
	local px = Num(saved, "x") or 360
	local py = Num(saved, "y") or 410
	BuildIcon(px, py)
	if Num(saved, "shown") == 0 then
		iconShown = false
		iconBtn:Show(false)
	end
end)
if not okIcon then Say("[!]아이콘을 못 만들었다: " .. tostring(errIcon)) end

local ticker = CreateEmptyWindow("bpltTicker", "UIParent")
ticker:Show(true)
ticker:SetHandler("OnUpdate", function(_, dt)
	local d = tonumber(dt) or 16
	if d > 0 and d < 5 then d = d * 1000 end
	accData = accData + d
	accList = accList + d
	nowMs = nowMs + d
	if accData >= DATA_MS then
		accData = 0
		pcall(PollMyCd)
		pcall(BuildSkillCur)
		pcall(ReadGauges)
		for _, u in ipairs(UNITS) do
			cur[u] = Collect(u)
			pcall(FillPlate, u)
		end
	end
	for _, u in ipairs(UNITS) do Follow(u, d) end
	if accList >= LIST_MS then
		accList = 0
		pcall(RefreshWin)
	end
end)

local function SetIconShown(v)
	iconShown = v
	pcall(function() if iconBtn ~= nil then iconBtn:Show(v) end end)
	if not v then pcall(function() if mainWindow ~= nil then mainWindow:Show(false) end end) end
	Save()
end

local okEsc, escErr = pcall(function()
	if CreateSimpleButton == nil then return end
	local b = CreateSimpleButton("이름표버프", 700, -400)
	b:SetHandler("OnClick", function()
		SetIconShown(not iconShown)
		Say(iconShown and "아이콘을 켰다" or "아이콘을 껐다.  이름표 위 버프는 계속 뜬다  (ESC 의 [이름표버프] 로 다시 켠다)")
	end)
end)
if not okEsc then Say("[!]ESC 메뉴 버튼을 못 만들었다: " .. tostring(escErr)) end

UIParent:SetEventHandler(UIEVENT_TYPE.CHAT_MESSAGE, OnChat)
UIParent:SetEventHandler(UIEVENT_TYPE.COMBAT_MSG, OnCombat)

Say("준비됨.  아이콘을 누르면 창이 열린다")
