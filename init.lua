local LavalinkManager      = require("./libs/LavalinkManager")
local Node                 = require("./libs/Node")
local Player               = require("./libs/Player")
local Queue                = require("./libs/Queue")
local FilterManager        = require("./libs/FilterManager")
local RestHandler          = require("./libs/RestHandler")
local Emitter              = require("./libs/Emitter")
local utils                = require("./libs/utils")
local discordiaIntegration = require("./integrations/discordia")

return {
  discordia          = discordiaIntegration,

  LavalinkManager    = LavalinkManager,
  Node               = Node,
  Player             = Player,
  Queue              = Queue,
  FilterManager      = FilterManager,
  RestHandler        = RestHandler,
  Emitter            = Emitter,
  utils              = utils,
}
