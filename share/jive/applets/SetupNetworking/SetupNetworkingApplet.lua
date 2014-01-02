--[[

SetupNetworking Applet - configuration for network

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
local Textinput        = require("jive.ui.Textinput")
local Keyboard         = require("jive.ui.Keyboard")
local Group            = require("jive.ui.Group")
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
local Process          = require("jive.net.Process")
local debug            = require("jive.utils.debug")

local appletManager    = appletManager
local jnt              = jnt

local string, pairs, ipairs, tonumber, tostring, type, bit = string, pairs, ipairs, tonumber, tostring, type, bit

module(..., Framework.constants)
oo.class(_M, Applet)


function networkMenu(self, menuItem)
	local window = Window("text_list", self:string("SELECT_WIFI_NETWORK"))
	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	-- refreshing menu to show wifi networks
	local timer
	local items
	local count = 0

	local updateMenu
	updateMenu = function()
		local current = self:_getSSID()
		items = {}
		if current then
			items[1] = {
				text = self:string("DISABLE_WIFI"),
				callback = function(object, isSelected)
							   self:_setSSID(nil)
							   self:_setPSK(nil)
							   self:_wifiRestart()
							   updateMenu()
							   timer:restart()
						   end,
			}
		else
			items[1] = {
				text = self:string("WIFI_DISABLED"),
				style = "item_no_arrow",
			}
		end

		count = count + 1
		local instance = count

		local cb = function(scan, status)
					   if count == instance then
						   -- current configure network first
						   if current then
							   local iconstyle
							   if status.ssid and status.ssid == current and status.wpa_state == "COMPLETED" then
								   iconstyle = "wirelessWaiting"
							   else
								   iconstyle = "wirelessDisabled"
							   end
							   items[#items+1] = {
								   text = current,
								   style = 'item_checked',
								   arrow = Icon(iconstyle),
								   callback = function(event, menuItem)
												  self:pskMenu(current)
											  end
							   }
						   end

						   -- remaining scan items
						   for _, v in ipairs(scan) do
							   -- FIXME - only support networks using PSK at present
							   if v.ssid ~= current and string.match(v.flags, "PSK") then
								   items[#items+1] = {
									   text = v.ssid,
									   arrow = Icon("wirelessLevel" .. (v.quality or 0)),
									   callback = function(event, menuItem)
													  self:pskMenu(v.ssid)
												  end
								   }
							   end
						   end
						   items[#items+1] = {
							   text = self:string("HIDDEN_NETWORK"),
							   callback = function(event, menuItem)
											  self:ssidMenu()
										  end
						   }

						   menu:setItems(items, #items)
					   end
				   end
		self:_scan(cb)
	end

	-- update on a timer
	timer = Timer(2000, function() updateMenu() end, false)
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


function ssidMenu(self)
	local window = Window("input", tostring(self:string("ENTER_SSID")), 'setuptitle')
	window:setAllowScreensaver(false)

	local v = Textinput.textValue("", 1, 32)
	local textinput = Textinput("textinput", v,
								function(widget, value)
									value = tostring(value)
									if #value == 0 then
										window:hide()
										return false
									end
									window:hide()
									self:pskMenu(value)
									return true
								end
							)

	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )

	window:addWidget(group)
	window:addWidget(Keyboard("keyboard", 'qwerty', textinput))
	window:focusWidget(group)

	self:tieAndShowWindow(window)
end

	
function pskMenu(self, ssid)
	local window = Window("input", tostring(self:string("ENTER_PSK")) .. " " .. ssid, 'setuptitle')
	window:setAllowScreensaver(false)

	local v = Textinput.textValue("", 1, 32)
	local textinput = Textinput("textinput", v,
								function(widget, value)
									value = tostring(value)
									if #value == 0 then
										window:hide()
										return false
									end
									window:hide()
									local popup = Popup("waiting_popup")
									popup:addWidget(Icon("icon_connecting"))
									popup:addWidget(Label("text", tostring(self:string("CONNECTING")) .. " " .. ssid))
									self:tieAndShowWindow(popup)
									self:_setPSK(value)
									self:_setSSID(ssid)
									self:_wifiRestart(function() popup:hide() end)
									return true
								end
							)

	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )

	window:addWidget(group)
	window:addWidget(Keyboard("keyboard", 'qwerty', textinput))
	window:focusWidget(group)

	self:tieAndShowWindow(window)
end


function _request(self, req, cb)
	local cmd = "sudo wpa_cli " .. req
	local res = ""
	
	Process(jnt, cmd):read(
		function(chunk, err)
			if err then
				log:warn(err)
				cb(nil)
			end
			
			if chunk then
				res = res .. chunk
			else
				cb(res)
			end
	end)
end


function _status(self, cb)
	self:_request("status",
		function(res)
			local t = {}
			for line in string.gmatch(res, "(.-)\n") do
				local k, v = string.match(line, "(.-)=(.*)")
				if k and v then
					t[k] = v
				end
			end
			cb(t)
		end
	)
end


function _scan(self, cb)
	local step1
	local step2
	local step3

	local status, scan = {}, {}

	-- wpa_cli status
	step1 = function()
		self:_status(function(res) status = res step2() end)		
	end

	-- wpa_cli scan
	step2 = function()
		self:_request("scan", 
			function(res)
				if string.match(res, "OK") then
					step3()
				else
					log:warn(res)
					cb(scan, status)
				end
			end
		)
	end

	-- wpa_cli scan_results
	step3 = function()
		self:_request("scan_results", 
			function(res)
				for line in string.gmatch(res, "(.-)\n") do
					local bssid, freq, signal, flags, ssid = string.match(line, "(%x+:%x+:%x+:%x+:%x+:%x+)%s+(.+)%s+(.+)%s+(.+)%s+(.+)")
					local quality
					signal = tonumber(signal)
					if signal then
						if signal > -25 then
							quality = 4
						elseif signal > -40 then
							quality = 3
						elseif signal > -60 then
							quality = 2
						else
							quality = 1
						end
					end
					if ssid then
						scan[#scan+1] = { ssid = ssid, flags = flags, quality = quality }
					end
				end
				cb(scan, status)
			end
		)
	end

	step1()
end


-- make these system specific...

local configFile    = "/etc/sysconfig/network-scripts/ifcfg-wlan0"
local configFileTmp = "/tmp/ifcfg-wlan0"
local pskFileTmp    = "/tmp/tmp.txt"
local wlanInterface = "wlan0"


function _setSSID(self, ssid)
	local inconf  = io.open(configFile, "r")
	local outconf = io.open(configFileTmp, "w")
	if inconf == nil or outconf == nil then
		log:warn("can't open config files, aborting save")
		return
	end

	if ssid == nil then
		ssid = "YOUR_ESSID_HERE"
	end

	log:info("setting wifi ssid")

	for line in inconf:lines() do
		if string.match(line, "ESSID") then
			outconf:write('ESSID="' .. ssid .. '"\n')
		else
			outconf:write(line .. "\n")
		end
	end

	inconf:close()
	outconf:close()

	os.execute("sudo csos-ifcfgUpdate " .. configFileTmp .. " " .. wlanInterface)
end


function _getSSID(self)
	local ssid
	local conf = io.open(configFile, "r")
	if conf == nil then
		log:warn("can't open config files")
		return
	end

	for line in conf:lines() do
		if string.match(line, "ESSID") then
			ssid = string.match(line, 'ESSID="(.*)"')
		end
	end

	conf:close()

	if ssid == "YOUR_ESSID_HERE" then
		ssid = nil
	end

	return ssid
end


function _setPSK(self, psk)
	log:info("setting wifi psk")

	if psk == nil then
		psk = "YOUR_PSK_HERE"
	end

	local file = io.open(pskFileTmp, "w")
	file:write('WPA_PSK=' .. "'" .. psk .. "'\n")
	file:close()
	os.execute("sudo csos-keysUpdate " .. pskFileTmp .. " " .. wlanInterface)
	os.execute("rm " .. pskFileTmp)
end


function _wifiRestart(self, cb)
	log:info("restarting wlan0")

	local exec = function(cmd, cb)
		Process(jnt, cmd):read(
			function(chunk, err)
				if err then
					log:warn(err)
					cb(nil)
				end
				
				if chunk then
					res = res .. chunk
				else
					log:info(res)
					if cb then
						cb()
					end
				end
			end
		)
	end

	exec("sudo ifdown wlan0", function() exec("sudo ifup wlan0", cb) end)
end
