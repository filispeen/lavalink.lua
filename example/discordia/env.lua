local fs = require("fs")
local path = require("path")

local function load(filepath)
  filepath = filepath or path.join(process.cwd(), ".env")

  local content = fs.readFileSync(filepath)
  if not content then return end

  for line in content:gmatch("[^\r\n]+") do
    local key, value = line:match("^([%w_]+)%s*=%s*(.-)%s*$")

    if key and not line:match("^%s*#") then
      value = value:match('^"(.*)"$') or value:match("^'(.*)'$") or value
      process.env[key] = value
    end
  end
end

return { load = load }