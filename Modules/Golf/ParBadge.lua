-- One "PAR n" badge for a single row of the song wheel.
--
-- Not a module. It lives in a subdirectory on purpose: Simply Love's module loader scans
-- Modules/ for files whose extension is "lua" and treats whatever each returns as a
-- ScreenName -> Actor map, so a bare actor file sitting beside GolfScoring.lua would be
-- mangled into junk entries. A directory entry ("Golf") fails that extension test and is
-- skipped, leaving this reachable only by the explicit path GolfScoring.lua passes to
-- AddChildFromPath.
--
-- GolfScoring.lua injects one of these into each visible row actor of the wheel's recycled
-- pool, once per visit to ScreenSelectMusic. The wheel then dispatches a "Set" message
-- through each row whenever it rebinds to a different song, and because that's a direct
-- message rather than a broadcast, it propagates down to this actor -- carrying the Song in
-- its params. That's the whole trick: there's no other Lua-visible route from a wheel row to
-- the song it's currently displaying (WheelItemBase exposes GetText, not the Song).

-- luacheck: globals Golf Def LoadFont color _screen

-- Horizontal placement, in the row's own coordinate space, where x=0 is the row's left edge.
-- Simply Love's wheel row is _screen.w/2.125 wide and its own per-row actors right-align
-- against roughly _screen.w/2.15, so this parks the badge just inside the right edge.
-- TUNABLE: if the badge lands wrong on another theme, this is the line to change.
local BADGE_X = _screen.w / 2.15 - 6

return Def.BitmapText{
	Name="GolfParBadge",
	Font="Common Normal",
	Text="",
	InitCommand=function(self)
		self:visible(false):horizalign(right):zoom(0.75)
		self:x(BADGE_X)
		self:diffuse(color("#7CF47C"))
	end,

	-- Fired by the wheel every time this row is bound to a different song. params.Song is nil
	-- for group headers, courses and the random/sort rows, which correctly yields no par.
	SetCommand=function(self, params)
		local par = Golf and params and params.Song and Golf.GetPar(params.Song)

		if par then
			self:settext("PAR " .. Golf.FormatPar(par)):visible(true)
		else
			self:visible(false)
		end
	end,
}
