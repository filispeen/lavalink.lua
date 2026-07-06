local function deepCopy(orig)
  local orig_type = type(orig)
  local copy
  if orig_type == "table" then
    copy = {}
    for k, v in pairs(orig) do
      copy[deepCopy(k)] = deepCopy(v)
    end
    setmetatable(copy, deepCopy(getmetatable(orig)))
  else
    copy = orig
  end
  return copy
end

local function merge(target, source)
  for k, v in pairs(source) do
    if type(v) == "table" and type(target[k]) == "table" then
      merge(target[k], v)
    else
      target[k] = v
    end
  end
  return target
end

local function encodeURI(str)
  return str:gsub("[^%w%-%.%_%~%:%/%?%#%[%]%@%!%$%&%'%(%)%*%+%,%;%=]", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
end

local function encodeURIComponent(str)
  return str:gsub("[^%w%-%.%_%~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
end

local function buildQuery(params)
  if not params then return "" end
  local parts = {}
  for k, v in pairs(params) do
    table.insert(parts, encodeURIComponent(tostring(k)) .. "=" .. encodeURIComponent(tostring(v)))
  end
  if #parts == 0 then return "" end
  return "?" .. table.concat(parts, "&")
end

local function splitSearchResult(loadType, data)
  if loadType == "track" then
    return { data.data }
  elseif loadType == "playlist" then
    return data.data and data.data.tracks or {}
  elseif loadType == "search" then
    return data.data or {}
  end
  return {}
end

local function getOrDefault(val, default)
  if val == nil then return default end
  return val
end

return {
  deepCopy = deepCopy,
  merge = merge,
  buildQuery = buildQuery,
  encodeURI = encodeURI,
  encodeURIComponent = encodeURIComponent,
  splitSearchResult = splitSearchResult,
  getOrDefault = getOrDefault,
}
