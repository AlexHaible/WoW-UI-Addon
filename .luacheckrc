std = "lua51"
max_line_length = 140
exclude_files = { "tools/", "ReforgedUI/Libs/" }
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
	"ActionButton_UpdateAction", "BreakUpLargeNumbers", "PlayerFrame", "GetGameTime", "GetInventoryItemDurability", "GetMoney",
	"MAINMENU_BUTTON", "QUESTLOG_BUTTON", "SOCIAL_BUTTON", "TIMEMANAGER_TOOLTIP_TITLE", "WORLD_MAP", "XP", "ChatFrame1", "geterrorhandler", "hooksecurefunc", "strsplit", "strtrim",
	"AMMOSLOT", "ARMOR", "BAGSLOT", "BLOCK", "BOSS", "C_Item", "C_PaperDollInfo", "C_Timer", "DAMAGE", "DURABILITY",
	"ELITE", "Enum", "FACTION_BAR_COLORS", "GetBlockChance", "GetCoinTextureString", "GetComboPoints",
	"GetInventoryItemCount", "GetInventoryItemID", "GetItemInfoInstant", "GetShieldBlock", "GetSpellBonusDamage",
	"GetSpellBonusHealing", "IsAltKeyDown", "KEYRING", "KEYRING_CONTAINER", "KeyRingButton", "LibStub", "MenuUtil",
	"PutKeyInKeyRing", "RegisterUnitWatch", "SetPortraitTexture", "TargetFrame", "ToggleAllBags", "ToggleKeyRing",
	"UnitArmor", "UnitClassification", "UnitCreatureType", "UnitDamage", "UnitExists", "UnitIsPlayer",
	"UnitIsTapDenied", "UnitRangedDamage", "UnitReaction", "tContains", "C_EditMode", "ToggleGameMenu", "MainMenuBarBackpackButton", "CharacterReagentBag0Slot",
	-- Console port (hero screen, action bars, options menu)
	"ClearCursor", "ColorPickerFrame", "ContainerFrame1", "CurveConstants", "GetCursorInfo", "GetRealmName",
	"GetShapeshiftFormID", "HasAction", "HasNewMail", "IsResting", "MiniMapMailBorder", "MiniMapTrackingFrame",
	"PaperDollFrame_GetArmorReduction", "PlaceAction", "ReloadUI", "Settings", "UISpecialFrames", "UnitAffectingCombat",
	"UnitAttackSpeed", "UnitHealthPercent", "UnitIsGroupLeader", "UnitIsPVP", "UnitIsPVPFreeForAll", "UnitPowerPercent",
	"issecretvalue", "tinsert",
}
