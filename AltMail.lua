-- AltMail
-- A panel next to the mailbox:
--   * Click an alt to fill in the recipient and subject (switches to the Send Mail tab).
--   * Pick items from your bags (click, shift-click for all of that item, or All/None/Mats),
--     then "Attach" puts up to 12 of them on the mail. Press Send, then Attach again for the rest.
-- Alts are learned automatically the first time you log in on each character with AltMail on.

local ADDON_NAME = ...

local MAX_ATTACH = ATTACHMENTS_MAX_SEND or 12
local ICON_SIZE, ICON_GAP, ICONS_PER_ROW = 32, 4, 7
local PANEL_W = ICONS_PER_ROW * (ICON_SIZE + ICON_GAP) + 40

local db
local panel, subjectBox, addBox, altButtons, altArea, scrollFrame, scrollChild, countText, statusText, attachButton
local itemButtons = {}
local bagItems = {}      -- list of { bag, slot, itemID, icon, count, quality, locked, classID }
local selected = {}      -- "bag:slot" -> itemID

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
				Print("Removed " .. self.alt.name .. " from your alt list.")
				RefreshAlts()
			else
				Print("Shift + right-click to remove " .. self.alt.name .. " from the list.")
			end
			return
		end
		FillMail(self.alt)
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(MailName(self.alt))
		if self.alt.level then GameTooltip:AddLine("Level " .. self.alt.level, 1, 1, 1) end
		GameTooltip:AddLine("Click: fill in name + subject", 0.7, 0.7, 0.7)
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
		b:SetText(entry.alt.name)
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
				local classID
				if C_Item and C_Item.GetItemInfoInstant then
					classID = select(6, C_Item.GetItemInfoInstant(info.itemID))
				end
				bagItems[#bagItems + 1] = {
					bag = bag, slot = slot, itemID = info.itemID, icon = info.iconFileID,
					count = info.stackCount or 1, quality = info.quality, locked = info.isLocked,
					classID = classID, link = info.hyperlink,
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
		GameTooltip:AddLine("Click: select   Shift-click: all of this item", 0.7, 0.7, 0.7)
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

local function SelectWhere(pred)
	wipe(selected)
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
	panel:SetSize(PANEL_W, 480)
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

	local allBtn = SmallButton(panel, "All", 44, function() SelectWhere(function() return true end) end)
	local noneBtn = SmallButton(panel, "None", 50, function() wipe(selected); RefreshItems() end)
	local matsBtn = SmallButton(panel, "Mats", 50, function()
		SelectWhere(function(it) return it.classID == 7 or it.classID == 5 end) -- trade goods, reagents
	end)
	allBtn:SetPoint("TOPLEFT", countText, "BOTTOMLEFT", 0, -6)
	noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 4, 0)
	matsBtn:SetPoint("LEFT", noneBtn, "RIGHT", 4, 0)
	matsBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Select all trade goods and reagents")
		GameTooltip:Show()
	end)
	matsBtn:SetScript("OnLeave", GameTooltip_Hide)

	-- Bottom: attach button + status
	attachButton = SmallButton(panel, "Attach", 110, AttachSelected)
	attachButton:SetSize(110, 24)
	attachButton:SetPoint("BOTTOMRIGHT", -12, 12)
	attachButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Attach selected items")
		GameTooltip:AddLine("Up to " .. MAX_ATTACH .. " per mail. Press Send, then Attach again for the rest.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	attachButton:SetScript("OnLeave", GameTooltip_Hide)

	statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("BOTTOMLEFT", 14, 14)
	statusText:SetPoint("RIGHT", attachButton, "LEFT", -6, 0)
	statusText:SetJustifyH("LEFT")
	statusText:SetWordWrap(true)

	-- Item grid
	scrollFrame = CreateFrame("ScrollFrame", "AltMailScrollFrame", panel, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", allBtn, "BOTTOMLEFT", 0, -8)
	scrollFrame:SetPoint("BOTTOMRIGHT", attachButton, "TOPRIGHT", -20, 8)
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
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then return end
		AltMailDB = AltMailDB or {}
		db = AltMailDB
		db.alts = db.alts or {}
		if db.subject == nil then db.subject = "here mail :)" end
		MigrateAlts()
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" or event == "PLAYER_LEVEL_UP" then
		RecordMe()
	elseif event == "MAIL_SHOW" then
		if not panel then CreatePanel() end
		if not db.hidden then panel:Show() end
	elseif event == "MAIL_CLOSED" then
		wipe(selected)
	elseif panel and panel:IsShown() then
		-- Bags changed / mail sent / attachment changed: rescan once per frame.
		if event == "MAIL_SEND_SUCCESS" then
			statusText:SetText(SelectedCount() > 0 and ("Sent! %d still selected - press Attach."):format(SelectedCount()) or "Sent!")
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
