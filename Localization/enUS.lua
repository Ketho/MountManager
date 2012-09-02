local AceLocale = LibStub:GetLibrary("AceLocale-3.0")
local L = AceLocale:NewLocale("MountManager", "enUS", true)
if not L then return end

-- Configuration Screen
L["Description"] = "MountManager creates a character specific macro to summon a random mount based on your current location and any options selected. Simply add the created macro to an action bar to use."
L["Show in Chat"] = true
L["Toggles the display of the mount name in the chat window."] = true
L["Always Different"] = true
L["Always select a different mount than the previous one."] = true
L["Safe Flying"] = true
L["Toggles the ability to dismount when flying"] = true
L["One Click"] = true
L["One click will dismount you and summon the next available mount."] = true
L["Automatic Next Mount"] = true
L["Automatically determine the next available random mount after summoning the currently selected one."] = true

-- Misc
L["Beginning rescan..."] = true
L["Rescan complete"] = true
L["The next selected mount is"] = true
L["new mount(s) found!"] = true
L["new pet(s) found!"] = true