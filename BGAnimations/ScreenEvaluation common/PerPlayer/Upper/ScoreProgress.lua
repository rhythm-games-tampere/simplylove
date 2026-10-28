if SL.Global.GameMode == "Casual" or GAMESTATE:IsCourseMode() then return end

-- copied from EventProgress.lua
local chatModule = FILEMAN:DoesFileExist(THEME:GetCurrentThemeDirectory() .. "Modules/TwitchChat.lua")
if not IsUsingWideScreen() and (chatModule or #GAMESTATE:GetHumanPlayers() ~= 1) then return end

local player = ...
local pn = ToEnumShortString(player)

if not PROFILEMAN:IsPersistentProfile(player) then return end

local song = GAMESTATE:GetCurrentSong()
local steps = GAMESTATE:GetCurrentSteps(player)
if not (song and steps) then return end

local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)
local score_type = SL[pn].ActiveModifiers.ShowExScore and CacheType.EX or CacheType.ITG
local LampColors = SL.JudgmentColors["FA+"]

-- ---------------------------------------------------------------------------
-- data

local function CurrentScore()
	if score_type == CacheType.EX then return CalculateExScore(player) end
	return pss:GetPercentDancePoints() * 100
end

local function CurrentLamp()
	local stats = SL[pn].Stages.Stats[SL.Global.Stages.PlayedThisGame + 1]
	local faPlus = stats and stats.ex_counts and stats.ex_counts.W0_total or 0
	local whites = pss:GetTapNoteScores("TapNoteScore_W1") - faPlus
	return LampIndex(pss:GetGrade(), pss:GetPercentDancePoints(), whites, pss:GetStageAward())
end

-- Previous best score and best lamp at 1.0x or faster, excluding this play.
-- Searched from score cache + local scores
local function PreviousBest()
	local best_score, best_lamp

	local function Consider(value, lamp)
		if value and (not best_score or value > best_score) then best_score = value end
		if lamp and LampRank[lamp] and (not best_lamp or LampRank[lamp] > LampRank[best_lamp]) then best_lamp = lamp end
	end

	local name = PROFILEMAN:GetPlayerName(player)
	local hash = steps:GetGrooveStatsHash()
	local function ConsiderCached(source)
		local cached, cached_lamp = CacheGet(name, hash, score_type, source)
		local lamp = ParseLamp(cached_lamp)
		-- Failed plays don't count as a best
		if cached and lamp ~= 6 then
			Consider(tonumber((cached:gsub("[^%d%.]", ""))), lamp)
		end
	end
	ConsiderCached(CacheSource.Local)
	if SL[pn].ArrowCloudApiKey ~= "" then ConsiderCached(CacheSource.ArrowCloud) end
	if ThemePrefs.Get("EnableGrooveStats") then ConsiderCached(CacheSource.GrooveStats) end

	local current = pss:GetHighScore()
	for hs in ivalues(PROFILEMAN:GetProfile(player):GetHighScoreList(song, steps):GetHighScores()) do
		local isThisPlay = hs:GetDate() == current:GetDate() and hs:GetPercentDP() == current:GetPercentDP()
		if not isThisPlay and hs:GetGrade() ~= "Grade_Failed" and HighScoreMusicRate(hs) >= 1 then
			local value = score_type == CacheType.EX and HighScoreExScore(hs, steps, player) or hs:GetPercentDP() * 100
			Consider(value, HighScoreLampIndex(hs))
		end
	end

	return best_score, best_lamp
end

-- ---------------------------------------------------------------------------
-- layout, copied from EventProgress.lua

local posX = 381 * (player == PLAYER_1 and 1 or -1)
local posY = 109

local paneWidth = 156
local paneHeight = 144
local borderWidth = 2

local RowHeight = 25

if IsUsingWideScreen() and (chatModule or #GAMESTATE:GetHumanPlayers() > 1) then
	posX = 211 * (player == PLAYER_1 and -1 or 1)
	posY = 274
	paneWidth = 118
	paneHeight = 180
end

-- ---------------------------------------------------------------------------

local current, lamp, best_score, best_lamp

local Layout = {
	HeroZoom = 1.5, LampZoom = 1, RowZoom = 1.2,
	Pad = 6, ColumnGap = 0, Gap = 6, RowGap = 4, BottomPad = 6,
	RuleAlpha = 0.25,
	Gray = "#9a9a9a", Dim = "#6e6e6e",
	Offset = { Hero = 0, Lamp = 0, Rule = 0, Rows = 0 },
}

local Gray = color(Layout.Gray)
local Dim = color(Layout.Dim)
local Positive = LampColors[4]
local Negative = LampColors[6]

local contentLeft = -(paneWidth - borderWidth) / 2 + Layout.Pad
local contentRight = (paneWidth - borderWidth) / 2 - Layout.Pad
local contentWidth = contentRight - contentLeft
local bodyTop = -paneHeight/2 + RowHeight * 3/2
local innerBottom = (paneHeight - borderWidth) / 2

-- Rank rows as {label, value, dimmed suffix}
local function RankRow(label, rank, total)
	if rank == nil then return { label = label, value = "" } end
	if rank == false then return { label = label, value = "none", dimValue = true } end
	return { label = label, value = ("#%d"):format(rank), suffix = total and ("/%d"):format(total) }
end

local af = Def.ActorFrame{
	Name="ScoreProgress"..pn,

	InitCommand=function(self)
		self:xy(posX, posY)
	end,

	OnCommand=function(self)
		current = CurrentScore()
		lamp = CurrentLamp()
		best_score, best_lamp = PreviousBest()
		self:playcommand("Draw")
	end,

	DrawCommand=function(self)
		local hero = self:GetChild("Hero")
		if pss:GetFailed() then
			hero:settext("Failed"):diffuse(Negative)
		else
			local delta = current - (best_score or 0)
			hero:settext(("%+.2f%%"):format(delta)):diffuse(delta < 0 and Negative or Positive)
		end

		local lampText = self:GetChild("Lamp")
		local lampName = LampNames[lamp]

		if lamp ~= 6 and LampRank[lamp] > (best_lamp and LampRank[best_lamp] or 0) then
			local bestName = best_lamp and LampNames[best_lamp] or "None"
			lampText:settext(bestName .. " › " .. lampName):ClearAttributes():diffuse(Dim)
			lampText:AddAttribute(#bestName, { Length=3, Diffuse=Gray })
			lampText:AddAttribute(#bestName + 3, { Length=#lampName, Diffuse=LampColors[lamp] })
		else
			lampText:settext(lampName):ClearAttributes():diffuse(LampColors[lamp])
		end

		local y = bodyTop
		hero:y(y + Layout.Offset.Hero)
		y = y + hero:GetHeight() * Layout.HeroZoom + Layout.Gap
		lampText:y(y + Layout.Offset.Lamp)

		local rows = { RankRow("AC", self.rank, self.total), RankRow("GS", self.gsRank) }
		y = innerBottom - Layout.BottomPad
		for i = #rows, 1, -1 do
			local label, value, row = self:GetChild("Label"..i), self:GetChild("Value"..i), rows[i]
			label:settext(row.label)
			value:settext(row.value .. (row.suffix or "")):ClearAttributes():diffuse(row.dimValue and Gray or Color.White)
			local maxWidth = contentWidth - label:GetWidth() * Layout.RowZoom - Layout.ColumnGap
			if row.suffix then
				if value:GetWidth() * Layout.RowZoom > maxWidth then
					value:settext(row.value)
				else
					value:AddAttribute(#row.value, { Length=#row.suffix, Diffuse=Gray })
				end
			end
			value:maxwidth(maxWidth / Layout.RowZoom)
			y = y - label:GetHeight() * Layout.RowZoom
			label:y(y + Layout.Offset.Rows)
			value:y(y + Layout.Offset.Rows)
			y = y - Layout.RowGap
		end
		self:GetChild("Rule"):y(y + Layout.RowGap - Layout.Gap - 1 + Layout.Offset.Rule)
	end,

	-- rank is nil when the player is not on the leaderboard they are scoring on
	SetGrooveStatsRankCommand=function(self, params)
		self.gsRank = tonumber(params.rank) or false
		self:playcommand("Draw")
	end,

	ArrowCloudSubmitResultMessageCommand=function(self, params)
		if not (params and params.ok and params.player == pn) then return end
		if self.request then return end

		local cancelled = false
		self.cancel = function() cancelled = true end
		self.request = ArrowCloudScores.FetchRank(player, steps, score_type, function(rank, total)
			if cancelled or rank == nil then return end
			self.rank, self.total = rank, total
			self:playcommand("Draw")
		end)
	end,

	OffCommand=function(self)
		if self.cancel then self.cancel() end
		if self.request then self.request:Cancel() end
	end,

	-- border, background and header copied from EventProgress.lua
	Def.Quad {
		InitCommand=function(self)
			self:zoomto(paneWidth, paneHeight)
			self:diffuse(Color.White):diffusealpha(0.1)
		end
	},

	Def.Quad {
		InitCommand=function(self)
			self:zoomto(paneWidth - borderWidth, paneHeight - borderWidth)
			self:diffuse(Color.Black):diffusealpha(0.85)
		end
	},

	LoadFont("Wendy/_wendy small").. {
		Name="Header",
		Text=THEME:GetString("ScreenEvaluation", "ScoreProgressHeader"),
		InitCommand=function(self)
			self:zoom(0.5)
			self:y(-paneHeight/2 + 15)
			self:maxwidth((paneWidth - 6) / 0.5)
		end
	},

	LoadFont("Common Normal").. {
		Name="Hero",
		InitCommand=function(self) self:valign(0):zoom(Layout.HeroZoom) end,
	},

	LoadFont("Common Normal").. {
		Name="Lamp",
		InitCommand=function(self) self:valign(0):zoom(Layout.LampZoom) end,
	},

	Def.Quad {
		Name="Rule",
		InitCommand=function(self)
			self:valign(0):zoomto(contentWidth, 1)
			self:diffuse(Color.White):diffusealpha(Layout.RuleAlpha)
		end
	},
}

for i = 1, 2 do
	af[#af + 1] = LoadFont("Common Normal").. {
		Name="Label"..i,
		InitCommand=function(self) self:valign(0):halign(0):zoom(Layout.RowZoom):x(contentLeft):diffuse(Gray) end,
	}
	af[#af + 1] = LoadFont("Common Normal").. {
		Name="Value"..i,
		InitCommand=function(self) self:valign(0):halign(1):zoom(Layout.RowZoom):x(contentRight) end,
	}
end

return af
