-- Song wheel golf score: AC best strokes vs par
local player = ...
local pn = ToEnumShortString(player)
local white = color("#ffffff")

-- match golf.arrowcloud.dance scorecard colours
local golf_colors = {
	[-3] = color("#b37bff"), [-2] = color("#2da6fa"), [-1] = color("#29e16f"), [0] = white,
	[1] = color("#fd9320"), [2] = color("#fc4447"), [3] = color("#de667a"),
}

local function Draw(self, song, steps)
	if SL[pn].ArrowCloudApiKey == "" or not PROFILEMAN:IsPersistentProfile(player) then return end
	local par = Golf.GetPar(song, steps)
	if not par then return end

	ArrowCloudScores.Request(player, song)
	local strokes = tonumber((CacheGet(PROFILEMAN:GetPlayerName(player), steps:GetGrooveStatsHash(), CacheType.Golf, CacheSource.ArrowCloud)))
	if not strokes then return end

	local diff = strokes / Golf.RAW_PER_STROKE - par
	local term = clamp(math.floor(strokes / Golf.RAW_PER_STROKE + 0.5) - math.floor(par + 0.5), -3, 3)
	self:settext(("%+.2f"):format(diff)):diffuse(golf_colors[term])
	self:y(GAMESTATE:GetNumSidesJoined() == 2 and (player == PLAYER_1 and -7 or 7) or 0)
	self:visible(true)
end

return MusicWheelItem(player, Def.BitmapText {
	Font = "Wendy/_wendy small",
	Text = "",
	InitCommand = function(self) self:visible(false):zoom(0.24):horizalign(right):x(_screen.w / 2 - 4 - WideScale(28, 33)) end,
	Draw = Draw,
	ArrowCloudScoresUpdatedMessageCommand = function(self) self:queuecommand("Refresh") end,
})
