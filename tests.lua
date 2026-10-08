local Ability = require "necro.game.system.Ability"
local Action = require "necro.game.system.Action"
local Ambush = require "necro.game.character.Ambush"
local Currency = require "necro.game.item.Currency"
local CurrentLevel = require "necro.game.level.CurrentLevel"
local CustomEntities = require "necro.game.data.CustomEntities"
local Descent = require "necro.game.character.Descent"
local Entities = require "system.game.Entities"
local Event = require "necro.event.Event"
local Flyaway = require "necro.game.system.Flyaway"
local GameSession = require "necro.client.GameSession"
local Input = require "necro.client.Input"
local Inventory = require "necro.game.item.Inventory"
local Lobby = require "necro.game.level.Lobby"
local Map = require "necro.game.object.Map"
local Netplay = require "necro.network.Netplay"
local Object = require "necro.game.object.Object"
local Player = require "necro.game.character.Player"
local RNG = require "necro.game.system.RNG"
local Room = require "necro.client.Room"
local Tile = require "necro.game.tile.Tile"
local Turn = require "necro.cycles.Turn"

function assertItemAt(x, y, name)
  local player = Player.getPlayerEntity(1)
  local found = ''
  for i, entityId in ipairs(Map.getAll(player.position.x + x, player.position.y + y)) do
    local entity = Entities.getEntityByID(entityId)
    if entity.name == name then
      return true
    end
    found = found .. entity.name .. " "
  end
  print("ASSERTION FAILED. Map tile " .. x .. " " .. y .. " does not have an entity named '" .. name .. "'")
  print("Found entities: " .. found)
  return false
end

function assertInventoryItem(name)
  for _, item in ipairs(Inventory.getItems(Player.getPlayerEntity(1))) do
    if item.name == name then
      return true
    end
  end
  print("ASSERTION FAILED. Player does not have item '" .. name .. "' in their inventory.")
  return false
end

function giveMoney(gold)
  local player = Player.getPlayerEntity(1)
  Currency.set(player, Currency.Type.GOLD, gold)
  return true
end

-- TODO: Test for blood
-- TODO: Test for combo
-- TODO: Test for max health / cursed health
-- TODO: Test for spells
-- TODO: Tests for pushing things through trapdoors (cheat here, for sure). Probably simplest to test with Chest3.
-- TODO: Test for money
-- TODO: Test for inventory (probably implicit with the above)


local tests = {{
  name = "BloodShopTeleport",
  seed = 294842629,
  steps = {
    "RRUUQRRUL", -- Enter blood shop
    "GU", -- Aggro the shopkeep
    function() return assertItemAt(-1, 0, "Shopkeeper2") end,

    "..", -- Die to shopkeep

    "RRUUQRRUL", -- Enter blood shop
    "UGU", -- Move then throw, should get the same teleport
    function() return assertItemAt(-1, 0, "Shopkeeper2") end,

    "..", -- Die to shopkeep

    "RRUUQRRUL", -- Enter blood shop
    "UUUGU", -- Move further up, then throw, should get the same teleport
    function() return assertItemAt(-1, 2, "Shopkeeper2") end,
  },
}, {
  name = "ArenaKeepsEnemiesOnReplay",
  seed = 1939573472,
  steps = {
    "DRRRRRRRRDDDDRD....", -- Take the trapdoor
    function() return CurrentLevel.getNumber() == 2 end,
    function() return assertItemAt(-2, -2, "Bat") end,
    function() return assertItemAt( 2, -2, "Skeleton") end,
    function() return assertItemAt( 2,  2, "Ghost") end,
    function() return assertItemAt(-2,  2, "Dragon") end,
    "LULRU.DLRLRL", -- Almost clear the arena
    function() return assertItemAt(-1, 0, "Dragon") end,
    -- function() return assertItemAt(1, 0, "Wall2") end, -- TODO.
    "L", -- Kill the dragon and clear the arena
    function() return assertItemAt(-1, 0, "ResourceCoin10") end,
    -- function() return assertItemAt(1, 0, nil) end,

    "RRRRQR......", -- Die to bomb

    function() return CurrentLevel.getNumber() == 2 end,
    function() return assertItemAt(-2, -2, "Bat") end,
    function() return assertItemAt( 2, -2, "Skeleton") end,
    function() return assertItemAt( 2,  2, "Ghost") end,
    function() return assertItemAt(-2,  2, "Dragon") end,
    "LULRU.DLRLRL", -- Almost clear the arena
    function() return assertItemAt(-1, 0, "Dragon") end,

    ".......", -- Die to dragon

    function() return CurrentLevel.getNumber() == 2 end,
    function() return assertItemAt(-2, -2, "Bat") end,
    function() return assertItemAt( 2, -2, "Skeleton") end,
    function() return assertItemAt( 2,  2, "Ghost") end,
    function() return assertItemAt(-2,  2, "Dragon") end,
  },
},{
  name = "ShrineOfSpace",
  seed = 334529790,
  steps = {
    "LLDDDLL", -- Enter shriner
    function() return assertItemAt(-1, -2, "ShrineOfGlass") end,
    function() return assertItemAt( 0, -2, "ShrineOfBoss") end,
    function() return assertItemAt( 1, -2, "ShrineOfSpace") end,
    function() return giveMoney(50) end,
    "RUUDL", -- Tap shrine, leave

    "DLL.LLLL.....", -- Die to the ghost

    -- If shrine of space is preserved, the shriner will be in a different spot.
    -- (this also tests that we preserve 'seen shrines')

    "LLDDDLL", -- Enter shriner
    function() return assertItemAt(-1, -2, "ShrineOfGlass") end,
    function() return assertItemAt( 0, -2, "ShrineOfBoss") end,
    function() return assertItemAt( 1, -2, "ShrineOfSpace") end,
  },
},{
  name = "TransmuteShop",
  seed = 1658736754,
  steps = {
    "UURRRRUUUU.UUUURUU", -- Grab transmute tome
    function() return assertInventoryItem("TomeTransmute") end,
    "DDDDLDDDLLLUUUUUULL", -- Enter shop
    function() return assertItemAt(-1, -1, "WeaponSpear") end,
    function() return assertItemAt( 0, -1, "BombGrenade3") end,
    function() return assertItemAt( 1, -1, "Torch1") end,
    "A", -- Transmute
    function() return assertItemAt(-1, -1, "WeaponBloodLongsword") end,
    function() return assertItemAt( 0, -1, "WeaponWhip") end,
    function() return assertItemAt( 1, -1, "Food1") end,
    "A", -- Transmute
    function() return assertItemAt(-1, -1, "Sync_ShieldWooden") end,
    function() return assertItemAt( 0, -1, "Torch2") end,
    function() return assertItemAt( 1, -1, "WeaponRapier") end,
    "RRUULQ.....", -- Blow up Freddy and die

    -- Repeat the test and confirm the same items spawn / transmute
    -- (this also tests that we preserve 'seen items')

    "UURRRRUUUU.UUUURUU", -- Grab transmute tome
    function() return assertInventoryItem("TomeTransmute") end,
    "DDDDLDDDLLLUUUUUULL", -- Enter shop
    function() return assertItemAt(-1, -1, "WeaponSpear") end,
    function() return assertItemAt( 0, -1, "BombGrenade3") end,
    function() return assertItemAt( 1, -1, "Torch1") end,
    "A", -- Transmute
    function() return assertItemAt(-1, -1, "WeaponBloodLongsword") end,
    function() return assertItemAt( 0, -1, "WeaponWhip") end,
    function() return assertItemAt( 1, -1, "Food1") end,
    "A", -- Transmute
    function() return assertItemAt(-1, -1, "Sync_ShieldWooden") end,
    function() return assertItemAt( 0, -1, "Torch2") end,
    function() return assertItemAt( 1, -1, "WeaponRapier") end,
  },
}}




--- Tests above, test infra below



local testStairsType = CustomEntities.register {
  name = "TestStairs",
  gameObject = {},
  visibility = {},
  worldLabel = {text = "Run tests"},
}

local stairs = {x = 2, y = -2}
Event.gameStateLevel.add("placeTestStairs", {order="levelLoadingDone"}, function(evt)
  if CurrentLevel.isLobby() then
    Object.spawn(testStairsType, stairs.x, stairs.y)
    Tile.setType(stairs.x, stairs.y, "LobbyStairs")
  end
end)

local testSpeedMult = 10
local runningTests = false
local testNo = nil
Event.objectMove.add("enterTestStairs", {order = "tileEffects", sequence = 1, filter = "controllable"}, function(evt)
  if evt.x == stairs.x and evt.y == stairs.y and CurrentLevel.isLobby() then
    testNo = 0
    Room.setAttribute(Netplay.RoomAttribute.TEMPO_MULTIPLIER, testSpeedMult)
    startNextTest()
    runningTests = true
  end
end)

local currentTest = nil
local stepIndex = 1
local subStepIndex = 1
function startNextTest()
  testNo = testNo + 1
  if testNo > #tests then
    print("-- ALL TESTS DONE --")
    runningTests = false
    Room.setAttribute(Netplay.RoomAttribute.TEMPO_MULTIPLIER, nil)
    Lobby.open()
    return
  end

  currentTest = tests[testNo]
  stepIndex = 1
  subStepIndex = 1
  GameSession.start({modeID = GameSession.Mode.AllZonesSeeded, seed = currentTest.seed})
end

Event.objectUpdateRhythm.add("autoPlayDuringTests", {order="autoPlay"}, function(evt)
  if runningTests then
    evt.autoPlay = true
  end
end)

-- Entity RNG is not actually consistent per run, so we need to fix it to have consistent enemy kill.
Event.gameStateReset.add("seedRNGDuringTests", {order="random", sequence=1}, function()
  if runningTests then
    print("Reseeding RNG for " .. currentTest.name)
    RNG.seed(currentTest.seed, 100, 100)
  end
end)



function testFailed()
  print("FAILED: " .. currentTest.name)
  local player = Player.getPlayerEntity(1)
  Flyaway.create({
    entity = player,
    text = "! TEST FAILED !",
    delay = 0,
    offsetY = -20,
    size = 10,
  })
  -- Object.spawn("Trapdoor", player.position.x, player.position.y)
  -- Descent.perform(player, Descent.Type.TRAPDOOR)
  Lobby.open()
end

function getNextTestMove()
  if CurrentLevel.isLobby() then -- Stop the tests if the user quits to lobby
    runningTests = false
    Room.setAttribute(Netplay.RoomAttribute.TEMPO_MULTIPLIER, nil)
    return nil
  end

  if currentTest == nil then
    return nil
  end
  
  if stepIndex > #currentTest.steps then
    print("PASSED: " .. currentTest.name)
    startNextTest()
    return nil
  end

  local step = currentTest.steps[stepIndex]
  if type(step) == "function" then
    if not step() then
      testFailed()
      startNextTest()
      return nil
    end
    stepIndex = stepIndex + 1
    return getNextTestMove() -- Could be another assert or another string of moves.
  
  elseif type(step) == "string" then
    if subStepIndex > #step then
      subStepIndex = 1
      stepIndex = stepIndex + 1
      return getNextTestMove()
    end
    
    local key = string.sub(step, subStepIndex, subStepIndex)
    subStepIndex = subStepIndex + 1
    if key == "U" then     return Action.Direction.UP
    elseif key == "D" then return Action.Direction.DOWN
    elseif key == "L" then return Action.Direction.LEFT
    elseif key == "R" then return Action.Direction.RIGHT
    elseif key == "Q" then return Action.Special.BOMB
    elseif key == "G" then return Action.Special.THROW
    elseif key == "A" then return Action.Special.ITEM_1
    elseif key == "." then return Action.Special.IDLE
    
    -- Action.Special.ITEM_2
    -- Action.Special.SPELL_1
    -- Action.Special.SPELL_2
    end
  end

  print("Error while determining the next test move")
  testFailed()
end

-- The pending transition check lets lobby beats through untouched until the run starts, so the lobby check doesn't stop the tests.
Event.clientAddInput.add("injectInputs", {order="lobbyCooldown", sequence=-1}, function(evt)
  if runningTests and evt.action == Action.Special.IDLE and not GameSession.hasPendingTransition() then
    local move = getNextTestMove()
    if move ~= nil then
      evt.action = move
      evt.flags = Ability.getActionFlags(move)
    end
  end
end)

--[[
-- No beats means no idle inputs to rewrite, so submit one move each time the previous one has been fully simulated.
Event.tick.add("driveTests", {order="input", sequence=1}, function()
  if runningTests and not GameSession.hasPendingTransition() and not Input.isPlayerInputBlocked() and Turn.isLatestTurnReached() then
    local move = getNextTestMove()
    if move ~= nil then
      Input.add(move)
    end
  end
end)
--]]