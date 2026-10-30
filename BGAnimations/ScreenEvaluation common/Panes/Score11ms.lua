-- Small 11ms points / fantastic% line drawn above the pane's percentage.
local player, controller = unpack(...)

if not Is11msActive(player) then return end

local ex_counts = SL[ToEnumShortString(player)].Stages.Stats[SL.Global.Stages.PlayedThisGame + 1].ex_counts
if not ex_counts then return end

local points, percent = Get11msScore(player, ex_counts)

return LoadFont("Common Normal")..{
	Name="Score11ms",
	Text=("11ms Points: %d - FA%%: %.2f%%"):format(points, math.floor(percent * 10000) / 100),
	InitCommand=function(self)
		self:zoom(0.52):horizalign(right):valign(1)
		self:x( (controller == PLAYER_1 and 1.5 or 141))
		self:y(-19)
	end
}
