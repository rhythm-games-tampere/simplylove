-- Tells adp-tool who plays on each side to autoload sensitivities.

local url = "ws://127.0.0.1:8008"
local socket = nil
local connected = false
-- last name sent per side; false for none
local sent = {}

local PlayerName = function(player)
	if not GAMESTATE:IsHumanPlayer(player) or not PROFILEMAN:IsPersistentProfile(player) then return nil end
	local name = PROFILEMAN:GetProfile(player):GetDisplayName()
	return name ~= "" and name or nil
end

local Sync = function(all)
	if not connected then return end
	for side, player in ipairs({PLAYER_1, PLAYER_2}) do
		local name = PlayerName(player) or false
		if all or sent[side] ~= name then
			sent[side] = name
			socket:Send(JsonEncode({ setPlayer={ side=side, player=name or nil } }))
		end
	end
end

return Def.Actor{
	InitCommand=function(self)
		if not NETWORK or not NETWORK:IsUrlAllowed(url) then return end
		socket = NETWORK:WebSocket{
			url=url,
			pingInterval=15,
			automaticReconnect=true,
			onMessage=function(msg)
				local msgType = ToEnumShortString(msg.type)
				if msgType == "Open" then
					connected = true
					-- the server streams every pad's sensors unless told not to
					socket:Send(JsonEncode({ subscribe="" }))
					Sync(true)
				elseif msgType == "Close" or msgType == "Error" then
					connected = false
				end
			end,
		}
	end,
	ScreenChangedMessageCommand=function(self) self:queuecommand("Sync") end,
	PlayerJoinedMessageCommand=function(self) self:queuecommand("Sync") end,
	PlayerUnjoinedMessageCommand=function(self) self:queuecommand("Sync") end,
	PlayerProfileSetMessageCommand=function(self) self:queuecommand("Sync") end,
	SyncCommand=function(self) Sync(false) end,
}
