--[[

Setup Networking Meta - configuration support for Networking for Community Squeeze Instance

(c) 2013, Adrian Smith, triode1@btinternet.com

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
	for _, a in ipairs(arg) do
		-- only loaded for community squeeze ui
		if string.match(a, "jivelite%-cs") or a == "--cs-applets" then
			jiveMain:addItem(
				meta:menuItem('appletSetupNetworking', 'networkSettings', meta:string("APPLET_NAME"),
							  function(applet, ...) applet:networkMenu(...) end
				)
			)
			return
		end
	end
end


