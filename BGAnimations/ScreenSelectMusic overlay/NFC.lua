local frame, screen, uid, bindingPlayer
local active = false

local sideForButton = {
	Left = PLAYER_1,
	MenuLeft = PLAYER_1,
	Right = PLAYER_2,
	MenuRight = PLAYER_2,
}

local function text(value)
	frame:GetChild("Text"):settext(value)
end

local function close()
	active = false
	uid, bindingPlayer = nil, nil
	frame:visible(false)

	for pn in ivalues(PlayerNumber) do
		SCREENMAN:set_input_redirected(pn, false)
	end

	local timer = screen:GetChild("Timer")
	if timer and PREFSMAN:GetPreference("MenuTimer") then
		timer:start()
	end
end

local function show()
	if active or not screen.CanUseNFC or not screen:CanUseNFC() then
		return false
	end

	for pn in ivalues(PlayerNumber) do
		if SCREENMAN:get_input_redirected(pn) then
			return false
		end
	end

	active = true
	frame:visible(true)
	screen:GetMusicWheel():Move(0)

	for pn in ivalues(PlayerNumber) do
		SCREENMAN:set_input_redirected(pn, true)
	end

	local timer = screen:GetChild("Timer")
	if timer then timer:pause() end

	return true
end

local function input(event)
	if not active then return false end
	if event.type ~= "InputEventType_FirstPress" then return true end

	if event.GameButton == "Back" or event.GameButton == "Select" then
		close()
	elseif not bindingPlayer and uid then
		local player = event.GameButton == "Start" and event.PlayerNumber
			or sideForButton[event.GameButton] or sideForButton[event.button]

		if player == PLAYER_1 or player == PLAYER_2 then
			if screen:SwitchNFCProfile(uid, player) then
				close()
			else
				text("Cannot join or switch this player. Check credits\nand that the current style allows this side to join.\nLeft or P1 Start: P1; Right or P2 Start: P2.\nBack to cancel.")
			end
		end
	end

	return true
end

return Def.ActorFrame{
	InitCommand=function(self)
		frame = self
		self:visible(false):draworder(200)
	end,

	OnCommand=function(self)
		screen = SCREENMAN:GetTopScreen()
		screen:AddInputCallback(input)
	end,

	OffCommand=function(self)
		screen:RemoveInputCallback(input)
		if active then close() end
	end,

	BeginNFCBindingMessageCommand=function(self, params)
		if not PROFILEMAN:IsPersistentProfile(params.Player)
			or PROFILEMAN:ProfileWasLoadedFromMemoryCard(params.Player) then
			return
		end

		if show() then
			bindingPlayer = params.Player
			local name = PROFILEMAN:GetProfile(bindingPlayer):GetDisplayName()

			if not name:find("%S") then
				name = ToEnumShortString(bindingPlayer)
			end

			text("Bind NFC Card for " .. name .. ".\nTap a card now.")
		end
	end,

	NFCCardScannedMessageCommand=function(self, params)
		local id = screen:NFCProfile(params.UID)

		if bindingPlayer then
			local profile = PROFILEMAN:GetProfile(bindingPlayer)
			local name = profile:GetDisplayName()

			if id ~= "" and PROFILEMAN:GetLocalProfile(id) == profile then
				close()
				SM(name .. " already has this NFC card bound.")
				return
			end

			local ok = screen:BindNFC(params.UID, bindingPlayer)
			close()

			SM(ok and ("NFC card bound for " .. name .. ".")
				or "Binding failed. Select a local profile first; check Save directory permissions.")
		elseif not active and id ~= "" and show() then
			uid = params.UID
			text("NFC profile: " .. PROFILEMAN:GetLocalProfile(id):GetDisplayName()
				.. "\nPress Left for P1 or Right for P2.")
		end
	end,

	Def.Quad{
		InitCommand=function(self)
			self:Center():setsize(SCREEN_WIDTH, SCREEN_HEIGHT):diffuse(0, 0, 0, 0.9)
		end,
	},

	Def.BitmapText{
		Name="Text", Font="Common Normal",
		InitCommand=function(self)
			self:Center():zoom(0.8):wrapwidthpixels(SCREEN_WIDTH - 60)
		end,
	},
}
