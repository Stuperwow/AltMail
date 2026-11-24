-- AltMail
-- A panel next to the mailbox:
--   * Click an alt to fill in the recipient and subject (switches to the Send Mail tab).
--   * Pick items from your bags (click, shift-click for all of that item, or All/None/Mats),
--     then "Attach" puts up to 12 of them on the mail. Press Send, then Attach again for the rest.
-- Alts are learned automatically the first time you log in on each character with AltMail on.
-- Routes (1.3): "send every X to Y" rules - a specific item, name contains text, or a category,
-- to an alt or your bank alt. "Prep mail" fills in the name and attaches everything for the
-- next recipient; after each Send it preps the next one.

local ADDON_NAME = ...

local MAX_ATTACH = ATTACHMENTS_MAX_SEND or 12
local ICON_SIZE, ICON_GAP, ICONS_PER_ROW = 32, 4, 7
local PANEL_W = ICONS_PER_ROW * (ICON_SIZE + ICON_GAP) + 40

local db
local panel, subjectBox, addBox, altButtons, altArea, scrollFrame, scrollChild, countText, statusText, attachButton
local itemButtons = {}
local bagItems = {}      -- list of { bag, slot, itemID, icon, count, quality, locked, classID }
local selected = {}      -- "bag:slot" -> itemID
local prepButton, routesButton, routesFrame
local prepActive = false -- keep prepping the next mail after each Send
local RoutesPickItem, RefreshRoutes, RoutedCount, RouteFor, RouteRecipient, OpenCatMenu -- forward

local function Print(msg)
	print("|cffffd27fAltMail|r: " .. msg)
end

local function SlotKey(bag, slot) return bag .. ":" .. slot end

------------------------------------------------------------------------
-- Alts
------------------------------------------------------------------------

-- On Forever, characters have a first name and a surname ("Stuper Bonkbolt"), and
-- UnitName's second return is that surname - not a realm. There are no realms to add.
local function FullName(first, surname)
	if type(surname) == "string" and surname ~= "" then
		return first .. " " .. surname
	end
	return first
end

local function KeyFor(name)
	return strtrim(name or ""):lower()
end

local function MyName()
	local first, surname = UnitName("player")
	if not first then return nil end
	return FullName(first, surname)
end

local function MyKey()
	return KeyFor(MyName())
end

local function RecordMe()
	local name = MyName()
	if not name then return end
	local _, class = UnitClass("player")
	local key = KeyFor(name)
	local old = db.alts[key] or {}
	db.alts[key] = {
		name = name,
		class = class,
		faction = UnitFactionGroup("player"),
		level = UnitLevel("player"),
		manual = nil,
	}
	-- If this character was saved earlier under just its first name, drop that entry.
	local first = UnitName("player")
	if first and KeyFor(first) ~= key and db.alts[KeyFor(first)] then
		db.alts[KeyFor(first)] = nil
	end
	return old
end

-- What to type in the "To:" box: just the character's name.
local function MailName(alt)
	return alt.name
end

local function IsBank(name)
	return db.bank and name and KeyFor(db.bank) == KeyFor(name)
end

-- Fix lists saved by AltMail 1.0/1.1: keys had "-Realm" on the end, a realm was stored
-- (and added to the recipient), and the current character was saved by first name only.
local function MigrateAlts()
	if db.version and db.version >= 2 then return end
	local fixed = {}
	for _, alt in pairs(db.alts) do
		if type(alt) == "table" and type(alt.name) == "string" then
			alt.realm = nil
			local key = KeyFor(alt.name)
			local existing = fixed[key]
			if existing then
				-- Merge duplicates, keeping whatever details either copy has.
				for k, v in pairs(alt) do if existing[k] == nil then existing[k] = v end end
			else
				fixed[key] = alt
			end
		end
	end
	-- Remove first-name-only leftovers when a full "First Surname" entry starts with them.
	for key, alt in pairs(fixed) do
		if not key:find(" ", 1, true) then
			for otherKey in pairs(fixed) do
				if otherKey ~= key and otherKey:sub(1, #key + 1) == key .. " " then
					fixed[key] = nil
					break
				end
			end
		end
	end
	db.alts = fixed
	db.version = 2
end

local function SortedAlts()
	local me = MyKey()
	local myFaction = UnitFactionGroup("player")
	local list = {}
	for key, alt in pairs(db.alts) do
		if key ~= me and (not alt.faction or alt.faction == myFaction) then
			list[#list + 1] = { key = key, alt = alt }
		end
	end
	table.sort(list, function(a, b) return a.alt.name:lower() < b.alt.name:lower() end)
	return list
end

local function ClassColor(class)
	local c = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or RAID_CLASS_COLORS[class])
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function ShowSendTab()
	if SendMailFrame and not SendMailFrame:IsShown() and MailFrameTab2 then
		MailFrameTab2:Click()
	end
end

local function FillMail(alt)
	ShowSendTab()
	if SendMailNameEditBox then
		SendMailNameEditBox:SetText(MailName(alt))
		SendMailNameEditBox:ClearFocus()
	end
	if SendMailSubjectEditBox then
		SendMailSubjectEditBox:SetText(db.subject or "")
	end
	statusText:SetText("To: " .. MailName(alt))
end

local RefreshAlts -- forward

local function AltButton(i)
	local b = altButtons[i]
	if b then return b end
	b = CreateFrame("Button", nil, altArea, "UIPanelButtonTemplate")
	b:SetSize((PANEL_W - 40) / 2 - 2, 20)
	local col = (i - 1) % 2
	local row = math.floor((i - 1) / 2)
	b:SetPoint("TOPLEFT", altArea, "TOPLEFT", col * ((PANEL_W - 40) / 2 + 2), -row * 22)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			if IsShiftKeyDown() then
				db.alts[self.key] = nil
				if IsBank(self.alt.name) then db.bank = nil end
				Print("Removed " .. self.alt.name .. " from your alt list.")
			elseif IsBank(self.alt.name) then
				db.bank = nil
				Print(self.alt.name .. " is no longer your bank alt.")
			else
				db.bank = self.alt.name
				Print(self.alt.name .. " is now your bank alt.")
			end
			RefreshAlts()
			if RefreshRoutes then RefreshRoutes() end
			return
		end
		FillMail(self.alt)
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(MailName(self.alt))
		if self.alt.level then GameTooltip:AddLine("Level " .. self.alt.level, 1, 1, 1) end
		if IsBank(self.alt.name) then GameTooltip:AddLine("Your bank alt", 1, 0.82, 0) end
		GameTooltip:AddLine("Click: fill in name + subject", 0.7, 0.7, 0.7)
		GameTooltip:AddLine(IsBank(self.alt.name) and "Right-click: stop using as bank alt" or "Right-click: make this your bank alt", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("Shift + right-click: remove", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	altButtons[i] = b
	return b
end

RefreshAlts = function()
	local list = SortedAlts()
	for i, entry in ipairs(list) do
		local b = AltButton(i)
		b.key, b.alt = entry.key, entry.alt
		b:SetText(entry.alt.name .. (IsBank(entry.alt.name) and " |cffffd200(bank)|r" or ""))
		local fs = b:GetFontString()
		if fs then fs:SetTextColor(ClassColor(entry.alt.class)) end
		b:Show()
	end
	for i = #list + 1, #altButtons do altButtons[i]:Hide() end

	local rows = math.max(1, math.ceil(#list / 2))
	altArea:SetHeight(rows * 22)
	altArea.empty:SetShown(#list == 0)
end

local function AddAltByName(text)
	text = strtrim(text or "")
	if text == "" then return end
	-- Drop anything after a "-" (an old-style realm tag) and tidy the spacing.
	local name = strtrim((text:gsub("%-.*$", ""):gsub("%s+", " ")))
	if name == "" then return end
	-- Capitalize each part: "stuper bonkbolt" -> "Stuper Bonkbolt"
	name = name:gsub("(%S)(%S*)", function(a, b) return a:upper() .. b:lower() end)
	local key = KeyFor(name)
	if db.alts[key] then
		Print(name .. " is already on the list.")
	else
		db.alts[key] = { name = name, faction = UnitFactionGroup("player"), manual = true }
		Print("Added " .. name .. ". Log in on them once with AltMail on to get their class color.")
	end
	RefreshAlts()
end

------------------------------------------------------------------------
-- Bag items
------------------------------------------------------------------------

local function ScanBags()
	wipe(bagItems)
	if not C_Container then return end
	local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
	for bag = 0, lastBag do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and not info.isBound then
				local classID, subclassID, isReagent
				if C_Item and C_Item.GetItemInfoInstant then
					classID, subclassID = select(6, C_Item.GetItemInfoInstant(info.itemID))
				end
				local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
				if GetInfo then
					local ok, flag = pcall(function() return select(17, GetInfo(info.itemID)) end)
					isReagent = ok and flag == true
				end
				bagItems[#bagItems + 1] = {
					bag = bag, slot = slot, itemID = info.itemID, icon = info.iconFileID,
					count = info.stackCount or 1, quality = info.quality, locked = info.isLocked,
					classID = classID, subclassID = subclassID, isReagent = isReagent, link = info.hyperlink,
					name = (info.hyperlink and info.hyperlink:match("%[(.-)%]"))
						or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(info.itemID)),
				}
			end
		end
	end

	-- Drop selections whose slot is now empty or holds something else.
	local valid = {}
	for _, it in ipairs(bagItems) do valid[SlotKey(it.bag, it.slot)] = it.itemID end
	for key, itemID in pairs(selected) do
		if valid[key] ~= itemID then selected[key] = nil end
	end
end

local function SelectedCount()
	local n = 0
	for _ in pairs(selected) do n = n + 1 end
	return n
end

local function AttachedCount()
	local n = 0
	if HasSendMailItem then
		for i = 1, MAX_ATTACH do
			if HasSendMailItem(i) then n = n + 1 end
		end
	end
	return n
end

local function UpdateCounts()
	local sel = SelectedCount()
	countText:SetText(("Bag items  -  %d selected"):format(sel))
	local free = MAX_ATTACH - AttachedCount()
	if free <= 0 then
		attachButton:SetText("Mail full")
	else
		attachButton:SetText(sel > 0 and ("Attach %d"):format(math.min(sel, free)) or "Attach")
	end
	attachButton:SetEnabled(sel > 0 and free > 0)
	if prepButton then
		local n = RoutedCount()
		prepButton:SetText(n > 0 and ("Prep mail (%d)"):format(n) or "Prep mail")
	end
end

local RefreshItems -- forward

local function ItemButton(i)
	local b = itemButtons[i]
	if b then return b end
	b = CreateFrame("Button", nil, scrollChild)
	b:SetSize(ICON_SIZE, ICON_SIZE)
	local col = (i - 1) % ICONS_PER_ROW
	local row = math.floor((i - 1) / ICONS_PER_ROW)
	b:SetPoint("TOPLEFT", col * (ICON_SIZE + ICON_GAP), -row * (ICON_SIZE + ICON_GAP))

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.border = b:CreateTexture(nil, "OVERLAY")
	b.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	b.border:SetBlendMode("ADD")
	b.border:SetPoint("CENTER")
	b.border:SetSize(ICON_SIZE * 1.8, ICON_SIZE * 1.8)
	b.check = b:CreateTexture(nil, "OVERLAY", nil, 2)
	b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	b.check:SetSize(22, 22)
	b.check:SetPoint("TOPRIGHT", 4, 4)
	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("BOTTOMRIGHT", -1, 1)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

	b:SetScript("OnClick", function(self)
		local it = self.item
		if not it then return end
		local key = SlotKey(it.bag, it.slot)
		if IsAltKeyDown() then
			-- Alt: make a route for this item.
			RoutesPickItem(it)
			return
		end
		if IsShiftKeyDown() then
			-- Shift: select/deselect every stack of this item.
			local turnOn = not selected[key]
			for _, other in ipairs(bagItems) do
				if other.itemID == it.itemID then
					selected[SlotKey(other.bag, other.slot)] = turnOn and other.itemID or nil
				end
			end
		else
			selected[key] = (not selected[key]) and it.itemID or nil
		end
		RefreshItems()
	end)
	b:SetScript("OnEnter", function(self)
		if not self.item then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetBagItem(self.item.bag, self.item.slot)
		local r = RouteFor(self.item)
		if r then GameTooltip:AddLine("Route: goes to " .. RouteRecipient(r), 0.4, 1, 0.4) end
		GameTooltip:AddLine("Click: select   Shift-click: all of this item", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("Alt-click: make a route for this item", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)

	itemButtons[i] = b
	return b
end

RefreshItems = function()
	for i, it in ipairs(bagItems) do
		local b = ItemButton(i)
		b.item = it
		b.icon:SetTexture(it.icon)
		b.count:SetText(it.count > 1 and it.count or "")
		local isSel = selected[SlotKey(it.bag, it.slot)] ~= nil
		b.check:SetShown(isSel)
		-- Locked = already attached to this mail (or otherwise in use).
		b.icon:SetDesaturated(it.locked)
		b:SetAlpha(it.locked and 0.4 or (isSel and 1 or 0.85))
		if isSel then
			b.border:SetVertexColor(0.3, 1, 0.3)
			b.border:Show()
		elseif it.quality and it.quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it.quality] then
			local c = ITEM_QUALITY_COLORS[it.quality]
			b.border:SetVertexColor(c.r, c.g, c.b)
			b.border:Show()
		else
			b.border:Hide()
		end
		b:Show()
	end
	for i = #bagItems + 1, #itemButtons do
		itemButtons[i]:Hide()
		itemButtons[i].item = nil
	end
	local rows = math.max(1, math.ceil(#bagItems / ICONS_PER_ROW))
	scrollChild:SetHeight(rows * (ICON_SIZE + ICON_GAP))
	UpdateCounts()
end

local function SelectWhere(pred, add)
	if not add then wipe(selected) end
	for _, it in ipairs(bagItems) do
		if not it.locked and pred(it) then
			selected[SlotKey(it.bag, it.slot)] = it.itemID
		end
	end
	RefreshItems()
end

local function AttachSelected()
	if InCombatLockdown() then return end
	ShowSendTab()
	if CursorHasItem() then ClearCursor() end

	-- Work out the free attachment slots up front; the server may not report a slot
	-- as filled until a moment after we drop an item in it.
	local freeSlots = {}
	for i = 1, MAX_ATTACH do
		if not HasSendMailItem(i) then freeSlots[#freeSlots + 1] = i end
	end

	-- Attach in bag order so it's predictable.
	local attached, failed = 0, 0
	for _, it in ipairs(bagItems) do
		local key = SlotKey(it.bag, it.slot)
		if selected[key] and not it.locked then
			local freeSlot = table.remove(freeSlots, 1)
			if not freeSlot then break end

			C_Container.PickupContainerItem(it.bag, it.slot)
			if CursorHasItem() then
				ClickSendMailItemButton(freeSlot)
				if CursorHasItem() then
					-- Mail refused it (soulbound, quest item, etc.); the slot is still free.
					ClearCursor()
					failed = failed + 1
					table.insert(freeSlots, 1, freeSlot)
				else
					attached = attached + 1
					it.locked = true
				end
			end
			selected[key] = nil
		end
	end

	local left = SelectedCount()
	local msg = ("Attached %d item%s."):format(attached, attached == 1 and "" or "s")
	if failed > 0 then msg = msg .. (" %d couldn't be mailed."):format(failed) end
	if left > 0 then msg = msg .. (" %d still selected - press Send, then Attach again."):format(left) end
	statusText:SetText(msg)
	RefreshItems()
end

------------------------------------------------------------------------
-- Routes: "send every X to Y"
------------------------------------------------------------------------

-- Item ID lists back up the item-type checks, in case Forever tags something differently.
local function IDSet(list)
	local t = {}
	for _, id in ipairs(list) do t[id] = true end
	return t
end

local HERBS = IDSet({
	-- Classic
	2447, 765, 2449, 785, 2450, 2452, 3820, 2453, 3355, 3369, 3356, 3357, 3818, 3821, 3358, 3819,
	4625, 8831, 8153, 8836, 8838, 8839, 8845, 8846, 13464, 13463, 13465, 13466, 13467, 13468,
	19726, 22710,
	-- Burning Crusade
	22785, 22786, 22787, 22788, 22789, 22790, 22791, 22792, 22793, 22794,
	-- Wrath
	36901, 36903, 36904, 36905, 36906, 36907, 36908, 37921, 39970,
})
local ORE = IDSet({
	2770, 2771, 2772, 2775, 2776, 3858, 7911, 10620, 11370, 23424, 23425, 23426, 23427, 36909, 36910, 36912,
})
local CLOTH = IDSet({
	2589, 2592, 4306, 4338, 14047, 14256, 14342, 21877, 33470,      -- cloth
	2996, 2997, 4305, 4339, 14048, 21840, 21845, 41510, 41511,      -- bolts and imbued
})
local ENCHANTING = IDSet({
	10940, 11083, 11137, 11176, 16204, 22445, 34054,                -- dusts
	10938, 10939, 10998, 11082, 11134, 11135, 11174, 11175, 16202, 16203,
	22447, 22446, 34056, 34055,                                     -- essences
	10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344, 22448, 22449, 34053, 34052, -- shards
	20725, 22450, 34057,                                            -- crystals
})

local function TG(it, sub) return it.classID == 7 and it.subclassID == sub end
local function NameHas(it, pat) return it.name and it.name:find(pat) ~= nil end

local CATS = {
	{ key = "ore",     label = "Ore",               test = function(it) return ORE[it.itemID] or (TG(it, 7) and NameHas(it, " Ore$")) end },
	{ key = "metal",   label = "Ore, bars & stone", test = function(it) return ORE[it.itemID] or TG(it, 7) end },
	{ key = "herb",    label = "Herbs",             test = function(it) return HERBS[it.itemID] or TG(it, 9) end },
	{ key = "cloth",   label = "Cloth",             test = function(it) return CLOTH[it.itemID] or TG(it, 5) end },
	{ key = "leather", label = "Leather & hides",   test = function(it) return TG(it, 6) end },
	{ key = "ench",    label = "Enchanting mats",   test = function(it) return ENCHANTING[it.itemID] or TG(it, 12) end },
	{ key = "elem",    label = "Elementals",        test = function(it) return TG(it, 10) end },
	{ key = "meat",    label = "Cooking meat & fish", test = function(it) return TG(it, 8) or (NameHas(it, "^Raw ") and (it.classID == 7 or it.classID == 0)) end },
	{ key = "reagent", label = "All reagents & mats", test = function(it)
		return it.isReagent or it.classID == 5 or it.classID == 7 or (it.classID == 15 and it.subclassID == 1)
			or HERBS[it.itemID] or ORE[it.itemID] or CLOTH[it.itemID] or ENCHANTING[it.itemID] or false
	end },
	{ key = "trade",   label = "Trade goods",       test = function(it) return it.classID == 7 end },
	{ key = "consum",  label = "Consumables",       test = function(it) return it.classID == 0 end },
	{ key = "gem",     label = "Gems",              test = function(it) return it.classID == 3 end },
	{ key = "recipe",  label = "Recipes",           test = function(it) return it.classID == 9 end },
	{ key = "boe",     label = "BoE gear (green+)", test = function(it) return (it.classID == 2 or it.classID == 4) and (it.quality or 0) >= 2 end },
	{ key = "bag",     label = "Bags",              test = function(it) return it.classID == 1 end },
}
local CAT_BY_KEY = {}
for i, c in ipairs(CATS) do CAT_BY_KEY[c.key] = c; c.index = i end

-- Most specific rule wins: a picked item beats "name contains", which beats a category.
local KIND_RANK = { item = 1, name = 2, cat = 3 }

RouteRecipient = function(r)
	if r.to == "@bank" then return db.bank end
	return r.to
end

local function RouteWhat(r)
	if r.kind == "item" then return r.itemName or ("item " .. tostring(r.itemID)) end
	if r.kind == "name" then return 'Name has "' .. (r.text or "") .. '"' end
	if r.kind == "cat" then return (CAT_BY_KEY[r.cat] and CAT_BY_KEY[r.cat].label) or r.cat end
	return "?"
end

local function RouteWho(r)
	if r.to == "@bank" then return "bank alt" .. (db.bank and (" (" .. db.bank .. ")") or " (none set)") end
	return r.to
end

local function RouteMatches(r, it)
	if r.kind == "item" then return it.itemID == r.itemID end
	if r.kind == "name" then
		local text = r.text and r.text:lower()
		return text and text ~= "" and it.name and it.name:lower():find(text, 1, true) ~= nil
	end
	if r.kind == "cat" then
		local c = CAT_BY_KEY[r.cat]
		return c and c.test(it) or false
	end
	return false
end

-- The route an item should follow (nil if none, or if it would go to this character).
RouteFor = function(it)
	local best, bestRank
	local me = MyKey()
	for i, r in ipairs(db.routes) do
		if r.on ~= false then
			local to = RouteRecipient(r)
			if to and KeyFor(to) ~= me and RouteMatches(r, it) then
				local rank = (KIND_RANK[r.kind] or 9) * 1000 + i
				if not bestRank or rank < bestRank then best, bestRank = r, rank end
			end
		end
	end
	return best, bestRank
end

-- Group every routable bag item by recipient, in route order.
local function BuildPlan()
	local groups, order = {}, {}
	for _, it in ipairs(bagItems) do
		if not it.locked then
			local r, rank = RouteFor(it)
			if r then
				local to = RouteRecipient(r)
				local k = KeyFor(to)
				local g = groups[k]
				if not g then
					g = { to = to, items = {}, rank = rank }
					groups[k] = g
					order[#order + 1] = g
				end
				g.items[#g.items + 1] = it
				if rank < g.rank then g.rank = rank end
			end
		end
	end
	table.sort(order, function(a, b) return a.rank < b.rank end)
	local mails = 0
	for _, g in ipairs(order) do mails = mails + math.ceil(#g.items / MAX_ATTACH) end
	return order, mails
end

RoutedCount = function()
	local n = 0
	for _, it in ipairs(bagItems) do
		if not it.locked and RouteFor(it) then n = n + 1 end
	end
	return n
end

local function NeedsBank()
	if db.bank then return false end
	for _, r in ipairs(db.routes) do
		if r.on ~= false and r.to == "@bank" then return true end
	end
	return false
end

local function Prep(auto)
	if InCombatLockdown() then return end
	if AttachedCount() > 0 then
		prepActive = false
		statusText:SetText("This mail already has items on it - send it or take them off first.")
		return
	end
	local plan, mails = BuildPlan()
	if #plan == 0 then
		prepActive = false
		if auto then
			statusText:SetText("|cff40ff40All routed mail sent!|r" .. (NeedsBank() and " (Bank alt routes skipped - right-click an alt to set one.)" or ""))
		elseif #db.routes == 0 then
			statusText:SetText("No routes yet - click Routes to set some up.")
		elseif NeedsBank() then
			statusText:SetText("Nothing to send. (Some routes go to your bank alt - right-click an alt to set one.)")
		else
			statusText:SetText("Nothing in your bags matches a route.")
		end
		return
	end
	local g = plan[1]
	FillMail({ name = g.to })
	wipe(selected)
	for _, it in ipairs(g.items) do selected[SlotKey(it.bag, it.slot)] = it.itemID end
	AttachSelected()
	prepActive = true
	local onThis = math.min(#g.items, MAX_ATTACH)
	local more = mails - 1
	statusText:SetText(("|cff40ff40Mail to %s ready (%d item%s).|r Click Send.%s"):format(
		g.to, onThis, onThis == 1 and "" or "s",
		more > 0 and (" %d more after this."):format(more) or ""))
end

------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------

local function SmallButton(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 20)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local ICON_PATH = "Interface\\AddOns\\AltMail\\AltMail.tga"

-- Sparkly envelope in the title bar, with a few stars that twinkle in turn.
local function AddTitleIcon(frame)
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetSize(30, 30)
	holder:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, 4)
	holder:SetFrameLevel(frame:GetFrameLevel() + 5)

	local icon = holder:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture(ICON_PATH)

	local spots = { { 13, 11, 14, 0 }, { -12, 10, 10, 0.6 }, { 12, -12, 9, 1.2 } }
	for _, s in ipairs(spots) do
		local star = holder:CreateTexture(nil, "OVERLAY")
		star:SetTexture("Interface\\Cooldown\\star4")
		star:SetBlendMode("ADD")
		star:SetVertexColor(1, 0.9, 0.6)
		star:SetSize(s[3], s[3])
		star:SetPoint("CENTER", holder, "CENTER", s[1], s[2])
		star:SetAlpha(0)

		local ag = star:CreateAnimationGroup()
		ag:SetLooping("REPEAT")
		local wait = ag:CreateAnimation("Alpha")
		wait:SetFromAlpha(0); wait:SetToAlpha(0); wait:SetDuration(s[4] + 0.01); wait:SetOrder(1)
		local fadeIn = ag:CreateAnimation("Alpha")
		fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.35); fadeIn:SetOrder(2)
		local spin = ag:CreateAnimation("Rotation")
		spin:SetDegrees(90); spin:SetDuration(0.7); spin:SetOrder(2)
		local fadeOut = ag:CreateAnimation("Alpha")
		fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.35); fadeOut:SetStartDelay(0.35); fadeOut:SetOrder(2)
		local rest = ag:CreateAnimation("Alpha")
		rest:SetFromAlpha(0); rest:SetToAlpha(0); rest:SetDuration(1.8 - s[4]); rest:SetOrder(3)
		ag:Play()
	end
end

local function CreatePanel()
	panel = CreateFrame("Frame", "AltMailPanel", MailFrame, "BasicFrameTemplateWithInset")
	panel:SetSize(PANEL_W, 536)
	panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, 0)
	if panel.TitleText then panel.TitleText:SetText("AltMail") end
	AddTitleIcon(panel)
	if panel.CloseButton then
		panel.CloseButton:SetScript("OnClick", function() db.hidden = true; panel:Hide()
			Print("Panel hidden. Type /altmail to bring it back.") end)
	end

	local y = -32

	-- Subject
	local subLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	subLabel:SetPoint("TOPLEFT", 16, y)
	subLabel:SetText("Subject")
	subjectBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	subjectBox:SetSize(PANEL_W - 90, 20)
	subjectBox:SetPoint("LEFT", subLabel, "RIGHT", 10, 0)
	subjectBox:SetAutoFocus(false)
	subjectBox:SetMaxLetters(64)
	subjectBox:SetText(db.subject)
	local function saveSubject(self)
		db.subject = self:GetText()
		self:ClearFocus()
	end
	subjectBox:SetScript("OnEnterPressed", saveSubject)
	subjectBox:SetScript("OnEditFocusLost", function(self) db.subject = self:GetText() end)
	subjectBox:SetScript("OnEscapePressed", function(self) self:SetText(db.subject); self:ClearFocus() end)
	y = y - 30

	-- Alts
	local altLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	altLabel:SetPoint("TOPLEFT", 16, y)
	altLabel:SetText("Send to")
	y = y - 18

	altArea = CreateFrame("Frame", nil, panel)
	altArea:SetPoint("TOPLEFT", 16, y)
	altArea:SetWidth(PANEL_W - 32)
	altArea:SetHeight(22)
	altArea.empty = altArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	altArea.empty:SetPoint("TOPLEFT", 0, -4)
	altArea.empty:SetText("No alts yet - log in on each once, or add them below.")
	altButtons = {}

	-- Add alt row (anchored under the alt buttons so it moves as the list grows)
	addBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	addBox:SetSize(PANEL_W - 110, 20)
	addBox:SetPoint("TOPLEFT", altArea, "BOTTOMLEFT", 6, -6)
	addBox:SetAutoFocus(false)
	addBox:SetMaxLetters(48)
	addBox:SetScript("OnEnterPressed", function(self) AddAltByName(self:GetText()); self:SetText(""); self:ClearFocus() end)
	addBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
	local addBtn = SmallButton(panel, "Add alt", 70, function() AddAltByName(addBox:GetText()); addBox:SetText(""); addBox:ClearFocus() end)
	addBtn:SetPoint("LEFT", addBox, "RIGHT", 6, 0)

	-- Items header
	countText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	countText:SetPoint("TOPLEFT", addBox, "BOTTOMLEFT", -6, -12)

	local function CountIn(test)
		local n = 0
		for _, it in ipairs(bagItems) do if test(it) then n = n + (it.count or 1) end end
		return n
	end
	-- A quick-select button for one category. Shift-click adds to the current selection.
	local function CatButton(key, label, width)
		local c = CAT_BY_KEY[key]
		local b = SmallButton(panel, label, width, function() SelectWhere(c.test, IsShiftKeyDown()) end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(c.label)
			GameTooltip:AddLine(("Select them all (%d in bags)"):format(CountIn(c.test)), 1, 1, 1)
			GameTooltip:AddLine("Shift-click: add to what's already selected", 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		return b
	end

	local allBtn = SmallButton(panel, "All", 38, function() SelectWhere(function() return true end) end)
	local noneBtn = SmallButton(panel, "None", 46, function() wipe(selected); RefreshItems() end)
	local matsBtn = CatButton("reagent", "Mats", 46)
	local consBtn = CatButton("consum", "Consum.", 70)
	local moreBtn = SmallButton(panel, "More", 52, function(self)
		OpenCatMenu(self, function(i) SelectWhere(CATS[i].test, IsShiftKeyDown()) end)
	end)
	moreBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("More categories")
		GameTooltip:AddLine("Pick any category to select it. Hold Shift when picking to add to the selection.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	moreBtn:SetScript("OnLeave", GameTooltip_Hide)
	allBtn:SetPoint("TOPLEFT", countText, "BOTTOMLEFT", 0, -6)
	noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 4, 0)
	matsBtn:SetPoint("LEFT", noneBtn, "RIGHT", 4, 0)
	consBtn:SetPoint("LEFT", matsBtn, "RIGHT", 4, 0)
	moreBtn:SetPoint("LEFT", consBtn, "RIGHT", 4, 0)

	local row2 = {
		CatButton("ore", "Ore", 40), CatButton("herb", "Herbs", 52), CatButton("cloth", "Cloth", 50),
		CatButton("ench", "Ench", 46), CatButton("leather", "Leather", 64),
	}
	row2[1]:SetPoint("TOPLEFT", allBtn, "BOTTOMLEFT", 0, -4)
	for i = 2, #row2 do row2[i]:SetPoint("LEFT", row2[i - 1], "RIGHT", 4, 0) end

	-- Bottom: attach button + status
	attachButton = SmallButton(panel, "Attach", 90, AttachSelected)
	attachButton:SetSize(90, 24)
	attachButton:SetPoint("BOTTOMRIGHT", -12, 12)
	attachButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Attach selected items")
		GameTooltip:AddLine("Up to " .. MAX_ATTACH .. " per mail. Press Send, then Attach again for the rest.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	attachButton:SetScript("OnLeave", GameTooltip_Hide)

	-- Routes row (above the attach row)
	routesButton = SmallButton(panel, "Routes", 66, function()
		if routesFrame and routesFrame:IsShown() then routesFrame:Hide() else RoutesPickItem(nil) end
	end)
	routesButton:SetSize(66, 24)
	routesButton:SetPoint("BOTTOMLEFT", 12, 12)
	routesButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Routes")
		GameTooltip:AddLine('Rules like "every mage scroll goes to Stuper" or "trade goods go to my bank alt".', 1, 1, 1, true)
		GameTooltip:Show()
	end)
	routesButton:SetScript("OnLeave", GameTooltip_Hide)
	prepButton = SmallButton(panel, "Prep mail", 104, function() Prep(false) end)
	prepButton:SetSize(104, 24)
	prepButton:SetPoint("LEFT", routesButton, "RIGHT", 4, 0)
	prepButton:SetPoint("RIGHT", attachButton, "LEFT", -4, 0)
	prepButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Prep mail")
		GameTooltip:AddLine("Fills in the next recipient and attaches everything your routes send them. After you click Send, the next mail is prepped for you.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	prepButton:SetScript("OnLeave", GameTooltip_Hide)

	statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("BOTTOMLEFT", routesButton, "TOPLEFT", 2, 6)
	statusText:SetPoint("BOTTOMRIGHT", attachButton, "TOPRIGHT", -2, 6)
	statusText:SetHeight(26)
	statusText:SetJustifyV("BOTTOM")
	statusText:SetJustifyH("LEFT")
	statusText:SetWordWrap(true)

	-- Item grid
	scrollFrame = CreateFrame("ScrollFrame", "AltMailScrollFrame", panel, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", row2[1], "BOTTOMLEFT", 0, -8)
	scrollFrame:SetPoint("BOTTOMRIGHT", attachButton, "TOPRIGHT", -20, 38)
	scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetWidth(ICONS_PER_ROW * (ICON_SIZE + ICON_GAP))
	scrollChild:SetHeight(1)
	scrollFrame:SetScrollChild(scrollChild)

	panel:SetScript("OnShow", function()
		ScanBags()
		RefreshAlts()
		RefreshItems()
	end)
end

------------------------------------------------------------------------
-- Routes window
------------------------------------------------------------------------

local ROUTES_W = 330
local form = { kind = "name", catIndex = 1, toIndex = 1 }

local function Check(parent, label)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetSize(22, 22)
	for _, k in ipairs({ "Text", "text" }) do
		local t = c[k]
		if type(t) == "table" and t.SetText then t:SetText("") end
	end
	c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
	c.label:SetText(label)
	return c
end

-- Who a new route can go to: your bank alt, then every alt you know.
local function ToChoices()
	local list = { "@bank" }
	local names = {}
	for _, alt in pairs(db.alts) do names[#names + 1] = alt.name end
	table.sort(names, function(a, b) return a:lower() < b:lower() end)
	for _, n in ipairs(names) do list[#list + 1] = n end
	return list
end

local function ToLabel(to)
	if to == "@bank" then return "Bank alt" .. (db.bank and (" (" .. db.bank .. ")") or " (not set)") end
	return to
end

local function UpdateForm()
	local f = routesFrame
	for _, r in ipairs(f.kindRadios) do r:SetChecked(r.kind == form.kind) end
	if form.itemID then
		f.itemIcon:SetTexture(form.icon)
		f.itemIcon:Show()
		f.itemLabel:SetText(form.itemName or ("item " .. form.itemID))
		f.itemLabel:SetFontObject("GameFontHighlight")
	else
		f.itemIcon:Hide()
		f.itemLabel:SetText("Alt-click an item in AltMail's bag grid")
		f.itemLabel:SetFontObject("GameFontDisableSmall")
	end
	f.catButton:SetText(CATS[form.catIndex].label)
	local choices = ToChoices()
	if form.toIndex > #choices then form.toIndex = 1 end
	f.toButton:SetText(ToLabel(choices[form.toIndex]))
end

local function RouteRow(i)
	local f = routesFrame
	local r = f.rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, f.listChild)
	r:SetSize(ROUTES_W - 54, 24)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * 25)
	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.07)
	r.on = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
	r.on:SetSize(20, 20)
	r.on:SetPoint("LEFT", 0, 0)
	if type(r.on.Text) == "table" and r.on.Text.SetText then r.on.Text:SetText("") end
	r.on:SetScript("OnClick", function(self)
		self:GetParent().route.on = self:GetChecked() and true or false
		RefreshRoutes()
	end)
	r.on:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Turn this route on or off")
		GameTooltip:Show()
	end)
	r.on:SetScript("OnLeave", GameTooltip_Hide)
	r.del = CreateFrame("Button", nil, r, "UIPanelCloseButton")
	r.del:SetSize(22, 22)
	r.del:SetPoint("RIGHT", 2, 0)
	r.del:SetScript("OnClick", function(self)
		local route = self:GetParent().route
		for k, rr in ipairs(db.routes) do
			if rr == route then table.remove(db.routes, k) break end
		end
		RefreshRoutes()
	end)
	r.del:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Delete this route")
		GameTooltip:Show()
	end)
	r.del:SetScript("OnLeave", GameTooltip_Hide)
	r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.text:SetPoint("LEFT", r.on, "RIGHT", 2, 0)
	r.text:SetPoint("RIGHT", r.del, "LEFT", -2, 0)
	r.text:SetJustifyH("LEFT")
	r.text:SetWordWrap(false)
	f.rows[i] = r
	return r
end

RefreshRoutes = function()
	if not routesFrame or not routesFrame:IsShown() then
		if panel and panel:IsShown() then UpdateCounts() end
		return
	end
	local f = routesFrame
	f.bankText:SetText("Bank alt: " .. (db.bank and ("|cffffd200" .. db.bank .. "|r") or "|cff888888none - right-click an alt in AltMail|r"))
	for i, route in ipairs(db.routes) do
		local r = RouteRow(i)
		r.route = route
		r.on:SetChecked(route.on ~= false)
		local who = RouteWho(route)
		local missing = route.to == "@bank" and not db.bank
		r.text:SetText(RouteWhat(route) .. "  |cff888888to|r  " .. (missing and "|cffff6060" or "|cffffd200") .. who .. "|r")
		r.text:SetAlpha(route.on ~= false and 1 or 0.45)
		r:Show()
	end
	for i = #db.routes + 1, #f.rows do f.rows[i]:Hide() end
	f.listChild:SetHeight(math.max(1, #db.routes * 25))
	f.empty:SetShown(#db.routes == 0)
	UpdateForm()
	if panel and panel:IsShown() then UpdateCounts() end
end

local function AddRoute()
	local route = { on = true, kind = form.kind }
	if form.kind == "item" then
		if not form.itemID then Print("Alt-click an item in AltMail's bag grid first.") return end
		route.itemID, route.itemName = form.itemID, form.itemName
	elseif form.kind == "name" then
		local text = strtrim(routesFrame.nameBox:GetText() or "")
		if text == "" then Print("Type part of an item name, like Scroll: or Linen.") return end
		route.text = text
	else
		route.cat = CATS[form.catIndex].key
	end
	route.to = ToChoices()[form.toIndex]
	if route.to == "@bank" and not db.bank then
		Print("Route added. Right-click an alt in AltMail to choose your bank alt.")
	end
	db.routes[#db.routes + 1] = route
	routesFrame.nameBox:SetText("")
	routesFrame.nameBox:ClearFocus()
	RefreshRoutes()
end

-- Category pick list (shows how many bag items match each one). Shared by the Routes window
-- and the panel's More button; onPick(index) is called with the chosen category.
local catMenu
OpenCatMenu = function(anchor, onPick, current)
	if catMenu and catMenu:IsShown() and catMenu.anchor == anchor then catMenu:Hide() return end
	local m = catMenu
	if not m then
		m = CreateFrame("Frame", "AltMailCatMenu", panel, "BackdropTemplate")
		catMenu = m
		m:SetFrameStrata("FULLSCREEN_DIALOG")
		m:SetClampedToScreen(true)
		m:EnableMouse(true)
		if m.SetBackdrop then
			m:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
			m:SetBackdropColor(0.05, 0.05, 0.08, 0.96)
			m:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
		end
		m.buttons = {}
		for i, c in ipairs(CATS) do
			local b = CreateFrame("Button", nil, m)
			b:SetSize(196, 18)
			b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 18)
			b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			b.text:SetPoint("LEFT", 4, 0)
			b.text:SetText(c.label)
			b.count = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			b.count:SetPoint("RIGHT", -4, 0)
			b:SetScript("OnClick", function()
				m:Hide()
				if m.onPick then m.onPick(i) end
			end)
			m.buttons[i] = b
		end
		m:SetSize(208, 12 + #CATS * 18)
		m:SetScript("OnShow", function(self) self.shownAt = GetTime() end)
		m:SetScript("OnUpdate", function(self)
			if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
				and not self:IsMouseOver() and not (self.anchor and self.anchor:IsMouseOver())
				and GetTime() - (self.shownAt or 0) > 0.2 then
				self:Hide()
			end
		end)
	end
	m.anchor, m.onPick = anchor, onPick
	for i, c in ipairs(CATS) do
		local n = 0
		for _, it in ipairs(bagItems) do
			if c.test(it) then n = n + (it.count or 1) end
		end
		local b = m.buttons[i]
		b.count:SetText(n > 0 and ("%d in bags"):format(n) or "")
		if current == i then b.text:SetTextColor(1, 0.82, 0) else b.text:SetTextColor(1, 1, 1) end
	end
	m:ClearAllPoints()
	m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	m:Show()
end

local function CreateRoutesFrame()
	local f = CreateFrame("Frame", "AltMailRoutes", panel, "BasicFrameTemplateWithInset")
	routesFrame = f
	f:SetSize(ROUTES_W, 420)
	f:SetPoint("TOPLEFT", panel, "TOPRIGHT", 2, 0)
	if f.TitleText then f.TitleText:SetText("AltMail Routes") end
	f.rows = {}

	f.bankText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.bankText:SetPoint("TOPLEFT", 16, -32)
	f.bankText:SetPoint("RIGHT", -16, 0)
	f.bankText:SetJustifyH("LEFT")

	-- Route list
	local sf = CreateFrame("ScrollFrame", "AltMailRoutesScroll", f, "UIPanelScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 12, -50)
	sf:SetSize(ROUTES_W - 50, 150)
	f.listChild = CreateFrame("Frame", nil, sf)
	f.listChild:SetSize(ROUTES_W - 54, 1)
	sf:SetScrollChild(f.listChild)
	f.empty = f.listChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.empty:SetPoint("TOPLEFT", 4, -6)
	f.empty:SetWidth(ROUTES_W - 64)
	f.empty:SetJustifyH("LEFT")
	f.empty:SetText("No routes yet. Add one below.")

	-- New route form
	local y = -212
	local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	head:SetPoint("TOPLEFT", 16, y)
	head:SetText("New route - send...")
	y = y - 20

	f.kindRadios = {}
	local function Radio(kind, label, yy)
		local c = Check(f, label)
		c:SetPoint("TOPLEFT", 16, yy)
		c.kind = kind
		c:SetScript("OnClick", function(self)
			form.kind = self.kind
			UpdateForm()
			if self.kind == "name" then f.nameBox:SetFocus() end
		end)
		f.kindRadios[#f.kindRadios + 1] = c
		return c
	end

	local rItem = Radio("item", "This item:", y)
	f.itemIcon = f:CreateTexture(nil, "ARTWORK")
	f.itemIcon:SetSize(18, 18)
	f.itemIcon:SetPoint("LEFT", rItem.label, "RIGHT", 6, 0)
	f.itemLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.itemLabel:SetPoint("LEFT", f.itemIcon, "RIGHT", 4, 0)
	f.itemLabel:SetPoint("RIGHT", f, "RIGHT", -14, 0)
	f.itemLabel:SetJustifyH("LEFT")
	f.itemLabel:SetWordWrap(false)
	y = y - 26

	local rName = Radio("name", "Name contains:", y)
	f.nameBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	f.nameBox:SetSize(130, 20)
	f.nameBox:SetPoint("LEFT", rName.label, "RIGHT", 10, 0)
	f.nameBox:SetAutoFocus(false)
	f.nameBox:SetMaxLetters(40)
	f.nameBox:SetScript("OnEditFocusGained", function() form.kind = "name"; UpdateForm() end)
	f.nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	f.nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	y = y - 26

	local rCat = Radio("cat", "Category:", y)
	f.catButton = SmallButton(f, "", 160, function(self)
		OpenCatMenu(self, function(i)
			form.kind, form.catIndex = "cat", i
			UpdateForm()
		end, form.kind == "cat" and form.catIndex or nil)
	end)
	f.catButton:SetPoint("LEFT", rCat.label, "RIGHT", 10, 0)
	f.catButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Click to pick a category")
		GameTooltip:Show()
	end)
	f.catButton:SetScript("OnLeave", GameTooltip_Hide)
	y = y - 34

	local toLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	toLabel:SetPoint("TOPLEFT", 16, y - 3)
	toLabel:SetText("...to")
	f.toButton = SmallButton(f, "", 220, function() end)
	f.toButton:SetPoint("LEFT", toLabel, "RIGHT", 10, 0)
	f.toButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	f.toButton:SetScript("OnClick", function(_, button)
		local n = #ToChoices()
		form.toIndex = (form.toIndex + (button == "RightButton" and -2 or 0)) % n + 1
		UpdateForm()
	end)
	f.toButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Click for the next alt, right-click for the previous one")
		GameTooltip:AddLine("\"Bank alt\" follows whoever your bank alt is, even if you change it later.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.toButton:SetScript("OnLeave", GameTooltip_Hide)

	local add = SmallButton(f, "Add route", 110, AddRoute)
	add:SetSize(110, 24)
	add:SetPoint("BOTTOMRIGHT", -12, 12)
	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", 14, 16)
	hint:SetPoint("RIGHT", add, "LEFT", -6, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText("Picked items beat name matches, which beat categories.")

	f:SetScript("OnShow", RefreshRoutes)
end

-- Open the routes window; with an item, set the new-route form to "this item".
RoutesPickItem = function(it)
	if not panel then return end
	if not routesFrame then CreateRoutesFrame() end
	if it then
		form.kind = "item"
		form.itemID, form.itemName, form.icon = it.itemID, it.name, it.icon
	end
	routesFrame:Show()
	RefreshRoutes()
end

------------------------------------------------------------------------
-- Events & slash
------------------------------------------------------------------------

local pendingRefresh = false

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("MAIL_SHOW")
events:RegisterEvent("MAIL_CLOSED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("MAIL_SEND_SUCCESS")
events:RegisterEvent("MAIL_SEND_INFO_UPDATE")
events:RegisterEvent("MAIL_FAILED")
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then return end
		AltMailDB = AltMailDB or {}
		db = AltMailDB
		db.alts = db.alts or {}
		if db.subject == nil then db.subject = "here mail :)" end
		MigrateAlts()
		if not db.routes then
			-- First run of 1.3: start with the mage-scroll route Tim asked for.
			db.routes = { { on = true, kind = "name", text = "Scroll:", to = "Stuper Bonkbolt" } }
		end
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" or event == "PLAYER_LEVEL_UP" then
		RecordMe()
	elseif event == "MAIL_SHOW" then
		if not panel then CreatePanel() end
		if not db.hidden then panel:Show() end
	elseif event == "MAIL_CLOSED" then
		wipe(selected)
		prepActive = false
	elseif panel and panel:IsShown() then
		-- Bags changed / mail sent / attachment changed: rescan once per frame.
		if event == "MAIL_SEND_SUCCESS" then
			if prepActive then
				statusText:SetText("Sent! Prepping the next one...")
				-- Give the bags a moment to update, then prep the next recipient.
				C_Timer.After(0.6, function()
					if prepActive and panel:IsShown() then
						ScanBags()
						RefreshItems()
						Prep(true)
					end
				end)
			else
				statusText:SetText(SelectedCount() > 0 and ("Sent! %d still selected - press Attach."):format(SelectedCount()) or "Sent!")
			end
		elseif event == "MAIL_FAILED" then
			prepActive = false
			statusText:SetText("|cffff6060Mail didn't send.|r Fix it and click Send, or Prep mail to start over.")
		end
		if not pendingRefresh then
			pendingRefresh = true
			C_Timer.After(0, function()
				pendingRefresh = false
				if panel:IsShown() then
					ScanBags()
					RefreshItems()
				end
			end)
		end
	end
end)

SLASH_ALTMAIL1 = "/altmail"
SlashCmdList.ALTMAIL = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "routes" then
		if panel and panel:IsShown() then RoutesPickItem(nil) else Print("Open a mailbox first, then click Routes.") end
		return
	end
	if msg == "list" then
		local list = SortedAlts()
		Print(#list == 0 and "No alts recorded yet." or "Alts:")
		for _, e in ipairs(list) do Print("  " .. MailName(e.alt)) end
		return
	end
	db.hidden = not db.hidden
	if db.hidden then
		if panel then panel:Hide() end
		Print("Panel hidden at the mailbox. /altmail to show it again.")
	else
		Print("Panel will show at the mailbox.")
		if panel and MailFrame and MailFrame:IsShown() then panel:Show() end
	end
end
