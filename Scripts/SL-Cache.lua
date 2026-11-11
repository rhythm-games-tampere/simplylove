-- Persistent score cache (simplylove.db) keyed by player name and chart hash.
local sqlite3 = sqlite3 -- Provided by lsqlite3

CacheType = { EX = "ex", ITG = "itg", Golf = "golf" }
CacheSource = { Local = "local", GrooveStats = "groovestats", ArrowCloud = "arrowcloud" }

local Db = sqlite3 and sqlite3.open("simplylove.db")
local SetStmt, GetStmt, DeleteStmt
if Db then
	Db:exec([[
		CREATE TABLE IF NOT EXISTS score_cache (
			player TEXT NOT NULL,
			hash TEXT NOT NULL,
			score TEXT NOT NULL,
			score_type TEXT NOT NULL,
			score_source TEXT NOT NULL,
			score_color TEXT,
			UNIQUE(player, hash, score_source, score_type) ON CONFLICT REPLACE
		);
	]])
	Db:exec("PRAGMA journal_mode=WAL;")
	Db:exec("PRAGMA synchronous=NORMAL;")
	SetStmt = Db:prepare("INSERT INTO score_cache(player, hash, score_type, score_source, score, score_color) VALUES (?, ?, ?, ?, ?, ?)")
	GetStmt = Db:prepare("SELECT score, score_color FROM score_cache WHERE player=? AND hash=? AND score_type=? AND score_source=?")
	DeleteStmt = Db:prepare("DELETE FROM score_cache WHERE player=? AND hash=? AND score_type=? AND score_source=?")
end
if not (Db and SetStmt and GetStmt and DeleteStmt) then
	lua.Warn("Initializing SL cache failed")
	Db = nil
end

---@param player string
---@param hash string
---@param score_type string CacheType
---@param score_source string CacheSource
---@param score string
---@param score_color string?
function CacheSet(player, hash, score_type, score_source, score, score_color)
	if not Db then return end
	SetStmt:bind_values(player, hash, score_type, score_source, score, score_color)
	SetStmt:step()
	SetStmt:reset()
end

---@param player string
---@param hash string
---@param score_type string CacheType
---@param score_source string CacheSource
---@return string?, string?
function CacheGet(player, hash, score_type, score_source)
	if not Db then return nil, nil end
	GetStmt:bind_values(player, hash, score_type, score_source)
	local score, score_color
	if GetStmt:step() == sqlite3.ROW then
		score, score_color = GetStmt:get_value(0), GetStmt:get_value(1)
	end
	GetStmt:reset()
	return score, score_color
end

---@param player string
---@param hash string
---@param score_type string CacheType
---@param score_source string CacheSource
function CacheDelete(player, hash, score_type, score_source)
	if not Db then return end
	DeleteStmt:bind_values(player, hash, score_type, score_source)
	DeleteStmt:step()
	DeleteStmt:reset()
end

-- Runs fn inside one transaction.
function CacheBatch(fn)
	if Db then Db:exec("BEGIN") end
	fn()
	if Db then Db:exec("COMMIT") end
end
