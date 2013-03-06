MountManager = LibStub("AceAddon-3.0"):NewAddon("MountManager", "AceConsole-3.0", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("MountManager")
local M = LibStub("LibMounts-1.0")

------------------------------------------------------------------
-- Local Settings
------------------------------------------------------------------
local state = {}
local options = {
    name = "MountManager",
    handler = MountManager,
    type = "group",
    args = {
        desc = {
            type = "description",
            name = L["Description"],
            order = 0,
        },
        showInChat = {
            type = "toggle",
            name = L["Show in Chat"],
            desc = L["Toggles the display of the mount name in the chat window."],
            get = "GetShowInChat",
            set = "SetShowInChat",
            width = "full",
        },
        alwaysDifferent = {
            type = "toggle",
            name = L["Always Different"],
            desc = L["Always select a different mount than the previous one."],
            get = "GetAlwaysDifferent",
            set = "SetAlwaysDifferent",
            width = "full",
        },
        safeFlying = {
            type = "toggle",
            name = L["Safe Flying"],
            desc = L["Toggles the ability to dismount when flying"],
            get = "GetSafeFlying",
            set = "SetSafeFlying",
            width = "full",
        },
        oneClick = {
            type = "toggle",
            name = L["One Click"],
            desc = L["One click will dismount you and summon the next available mount."],
            get = "GetOneClick",
            set = "SetOneClick",
            width = "full",
        },
        autoNextMount = {
            type = "toggle",
            name = L["Automatic Next Mount"],
            desc = L["Automatically determine the next available random mount after summoning the currently selected one."],
            get = "GetAutoNextMount",
            set = "SetAutoNextMount",
            width = "full",
        },
    },
}
local defaults = {
    char = {
        level = level,
        race = race,
        class = class,
		prof = {},
        mount_skill = 0,
		serpent = false,
        mounts = {
			skill = {},
            ground = {},
            flying = {},
            water = {},
            aq = {},
            vashj = {},
        }
    },
    profile = {
        showInChat = false,
        alwaysDifferent = true,
        safeFlying = true,
        oneClick = true,
        autoNextMount = true
    },
}

-- This variable is used for determining the ability to fly in the old world
local flightTest = 60025
-- Worgen racial
local worgenRacial = 87840
-- Druid travel forms
local druidForms = {
    travel = 783,
    aquatic = 1066,
    flight = 33943,
    swiftflight = 40120
}
-- Shaman ghost wolf form
local ghostWolf = 2645
-- Monk zen flight
local zenFlight = 125883

-- A list of all the Vashj'ir zones for reference
local vashj = { 
	[613] = true, -- Vashj'ir
	[610] = true, -- Kelp'thar Forest
	[615] = true, -- Shimmering Expanse
	[614] = true  -- Abyssal Depths
}
local SetMapToCurrentZone = SetMapToCurrentZone;

------------------------------------------------------------------
-- Property Accessors
------------------------------------------------------------------
function MountManager:GetShowInChat(info)
    return self.db.profile.showInChat
end
function MountManager:SetShowInChat(info, value)
    self.db.profile.showInChat = value
end

function MountManager:GetAlwaysDifferent(info)
    return self.db.profile.alwaysDifferent
end
function MountManager:SetAlwaysDifferent(info, value)
    self.db.profile.alwaysDifferent = value
end

function MountManager:GetSafeFlying(info)
    return self.db.profile.safeFlying
end
function MountManager:SetSafeFlying(info, value)
    self.db.profile.safeFlying = value
end

function MountManager:GetOneClick(info)
    return self.db.profile.oneClick
end
function MountManager:SetOneClick(info, value)
    self.db.profile.oneClick = value
end

function MountManager:GetAutoNextMount(info)
    return self.db.profile.autoNextMount
end
function MountManager:SetAutoNextMount(info, value)
    self.db.profile.autoNextMount = value
end

------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------
function MountManager:OnInitialize()
    -- Called when the addon is loaded
    self.db = LibStub("AceDB-3.0"):New("MountManagerDB", defaults, "Default")

    LibStub("AceConfig-3.0"):RegisterOptionsTable("MountManager", options)
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("MountManager", "MountManager")
    self:RegisterChatCommand("mountmanager", "ChatCommand")
    self:RegisterChatCommand("mm", "ChatCommand")
end

function MountManager:OnEnable()
	-- Add missing mount data (need to replace Lib with more reliable implementation)
	self:AddMissingData()

    -- Setup current character values
    self.db.char.level = UnitLevel("player")
    self.db.char.race = select(2, UnitRace("player"))
    self.db.char.class = UnitClass("player")
	local prof1, prof2 = GetProfessions()
	local name1, _, rank1 = GetProfessionInfo(prof1)
	local name2, _, rank2 = GetProfessionInfo(prof2)
	self.db.char.prof = {
		[name1] = rank1,
		[name2] = rank2
	}
    self:LEARNED_SPELL_IN_TAB()
	
    -- Track the current combat state for summoning
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    
    -- Track the current zone and player state for summoning restrictions
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")	-- new world zone
    self:RegisterEvent("ZONE_CHANGED")			-- new sub-zone
    self:RegisterEvent("ZONE_CHANGED_INDOORS")	-- new city sub-zone
    self:RegisterEvent("UPDATE_WORLD_STATES")	-- world pvp objectives updated
    self:RegisterEvent("SPELL_UPDATE_USABLE")	-- self-explanatory
    
    -- Track riding skill to determine what mounts can be used
    if self.db.char.mount_skill ~= 5 or not self.db.char.serpent then
        self:RegisterEvent("LEARNED_SPELL_IN_TAB")
    end
    
    -- Learned a new mount
    self:RegisterEvent("COMPANION_LEARNED")
    
    -- Perform an initial scan
    self:ScanForNewMounts()
    self:ZONE_CHANGED_NEW_AREA()
    
    -- Add race and class specific spells
    if self.db.char.race == "Worgen" and self.db.char.mount_skill > 0 and not self:MountExists(worgenRacial) then
        self.db.char.mounts["ground"][worgenRacial] = true;
    end
    if self.db.char.class == "Druid" then
        self:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
        self:UPDATE_SHAPESHIFT_FORMS()
    end
	if self.db.char.class == "Monk" then
		self.db.char.mounts["air"][zenFlight] = IsSpellKnown(zenFlight);
	end
    if self.db.char.class == "Shaman" and self.db.char.level > 14 then
        self.db.char.mounts["skill"][ghostWolf] = true;
    end
    
    -- Track spell cast, to generate a new mount after the current has been cast
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	
    self:RegisterEvent("ADDON_LOADED")
end

function MountManager:AddMissingData()
	M.data["ground"][130138] = true --Black Riding Goat
	M.data["ground"][130086] = true --Brown Riding Goat
	M.data["ground"][130137] = true --White Riding Goat
	
	M.data["air"][136163] = true 	--Grand Gryphon
	M.data["ground"][136163] = true --Grand Gryphon
	M.data["air"][135416] = true 	--Grand Armored Gryphon
	M.data["ground"][135416] = true --Grand Armored Gryphon
	M.data["air"][136164] = true 	--Grand Wyvern
	M.data["ground"][136164] = true --Grand Wyvern
	M.data["air"][135418] = true 	--Grand Armored Wyvern
	M.data["ground"][135418] = true --Grand Armored Wyvern
	
	M.data["air"][133023] = true 	--Jade Pandaren Kite
	M.data["air"][134573] = true 	--Swift Windsteed
	M.data["ground"][134573] = true --Swift Windsteed
end

------------------------------------------------------------------
-- Event Handling
------------------------------------------------------------------
function MountManager:ChatCommand(input)
    if input == "rescan" then
        self:Print(L["Beginning rescan..."])

        self.db.char.mounts = {
			skill = {},
            ground = {},
            flying = {},
            water = {},
            aq = {},
            vashj = {},
        }
        
        self:ScanForNewMounts()
        
        if self.db.char.race == "Worgen" and self.db.char.mount_skill > 0 then
            self.db.char.mounts["ground"][worgenRacial] = true;
        end
        if self.db.char.class == "Druid" then
            self:UPDATE_SHAPESHIFT_FORMS()
        end
		if self.db.char.class == "Monk" then
			self.db.char.mounts["air"][zenFlight] = IsSpellKnown(zenFlight);
		end
		if self.db.char.class == "Shaman" and self.db.char.level > 14 then
			self.db.char.mounts["skill"][ghostWolf] = true;
		end

        self:Print(L["Rescan complete"])
    else
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
    end
end

function MountManager:PLAYER_REGEN_DISABLED()
    state.inCombat = true
end

function MountManager:PLAYER_REGEN_ENABLED()
    state.inCombat = false
end

function MountManager:ZONE_CHANGED_NEW_AREA()
	SetMapToCurrentZone();
	state.zone = GetCurrentMapAreaID()
	
	self:UpdateZoneStatus()
end
function MountManager:UpdateZoneStatus()
    if InCombatLockdown() or state.inCombat then return end
    
    local prevSwimming = state.isSwimming
    local prevFlyable = state.isFlyable
    
    state.isSwimming = IsSwimming() or IsSubmerged()
    
    if state.zone == 501 then -- Wintergrasp
        if GetWintergraspWaitTime() then
            state.isFlyable = 1
        else  
            state.isFlyable = 0  
        end
    elseif IsFlyableArea() and (self.db.char.mount_skill > 2) and IsUsableSpell(flightTest) then
        state.isFlyable = 1
    else
        state.isFlyable = 0
    end
    
    if (prevSwimming ~= state.isSwimming) or (prevFlyable ~= state.isFlyable) then
        self:GenerateMacro()
    end
end
MountManager.ZONE_CHANGED = MountManager.UpdateZoneStatus
MountManager.ZONE_CHANGED_INDOORS = MountManager.UpdateZoneStatus
MountManager.UPDATE_WORLD_STATES = MountManager.UpdateZoneStatus
MountManager.SPELL_UPDATE_USABLE = MountManager.UpdateZoneStatus

function MountManager:LEARNED_SPELL_IN_TAB()
    if IsSpellKnown(90265) then -- Master (310 flight)
        self.db.char.mount_skill = 5
    elseif IsSpellKnown(34091) then -- Artisan (280 flight)
        self.db.char.mount_skill = 4
    elseif IsSpellKnown(34090) then -- Expert (150 flight)
        self.db.char.mount_skill = 3
    elseif IsSpellKnown(33391) then -- Journeyman (100 ground)
        self.db.char.mount_skill = 2
    elseif IsSpellKnown(33388) then -- Apprentice (60 ground)
        self.db.char.mount_skill = 1
    end
	
	if IsSpellKnown(130487) then -- Cloud Serpent Riding
		self.db.char.serpent = true
	end
	
	if self.db.char.class == "Monk" then
		self.db.char.mounts["air"][zenFlight] = IsSpellKnown(zenFlight);
	end
end

function MountManager:COMPANION_LEARNED()
    self:ScanForNewMounts()
end

function MountManager:UNIT_SPELLCAST_SUCCEEDED(event, unit, spellName)
    if self.db.profile.autoNextMount and unit == "player" and spellName == GetSpellInfo(state.mount) then
        self:GenerateMacro()
    end
end

function MountManager:UPDATE_SHAPESHIFT_FORMS()
    if IsSpellKnown(druidForms.travel) then
        self.db.char.mounts["skill"][druidForms.travel] = true
    end
    if IsSpellKnown(druidForms.aquatic) then
        self.db.char.mounts["water"][druidForms.aquatic] = true
    end
    if IsSpellKnown(druidForms.flight) then
        self.db.char.mounts["flying"][druidForms.flight] = true
    end
    if IsSpellKnown(druidForms.swiftflight) then
        self.db.char.mounts["flying"][druidForms.swiftflight] = true
    end
end

function MountManager:ADDON_LOADED(event, addon)
	if (addon == "Blizzard_PetJournal") then
		self:HijackMountFrame()
	end
end

------------------------------------------------------------------
-- Mount Methods
------------------------------------------------------------------
function MountManager:ScanForNewMounts()
    local newMounts = 0
    for id = 1,GetNumCompanions("MOUNT") do
        local mountSpellID = select(3, GetCompanionInfo("MOUNT", id))
        --make sure its not already found
        if not self:MountExists(mountSpellID) then
            newMounts = newMounts + 1

            local ground, air, water, speed, location = M:GetMountInfo(mountSpellID)

            if location then
                if location == "Temple of Ahn'Qiraj" then
                    self.db.char.mounts["aq"] = self.db.char.mounts["aq"] or {}
                    self.db.char.mounts["aq"][mountSpellID] = true
                end
                if location == "Vashj'ir" then
                    self.db.char.mounts["vashj"] = self.db.char.mounts["vashj"] or {}
                    self.db.char.mounts["vashj"][mountSpellID] = true
                end
            else
                if ground then
                    self.db.char.mounts["ground"] = self.db.char.mounts["ground"] or {}
                    self.db.char.mounts["ground"][mountSpellID] = true
                end
                if air then
                    self.db.char.mounts["flying"] = self.db.char.mounts["flying"] or {}
                    self.db.char.mounts["flying"][mountSpellID] = true
                    -- update the testing variable to a flying mount id that the player owns
                    flightTest = mountSpellID
                end
                if water then
                    self.db.char.mounts["water"] = self.db.char.mounts["water"] or {}
                    self.db.char.mounts["water"][mountSpellID] = true
                end
            end
        end
    end
    
    if newMounts > 0 then
        self:Print(string.format("|cff20ff20%s|r %s", newMounts, L["new mount(s) found!"]))
		self:UpdateMountChecks()
    end
end
function MountManager:MountExists(mountSpellID)
    for mountType, typeTable in pairs(self.db.char.mounts) do
        if typeTable[mountSpellID] ~= nil then
            return true
        end
    end
    return false
end
function MountManager:SummonMount(mount)
    for id = 1,GetNumCompanions("MOUNT") do
        local spellID = select(3, GetCompanionInfo("MOUNT", id))
        if spellID == mount then
            CallCompanion("MOUNT", id)
        end
    end
end

------------------------------------------------------------------
-- Mount Configuration
------------------------------------------------------------------
function MountManager:HijackMountFrame()
    self.companionButtons = {}

	-- verify there are mounts to track
	local numMounts = GetNumCompanions("MOUNT")
	if numMounts < 1 then
		return
	end

	local scrollFrame = MountJournal.ListScrollFrame
	local buttons = scrollFrame.buttons

	-- build out check buttons
	for idx = 1, #buttons do
		local parent = buttons[idx];
		if idx <= numMounts then
			local button = CreateFrame("CheckButton", "MountCheckButton" .. idx, parent, "UICheckButtonTemplate")
			button:SetEnabled(false)
			button:SetPoint("TOPRIGHT", 0, 0)
			button:HookScript("OnClick", function(self)
				MountManager:MountCheckButton_OnClick(self)
			end)

			self.companionButtons[idx] = button
		end
	end

	-- hook up events to update check state on scrolling
	scrollFrame:HookScript("OnMouseWheel", function(self)
		MountManager:UpdateMountChecks()
	end)
	scrollFrame:HookScript("OnVerticalScroll", function(self)
		MountManager:UpdateMountChecks()
	end)
	
	-- hook up events to update check state on search
	MountJournal.searchBox:HookScript("OnTextChanged", function(self)
		MountManager:UpdateMountChecks()
	end)

	-- force an initial update on the journal, as it's coded to only do it upon scroll or selection
	MountJournal_UpdateMountList()
	self:UpdateMountChecks()
end

function MountManager:UpdateMountChecks()
    if self.companionButtons then
		for idx, button in ipairs(self.companionButtons) do
			local parent = button:GetParent()
			if parent:IsEnabled() == 1 then
				-- Get information about the currently selected mount
				local spellID = parent.spellID
					
				-- Set the checked state based on the currently saved value
				local checked = false;
				for mountType, typeTable in pairs(self.db.char.mounts) do
					if typeTable[spellID] ~= nil then
						checked = typeTable[spellID]
					end
				end

				button:SetEnabled(true)
				button:SetChecked(checked)
			else
				button:SetEnabled(false)
				button:SetChecked(false)
			end
		end
	end
end

function MountManager:MountCheckButton_OnClick(button)
    local spellID = button:GetParent().spellID
    
    -- Toggle the saved value for the selected mount
    for mountType, typeTable in pairs(self.db.char.mounts) do
        if typeTable[spellID] ~= nil then
            if typeTable[spellID] == true then
                typeTable[spellID] = false
            else
                typeTable[spellID] = true
            end
        end
    end
end

function MountManager:MountManagerButton_OnClick(button)
    if button == "LeftButton" then
        if IsIndoors() then return end
        
        if IsFlying() then
            if self.db.profile.safeFlying == false then
                Dismount()
            end
        else
            local speed = GetUnitSpeed("player")
            
            if IsMounted() then
                Dismount()
                if speed == 0 and self.db.profile.oneClick then
                    self:SummonMount(state.mount)
                end
            else 
                if speed == 0 then
                    self:SummonMount(state.mount)
                end    
            end
        end
    else
        self:GenerateMacro()
    end
end

------------------------------------------------------------------
-- Macro Setup
------------------------------------------------------------------
function MountManager:GenerateMacro()
    if InCombatLockdown() or state.inCombat then return end
    
    -- Create base macro for mount selection
    local index = GetMacroIndexByName("MountManager")
    if index == 0 then
        index = CreateMacro("MountManager", 1, "", 1, nil)
    end
    
    state.mount = self:GetRandomMount()
	if state.mount ~= nil then
		local name, rank, icon = GetSpellInfo(state.mount)
		icon = string.sub(icon, 17)
		
		if self.db.profile.showInChat then
			self:Print(string.format("%s |cff20ff20%s|r", L["The next selected mount is"], name))
		end
		
		EditMacro(index, "MountManager", icon, string.format("/script MountManagerButton:Click(GetMouseButtonClicked());\n#showtooltip %s", name))
	else
		self:Print(L["There is no mount available for the current character."])
	end
end

function MountManager:GetRandomMount()
    if self.db.char.mount_skill == 0 then
		return nil
	end
	
	-- Determine state order for looking for a mount
    local typeList = {}
	if vashj[state.zone] then -- in Vashj'ir
		if state.isFlyable == 1 and not IsModifierKeyDown() then
			typeList = { "flying", "vashj", "water", "ground" }
		elseif state.isSwimming == 1 then
			typeList = { "vashj", "water", "ground" }
		else
			typeList = { "ground" }
		end
	elseif state.zone == 766 then -- in AQ
		if IsModifierKeyDown() then
			typeList = { "ground" }
		elseif state.isSwimming == 1 then
			typeList = { "water", "aq", "ground" }
		else
			typeList = { "aq", "ground" }
		end
	elseif state.isSwimming == 1 then
		if state.isFlyable == 1 and not IsModifierKeyDown() then
			typeList = { "flying", "water", "ground" }
		else
			typeList = { "water", "ground" }
		end
	elseif state.isFlyable == 1 and not IsModifierKeyDown() then
		typeList = { "flying", "ground" }
	else
		typeList = { "ground" }
	end
	
	-- Cycle through the type list
	for i, type in pairs(typeList) do
		-- Make a sublist of any valid mounts of the selected type
		local mounts = {}
		for mount, active in pairs(self.db.char.mounts[type]) do
			if self.db.char.mounts[type][mount] == true and self:CheckProfession(mount) and self:CheckSerpent(mount) then
				mounts[#mounts + 1] = mount
			end
		end
		
		-- If there were any matching mounts of the current type, then proceed, otherwise move to the next type
		if #mounts > 0 then
			-- Grab a random mount from the narrowed list
			local rand = random(1, #mounts)
			local mount = mounts[rand]
			if state.mount == mount and self.db.profile.alwaysDifferent and #mounts > 1 then
				while state.mount == mount do
					rand = random(1, #mounts)
					mount = mounts[rand]
				end
			end
			return mount
		end
	end
	
	-- If this point has been reached, then no matching mount was found
	return nil
end

-- Profession restricted mounts
local profMounts = M.data["professionRestricted"]
function MountManager:CheckProfession(spell)
	if profMounts[spell] then
		local skill = GetSpellInfo(profMounts[spell][1])
		local req = profMounts[spell][2]
		if self.db.char.prof[skill] then
			return self.db.char.prof[skill] >= req
		else
			return false
		end
	end
	return true
end

-- Cloud Serpents
local serpents = {
	[113199] = true, --Jade Cloud Serpent
	[123992] = true, --Azure Cloud Serpent
	[123993] = true, --Golden Cloud Serpent
	[127154] = true, --Onyx Cloud Serpent
	[127156] = true, --Crimson Cloud Serpent
	[127170] = true, --Astral Cloud Serpent
	
	[127158] = true, --Heavenly Onyx Cloud Serpent
	[127161] = true, --Heavenly Crimson Cloud Serpent
	[127164] = true, --Heavenly Golden Cloud Serpent
	[127165] = true, --Heavenly Jade Cloud Serpent
	[127169] = true, --Heavenly Azure Cloud Serpent
	
	[124408] = true, --Thundering Jade Cloud Serpent
	[129918] = true, --Thundering August Cloud Serpent
	[132036] = true, --Thundering Ruby Cloud Serpent
}
function MountManager:CheckSerpent(spell)
	if serpents[spell] then
		return self.db.char.serpent
	end
	return true
end