-- stuff we use
local ipairs, pairs, assert, io, string = ipairs, pairs, assert, io, string

local oo               = require("loop.simple")

local Applet           = require("jive.Applet")
local RadioGroup       = require("jive.ui.RadioGroup")
local RadioButton      = require("jive.ui.RadioButton")
local Framework        = require("jive.ui.Framework")
local Label            = require("jive.ui.Label")
local Icon             = require("jive.ui.Icon")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Surface          = require("jive.ui.Surface")
local Textarea         = require("jive.ui.Textarea")
local Window           = require("jive.ui.Window")
local System           = require("jive.System")
local Player           = require("jive.slim.Player")

local jnt              = jnt
local appletManager    = appletManager

local jiveMain         = jiveMain

local welcomeTitleStyle = 'setuptitle'
local disableHomeKeyDuringSetup
local freeAppletWhenEscapingSetup

module(..., Framework.constants)
oo.class(_M, Applet)


function setupFirstStartup(self)
	self:getSettings().setupDone = true
	self:storeSettings()

	local step1, step2

	step1 = function()
				appletManager:callService("setupShowSetupLanguage", step2, false)
			end

	step2 = function()
				appletManager:callService("selectSkinStartup", function() self:setupDone() end)
			end
	
	step1()
end


function setupDone(self)
	for i, player in Player.iterate() do
		if player:getId() == System:getMacAddress() then
			jiveMain:closeToHome(true, Window.transitionPushLeft)
			return appletManager:callService("selectPlayer", player)
		end
	end

	return appletManager:callService("setupShowSelectPlayer", 
									 function()
										 jiveMain:closeToHome(true, Window.transitionPushLeft)
									 end, 
									 'setuptitle')
end
