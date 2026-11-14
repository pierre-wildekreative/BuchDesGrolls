-- Rauchtest: WoW-API grob nachgebaut, Addon geladen, Abläufe durchgespielt
local ADDON, LOCALE, DBVERSION = ...
function GetLocale() return LOCALE end
local DE = LOCALE == "deDE"
local function T(de, en) return DE and de or en end

local now = 1000
local emotes, warnings, chat = {}, {}, {}
local units = {} -- token -> {name, second}
local inGroup, groupSize = false, 0

local function widget()
    local w = { scripts = {}, shown = true, text = "" }
    return setmetatable(w, { __index = function(_, method)
        if method == "SetScript" then return function(self, n, fn) self.scripts[n] = fn end end
        if method == "IsShown" then return function(self) return self.shown end end
        if method == "Show" then return function(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end end
        if method == "Hide" then return function(self) self.shown = false end end
        if method == "SetShown" then return function(self, s) self.shown = s and true or false end end
        if method == "SetText" then return function(self, t) self.text = t end end
        if method == "GetText" then return function(self) return self.text end end
        if method == "GetStringWidth" or method == "GetWidth" then return function() return 100 end end
        if method == "GetCenter" then return function() return 0, 0 end end
        if method == "GetEffectiveScale" then return function() return 1 end end
        if method == "CreateTexture" or method == "CreateFontString" then return function() return widget() end end
        if method == "StartMoving" or method == "StopMovingOrSizing" then return function() end end
        return function() end
    end })
end

local frames = {}
function CreateFrame(_, name) local w = widget(); frames[#frames + 1] = w; if name then _G[name] = w end; return w end
UIParent, Minimap, GameTooltip = widget(), widget(), widget()
function GameTooltip_Hide() end
print = function(msg) chat[#chat + 1] = msg end
strlower, strtrim = string.lower, function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
date, time = os.date, os.time
function GetTime() return now end
function wipe(t) for k in pairs(t) do t[k] = nil end end
tinsert = table.insert
math.atan2 = math.atan2 or math.atan
function UnitIsPlayer(u) return units[u] ~= nil end
function UnitExists(u) return units[u] ~= nil end
function UnitName(u) return units[u][1], units[u][2] end
function IsInGroup() return inGroup end
function IsInRaid() return false end
function GetNumGroupMembers() return groupSize end
function GetCursorPosition() return 10, 10 end
C_Timer = { After = function(_, fn) fn() end }
local sent = {}
C_ChatInfo = { PerformEmote = function(token, unit) emotes[#emotes + 1] = token .. ">" .. unit end,
    SendChatMessage = function(msg, channel, _, target) assert(#msg <= 255, "Nachricht zu lang"); sent[#sent + 1] = { msg, channel, target } end }
function IsInGuild() return true end
local function R(e) local r = e.reasons[#e.reasons]; return r and r.text end
function PlaySound(id) assert(id, "PlaySound ohne Sound") end
SOUNDKIT = { ALARM_CLOCK_WARNING_3 = 1, RAID_WARNING = 2, IG_ABILITY_PAGE_TURN = 3, IG_QUEST_LOG_OPEN = 4, IG_QUEST_LOG_CLOSE = 5 }
RaidWarningUtil = { AddMessage = function(msg) warnings[#warnings + 1] = msg end }
ChatTypeInfo = { RAID_WARNING = {} }
UISpecialFrames, SlashCmdList = {}, {}
Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
Enum = { TooltipDataType = { Unit = 2 } }
C_Texture = { GetAtlasInfo = function() return {} end }
local recap = {}
C_DeathRecap = { GetRecapEvents = function() return recap end }
local menuCallbacks, tooltipCallback = {}, nil
Menu = { ModifyMenu = function(tag, fn) menuCallbacks[tag] = fn end }
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) tooltipCallback = fn end }
local function menuRoot()
    local root = { buttons = {} }
    function root:CreateTitle() end
    function root:CreateDivider() end
    function root:CreateButton(text, fn) self.buttons[text] = fn; return self end
    function root:SetEnabled(on) assert(type(on) == "boolean", "SetEnabled braucht bool") end
    function root:CreateRadio(text, isSel, setSel) self.buttons[text] = setSel; assert(type(isSel()) == "boolean") end
    return root
end
local lastMenu
MenuUtil = { CreateContextMenu = function(owner, gen) lastMenu = menuRoot(); gen(owner, lastMenu) end }

-- v1-Daten für die Migration
BuchDesGrollsDB = DBVERSION == "v1" and { thrallfan = "Thrallfan" }
    or { entries = { thrallfan = { name = "Thrallfan", reason = "alter Grund", level = 1, added = 5, seen = 0, kills = 0, deaths = 0 } } }
assert(loadfile(ADDON))()

local events = frames[1].scripts.OnEvent
local function fire(...) events(frames[1], ...) end
local slash = SlashCmdList.BUCHDESGROLLS
local E = function() return BuchDesGrollsDB.entries end

fire("ADDON_LOADED", "AnderesAddon")
fire("PLAYER_TARGET_CHANGED") -- vor dem Laden: darf nicht krachen
fire("ADDON_LOADED", "BuchDesGrolls")
assert(E().thrallfan.name == "Thrallfan" and E().thrallfan.level == 1, "Migration")
assert(R(E().thrallfan) == (DBVERSION == "v2" and "alter Grund" or nil) and E().thrallfan.reason == nil, "Migration der Gründe")

-- Sichtung: Emote + Warnung, Cooldown greift
units.target = { "Thrallfan" }
fire("PLAYER_TARGET_CHANGED")
assert(#emotes == 1 and emotes[1] == "RUDE>target", "Emote bei Sichtung")
assert(#warnings == 1 and E().thrallfan.seen == 1, "Warnung und Zähler")
fire("PLAYER_TARGET_CHANGED")
assert(#emotes == 1, "Cooldown")
now = now + 61
units.mouseover = { "Thrallfan" }
fire("UPDATE_MOUSEOVER_UNIT")
assert(#emotes == 2 and E().thrallfan.seen == 2, "nach Cooldown erneut")

-- Ziel mit Nachname und Grund eintragen
units.target = { "Bob", "Meier" }
slash("ziel hat mir den Knoten geklaut; echt~jetzt")
local bob = E()["bob meier"]
assert(bob and bob.name == "Bob Meier" and R(bob) == "hat mir den Knoten geklaut, echt,jetzt", "ziel + Grund")
assert(emotes[#emotes] == "RUDE>target" and #warnings == 2, "Emote ohne Warnung beim Eintragen")

-- per Name mit Grund, per Name ohne Grund
slash("add Karl Heinz: Ninja-Looter")
assert(R(E()["karl heinz"]) == "Ninja-Looter", "add Name: Grund")
slash("add Solo")
assert(E().solo and R(E().solo) == nil, "add Name")
slash("add Solo: doch ein Grund")
assert(R(E().solo) == "doch ein Grund", "erster Vorfall")
slash("add Solo: und noch einer")
assert(#E().solo.reasons == 2 and E().solo.reasons[1].text == "doch ein Grund" and R(E().solo) == "und noch einer", "Eintrag wird erweitert")
slash("add Solo")
assert(#E().solo.reasons == 2, "ohne Grund kein leerer Vorfall")

-- Erzfeind: zwei Emotes, Alarm
E()["karl heinz"].level = 3
units.nameplate3 = { "Karl", "Heinz" }
local before = #emotes
fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
assert(#emotes == before + 2 and emotes[#emotes] == "RUDE>nameplate3" and emotes[#emotes - 1] == "SPIT>nameplate3", "Erzfeind-Emotes")
assert(warnings[#warnings]:find(T("Erzfeind Karl Heinz", "Arch-enemy Karl Heinz"), 1, true), "Erzfeind-Warnung")

-- Vergeben: zählt, aber kein Emote
slash("vergib Solo")
units.target = { "Solo" }
before = #emotes
fire("PLAYER_TARGET_CHANGED")
assert(#emotes == before and E().solo.seen == 1 and E().solo.forgiven, "vergeben")

-- Gruppe
inGroup, groupSize = true, 3
units.party1 = { "Bob", "Meier" }
before = #warnings
fire("GROUP_ROSTER_UPDATE"); fire("GROUP_ROSTER_UPDATE")
assert(#warnings == before + 1 and warnings[#warnings]:find(T("Gruppe", "group"), 1, true), "Gruppenwarnung einmal")

-- Kills und Tode
fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Bob Meier stirbt, ehrenhafter Sieg Rang: Späher")
assert(E()["bob meier"].kills == 1, "Kill")
recap = { { sourceName = "Karl Heinz" }, { sourceName = "Karl Heinz" }, { sourceName = "Wolf" }, {} }
fire("PLAYER_DEAD")
assert(E()["karl heinz"].deaths == 1, "Tod einmal gezählt")

-- Buch, Zeilenmenü, Tooltip
slash("")
assert(BuchDesGrollsFrame, "Buch erzeugt")
local rows = {}
for _, fr in ipairs(frames) do if type(rawget(fr, "key")) == "string" then rows[#rows + 1] = fr end end
assert(#rows == 4, "vier Zeilen befüllt, gefunden: " .. #rows)
assert(rows[4].key == "solo", "vergebene Einträge am Ende")
local k1 = rows[1].key
rows[1].scripts.OnEnter(rows[1])
rows[1].scripts.OnClick(rows[1])
lastMenu.buttons[T("Erzfeind", "Arch-Enemy")]()
assert(E()[k1].level == 3, "Stufe per Menü")
lastMenu.buttons[T("Letzten Vorfall ändern", "Edit last incident")]()
BuchDesGrollsPrompt.edit.text = "neuer Grund"
BuchDesGrollsPrompt.edit.scripts.OnEnterPressed()
assert(R(E()[k1]) == "neuer Grund" and #E()[k1].reasons == 1, "Vorfall ändern")
lastMenu.buttons[T("Vorfall hinzufügen", "Add incident")]()
BuchDesGrollsPrompt.edit.text = string.rep("ä", 200)
BuchDesGrollsPrompt.edit.scripts.OnEnterPressed()
assert(#E()[k1].reasons == 2, "Vorfall per Menü hinzufügen")
lastMenu.buttons[T("Gruppe", "Party")]()
assert(#sent == 3 and sent[1][2] == "PARTY" and sent[1][1]:find("Bob Meier", 1, true) and sent[2][1]:find("neuer Grund", 1, true), "Posten in die Gruppe")
assert(sent[3][1]:sub(-3) == "..." and not sent[3][1]:sub(1, -4):find("\195$"), "lange Nachricht sauber gekürzt")
lastMenu.buttons[T("Gilde", "Guild")](); lastMenu.buttons[T("Schlachtzug", "Raid")]()
assert(sent[4][2] == "GUILD" and sent[7][2] == "RAID", "Gilde und Schlachtzug")
lastMenu.buttons[T("Flüstern …", "Whisper …")]()
BuchDesGrollsPrompt.edit.text = " Elodia Bloodreign "
BuchDesGrollsPrompt.edit.scripts.OnEnterPressed()
assert(#sent == 12 and sent[10][2] == "WHISPER" and sent[10][3] == "Elodia Bloodreign", "Flüstern")
lastMenu.buttons[T("Letzten Vorfall ändern", "Edit last incident")]()
BuchDesGrollsPrompt.edit.text = ""
BuchDesGrollsPrompt.edit.scripts.OnEnterPressed()
assert(#E()[k1].reasons == 1, "leerer Text löscht den letzten Vorfall")
lastMenu.buttons[T("Vergeben", "Forgive")]()
assert(E()[k1].forgiven, "Vergeben per Menü")
for _, row in ipairs(rows) do if row.key == k1 then row.scripts.OnClick(row) end end
lastMenu.buttons[T("Groll erneuern", "Renew grudge")]()
assert(not E()[k1].forgiven, "Groll erneuern")
BuchDesGrollsFrame.scripts.OnMouseWheel(BuchDesGrollsFrame, -1)

-- Export / Import
slash("export")
local exported = BuchDesGrollsPrompt.edit.text
assert(exported:match("^BDG1;") and not exported:find("Solo", 1, true), "Export ohne Vergebene: " .. exported)
for k in pairs(E()) do E()[k] = nil end
slash("import")
BuchDesGrollsPrompt.edit.text = exported
BuchDesGrollsPrompt.edit.scripts.OnEnterPressed()
assert(E()["karl heinz"].level == 3 and R(E()["karl heinz"]) == "Ninja-Looter" and E().thrallfan, "Import")
BuchDesGrollsPrompt.onAccept("Quatsch")

-- Vor- und Nachname in allen Varianten, die der Client liefern könnte
slash("add Elodia Bloodreign: Testgroll")
assert(E()["elodia bloodreign"].name == "Elodia Bloodreign", "Name mit Nachname per Befehl")
now = now + 100
for i, unit in ipairs({ { "Elodia", "Bloodreign" }, { "Elodia Bloodreign" }, { "Elodia Bloodreign", "Realm" } }) do
    now = now + 61
    units.target = unit
    local n = #emotes
    fire("PLAYER_TARGET_CHANGED")
    assert(#emotes == n + 1, "Nachname-Variante " .. i)
    assert(E()["elodia bloodreign"].name == "Elodia Bloodreign", "Anzeigename bleibt, Variante " .. i)
end
slash("del Elodia Bloodreign")
assert(not E()["elodia bloodreign"], "del mit Nachname")

-- englische Befehle
units.target = { "Grim", "Darkblade" }
slash("target stole my kill")
assert(R(E()["grim darkblade"]) == "stole my kill", "target")
slash("forgive Grim Darkblade")
assert(E()["grim darkblade"].forgiven, "forgive")
slash("remove Grim Darkblade")
assert(not E()["grim darkblade"], "remove")
slash("add Grim Darkblade"); slash("delete")
assert(not E()["grim darkblade"], "delete mit Ziel")
assert(SLASH_BUCHDESGROLLS3 == "/grudge", "/grudge")

-- Rechtsklick-Menü
local root = menuRoot()
menuCallbacks.MENU_UNIT_PLAYER(nil, root, { name = "Neu", surname = "Feind" })
root.buttons[T("Ins Buch des Grolls eintragen", "Add to the Book of Grudges")]()
assert(E()["neu feind"], "Eintrag per Rechtsklick")
root = menuRoot()
menuCallbacks.MENU_UNIT_FRIEND(nil, root, { name = "Neu", surname = "Feind" })
root.buttons[T("Weiteren Vorfall im Buch des Grolls notieren", "Note another incident in the Book of Grudges")]()
BuchDesGrollsPrompt.edit.text = "schon wieder"
BuchDesGrollsPrompt.edit.scripts.OnEnterPressed()
assert(R(E()["neu feind"]) == "schon wieder", "weiterer Vorfall per Rechtsklick")
root.buttons[T("Aus dem Buch des Grolls streichen", "Remove from the Book of Grudges")]()
assert(not E()["neu feind"], "Streichen per Rechtsklick")
menuCallbacks.MENU_UNIT_PARTY(nil, menuRoot(), {})

-- Tooltip, Minimap, Rest
units.mouseover = { "Karl", "Heinz" }
tooltipCallback(GameTooltip)
BuchDesGrollsMinimapButton.scripts.OnDragStart()
BuchDesGrollsMinimapButton.scripts.OnUpdate()
BuchDesGrollsMinimapButton.scripts.OnEnter()
BuchDesGrollsMinimapButton.scripts.OnClick()
BuchDesGrolls_OnCompartmentClick()
units.target = nil
slash("del"); slash("del Niemand"); slash("del Thrallfan"); slash("hilfe")
assert(not E().thrallfan, "del")

assert(chat[#chat]:find(T("teilen", "share"), 1, true), "Hilfe in Client-Sprache")
io.write(LOCALE .. " " .. DBVERSION .. ": ALLE TESTS OK (" .. #chat .. " Chatzeilen, " .. #emotes .. " Emotes)\n")
