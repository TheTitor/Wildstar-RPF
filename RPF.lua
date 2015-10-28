-----------------------------------------------------------------------------------------------
-- Client Lua Script for RPF
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"
require "Unit"
require "ICComm"
require "ICCommLib"
require "GameLib"
require "HousingLib"
require "CombatFloater"
 
 
-----------------------------------------------------------------------------------------------
-- RPF Module Definition
-----------------------------------------------------------------------------------------------
local RPF = {} 
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function RPF:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
	o.tItems = {} -- keep track of all the list items
	o.wndSelectedListItem = nil -- keep track of which list item is currently selected    -- initialize variables here

    return o
end

function RPF:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {
		-- "UnitOrPackageName",
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 

-----------------------------------------------------------------------------------------------
-- RPF OnLoad
-----------------------------------------------------------------------------------------------
function RPF:OnLoad()
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("RPF.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end

function RPF:SetupComms()
	self.unit = GameLib.GetPlayerUnit()
	if self.unit ~=nil then
		self.playerName = self.unit:GetName()
		self.chanRPF = self.chanRPF .. self.unit:GetFaction()
		self.Comm = ICCommLib.JoinChannel(self.chanRPF, ICCommLib.CodeEnumICCommChannelType.Global)
		self.Comm:SetJoinResultFunction("OnJoinResult", self)
		self.Comm:SetReceivedMessageFunction("OnMessageReceived", self)
		self.Comm:SetSendMessageResultFunction("OnMessageSent", self)
		self.Comm:SetThrottledFunction("OnMessageThrottled", self)
		local sendHello = {}
		sendHello.flag = self.flag.newClient
		self:SendMessage(self.JSON.encode(sendHello))
		self:Print("Setup!")
		self.startupTimer:Stop()
	end
end


-----------------------------------------------------------------------------------------------
-- RPF OnDocLoaded
-----------------------------------------------------------------------------------------------
function RPF:OnDocLoaded()

	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.wndMain = Apollo.LoadForm(self.xmlDoc, "RPFForm", nil, self)
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			return
		end
		
		self.wndItemList = self.wndMain:FindChild("ItemList")
	    self.wndMain:Show(false, true)

		-- if the xmlDoc is no longer needed, you should set it to nil
		-- self.xmlDoc = nil
		
		-- Register handlers for events, slash commands and timer, etc.
		-- e.g. Apollo.RegisterEventHandler("KeyDown", "OnKeyDown", self)
		Apollo.RegisterSlashCommand("rpf", "OnRPFOn", self)

		-- create a channel for sending messages

		self.heartbeatHello = ApolloTimer.Create(20, true, "OnHeartbeatHello", self)
		self.heartbeatCompare = ApolloTimer.Create(40, true, "OnHeartbeatCompare", self)
		-- Do additional Addon initialization here
		self.chanRPF = "__RPF__" 
		self.DEBUGMODE = false
		self.kcrSelectedText = ApolloColor.new("yellow")
		self.kcrNormalText = ApolloColor.new("white")
		self.JSON = Apollo.GetPackage("Lib:dkJSON-2.5").tPackage
		self.selfAdvertUp = false
		self.flag = {}
		self.flag.newClient = 0
		self.flag.heartbeat = 1
		self.flag.addEvent = 2
		self.flag.editEvent = 3
		self.flag.removeEvent = 4
		self.decayTime = 59 -- decay timer in minute
		self.transmit = {}
		self.currentEntries = {}
		self.goToLocation = nil
		self.heartbeatEntries = {}
		self.selfAdvertTimestamp = nil
		self.Comm = nil
		self.startupTimer = ApolloTimer.Create(5, false, "SetupComms", self)
	end
end

-----------------------------------------------------------------------------------------------
-- RPF Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here

-- Sends a message as the current user to the ICCommLib channel
function RPF:SendMessage(message)
	if (self.unit ~= nil) and self.Comm:IsReady() then
		self.Comm:SendMessage(message)
		return true
	else
		self.startupTimer = ApolloTimer.Create(5, false, "SetupComms", self)
	end
	return false
end

-- on SlashCommand "/rpf"
function RPF:OnRPFOn()
	if self.Comm ~= nil then
   	 	self.wndMain:Invoke() -- show the window
		self.wndMain:FindChild("Location"):SetMaxTextLength(GameLib.GetTextTypeMaxLength(GameLib.CodeEnumUserText.CharacterName))
   	 	self.wndMain:FindChild("ShortDescription"):SetMaxTextLength(45)
    	self.wndMain:FindChild("LongDescription"):SetMaxTextLength(350)
	else FloatText("RPF is not ready. Wait 5 seconds then try again")
	end
end

-- on timer
function RPF:OnHeartbeatCompare()
   for k, v in pairs(self.currentEntries) do
	 local data = self.JSON.decode(v)
	 local diff =os.date("*t", os.difftime(os.time(), data.time))
     if (k ~= self.playerName and self.heartbeatEntries[k] == nil) or diff.min > self.decayTime then 
			self:DestroySingleEntry(k) 
	 end
   end
   for k, v in pairs(self.heartbeatEntries) do
    	if self.currentEntries[k] == nil then
			local sendHello = {}
			sendHello.flag = self.flag.newClient
			self.Comm:SendMessage(self.JSON.encode(sendHello))
			break
		end
   end
   self.heartbeatEntries = {}
	if self.selfAdvertUp then
	 local diff = os.date("*t", os.difftime(os.time(),self.selfAdvertTimestamp))
	 if diff.min > self.decayTime then
		self:OnRemoveEvent()
	 end
	end
end

function RPF:OnHeartbeatHello()
	for idx,wnd in pairs(self.tItems) do
		self:Print(idx)
	end
	if self.selfAdvertUp then
		local heartbeatmessage = {}
		heartbeatmessage.flag = self.flag.heartbeat
		self.Comm:SendMessage(self.JSON.encode(heartbeatmessage))
		self:OnMessageReceived(self.chanRPF, self.JSON.encode(heartbeatmessage), self.playerName)
	end
end

function RPF:Print(strToPrint)
	if self.DEBUGMODE then
	 	Print(strToPrint)
	end
end

function RPF:OnJoinResult(channel, eResult)
	local bJoin = eResult == ICCommLib.CodeEnumICCommJoinResult.Join
	if bJoin then
		self:Print(string.format('RPF: Joined ICComm Channel "%s"', channel:GetName()))
		if channel:IsReady() then
			self:Print('RPF: Channel is ready to transmit')
		else
			self:Print('RPF: Channel is not ready to transmit')
		end
	else
		self:Print('RPF: Failed to join')	
	end
end

function RPF:OnMessageReceived(channel, strMessage, strSender)
		data = self.JSON.decode(strMessage)
		if data.flag == self.flag.addEvent or data.flag == self.flag.editEvent then
			self:DestroySingleEntry(strSender)
			self:AddItem(strSender, data.short, data.loc, data.long)
    		self.wndItemList:ArrangeChildrenVert()
			self.currentEntries[strSender] = strMessage
			self.heartbeatEntries[strSender] = strMessage
		elseif data.flag == self.flag.newClient then
			if self.selfAdvertUp then
				self.Comm:SendPrivateMessage(strSender, self.JSON.encode(self.transmit))
			end
		elseif data.flag == self.flag.heartbeat then
			self.heartbeatEntries[strSender] = strMessage
		elseif data.flag == self.flag.removeEvent then
			self:DestroySingleEntry(strSender)
		end
		self:Print(string.format("Received: %s %s", strMessage, strSender))
end

function RPF:OnMessageSent(channel, eResult, idMessage)
end
-----------------------------------------------------------------------------------------------
-- RPFForm Functions
-----------------------------------------------------------------------------------------------
-- when the OK button is clicked
function RPF:OnOK()
	if self.goToLocation ~= nil then
		if HousingLib.IsHousingWorld() then
			HousingLib.RequestVisitPlayer(self.goToLocation)
		else
			FloatText("You must be in the housing world to teleport there")
		end
	end
end

-- when the Cancel button is clicked
function RPF:OnCancel()
	self.wndMain:Close() -- hide the window
end

function RPF:OnReenableComs()
	local editButton = self.wndMain:FindChild("AddEvent"):Enable(true)
	self.delayButtonPressing:Stop()
end

function RPF:OnRemoveEvent()
	if self.selfAdvertUp then 
		self:DestroySingleEntry(self.playerName)
		local destroyMessage = {}
		destroyMessage.flag = self.flag.removeEvent
		destroyMessage.owner = self.playerName
		self.Comm:SendMessage(self.JSON.encode(destroyMessage))
		self.selfAdvertUp = false
		self.wndMain:FindChild("AddEvent"):SetText("Add RP Event")
	end
end


function RPF:OnAddEvent( wndHandler, wndControl, eMouseButton )
	if not self.selfAdvertUp then
    	self.wndItemList:ArrangeChildrenVert()
		self.selfAdvertUp = true
		self.selfAdvertTimestamp = os.time()
		self.transmit.flag = self.flag.addEvent
		self.transmit.short = self.wndMain:FindChild("ShortDescription"):GetText()
		self.transmit.loc = self.wndMain:FindChild("Location"):GetText()
		self.transmit.long = self.wndMain:FindChild("LongDescription"):GetText()
		self.transmit.time = self.selfAdvertTimestamp
		self.Comm:SendMessage(self.JSON.encode(self.transmit))
		self:OnMessageReceived(self.chanRPF, self.JSON.encode(self.transmit), self.playerName)
		self.currentEntries[self.playerName] = self.JSON.encode(self.transmit)
		self.heartbeatEntries[self.playerName] = self.JSON.encode(self.transmit)
		wndControl:SetText("Edit RP Event")
	else
		if (self.wndMain:FindChild("ShortDescription"):GetText() ~= self.transmit.short or self.wndMain:FindChild("Location"):GetText() ~= self.transmit.loc or self.wndMain:FindChild("LongDescription"):GetText()~= self.transmit.long) then
			self.transmit.flag = self.flag.editEvent
			self.transmit.short = self.wndMain:FindChild("ShortDescription"):GetText()
			self.transmit.loc = self.wndMain:FindChild("Location"):GetText()
			self.transmit.long = self.wndMain:FindChild("LongDescription"):GetText()
			self.transmit.time = self.selfAdvertTimestamp
			self.Comm:SendMessage(self.JSON.encode(self.transmit))
			self.currentEntries[self.playerName] = self.JSON.encode(self.transmit)
			self.heartbeatEntries[self.playerName] = self.JSON.encode(self.transmit)
			self:OnMessageReceived(self.chanRPF, self.JSON.encode(self.transmit),self.playerName)
		end
	end
	wndControl:Enable(false)
	self.delayButtonPressing = ApolloTimer.Create(20, false, "OnReenableComs", self)

end

-----------------------------------------------------------------------------------------------
-- ItemList Functions
-----------------------------------------------------------------------------------------------
--self.wndItemList:ArrangeChildrenVert()

function RPF:DestroySingleEntry(name)
	if self.tItems ~= nil and self.tItems[name] ~= nil then
		if self.wndSelectedListItem == self.tItems[name] then
			self.wndSelectedListItem = nil
			self.goToLocation = nil
		end
		self.currentEntries[name] = nil
		self.tItems[name]:Destroy()
		self.tItems[name] = nil
		self.currentEntries[name] = nil
    	self.wndItemList:ArrangeChildrenVert()
		self:DestroySingleEntry(name)
	end
end

-- clear the item list
function RPF:DestroyItemList()
	-- destroy all the wnd inside the list
	for idx,wnd in pairs(self.tItems) do
		wnd:Destroy()
	end

	-- clear the list item array
	self.tItems = {}
	self.wndSelectedListItem = nil
end

-- add an item into the item list
function RPF:AddItem(owner, shortDesc, location, longDesc)
	self:DestroySingleEntry(owner)
	-- load the window item for the list item
	local wnd = Apollo.LoadForm(self.xmlDoc, "ListItem", self.wndItemList, self)
	-- keep track of the window item created
	self.tItems[owner] = wnd
	-- give it a piece of data to refer to 
	local wndItemText = wnd:FindChild("ListText")
	local wndItemText2 = wnd:FindChild("ListLocation")
	if wndItemText and wndItemText2 and shortDesc and longDesc and location then -- make sure the text wnd exist
		wndItemText:SetText(shortDesc)
		wnd:SetTooltip(longDesc)
		wndItemText2:SetText(location)
		wndItemText:SetTextColor(self.kcrNormalText)
		wndItemText2:SetTextColor(self.kcrNormalText)
		self.wndItemList:ArrangeChildrenVert()
		self.currentEntries[owner] = strMessage
		self.heartbeatEntries[owner] = strMessage	 
		wnd:SetData(owner)
	end
end

-- when a list item is selected
function RPF:OnListItemSelected(wndHandler, wndControl)
    -- make sure the wndControl is valid
    if wndHandler ~= wndControl then
        return
    end
    
    -- change the old item's text color back to normal color
    local wndItemText
    local wndItemText2
    if self.wndSelectedListItem ~= nil then
        wndItemText = self.wndSelectedListItem:FindChild("ListText")
		wndItemText2 = self.wndSelectedListItem:FindChild("ListLocation")
        wndItemText:SetTextColor(self.kcrNormalText)
		wndItemText:SetText(string.sub(wndItemText:GetText(), 3))
		wndItemText2:SetTextColor(self.kcrNormalText)
    end

    
	-- wndControl is the item selected - change its color to selected
	self.wndSelectedListItem = wndControl
	wndItemText = self.wndSelectedListItem:FindChild("ListText")
	wndItemText2 = self.wndSelectedListItem:FindChild("ListLocation")
	wndItemText:SetText("->" .. wndItemText:GetText())
    wndItemText:SetTextColor(self.kcrSelectedText)
    wndItemText2:SetTextColor(self.kcrSelectedText)
	self.goToLocation = wndItemText2:GetText()
	self:Print( "item " ..  self.wndSelectedListItem:GetData() .. " is selected.")
end


-----------------------------------------------------------------------------------------------
-- RPF Instance
-----------------------------------------------------------------------------------------------
local RPFInst = RPF:new()
RPFInst:Init()
