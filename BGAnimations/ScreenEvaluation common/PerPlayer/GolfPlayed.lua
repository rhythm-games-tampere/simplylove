-- Forget the cached ArrowCloud golf best for the chart just played; the wheel refetches it
local player = ...

return Def.Actor{
	OnCommand = function(self)
		if type(Golf) ~= "table" or GAMESTATE:IsCourseMode() then return end
		local song, steps = GAMESTATE:GetCurrentSong(), GAMESTATE:GetCurrentSteps(player)
		if not (song and steps and Golf.GetPar(song, steps)) then return end
		local hash = steps:GetGrooveStatsHash()
		if hash and hash ~= "" then ArrowCloudScores.GolfPlayed(player, hash) end
	end,
}
