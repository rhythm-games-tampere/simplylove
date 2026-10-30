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

	-- remembered for ScreenGameOver, which lists profiles that are no longer joined
	record.player = player
	record.name = PROFILEMAN:IsPersistentProfile(player)
		and PROFILEMAN:GetProfile(player):GetDisplayName()
		or THEME:GetString("ScreenSelectProfile", "GuestProfile")
	if PROFILEMAN:IsPersistentProfile(player) then
		record.avatar = GetPlayerAvatarPath(player)
	end

	return record
end

-- keyed by stage index so reloading ScreenEvaluation doesn't count the same song twice
MarkSessionSongPlayed = function(player)
	GetSessionRecord(player).stagesPlayed[SL.Global.Stages.PlayedThisGame + 1] = true
end

local Summarize = function(record)
	local songTime = record and record.songTime or 0

	local songsPlayed = 0
	if record then
		for _ in pairs(record.stagesPlayed) do songsPlayed = songsPlayed + 1 end
	end

	local hours = math.floor(songTime/3600)
	local minutes = math.floor((songTime-(hours*3600))/60)
	local seconds = round(songTime%60)

	return {
		name = record and record.name,
		player = record and record.player,
		avatar = record and record.avatar,
		totalTime = songTime,
		sessionTime = math.max(record and (GetTimeSinceStart() - record.started) or 0, songTime),
		hours = hours,
		minutes = minutes,
		seconds = seconds,
		songsPlayedThisGame = songsPlayed,
		notesHitThisGame = record and record.notesHit or 0
	}
end

SessionDataForStatistics = function(player)
	return Summarize(SL.Global.SessionStats[ProfileKey(player)])
end

-- stats for profiles that played this session but aren't joined right now, oldest first
InactiveSessionData = function()
	local active = {}
	for player in ivalues(GAMESTATE:GetHumanPlayers()) do
		active[ProfileKey(player)] = true
	end

	local records = {}
	for key,record in pairs(SL.Global.SessionStats) do
		if not active[key] and (record.songTime > 0 or record.notesHit > 0 or next(record.stagesPlayed)) then
			records[#records+1] = record
		end
	end
	table.sort(records, function(a,b) return a.started < b.started end)

	local data = {}
	for record in ivalues(records) do
		data[#data+1] = Summarize(record)
	end
	return data
end

-- ScreenGameOver stays up longer when there are many profiles' stats to show
GameOverTimerSeconds = function()
	local seconds = (ThemePrefs.Get("VisualStyle") == "SRPG10") and 135 or 23
	local profiles = #InactiveSessionData() + #GAMESTATE:GetHumanPlayers()
	if profiles >= 8 then
		seconds = math.max(seconds, 45)
	end
	return seconds
end
