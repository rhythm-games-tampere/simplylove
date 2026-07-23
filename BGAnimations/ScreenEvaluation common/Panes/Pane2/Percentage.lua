local player, controller = unpack(...)

local percent = nil
local diffuse = nil
local styletype = ToEnumShortString(GAMESTATE:GetCurrentStyle():GetStyleType())
if (styletype == "TwoPlayersSharedSides") then
	stats = STATSMAN:GetCurStageStats():GetRoutineStageStats()
	-- Format the Percentage string, removing the % symbol
	percent = CalculateExScore(player)
	diffuse = SL.JudgmentColors[SL.Global.GameMode][1]
elseif SL[ToEnumShortString(player)].ActiveModifiers.ShowExScore then
	percent = CalculateExScore(player)
	diffuse = SL.JudgmentColors[SL.Global.GameMode][1]
else
	local stats = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)
	local PercentDP = stats:GetPercentDancePoints()
	percent = FormatPercentScore(PercentDP):gsub("%%", "")
	-- Format the Percentage string, removing the % symbol
	percent = tonumber(percent)
	diffuse = Color.White
end

-- Award a small star beside the score when the best judgment (White Fantastic,
-- W0) makes up 90% or more of all judged notes. The denominator is the sum of
-- every judged window (W0..Miss), matching the per-judgment percentages.
local exCounts = GetExJudgmentCounts(player)
local totalNotes = 0
for _, window in ipairs({ "W0", "W1", "W2", "W3", "W4", "W5", "Miss" }) do
	totalNotes = totalNotes + (exCounts[window] or 0)
end
local bestPct = totalNotes > 0 and ((exCounts["W0"] or 0) / totalNotes * 100) or 0
-- The star(s) are opt-in via the "Show 90%+ Star" player option (FA+ row).
-- Never show them on a failed stage (F grade).
local starsEnabled = SL[ToEnumShortString(player)].ActiveModifiers.ShowFaPlusStar
local failed = STATSMAN:GetCurStageStats():GetPlayerStageStats(player):GetFailed()
local showStar = starsEnabled and (bestPct >= 90) and not failed


return Def.ActorFrame{
	Name="PercentageContainer"..ToEnumShortString(player),
	OnCommand=function(self)
		self:y( _screen.cy-26 )
	end,

	-- dark background quad behind player percent score
	Def.Quad{
		InitCommand=function(self)
			self:diffuse(color("#101519")):zoomto(158.5, SL.Global.GameMode == "Casual" and 60 or 88)
			self:horizalign(controller==PLAYER_1 and left or right)
			self:x(150 * (controller == PLAYER_1 and -1 or 1))
			if SL.Global.GameMode ~= "Casual" then
				self:y(14)
			end
			if ThemePrefs.Get("VisualStyle") == "Technique" then
				self:diffusealpha(0.5)
			end
		end
	},


	LoadFont("Wendy/_wendy white")..{
		Name="Percent",
		Text=("%.2f"):format(percent),
		InitCommand=function(self)
			self:horizalign(right):zoom(0.585)
			self:x( (controller == PLAYER_1 and 1.5 or 141))
			self:diffuse(diffuse)
		end
	},

	-- small star on the outer side of the score, shown only when W0 >= 90%
	LoadActor(THEME:GetPathG("", "_grades/assets/star.png"))..{
		Name="BestJudgmentStar",
		InitCommand=function(self)
			self:zoom(0.08):diffuse(Color.White)
			-- outer side: left edge of the box for P1, right edge for P2
			self:x( (controller == PLAYER_1) and 12 or -144 )
			self:y( -20)
			self:visible(showStar)
		end
	}
}
