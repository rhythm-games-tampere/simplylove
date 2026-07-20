local player = Var "Player"
local pn = ToEnumShortString(player)
local mods = SL[pn].ActiveModifiers
local sprite
local safeguardSprite
local coupleSprite
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

return Def.ActorFrame{
	Name="Player Judgment",
	InitCommand=function(self)
		local kids = self:GetChildren()
		sprite = kids.JudgmentWithOffsets
		safeguardSprite = kids.JudgmentSafeguard
	end,
	EarlyHitMessageCommand=function(self, param)
		if param.Player ~= player then return end

		local frame = TNSFrames[ param.TapNoteScore ]
		if not frame then return end

		if not mods.HideEarlyDecentWayOffFlash then
			GetPlayerAF(pn):GetChild("NoteField"):did_tap_note(param.Column + 1, param.TapNoteScore, --[[bright]] false)
		end

		if not mods.HideEarlyDecentWayOffJudgments then
			-- If the judgment font contains a graphic for the additional white fantastic window...
			if sprite:GetNumStates() == 7 or sprite:GetNumStates() == 14 then
				if ToEnumShortString(param.TapNoteScore) == "W1" then
					if mods.ShowFaPlusWindow then
						-- If this W1 judgment fell outside of the FA+ window, show the white window
						--
						-- Treat Autoplay specially. The TNS might be out of the range, but
						-- it's a nicer experience to always just display the top window graphic regardless.
						-- This technically causes a discrepency on the histogram, but it's likely okay.
						if not IsW0Judgment(param, player) and not IsAutoplay(player) then
							frame = 1
						end
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

			-- most judgment sprite sheets have 12 or 14 frames; 6/7 for early judgments, 6/7 for late judgments
			-- some (the original 3.9 judgment sprite sheet for example) do not visibly distinguish
			-- early/late judgments, and thus only have 6/7 frames
			if sprite:GetNumStates() == 12 or sprite:GetNumStates() == 14 then
				frame = frame * 2
			end

			sprite:visible(true):setstate(frame)

			if mods.JudgmentTilt then
				-- How much to rotate.
				-- We cap it at 50ms (15px) since anything after likely to be too distracting.
				local offset = math.min(math.abs(param.TapNoteOffset), 0.050) * 300 * mods.TiltMultiplier
				-- Which direction to rotate.
				local direction = param.TapNoteOffset < 0 and -1 or 1
				sprite:rotationz(direction * offset)
			end
			-- this should match the custom JudgmentTween() from SL for 3.95
			sprite:zoom(0.8):decelerate(0.1):zoom(0.75):sleep(0.6):accelerate(0.2):zoom(0)
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

		-- sprite_alpha lets us fade the highest judgment by a player-chosen percentage
		-- (0% = fully invisible, 100% = fully opaque), or fade it to preview a
		-- near-miss Fantastic as a translucent guideline
		local sprite_alpha = 1
		local highest_opacity_string = (mods.FantasticOpacity or "100%"):gsub("%%", "")
		local highest_opacity_pct = tonumber(highest_opacity_string) or 100
		local highest_alpha = highest_opacity_pct / 100

		-- safeguard_alpha controls how visible the near-miss white Fantastic preview is
		-- (0% = never shown, 100% = fully opaque)
		local safeguard_opacity_string = (mods.SafeguardOpacity or "0%"):gsub("%%", "")
		local safeguard_opacity_pct = tonumber(safeguard_opacity_string) or 0
		local safeguard_alpha = safeguard_opacity_pct / 100

		-- show_safeguard/safeguard_frame drive a second sprite ("safeguardSprite") that gets
		-- drawn underneath the blue Fantastic to preview the white Fantastic behind it,
		-- rather than replacing the blue frame outright.
		local show_safeguard = false
		local safeguard_frame = 1

		-- If the judgment font contains a graphic for the additional white fantastic window...
		if sprite:GetNumStates() == 7 or sprite:GetNumStates() == 14 then
			if tns == "W1" then
				if mods.ShowFaPlusWindow then
					-- frame 0 is the "blue" Fantastic (the highest judgment, closest to 0 offset)
					-- frame 1 is the "white" Fantastic (the second-highest judgment, further from 0
					-- but still within the W1/Fantastic window)
					--
					-- Treat Autoplay specially. The TNS might be out of the range, but
					-- it's a nicer experience to always just display the top window graphic regardless.
					-- This technically causes a discrepency on the histogram, but it's likely okay.
					local offset = math.abs(param.TapNoteOffset)
					local prefs = SL.Preferences["FA+"]
					local scale = PREFSMAN:GetPreference("TimingWindowScale")
					local blue_boundary = 0.010 * scale + prefs["TimingWindowAdd"]
					-- The safeguard previews the upcoming white Fantastic in the last few ms
					-- before the player falls out of the blue window, not after.
					local guideline_width = 0.003
					local guideline_start = blue_boundary - guideline_width

					if offset > blue_boundary and not IsAutoplay(player) then
						-- Genuinely outside the blue window: white Fantastic, fully opaque.
						frame = 1

						for col,tapnote in pairs(param.Notes) do
							local tnt = ToEnumShortString(tapnote:GetTapNoteType())
							if tnt == "Tap" or tnt == "HoldHead" or tnt == "Lift" then
								GetPlayerAF(pn):GetChild("NoteField"):did_tap_note(col, "TapNoteScore_W1", --[[bright]] true)
							end
						end
					else
						-- Still inside the blue window: keep showing the blue Fantastic (frame 0).
						sprite_alpha = highest_alpha

						if safeguard_alpha > 0 and offset > guideline_start and not IsAutoplay(player) then
							-- Close enough to the edge to warn the player they're about to lose it:
							-- draw the white Fantastic on top of the blue one at reduced alpha.
							show_safeguard = true
						end
					end
				else
					sprite_alpha = highest_alpha
				end
				-- We don't need to adjust the top window otherwise.
			else
				-- Everything outside of W1 needs to be shifted down a row if not in FA+ mode.
				-- Some people might be using 2x7s in FA+ mode (by copying ITG graphics to FA+).
				-- In that case, we need to shift the Way Off down to a Miss
				frame = frame + 1
			end
		elseif tns == "W1" then
			sprite_alpha = highest_alpha
		end


		-- most judgment sprite sheets have 12 or 14 frames; 6/7 for early judgments, 6/7 for late judgments
		-- some (the original 3.9 judgment sprite sheet for example) do not visibly distinguish
		-- early/late judgments, and thus only have 6/7 frames
		if sprite:GetNumStates() == 12 or sprite:GetNumStates() == 14 then
			frame = frame * 2
			safeguard_frame = safeguard_frame * 2
			if not param.Early then
				frame = frame + 1
				safeguard_frame = safeguard_frame + 1
			end
		end

		self:playcommand("Reset")

		sprite:visible(true):setstate(frame)
		sprite:diffusealpha(sprite_alpha)

		if show_safeguard then
			safeguardSprite:visible(true):setstate(safeguard_frame)
			safeguardSprite:diffusealpha(safeguard_alpha)
		end

		if mods.JudgmentTilt then
			if tns ~= "Miss" then
				-- How much to rotate.
				-- We cap it at 50ms (15px) since anything after likely to be too distracting.
				local offset = math.min(math.abs(param.TapNoteOffset), 0.050) * 300 * mods.TiltMultiplier
				-- Which direction to rotate.
				local direction = param.TapNoteOffset < 0 and -1 or 1
				sprite:rotationz(direction * offset)
				if show_safeguard then safeguardSprite:rotationz(direction * offset) end
			else
				-- Reset rotations on misses so it doesn't use the previous note's offset.
				sprite:rotationz(0)
			end
		end
		-- this should match the custom JudgmentTween() from SL for 3.95
		sprite:zoom(0.8):decelerate(0.1):zoom(0.75):sleep(0.6):accelerate(0.2):zoom(0)
		if show_safeguard then
			safeguardSprite:zoom(0.8):decelerate(0.1):zoom(0.75):sleep(0.6):accelerate(0.2):zoom(0)
		end
	end,

	-- Drawn before (and therefore underneath) JudgmentWithOffsets so the white Fantastic
	-- safeguard preview can be layered beneath the blue Fantastic instead of replacing it.
	Def.Sprite{
		Name="JudgmentSafeguard",
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
		ResetCommand=function(self) self:finishtweening():stopeffect():visible(false) end
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
		ResetCommand=function(self) self:finishtweening():stopeffect():visible(false) end
	}
}
