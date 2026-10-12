std = "lua51"
max_line_length = 140
exclude_files = { "tools/" }
ignore = {
	"212", -- unused argument (event handlers)
}
globals = {
	"ReforgedUIDB", "SlashCmdList", "SLASH_REFORGEDUI1", "SLASH_REFORGEDUI2", "GetMinimapShape",
}
read_globals = {
	-- WoW API and frames (Retail and Classic-based clients)
	"AddonCompartmentFrame", "BACKPACK_TOOLTIP", "C_Container", "C_PvP", "ClearOverrideBindings",
	"ContainerFrameCombinedBags", "ContainerIDToInventoryID", "CreateColor", "CreateFrame",
	"EQUIP_CONTAINER", "ExpansionLandingPageMinimapButton", "FCF_SavePositionAndDimensions",
	"GameTimeFrame", "GameTooltip", "GameTooltip_Hide", "GameTooltip_SetDefaultAnchor",
	"GarrisonLandingPageMinimapButton", "GetBindingKey", "GetContainerNumFreeSlots", "GetContainerNumSlots",
	"GetInventoryItemTexture", "GetMaxPlayerLevel", "GetMinimapZoneText", "GetXPExhaustion",
	"GetZonePVPInfo", "IsPlayerAtEffectiveMaxLevel", "InCombatLockdown", "LEVEL", "MAX_PLAYER_LEVEL_TEXT",
	"MiniMapInstanceDifficulty", "MiniMapMailFrame", "MiniMapTracking", "MiniMapTrackingButton",
	"MiniMapWorldMapButton", "Minimap", "MinimapBackdrop", "MinimapBorder", "MinimapBorderTop",
	"MinimapCluster", "MinimapCompassTexture", "MinimapZoneTextButton", "MinimapZoomIn", "MinimapZoomOut",
	"NUM_CHAT_WINDOWS", "NUM_CONTAINER_FRAMES", "PickupBagFromSlot", "PowerBarColor", "PutItemInBackpack",
	"PutItemInBag", "RAID_CLASS_COLORS", "RegisterStateDriver", "SetOverrideBindingClick",
	"TimeManagerClockButton", "ToggleBackpack", "ToggleBag", "UIParent", "UnitClass", "UnitFactionGroup",
	"UnitHealth", "UnitHealthMax", "UnitLevel", "UnitName", "UnitPower", "UnitPowerMax", "UnitPowerType",
	"UnitRace", "UnitXP", "UnitXPMax", "UpdateContainerFrameAnchors", "updateContainerFrameAnchors",
	"ActionButton_UpdateAction", "BreakUpLargeNumbers", "GetGameTime", "GetInventoryItemDurability", "GetMoney",
	"MAINMENU_BUTTON", "QUESTLOG_BUTTON", "SOCIAL_BUTTON", "TIMEMANAGER_TOOLTIP_TITLE", "WORLD_MAP", "XP", "ChatFrame1", "geterrorhandler", "hooksecurefunc", "strsplit", "strtrim",
}
