local FilterManager = {}
FilterManager.__index = FilterManager

local DEFAULT_FILTERS = {
  volume = nil,
  equalizer = nil,
  karaoke = nil,
  timescale = nil,
  tremolo = nil,
  vibrato = nil,
  rotation = nil,
  distortion = nil,
  channelMix = nil,
  lowPass = nil,
  pluginFilters = nil,
}

function FilterManager.new(player)
  local self = setmetatable({}, FilterManager)
  self.player = player
  self.data = {}
  return self
end

function FilterManager:_apply()
  local node = self.player.node
  if not node or not node.sessionId then return end
  local restHandler = node.rest
  local ok, err = pcall(function()
    restHandler:updatePlayer(self.player.guildId, { filters = self.data })
  end)
  if not ok then
    self.player.manager:emit("error", self.player, err)
  end
end

function FilterManager:setVolume(vol)
  self.data.volume = vol
  self:_apply()
  return self
end

function FilterManager:setEqualizer(bands)
  self.data.equalizer = bands
  self:_apply()
  return self
end

function FilterManager:setKaraoke(options)
  self.data.karaoke = options
  self:_apply()
  return self
end

function FilterManager:setTimescale(options)
  self.data.timescale = options
  self:_apply()
  return self
end

function FilterManager:setTremolo(options)
  self.data.tremolo = options
  self:_apply()
  return self
end

function FilterManager:setVibrato(options)
  self.data.vibrato = options
  self:_apply()
  return self
end

function FilterManager:setRotation(options)
  self.data.rotation = options
  self:_apply()
  return self
end

function FilterManager:setDistortion(options)
  self.data.distortion = options
  self:_apply()
  return self
end

function FilterManager:setChannelMix(options)
  self.data.channelMix = options
  self:_apply()
  return self
end

function FilterManager:setLowPass(options)
  self.data.lowPass = options
  self:_apply()
  return self
end

function FilterManager:setPluginFilters(filters)
  self.data.pluginFilters = filters
  self:_apply()
  return self
end

function FilterManager:resetFilters()
  self.data = {}
  self:_apply()
  return self
end

function FilterManager:resetFilter(filterName)
  self.data[filterName] = nil
  self:_apply()
  return self
end

function FilterManager:apply()
  self:_apply()
  return self
end

function FilterManager:apply()
  self:_apply()
  return self
end

function FilterManager:getCurrentData()
  local copy = {}
  for k, v in pairs(self.data) do
    copy[k] = v
  end
  return copy
end

return FilterManager
