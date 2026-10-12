-- Chat placement: inside the console on 21:9 and 32:9, floating above the
-- minimap block on 16:9 (where Warcraft III shows its messages).

local _, ns = ...
local Chat = ns:RegisterModule("chat", {})

function Chat:OnEnable()
	self.frame = ChatFrame1
	self.editBoxes = {}
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local eb = _G["ChatFrame" .. i .. "EditBox"]
		if eb then
			self.editBoxes[#self.editBoxes + 1] = eb
		end
	end
end

function Chat:OnLayout(L)
	local cf = self.frame
	if not cf then
		return
	end
	ns:Lock(cf, function(f)
		ns:PlaceRect(f, L.chat)
	end)
	if FCF_SavePositionAndDimensions then
		FCF_SavePositionAndDimensions(cf)
	end
	for _, eb in ipairs(self.editBoxes) do
		ns:Lock(eb, function(f)
			ns:PlaceRect(f, L.chatEdit)
		end)
	end
end
