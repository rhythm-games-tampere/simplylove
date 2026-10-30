-- Session stats are kept per profile, not per player side, so switching profiles
-- mid-session doesn't carry one profile's stats over to the next.
-- (SL[pn].Stages deliberately follows the side for ScreenEvaluationSummary, so it can't be used here.)
--
-- Song time and notes hit are added live during gameplay, so attempts that end
-- in a restart or a back out still count.

local ProfileKey = function(player)
	if PROFILEMAN:IsPersistentProfile(player) then
		return PROFILEMAN:GetProfile(player):GetGUID()
	end
	return "Guest" .. ToEnumShortString(player)
end

-- creates the record the first time a profile is seen this session,
-- which is also when that profile's session clock starts
GetSessionRecord = function(player)
	local key = ProfileKey(player)
	local record = SL.Global.SessionStats[key]
	if not record then
		record = { started=GetTimeSinceStart(), songTime=0, notesHit=0, stagesPlayed={} }
		SL.Global.SessionStats[key] = record
	end
	return record
end

-- keyed by stage index so reloading ScreenEvaluation doesn't count the same song twice
MarkSessionSongPlayed = function(player)
	GetSessionRecord(player).stagesPlayed[SL.Global.Stages.PlayedThisGame + 1] = true
end

SessionDataForStatistics = function(player)
	local record = SL.Global.SessionStats[ProfileKey(player)]
	local songTime = record and record.songTime or 0

	local songsPlayed = 0
	if record then
		for _ in pairs(record.stagesPlayed) do songsPlayed = songsPlayed + 1 end
	end

	local hours = math.floor(songTime/3600)
	local minutes = math.floor((songTime-(hours*3600))/60)
	local seconds = round(songTime%60)

	return {
		totalTime = songTime,
		sessionTime = math.max(record and (GetTimeSinceStart() - record.started) or 0, songTime),
		hours = hours,
		minutes = minutes,
		seconds = seconds,
		songsPlayedThisGame = songsPlayed,
		notesHitThisGame = record and record.notesHit or 0
	}
end
