-- The game's calendar: what is on now and in the coming week, read from
-- C_Calendar, as a feed ("Reforged: Calendar") for the top bar's slots and
-- any other LibDataBroker display, and the state of the calendar button on
-- the minimap (Minimap.lua makes it; here it gets today's date and the
-- invitation badge). A click on either opens the calendar.
--
-- Times are the realm's, like the calendar's own. Raid lockouts and resets
-- are left out, and so are events the player declined.

local _, ns = ...
local Calendar = ns:RegisterModule("calendar", {})
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)

local FEED = "Reforged: Calendar"
Calendar.FEED = FEED
local ICON = "Interface\\Icons\\INV_Misc_Note_01"
Calendar.ICON = ICON
-- How many days ahead the feed looks (the calendar keeps the next month's
-- events loaded, so a week is always there).
local DAYS_AHEAD = 7
-- Lines of events in the tooltip, at most.
local MAX_LINES = 12
-- Player and guild events have no end of their own: count them as on for
-- this long after they start.
local EVENT_MINUTES = 60
-- The feed's text goes stale as time passes ("in 40 min"): refresh it this
-- often, in seconds.
local REFRESH = 30

local SKIP_TYPES = { RAID_LOCKOUT = true, RAID_RESET = true }
local HOLIDAY_TYPES = { HOLIDAY = true }
-- Events the player can be invited to.
local INVITE_TYPES = { PLAYER = true, GUILD_EVENT = true, COMMUNITY_EVENT = true }
-- Enum.CalendarStatus's values, should the client lack the table.
local STATUS = { Invited = 0, Declined = 2, Out = 4 }
local function status(key)
	local t = Enum and Enum.CalendarStatus
	return t and t[key] or STATUS[key]
end
local WEEKDAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local INVITE_COLOR = "|cffff9933"

local floor = math.floor

----------------------------------------------------------------------------
-- Dates as day numbers (days since 1 January 1970), so the coming week can
-- run across a month's end and times can be compared. Howard Hinnant's
-- civil calendar algorithms.

local function daysFromCivil(y, m, d)
	if m <= 2 then
		y = y - 1
	end
	local era = floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

local function civilFromDays(z)
	z = z + 719468
	local era = floor(z / 146097)
	local doe = z - era * 146097
	local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
	local mp = floor((5 * doy + 2) / 153)
	local d = doy - floor((153 * mp + 2) / 5) + 1
	local m = mp < 10 and mp + 3 or mp - 9
	if m <= 2 then
		y = y + 1
	end
	return y, m, d
end
Calendar.DaysFromCivil, Calendar.CivilFromDays = daysFromCivil, civilFromDays

-- A CalendarTime as minutes since 1970 (realm time).
local function stamp(t)
	return daysFromCivil(t.year, t.month, t.monthDay) * 1440 + (t.hour or 0) * 60 + (t.minute or 0)
end

----------------------------------------------------------------------------
-- Reading the calendar

-- False when this client (or this game's rules) has no in-game calendar.
function Calendar:Available()
	if not (C_Calendar and C_Calendar.GetNumDayEvents and C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime) then
		return false
	end
	local rules, rule = C_GameRules, Enum and Enum.GameRule and Enum.GameRule.IngameCalendarDisabled
	if rules and rules.IsGameRuleActive and rule then
		local ok, off = pcall(rules.IsGameRuleActive, rule)
		if ok and off then
			return false
		end
	end
	return true
end

function Calendar:PendingInvites()
	local get = C_Calendar and C_Calendar.GetNumPendingInvites
	local ok, n = pcall(get or error)
	return ok and type(n) == "number" and n or 0
end

-- Now, as minutes since 1970 and the day number.
local function now()
	local t = C_DateAndTime.GetCurrentCalendarTime()
	return stamp(t), daysFromCivil(t.year, t.month, t.monthDay)
end

-- An event worth listing: not a raid lockout or reset, not declined.
local function wanted(e)
	if type(e) ~= "table" or type(e.title) ~= "string" or e.title == "" or SKIP_TYPES[e.calendarType] then
		return false
	end
	if e.inviteStatus == status("Declined") or e.inviteStatus == status("Out") then
		return false
	end
	return type(e.startTime) == "table" and type(e.endTime) == "table"
end

-- The events from today to DAYS_AHEAD days on that have not ended: those on
-- now first (ending soonest first), then the rest by start. Each is
-- { title, start, finish, holiday, open (no end shown), invite (waiting for
-- an answer) }, times in minutes since 1970. Holidays come once, however
-- many days they span.
function Calendar:Events()
	local list = {}
	if not self:Available() then
		return list
	end
	local ok, err = pcall(function()
		local nowStamp, today = now()
		-- Day events are read by month offset from the month the calendar is
		-- showing, which its window may have moved.
		local view = C_Calendar.GetMonthInfo(0)
		local seen = {}
		for d = 0, DAYS_AHEAD do
			local y, m, day = civilFromDays(today + d)
			local offset = (y - view.year) * 12 + m - view.month
			for i = 1, C_Calendar.GetNumDayEvents(offset, day) or 0 do
				local e = C_Calendar.GetDayEvent(offset, day, i)
				if wanted(e) then
					local start, finish = stamp(e.startTime), stamp(e.endTime)
					local holiday = HOLIDAY_TYPES[e.calendarType] or false
					local key = ("%s:%s:%s:%d"):format(e.calendarType, tostring(e.eventID), e.title, start)
					if finish <= start then
						finish = start + (holiday and 1440 or EVENT_MINUTES)
					end
					if not seen[key] and finish > nowStamp then
						seen[key] = true
						list[#list + 1] = {
							title = e.title, start = start, finish = finish, holiday = holiday,
							open = e.dontDisplayEnd and true or false,
							invite = INVITE_TYPES[e.calendarType] and e.inviteStatus == status("Invited") or false,
						}
					end
				end
			end
		end
		table.sort(list, function(a, b)
			local aNow, bNow = a.start <= nowStamp, b.start <= nowStamp
			if aNow ~= bNow then
				return aNow
			end
			if aNow then
				if a.finish ~= b.finish then
					return a.finish < b.finish
				end
			elseif a.start ~= b.start then
				return a.start < b.start
			end
			return a.title < b.title
		end)
	end)
	if not ok then
		self.lastError = err
		return {}
	end
	return list
end

----------------------------------------------------------------------------
-- Words

local function clock(minutes)
	local topbar = ns.modules.topbar
	local hours = topbar and topbar.TimeHours and topbar:TimeHours() or 24
	local h, m = floor(minutes / 60) % 24, minutes % 60
	if topbar and topbar.FormatTime then
		return topbar.FormatTime(h, m, hours)
	end
	return ("%02d:%02d"):format(h, m)
end

-- "Today", "Tomorrow" or "Fri" within the week, "14 Nov" after it.
local function dayName(minutes, today)
	local day = floor(minutes / 1440)
	if day == today then
		return "Today"
	elseif day == today + 1 then
		return "Tomorrow"
	elseif day > today and day < today + 7 then
		return WEEKDAYS[(day + 4) % 7 + 1]
	end
	local _, m, d = civilFromDays(day)
	return ("%d %s"):format(d, MONTHS[m])
end

-- "in 40 min", "in 3 h" (under a day away), else nil.
local function soon(minutes, nowStamp)
	local left = minutes - nowStamp
	if left < 60 then
		return ("in %d min"):format(math.max(1, left))
	elseif left < 1440 then
		return ("in %d h"):format(floor(left / 60 + 0.5))
	end
end

function Calendar:InviteText(n)
	return ("%d invitation%s"):format(n, n == 1 and "" or "s")
end

-- The feed's text: what is on now (and how many more), or else the next
-- event and when; invitations waiting go first.
function Calendar:FeedText(events)
	if not self:Available() then
		return "No calendar"
	end
	events = events or self:Events()
	local nowStamp, today = now()
	local text
	local first = events[1]
	if not first then
		text = "No events"
	elseif first.start <= nowStamp then
		local more = 0
		for i = 2, #events do
			if events[i].start <= nowStamp then
				more = more + 1
			end
		end
		text = more > 0 and ("%s +%d"):format(first.title, more) or first.title
	else
		local when = soon(first.start, nowStamp)
		if not when then
			when = dayName(first.start, today)
			if not first.holiday then
				when = when .. " " .. clock(first.start)
			end
		end
		text = ("%s %s"):format(first.title, when)
	end
	local pending = self:PendingInvites()
	if pending > 0 then
		text = ("%s%s|r  %s"):format(INVITE_COLOR, self:InviteText(pending), text)
	end
	return text
end

-- When an event is, for the tooltip: on now, until when it ends; later, when
-- it starts.
local function whenText(e, nowStamp, today)
	if e.start <= nowStamp then
		if e.open then
			return "On now"
		end
		local ends = e.finish
		if e.holiday then
			-- Holidays end at a time on their last day; the day is enough
			-- unless that is today.
			if floor(ends / 1440) == today then
				return "until " .. clock(ends)
			end
			return "until " .. dayName(ends, today)
		end
		return "until " .. clock(ends)
	end
	local day = dayName(e.start, today)
	if floor(e.start / 1440) == today or not e.holiday then
		return day .. " " .. clock(e.start)
	end
	return day
end

function Calendar:Tooltip(tip)
	tip:AddLine("Calendar", 1, 1, 1)
	if not self:Available() then
		tip:AddLine("This game has no calendar.", 0.8, 0.8, 0.8)
		return
	end
	local events = self:Events()
	local nowStamp, today = now()
	local pending = self:PendingInvites()
	if pending > 0 then
		tip:AddLine(self:InviteText(pending) .. " waiting for an answer", 1, 0.6, 0.2)
	end
	local heading
	for i, e in ipairs(events) do
		if i > MAX_LINES then
			tip:AddLine(("and %d more"):format(#events - MAX_LINES), 0.6, 0.6, 0.6)
			break
		end
		local section = e.start <= nowStamp and "Now" or "Coming up"
		if section ~= heading then
			heading = section
			tip:AddLine(" ")
			tip:AddLine(section, 1, 0.82, 0)
		end
		local r, g, b = 1, 1, 1
		if e.invite then
			r, g, b = 1, 0.6, 0.2
		elseif e.holiday then
			r, g, b = 0.6, 0.9, 1
		end
		tip:AddDoubleLine(e.title, whenText(e, nowStamp, today), r, g, b, 0.8, 0.8, 0.8)
	end
	if #events == 0 then
		tip:AddLine(" ")
		tip:AddLine("Nothing on the calendar this week.", 0.8, 0.8, 0.8)
	end
	tip:AddLine(" ")
	tip:AddLine("Click to open the calendar.", 0.6, 0.6, 0.6)
end

----------------------------------------------------------------------------
-- Opening the calendar

function Calendar:Open()
	if not self:Available() then
		return
	end
	-- Blizzard's calendar button: with invitations waiting it opens (rather
	-- than toggles) the calendar.
	local pending = self:PendingInvites()
	local shown = CalendarFrame and CalendarFrame:IsShown()
	if pending > 0 and not shown and Calendar_LoadUI and Calendar_LoadUI() and Calendar_Show then
		Calendar_Show()
	elseif ToggleCalendar then
		ToggleCalendar()
	end
	self.seenInvites = pending
	self:Update()
end

----------------------------------------------------------------------------
-- The button (made by Minimap.lua): today's date, and a letter while
-- invitations wait, pulsing until the calendar has been opened.

local PULSE = 2 -- seconds per pulse, like Blizzard's

local function pulse(b, dt)
	b.pulseTime = ((b.pulseTime or 0) + dt) % PULSE
	local a = 0.5 + 0.5 * math.cos(2 * math.pi * b.pulseTime / PULSE)
	b.glow:SetAlpha(a)
end

function Calendar:SetButton(b)
	self.button = b
	self:Update()
end

function Calendar:UpdateButton()
	local b = self.button
	if not b then
		return
	end
	local ok, t = pcall(C_DateAndTime.GetCurrentCalendarTime)
	b.day:SetText(ok and type(t) == "table" and t.monthDay or "")
	local pending = self:PendingInvites()
	if pending == 0 then
		self.seenInvites = 0
	end
	b.invite:SetShown(pending > 0)
	local flash = pending > (self.seenInvites or 0)
	b.glow:SetShown(flash)
	if flash and not b:GetScript("OnUpdate") then
		b:SetScript("OnUpdate", pulse)
	elseif not flash and b:GetScript("OnUpdate") then
		b:SetScript("OnUpdate", nil)
	end
end

----------------------------------------------------------------------------

function Calendar:Update()
	if self.feed then
		self.feed.text = self:FeedText()
	end
	self:UpdateButton()
end

-- Ask the server for the calendar's events (they arrive with
-- CALENDAR_UPDATE_EVENT_LIST).
function Calendar:Request()
	if self:Available() and C_Calendar.OpenCalendar then
		pcall(C_Calendar.OpenCalendar)
	end
end

function Calendar:OnEnable()
	if LDB then
		self.feed = LDB:NewDataObject(FEED, {
			type = "data source", label = "Calendar", text = "", icon = ICON,
			OnClick = function() Calendar:Open() end,
			OnTooltipShow = function(tip) Calendar:Tooltip(tip) end,
		})
	end
	local update = ns:Throttle(function() self:Update() end, 0.2)
	for _, e in ipairs({ "CALENDAR_UPDATE_EVENT_LIST", "CALENDAR_UPDATE_PENDING_INVITES", "CALENDAR_NEW_EVENT",
		"CALENDAR_UPDATE_EVENT", "CALENDAR_UPDATE_INVITE_LIST", "PLAYER_ENTERING_WORLD" }) do
		ns:On(e, update)
	end
	local requested
	ns:On("PLAYER_ENTERING_WORLD", function()
		if not requested then
			requested = true
			self:Request()
		end
	end)
	local elapsed = 0
	self.ticker = CreateFrame("Frame")
	self.ticker:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= REFRESH then
			elapsed = 0
			self:Update()
		end
	end)
	self:Request()
	self:Update()
end
