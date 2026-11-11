-- Song wheel score: the best of the local, ArrowCloud and GrooveStats scores, plus its lamp's judgment count.
local player = ...
local pn = ToEnumShortString(player)
local white = color("#ffffff")

-- Best local score as a formatted string plus its lamp string.
local function LocalScore(song, steps, score_type)
	local name = PROFILEMAN:GetPlayerName(player)
	local hash = steps:GetGrooveStatsHash()
	local cached, cached_lamp = CacheGet(name, hash, score_type, CacheSource.Local)
	if cached and song ~= GAMESTATE:GetCurrentSong() then return cached, cached_lamp end

	local best_hs, best_value
	for hs in ivalues(PROFILEMAN:GetProfile(pn):GetHighScoreList(song, steps):GetHighScores()) do
		if HighScoreMusicRate(hs) >= 1 then
			local value = score_type == CacheType.EX and HighScoreExScore(hs, steps, pn) or hs:GetPercentDP() * 100
			if value and (not best_value or value > best_value) then
				best_hs, best_value = hs, value
			end
		end
	end

	if not best_hs then
		if cached then CacheDelete(name, hash, score_type, CacheSource.Local) end
		return nil, nil
	end

	local live = ("%05.2f"):format(best_value)
	local lamp = HighScoreLampString(best_hs)
	if live ~= cached or lamp ~= cached_lamp then
		CacheSet(name, hash, score_type, CacheSource.Local, live, lamp)
	end
	return live, lamp
end

local function Layout(self)
	local mode = PlayerMusicWheelScore(player)
	local other = PlayerMusicWheelScore(player == PLAYER_1 and PLAYER_2 or PLAYER_1)
	local two = GAMESTATE:GetNumSidesJoined() == 2

	if mode == PlayerMusicWheelScore_ReplaceGrade then
		self:x(32)
	else
		self:x(_screen.w / WideScale(2.15, 2.14) - 35)
	end

	local stacked = two and (mode == other or mode == PlayerMusicWheelScore_ReplaceGrade)
	self:y(stacked and (player == PLAYER_1 and -11 or 4) or -4)
end

local function Draw(self, song, steps)
	local mode = PlayerMusicWheelScore(player)
	if mode == PlayerMusicWheelScore_No or not PROFILEMAN:IsPersistentProfile(player) then return end
	-- AC Golf PAR instead
	if mode ~= PlayerMusicWheelScore_ReplaceGrade and type(Golf) == "table" and Golf.GetPar(song, steps) then return end
	Layout(self)

	local score_type = SL[pn].ActiveModifiers.ShowExScore and CacheType.EX or CacheType.ITG
	local name = PROFILEMAN:GetPlayerName(player)
	local hash = steps:GetGrooveStatsHash()

	local best, best_lamp
	local function Consider(score, lamp)
		if score and (not best or tonumber(score) > tonumber(best)) then
			best, best_lamp = score, lamp
		end
	end
	Consider(LocalScore(song, steps, score_type))
	if SL[pn].ArrowCloudApiKey ~= "" then
		ArrowCloudScores.Request(player, song)
		Consider(CacheGet(name, hash, score_type, CacheSource.ArrowCloud))
	end
	if ThemePrefs.Get("EnableGrooveStats") then
		Consider(CacheGet(name, hash, score_type, CacheSource.GrooveStats))
	end
	if not best then return end

	local idx, count = ParseLamp(best_lamp)
	local c = idx and SL.JudgmentColors["FA+"][idx] or white
	local score = self:GetChild("Score")
	score:settext(best):diffuse(c)

	-- Color exceptions: misses for a clear, whites for a FFC
	local digit_color = ({ [1] = white, [2] = SL.JudgmentColors["FA+"][6] })[idx] or c
	self:GetChild("Count"):settext(count and count < 10 and tostring(count) or ""):diffuse(digit_color)
		:x(score:GetZoomedWidth() / 2 + 2)
	self:visible(true)
end

return MusicWheelItem(player, Def.ActorFrame {
	InitCommand = function(self) self:visible(false) end,
	Draw = Draw,

	CacheUpdatedGSMessageCommand = function(self, params)
		if params.Song == self.Song then
			self:queuecommand("Refresh")
		end
	end,

	ArrowCloudScoresUpdatedMessageCommand = function(self)
		self:queuecommand("Refresh")
	end,

	Def.BitmapText {
		Name = "Score",
		Font = "Wendy/_wendy monospace numbers",
		Text = "",
		InitCommand = function(self) self:zoom(0.2) end,
	},

	-- Superscript judge digit
	Def.BitmapText {
		Name = "Count",
		Font = "Wendy/_wendy monospace numbers",
		Text = "",
		InitCommand = function(self) self:zoom(0.12):horizalign(left):y(-1) end,
	},
})
