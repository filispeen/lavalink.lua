local Queue = {}
Queue.__index = Queue

function Queue.new()
  local self = setmetatable({}, Queue)
  self.tracks = {}
  self.previous = {}
  self.current = nil
  return self
end

function Queue:add(track)
  if type(track) == "table" and track[1] then
    for _, t in ipairs(track) do
      table.insert(self.tracks, t)
    end
  else
    table.insert(self.tracks, track)
  end
end

function Queue:addAt(index, track)
  table.insert(self.tracks, index, track)
end

function Queue:remove(startIndex, endIndex)
  startIndex = startIndex or 1
  endIndex = endIndex or startIndex
  local removed = {}
  for i = endIndex, startIndex, -1 do
    table.insert(removed, 1, table.remove(self.tracks, i))
  end
  return removed
end

function Queue:clear()
  self.tracks = {}
end

function Queue:shuffle()
  local n = #self.tracks
  for i = n, 2, -1 do
    local j = math.random(1, i)
    self.tracks[i], self.tracks[j] = self.tracks[j], self.tracks[i]
  end
end

function Queue:splice(startIndex, deleteCount, ...)
  local inserted = { ... }
  local removed = {}
  for i = 1, deleteCount do
    table.insert(removed, table.remove(self.tracks, startIndex))
  end
  for i = #inserted, 1, -1 do
    table.insert(self.tracks, startIndex, inserted[i])
  end
  return removed
end

function Queue:size()
  return #self.tracks
end

function Queue:totalSize()
  return #self.tracks + (self.current and 1 or 0)
end

function Queue:isEmpty()
  return #self.tracks == 0
end

function Queue:shift()
  if #self.tracks == 0 then return nil end
  return table.remove(self.tracks, 1)
end

function Queue:addPrevious(track)
  if not track then return end
  table.insert(self.previous, 1, track)
  if #self.previous > 25 then
    table.remove(self.previous)
  end
end

function Queue:advance()
  if self.current then
    self:addPrevious(self.current)
  end
  self.current = self:shift()
  return self.current
end

function Queue:peekNext()
  return self.tracks[1]
end

return Queue
