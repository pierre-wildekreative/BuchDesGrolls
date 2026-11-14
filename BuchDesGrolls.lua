local COOLDOWN = 60 -- Sekunden, bis derselbe Spieler erneut Emote und Warnung auslöst
local ROWS = 8      -- Einträge pro Buchseite

-- Deutscher Client: deutsche Texte, alle anderen Sprachen: englische
local GERMAN = GetLocale() == "deDE"
local function T(de, en)
    return GERMAN and de or en
end

local TITLE = T("Buch des Grolls", "Book of Grudges")
local LEVELS = {
    { name = T("Leichter Groll", "Mild Grudge"), emotes = { "RUDE" } },
    { name = T("Tiefer Groll", "Deep Grudge"), emotes = { "SPIT" } },
    { name = T("Erzfeind", "Arch-Enemy"), emotes = { "SPIT", "RUDE" } },
}

-- Forever trennt Vor- und Nachname mit diesem Zeichen (ein Leerzeichen)
local SEP = Constants and Constants.CharacterNameSeparatorConsts
    and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or "-"
local secret = issecretvalue or function() return false end

local db           -- BuchDesGrollsDB
local lastRude = {}
local groupWarned = {}
local book, prompt
local page = 1
local refresh

local function say(msg)
    print("|cffff5533" .. TITLE .. ":|r " .. msg)
end

-- ponytail: strlower kann nur ASCII, "Ärger" ~= "ärger". Per Ziel oder Rechtsklick eintragen umgeht das.
local function key(name)
    return name and name ~= "" and strlower(name) or nil
end

local function join(name, second)
    if second and second ~= "" then return name .. SEP .. second end
    return name
end

-- Schlüssel und Anzeigename eines Spielers; nil, wenn kein Spieler oder der Name gesperrt ist
local function unitKey(unit)
    if not UnitIsPlayer(unit) then return end
    local name, second = UnitName(unit)
    if not name or secret(name) or secret(second) then return end
    -- Der zweite Wert ist der Nachname, kann aber auch ein Realm sein, während der
    -- volle Name schon im ersten steckt. Dann zählt der Eintrag ohne den Zusatz.
    local full = join(name, second)
    if db.entries[key(name)] and not db.entries[key(full)] then full = name end
    return key(full), full
end

local function clean(text)
    text = text and strtrim(text):gsub("[~;|]", ",") or ""
    return text ~= "" and text or nil
end

local function day(t)
    return date(T("%d.%m.%Y", "%d %b %Y"), t)
end

local function warn(msg, alarm)
    if RaidWarningUtil then
        RaidWarningUtil.AddMessage(msg, ChatTypeInfo["RAID_WARNING"])
    else
        UIErrorsFrame:AddMessage(msg, 1, 0.1, 0.1)
    end
    PlaySound(alarm and SOUNDKIT.ALARM_CLOCK_WARNING_3 or SOUNDKIT.RAID_WARNING)
    say(msg)
end

local function emote(token, unit)
    -- Emotes können im Kampf oder in Instanzen gesperrt sein, dann eben nicht
    pcall(C_ChatInfo and C_ChatInfo.PerformEmote or DoEmote, token, unit)
end

-- Text des jüngsten Vorfalls
local function latest(e)
    local incident = e.reasons[#e.reasons]
    return incident and incident.text
end

local function addIncident(e, text)
    if text then e.reasons[#e.reasons + 1] = { text = text, time = time() } end
end

-- Eintrag anlegen oder um einen Vorfall erweitern; gibt Eintrag und "neu angelegt" zurück
local function addEntry(name, reason, level)
    local k = key(name)
    local e = db.entries[k]
    local isNew = not e
    if isNew then
        e = { name = name, reasons = {}, level = level or 1, added = time(), seen = 0, kills = 0, deaths = 0 }
        db.entries[k] = e
    end
    addIncident(e, reason)
    return e, isNew
end

local function withReason(msg, e)
    return msg .. (latest(e) and " (" .. latest(e) .. ")" or "")
end

-- Chatnachrichten dürfen höchstens 255 Bytes lang sein; nicht mitten im Umlaut abschneiden
local function cut(text)
    if #text <= 255 then return text end
    local n = 252
    while n > 0 and text:byte(n + 1) >= 128 and text:byte(n + 1) < 192 do n = n - 1 end
    return text:sub(1, n) .. "..."
end

-- ponytail: postet höchstens die letzten 5 Vorfälle, damit der Chat nicht drosselt
local function post(e, channel, target)
    local status = e.forgiven and T("vergeben", "forgiven") or LEVELS[e.level].name
    local lines = { "[" .. TITLE .. "] " .. e.name .. " – " .. status .. ", " .. e.seen .. T("× gesehen", "× seen") }
    for i = math.max(1, #e.reasons - 4), #e.reasons do
        lines[#lines + 1] = day(e.reasons[i].time) .. ": " .. e.reasons[i].text
    end
    for _, line in ipairs(lines) do
        if not pcall(C_ChatInfo.SendChatMessage or SendChatMessage, cut(line), channel, nil, target) then
            return say(T("Der Chat ist gerade gesperrt.", "Chat is locked right now."))
        end
    end
end

local function check(unit, quiet)
    local k, name = unitKey(unit)
    local e = k and db.entries[k]
    if not e then return end
    e.name = name
    local now = GetTime()
    if lastRude[k] and now - lastRude[k] < COOLDOWN then return end
    lastRude[k] = now
    e.seen = e.seen + 1
    e.lastSeen = time()
    if not e.forgiven then
        if not quiet then
            local who = e.level == 3 and (T("Erzfeind ", "Arch-enemy ") .. name) or name
            warn(withReason(who .. T(" ist in der Nähe!", " is nearby!"), e), e.level == 3)
        end
        for i, token in ipairs(LEVELS[e.level].emotes) do
            C_Timer.After((i - 1) * 2, function()
                -- der Unit-Token kann inzwischen auf jemand anderen zeigen
                if unitKey(unit) == k then emote(token, unit) end
            end)
        end
    end
    refresh()
end

local function checkGroup()
    if not IsInGroup() then
        wipe(groupWarned)
        return
    end
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, GetNumGroupMembers() do
        local k, name = unitKey(prefix .. i)
        local e = k and db.entries[k]
        if e and not e.forgiven and not groupWarned[k] then
            groupWarned[k] = true
            warn(withReason(name .. T(" ist in deiner Gruppe!", " is in your group!"), e), true)
        end
    end
end

-- ponytail: Das Kampflog ist für Addons gesperrt. Kills zählen daher nur über die
-- Ehren-Meldung (nur ehrenhafte Siege), Tode über den Todesrückblick. Beides ist ein Näherungswert.
local function countKill(text)
    if secret(text) then return end
    for _, e in pairs(db.entries) do
        if text:sub(1, #e.name) == e.name then
            e.kills = e.kills + 1
            say(e.name .. T(" erlegt. Strich Nummer ", " slain. Tally mark number ") .. e.kills .. ".")
            return refresh()
        end
    end
end

local function countDeath()
    local counted = {}
    for _, event in ipairs(C_DeathRecap.GetRecapEvents() or {}) do
        local source = event.sourceName
        local e = source and not secret(source) and db.entries[key(source)]
        if e and not counted[e] then
            counted[e] = true
            e.deaths = e.deaths + 1
            say(e.name .. T(" hat dich erwischt. Das wird notiert.", " got you. This has been noted."))
        end
    end
    refresh()
end

-- Eingabefenster (Grund, Export, Import)

local function solid(parent, layer, r, g, b, a)
    local tex = parent:CreateTexture(nil, layer)
    tex:SetColorTexture(r, g, b, a or 1)
    return tex
end

local function paperBackground(frame)
    solid(frame, "BACKGROUND", 0.20, 0.12, 0.05):SetAllPoints()
    local paper = solid(frame, "BORDER", 0.90, 0.81, 0.62)
    paper:SetPoint("TOPLEFT", 5, -5)
    paper:SetPoint("BOTTOMRIGHT", -5, 5)
    -- Pergament des Questfensters; fehlt der Atlas, bleibt die Farbfläche stehen
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestBG-Parchment") then
        paper:SetAtlas("QuestBG-Parchment")
    end
end

local function textButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function ask(title, text, onAccept)
    if not prompt then
        prompt = CreateFrame("Frame", "BuchDesGrollsPrompt", UIParent)
        prompt:SetSize(380, 112)
        prompt:SetPoint("CENTER", 0, 140)
        prompt:SetFrameStrata("DIALOG")
        prompt:EnableMouse(true)
        paperBackground(prompt)
        prompt.title = prompt:CreateFontString(nil, "ARTWORK", "QuestFont")
        prompt.title:SetPoint("TOP", 0, -16)
        prompt.title:SetWidth(350)
        local function accept()
            prompt:Hide()
            if prompt.onAccept then prompt.onAccept(prompt.edit:GetText()) end
        end
        prompt.edit = CreateFrame("EditBox", nil, prompt, "InputBoxTemplate")
        prompt.edit:SetSize(330, 24)
        prompt.edit:SetPoint("CENTER", 2, -4)
        prompt.edit:SetAutoFocus(false)
        prompt.edit:SetMaxLetters(0)
        prompt.edit:SetScript("OnEnterPressed", accept)
        prompt.edit:SetScript("OnEscapePressed", function() prompt:Hide() end)
        textButton(prompt, "OK", 90, accept):SetPoint("BOTTOMRIGHT", prompt, "BOTTOM", -4, 12)
        textButton(prompt, T("Abbrechen", "Cancel"), 90, function() prompt:Hide() end)
            :SetPoint("BOTTOMLEFT", prompt, "BOTTOM", 4, 12)
    end
    prompt.onAccept = onAccept
    prompt.title:SetText(title)
    prompt.edit:SetText(text or "")
    prompt:Show()
    prompt.edit:SetFocus()
    prompt.edit:HighlightText()
end

local function askIncident(e)
    ask(T("Was ist mit " .. e.name .. " schiefgelaufen?", "What went wrong with " .. e.name .. "?"), "", function(text)
        addIncident(e, clean(text))
        refresh()
    end)
end

-- leerer Text löscht den jüngsten Vorfall
local function editLatest(e)
    ask(T("Letzter Vorfall mit ", "Last incident with ") .. e.name, latest(e), function(text)
        text = clean(text)
        if text then
            e.reasons[#e.reasons].text = text
        else
            e.reasons[#e.reasons] = nil
        end
        refresh()
    end)
end

local function askWhisper(e)
    ask(T("An wen flüstern?", "Whisper to whom?"), "", function(text)
        if strtrim(text) ~= "" then post(e, "WHISPER", strtrim(text)) end
    end)
end

local function export()
    local parts = { "BDG1" }
    for _, e in pairs(db.entries) do
        if not e.forgiven then
            local texts = {}
            for i, incident in ipairs(e.reasons) do texts[i] = incident.text end
            parts[#parts + 1] = e.name .. "~" .. e.level .. "~" .. table.concat(texts, " / ")
        end
    end
    ask(T("Kopieren (Strg+C bzw. Cmd+C) und weitergeben", "Copy (Ctrl+C or Cmd+C) and pass it on"),
        table.concat(parts, ";"))
end

local function import(text)
    if not text:match("^BDG1") then
        return say(T("Das ist kein Buch-des-Grolls-Export.", "That is not a Book of Grudges export."))
    end
    local count = 0
    for item in text:gmatch("[^;]+") do
        local name, level, reason = item:match("^(.-)~([1-3])~(.*)$")
        if name and name ~= "" and not db.entries[key(name)] then
            addEntry(name, clean(reason), tonumber(level))
            count = count + 1
        end
    end
    say(count .. T(" neue Einträge übernommen.", " new entries imported."))
    refresh()
end

local function askImport()
    ask(T("Export eines anderen Buchs hier einfügen", "Paste another book's export here"), "", import)
end

-- Buchfenster

local function sortedKeys()
    local keys = {}
    for k in pairs(db.entries) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ea, eb = db.entries[a], db.entries[b]
        if (ea.forgiven ~= nil) ~= (eb.forgiven ~= nil) then return eb.forgiven ~= nil end
        return a < b
    end)
    return keys
end

function refresh()
    if not book or not book:IsShown() then return end
    local keys = sortedKeys()
    local pages = math.max(1, math.ceil(#keys / ROWS))
    page = math.min(math.max(page, 1), pages)
    for i, row in ipairs(book.rows) do
        local k = keys[(page - 1) * ROWS + i]
        local e = k and db.entries[k]
        row.key = k
        row:SetShown(e ~= nil)
        if e then
            row.text:SetText(e.name)
            local more = #e.reasons - 1
            row.reason:SetText(not latest(e) and T("kein Grund notiert", "no reason noted")
                or (latest(e) .. (more > 0 and " (+" .. more .. T(" weitere)", " more)") or "")))
            row.status:SetText(e.forgiven and (T("vergeben am ", "forgiven on ") .. day(e.forgiven))
                or (LEVELS[e.level].name .. " · " .. e.seen .. T("× gesehen", "× seen")))
            row.strike:SetShown(e.forgiven ~= nil)
            row.strike:SetWidth(row.text:GetStringWidth())
            row:SetAlpha(e.forgiven and 0.6 or 1)
        end
    end
    book.empty:SetShown(#keys == 0)
    book.pageText:SetText(T("Seite ", "Page ") .. page .. " / " .. pages)
    book.prev:SetEnabled(page > 1)
    book.next:SetEnabled(page < pages)
end

local function rowMenu(row)
    local k = row.key
    local e = db.entries[k]
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(e.name)
        local levels = root:CreateButton(T("Groll-Stufe", "Grudge level"))
        for i, level in ipairs(LEVELS) do
            levels:CreateRadio(level.name, function() return e.level == i end, function()
                e.level = i
                refresh()
            end)
        end
        root:CreateButton(T("Vorfall hinzufügen", "Add incident"), function() askIncident(e) end)
        root:CreateButton(T("Letzten Vorfall ändern", "Edit last incident"), function() editLatest(e) end)
            :SetEnabled(latest(e) ~= nil)
        local chat = root:CreateButton(T("Im Chat posten", "Post to chat"))
        chat:CreateButton(T("Gruppe", "Party"), function() post(e, "PARTY") end):SetEnabled(IsInGroup())
        chat:CreateButton(T("Schlachtzug", "Raid"), function() post(e, "RAID") end):SetEnabled(IsInRaid())
        chat:CreateButton(T("Gilde", "Guild"), function() post(e, "GUILD") end):SetEnabled(IsInGuild())
        chat:CreateButton(T("Flüstern …", "Whisper …"), function() askWhisper(e) end)
        root:CreateButton(e.forgiven and T("Groll erneuern", "Renew grudge") or T("Vergeben", "Forgive"), function()
            e.forgiven = not e.forgiven and time() or nil
            refresh()
        end)
        root:CreateButton(T("Streichen", "Remove"), function()
            db.entries[k] = nil
            refresh()
        end)
    end)
end

local function rowTooltip(row)
    local e = db.entries[row.key]
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.name)
    GameTooltip:AddLine(LEVELS[e.level].name, 1, 0.3, 0.2)
    for _, incident in ipairs(e.reasons) do
        GameTooltip:AddLine(day(incident.time) .. ": " .. incident.text, 1, 0.82, 0, true)
    end
    GameTooltip:AddLine(T("Eingetragen am ", "Added on ") .. day(e.added), 1, 1, 1)
    GameTooltip:AddLine(e.seen .. T("× gesehen", "× seen")
        .. (e.lastSeen and T(", zuletzt am ", ", last on ") .. day(e.lastSeen) or ""), 1, 1, 1)
    GameTooltip:AddLine(T("Von dir getötet: ", "Killed by you: ") .. e.kills
        .. T(" · Dich getötet: ", " · Killed you: ") .. e.deaths, 1, 1, 1)
    if e.forgiven then GameTooltip:AddLine(T("Vergeben am ", "Forgiven on ") .. day(e.forgiven), 0.4, 1, 0.4) end
    GameTooltip:Show()
end

local function turnPage(delta)
    page = page + delta
    PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN)
    refresh()
end

local function pageButton(dir, delta)
    local b = CreateFrame("Button", nil, book)
    b:SetSize(32, 32)
    b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page-Down")
    b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page-Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", function() turnPage(delta) end)
    return b
end

local function createBook()
    book = CreateFrame("Frame", "BuchDesGrollsFrame", UIParent)
    book:SetSize(420, 540)
    book:SetPoint("CENTER")
    book:SetFrameStrata("HIGH")
    book:SetClampedToScreen(true)
    book:EnableMouse(true)
    book:SetMovable(true)
    book:RegisterForDrag("LeftButton")
    book:SetScript("OnDragStart", book.StartMoving)
    book:SetScript("OnDragStop", book.StopMovingOrSizing)
    book:EnableMouseWheel(true)
    book:SetScript("OnMouseWheel", function(_, delta) turnPage(-delta) end)
    book:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN)
        refresh()
    end)
    book:SetScript("OnHide", function() PlaySound(SOUNDKIT.IG_QUEST_LOG_CLOSE) end)
    tinsert(UISpecialFrames, "BuchDesGrollsFrame") -- schließt mit ESC
    paperBackground(book)

    local title = book:CreateFontString(nil, "ARTWORK", "QuestTitleFont")
    title:SetPoint("TOP", 0, -20)
    title:SetText(TITLE)
    local hint = book:CreateFontString(nil, "ARTWORK", "GameFontBlackSmall")
    hint:SetPoint("TOP", 0, -42)
    hint:SetText(T("Klick auf einen Eintrag für Optionen", "Click an entry for options"))

    CreateFrame("Button", nil, book, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -4, -4)

    book.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, book)
        row:SetSize(364, 48)
        row:SetPoint("TOPLEFT", 28, -14 - i * 48)
        row:RegisterForClicks("AnyUp")
        row:SetScript("OnClick", rowMenu)
        row:SetScript("OnEnter", rowTooltip)
        row:SetScript("OnLeave", GameTooltip_Hide)
        solid(row, "HIGHLIGHT", 0.20, 0.12, 0.05, 0.12):SetAllPoints()
        row.text = row:CreateFontString(nil, "ARTWORK", "QuestFont")
        row.text:SetPoint("TOPLEFT", 2, -6)
        row.status = row:CreateFontString(nil, "ARTWORK", "GameFontBlackSmall")
        row.status:SetPoint("TOPRIGHT", -2, -9)
        row.reason = row:CreateFontString(nil, "ARTWORK", "GameFontBlackSmall")
        row.reason:SetPoint("TOPLEFT", 2, -27)
        row.reason:SetWidth(360)
        row.reason:SetJustifyH("LEFT")
        row.reason:SetWordWrap(false)
        row.strike = solid(row, "OVERLAY", 0.20, 0.12, 0.05)
        row.strike:SetHeight(1)
        row.strike:SetPoint("LEFT", row.text, "LEFT")
        local line = solid(row, "ARTWORK", 0.20, 0.12, 0.05, 0.25)
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT")
        book.rows[i] = row
    end

    book.empty = book:CreateFontString(nil, "ARTWORK", "QuestFont")
    book.empty:SetPoint("CENTER")
    book.empty:SetText(T("Das Buch ist leer.", "The book is empty."))

    book.pageText = book:CreateFontString(nil, "ARTWORK", "QuestFont")
    book.pageText:SetPoint("BOTTOM", 0, 50)
    book.prev = pageButton("Prev", -1)
    book.prev:SetPoint("BOTTOMLEFT", 24, 14)
    book.next = pageButton("Next", 1)
    book.next:SetPoint("BOTTOMRIGHT", -24, 14)
    textButton(book, T("Exportieren", "Export"), 110, export):SetPoint("BOTTOMRIGHT", book, "BOTTOM", -4, 20)
    textButton(book, T("Importieren", "Import"), 110, askImport):SetPoint("BOTTOMLEFT", book, "BOTTOM", 4, 20)
end

local function toggleBook()
    if not book then
        createBook()
        refresh()
    else
        book:SetShown(not book:IsShown())
    end
end

-- wird über die .toc auch vom Addon-Menü an der Minimap aufgerufen
function BuchDesGrolls_OnCompartmentClick()
    toggleBook()
end

-- Minimap-Knopf

local function createMinimapButton()
    local b = CreateFrame("Button", "BuchDesGrollsMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    local function place()
        local angle = db.minimapAngle or 3.6
        local radius = Minimap:GetWidth() / 2 + 6
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
    end
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function()
        b:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            db.minimapAngle = math.atan2(cy / scale - my, cx / scale - mx)
            place()
        end)
    end)
    b:SetScript("OnDragStop", function() b:SetScript("OnUpdate", nil) end)
    b:SetScript("OnClick", toggleBook)
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(b, "ANCHOR_LEFT")
        GameTooltip:AddLine(TITLE)
        GameTooltip:AddLine(T("Klick: Buch öffnen · Ziehen: verschieben", "Click: open book · Drag: move"), 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    place()
end

-- Rechtsklick-Menü und Tooltip

local function setupMenus()
    if not (Menu and Menu.ModifyMenu) then return end
    for _, which in ipairs({ "PLAYER", "ENEMY_PLAYER", "PARTY", "RAID_PLAYER", "FRIEND" }) do
        Menu.ModifyMenu("MENU_UNIT_" .. which, function(_, root, context)
            local name = context and context.name
            if not name or secret(name) or secret(context.surname) then return end
            name = join(name, context.surname)
            local k = key(name)
            root:CreateDivider()
            if db.entries[k] then
                root:CreateButton(T("Weiteren Vorfall im Buch des Grolls notieren", "Note another incident in the Book of Grudges"), function()
                    askIncident(db.entries[k])
                end)
                root:CreateButton(T("Aus dem Buch des Grolls streichen", "Remove from the Book of Grudges"), function()
                    db.entries[k] = nil
                    say(name .. T(" wurde gestrichen.", " has been removed."))
                    refresh()
                end)
            else
                root:CreateButton(T("Ins Buch des Grolls eintragen", "Add to the Book of Grudges"), function()
                    askIncident(addEntry(name))
                    say(name .. T(" steht jetzt im Buch.", " is now in the book."))
                    refresh()
                end)
            end
        end)
    end
end

local function setupTooltip()
    if not (TooltipDataProcessor and Enum.TooltipDataType) then return end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip ~= GameTooltip then return end
        local k = unitKey("mouseover")
        local e = k and db.entries[k]
        if not e then return end
        if e.forgiven then
            tooltip:AddLine(TITLE .. ": " .. T("vergeben", "forgiven"), 0.4, 1, 0.4)
        else
            tooltip:AddLine(TITLE .. ": " .. LEVELS[e.level].name, 1, 0.3, 0.2)
            -- die letzten drei Vorfälle, damit der Tooltip nicht ausufert
            for i = math.max(1, #e.reasons - 2), #e.reasons do
                tooltip:AddLine(day(e.reasons[i].time) .. ": " .. e.reasons[i].text, 1, 1, 1, true)
            end
        end
    end)
end

-- Ereignisse

local function load()
    local old = BuchDesGrollsDB or {}
    if not old.entries then
        -- Version 1 hat nur Schlüssel -> Name gespeichert
        local entries = {}
        for k, name in pairs(old) do
            entries[k] = { name = name, level = 1, added = time(), seen = 0, kills = 0, deaths = 0 }
        end
        old = { entries = entries }
    end
    -- Version 2 hatte einen einzelnen Grund statt einer Liste von Vorfällen
    for _, e in pairs(old.entries) do
        if not e.reasons then
            e.reasons = e.reason and { { text = e.reason, time = e.added } } or {}
            e.reason = nil
        end
    end
    BuchDesGrollsDB = old
    db = old
    createMinimapButton()
    setupMenus()
    setupTooltip()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN")
f:RegisterEvent("PLAYER_DEAD")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "BuchDesGrolls" then load() end
    elseif not db then
        return
    elseif event == "PLAYER_TARGET_CHANGED" then
        check("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        check("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        check(arg1)
    elseif event == "GROUP_ROSTER_UPDATE" then
        checkGroup()
    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        countKill(arg1)
    elseif event == "PLAYER_DEAD" then
        -- der Todesrückblick ist erst kurz nach dem Tod gefüllt
        C_Timer.After(1, function() pcall(countDeath) end)
    end
end)

-- Slash-Befehle (deutsche und englische Wörter gelten in jeder Client-Sprache)

local function targetName()
    local _, name = unitKey("target")
    return name
end

SLASH_BUCHDESGROLLS1 = "/groll"
SLASH_BUCHDESGROLLS2 = "/bdg"
SLASH_BUCHDESGROLLS3 = "/grudge"
local ENGLISH = { target = "ziel", remove = "del", delete = "del", forgive = "vergib" }
SlashCmdList.BUCHDESGROLLS = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)%s*$")
    cmd = strlower(cmd)
    cmd = ENGLISH[cmd] or cmd
    if cmd == "" or cmd == "list" then
        toggleBook()
    elseif cmd == "export" then
        export()
    elseif cmd == "import" then
        askImport()
    elseif cmd == "add" or cmd == "ziel" or cmd == "del" or cmd == "vergib" then
        -- "add Name: Grund" nimmt den Namen aus dem Befehl, alles andere das Ziel
        local name, reason
        if cmd == "ziel" then
            name, reason = targetName(), rest
        elseif cmd == "add" and rest:find(":", 1, true) then
            name, reason = rest:match("^(.-)%s*:%s*(.*)$")
        else
            name = rest ~= "" and rest or targetName()
        end
        local e = name and db.entries[key(name)]
        if not name or name == "" then
            say(T("Kein Name angegeben und kein Spieler im Ziel.", "No name given and no player targeted."))
        elseif cmd == "add" or cmd == "ziel" then
            reason = clean(reason)
            local _, isNew = addEntry(name, reason)
            say(name .. (isNew and T(" steht jetzt im Buch.", " is now in the book.")
                or reason and T(" steht schon im Buch, Vorfall notiert.", " is already in the book, incident noted.")
                or T(" steht schon im Buch.", " is already in the book.")))
            if UnitExists("target") then check("target", true) end
        elseif not e then
            say(name .. T(" steht nicht im Buch.", " is not in the book."))
        elseif cmd == "del" then
            db.entries[key(name)] = nil
            say(name .. T(" wurde gestrichen.", " has been removed."))
        else
            e.forgiven = time()
            say(name .. T(" ist vergeben. Vorerst.", " is forgiven. For now."))
        end
        refresh()
    elseif GERMAN then
        say("/groll – Buch öffnen oder schließen")
        say("/groll ziel [Grund] – aktuelles Ziel eintragen")
        say("/groll add Name: Grund – Spieler per Name eintragen")
        say("/groll del [Name] – streichen (ohne Name: aktuelles Ziel)")
        say("/groll vergib [Name] – vergeben (ohne Name: aktuelles Ziel)")
        say("/groll export, /groll import – Buch mit anderen teilen")
    else
        say("/grudge – open or close the book")
        say("/grudge target [reason] – add your current target")
        say("/grudge add Name: reason – add a player by name")
        say("/grudge remove [Name] – remove (without a name: current target)")
        say("/grudge forgive [Name] – forgive (without a name: current target)")
        say("/grudge export, /grudge import – share the book with others")
    end
end
