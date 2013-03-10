--[[

SetupSqueezelite Applet - support of usb audio and extended digital output capabilties via addon kernel

(c) 2012, 2013, Adrian Smith, triode1@btinternet.com

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

local string, ipairs, tonumber, tostring, require, type, table, bit = string, ipairs, tonumber, tostring, require, type, table, bit

module(..., Framework.constants)
oo.class(_M, Applet)


function deviceMenu(self, menuItem)
	local window = Window("text_list", menuItem.text)
	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	-- refreshing menu to detect hotplugging of usb dacs
	local timer

	local updateMenu = function()
		local info = self:_parseCards()
		local slEnabled = self:_slIsEnabled()
		local items = {}

		if slEnabled then
			for num, card in ipairs(info) do
				items[#items+1] = {
					text = card.desc .. (self:_isActiveOutput(card.id) and tostring(self:string("ACTIVE")) or ""),
					callback = function(event, menuItem)
								   timer:stop()
								   self:cardMenu(card.id, card.desc)
							   end,
				}
			end
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
	local isActive = self:_isActiveOutput(card)
	local window = Window("text_list", desc)
	local menu = SimpleMenu("menu")
	local items = {}

	window:addWidget(menu)
	self:tieAndShowWindow(window)

	local activeEntry = {
		text = self:string("ACTIVE_DEVICE"),
		style = "item_no_arrow",
	}

	if isActive then
		items[1] = activeEntry
	else
		items[1] = {
			text = self:string("SELECT_DEVICE"),
			callback = function(event, menuItem)
						   self:_setActiveOutput(card)
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
		local alt  = parse("    Altset (%d+)")
		local fmt  = parse("    Format: (.*)")
		local chan = parse("    Channels: (%w+)")
		local type = parse("    Endpoint: %d+ %w+ %((%w+)%)")
		local rate = parse("    Rates: (.*)")
		skip(2)

		fmts[#fmts+1] = { intf = intf, alt = alt, fmt = fmt, chan = chan, type = type, rate = rate, int = int }

		if t.interface == intf and t.altset == alt then
			t.fmt = fmts[#fmts]
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

local active

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

function _isActiveOutput(self, card)
	--FIXME parse the active configuration...
	return card == active
end

function _setActiveOutput(self, card)
	active = card
	os.execute("echo 'AUDIO_DEV=" .. '"-o hw:CARD=' .. card .. ',DEV=0"\nALSA_PARAMS="-a 40:::"' .. "' > /tmp/squeezelite.config")
	os.execute("sudo cp /tmp/squeezelite.config /etc/sysconfig/squeezelite")
	os.execute("sudo systemctl restart squeezelite.service")
end
