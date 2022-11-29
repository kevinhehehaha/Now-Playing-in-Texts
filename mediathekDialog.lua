--[[
Copyright (C) 2019 roland1

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
--]]

local NAME = "mediathekDialog"
local VERSION = "1.0.3"
function descriptor()
	return {
		title = NAME,
		version = VERSION,
		author = "roland1",
		license = "GPL",
		shortdesc = NAME,
		description = "Filter-Erstellung für mediathek "..VERSION,
		url = nil,
--		capabilities = {"playing-listener", "input-listener"},
		capabilities = {},
	}
end

local json

local file = {}
file.write = function(path, ...)
	local fa, err = io.open(path, "wb")
	if not fa then return nil, err end
	local o, err = fa:write(...)
	fa:close()
	return o, err
end
file.read = function(path)
	local fr, err = io.open(path, "rb")
	if not fr then return nil, err end
	local s, err = fr:read"*a"
	if not fr then return nil, err end
	fr:close()
	return s
end

local tonums = function(s)
	local t,n = {}
	for i = 1, 3 do
		n,s = s:match"(%d+)(.*)$"
		if not n then break end
		t[i] = tonumber(n)
	end
	if #t == 0 then return nil end
	return t
end

local dmY2time = function(t)
	return os.time{
		day=t[1],month=t[2],year=t[3],
		hour=0,min=0,sec=0 -- sigh
	}
end
local HMS2time = function(t)
	return t[1]*3600+t[2]*60+t[3]
end

local rpatch = function(t,u)
	for i = 0,#u-1 do
		t[#t-i] = u[#u-i]
	end
	return t
end
local lpatch = function(t,u)
	for i = 1,#u do
		t[i] = u[i]
	end
	return t
end

local HELP = [[
<b>Titel Thema Titel_Thema Beschreibung Sender:</b> Eingabe ist Suchstring.<br/>
<b>Titel_Thema:</b> Suche in Titel, Thema aneinandergehängt.<br/>
<b>LaufzeitMin LaufzeitMax ZeitMin ZeitMax:</b> Eingabe hat Format Stunde:Minute:Sekunde oder Minute:Sekunde oder Sekunde.<br/>
<b>AlterMin AlterMax DatumMin DatumMax:</b> Eingabe hat Format Tag.Monat.Jahr oder Tag.Monat oder Tag, alles numerisch.<br/>
<b>FilterName:</b> Name, unter dem der Filter in mediathek auftaucht. Startet der Name mit *, dann ist er ein globaler Filter. Optional wenn Titel nicht leer ist.<br/>
<b>[Speichern]:</b> Speichert den Filter in mediatheks Konfiguration. Unterbricht mediathek. mediathek muss erneut aktiviert werden um Einträge anzuzeigen.<br/>
<b>[Löschen]:</b> Entfernt Einträge aus den Dialog-Feldern.
]]


function activate()
	json = require"dkjson"
	local pd = package.config:sub(1, 1)
	local udd = vlc.config.userdatadir():gsub(pd.."+$", "")
	local confp = udd..pd.."mediathek-1.state"
	local dlg = vlc.dialog(NAME)
	local txt,col = {},1

	for lb in ("Titel Thema Titel_Thema Beschreibung Sender LaufzeitMin LaufzeitMax AlterMin AlterMax DatumMin DatumMax ZeitMin ZeitMax FilterName"):gmatch"%S+" do
		dlg:add_label(lb,1,col)
		txt[lb] = dlg:add_text_input("",2,col)
		col = col+1
	end
	local rule_label
	dlg:add_button("Speichern",function()
		local t = {}
		local now = os.time()
		local dnow = os.date("*t",now)
		for k,tin in pairs(txt) do
			local s = tin:get_text() or ""
			if s == "" then
			elseif k:match"Max$" or k:match"Min$" then
				local tn = tonums(s)
				if tn then
					if k:match"^Datum" then
						t[k] = dmY2time( lpatch({dnow.day,dnow.month,dnow.year},tn) )
					elseif k:match"^Alter" then
						tn = lpatch({0,0,0},tn)
						t[k] = (365*tn[3]+30.42*tn[2]+tn[1])*86400
					else
						t[k] = HMS2time( rpatch({0,0,0},tn) )
					end
				end
			else
				t[k] = s
			end
		end
		local frmts = {
			Alter = "now-date",
			Datum = "date",
			Zeit = "time",
			Laufzeit = "duration",
		}
		local name = t.FilterName
		t.FilterName = nil
		if not name and not t.Titel then
			rule_label:set_text"FEHLER: Titel oder FilterName sind notwendig."
			return true
		end
		name = name or t.Titel:gsub("[^%w_%*]+", "_")
		local buf = {}
		for k,tk in pairs(t) do
			local nm,ord = k:match"(.*)(M[ia][nx])$"
			if ord == "Min" then buf[#buf+1] = frmts[nm]..">="..tostring(tk)
			elseif ord == "Max" then buf[#buf+1] = frmts[nm].."<="..tostring(tk)
			else buf[#buf+1] = ("(%s):lower():find(%q,1,true)"):format(k:gsub("_", '.." "..'),tk:lower())
			end
		end
		local rule = table.concat(buf, " and ")
		local o
		do
			local s = file.read(confp)
			local succ, r = pcall(json.decode, s)
			if succ and type(r) == "table" then	o = r
			else o = {}
			end
		end
		o[name] = table.concat(buf, " and ")

		if file.write( confp, json.encode(o, {indent=true}) ) then
			rule_label:set_text("+"..name.." "..rule)
			local name = "lua{sd='mediathek'}"
			vlc.sd.remove( name )
			vlc.sd.add( name )
		else
			rule_label:set_text("Kann Filter nicht speichern.")
		end
	end,1,col)
	col = col+1
	dlg:add_button("Löschen",function()
		for k,tin in pairs(txt) do
			tin:set_text("")
		end
	end,1,col)
	col = col+1
	dlg:add_label("Filter", 1,col)
	rule_label = dlg:add_text_input("Hier erscheint der Filter, wie er auch in die Suchmaske eingegeben werden kann.", 2,col)
	col = col+1

	local col0 = col
	local help_lb
	local help_button = dlg:add_button("Hilfe",function()
		if not help_lb then
			help_lb = dlg:add_html(HELP,2,col0,1,5)
		else
			dlg:del_widget(help_lb)
			help_lb = nil
		end
	end, 1,col0)

	dlg:show()
end

function close()
	deactivate()
end
function deactivate()
	--if dlg then dlg:hide() end
	vlc.deactivate()
end

function input_changed()
end

function meta_changed() 
end
