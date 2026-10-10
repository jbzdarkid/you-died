local Ambush = require "necro.game.character.Ambush"
local Collision = require "necro.game.tile.Collision"
local Currency = require "necro.game.item.Currency"
local CurrentLevel = require "necro.game.level.CurrentLevel"
local Damage = require "necro.game.system.Damage"
local Descent = require "necro.game.character.Descent"
local Entities = require "system.game.Entities"
local Event = require "necro.event.Event"
local Flyaway = require "necro.game.system.Flyaway"
local GrooveChain = require "necro.game.character.GrooveChain"
local Health = require "necro.game.character.Health"
local Inventory = require "necro.game.item.Inventory"
local ItemGeneration = require "necro.game.item.ItemGeneration"
local Object = require "necro.game.object.Object"
local ObjectEvents = require "necro.game.object.ObjectEvents"
local Player = require "necro.game.character.Player"
local RunState = require "necro.game.system.RunState"
local ShrineGeneration = require "necro.game.level.ShrineGeneration"
local TextPool = require "necro.config.i18n.TextPool"
local Utilities = require "system.utils.Utilities"

-- Docs are available via https://vortexbuffer.com/synchrony/docs/search/search_index.json


-- TODO: Some better ideas about what lives where.
-- TODO: Pause menu entry to retry level (in case you can't die?)

local youDied = false -- Tracks if we need to reapply the saved level on restart.
local deathCount = 0

local savedState = nil
Event.gameStateReset.add("clearCheckpoint", {order="random"}, function()
  -- Clear state when we start a new run or go to the lobby.
  youDied = false
  savedState = nil
end)

Event.levelLoad.add("preLevelLoad", {order="runState", sequence=-1}, function(evt)
  if youDied then
    print("Restarting level " .. evt.zone .. "-" .. evt.floor .. " after dying")
    loadState()
  else
    print("Reached new level " .. evt.zone .. "-" .. evt.floor .. ", making new checkpoint")
    savedState = saveState()
    savedState.targetLevel = CurrentLevel.getNumber()
  end
end)

Event.getIntroText.add("replaceCustomModeIntro", {order="modsEnabled", sequence=1}, function(ev)
  if youDied then
    ev.text = "You died!\nDeath count: " .. tostring(deathCount)
  elseif ev.text == TextPool.get("gameMode.allZones.intro.modded") then
    ev.text = TextPool.get("gameMode.allZones.intro")
  end
end)

Event.gameStateLevel.add("postLevelLoad", {order="levelLoadingDone", sequence=-1}, function(evt)
  if youDied then
    print("Applying saved entity RNG values on restart")
    for entity in Entities.entitiesWithComponents({"random"}) do
      local key = entity.name .. "@" .. entity.position.x .. "," .. entity.position.y
      entity.random.state1 = savedState.randomEntities[key].state1
      entity.random.state2 = savedState.randomEntities[key].state2
      entity.random.state3 = savedState.randomEntities[key].state3
    end
  elseif savedState == nil then
    -- Invalid state
  else
    print("Capturing entity RNG values after level load")
    savedState.randomEntities = {}
    for entity in Entities.entitiesWithComponents({"random"}) do
      local key = entity.name .. "@" .. entity.position.x .. "," .. entity.position.y
      savedState.randomEntities[key] = Utilities.deepCopy(entity.random)
    end

    savedState.ambushers = {}
    if Ambush.isActive() then
      print("Capturing ambushers from a trapdoor drop")
      for entity in Entities.entitiesWithComponents({"ambusher"}) do
        if entity.ambusher.active then
          table.insert(savedState.ambushers, entity.name)
        end
      end
    end
  end
  -- This is the last handler (for now) so it's where we clear this flag.
  youDied = false
end)

Event.objectTakeDamage.add("checkDeath", {order="death", sequence=-1, filter="health"}, function(evt)
  if evt.survived or evt.victim ~= Player.getPlayerEntity(1) then
    return
  end

  print("Player was killed by " .. evt.attacker.name)
  -- Stop the player from dying, and instead drop them down a trapdoor so we can restart the level.
  evt.suppressed = true
  evt.damage = 0
  
  if #savedState.ambushers > 0 then
    -- When you drop down a trapdoor, the game determines if it should spawn an ambush based on the live minibosses.
    -- To get the same ambush, we need to clear the current miniboss, and spawn the one from the saved ambush.
    for entity in Entities.entitiesWithComponents({"ambusher"}) do
      entity.ambusher.pending = false
    end
    for i, name in ipairs(savedState.ambushers) do
      Object.spawn(name, -100, -100, {ambusher = {pending = true}})
    end
    Descent.perform(evt.victim, Descent.Type.TRAPDOOR)
  else
    Descent.perform(evt.victim, Descent.Type.STAIRS)
  end

  -- TODO: A menu? So we can choose... something else?
  Flyaway.create({
    entity = evt.victim,
    text = "! YOU DIED !",
    delay = 0,
    offsetY = -20,
    size = 10,
  })

  deathCount = deathCount + 1
  youDied = true
end)

Event.levelComplete.add("replayLevel", {order="nextLevel", sequence=-1}, function(evt)
  if youDied and savedState ~= nil then
    print("Prevented level transition because you died")
    evt.targetLevel = savedState.targetLevel

    -- We need to restore the runState here, before the level loads. Otherwise things like Shrine of Space have already been applied.
    RunState.reset({Player.getPlayerEntity(1)})
    for key, value in pairs(savedState.runState) do
      RunState.set(key, Utilities.deepCopy(value))
    end

    -- Equipped items can also effect level generation (e.g. war)
    local player = Player.getPlayerEntity(1)
    Inventory.clear(player)
    for i, item in ipairs(savedState.items) do
      local granted = Inventory.grant(item.name, player)
      if item.quantity ~= nil then
        granted.itemStack.quantity = item.quantity
      end
      if item.follower ~= nil then
        granted.follower = item.follower
      end
      if item.remainingKills ~= nil then
        granted.spellCooldownKills.remainingKills = item.remainingKills
      end
      if item.activated then
        granted.itemActivable.active = true
      end
      if item.ammo ~= nil then
        granted.weaponReloadable.ammo = item.ammo
      end

      if item.name == "Holster" and savedState.holsteredItem ~= nil then
        -- Holstered items aren't actually in the inventory, they're stored on the item.
        -- Swap in and out so we use the game's storage systems.
        Inventory.swapWithHolster(player, granted)
        Inventory.grant(savedState.holsteredItem, player)
        Inventory.swapWithHolster(player, granted)
      end
    end
  end
end)

function saveState()
  local state = {}
  local player = Player.getPlayerEntity(1)
  
  state.items = {}
  state.followers = {}
  for i, item in ipairs(Inventory.getItems(player)) do
    local itemData = {name = item.name}
    if item.itemStack then
      itemData.quantity = item.itemStack.quantity
    end
    if item.follower ~= nil then
      itemData.follower = item.follower
    end
    if item.spellCooldownKills ~= nil then
      itemData.remainingKills = item.spellCooldownKills.remainingKills
    end
    if item.itemActivable ~= nil then
      itemData.activated = item.itemActivable.active
    end
    if item.weaponReloadable ~= nil then
      itemData.ammo = item.weaponReloadable.ammo
    end

    if item.itemHolster ~= nil then -- Checks both 'is Holster' and 'item is holstered'
      state.holsteredItem = Entities.getEntityByID(item.itemHolster.content).name
    end

    table.insert(state.items, itemData)
  end

  state.health = player.health.health
  state.maxHealth = player.health.maxHealth
  state.cursedHealth = player.cursedHealth.health

  state.bloodKillCount = player.regenerationKillCounter.killCount

  state.gold = Currency.get(player, Currency.Type.GOLD)

  state.grooveChain = Utilities.deepCopy(player.grooveChain)
  
  -- Per-run globals (e.g. "have you killed freddy")
  state.runState = Utilities.deepCopy(RunState.getState())

  -- Item spawns depend on what you've already seen
  state.seenItems = {}
  for item, count in pairs(ItemGeneration.getSeenCounts()) do
    state.seenItems[item] = count
  end
  
  -- Shrine spawns also depend on what you've already seen
  state.seenShrines = {}
  for shrine, count in pairs(ShrineGeneration.getSeenCounts()) do
    state.seenShrines[shrine] = count
  end

  state.trapdoorItems = {}
  for entity in Entities.entitiesWithComponents({"descent"}) do
    if entity.descent.active and string.sub(entity.name, 1, 5) == "Crate" then
      local item = {
        name = entity.name,
        health = entity.health.health,
        maxHealth = entity.health.maxHealth,
        contents = {},
      }
      if entity.storage ~= nil then
        for i, itemName in pairs(entity.storage.items) do
          table.insert(item.contents, itemName)
        end
      end
      table.insert(state.trapdoorItems, item)
    end
  end
  
  return state
end

function loadState()
  local player = Player.getPlayerEntity(1)

  player.health.health = savedState.health
  player.health.maxHealth = savedState.maxHealth
  player.cursedHealth.health = savedState.cursedHealth
  
  player.regenerationKillCounter.killCount = savedState.bloodKillCount

  Currency.set(player, Currency.Type.GOLD, savedState.gold)

  player.grooveChain.killCount = savedState.grooveChain.killCount
  player.grooveChain.multiplier = savedState.grooveChain.multiplier
  GrooveChain.update(player)

  -- getSeenCounts returns a reference we can modify
  local mutableCounts = ItemGeneration.getSeenCounts()
  for item in pairs(mutableCounts) do
    mutableCounts[item] = savedState.seenItems[item] -- Will be nil if we haven't seen it before
  end

  -- getSeenCounts returns a reference we can modify
  local mutableShrineCounts = ShrineGeneration.getSeenCounts()
  for shrine in pairs(mutableShrineCounts) do
    mutableShrineCounts[shrine] = savedState.seenShrines[shrine]
  end 
  
  -- Wipe out anything that dropped through a trapdoor so it's not there on restart
  for entity in Entities.entitiesWithComponents({"descent"}) do
    if entity.descent.active and string.sub(entity.name, 1, 5) == "Crate" then
      Object.delete(entity)
    end
  end

  -- Spawn crates mid-descent (in theory this should fix the player collision issue).
  for i, item in ipairs(savedState.trapdoorItems) do
    Object.spawn(item.name, 0, 0, {
      descent = {active = true},
      health = {health = item.health, maxHealth = item.maxHealth},
      storage = {items = item.contents},
      spawnInvincibility = {active = false},
    })
  end
end
