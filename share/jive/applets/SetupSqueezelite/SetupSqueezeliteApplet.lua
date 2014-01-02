--[[

SetupSqueezelite Applet - configuration for squeezelite playback

(c) 2013-2014, Adrian Smith, triode1@btinternet.com

--]]

local oo               = require("loop.simple")
local io               = require("io")
local os               = require("os")
local Applet           = require("jive.Applet")
local System           = require("jive.System")
local Framework        = require("jive.ui.Framework")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Textarea         = require("jive.ui.Textarea")
local Label            = require("jive.ui.Label")
local Popup            = require("jive.ui.Popup")
local Checkbox         = require("jive.ui.Checkbox")
local RadioGroup       = require("jive.ui.RadioGroup")
local RadioButton      = require("jive.ui.RadioButton")
local Slider           = require("jive.ui.Slider")
local Surface          = require("jive.ui.Surface")
local Task             = require("jive.ui.Task")
local Timer            = require("jive.ui.Timer")
local Icon             = require("jive.ui.Icon")
local Window           = require("jive.ui.Window")
local debug            = require("jive.utils.debug")

local appletManager    = appletManager

local string, pairs, ipairs, tonumber, tostring, require, type, table, bit = string, pairs, ipairs, tonumber, tostring, require, type, table, bit

module(..., Framework.constants)
oo.class(_M, Applet)


-- squeezelite alsa options
local opts = {
	{ name = 'buffer', vals = { 20, 40, 80, 160, 250, 500 } },
	{ name = 'count',  vals = { 2, 4, 8, 16, 32 } },
	{ name = 'format', vals = { '16', '24', '24_3', '32' } },
	{ name = 'mmap',   vals = { 0, 1 } },
	{ name = 'maxrate', vals = { 44100, 48000, 88200, 96000, 172400, 192000, 352800, 384000 } },
}


function deviceMenu(self, menuItem)
	self:_parseConfig()

	local window = Window("text_list", menuItem.text)
	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	-- refreshing menu to detect hotplugging of usb dacs
	local timer

	local updateMenu = function()
		local info = self:_parseCards()
		local slEnabled = self:_slIsEnabled()
		local items = {}

		if true then

			for num, card in ipairs(info) do
				items[#items+1] = {
					text = card.desc,
					style = self:_isDevice(card.id) and "item_checked" or "item",
					callback = function(event, menuItem)
								   timer:stop()
								   self:cardMenu(card.id, card.desc)
							   end,
				}
			end

			items[#items+1] = {
				text = self:string("OPTIONS"),
					callback = function(event, menuItem)
								   timer:stop()
								   local window = Window("text_list", menuItem.text)
								   local items = {}
								   for _, opt in ipairs(opts) do
									   items[#items+1] = {
										   text = tostring(self:string("OPT_" .. string.upper(opt.name))),
										   callback = function(event, menuItem)
														  local window = Window("text_list", menuItem.text)
														  local group = RadioGroup()
														  local items = {}
														  items[1] = {
															  text  = self:string("DEFAULT"),
															  style = 'item_choice',
															  check = RadioButton("radio", group,
																				  function(event, menuItem)
																					  self:_setParam(opt.name, nil)
																				  end,
																				  self:_getParam(opt.name) == nil)
														  }
														  for k, v in ipairs(opt.vals) do
															  items[#items+1] = {
																  text  = v,
																  style = 'item_choice',
																  check = RadioButton("radio", group,
																					  function(event, menuItem)
																						  self:_setParam(opt.name, v)
																					  end,
																					  tostring(self:_getParam(opt.name)) == tostring(v))
															  }
														  end
														  local menu = SimpleMenu("menu", items)
														  menu:setHeaderWidget(
															  Textarea("help_text", self:string("HELP_" .. string.upper(opt.name)))
														  )
														  window:addWidget(menu)
														  self:tieAndShowWindow(window)
													  end,
									   }
								   end
								   local menu = SimpleMenu("menu", items)
								   window:addWidget(menu)
								   self:tieAndShowWindow(window)
							   end,
			}

		end

		items[#items+1] = {
			text = self:string("ENABLE_SQUEEZELITE"),
			style = 'item_choice',
			check = Checkbox("checkbox",
							 function(object, isSelected)
								 self:_slEnable(isSelected)
							 end,
							 slEnabled
						 ),
		}

		menu:setItems(items, #items)
	end

	-- update on a timer
	timer = Timer(1000, function() updateMenu() end, false)
	timer:start()

	-- initial display
	updateMenu()

	-- cancel timer when window is hidden (e.g. screensaver)
	window:addListener(bit.bor(EVENT_WINDOW_ACTIVE, EVENT_HIDE),
		function(event)
			local type = event:getType()
			if type == EVENT_WINDOW_ACTIVE then
				updateMenu()
				timer:restart()
			else
				timer:stop()
			end
			return EVENT_UNUSED
		end,
		true
	)

	self:tieAndShowWindow(window)
	return window
end


function cardMenu(self, card, desc)
	local isSelected = self:_isDevice(card)
	local window = Window("text_list", desc)
	local menu = SimpleMenu("menu")
	local items = {}

	window:addWidget(menu)
	self:tieAndShowWindow(window)

	local activeEntry = {
		text = self:string("ACTIVE_DEVICE"),
		style = "item_checked",
	}

	if isSelected then
		items[1] = activeEntry
	else
		items[1] = {
			text = self:string("SELECT_DEVICE"),
			callback = function(event, menuItem)
						   self:_setDevice(card)
						   items[1] = activeEntry
						   menu:reLayout()
					   end,
		}
	end

	-- check we can open the /proc file for updating usb details
	local update = false
	local info = io.open("/proc/asound/" .. card .. "/stream0", "r")
	if info ~= nil then
		update = true
		info:close()
	end

	if update then
		local display = function()
							local info = self:_usbInfo(card)
							table.insert(info, 1, items[1])
							menu:setItems(info, #info)
						end
		display()
		
		local timer = Timer(1000, function() display() end, false)
		timer:start()

		window:addListener(bit.bor(EVENT_WINDOW_ACTIVE, EVENT_HIDE),
			function(event)
				local type = event:getType()
				if type == EVENT_WINDOW_ACTIVE then
					timer:restart()
				else
					timer:stop()
				end
				return EVENT_UNUSED
			end,
			true
		)
	else
		menu:setItems(items, #items)
	end
end


function _parseCards(self)
	local t = {}

	local cards = io.open("/proc/asound/cards", "r")

	if cards == nil then
		log:error("/proc/asound/cards could not be opened")
		return
	end

	-- read and parse entries
	for line in cards:lines() do
		local num, id, desc = string.match(line, "(%d+)%s+%[(.-)%s*%]:%s+(.*)")
		if (id) then
			t[#t+1] = { id = id, desc = desc }
		end
	end

	cards:close()

	return t
end


function _parseStreamInfo(self, card)
	local bits, needhub, async
	local t = {}
	
	local cards = io.open("/proc/asound/" .. card .. "/stream0", "r")
	
	if cards == nil then
		return t
	end
	
	-- parsing helper functions
	local last
	local parse = function(regexp, opt)
		local tmp = last or cards:read()
		if tmp == nil then
			return
		end
		local r1, r2, r3 = string.match(tmp, regexp)
		if opt and r1 == nil and r2 == nil and r3 == nil then
			last = tmp
		else
			last = nil
		end
		return r1, r2, r3
	end

	local skip = function(number) 
		if last and number > 0 then
			last = nil
			number = number - 1
		end
		while number > 0 do
			cards:read()
			number = number - 1
		end
	end

	local eof = function()
		if last then return false end
		last = cards:read()
		return last == nil
	end

	-- detect full speed async devices without external hub
	t.id, t.speed = parse("%.(.-),%s(%w+)%sspeed%s:")

	-- FIXME this is linux version specific
	if t.id then
		t.hub = string.match(t.id, "%.")
	end
	skip(2)

	-- detect status
	t.status = parse("  Status: (%w+)")

	if t.status == "Running" then
		t.interface = parse("    Interface = (%d+)")
		t.altset    = parse("    Altset = (%d+)")
		skip(2)
		t.momfreq   = parse("    Momentary freq = (%d+) Hz")
		t.feedbkfmt = parse("    Feedback Format = (.*)", true)
	end
	
	local fmts = {}

	while not eof() do

		local intf = parse("  Interface (%d+)")
		if intf then 
			local alt  = parse("    Altset (%d+)")
			local fmt  = parse("    Format: (.*)")
			local chan = parse("    Channels: (%w+)")
			local type = parse("    Endpoint: %d+ %w+ %((%w+)%)")
			local rate = parse("    Rates: (.*)")
			
			fmts[#fmts+1] = { intf = intf, alt = alt, fmt = fmt, chan = chan, type = type, rate = rate, int = int }
			
			if t.interface == intf and t.altset == alt then
				t.fmt = fmts[#fmts]
			end
		end

	end
	
	t.fmts = fmts

	cards:close()

	return t
end


function _usbInfo(self, card)
	log:debug("fetching info...")
	local info = self:_parseStreamInfo(card)
	local items = {}
	local entry = function(text)
					  items[#items+1] = {
						  text = text,
						  style = "item_no_arrow",
					  }
				  end
	entry("Status: " .. info.status)
	entry("Speed: " .. (info.speed == "full" and "Full" or "High"))
	entry("Connection: " .. (info.hub and "via Hub" or "Direct"))
	if info.status == "Running" then
		local first, rest = string.match(info.fmt.type, "(%w)(%w+)")
		entry("Type: " .. string.upper(first) .. string.lower(rest))
		entry("Frequency: " .. info.momfreq .. " Hz")
		entry("Format: " .. info.fmt.fmt)
		entry("Rates: " .. info.fmt.rate)
		entry("Feedback Format: " .. ((info.feedbkfmt == "10.14" and "Full (10.14)") or 
									  (info.feedbkfmt == "16.16" and "High (16.16)") or "None"))
	else
		local i = 1
		while info.fmts[i] do
			local fmt = info.fmts[i]
			local cnt = #info.fmts > 1 and (" [" .. i .. "]: ") or ": "
			local first, rest = string.match(fmt.type, "(%w)(%w+)")
			entry("Type" .. cnt .. string.upper(first) .. string.lower(rest))
			entry("Format" .. cnt .. fmt.fmt)
			entry("Rates" .. cnt .. fmt.rate)
			i = i + 1
		end
	end
	return items
end


-- make these system specific...

local configFile    = "/etc/sysconfig/squeezelite"
local configFileTmp = "/tmp/squeezelite.config"

local current


function _getParam(self, key)
	return current[key]
end


function _setParam(self, key, val)
	log:debug("set " .. key .. ": ", (val or "nil"))
	current[key] = val
	self:_writeConfig()
end


function _isDevice(self, card)
	return card == current.device
end


function _setDevice(self, card)
	log:debug("set device: " .. (card or "nil"))
	current.device = card
	self:_writeConfig()
end


function _parseConfig(self)
	local conf = io.open(configFile, "r")
	if conf == nil then
		log:warn("can't open config file")
		return
	end

	current = {}

	for line in conf:lines() do
		if string.match(line, "AUDIO_DEV") then
			local dev = string.match(line, '^AUDIO_DEV="%-o%s(.-)"')
			log:info("dev: ", dev)
			if dev then
				current.device = string.match(dev, "hw:CARD=(.-),DEV") or string.match(dev, "hw:CARD=(.-)")
			end
		end
		if string.match(line, "ALSA_PARAMS") then
			local params = string.match(line, '^ALSA_PARAMS="%-a%s(.-)"')
			if params then
				if string.match(params, "%d-:%d-:[%d_]-:%d-") then
					current.buffer, current.count, current.format, current.mmap = string.match(params, "(%d-):(%d-):([%d_]-):(%d-)")
				elseif string.match(params, "%d-:%d-:[%d_]-") then
					current.buffer, current.count, current.format = string.match(params, "(%d-):(%d-):([%d_]-)")
				elseif string.match(params, "%d-:%d-") then
					current.buffer, current.count = string.match(params, "(%d-):(%d-)")
				elseif string.match(params, "%d-") then
					current.buffer = params
				end
				if current.buffer == "" then current.buffer = nil end
				if current.count  == "" then current.count  = nil end
				if current.format == "" then current.format = nil end
				if current.mmap   == "" then current.mmap   = nil end
			end
		end
		if string.match(line, "MAX_RATE") then		
			current.maxrate = string.match(line, '^MAX_RATE="%-r%s(%d-)"')
		end
	end

	conf:close()
end


function _writeConfig(self)
	local inconf  = io.open(configFile, "r")
	local outconf = io.open(configFileTmp, "w")
	if inconf == nil or outconf == nil then
		log:warn("can't open config files, aborting save")
		return
	end

	log:info("writing config")
	local wrote_dev, wrote_params, wrote_rate

	for line in inconf:lines() do
		if string.match(line, "AUDIO_DEV") then
			if current.device then
				outconf:write('AUDIO_DEV="-o hw:CARD=' .. current.device .. ',DEV=0"\n')
			else
				outconf:write('# AUDIO_DEV=""\n')
			end
			wrote_dev = true
		elseif string.match(line, "ALSA_PARAMS") then
			if current.buffer or current.count or current.format or current.mmap then
				outconf:write('ALSA_PARAMS="-a ' .. (current.buffer or "") .. ":" .. (current.count or "") .. ":" ..
							  (current.format or "") .. ":" .. (current.mmap or "") .. '"\n')
			else
				outconf:write('# ALSA_PARAMS=""\n')
			end
			wrote_params = true
		elseif string.match(line, "MAX_RATE") then
			if current.maxrate then
				outconf:write('MAX_RATE="-r ' .. current.maxrate .. '"\n')
			else
				outconf:write('# MAX_RATE=""\n')
			end
			wrote_rate = true
		else
			outconf:write(line .. "\n")
		end
	end

	inconf:close()

	if current.device and not wrote_dev then
		outconf:write('AUDIO_DEV="-o hw:CARD=' .. current.device .. ',DEV=0"\n')
	end
	if (current.buffer or current.count or current.format or current.mmap) and not wrote_params then
		outconf:write('ALSA_PARAMS="-a ' .. (current.buffer or "") .. ":" .. (current.count or "") .. ":" ..
					  (current.format or "") .. ":" .. (current.mmap or "") .. '"\n')
	end
	if current.maxrate and not wrote_rate then
		outconf:write('MAX_RATE="-r ' .. current.maxrate .. '"\n')
	end

	outconf:close()

	os.execute("sudo csos-squeezeliteConfigUpdate " .. configFileTmp)

	if self:_slIsEnabled() then
		os.execute("sudo systemctl restart squeezelite.service")
	end
end


function _slIsEnabled(self)
	return os.execute("systemctl --quiet is-active squeezelite.service") == 0
end


function _slEnable(self, new)
	if new then
		os.execute("sudo systemctl start squeezelite.service")
	else
		os.execute("sudo systemctl stop squeezelite.service")
	end
end

