local af = Def.ActorFrame{}

-- darken the entire screen slightly
af[#af+1] = Def.Quad{
	InitCommand=function(self) self:FullScreen():diffuse(0,0,0,0) end,
	OnCommand=function(self) self:accelerate(0.5):diffusealpha(0.5) end,
	OffCommand=function(self) self:accelerate(0.5):diffusealpha(0) end
}

-- Intructions BG
af[#af+1] = Def.Quad {
	InitCommand=function(self) self:xy(_screen.cx, _screen.cy-40):zoomto(_screen.w*0.75, _screen.h*0.25):diffuse(GetCurrentColor()) end
}
-- white border
af[#af+1] = Border(_screen.w*0.75, _screen.cy*0.5, 2) .. {
	InitCommand=function(self) self:xy(_screen.cx, _screen.cy-40) end
}


-- Text Entry BG
af[#af+1] = Def.Quad {
	InitCommand=function(self) self:xy(_screen.cx, _screen.cy+16):zoomto(_screen.w*0.75, 40):diffuse(0,0,0,1) end
}
-- white border
af[#af+1] = Border(_screen.w*0.75, 40, 2)..{
	InitCommand=function(self) self:xy(_screen.cx, _screen.cy+16) end
}

-- When creating a new local profile, the engine prefills the name with "NewProfileDefaultName" + a number.
-- Reload the prompt with an empty answer instead. Reloading replaces the engine's name validation,
-- so the same checks are done here. Back/Esc still cancels as before.
local profile_question = THEME:GetString("ScreenOptionsManageProfiles", "Enter a name for the profile.")
local default_name = THEME:GetString("ScreenOptionsManageProfiles", "NewProfileDefaultName")
local cleared = false

local ProfileNameTaken = function(name)
	for i=0, PROFILEMAN:GetNumLocalProfiles()-1 do
		if PROFILEMAN:GetLocalProfileFromIndex(i):GetDisplayName() == name then return true end
	end
	return false
end

af[#af+1] = Def.Actor{
	-- ScreenTextEntry only sets the question and answer text after OnCommand has run, so check on the next update
	OnCommand=function(self)
		if not cleared then self:queuecommand("ClearName") end
	end,
	OffCommand=function(self) cleared = false end,
	ClearNameCommand=function(self)
		local screen = SCREENMAN:GetTopScreen()
		local question = screen:GetChild("Question")
		local answer = screen:GetChild("Answer")

		-- an empty EditLocalProfileID means a new profile; renaming an existing one sets it
		if not (GAMESTATE:GetEditLocalProfileID() == ""
		and question and question:GetText():find(profile_question, 1, true)
		and answer and answer:GetText():find(default_name, 1, true) == 1)
		then
			return
		end

		cleared = true
		screen:Load({
			Question=profile_question,
			InitialAnswer="",
			MaxInputLength=32,
			Validate=function(answer)
				if answer:match("^%s*$") then
					return false, THEME:GetString("ScreenEditMenu", "Profile name cannot be blank.")
				end
				if ProfileNameTaken(answer) then
					return false, THEME:GetString("ScreenEditMenu", "The name you chose conflicts with another profile. Please use a different name.")
				end
				return true, ""
			end,
			-- same characters the engine allows: printable ASCII except quotes
			ValidateAppend=function(answer, append)
				return not append:find("[^\32-\126]") and not append:find("['\"]")
			end,
		})
	end
}

return af