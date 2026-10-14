-- The original addon's chat area: the main chat window fills the black area at the
-- right end of the console, with its input box under (or above) it. The chat
-- buttons beside the window can be hidden ("Hide chat icons"), and the window
-- can be let go so the player can move and resize it.

local _, ns = ...
local Chat = ns:RegisterModule("chat", {})

local ICON_FRAMES = {
	"ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton",
	"ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
}

function Chat:OnEnable()
	self.frame = ChatFrame1
	self.editBoxes = {}
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local eb = _G["ChatFrame" .. i .. "EditBox"]
		if eb then
			self.editBoxes[#self.editBoxes + 1] = eb
		end
	end

	if ns.db.consoleOpts.hideChatIcons then
		for _, name in ipairs(ICON_FRAMES) do
			ns:Conceal(_G[name])
		end
		for i = 1, (NUM_CHAT_WINDOWS or 10) do
			local cf = _G["ChatFrame" .. i]
			if cf then
				ns:Conceal(cf.ButtonFrame or _G["ChatFrame" .. i .. "ButtonFrame"])
				ns:Conceal(cf.ScrollToBottomButton)
			end
		end
	end
end

function Chat:OnLayout(L)
	local cf = self.frame
	if not cf then
		return
	end
	-- "Let me move and resize the chat window": placed in the chat area
	-- once, then left where the player (or Edit Mode) puts it; the input
	-- boxes follow their windows as Blizzard anchors them.
	if ns.db.consoleOpts.freeChat then
		ns:Unlock(cf)
		local above = ns.db.consoleOpts.chatInputAbove
		for _, eb in ipairs(self.editBoxes) do
			ns:Unlock(eb)
			-- Back on its own window, under it (or above), as Blizzard has it.
			local owner = eb.chatFrame or _G[(eb:GetName() or ""):gsub("EditBox$", "")]
			if owner then
				eb:ClearAllPoints()
				if above then
					eb:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", -5, 2)
					eb:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 5, 2)
				else
					eb:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", -5, -2)
					eb:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 5, -2)
				end
			end
		end
		if not ns.db.consoleOpts.chatPlaced then
			ns.db.consoleOpts.chatPlaced = true
			ns:PlaceRect(cf, L.chat)
		end
		if cf.SetMovable then
			cf:SetMovable(true)
			cf:SetResizable(true)
		end
		return
	end
	ns:Lock(cf, function(f)
		ns:PlaceRect(f, L.chat)
	end)
	for _, eb in ipairs(self.editBoxes) do
		ns:Lock(eb, function(f)
			ns:PlaceRect(f, L.chatEdit)
		end)
	end
	-- The social (quick join) button sits on the wall above the chat
	-- buttons rather than up in the game world.
	local column = cf.ButtonFrame or _G.ChatFrame1ButtonFrame
	local social = _G.QuickJoinToastButton
	if social and column and not ns.db.consoleOpts.hideChatIcons then
		ns:Lock(social, function(f)
			f:ClearAllPoints()
			f:SetPoint("BOTTOMLEFT", column, "TOPLEFT", 0, 2)
		end)
	end
end
