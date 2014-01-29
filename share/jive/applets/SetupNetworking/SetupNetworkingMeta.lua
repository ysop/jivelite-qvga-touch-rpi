--[[

Setup Networking Meta - configuration support for Networking on Wandboard 
Squeeze Player Instance

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
	-- only load on Wandboard Squeeze Player control instance
	local load = false
	if string.match(arg[0], "jivelite%-wsp") then
		load = true
	end
	for _, a in ipairs(arg) do
		if a == "--wsp-applets" then
			load = true
		end
	end

	if load then
		jiveMain:addItem(
			meta:menuItem('appletSetupNetworking', 'networkSettings', meta:string("APPLET_NAME"),
						  function(applet, ...) applet:networkMenu(...) end
			)
		)
	end
end


