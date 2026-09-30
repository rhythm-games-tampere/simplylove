-- only run in modified stepmania build 
if not SYNCMAN or not SYNCMAN:IsEnabled() then
  return Def.Actor{}
end

local MAX_PLAYER_COUNT = 6
local Y_FROM_BOTTOM = 30

local playerNameTexts = {}
local scoreTexts = {}

local isDouble = GAMESTATE:GetCurrentStyle():GetStyleType() == "StyleType_OnePlayerTwoSides"

local BACKGROUND_MARGIN = 5
local background_min_width = 0
local background_act
local background_def = Def.Quad {
  InitCommand = function(self)
    background_act = self
    if isDouble then
      self:halign(0):x(20 - BACKGROUND_MARGIN)
    else
      self:CenterX()
    end
    self
      :diffuse(0,0,0,0.8)
      :visible(false)
      :valign(1)
  end
}

local t = Def.ActorFrame{
  SyncStartPlayerScoresChangedMessageCommand=function(self)
    self:queuecommand("UpdateScores")
  end,

  UpdateScoresCommand=function(self)
    local scores = SYNCMAN:GetCurrentPlayerScores()
    local max_width = background_min_width

    for i = 1, MAX_PLAYER_COUNT do
      local scoreIndex = (i - (MAX_PLAYER_COUNT - #scores))

      if scoreIndex > 0 and scoreIndex <= #scores then
        local score = scores[scoreIndex]
        local color = score.failed and color("1,0.3,0.3,0.4") or color("1,1,1,0.5")
        playerNameTexts[i]:settext(score.playerName):diffuse(color)
        scoreTexts[i]:settext(score.score):diffuse(color)

        max_width = math.max(max_width, playerNameTexts[i]:GetZoomedWidth())
      else
        playerNameTexts[i]:settext("")
        scoreTexts[i]:settext("")
      end
    end

    if #scores == 0 then
      background_act:visible(false)
      return
    end

    local bottom = scoreTexts[MAX_PLAYER_COUNT]
    local top = playerNameTexts[MAX_PLAYER_COUNT - #scores + 1]
    local bottom_y = bottom:GetY() + (bottom:GetZoomedHeight() / 2)
    local top_y = top:GetY() - (top:GetZoomedHeight() / 2)

    background_act
      :zoomy(bottom_y - top_y + (2 * BACKGROUND_MARGIN))
      :zoomx(max_width + (2 * BACKGROUND_MARGIN))
      :y(bottom_y + BACKGROUND_MARGIN)
      :visible(true)
  end
}

t[#t+1] = background_def

for i = 1, MAX_PLAYER_COUNT do
  local playerIndex = MAX_PLAYER_COUNT - i + 1

  t[#t+1] = Def.BitmapText{
    Font="Miso/_miso light",
    Text="",
    InitCommand=function(self)
      playerNameTexts[playerIndex] = self
      if isDouble then
        self:x(20)
        self:align(0, 0.5)
      else
        self:CenterX()
        self:align(0.5, 0.5)
      end

      self:zoom(0.75)
      self:y(SCREEN_HEIGHT - (i * 40) - Y_FROM_BOTTOM)
    end
  }

  t[#t+1] = Def.BitmapText{
    Font="Wendy/_wendy small",
    Text="",
    InitCommand=function(self)
      scoreTexts[playerIndex] = self
      if isDouble then
        self:x(20)
        self:align(0, 0.5)
      else
        self:CenterX()
        self:align(0.5, 0.5)
      end

      self:zoom(0.25)
      self:y(SCREEN_HEIGHT - (i * 40) - Y_FROM_BOTTOM + 15)

      self:settext("100.00")
      background_min_width = self:GetZoomedWidth()
      self:settext("")
    end
  }
end

return t
