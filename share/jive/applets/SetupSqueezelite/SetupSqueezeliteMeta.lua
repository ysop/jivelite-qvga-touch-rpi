--[[

Setup Squeezelite Meta - configuration support for Squeezelite player to set alsa params

(c) 2013, Adrian Smith, triode1@btinternet.com

--]]

local oo         = require("loop.simple")
local AppletMeta = require("jive.AppletMeta")
local jiveMain   = jiveMain

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
	jiveMain:addItem(
		meta:menuItem('appletSetupSqueezelite', 'settingsAudio', meta:string("APPLET_NAME"), 
			function(applet, ...) applet:deviceMenu(...) end
		)
	)
end


