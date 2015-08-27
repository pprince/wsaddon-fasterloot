-----------------------------------------------------------------------------------------------
-- Client Lua Script for FasterLoot
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"
require "ChatSystemLib"
 
-----------------------------------------------------------------------------------------------
-- FasterLoot Module Definition
-----------------------------------------------------------------------------------------------
local FasterLoot = {} 
local addonCRBML = Apollo.GetAddon("MasterLoot")

-----------------------------------------------------------------------------------------------
-- FasterLoot constants
-----------------------------------------------------------------------------------------------
local FASTERLOOT_CURRENT_VERSION = "0.1.0"

-- List of items mapped to designated looters
-- The key is a match string, used in string.match, and may contain regex symbols
-- TO EDIT: Add a LUA match string as the key, and the name of a character as the value
-- e.g.: ["Eldan Runic Module"] = "Chimpy Evans"
--       ["^Sign of %a+ %- Eldan$"] = "Chimpy Evans"

local player_name = "J Teatime"

local tDesignatedLooters = {
	--
	--  KEEP FOR GUILD
	--
	["Runic Elemental Flux"] 			= player_name,
	["Partial Primal Pattern"] 			= player_name,
	["Tarnished Eldan Gift"] 			= player_name,
	["Encrypted Datashard"] 			= player_name,
	["Suspended Bio%-Phage Cluster"] 	= player_name,
	["Pristine Genesis Key"] 			= player_name,
	["^Warplot Boss Token: .+"] 		= player_name,
	["^Recipe: .+"] 					= player_name,
	["Spikehorde Meat"]					= player_name,
	["Spikehorde Shell Meat"]			= player_name,
	["Behemoth Meat"]					= player_name
}

-- List of items that are always randomed.
-- WARNING: This always takes precedence (Not true, designated looters take precedence)
-- TO EDIT: Add an item name as the key, and anything as the value
-- e.g.: ["Partial Primal Pattern"] = 0
local tWhiteList = {
	--
	--  RANDOM OFF
	--
	["Eldan Runic Module"] 				= 0,
	["Sign of Fire - Eldan"] 			= 0,
	["Sign of Fusion - Eldan"] 			= 0,
	["Sign of Logic - Eldan"] 			= 0,
	["Sign of Air - Eldan"] 			= 0,
	["Sign of Water - Eldan"] 			= 0,
	["Sign of Earth - Eldan"] 			= 0,
	["Sign of Life - Eldan"] 			= 0
}
	

-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function FasterLoot:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

    -- initialize variiables here

    return o
end

function FasterLoot:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {
		-- "UnitOrPackageName",
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)

	self.settings = {}
	self.settings.user = {}
	self.settings.user.debug = false
	self.settings.user.version = FASTERLOOT_CURRENT_VERSION

	self.tOldMasterLootList = {}

end

function FasterLoot:OnLoad()
	self.xmlDoc = XmlDoc.CreateFromFile("FasterLoot.xml")
	self.xmlDoc:RegisterCallback("OnDocReady", self)

	Apollo.RegisterSlashCommand("fasterloot", "OnSlashCommand", self)
end

function FasterLoot:OnDocReady()
	if self.xmlDoc == nil then
		return
	end
	
	-- Delayed timer to fix Carbine's MasterLoot on /reloadui
	Apollo.RegisterTimerHandler("FixCRBML_Delay", "FixCRBML", self)

	-- Event that fires when new loot needs to be handled
	Apollo.RegisterEventHandler("MasterLootUpdate", "OnMasterLootUpdate", self)

	self.wndFasterLoot = Apollo.LoadForm(self.xmlDoc, "FasterLootWindow", nil, self)
	if self.settings.user.tSavedWindowLoc then
		locSavedLoc = WindowLocation.new(self.settings.user.tSavedWindowLoc)
		self.wndFasterLoot:MoveToLocation(locSavedLoc)
	end
	self.wndFasterLoot:Show(false)

end

-----------------------------------------------------------------------------------------------
-- FasterLoot Functions
-----------------------------------------------------------------------------------------------
-- Handle slash commands
function FasterLoot:OnSlashCommand(cmd, params)

    p = string.lower(params)

	args = split(p, "[ ]+")

	if args[1] == "debug" then
		if #args == 2 then
			if args[2] == "update" then
				self:OnMasterLootUpdate(true)
			end
		else
			self:ToggleDebug()
		end
	elseif args[1] == "show" then
		self.wndFasterLoot:Show(true)
	else
        self:PrintCMD("FasterLoot v" .. self.settings.user.version)
		self:PrintCMD("Chimpy Evans on Entity")
		self:PrintCMD("--- FOR SCIENCE ---")
		self:PrintCMD("Open Filter Window (Not Yet Implemented)")
		self:PrintCMD("    /fasterloot show")
		self:PrintCMD("Toggle Debug")
		self:PrintCMD("    /fasterloot debug")
		self:PrintCMD("Update the Window")
		self:PrintCMD("    /fasterloot debug update")
	end
end

-- Returns a table of all Master Lootable items. Filters
-- out those items which are not supposed to go through MasterLoot
function FasterLoot:GatherMasterLoot()
	-- tLootList is a table
	-- index => {
	--   tLooters => Table of valid looters, used in AssignMasterLoot
	--   itemDrop => Actual item (e.g.: GetDetailedData())
	--   nLootId => Loot drop ID, used in AssignMasterLoot
	--   bIsMaster => If the item is valid master loot fodder
	-- }

	-- Get all loot
	local tLootList = GameLib.GetMasterLoot()

	-- Gather all the master lootable items
	local tMasterLootList = {}
	for idxNewItem, tCurMasterLoot in pairs(tLootList) do
		if tCurMasterLoot.bIsMaster then
			table.insert(tMasterLootList, tCurMasterLoot)
		end
	end

	return tMasterLootList
end

-- When Master Loot is updated, check each one for filtering, and random those
-- drops that fit the filter.
function FasterLoot:OnMasterLootUpdate(bForceOpen)
	local tMasterLootList = self:GatherMasterLoot()

	-- Check each item against the filter, and then random the ones that pass
	for idxMasterItem, tCurMasterLoot in pairs(tMasterLootList) do
		-- Prioritize designated looters first.
		tDesignatedLooter = self:DesignatedLooterForItemDrop(tCurMasterLoot)
		if tDesignatedLooter ~= nil then
			local strItemLink = tCurMasterLoot.itemDrop:GetChatLinkString()
			local strItemName = tCurMasterLoot.itemDrop:GetName()
			self:PrintDB("Assigning " .. strItemName .. " to designated " .. tDesignatedLooter:GetName())
			self:PrintParty("Keeping " .. strItemLink .. " for the guild, via " .. tDesignatedLooter:GetName() .. ".")
			GameLib.AssignMasterLoot(tCurMasterLoot.nLootId, tDesignatedLooter)
		-- Check to see if we can just random the item out
		elseif self:ItemDropShouldBeRandomed(tCurMasterLoot) then
			local strItemLink = tCurMasterLoot.itemDrop:GetChatLinkString()
			local strItemName = tCurMasterLoot.itemDrop:GetName()
			local randomLooter = tCurMasterLoot.tLooters[math.random(1, #tCurMasterLoot.tLooters)]
			self:PrintDB("Assigning " .. strItemName .. " to " .. randomLooter:GetName())
			self:PrintParty("Randomly assigning " .. strItemLink .. " to " .. randomLooter:GetName() .. ".")
			GameLib.AssignMasterLoot(tCurMasterLoot.nLootId, randomLooter)
		-- Otherwise, drop it to the master loot window
		else
			self:PrintDB("Not assigning " .. tCurMasterLoot.itemDrop:GetName())
		end
	end

	-- Update the old master loot list
	self.tOldMasterLootList = tMasterLootList
end

-- Allow some items to go directly to some people
function FasterLoot:DesignatedLooterForItemDrop(tMasterLoot)
	strItemName = tMasterLoot.itemDrop:GetName()
	self:PrintDB("Entering to check designated loot for" .. strItemName)
	-- Iterate through the designated looter table, seeing if an entry exists for this item
	-- If we find a match, check to see if the looter we want is available.
	strDesignatedLooterName = self:GetDesignatedLooter(strItemName)
	if strDesignatedLooterName ~= nil then
		self:PrintDB("It is designated loot. Is the looter " .. strDesignatedLooterName .. " available?")
		for _, unitCurLooter in pairs(tMasterLoot.tLooters) do
			strCurLooterName = unitCurLooter:GetName()
			self:PrintDB("Checking " .. strCurLooterName)
			if strDesignatedLooterName == strCurLooterName then
				self:PrintDB("Yes! Give it out!")
				return unitCurLooter
			else
				self:PrintDB("No!")
			end
		end
		self:PrintDB("No designated looter available")
	else
		self:PrintDB("Not designated loot")
	end

	return nil
end

-- Given an item name, check it against the matches in the designated looter list
-- Returns the looter's name if a match is found
-- TODO: Multiple designated looters for backups?
function FasterLoot:GetDesignatedLooter(strItemName)
	for strDesignatedMatch, strDesignatedLooter in pairs(tDesignatedLooters) do
		if string.match(strItemName, strDesignatedMatch) then
			return strDesignatedLooter
		end
	end
	return nil
end

-- Filter oracle function used to determine if one particular item should
-- be randomed to a valid looter.
function FasterLoot:ItemDropShouldBeRandomed(tMasterLoot)
	-- Designated loot should never be randomed
	strItemName = tMasterLoot.itemDrop:GetName()
	if self:GetDesignatedLooter(strItemName) ~= nil then
		self:PrintDB("Designated loot should never be randomed")
		return false
	end
	
	tDetailedInfo = tMasterLoot.itemDrop:GetDetailedInfo().tPrimary
	enumItemQuality = tMasterLoot.itemDrop:GetItemQuality()
	strItemType = tMasterLoot.itemDrop:GetItemTypeName()
	
	--for key, val in pairs(tDetailedInfo) do
	--	self:PrintDB(key .. " => " .. tostring(val))
	--end

	-- White list items are ALWAYS randomed...
	if tWhiteList[strItemName] ~= nil then
		return true
	end
	
	-- Purples/Orange/Pinks are currently always interesting
	if enumItemQuality == Item.CodeEnumItemQuality.Superb or
	   enumItemQuality == Item.CodeEnumItemQuality.Legendary or
	   enumItemQuality == Item.CodeEnumItemQuality.Artifact then
		self:PrintDB("Can't random " .. strItemName .. " because of quality")
		return false
	end

	-- If the item level is below an item level threshold
	if tDetailedInfo.nEffectiveLevel > 55 then
		self:PrintDB("Can't random " .. strItemName .. " because of ilvl")
		return false
	end

	-- Various desirable items
	if strItemName == "Eldan Runic Module" or
	   strItemName == "Suspended Biophage Cluster" or	
	   string.find(strItemName, "Archivos") or
	   string.find(strItemName, "Warplot Boss") or
	   string.match(strItemName, "Sign of %a+ - Eldan") or
	   string.find(strItemName, "Ground Mount") or
	   string.find(strItemName, "Hoverboard Mount") then
		self:PrintDB("Can't random " .. strItemName .. " because of name")
		return false
	end

	-- Why do people care about these?
	if strItemType == "Decor" or
	   strItemType == "Improvement" then
		self:PrintDB("Can't random " .. strItemName .. " because of type")
		return false
	end

	return true
end

-----------------------------------------------------------------------------------------------
-- Save/Restore functionality
-----------------------------------------------------------------------------------------------
function FasterLoot:OnSave(eType)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then return end

	return FasterLoot.deepcopy(self.settings)
end

function FasterLoot:OnRestore(eType, tSavedData)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then return end
	self.tOldMasterLootList = self:GatherMasterLoot()

	if tSavedData and tSavedData.user then
		-- Copy the settings wholesale
		self.settings.user = FasterLoot.deepcopy(tSavedData.user)
		
		-- This section is for converting between versions that saved data differently

		-- Now that we've turned the save data into the most recent version, set it
		self.settings.user.version = FASTERLOOT_CURRENT_VERSION
	end

	if #self.tOldMasterLootList > 0 and addonCRBML ~= nil then
		-- Try every second to bring the window back up...
		Apollo.CreateTimer("FixCRBML_Delay", 1, false)
		Apollo.StartTimer("FixCRBML_Delay")
	end
end

-- This function is called on a timer from OnRestore to attempt to open Carbine's MasterLoot addon,
-- which doesn't automatically open if loot exists
function FasterLoot:FixCRBML()
	-- Hack, Carbine's ML OnLoad sets this field
	-- We use it to determine when Carbine is done loading
	if addonCRBML.tOld_MasterLootList ~= nil then
		self:PrintDB("Trying to open up MasterLoot!")
		addonCRBML:OnMasterLootUpdate(true)
		self:OnMasterLootUpdate(false)
	else
		self:PrintDB("MasterLoot not ready, trying again")
		Apollo.CreateTimer("FixCRBML_Delay", 1, false)
		Apollo.StartTimer("FixCRBML_Delay")
	end
end

-- Copied from StrikeHardMeter
-- I would use GeminiDB, but it's something new I'd have to learn...
function FasterLoot.deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[FasterLoot.deepcopy(orig_key)] = FasterLoot.deepcopy(orig_value)
        end
        setmetatable(copy, FasterLoot.deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-----------------------------------------------------------------------------------------------
-- Wrappers for debug functionality
-----------------------------------------------------------------------------------------------
function FasterLoot:ToggleDebug()
	if self.settings.user.debug then
		self:PrintDB("Debug turned off")
		self.settings.user.debug = false
	else
		self.settings.user.debug = true
		self:PrintDB("Debug turned on")
	end
end

function FasterLoot:PrintParty(str)
	for _,channel in pairs(ChatSystemLib.GetChannels()) do
		if channel:GetType() == ChatSystemLib.ChatChannel_Party then
			channel:Send("[Loot]: " .. str)
		end
	end
end

function FasterLoot:PrintDB(str)
	if self.settings.user.debug then
		ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_Debug, "[Loot]: " .. str)
	end
end

function FasterLoot:PrintCMD(str)
	ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_Command, str)
end

-----------------------------------------------------------------------------------------------
-- FasterLoot form functions
-----------------------------------------------------------------------------------------------
function FasterLoot:OnCloseFilterWindow()
	self:PrintDB("Closing window, saving location")
	self.settings.user.tSavedWindowLoc = self.wndFasterLoot:GetLocation():ToTable()
	self.wndFasterLoot:Show(false)
end

-----------------------------------------------------------------------------------------------
-- Local functions
-----------------------------------------------------------------------------------------------
-- Helper used to split up string and argument for slash command processing
-- Stolen shamelessly
function split(str, pat)
	local t = {}  -- NOTE: use {n = 0} in Lua-5.0
	local fpat = "(.-)" .. pat
	local last_end = 1
	local s, e, cap = str:find(fpat, 1)
	while s do
		if s ~= 1 or cap ~= "" then
			table.insert(t, cap)
      	end
      	last_end = e+1
      	s, e, cap = str:find(fpat, last_end)
   	end
   	if last_end <= #str then
		cap = str:sub(last_end)
      	table.insert(t, cap)
   	end
	return t
end

-----------------------------------------------------------------------------------------------
-- FasterLoot Instance
-----------------------------------------------------------------------------------------------
local FasterLootInst = FasterLoot:new()
FasterLootInst:Init()
