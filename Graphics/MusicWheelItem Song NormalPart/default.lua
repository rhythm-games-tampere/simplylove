-- the MusicWheelItem for CourseMode contains the basic colored Quads
-- use that as a common base, and add in a Sprite for "Has Edit"
local af = LoadActor("../MusicWheelItem Course NormalPart.lua")

-- Golf PAR badges are injected after the row's first Set
af.SetCommand = function(self, params) self.Song = params and params.Song end
af.GolfBadgesInjectedMessageCommand = function(self)
	local badge = self:GetParent():GetChild("GolfParBadge")
	if self.Song and type(badge) == "table" and badge.playcommand then
		badge:playcommand("Set", { Song = self.Song })
	end
end

-- Player-specific actors
for player in ivalues(PlayerNumber) do
	if ThemePrefs.Get("MusicWheelTechNotation") ~= "No" then
		af[#af + 1] = LoadActor("TechNotation.lua", player)
	end

	af[#af+1] = LoadActor("Favorites.lua", player)
	af[#af+1] = LoadActor("Unlocks.lua", player)

	if SLMusicWheelScoreEnabled() then
		af[#af + 1] = LoadActor("Score.lua", player)
	else
		af[#af + 1] = LoadActor("ITL_EXScore.lua", player)
	end
	if type(Golf) == "table" then
		af[#af + 1] = LoadActor("GolfScore.lua", player)
	end
end


if ThemePrefs.Get("MusicWheelTechNotation") ~= "No" then
	-- disable HasEdit if tech notation is displayed
	return af
end

-- using a png in a Sprite ties the visual to a specific rasterized font (currently Miso),
-- but Sprites are cheaper than BitmapTexts, so we should use them where dynamic text is not needed
local stepstype = GAMESTATE:GetCurrentStyle():GetStepsType()
af[#af+1] = Def.Sprite{
	Texture=THEME:GetPathG("", "Has Edit (doubleres).png"),
	InitCommand=function(self)
		self:horizalign(left):visible(false):zoom(0.375)
		self:x( _screen.w/(WideScale(2.15, 2.14)) - self:GetWidth()*self:GetZoom() - 8 )

		if DarkUI() then self:diffuse(0,0,0,1) end
	end,
	SetCommand=function(self, params)
		self:visible(not MusicWheelScoreOnRight() and params.Song and params.Song:HasEdits(stepstype) or false)
	end
}

return af
