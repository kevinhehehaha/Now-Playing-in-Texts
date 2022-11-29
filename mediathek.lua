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
-----------------------------------------------------------

-- cmd /c escaping
-----------------------------------------------------------
local windows_xz_decoder = [[
""%ProgramW6432%\7-Zip\7z.exe" x -so "%filepath%.xz" > "%filepath%""
""%programfiles(x86)%\7-Zip\7z.exe" x -so "%filepath%.xz" > "%filepath%""
]]

local linux_xz_decoder = [[
xz --decompress --stdout '%filepath%.xz' > '%filepath%'
]]

-----------------------------------------------------------

local json

local NAME = "mediathek"
local ENV
local log

function descriptor()
	return {
		title = NAME,
		version = "1.0.4",
		author = "roland1",
		license = "GPL",
		shortdesc = NAME.." for vlc 3.0.7",
		description = "Zugang zu den Online-Mediatheken des ÖRR \
		basierend auf den Datenbanken des MediathekView Projektes https://mediathekview.de/.",
		url = nil,
		capabilities = {"search"},
	}
end

local urls = {
		"http://verteiler1.mediathekview.de/Filmliste-akt.xz",
		"http://verteiler2.mediathekview.de/Filmliste-akt.xz",
		"http://verteiler3.mediathekview.de/Filmliste-akt.xz",
		"http://verteiler4.mediathekview.de/Filmliste-akt.xz",
		"http://verteiler5.mediathekview.de/Filmliste-akt.xz",
		"http://verteiler6.mediathekview.de/Filmliste-akt.xz",
		--"http://download10.onlinetvrecorder.com/mediathekview/Filmliste-akt.xz",
}


local file = {}
file.read = function(path)
	local fr, err = io.open(path, "rb")
	if not fr then return nil, err end
	local s, err = fr:read"*a"
	if not fr then return nil, err end
	fr:close()
	return s
end
file.write = function(path, ...)
	local fa, err = io.open(path, "wb")
	if not fa then return nil, err end
	local o, err = fa:write(...)
	fa:close()
	return o, err
end
file.exist = function(path)
	local fa, err = io.open(path)
	if not fa then return false end
	fa:close()
	return true
end

local fdcopy = function(fr,fw)
	local sz = 1e5
	repeat
		local s = fr:read(sz)
		if s == nil or s == "" or type(s) ~= "string" then break end
		fw:write(s)
	until false
end


local dmY2time = function(s)
	local d, m, Y = s:match"(%d%d)%.(%d%d)%.(%d%d%d%d)"
	if not d then return end
	return os.time{
		day=tonumber(d),month=tonumber(m),year=tonumber(Y),
		hour=0,min=0,sec=0 -- sigh
	}
end
local HMS2time = function(s)
	local H,M,S = s:match"(%d%d)%:(%d%d)%:?(%d?%d?)"
	if not H then return end
	return tonumber(H)*3600+tonumber(M)*60+(tonumber(S) or 0)
end

--------------------------------------

local here_is_xz_header = function(fr)
	local pre = "\2537zXZ\000"
	local pos = fr:seek"cur"
	local succ = fr:read(#pre) == pre
	fr:seek("set", pos)
	return succ
end

local function headertail(ENV, url, ...)
	local nextarray
	do
		-- traverse, find ending delim
		local function tr_str(s,q) -- (q)"...(returnval)"
			local p
			repeat
				p,q = s:find('"',q+1,true)
				if not p then return nil end
				while "\\" == s:sub(p-1,p-1) do p = p-1 end
			until (q-p)%2 == 0
			return q
		end

		local function tr_arr(s,q)  -- (q)[...(returnval)]
			local _,m
			_,q,m = s:find('([%[%]"])',q+1)
			if m == '"' then return tr_arr(s,tr_str(s,q)) -- not +1. [...,"...(arg)"]
			elseif m == "[" then return tr_arr(s,tr_arr(s,q))
			elseif m == "]" then return q
			end
		end
		local function nextarr(s,q) -- (q)?
			if not q then error"nextarr missing '\"'" end
			local _,m
			_,q,m = s:find('(["%[])',q)
			if not m then return nil
			elseif m == '"' then return nextarr(s,tr_str(s,q)+1)
			end
			local r = tr_arr(s,q)
			if not r then error"nextarr missing ']'." end
			return r+1, s:sub(q,r)
		end

		nextarray = function(st,q) -- (q)?
			local src,s = st[1],st[2]
			if not q then error"nextarr missing '\"'" end
			local succ,r,a = pcall(nextarr,s,q)
			if succ and r then return r,a end
			local s1 = src()
			if s1 and s1 ~= "" then
				st[2] = s:sub(r and q or #s+1)..s1 -- r?error:nothing_opened
				return nextarray(st,1)
			end
			if not succ then error"Very Bad" end
		end

	end

	local pth = ENV.filepath
	local fr = io.open(pth, "rb")
	repeat
		if not fr then break end
		if here_is_xz_header(fr) then
			fr:close()
			os.remove(pth..".xz")
			assert( os.rename(pth,pth..".xz") )
			
			for cmdf in ENV.xz_decoder:gmatch"[^\r\n]+" do
				local succ = os.execute(cmdf % ENV)
--				log(cmdf % ENV)
				if succ == true or succ == 0 then
					fr = assert( io.open(pth,"rb") )
					break
				end
				log("Command failed:", cmdf % ENV)
			end
		end
		assert(fr:read(0), "Cannot read %filepath%." % ENV)
		local sz = 1e5
		local src = function() return fr:read(sz) end
		local st = {src,src()}
		local nextarr = function(st,q)
			local p,s = nextarray(st,q)
			if p then return p, json.decode(s) end
		end
		local p,a = nextarr(st,1)
		if not (a and a[1]) then break end
		----------------------------------------
		local tm = dmY2time(a[1])+HMS2time(a[1])
		if not tm then break end
		if (...) and tm < os.time()-86400 then break end
		---------------------------------------
		p,a = nextarr(st,p)
		if (a and a[1]) then
			local p0 = p
			local ofs0 = fr:seek"cur"
			local s0 = st[2]
			local tail = function()
				fr:seek("set",ofs0)
				st[2] = s0
				return nextarr,st,p0
			end
			return a,tail
		end
	until true
	if fr then fr:close() end
	assert(url, "No more url to try." )

	local fd = assert( vlc.stream(url) , "Cannot open stream %url%." % url)
--	assert( file.write(pth,fd:read(1e9)), "Cannot write to %filepath%." % ENV ) -- smaller units for smaller rams.
	local fw = assert( io.open(pth,"wb") )
	fdcopy(fd,fw)
	fw:close()
	
	return headertail(ENV,...)
end

local filters = {}
local nodes = {}
--local save_filters
local query

function main()
--	log(_VERSION)
	json = require"dkjson"
	unpack = unpack or table.unpack
	
	getmetatable"".__mod = function(s,env)
		return (s:gsub("%%([^%%]*)%%", env))
	end
	ENV = setmetatable(
		{[""] = "%", ["/"] = package.config:sub(1, 1)},
		{__index = function(_,k) return os.getenv(k) end}
	)
	if ENV["/"] == "\\" then
		ENV.userdatadir = "%APPDATA%\\vlc" % ENV
		ENV.xz_decoder = windows_xz_decoder
		ENV.rmode = "rb"
	else
		ENV.userdatadir = "%HOME%/.local/share/vlc" % ENV
		ENV.xz_decoder = linux_xz_decoder
		ENV.rmode = "r"
	end
	ENV.title = NAME
	ENV.filepath = "%userdatadir%%/%%title%.database" % ENV

	do
		local print0,assert0,error0 = print,assert,error
		local ts = function(...)
			local t,n = {...},select("#", ...)
			for i = 1,n do t[i] = tostring(t[i]) end
			return table.concat(t,", ")
		end
		-- stderr umbiegen?
		local logw = io.open( "%userdatadir%%/%%title%.log" % ENV , "w" )
		if logw then
			log = function(...)
				logw:write( ts(os.date"[%Y-%m-%d-%H-%M-%S]", ...),"\n" )
				logw:flush()
			end
			assert = function(...)
				if (...) == nil then log(select(2,...)) end
				return assert0(...)
			end
		else
			log = function() end
		end
		
	end
--TODO randomize urls	
	log"Start Download"
	local header,tail = headertail(ENV,unpack(urls))
	log"End Download"
	assert(header, "Cannot load filmliste")
	log("header=",unpack(header))

	local shallowcopy = function(t)
		local o = {}
		for k, v in pairs(t) do o[k] = v end
		return o
	end

	local loadfilter
	do
		local header1 = {"now", "playcount", unpack(header)}
		for i = 1, #header1 do header1[i] = header1[i]:gsub("[^%w_]+", "_") end
		local arglist = table.concat(header1, ",")
		log("arglist=", arglist)
		local env = {
			dmY2time  = dmY2time,
			HMS2time  = HMS2time, 
			tonumber = tonumber,
			tostring = tostring,
			string = shallowcopy(string),
			math = shallowcopy(math),
			os = {
				time = os.time,
				date = os.date,
			}
		}
		local loadf = [[
		return function(%s)

			local channel=Sender
			local title=Titel
			local date=tonumber(DatumL) or 0
			local time=HMS2time(Zeit) or 0
			local duration=HMS2time(Dauer) or 0
--			local size=tonumber(Groesse) or 0
			local description=Beschreibung

			local Laufzeit=duration
			local Genre=Thema
			local Album=Sender

--			return %%s -- escaped
			local __t__ = {}
			%s
			return __t__
		end
		]]
		if loadstring and setfenv then
			loadfilter = function(s)
--				log("load",loadf:format(arglist, s))
			-- binary string?
				local f = loadstring(loadf:format(arglist, s))
				setfenv(f,env)
				return f()
			end
		else
			loadfilter = function(s)
--				log("load",loadf:format(arglist, s))
				return load(loadf:format(arglist, s), nil, "t", env)()
			end
		end
	end

	do
		local loadplaycounts = function()
			local o = {}
			local fn = "%userdatadir%%/%progress.playcount" % ENV
			local fr = io.open(fn)
			if not fr then return o end
			repeat
				local ln = fr:read()
				if not ln then break end
				local c, uri = ln:match"^(%d+)%s+(.-)$"
				if not c then break end
				o[uri] = tonumber(c)
			until false
			fr:close()
			return o
		end

		local n2i = {}
		for i = 1, #header do n2i[ header[i] ] = i end
		local limit = 200
		local order = function(a,b) return a.datel > b.datel end

		local test = function(s, ...)
		end
		-----------------------------------------------
		query = function(filters,nodes)
			local now = os.time()
			local playcounts = loadplaycounts()
			local items_of_ttl = {}
	--		local maxitem_of_ttl = {}
			local prebuf = {} -- * prefilter rules
			local buf = {}
			-- construct name in place of  __t__ on the fly.
			local a,b,c = tail()
			local _, testa = a(b,c) -- nextarr(tail,1)
			for ttl,cat in pairs(filters) do
				local s
				local isprefilter = ttl:sub(1,1) == "*"
				if isprefilter then
					s = ("if not (%s) then return {} end"):format(cat)
				else
					s = ("if %s then __t__[#__t__+1] = %q end"):format(cat,ttl)
				end
				local succ,testf = pcall(loadfilter,s)
				if succ
				and pcall( testf, now, playcounts[testa[n2i.Url]] or 0, unpack(testa) )  then

					if isprefilter then
						prebuf[#prebuf+1] = s
					else
						buf[#buf+1] = s
					end
					
					items_of_ttl[ttl] = {}
				else
					filters[ttl] = nil
					nodes[ttl]:add_subitem{path = "idk", title = "CANNOT COMPILE SEARCH!"}
				end
			end
	
			local filter = assert(loadfilter(table.concat(prebuf,"\n").."\n"..table.concat(buf,"\n")), "Cannot load filter.")

			for _, a in tail() do

				local succ, t = pcall( filter, now, playcounts[a[n2i.Url]] or 0, unpack(a) )
				if not succ then --TODO check each filter in its own right
					log("ERROR","args=",now, playcounts[a[n2i.Url]] or 0, unpack(a))
				end
				for _, ttl in ipairs(t) do
					local newitem = {
						path = a[n2i.Url],
						name = a[n2i.Titel],
						title = a[n2i.Titel],
						description = a[n2i.Beschreibung],
						date = a[n2i.Datum],
						duration = HMS2time(a[n2i.Dauer]),
						time = a[n2i.Zeit],
						datel = tonumber(a[n2i.DatumL]) or 0,
						genre = a[n2i.Thema],
						album = a[n2i.Sender],
					}
					--TODO 2*limit
					----------------------------------------------
					local items = items_of_ttl[ttl]
					if #items < limit then
						items[#items+1] = newitem
						if #items == limit then
							table.sort(items,order)
						end
					elseif order(newitem, items[#items])then
						items[#items+1] = newitem
						table.sort(items,order)
						items[#items] = nil
					end
					----------------------------------------------
				end
			end
			
			for ttl,items in pairs(items_of_ttl) do
				table.sort(items,order)
				for _, item in ipairs(items) do nodes[ttl]:add_subitem(item) end
			end
			
		end
		-----------------------------------------------

	end

	local statepath = "%userdatadir%%/%%title%-1.state" % ENV -- %major%

	save_state = function()
		file.write( statepath,json.encode(filters,{indent=true}) )
	end
	---------------------------------
	local statepath_legacy = "%userdatadir%%/%%title%.state" % ENV
	if not file.exist(statepath) and file.exist(statepath_legacy) then
		local ut = {["\\\\"]="\\",["\\n"]="\n",["\\t"]="\t"}
		local unescape = function(s)
			return (s:gsub("\\[\\nt]", ut))
		end

		local s =  file.read(statepath_legacy)
		for ttl, exp in s:gmatch"([^\r\n\t]+)\t([^\r\n\t]+)" do
			ttl = unescape(ttl)
			exp = unescape(exp)
			filters[ ttl ] = exp
		end
		save_state()
	end
	---------------------------------

	if file.exist(statepath) then
		filters = json.decode(file.read(statepath))
	end
	for ttl,cat in pairs(filters) do
		nodes[ttl] = vlc.sd.add_node{title=ttl,category=cat}
	end


	do
		local f = query
		query = function(...)
			log"Start query"
			f(...)
			log"End query"
		end
	end

	query(filters,nodes)

end

local remove_from_state = function(title)
	filters[title] = nil
	local node = nodes[title]
	if node then vlc.sd.remove_node(node) end
end

function search(s)
	log("search",s)
	local cmd, rest = s:match"^([%+%-/])(.*)$"
	if cmd == "+" then
		local title, category = rest:match"^(%*?[%w_]+)%s+(.-)$" -- prefilter
		assert(title, "search + title error")
		if filters[title] == category then return end
		remove_from_state(title)
		filters[title] = category
		nodes[title] = vlc.sd.add_node{title=title,category=category}
		query( {[title] = category} , nodes )
	elseif cmd == "/" then
		local sf = "+%s Titel:lower():find(%q, 1, true)"
		return search(sf:format(rest:gsub("%W+","_"), rest:lower()))
	elseif cmd == "-" then
		local title = assert(rest:match"^(.-)%s*$", "search - title error")
		remove_from_state(title)
	else
		return search("/"..s)
	end
	save_state()
end
