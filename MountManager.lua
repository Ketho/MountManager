MountManager = LibStub("AceAddon-3.0"):NewAddon("MountManager", "AceConsole-3.0", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("MountManager")
local Z = LibStub("LibBabble-Zone-3.0"):GetLookupTable()

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
        mount_skill = 0,
        mounts = {
            ground = {},
            flying = {},
            water = {},
            aq = {},
            vashj = {},
        },
        pets = {}
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
    
    -- Setup current character values
    self.db.char.level = UnitLevel("player")
    self.db.char.race = select(2, UnitRace("player"))
    self.db.char.class = UnitClass("player")
    self:ACHIEVEMENT_EARNED()
end

function MountManager:OnEnable()
    -- Track the current combat state for summoning
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    
    -- Track the current zone and player state for summoning restrictions
    self:RegisterEvent("ZONE_CHANGED")
    self:RegisterEvent("ZONE_CHANGED_INDOORS")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("UPDATE_WORLD_STATES")
    self:RegisterEvent("SPELL_UPDATE_USABLE")
    
    -- Track riding skill to determine what mounts can be used
    if self.db.char.mount_skill ~= 4 then
        self:RegisterEvent("ACHIEVEMENT_EARNED")
    end
    
    -- Learned a new mount or pet
    self:RegisterEvent("COMPANION_LEARNED")
    
    -- Perform an initial scan
    self:ScanForNewMounts()
    self:ScanForNewPets()
    self:ZONE_CHANGED()
    
    -- Add race and class specific spells
    if self.db.char.race == "Worgen" and self.db.char.mount_skill > 0 and not self:MountExists(worgenRacial) then
        self.db.char.mounts["ground"][worgenRacial] = true;
    end
    if self.db.char.class == "DRUID" then
        self:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
        self:UPDATE_SHAPESHIFT_FORMS()
    end
    
    -- Track spell cast, to generate a new mount after the current has been cast
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	
    self:RegisterEvent("ADDON_LOADED")
end

------------------------------------------------------------------
-- Event Handling
------------------------------------------------------------------
function MountManager:ChatCommand(input)
    if input == "rescan" then
        self:Print(L["Beginning rescan..."])

        self.db.char.mounts = {
            ground = {},
            flying = {},
            water = {},
            aq = {},
            vashj = {},
        }
        self.db.char.pets = {}
        
        self:ScanForNewMounts()
        self:ScanForNewPets()
        
        if self.db.char.race == "Worgen" and self.db.char.mount_skill > 0 then
            self.db.char.mounts["ground"][worgenRacial] = true;
        end
        if self.db.char.class == "DRUID" then
            self:UPDATE_SHAPESHIFT_FORMS()
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

function MountManager:ZONE_CHANGED()
    if InCombatLockdown() or state.inCombat then return end
    
    local prevSwimming = state.isSwimming
    local prevFlyable = state.isFlyable
    
    state.isSwimming = IsSwimming()
    
    state.zone = GetRealZoneText()
    if state.zone == Z["Wintergrasp"] then
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
MountManager.ZONE_CHANGED_INDOORS = MountManager.ZONE_CHANGED
MountManager.ZONE_CHANGED_NEW_AREA = MountManager.ZONE_CHANGED
MountManager.UPDATE_WORLD_STATES = MountManager.ZONE_CHANGED
MountManager.SPELL_UPDATE_USABLE = MountManager.ZONE_CHANGED

function MountManager:ACHIEVEMENT_EARNED()
    if select(4, GetAchievementInfo(892)) then -- Fast Flight
        self.db.char.mount_skill = 4
        self:UnregisterEvent("ACHIEVEMENT_EARNED")
    elseif select(4, GetAchievementInfo(890)) then -- Slow Flight
        self.db.char.mount_skill = 3
    elseif select(4, GetAchievementInfo(889)) then -- Fast Ground
        self.db.char.mount_skill = 2
    elseif select(4, GetAchievementInfo(891)) then -- Slow Ground
        self.db.char.mount_skill = 1
    end
end

function MountManager:COMPANION_LEARNED()
    self:ScanForNewMounts()
    self:ScanForNewPets()
end

function MountManager:UNIT_SPELLCAST_SUCCEEDED(event, unit, spellName)
    if self.db.profile.autoNextMount and unit == "player" and spellName == GetSpellInfo(state.mount) then
        self:GenerateMacro()
    end
end

function MountManager:UPDATE_SHAPESHIFT_FORMS()
    if not self:MountExists(druidForms.travel) and IsSpellKnown(druidForms.travel) then
        self.db.char.mounts["ground"][druidForms.travel] = true
    end
    if not self:MountExists(druidForms.aquatic) and IsSpellKnown(druidForms.aquatic) then
        self.db.char.mounts["water"][druidForms.aquatic] = true
    end
    if not self:MountExists(druidForms.flight) and IsSpellKnown(druidForms.flight) then
        self.db.char.mounts["flying"][druidForms.flight] = true
    end
    if not self:MountExists(druidForms.swiftflight) and IsSpellKnown(druidForms.swiftflight) then
        self.db.char.mounts["flying"][druidForms.flight] = false
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

            local ground, air, water, speed, location = LibStub("LibMounts-1.0"):GetMountInfo(mountSpellID)

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
-- Pet Methods
------------------------------------------------------------------
function MountManager:ScanForNewPets()
    local newPets = 0
    for id = 1,GetNumCompanions("CRITTER") do
        local petSpellID = select(3, GetCompanionInfo("CRITTER", id))
        --make sure its not already found
        if not self:PetExists(petSpellID) then
            newPets = newPets + 1

            self.db.char.pets[petSpellID] = true
        end
    end
    if newPets > 0 then
        self:Print(string.format("|cff20ff20%s|r %s", newPets, L["new pet(s) found!"]))
    end
end
function MountManager:PetExists(petSpellID)
    if self.db.char.pets[petSpellID] ~= nil then
        return true
    end
    return false
end
function MountManager:SummonPet(pet)
    for id = 1,GetNumCompanions("CRITTER") do
        local spellID = select(3, GetCompanionInfo("CRITTER", id))
        if spellID == pet then
            CallCompanion("CRITTER", id)
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

				button:SetChecked(checked)
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
    local name, rank, icon = GetSpellInfo(state.mount)
    icon = string.sub(icon, 17)
    
    if self.db.profile.showInChat then
        self:Print(string.format("%s |cff20ff20%s|r", L["The next selected mount is"], name))
    end
    
    EditMacro(index, "MountManager", icon, string.format("/script MountManagerButton:Click(GetMouseButtonClicked());\n#showtooltip %s", name))
end

function MountManager:GetRandomMount()
    local type = "ground"
    
    local vash = { Z["Vashj'ir"], Z["Kelp'thar Forest"], Z["Shimmering Expanse"], Z["Abyssal Depths"], }
    
    -- Determine what type to use
    if state.isSwimming == 1 then
        type = "water"
        
        local present = false
        for mount, active in pairs(self.db.char.mounts["vashj"]) do
            if self.db.char.mounts["vashj"][mount] == true then
                present = true
            end
        end
        if present then
            for i, value in pairs(vash) do
                if state.zone == value then
                    type = "vashj"
                end
            end
        end
    elseif state.zone == Z["Temple of Ahn'Qiraj"] then
        type = "aq"
    elseif state.isFlyable == 1 and not IsModifierKeyDown() then
        type = "flying"
    end
    
    -- Narrow down the list to the available mounts of the selected type
    local mounts = {}
    for mount, active in pairs(self.db.char.mounts[type]) do
        if self.db.char.mounts[type][mount] == true then
            mounts[#mounts + 1] = mount
        end
    end
    
    -- Grab a random mount from the narrowed list
    local rand = random(1, #mounts)
    local mount = mounts[rand]
    if self.db.profile.alwaysDifferent == true and #mounts > 1 then
        while state.mount == mount do
            rand = random(1, #mounts)
            mount = mounts[rand]
        end
    end
    return mount
end