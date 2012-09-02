local L = LibStub("AceLocale-3.0"):NewLocale("MountManager", "L", true)

-- Configuration Screen
L["Name"] = "MountManager"
L["Description"] = "Description here..."
L["Enable Chat"] = "Show in Chat"
L["Enable Chat Desc"] = "Toggles the display of the mount name in the chat window."
L["Always Different"] = "Always Different"
L["Always Different Desc"] = "Always select a different mount than the previous one."
L["Safe Flying"] = "Safe Flying"
L["Safe Flying Desc"] = "Toggles the ability to dismount when flying"
L["One Click"] = "One Click"
L["One Click Desc"] = "One click will dismount you and summon the next available mount."
L["Auto Next Mount"] = "Automatic Next Mount"
L["Auto Next Mount Desc"] = "Automatically determine the next available random mount after summoning the currently selected one."

-- Misc
L["RescanStart"] = "Beginning rescan..."
L["RescanEnd"] = "Rescan complete"
L["ChatFormat"] = "The next selected mount is |cff20ff20%s|r"
L["NewMountsFormat"] = "|cff20ff20%s|r new mount(s) found!"
L["NewPetsFormat"] = "|cff20ff20%s|r new pet(s) found!"

-- Macro
L["MacroFormat"] = "/script MountManagerButton:Click(GetMouseButtonClicked());\n#showtooltip %s"