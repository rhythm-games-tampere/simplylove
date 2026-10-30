local player, x_pos, y_pos = unpack(...)

local stats = SessionDataForStatistics(player)
local songsPlayed = stats.songsPlayedThisGame
local songTime = stats.totalTime
local sessionTime = stats.sessionTime
local notesHit = stats.notesHitThisGame

local songRatio = sessionTime > 0 and (songTime / sessionTime) or 0

local Format = LoadActor("./Formatters.lua")

-- under a minute of play the rate isn't meaningful, so it's not shown
local NotesPerMinute = function(seconds)
	if seconds < 60 then return "-" end
	return Format.Count(math.floor(notesHit / (seconds/60) + 0.5))
end

-- -----------------------------------------------------------------------

local panel_w = 150
local icon_size = 18
local bar_w = 130
local bar_h = 22

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

AddText(ScreenString("ThisSession"), 0, 18, 0.95)

local rows = {
	{ "💿", ("%d %s"):format(songsPlayed, ScreenString(songsPlayed == 1 and "SongSingular" or "SongPlural")) },
	{ "👟", ("%s %s"):format(Format.Count(notesHit), ScreenString("Steps")) },
	{ "⏱", Format.Time(sessionTime) },
}
for i,row in ipairs(rows) do
	local y = 20 + i*28
	AddIcon(row[1], -bar_w/2 + icon_size/2, y)
	AddText(row[2], -bar_w/2 + icon_size + 8, y, 0.9, 0)
end

-- session bar: the whole width is the session, the fill is time spent in songs
local bar_y = 138

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
	Text=("%s (%d%%)"):format(Format.Time(songTime), math.floor(songRatio*100 + 0.5)),
	InitCommand=function(self)
		self:halign(0):xy(-bar_w/2 + 5, bar_y):zoom(0.8):maxwidth((bar_w - 10)/0.8):shadowlength(1)
	end
}

-- session time is never shorter than song time, so this hides the whole block
if sessionTime >= 60 then
	AddText(ScreenString("NotesPerMinute"), 0, 172, 0.85)

	local columns = {
		{ "⏱", NotesPerMinute(sessionTime), -bar_w/4 },
		{ "💿", NotesPerMinute(songTime),     bar_w/4 },
	}
	for column in ivalues(columns) do
		AddIcon(column[1], column[3], 194)
		AddText(column[2], column[3], 214, 0.85)
	end
end

return af
