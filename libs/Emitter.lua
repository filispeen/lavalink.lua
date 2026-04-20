local Emitter = {}
Emitter.__index = Emitter

function Emitter.new()
  local self = setmetatable({}, Emitter)
  self._listeners = {}
  return self
end

function Emitter:on(event, callback)
  if not self._listeners[event] then
    self._listeners[event] = {}
  end
  table.insert(self._listeners[event], { fn = callback, once = false })
  return self
end

function Emitter:once(event, callback)
  if not self._listeners[event] then
    self._listeners[event] = {}
  end
  table.insert(self._listeners[event], { fn = callback, once = true })
  return self
end

function Emitter:off(event, callback)
  if not self._listeners[event] then return end
  local list = self._listeners[event]
  for i = #list, 1, -1 do
    if list[i].fn == callback then
      table.remove(list, i)
    end
  end
end

function Emitter:emit(event, ...)
  if not self._listeners[event] then return end
  local list = self._listeners[event]
  local toRemove = {}
  for i, entry in ipairs(list) do
    local ok, err = pcall(entry.fn, ...)
    if not ok then
      self:_onError(event, err)
    end
    if entry.once then
      table.insert(toRemove, i)
    end
  end
  for i = #toRemove, 1, -1 do
    table.remove(list, toRemove[i])
  end
end

function Emitter:_onError(event, err)
  if event ~= "error" then
    self:emit("error", err)
  else
    error(err)
  end
end

function Emitter:removeAllListeners(event)
  if event then
    self._listeners[event] = nil
  else
    self._listeners = {}
  end
end

return Emitter
