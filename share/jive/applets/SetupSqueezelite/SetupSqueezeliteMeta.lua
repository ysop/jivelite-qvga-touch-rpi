--[[

Setup Squeezelite Meta - configuration support for Squeezelite player to set 
alsa params for Wandboard Squeeze Player Instance

(c) 2013-2014, Adrian Smith, triode1@btinternet.com

--]]

local oo         = require("loop.simple")
local AppletMeta = require("jive.AppletMeta")
local jiveMain   = jiveMain

local arg, ipairs, string = arg, ipairs, string

module(...)
oo.class(_M, AppletMeta)


function jiveVersion(meta)
	return 1, 1
end


function defaultSettings(meta)
	return { 
	}
end


function registerApplet(meta)
	-- only load on Squeeze Player control instance
	local load = false
	if string.match(arg[0], "jivelite%-sp") then
		load = true
	end
	for _, a in ipairs(arg) do
		if a == "--sp-applets" then
			load = true
		end
	end

	if load then
		jiveMain:addItem(
			meta:menuItem('appletSetupSqueezelite', 'settingsAudio', meta:string("APPLET_NAME"), 
						  function(applet, ...) applet:deviceMenu(...) end
			)
		)
	end
end
