local player = Var "Player"
local pn = ToEnumShortString(player)
local mods = SL[pn].ActiveModifiers
local sprite
local coupleSprite
local underlay

-- Opacity (0..1) of the blue Fantastic (W1 in normal mode, or W0 with the FA+ Window).
local blueOpacity      = tonumber( (tostring(mods.FantasticOpacity or "100%"):gsub("%%","")) ) / 100
-- Opacity (0..1) of the white "safeguard" Fantastic drawn beneath the blue near the edge of the W0 window.
local safeguardOpacity = tonumber( (tostring(mods.SafeguardOpacity or "0%"):gsub("%%","")) ) / 100

local style = GAMESTATE:GetCurrentStyle()
local styletype = style and style:GetStyleType() or nil

------------------------------------------------------------
-- A profile might ask for a judgment graphic that doesn't exist
-- If so, use the first available Judgment graphic
-- If that fails too, fail gracefully and do nothing
local available_judgments = GetJudgmentGraphics()

local file_to_load = (FindInTable(mods.JudgmentGraphic, available_judgments) ~= nil and mods.JudgmentGraphic or available_judgments[1]) or "None"

if file_to_load == "None" then
	return Def.Actor{
		InitCommand=function(self) self:visible(false) end,
		JudgmentMessageCommand=function(self,param)
			if param.Player ~= player then return end

			if ToEnumShortString(param.TapNoteScore) == "W1" and mods.ShowFaPlusWindow then
				local is_W0 = IsW0TightJudgment(param, player) or (not mods.TighterFantasticWindow and IsW0Judgment(param, player))
				if not is_W0 and not IsAutoplay(player) then
					frame = 1
					if param.Notes ~= nil then
						for col,tapnote in pairs(param.Notes) do
							local tnt = ToEnumShortString(tapnote:GetTapNoteType())
							if tnt == "Tap" or tnt == "HoldHead" or tnt == "Lift" then
								GetPlayerAF(pn):GetChild("NoteField"):did_tap_note(col, "TapNoteScore_W1", --[[bright]] true)
							end
						end
					elseif param.TapNote ~= nil then
						if tnt == "Tap" or tnt == "HoldHead" or tnt == "Lift" then
							GetPlayerAF(pn):GetChild("NoteField"):did_tap_note(col, "TapNoteScore_W1", --[[bright]] true)
						end
					end
				end
			end
	  end,
		EarlyHitMessageCommand=function(self, param)
			if param.Player ~= player then return end
	
			if not mods.HideEarlyDecentWayOffFlash then
				GetPlayerAF(pn):GetChild("NoteField"):did_tap_note(param.Column + 1, param.TapNoteScore, --[[bright]] false)
			end
		end
	}
end

------------------------------------------------------------

local TNSFrames = {
	TapNoteScore_W1 = 0,
	TapNoteScore_W2 = 1,
	TapNoteScore_W3 = 2,
	TapNoteScore_W4 = 3,
	TapNoteScore_W5 = 4,
	TapNoteScore_Miss = 5,
	TapNoteScore_CheckpointHit = -1,
	TapNoteScore_CheckpointMiss = 5
}

-- Most judgment sprite sheets have 12 or 14 frames; 6/7 for early judgments, 6/7 for late.
-- Some (the original 3.9 sheet, for example) don't distinguish early/late and only have 6/7.
-- Given a 0-indexed base frame, return the actual state to display.
local function ExpandFrame(base, isEarly)
	if sprite:GetNumStates() == 12 or sprite:GetNumStates() == 14 then
		base = base * 2
		if not isEarly then base = base + 1 end
	end
	return base
end

-- For a W1 (Fantastic) judgment when the FA+ white window graphic is available, split the top
-- window into three bands around the blue W0 window:
--   * pure blue core             (|offset| <= core)
--   * safeguard band at the edge (core < |offset| <= w0_outer) -> blue drawn over white
--   * white window               (|offset| > w0_outer)
-- The safeguard band is 5ms wide normally, 3ms with the 10ms Blue Window.
-- Safeguard Opacity 0% disables the band entirely: the whole W0 window shows plain blue.
-- Returns: frame (0 = blue, 1 = white), showingBlue, isSafeguard.
local function FantasticBand(param)
	local ms       = math.abs(param.TapNoteOffset) * 1000
	local w0_outer = GetTimingWindow(1, "FA+", mods.TighterFantasticWindow) * 1000
	local band     = mods.TighterFantasticWindow and 2 or 5
	local core     = math.max(0, w0_outer - band)

	if ms > w0_outer then
		return 1, false, false     -- outside the FA+ window: show the white window
	elseif safeguardOpacity > 0 and ms > core then
		return 0, true, true       -- safeguard band: blue on top, white underneath
	else
		return 0, true, false      -- blue window: display the blue Fantastic as-is
	end
end

return Def.ActorFrame{
	Name="Player Judgment",
	InitCommand=function(self)
		local kids = self:GetChildren()
		sprite = kids.JudgmentWithOffsets
		underlay = kids.SafeguardUnderlay
	end,
	EarlyHitMessageCommand=function(self, param)
		if param.Player ~= player then return end

		local frame = TNSFrames[ param.TapNoteScore ]
		if not frame then return end

		if not mods.HideEarlyDecentWayOffFlash then
			GetPlayerAF(pn):GetChild("NoteField"):did_tap_note(param.Column + 1, param.TapNoteScore, --[[bright]] false)
		end

		if not mods.HideEarlyDecentWayOffJudgments then
			local tns = ToEnumShortString(param.TapNoteScore)
			local showingBlue = (tns == "W1")
			local isSafeguard = false

			-- If the judgment font contains a graphic for the additional white fantastic window...
			if sprite:GetNumStates() == 7 or sprite:GetNumStates() == 14 then
				if tns == "W1" then
					-- Treat Autoplay specially. The TNS might be out of the range, but
					-- it's a nicer experience to always just display the top window graphic regardless.
					if mods.ShowFaPlusWindow and not IsAutoplay(player) then
						frame, showingBlue, isSafeguard = FantasticBand(param)
					end
					-- We don't need to adjust the top window otherwise.
				else
                    -- Everything outside of W1 needs to be shifted down a row if not in FA+ mode.
                    -- Some people might be using 2x7s in FA+ mode (by copying ITG graphics to FA+).
                    -- Don't need to shift in that case.
					frame = frame + 1
				end
			end

			self:playcommand("Reset")

			-- early hits are always "early", so never bump to the late frame
			sprite:visible(true):setstate(ExpandFrame(frame, true))

			if isSafeguard then
				-- Safeguard band: white Fantastic underneath, blue on top at the Safeguard Opacity,
				-- with Fantastic Opacity scaling the composite (kept visible when it's 0%).
				local scale = (blueOpacity == 0) and 1 or blueOpacity
				sprite:diffusealpha(safeguardOpacity * scale)
				underlay:visible(true):setstate(ExpandFrame(1, true)):diffusealpha(scale)
			else
				sprite:diffusealpha(showingBlue and blueOpacity or 1)
			end

			if mods.JudgmentTilt then
				-- How much to rotate.
				-- We cap it at 50ms (15px) since anything after likely to be too distracting.
				local offset = math.min(math.abs(param.TapNoteOffset), 0.050) * 300 * mods.TiltMultiplier
				-- Which direction to rotate.
				local direction = param.TapNoteOffset < 0 and -1 or 1
				sprite:rotationz(direction * offset)
				if isSafeguard then underlay:rotationz(direction * offset) end
			end
			-- this should match the custom JudgmentTween() from SL for 3.95
			sprite:zoom(0.8):decelerate(0.1):zoom(0.75):sleep(0.6):accelerate(0.2):zoom(0)
			if isSafeguard then
				underlay:zoom(0.8):decelerate(0.1):zoom(0.75):sleep(0.6):accelerate(0.2):zoom(0)
			end
		end
	end,
	JudgmentMessageCommand=function(self, param)
		if param.Player ~= player then return end
		if not param.TapNoteScore then return end
		if param.HoldNoteScore then return end

		local tns = ToEnumShortString(param.TapNoteScore)
		if param.EarlyTapNoteScore ~= nil then
			local earlyTns = ToEnumShortString(param.EarlyTapNoteScore)

			if earlyTns ~= "None" then
				if tns == "W4" or tns == "W5" then
                    return
                end
			end
		end

		-- "frame" is the number we'll use to display the proper portion of the judgment sprite sheet
		-- Sprite actors expect frames to be 0-indexed when using setstate() (not 1-indexed as is more common in Lua)
		-- an early W1 judgment would be frame 0, a late W2 judgment would be frame 3, and so on
		local frame = TNSFrames[ param.TapNoteScore ]
		if not frame then return end

		-- Whether we're displaying the blue Fantastic (so the Fantastic Opacity mod applies), and
		-- whether we should draw the white "safeguard" Fantastic beneath the blue near the W0 edge.
		local showingBlue = (tns == "W1")
		local isSafeguard = false

		-- If the judgment font contains a graphic for the additional white fantastic window...
		if sprite:GetNumStates() == 7 or sprite:GetNumStates() == 14 then
			if tns == "W1" then
				-- Treat Autoplay specially. The TNS might be out of the range, but
				-- it's a nicer experience to always just display the top window graphic regardless.
				-- This technically causes a discrepency on the histogram, but it's likely okay.
				if mods.ShowFaPlusWindow and not IsAutoplay(player) then
					frame, showingBlue, isSafeguard = FantasticBand(param)

					-- outside the FA+ window (white window): flash the note columns bright
					if not showingBlue then
						for col,tapnote in pairs(param.Notes) do
							local tnt = ToEnumShortString(tapnote:GetTapNoteType())
							if tnt == "Tap" or tnt == "HoldHead" or tnt == "Lift" then
								GetPlayerAF(pn):GetChild("NoteField"):did_tap_note(col, "TapNoteScore_W1", --[[bright]] true)
							end
						end
					end
				end
				-- We don't need to adjust the top window otherwise.
			else
				-- Everything outside of W1 needs to be shifted down a row if not in FA+ mode.
				-- Some people might be using 2x7s in FA+ mode (by copying ITG graphics to FA+).
				-- In that case, we need to shift the Way Off down to a Miss
				frame = frame + 1
			end
		end


		self:playcommand("Reset")

		sprite:visible(true):setstate(ExpandFrame(frame, param.Early))

		if isSafeguard then
			-- Safeguard band: white Fantastic (frame 1) underneath at 100%, blue Fantastic
			-- (frame 0, already set above) on top at the Safeguard Opacity. Fantastic Opacity
			-- then scales the whole composite -- except when it's 0%, where it would erase the
			-- band entirely, so we leave the band un-scaled in that case.
			local scale = (blueOpacity == 0) and 1 or blueOpacity
			sprite:diffusealpha(safeguardOpacity * scale)
			underlay:visible(true):setstate(ExpandFrame(1, param.Early)):diffusealpha(scale)
		else
			-- The Fantastic Opacity mod only dims the lone blue Fantastic; everything else stays fully opaque.
			sprite:diffusealpha(showingBlue and blueOpacity or 1)
		end

		if mods.JudgmentTilt then
			if tns ~= "Miss" then
				-- How much to rotate.
				-- We cap it at 50ms (15px) since anything after likely to be too distracting.
				local offset = math.min(math.abs(param.TapNoteOffset), 0.050) * 300 * mods.TiltMultiplier
				-- Which direction to rotate.
				local direction = param.TapNoteOffset < 0 and -1 or 1
				sprite:rotationz(direction * offset)
				if isSafeguard then underlay:rotationz(direction * offset) end
			else
				-- Reset rotations on misses so it doesn't use the previous note's offset.
				sprite:rotationz(0)
			end
		end
		-- this should match the custom JudgmentTween() from SL for 3.95
		sprite:zoom(0.8):decelerate(0.1):zoom(0.75):sleep(0.6):accelerate(0.2):zoom(0)
		if isSafeguard then
			underlay:zoom(0.8):decelerate(0.1):zoom(0.75):sleep(0.6):accelerate(0.2):zoom(0)
		end
	end,

	-- The white "safeguard" Fantastic. Declared before JudgmentWithOffsets so it draws behind it.
	-- It mirrors the main sprite's setup and is only made visible within the safeguard band.
	Def.Sprite{
		Name="SafeguardUnderlay",
		InitCommand=function(self)
			self:animate(false):visible(false)

			if string.match(tostring(SCREENMAN:GetTopScreen()), "ScreenEdit") then
				self:Load( THEME:GetPathG("", "_judgments/Love") )
			else
				self:Load( THEME:GetPathG("", "_judgments/" .. file_to_load) )
			end
			if styletype == "StyleType_TwoPlayersSharedSides" then
				if player == PLAYER_1 then
					self:addy(10)
					self:diffuse(Color.Blue)
				else
					self:addy(60)
					self:diffuse(Color.Red)
				end
			end
		end,
		ResetCommand=function(self) self:finishtweening():stopeffect():visible(false):diffusealpha(1) end
	},
	Def.Sprite{
		Name="JudgmentWithOffsets",
		InitCommand=function(self)
			-- animate(false) is needed so that this Sprite does not automatically
			-- animate its way through all available frames; we want to control which
			-- frame displays based on what judgment the player earns
			self:animate(false):visible(false)

			-- if we are on ScreenEdit, judgment graphic is always "Love"
			-- because ScreenEdit is a mess and not worth bothering with.
			if string.match(tostring(SCREENMAN:GetTopScreen()), "ScreenEdit") then
				self:Load( THEME:GetPathG("", "_judgments/Love") )

			else
				self:Load( THEME:GetPathG("", "_judgments/" .. file_to_load) )
			end
			-- local mini = mods.Mini:gsub("%%","") / 100
			-- self:addx((mods.NoteFieldOffsetX * (1 + mini)) * 2)
			-- self:addy((mods.NoteFieldOffsetY * (1 + mini)) * 2)
			if styletype == "StyleType_TwoPlayersSharedSides" then
				if player == PLAYER_1 then
					self:addy(10)
					self:diffuse(Color.Blue)
				else
					self:addy(60)
					self:diffuse(Color.Red)
				end
			end
		end,
		ResetCommand=function(self) self:finishtweening():stopeffect():visible(false):diffusealpha(1) end
	}
}
