-- Golf scoring: an alternate scoring concept where every tap costs a number of "strokes"
-- based on how far off it was, and a chart has a "par" the player tries to come in under.
-- Lower is better. A perfect chart is 0.
--
-- STANDALONE. This file plus the Golf/ directory beside it are the whole feature -- drop
-- them into any Simply-Love-derived theme's Modules/ directory and nothing else needs to
-- change. It deliberately avoids theme-specific API (no SL table, no SL_WideScale, no
-- required ThemePrefs keys) and degrades to doing nothing rather than erroring when the
-- host theme doesn't provide something it would have liked.
--
-- Provides:
--   * in-game stroke total and par, replacing the host theme's score display
--   * a "PAR n" badge on matching rows of the song wheel
--
-- ---------------------------------------------------------------------------------------
-- AUTHORING PARS
--
-- Par isn't something the engine knows about, and it can't be hidden in the simfile either:
-- the .sm/.ssc loaders parse a fixed set of tags and discard anything they don't recognise,
-- so a custom "#PAR:" would only be readable by re-reading the raw file off disk (the way
-- SL-ChartParser.lua does). That's far too expensive to do per wheel row per scroll tick.
--
-- So par lives in a "Golf.ini" at the root of the pack, read once per pack and cached. The
-- presence of that file is the entire opt-in: any pack shipping one is a golf pack, and any
-- chart it names is a golf hole.
--
--     ; /Songs/<any pack>/Golf.ini
--     [Honey]
--     Par=3
--
--     ; per-chart override, for songs carrying more than one golf chart
--     [Honey:Challenge]
--     Par=4
--
-- Section names are the song's folder name, optionally suffixed with ":" and the short
-- Difficulty string ("Beginner", "Easy", "Medium", "Hard", "Challenge", "Edit").
--
-- Par is authored in the *displayed* unit and used as-is: "Par=2.1" shows as 2.1. Per-note
-- costs are a separate, much larger quantity -- raw strokes, up to 100 for a miss -- so a full
-- chart runs into the thousands before the division by Golf.RAW_PER_STROKE.

-- luacheck: globals Golf GAMESTATE SCREENMAN THEME FILEMAN IniFile SongUtil Basename
-- luacheck: globals ToEnumShortString ivalues clamp LoadFont Color Def PLAYER_1 PLAYER_2 _screen Trace
-- luacheck: globals ThemePrefs right

-- Set true to trace what the wheel-badge injection is doing into the engine log. Useful when
-- bringing this up on a theme it hasn't been tried against -- see injectWheelBadges.
local DEBUG = false

local function debugPrint(msg)
	if DEBUG and Trace then Trace("[Golf] " .. msg) end
end

-- "Is this thing an actor I can call `name` on?"
--
-- It has to be asked this way rather than with type(). Actors reach Lua as *tables*: ITGmania
-- registers Actor with LUA_REGISTER_INSTANCED_BASE_CLASS, which pushes the object's LuaClass
-- (a LuaTable subclass), not a userdata. And ActorFrame:GetChild returns a plain array table
-- when several children share the requested name. Both are type "table", so only the presence
-- of the method we're about to call tells them apart -- the array has no actor methods on it.
local function hasMethod(obj, name)
	return type(obj) == "table" and type(obj[name]) == "function"
end

-- ---------------------------------------------------------------------------------------
-- Par data
--
-- One global, deliberately. Golf/ParBadge.lua is loaded by the engine as an actor (via
-- AddChildFromPath) and so can't see this file's locals; a single well-named table is the
-- least intrusive way to share the par lookup with it.

Golf = Golf or {}

-- Raw strokes -> the displayed score. Each note is stored as a whole number of raw strokes
-- (0 for an ace, 100 for a miss) and RAW_PER_STROKE of them make one displayed stroke, which
-- is the unit par is written in. Matches the server: see api/src/utils/scoring/golf.ts.
Golf.RAW_PER_STROKE = 1000

-- [pack directory] -> parsed Golf.ini table, or false if the pack has no Golf.ini.
-- Doubles as the is-this-a-golf-pack answer, and as the cache that keeps the wheel from
-- stat()ing the same pack once per visible row per scroll tick.
local par_data = {}

-- "/Songs/Some Pack/Some Song/" -> "/Songs/Some Pack/"
local function PackDir(song)
	local dir = song:GetSongDir()
	if not dir or dir == "" then return nil end
	return (dir:gsub("[^/]+/$", ""))
end

-- IniFile.StrToKeyVal already converts numeric values with tonumber(), but a Golf.ini
-- written with CRLF line endings (likely, since these packs get authored on Windows)
-- leaves a trailing \r on anything it couldn't convert. Be forgiving.
--
-- Returns the par exactly as authored -- Golf.ini holds values in the displayed unit already,
-- so nothing is scaled here.
local function ToPar(value)
	if type(value) == "number" then return value end
	if type(value) ~= "string" then return nil end
	return tonumber(value:match("^%s*(.-)%s*$"))
end

local function LoadParData(pack_dir)
	if par_data[pack_dir] ~= nil then return par_data[pack_dir] end

	local path = pack_dir .. "Golf.ini"
	if not FILEMAN:DoesFileExist(path) then
		par_data[pack_dir] = false
		return false
	end

	par_data[pack_dir] = IniFile.ReadFile(path) or false
	return par_data[pack_dir]
end

-- Which chart's par should we show for a song we aren't currently sitting on?
-- Golf songs are expected to carry a single chart, so the common case is trivial. When
-- there is more than one, prefer whatever difficulty the master player is currently on so
-- the wheel stays consistent with the difficulty they're browsing at.
Golf.ChooseSteps = function(song)
	if not song then return nil end

	local steps = SongUtil.GetPlayableSteps(song)
	if not steps or #steps == 0 then return nil end
	if #steps == 1 then return steps[1] end

	local current = GAMESTATE:GetCurrentSteps(GAMESTATE:GetMasterPlayerNumber())
	if current then
		local difficulty = current:GetDifficulty()
		for chart in ivalues(steps) do
			if chart:GetDifficulty() == difficulty then return chart end
		end
	end

	return steps[#steps]
end

-- Returns the par for a chart as a number, or nil if the pack has no Golf.ini or that
-- particular song/chart has no par defined in it.
-- `steps` is optional; when omitted we only bother resolving a chart once we already know
-- the pack has par data at all.
Golf.GetPar = function(song, steps)
	if not song then return nil end

	local pack_dir = PackDir(song)
	if not pack_dir then return nil end

	local data = LoadParData(pack_dir)
	if not data then return nil end

	local song_key = Basename(song:GetSongDir())
	if not song_key or song_key == "" then return nil end

	steps = steps or Golf.ChooseSteps(song)

	-- a per-chart entry wins over the song-wide one
	if steps then
		local section = data[song_key .. ":" .. ToEnumShortString(steps:GetDifficulty())]
		if section then
			local par = ToPar(section.Par)
			if par then return par end
		end
	end

	local section = data[song_key]
	if section then return ToPar(section.Par) end

	return nil
end

-- Drop the cached Golf.ini contents so edits made while the game is running -- including
-- adding a Golf.ini to a pack that had none -- get picked up on re-entering ScreenSelectMusic
-- rather than needing a restart.
Golf.ClearCache = function()
	par_data = {}
end

-- ---------------------------------------------------------------------------------------
-- Formatting

Golf.FormatScore = function(strokes)
	return ("%.2f"):format((strokes or 0) / Golf.RAW_PER_STROKE)
end

-- Pars are usually fractional in the current unit, so print up to two decimals and trim
-- whatever isn't needed: 5.6 -> "5.6", 2 -> "2". Display only; the value is never altered.
Golf.FormatPar = function(par)
	if not par then return "-" end
	local text = ("%.2f"):format(par)
	return (text:gsub("%.?0+$", ""))
end

Golf.IsUnderPar = function(strokes, par)
	if not par then return false end
	return ((strokes or 0) / Golf.RAW_PER_STROKE) <= par
end

-- ---------------------------------------------------------------------------------------
-- Results hand-off
--
-- Per-player results for the stage currently being played, keyed "P1"/"P2". A player with no
-- entry wasn't playing a golf hole. Nothing in this module reads it back -- it exists so a
-- host theme (or Arrow Cloud's result card) can show the stage's golf numbers afterwards.

Golf.Scores = {}

Golf.ClearScores = function()
	Golf.Scores = {}
end

-- Returns this player's golf result only if it belongs to the chart currently loaded in
-- GAMESTATE. Gameplay clears the table on entry, but only on the gameplay screens this module
-- hooks -- a golf chart played somewhere it doesn't hook (routine's ScreenGameplayShared, say)
-- would otherwise leave the previous stage's result sitting there to be read as this one's.
Golf.GetScoreForCurrentChart = function(player)
	local result = Golf.Scores[ToEnumShortString(player)]
	if not result then return nil end

	local song = GAMESTATE:GetCurrentSong()
	if not song or result.songDir ~= song:GetSongDir() then return nil end

	local steps = GAMESTATE:GetCurrentSteps(player)
	if result.difficulty ~= (steps and steps:GetDifficulty()) then return nil end

	return result
end

-- ---------------------------------------------------------------------------------------
-- Host theme compatibility
--
-- Everything below here is "ask the theme nicely, fall back to something sane".

-- Simply Love exposes a "ThemeFont" preference; other themes don't. Resolve it once, behind a
-- pcall, and fall back to the _fallback-guaranteed "Common" family. Without this the module
-- dies at load on any theme lacking that pref: ThemePrefs.Get returns nil and the
-- nil .. " numbers" concat throws.
local themeFont = "Common"
do
	local ok, value = pcall(function()
		return ThemePrefs and ThemePrefs.Get and ThemePrefs.Get("ThemeFont")
	end)
	if ok and type(value) == "string" and value ~= "" then themeFont = value end
end

-- Not every theme ships every font variant. Stock Simply Love, for instance, has
-- "Common Normal" and "Common Bold" but no "Common numbers" -- that one is an Arrow Cloud
-- fork addition. Asking for a missing font doesn't error, it silently substitutes the
-- engine default, which renders at the wrong size and looks broken rather than failing
-- loudly. So check first and step down to something the host definitely has.
local function fontExists(name)
	local ok, path = pcall(function() return THEME:GetPathF("", name, true) end)
	return ok and type(path) == "string" and path ~= ""
end

-- Concrete font files to try when the themed name isn't available, per variant. The score
-- numerals matter most: Simply Love's own gameplay score is
-- LoadFont("Wendy/_wendy monospace numbers") at zoom 0.5, and this fork's "Common numbers" is
-- literally a .redir to that same font. Naming it directly means the golf total renders in the
-- same face and size as the score it replaces, on both themes. Without it the chain fell
-- through to "Common Normal" -- a small text face -- and the total came out tiny and wrong.
local FONT_FALLBACKS = {
	numbers = { "Wendy/_wendy monospace numbers", "Wendy/_wendy small" },
	Bold    = { "Wendy/_wendy small" },
}

local function GolfFont(variant)
	local candidates = {
		themeFont .. " " .. variant,   -- e.g. "Mega numbers"
		"Common " .. variant,          -- e.g. "Common numbers"
	}
	for _, extra in ipairs(FONT_FALLBACKS[variant] or {}) do
		candidates[#candidates+1] = extra
	end
	candidates[#candidates+1] = themeFont .. " Normal"
	candidates[#candidates+1] = "Common Normal"   -- guaranteed by _fallback

	for _, candidate in ipairs(candidates) do
		if fontExists(candidate) then return LoadFont(candidate) end
	end
	return LoadFont("Common Normal")
end

-- Simply Love's SL_WideScale, inlined so this file doesn't depend on it. Interpolates between
-- a 4:3 value and a 16:9 one by actual aspect ratio rather than snapping to one or the other.
local function GolfWideScale(ar4_3, ar16_9)
	local ar = _screen.w / _screen.h
	if ar <= 4/3 then return ar4_3 end
	if ar >= 16/9 then return ar16_9 end
	return ar4_3 + (ar16_9 - ar4_3) * ((ar - 4/3) / (16/9 - 4/3))
end

-- Names the host theme might use for its per-player gameplay score actor, in the Underlay.
-- We hide these while golf is active so the two scores don't sit on top of each other. Simply
-- Love uses "<pn>Score"; Arrow Cloud's fork adds "<pn>ScoreHardEx". A theme using none of
-- these just keeps its own score visible alongside the golf one -- degraded, not broken.
local SCORE_ACTOR_SUFFIXES = { "Score", "ScoreHardEx" }

-- ---------------------------------------------------------------------------------------
-- Stroke calculation

-- A note's cost is worked out in POINTS, then converted to a whole number of RAW STROKES --
-- and that per-note rounding is load-bearing. The server sums rounded whole strokes
-- (Math.round(points * 0.4) per note, in api/src/utils/scoring/golf.ts), so accumulating
-- fractional points here and dividing once at the end does NOT give the same answer: half-up
-- rounding biases each note upward slightly, which over a few hundred notes drifts the HUD
-- below the server by ~0.07 strokes. Round per note, exactly as the server does.
--
-- The timing error is floored to a whole millisecond, so every note landing in the same
-- millisecond costs the same.
--
--   e < 5ms         free -- covers hardware jitter
--   5..45ms         1.25 points per ms, steepening to 1.75 per ms past 23ms
--   > 45ms          slope starts at 2.5 per ms and tapers as 2.5 / (1 + d/60), d being the ms
--                   past 45 -- down to about 1.3 by 100ms. Cost still rises, just more slowly.
--   > 103.5ms       scores as a miss
--
-- Misses, dropped holds/rolls and hit mines all cost a flat MISS_STROKES (100), deliberately
-- worse than the worst reachable hit (65 raw strokes, at 103ms).
local FREE_MS  = 5      -- errors under this are free
local OOB_MS   = 103.5  -- past this a hit is scored as a miss
local MISS_POINTS = 250
local KNEE1_MS = 23     -- where the linear slope steepens
local KNEE2_MS = 45     -- where the taper takes over
local SLOPE1   = 1.25   -- points per ms below KNEE1
local SLOPE2   = 1.75   -- points per ms between the knees
local SLOPE3   = 2.5    -- points per ms at KNEE2, before the taper reduces it
local TAPER_MS = 60     -- larger = slower taper

-- Cost at KNEE2, where the two branches meet: 1.25*41 + 0.5*22 = 62.25. Deriving it rather
-- than hardcoding keeps the curve continuous if any slope or knee above is retuned.
local KNEE2_COST = SLOPE1 * (KNEE2_MS - FREE_MS + 1) + (SLOPE2 - SLOPE1) * (KNEE2_MS - KNEE1_MS)

-- Raw strokes per point, and the half-up rounding the server's Math.round() does for
-- non-negative values. math.floor(x + 0.5) matches it exactly; costs are never negative.
local RAW_PER_POINT = 0.4
local function toRaw(points)
	return math.floor(points * RAW_PER_POINT + 0.5)
end

-- Points for one note from its absolute timing error in ms; nil means a miss.
local function noteCost(ms)
	if ms == nil or ms > OOB_MS then return MISS_POINTS end
	if ms < FREE_MS then return 0 end

	local f = math.floor(ms)
	if f <= KNEE2_MS then
		return SLOPE1 * (f - FREE_MS + 1) + (SLOPE2 - SLOPE1) * math.max(0, f - KNEE1_MS)
	end
	return KNEE2_COST + SLOPE3 * TAPER_MS * math.log(1 + (f - KNEE2_MS) / TAPER_MS)
end

-- Raw strokes for a miss, a dropped hold or roll, or a hit mine. The server's
-- GOLF_MISS_STROKES; keep the two equal.
local MISS_STROKES = toRaw(MISS_POINTS)

-- Whole raw strokes for one note, from the engine's signed offset in seconds.
local function offsetCost(offsetSeconds)
	if offsetSeconds == nil then return MISS_STROKES end
	return toRaw(noteCost(math.abs(offsetSeconds) * 1000))
end

-- The most a hit can cost, which anchors the red end of the per-note color ramp.
local MAX_HIT_STROKES = toRaw(noteCost(OOB_MS))

-- Color ramp for per-note feedback: green at no cost, red at the worst a hit can cost (a miss
-- is above that ceiling, so it clamps to red).
local function strokeColor(strokes)
	if strokes <= 0 then return 0.2, 1, 0.2 end
	if strokes >= MAX_HIT_STROKES then return 1, 0.15, 0.15 end
	-- sqrt curve so yellow appears early and red ramps in faster
	local t = math.sqrt(clamp(strokes / MAX_HIT_STROKES, 0, 1))
	return 0.2 + 0.8 * t, 1 - 0.85 * t, 0.2 - 0.05 * t
end

-- ---------------------------------------------------------------------------------------
-- In-game display

-- Fallbacks for where the score sits, used only when the host theme's score actor can't be
-- found to measure. Matches Simply Love's ScreenGameplay underlay/PerPlayer/Score.lua.
local scorePos = {
	[PLAYER_1] = { x=(_screen.cx - clamp(_screen.w, 640, 854)/4.3),  y=56 },
	[PLAYER_2] = { x=(_screen.cx + clamp(_screen.w, 640, 854)/2.75), y=56 },
}

-- Likewise for the difficulty meter, which the par box covers.
local diffPos = {
	[PLAYER_1] = { x=(_screen.cx + -1 * GolfWideScale(292.5, 342.5)), y=56 },
	[PLAYER_2] = { x=(_screen.cx + 1 * GolfWideScale(292.5, 342.5)),  y=56 },
}

-- The host theme's score actor for this player, or nil. Used both to hide it and to borrow
-- its position so the golf score lands exactly where the player is already looking.
local function findScoreActor(pn, suffix)
	local screen = SCREENMAN:GetTopScreen()
	if not screen then return nil end
	if not hasMethod(screen, "GetChild") then return nil end
	local underlay = screen:GetChild("Underlay")
	if not hasMethod(underlay, "GetChild") then return nil end
	local actor = underlay:GetChild(pn .. suffix)
	if not hasMethod(actor, "visible") then return nil end
	return actor
end

local function setScoreVisible(pn, visible)
	for _, suffix in ipairs(SCORE_ACTOR_SUFFIXES) do
		local actor = findScoreActor(pn, suffix)
		if actor then actor:visible(visible) end
	end
end

local function makePlayerDisplay(pn)
	local player = (pn == "P1") and PLAYER_1 or PLAYER_2
	-- state.par is what gates everything: no par means this chart isn't a golf hole and the
	-- module leaves the screen's normal scoring completely alone.
	local state = { totalStrokes = 0, noteCount = 0, par = nil }

	-- Flash text goes to the right of P1's score, left of P2's score
	local flashOffsetX = (player == PLAYER_1) and 48 or -108

	-- Put this actor where the host theme's score is, falling back to Simply Love's coords.
	local function positionToScore(self, extraX)
		local realScore = findScoreActor(pn, "Score")
		if realScore then
			self:xy(realScore:GetX() + (extraX or 0), realScore:GetY())
		else
			self:xy(scorePos[player].x + (extraX or 0), scorePos[player].y)
		end
	end

	return Def.ActorFrame{
		Name="Golf"..pn,
		InitCommand=function(self) self:visible(false):diffusealpha(0) end,

		GolfResetCommand=function(self, params)
			state.totalStrokes = 0
			state.noteCount = 0
			state.par = params and params.par or nil

			if state.par then
				Golf.Scores[pn] = {
					strokes    = 0,
					notes      = 0,
					par        = state.par,
					-- so a reader can tell this result apart from a stale one
					songDir    = params.songDir,
					difficulty = params.difficulty,
				}
			else
				Golf.Scores[pn] = nil
			end

			self:playcommand("GolfUpdate")
		end,

		JudgmentMessageCommand=function(self, params)
			if params.Player ~= player then return end
			-- MessageCommands still fire while this frame is hidden, so an un-parred chart
			-- has to bail out here rather than relying on not being drawn.
			if not state.par then return end

			local strokes = nil

			-- A hold's judgment message carries BOTH its HoldNoteScore and the head tap's
			-- TapNoteScore (with no TapNoteOffset), so the HNS case has to come first or the
			-- head gets scored a second time.
			if params.HoldNoteScore then
				local hns = ToEnumShortString(params.HoldNoteScore)
				if hns == "LetGo" or hns == "MissedHold" then
					strokes = MISS_STROKES
				else
					return
				end

			elseif params.TapNoteScore then
				local tns = ToEnumShortString(params.TapNoteScore)
				if tns == "HitMine" then
					strokes = MISS_STROKES
				elseif tns == "AvoidMine" then
					return
				elseif tns == "Miss" then
					strokes = MISS_STROKES
					state.noteCount = state.noteCount + 1
				else
					strokes = offsetCost(params.TapNoteOffset)
					state.noteCount = state.noteCount + 1
				end
			end

			if strokes == nil then return end

			state.totalStrokes = state.totalStrokes + strokes

			Golf.Scores[pn].strokes = state.totalStrokes
			Golf.Scores[pn].notes = state.noteCount

			self:playcommand("GolfUpdate")

			-- Already whole raw strokes, so the readout needs no rounding of its own.
			local flashText = (strokes == 0) and "ACE" or ("+%d"):format(strokes)
			self:playcommand("GolfFlash", { text = flashText, strokes = strokes })
		end,

		-- Golf total, styled like the score it replaces but green
		GolfFont("numbers")..{
			InitCommand=function(self)
				self:valign(1):horizalign(right)
				self:zoom(0.5)
				self:diffuse(0.2, 0.8, 0.2, 1)
				self:settext("0")
			end,
			GolfPositionCommand=function(self) positionToScore(self) end,
			GolfUpdateCommand=function(self)
				self:settext(Golf.FormatScore(state.totalStrokes))
			end,
		},

		-- Per-note stroke flash next to the score
		LoadFont("Common Normal")..{
			InitCommand=function(self)
				self:valign(0):horizalign(right)
				self:zoom(1)
				self:diffuse(0.4, 0.75, 0.4, 1)
			end,
			GolfPositionCommand=function(self) positionToScore(self, flashOffsetX) end,
			GolfFlashCommand=function(self, params)
				self:finishtweening()
				self:settext(params.text)
				local r, g, b = strokeColor(params.strokes)
				self:diffuse(r, g, b, 1)
				self:sleep(0.4):linear(0.3):diffusealpha(0)
			end,
		},

		-- "Par" display covering the original difficulty meter
		Def.ActorFrame{
			GolfPositionCommand=function(self)
				self:xy(diffPos[player].x, diffPos[player].y)
			end,

			-- Green background quad (covers the original 30x30 difficulty quad)
			Def.Quad{
				InitCommand=function(self)
					self:zoomto(30, 30)
					self:diffuse(0.2, 0.8, 0.2, 1)
				end,
			},

			GolfFont("Bold")..{
				InitCommand=function(self)
					self:diffuse(Color.Black)
					self:zoom(0.4)
					self:y(-4)
				end,
				GolfUpdateCommand=function(self)
					self:settext(Golf.FormatPar(state.par))
				end,
			},

			GolfFont("Normal")..{
				InitCommand=function(self)
					self:diffuse(Color.Black)
					self:y(9.5)
					self:zoom(0.5)
					self:settext("Par")
				end,
			},
		},
	}
end

-- ---------------------------------------------------------------------------------------
-- Song wheel pars
--
-- The wheel's per-row actors are built from the theme's "MusicWheelItem Song NormalPart"
-- graphic, which a module can't edit. But the engine binds enough to get in from outside:
--
--   * ScreenSelectMusic:GetMusicWheel() hands back the wheel.
--   * WheelBase:GetWheelItem(i) hands back one of the *visible row actors* -- a fixed-size
--     recycled pool (NUM_WHEEL_ITEMS), not one actor per song.
--   * ActorFrame:AddChildFromPath(path) loads an actor from a file and parents it to a frame.
--   * When the wheel rebinds a row to a different song it builds a Message named "Set" and
--     dispatches it with HandleMessage, which propagates to every descendant (only
--     *broadcast* messages skip propagation). Its params carry the Song.
--
-- So: inject one badge actor into each row of the pool, once per visit to the screen, and
-- every subsequent scroll hands that badge its row's Song for free. Injecting into the pool
-- rather than per song is also why this stays cheap -- it's ~15 actors regardless of library
-- size.
local BADGE_NAME = "GolfParBadge"
local badgePath = THEME:GetCurrentThemeDirectory() .. "Modules/Golf/ParBadge.lua"

-- GetWheelItem errors (rather than returning nil) past the end of the visible pool, and
-- GetNumItems counts the song list, not the pool -- so probe with pcall and remember the size.
local wheelPoolSize = nil

local function getWheelItem(wheel, i)
	local ok, item = pcall(function() return wheel:GetWheelItem(i) end)
	if ok and hasMethod(item, "AddChildFromPath") then return item end
	return nil
end

local function injectWheelBadges()
	local screen = SCREENMAN:GetTopScreen()
	if not hasMethod(screen, "GetMusicWheel") then
		debugPrint("no GetMusicWheel on this screen; skipping wheel badges")
		return
	end

	local ok, wheel = pcall(function() return screen:GetMusicWheel() end)
	if not ok or not hasMethod(wheel, "GetWheelItem") then
		debugPrint("GetMusicWheel returned nothing usable; skipping wheel badges")
		return
	end

	local injected, skipped = 0, 0
	local i = 0
	while true do
		if wheelPoolSize and i >= wheelPoolSize then break end

		local item = getWheelItem(wheel, i)
		if not item then
			-- first failure marks the end of the pool
			wheelPoolSize = wheelPoolSize or i
			break
		end

		if not hasMethod(item, "GetChild") then
			skipped = skipped + 1
		elseif hasMethod(item:GetChild(BADGE_NAME), "visible") then
			-- already injected on an earlier visit; the pool survives screen changes
			skipped = skipped + 1
		elseif item:AddChildFromPath(badgePath) then
			injected = injected + 1
		else
			skipped = skipped + 1
			debugPrint("AddChildFromPath failed for row " .. i .. " (" .. badgePath .. ")")
		end

		i = i + 1
	end

	debugPrint("wheel rows=" .. tostring(wheelPoolSize or i) ..
		" injected=" .. injected .. " already-present/skipped=" .. skipped)

	-- A freshly injected badge is blank until something hands it a Song, and the only thing
	-- that does is the "Set" message the wheel dispatches when it rebinds a row -- which has
	-- usually already happened by the time we get here. So badges fill in on the player's
	-- first wheel movement rather than appearing immediately.
	--
	-- Forcing a rebind by moving the wheel is NOT an option, even though it works:
	-- MusicWheel::ChangeMusic calls m_soundChangeMusic.Play(), so the nudge fired the
	-- change-song sound on every single entry to the song wheel. The engine exposes no silent
	-- rebuild to Lua (ReloadSongList, RebuildWheelItems and SetOpenSection are all C++-only),
	-- so there is no quiet way to force it. Silence beats immediacy.
end

-- ---------------------------------------------------------------------------------------
-- Module entry points

local gameplay = Def.ActorFrame{
	ModuleCommand=function(self)
		self:GetChild("GolfP1"):visible(false)
		self:GetChild("GolfP2"):visible(false)

		Golf.ClearScores()

		local song = GAMESTATE:GetCurrentSong()
		if not song then return end

		for _, player in ipairs(GAMESTATE:GetHumanPlayers()) do
			local pn = ToEnumShortString(player)
			local steps = GAMESTATE:GetCurrentSteps(player)
			local par = Golf.GetPar(song, steps)

			-- Charts with no par defined aren't golf holes: don't hide the real score and
			-- don't draw any of this. Checked per player because in versus the two sides can
			-- be on different difficulties, only one of which is parred.
			if par then
				setScoreVisible(pn, false)

				local golfAf = self:GetChild("Golf"..pn)
				golfAf:visible(true)
				golfAf:playcommand("GolfPosition")
				golfAf:playcommand("GolfReset", {
					par        = par,
					songDir    = song:GetSongDir(),
					difficulty = steps and steps:GetDifficulty(),
				})
				-- reset the alpha explicitly; on the second and later songs of a set this
				-- frame is still sitting at the 1 the last fade-in left it on
				golfAf:finishtweening():diffusealpha(0):linear(0.4):diffusealpha(1)
			else
				self:GetChild("Golf"..pn):playcommand("GolfReset")
			end
		end
	end,

	makePlayerDisplay("P1"),
	makePlayerDisplay("P2"),
}

local selectMusic = Def.ActorFrame{
	ModuleCommand=function(self)
		-- Pick up Golf.ini edits made while the game is running.
		Golf.ClearCache()
		injectWheelBadges()
	end,
}

return {
	ScreenGameplay = gameplay,
	ScreenSelectMusic = selectMusic,
}
