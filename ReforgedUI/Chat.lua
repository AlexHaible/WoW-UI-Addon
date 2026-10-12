-- Chat placement: in the console's left block when the screen has room for
-- it, otherwise floating above the left end of the console.

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
	for _, eb in ipairs(self.editBoxes) do
		ns:Lock(eb, function(f)
			ns:PlaceRect(f, L.chatEdit)
		end)
	end
end
