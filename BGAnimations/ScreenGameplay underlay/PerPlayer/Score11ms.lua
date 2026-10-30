-- Small 11ms points readout drawn above the score.

local player = ...
local pn = ToEnumShortString(player)

if not Is11msActive(player) then return end

local function Redraw(self, ex_counts)
	local points = Get11msScore(player, ex_counts)
	self:settext(("11ms points: %d"):format(points))
end

return LoadFont("Common Normal")..{
	Name=pn.."Score11ms",
	InitCommand=function(self)
		self:zoom(0.5):horizalign(left):valign(1)
	end,
	OnCommand=function(self)
		local score = self:GetParent():GetChild(pn.."Score")
		if not score or not score:GetVisible() then
			self:visible(false)
			return
		end
		-- the score font is monospace, so anchor to where a 5-character score ("99.99") starts
		local char_w = score:GetZoomedWidth() / #score:GetText()
		self:xy(score:GetX() - char_w * 5, score:GetY() - score:GetZoomedHeight() - 1)
		Redraw(self, {})
	end,
	ExCountsChangedMessageCommand=function(self, params)
		if params.Player ~= player then return end
		Redraw(self, params.ExCounts)
	end,
}
