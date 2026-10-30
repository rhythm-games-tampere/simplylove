-- Development helper: fills the per-profile session stats with fake profiles so
-- ScreenGameOver can be previewed with lots of data. Set to false (or delete this file) when done.
local enabled = true

local names = {
	"Aino", "Bertta", "Cecilia", "Daniel", "Eero", "Fanni", "Gustav", "Helmi",
	"Ilmari", "Jenni", "Kalle", "Lotta", "Mikko", "Noora", "Olli", "Pinja",
	"Quentin", "Riikka", "Sampo", "Tuuli", "Urho", "Veera", "Waltteri", "Xenia",
	"Ykä", "Zelda", "Ronja the Long Named Stepper", "Matti", "Saara", "Joonas",
	"Elina", "Antti", "Heidi", "Kimmo",
}

-- fixed-seed generator so the mock data looks the same on every visit
local seed = 12345
local Random = function(lo, hi)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return lo + seed % (hi - lo + 1)
end

-- avatars of real local profiles, reused on some of the fake ones
local LocalAvatars = function()
	local avatars = {}
	for i=0, PROFILEMAN:GetNumLocalProfiles()-1 do
		local id = PROFILEMAN:GetLocalProfileIDFromIndex(i)
		local path = GetAvatarPath(PROFILEMAN:LocalProfileIDToDir(id), PROFILEMAN:GetLocalProfileFromIndex(i):GetDisplayName())
		if path then avatars[#avatars+1] = path end
	end
	return avatars
end

local FakeRecord = function(name, player, started, avatar)
	local songs = Random(3, 60)
	local stagesPlayed = {}
	for i=1, songs do stagesPlayed[i] = true end

	return {
		name = name,
		player = player,
		avatar = avatar,
		started = started,
		activeTime = songs * Random(150, 240),
		-- roughly 1.5 - 2.5 minutes per song, 250 - 900 notes per song
		songTime = songs * Random(90, 150),
		notesHit = songs * Random(250, 900),
		stagesPlayed = stagesPlayed,
	}
end

EnsureSessionMockData = function()
	if not enabled or SL.Global.SessionStats["Mock1"] then return end

	local avatars = LocalAvatars()
	local now = GetTimeSinceStart()

	for i,name in ipairs(names) do
		local avatar = (#avatars > 0 and i % 3 ~= 0) and avatars[(i % #avatars) + 1] or nil
		local player = (i % 2 == 0) and PLAYER_2 or PLAYER_1
		local started = now - Random(2, 5) * 3600 + i * 60
		SL.Global.SessionStats["Mock" .. i] = FakeRecord(name, player, started, avatar)
	end

	-- give the joined players a long session as well
	for player in ivalues(GAMESTATE:GetHumanPlayers()) do
		local record = GetSessionRecord(player)
		local fake = FakeRecord(record.name, player, now - 3*3600, record.avatar)
		record.started = fake.started
		record.activeTime = math.max(record.activeTime, fake.activeTime)
		record.songTime = math.max(record.songTime, fake.songTime)
		record.notesHit = math.max(record.notesHit, fake.notesHit)
		for k in pairs(fake.stagesPlayed) do record.stagesPlayed[-k] = true end
	end
end

-- calories for the burger row on ScreenGameOver (600 calories per burger); nil when disabled
SessionMockCalories = function(player)
	if not enabled then return nil end
	return (player == PLAYER_1 and 8 or 12.39) * 600
end
