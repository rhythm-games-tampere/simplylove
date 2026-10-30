-- small cards for profiles that played this session but aren't joined anymore

local data = InactiveSessionData()
if #data == 0 then return Def.Actor{} end

local Format = LoadActor("./Formatters.lua")

local card_w = 140
local card_h = 44
local gap = 8
local step = card_h + gap

-- between the side panels (160px each), with a small margin
local area_w = _screen.w - 2*(160 + 10)
local columns = math.max(1, math.floor((area_w + gap) / (card_w + gap)))
local num_rows = math.ceil(#data / columns)

-- cards are only drawn inside these, never over the band where the burgers are drawn (y 180 - 230)
local zones = { {10, 180}, {240, _screen.h - 10} }

-- row tops when everything fits on screen
local rows = {}
for zone in ivalues(zones) do
	for y=zone[1], zone[2] - card_h, step do rows[#rows+1] = y end
end

local scrolling = num_rows > #rows

-- when scrolling, rows are one continuous list moving through both zones
local max_offset = scrolling and (zones[1][1] + num_rows*step - gap - zones[2][2]) or 0
local pause = 2
local speed = math.max(20, 2*max_offset / (GameOverTimerSeconds() - 4*pause))
local travel = max_offset / speed

-- seconds -> offset; down, pause, back up, pause, repeat
local OffsetAt = function(t)
	t = (t - pause) % (2*travel + 2*pause)
	if t < travel then return t * speed end
	if t < travel + pause then return max_offset end
	if t < 2*travel + pause then return max_offset - (t - travel - pause) * speed end
	return 0
end

-- 1 when the card is fully inside a zone, fading out over `fade` px as it leaves
local fade = 12
local Visibility = function(top)
	local best = 0
	for zone in ivalues(zones) do
		local inside = math.min(top - zone[1], zone[2] - (top + card_h))
		best = math.max(best, math.min(1, math.max(0, (inside + fade) / fade)))
	end
	return best
end

local cards = {}
local elapsed = 0

local af = Def.ActorFrame{
	InitCommand=function(self) self:diffusealpha(0) end,
	OnCommand=function(self)
		self:sleep(0.5):decelerate(0.5):diffusealpha(1)
		if scrolling then
			self:SetUpdateFunction(function(_, dt)
				elapsed = elapsed + dt
				local offset = OffsetAt(elapsed)
				for card in ivalues(cards) do
					local top = card.top - offset
					card.actor:y(top + card_h/2):diffusealpha(Visibility(top))
				end
			end)
		end
	end,
	OffCommand=function(self) self:accelerate(0.5):diffusealpha(0) end,
}

for i,stats in ipairs(data) do
	local row = math.ceil(i / columns)
	if not scrolling and row > #rows then break end

	local cards_in_row = math.min(columns, #data - (row-1)*columns)
	local col = (i-1) % columns
	local x = _screen.cx + (col - (cards_in_row-1)/2) * (card_w + gap)
	local top = scrolling and (zones[1][1] + (row-1)*step) or rows[row]
	local side_color = stats.player and PlayerColor(stats.player) or color("#ffffff")

	af[#af+1] = Def.ActorFrame{
		InitCommand=function(self)
			self:xy(x, top + card_h/2)
			if scrolling then
				self:diffusealpha(Visibility(top))
				cards[#cards+1] = { actor=self, top=top }
			end
		end,

		Def.Quad{
			InitCommand=function(self) self:zoomto(card_w, card_h):diffuse(side_color) end
		},
		Def.Quad{
			InitCommand=function(self) self:zoomto(card_w-2, card_h-2):diffuse(color("#000000ee")) end
		},
		LoadFont("Common Normal")..{
			Text=stats.name or "",
			InitCommand=function(self)
				self:y(-10):zoom(0.85):maxwidth((card_w-10)/0.85):diffuse(side_color)
			end
		},
		LoadFont("Common Normal")..{
			Text=("💿 %d   👟 %s   ⏱ %s"):format(
				stats.songsPlayedThisGame,
				Format.Count(stats.notesHitThisGame),
				Format.Time(stats.totalTime)
			),
			InitCommand=function(self)
				self:y(10):zoom(0.75):maxwidth((card_w-10)/0.75)
			end
		},
	}
end

return af
