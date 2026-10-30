local player, x_pos, y_pos = unpack(...)
local pn = ToEnumShortString(player)

local songsPlayed = 0
local songTime = 0
local notesHit = 0

-- Use pairs here (instead of ipairs) because this player might have late-joined
-- which will result in nil entries in the Stats table, which halts ipairs.
for i,stats in pairs(SL[pn].Stages.Stats) do
	if stats then
		songsPlayed = songsPlayed + 1
		songTime = songTime + (stats.duration or 0)

		-- count per-column so jumps/hands count as more than 1 and #COMBOS doesn't inflate the total
		if stats.column_judgments then
			for column, judgments in ipairs(stats.column_judgments) do
				for judgment, judgment_count in pairs(judgments) do
					-- early hits are stored in a table; skip those
					if type(judgment_count) == "number" and judgment ~= "Miss" then
						notesHit = notesHit + judgment_count
					end
				end
			end
		end
	end
end

local sessionTime = SL.Global.TimeAtSessionStart and (GetTimeSinceStart() - SL.Global.TimeAtSessionStart) or songTime
sessionTime = math.max(sessionTime, songTime)

local songRatio = sessionTime > 0 and (songTime / sessionTime) or 0

local FormatTime = function(seconds)
	local hours = math.floor(seconds/3600)
	local minutes = math.floor((seconds % 3600)/60)
	if hours > 0 then
		return ("%d%s %d%s"):format(hours, ScreenString("HoursShort"), minutes, ScreenString("MinutesShort"))
	end
	return ("%d%s"):format(minutes, ScreenString("MinutesShort"))
end

local FormatCount = function(n)
	if n >= 1000 then return ("%.1fk"):format(n/1000) end
	return ("%d"):format(n)
end

local NotesPerHour = function(seconds)
	if seconds <= 0 then return "0" end
	return FormatCount(math.floor(notesHit / (seconds/3600) + 0.5))
end

-- -----------------------------------------------------------------------

local panel_w = 150
local icon_size = 18
local bar_w = 130
local bar_h = 20

local af = Def.ActorFrame{
	InitCommand=function(self) self:xy(x_pos, y_pos) end,
}

local AddIcon = function(emoji, x, y)
	af[#af+1] = LoadFont("Common Normal")..{
		Text=emoji,
		InitCommand=function(self) self:xy(x, y):zoom(icon_size/16) end
	}
end

local AddText = function(text, x, y, zoom, halign)
	af[#af+1] = LoadFont("Common Normal")..{
		Text=text,
		InitCommand=function(self)
			self:xy(x, y):zoom(zoom):halign(halign or 0.5):maxwidth(panel_w/zoom):diffuse(PlayerColor(player))
		end
	}
end

AddText(ScreenString("ThisSession"), 0, 14, 0.95)

local rows = {
	{ "💿", ("%d %s"):format(songsPlayed, ScreenString(songsPlayed == 1 and "SongSingular" or "SongPlural")) },
	{ "👟", ("%s %s"):format(FormatCount(notesHit), ScreenString("Steps")) },
	{ "⏱", FormatTime(sessionTime) },
}
for i,row in ipairs(rows) do
	local y = 20 + i*22
	AddIcon(row[1], -bar_w/2 + icon_size/2, y)
	AddText(row[2], -bar_w/2 + icon_size + 8, y, 0.9, 0)
end

-- session bar: the whole width is the session, the fill is time spent in songs
local bar_y = 112

af[#af+1] = Def.Quad{
	InitCommand=function(self) self:y(bar_y):zoomto(bar_w + 2, bar_h + 2):diffuse(color("#000000aa")) end
}
af[#af+1] = Def.Quad{
	InitCommand=function(self) self:y(bar_y):zoomto(bar_w, bar_h):diffuse(color("#ffffff22")) end
}
af[#af+1] = Def.Quad{
	InitCommand=function(self)
		self:halign(0):xy(-bar_w/2, bar_y):zoomto(0, bar_h):diffuse(PlayerColor(player))
	end,
	OnCommand=function(self)
		self:sleep(0.75):decelerate(1):zoomto(bar_w * songRatio, bar_h)
	end
}
af[#af+1] = LoadFont("Common Normal")..{
	Text=("%s (%d%%)"):format(FormatTime(songTime), math.floor(songRatio*100 + 0.5)),
	InitCommand=function(self)
		self:halign(0):xy(-bar_w/2 + 5, bar_y):zoom(0.8):maxwidth((bar_w - 10)/0.8):shadowlength(1)
	end
}

AddText(ScreenString("NotesPerHour"), 0, 136, 0.85)

local columns = {
	{ "⏱", NotesPerHour(sessionTime), -bar_w/4 },
	{ "💿", NotesPerHour(songTime),  bar_w/4 },
}
for column in ivalues(columns) do
	AddIcon(column[1], column[3], 153)
	AddText(column[2], column[3], 170, 0.85)
end

return af
