-- Adds time spent in ScreenGameplay and notes hit to this profile's session stats
-- (see ./Scripts/SL_SessionDataForStatistics.lua).
--
-- Both are added as they happen rather than when the screen ends, because restarting
-- or backing out can leave ScreenGameplay without OffCommand ever being played.
------------------------------------------------------------

local player = ...
local record = GetSessionRecord(player)
local tracking = false

return Def.ActorFrame{
	OnCommand=function(self)
		tracking = true
		self:SetUpdateFunction(function(af, dt)
			if tracking then record.songTime = record.songTime + dt end
		end)
	end,
	OffCommand=function(self)
		tracking = false
	end,
	JudgmentMessageCommand=function(self, params)
		if not tracking or params.Player ~= player or not params.Notes then return end
		if GAMESTATE:GetPlayerState(player):GetHealthState() == 'HealthState_Dead' then return end
		if params.TapNoteScore == "TapNoteScore_Miss" then return end

		-- count each note of a jump/hand, but only taps, hold heads and lifts
		for col,tapnote in pairs(params.Notes) do
			local tnt = ToEnumShortString(tapnote:GetTapNoteType())
			if tnt == "Tap" or tnt == "HoldHead" or tnt == "Lift" then
				record.notesHit = record.notesHit + 1
			end
		end
	end
}
