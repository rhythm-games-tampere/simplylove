local API = "https://api.arrowcloud.dance"
local TIMEOUT = 15
local MAX_HASHES = 1000
local ERROR_PAUSE = 60
local LEADERBOARDS = { [CacheType.EX] = 2, [CacheType.ITG] = 3 }

local profile_slot = {
	[PLAYER_1] = "ProfileSlot_Player1",
	[PLAYER_2] = "ProfileSlot_Player2",
}

function ParseArrowCloudIni(player)
	if not profile_slot[player] then return end
	local pn = ToEnumShortString(player)
	SL[pn].ArrowCloudApiKey = ""

	local dir = PROFILEMAN:GetProfileDir(profile_slot[player])
	if not dir or #dir == 0 then return end
	local path = dir .. "ArrowCloud.ini"
	if not FILEMAN:DoesFileExist(path) then return end

	local contents = IniFile.ReadFile(path)
	local key = contents and type(contents.ArrowCloud) == "table" and contents.ArrowCloud.ApiKey
	if type(key) == "string" then SL[pn].ArrowCloudApiKey = key end
end

ArrowCloudScores = {}

-- per player: { pn, key, name, pending = {hash=true}, groups = {name=true}, inflight = {handler, hashes}?, disabled }
local State = {}
local PausedUntil = 0

local function StateFor(player)
	local pn = ToEnumShortString(player)
	local key = SL[pn].ArrowCloudApiKey
	if key == "" or not PROFILEMAN:IsPersistentProfile(player) then return nil end
	local s = State[pn]
	if not s or s.key ~= key then
		s = { pn = pn, key = key, name = PROFILEMAN:GetPlayerName(player), pending = {}, groups = {} }
		State[pn] = s
	end
	return s
end

local function Queue(s, steps)
	local hash = steps:GetGrooveStatsHash()
	if hash and hash ~= "" then s.pending[hash] = true end
end

local function Failure(response)
	return tostring(response.error and ToEnumShortString(response.error) or response.statusCode)
end

-- Slot = lamp index, as in HighScoreLampString
local function LampCounts(play)
	local j = type(play.judgments) == "table" and play.judgments or {}
	local r = type(play.radar) == "table" and play.radar or {}
	local function n(v) return tonumber(v) or 0 end
	return {
		[1] = n(j["Fantastic (23ms)"]) + n(r.minesTotal) - n(r.minesDodged),
		[2] = n(j["Decent"]) + n(j["Way Off"]) + n(j["Miss"]) + n(r.holdsTotal) - n(r.holdsHeld) + n(r.rollsTotal) - n(r.rollsHit),
		[3] = n(j["Excellent"]),
		[4] = n(j["Great"]),
	}
end

local function PlayLampIndex(play, counts)
	if play.grade == "F" then return 6 end
	if counts[2] > 0 then return nil end
	if counts[4] > 0 then return 4 end
	if counts[3] > 0 then return 3 end
	if counts[1] > 0 then return 1 end
	return 5
end

local function PlayLamp(play)
	local counts = LampCounts(play)
	local idx = PlayLampIndex(play, counts)
	return LampString(idx, idx and counts[idx])
end

-- body.scores: { [hash: string] = { [leaderboardId: string] = play } }
-- play: { score: number, grade: string,
--         judgments: { [string]: number },
--         radar: { minesTotal, minesDodged, holdsTotal, holdsHeld, rollsTotal, rollsHit: number } }
local function Store(s, body)
	local scores = type(body) == "table" and body.scores
	if type(scores) ~= "table" then return 0 end
	local rows = 0
	CacheBatch(function()
		for hash, entry in pairs(scores) do
			for score_type, id in pairs(LEADERBOARDS) do
				local play = type(entry) == "table" and entry[tostring(id)]
				local score = type(play) == "table" and tonumber(play.score)
				if score then
					CacheSet(s.name, hash, score_type, CacheSource.ArrowCloud, ("%05.2f"):format(score), PlayLamp(play))
					rows = rows + 1
				end
			end
		end
	end)
	return rows
end

local function Send(s)
	local hashes = {}
	for hash in pairs(s.pending) do
		if #hashes >= MAX_HASHES then break end
		hashes[#hashes + 1] = hash
		s.pending[hash] = nil
	end
	if #hashes == 0 then return end

	local request = { hashes = hashes }
	s.inflight = request
	request.handler = NETWORK:HttpRequest{
		url = API .. "/v1/retrieve-scores",
		method = "POST",
		body = JsonEncode({ chartHashes = hashes, leaderboardIds = { LEADERBOARDS[CacheType.EX], LEADERBOARDS[CacheType.ITG] } }),
		headers = { Authorization = "Bearer " .. s.key, ["Content-Type"] = "application/json" },
		connectTimeout = TIMEOUT,
		transferTimeout = TIMEOUT,
		onResponse = function(response)
			if s.inflight ~= request then return end
			s.inflight = nil
			local code = response.statusCode
			if code == 401 or code == 403 then
				lua.Warn("ArrowCloudScores: HTTP " .. code .. " for " .. s.pn .. ", disabling for this session")
				s.disabled = true
			elseif response.error or code ~= 200 then
				lua.Warn("ArrowCloudScores: request failed (" .. Failure(response) .. ")")
				PausedUntil = GetTimeSinceStart() + ERROR_PAUSE
				for _, hash in ipairs(hashes) do s.pending[hash] = true end
			elseif Store(s, JsonDecode(response.body)) > 0 then
				MESSAGEMAN:Broadcast("ArrowCloudScoresUpdated")
			end
		end,
	}
end

function ArrowCloudScores.Request(player, song, steps)
	local s = StateFor(player)
	if not s or s.disabled then return end
	if steps then Queue(s, steps) end

	local group = song:GetGroupName()
	if not s.groups[group] then
		s.groups[group] = true
		for g_song in ivalues(SONGMAN:GetSongsInGroup(group)) do
			for st in ivalues(SongUtil.GetPlayableSteps(g_song)) do Queue(s, st) end
		end
	end
end

function ArrowCloudScores.Flush()
	if GetTimeSinceStart() < PausedUntil then return end
	for _, s in pairs(State) do
		if not s.disabled and not s.inflight and next(s.pending) then Send(s) end
	end
end

function ArrowCloudScores.Cancel()
	for _, s in pairs(State) do
		local request = s.inflight
		if request then
			s.inflight = nil
			request.handler:Cancel()
			for _, hash in ipairs(request.hashes) do s.pending[hash] = true end
		end
	end
end

local function SelfRank(board)
	if type(board.scores) ~= "table" then return nil end
	for entry in ivalues(board.scores) do
		if entry.isSelf then return tonumber(entry.rank), tonumber(board.total) end
	end
end

-- callback(rank, total) when ranked, callback(false) when not
-- callback(nil) on failure. Returns the handler or nil.
function ArrowCloudScores.FetchRank(player, steps, score_type, callback)
	local pn = ToEnumShortString(player)
	local key = SL[pn].ArrowCloudApiKey
	local hash = steps and steps:GetGrooveStatsHash()
	if key == "" or not hash or hash == "" then return nil end
	local id = LEADERBOARDS[score_type]

	return NETWORK:HttpRequest{
		url = API .. "/v1/chart/" .. hash .. "/leaderboards",
		method = "GET",
		headers = { Authorization = "Bearer " .. key },
		connectTimeout = TIMEOUT,
		transferTimeout = TIMEOUT,
		onResponse = function(response)
			if response.error or response.statusCode ~= 200 then
				lua.Warn("ArrowCloudScores: leaderboard request failed (" .. Failure(response) .. ")")
				return callback(nil)
			end
			local body = JsonDecode(response.body)
			local boards = type(body) == "table" and body.leaderboards
			if type(boards) ~= "table" then
				lua.Warn("ArrowCloudScores: unexpected leaderboard response for " .. hash)
				return callback(nil)
			end

			for board in ivalues(boards) do
				if board.id == id then
					local rank, total = SelfRank(board)
					if rank then return callback(rank, total) end
				end
			end
			callback(false)
		end,
	}
end
