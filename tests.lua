local Ability = require "necro.game.system.Ability"
local Action = require "necro.game.system.Action"
local Ambush = require "necro.game.character.Ambush"
local ClientActionBuffer = require "necro.client.ClientActionBuffer"
local Currency = require "necro.game.item.Currency"
local CurrentLevel = require "necro.game.level.CurrentLevel"
local CustomEntities = require "necro.game.data.CustomEntities"
local Descent = require "necro.game.character.Descent"
local Entities = require "system.game.Entities"
local Event = require "necro.event.Event"
local Flyaway = require "necro.game.system.Flyaway"
local GameSession = require "necro.client.GameSession"
local GrooveChain = require "necro.game.character.GrooveChain"
local Health = require "necro.game.character.Health"
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

function assertTileAt(x, y, name)
  local player = Player.getPlayerEntity(1)
  local tile = Tile.getInfo(player.position.x + x, player.position.y + y)
  if tile.name == name then
    return true
  end
  print("ASSERTION FAILED. Map tile " .. x .. " " .. y .. " is '" .. tile.name .. "' not '" .. name .. "'")
  return false
end

function assertWorldItemAt(x, y, name)
  local player = Player.getPlayerEntity(1)
  local found = ''
  for _, entityId in ipairs(Map.getAll(player.position.x + x, player.position.y + y)) do
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
  local player = Player.getPlayerEntity(1)
  local found = ''
  for _, item in ipairs(Inventory.getItems(player)) do
    if item.name == name then
      return true
    end
    found = found .. item.name .. " "
  end
  print("ASSERTION FAILED. Player does not have item '" .. name .. "' in their inventory.")
  print("Found items: " .. found)
  return false
end

function assertEqual(actual, expected)
  if actual == expected then
    return true
  end
  print("ASSERTION FAILED. Expected '" .. tostring(expected) .. "' but found '" .. tostring(actual) .. "'")
  return false
end

function giveMoney(gold)
  local player = Player.getPlayerEntity(1)
  Currency.set(player, Currency.Type.GOLD, gold)
  return true
end

-- TODO: Test for Crate3 spreading through trapdoor (!)

local testSpeedMult = 10

local tests = {{
  name = "BloodDash",
  seed = 1053678846,
  steps = {
    "RRRRDDDDDDDDDRR", -- Open dash spell
    function() return assertWorldItemAt(1, 0, "Sync_SpellDash") end,
    "RDDWDDDDW@RW", -- Dash + blood dash + stairs dash

    function() return assertEqual(CurrentLevel.getNumber(), 2) end,
    "U", -- Dash up
    function() return assertTileAt(0, -1, "ShopWallCracked") end,
    
    "Q...", -- Die to bomb

    -- Confirm that we kept dash, so 'Up' gets us next to the shop wall again
    "U",
    function() return assertTileAt(0, -1, "ShopWallCracked") end,
  },
}, {
  name = "Backpack",
  seed = 806427797,
  steps = {
    "LDDDDDDDLLDDQ", -- Open cookie crate
    "LLLDLLLL", -- Enter shop
    function() return giveMoney(63) end,
    "LDDLLRRUUR", -- Grab backpack + item
    "RRRRRRRRZRRRRRRRRRR", -- Grab cookies, head right, eat one
    "RRR.UUUURRRRRRRRRUUU", -- Enter final room
    "U.UUUUZUZUZUULLLLLU", -- Kill dragon, take stairs, eat a few more cookies (2 left)
    
    function() return assertEqual(CurrentLevel.getNumber(), 2) end,
    "Z", -- Eat a cookie (2 -> 1)
    function() return assertInventoryItem("FoodCookies") end,
    function() return assertInventoryItem("FamiliarShopkeeper") end,
    "AU", -- Use the shopkeep familiar
    "UURRRRRRRRR", -- Grab 3x bomb
    "Q.Q...", -- Die to bombs

    "Z", -- Eat a cookie (2 -> 1) then confirm both items are in the inventory
    function() return assertInventoryItem("FoodCookies") end,
    function() return assertInventoryItem("FamiliarShopkeeper") end,
  },
}, {
  name = "Holster",
  seed = 739961933,
  steps = {
    "RRDDDDDDRR", -- Grab holster
    "LDDDDDDLLLDDDDDLLL", -- Enter the shop
    function() return giveMoney(150) end,
    "LLLLDDDUUURRRRRR", -- Buy rapier
    function() return assertInventoryItem("WeaponRapier") end,
    "UUUUUUURRRUUURRRR",
    "UURURRRRDDDD....", -- Take trapdoor

    function() return assertEqual(CurrentLevel.getNumber(), 2) end,
    function() return assertInventoryItem("WeaponRapier") end,
    "Z", -- Swap holstered item
    function() return assertInventoryItem("WeaponDagger") end,

    "DD.......", -- Die to the minotaur
    
    -- Confirm that we still have our rapier primary (and dagger secondary)
    function() return assertInventoryItem("WeaponRapier") end,
    "Z", -- Swap holstered item
    function() return assertInventoryItem("WeaponDagger") end,
  }
}, {
  name = "BloodWeapon",
  seed = 1665318877,
  steps = {
    "LLDDDDQUURDD", -- Enter blood shop
    "UUDD", -- Grab blood spear (10 kills until heal)
    function() return assertInventoryItem("WeaponBloodSpear") end,
    
    "UUUUUURRRRRUUU", -- Enter north room
    "UUURRUUU", -- Kill 4 enemies, blood is now at 6
    ".LULURRRR....", -- Kill 2 more enemies, take trapdoor (4)

    function() return assertEqual(CurrentLevel.getNumber(), 2) end,
    function() return assertEqual(Health.getCurrentHealth(Player.getPlayerEntity(1)), 2) end,
    
    "LDDURURDRLL", -- Clear arena
    function() return assertEqual(Health.getCurrentHealth(Player.getPlayerEntity(1)), 3) end,

    "DDRRR.RRR....", -- Die to bat

    function() return assertEqual(Health.getCurrentHealth(Player.getPlayerEntity(1)), 2) end,
    "LDDURURDRLL", -- Clear arena
    function() return assertEqual(Health.getCurrentHealth(Player.getPlayerEntity(1)), 3) end,
  },
}, {
  name = "Crate1Trapdoor",
  seed = 958822386,
  steps = {
    "RRDDDDDDD", -- Enter south room
    "DDDRLDDDDR", -- Open trap room
    "ULLDRRRRRR", -- Send crate down the trapdoor
    function() return assertWorldItemAt(1, 1, "TrapdoorOpen") end,
    "R....", -- Drop down yourself

    -- Confirm we got ambushed on floor 2
    function() return assertEqual(CurrentLevel.getNumber(), 2) end,
    function() return assertWorldItemAt(-2, -2, "Minotaur") end,
    function() return assertWorldItemAt( 2, -2, "Bat") end,
    function() return assertWorldItemAt( 2,  2, "Skeleton") end,
    function() return assertWorldItemAt(-2,  2, "Ghost") end,
    
    -- Check what came out of the crate
    function() return assertWorldItemAt(-1, 0, "BombGrenade3") end,
    "LUAD", -- Clear arena,
    "U.....", -- Die to ghost
    
    -- Confirm we're back in the arena
    function() return assertWorldItemAt(-2, -2, "Minotaur") end,
    function() return assertWorldItemAt( 2, -2, "Bat") end,
    function() return assertWorldItemAt( 2,  2, "Skeleton") end,
    function() return assertWorldItemAt(-2,  2, "Ghost") end,

    -- and the crate spawned the same stuff.
    function() return assertWorldItemAt(-1, 0, "BombGrenade3") end,
  },
}, {
  name = "CursedPotion",
  seed = 993027751,
  steps = {
    "RUUUUQDDLUUU", -- Enter blood shop
    "RUUDDL", -- Buy cursed potion and leave
    function() return assertInventoryItem("CursedPotion") end,
    function() return assertEqual(Health.getCurrentHealth(Player.getPlayerEntity(1)), 2) end,
    "A", -- Pop the potion
    function() return assertEqual(Health.getCurrentHealth(Player.getPlayerEntity(1)), 6) end,

    "...", -- Die to yellow skeleton

    -- Restarted the level, so we return to base (full) health
    function() return assertEqual(Health.getCurrentHealth(Player.getPlayerEntity(1)), 6) end,
  },
}, {
  name = "HealSpell",
  seed = 1431898213,
  steps = {
    "RDDDDDDDDDD",
    "LDDDDRRDDQULUDDD", -- Enter blood shrine
    "RUUDDL", -- Buy heal spell and leave
    function() return assertInventoryItem("SpellHeal") end,
    "W", -- Use the spell (kills to refresh = 15)
    "UUUD", -- Kill monkey (remaining = 14)
    "LLLLLLLL.", -- First bat (13)
    "L.L.UUUULLU", -- 7 more bats (6)
    ".DLRUURLDU", -- Last bat + dragon (4)
    "DRRRRRRRDDDD", -- Blue slime, enter exit room (3)
    ".RRRRRRRRRD", -- Two more slimes, take stairs (1)

    function() return assertEqual(CurrentLevel.getNumber(), 2) end,
    function() return assertEqual(Health.getCurrentHealth(Player.getPlayerEntity(1)), 3) end,
    "W", -- Blood heal
    function() return assertEqual(Health.getCurrentHealth(Player.getPlayerEntity(1)), 2) end,
    "WW", -- Die via blood magic

    function() return assertEqual(CurrentLevel.getNumber(), 2) end,
    function() return assertEqual(Health.getCurrentHealth(Player.getPlayerEntity(1)), 3) end,

    "DRRRRRRRR", -- Break into exit room
    "QLLLLW", -- Heal (should have refreshed now)
    function() return assertEqual(Health.getCurrentHealth(Player.getPlayerEntity(1)), 4) end,
  },
}, {
  name = "FoodShop",
  seed = 202792604,
  steps = {
    "LLDDQRRDLL", -- Enter food shop
    "GULUUUURDDDD", -- Exit shop with charm and drumstick
    function() return assertInventoryItem("Food3") end,
    function() return assertEqual(Health.getMaxHealth(Player.getPlayerEntity(1)), 6) end,
    "A", -- Eat and get overhealed
    function() return assertEqual(Health.getMaxHealth(Player.getPlayerEntity(1)), 12) end,

    "RDDDDDLD..........", -- Die to blue slime

    function() return assertEqual(Health.getMaxHealth(Player.getPlayerEntity(1)), 6) end,
  },
}, {
  name = "PreserveCombo",
  seed = 1009649599,
  steps = {
    "UURRRQRRRLU", -- Enter blood shop
    "UUDD", -- Buy obs spear
    function() return assertInventoryItem("WeaponObsidianSpear") end,
    "DDDDDDDDRRRRR", -- Enter ghost room
    "RRDDDDDLDUD", -- Kill ghost, enter speedup room
    "DDLLLLLL.", -- Kill minotaur, enter final room, drop the beat
    "DDDDDDD", -- Kill 3 enemies, take stairs
    function() return assertEqual(CurrentLevel.getNumber(), 2) end,
    function() return assertEqual(GrooveChain.getMultiplier(Player.getPlayerEntity(1)), 2) end,
    function() return assertEqual(Currency.get(Player.getPlayerEntity(1), Currency.Type.GOLD), 28) end,
    
    "LLDDDDLL", -- Enter west room
    "LLLLLLL....", -- Die to blue slime
    
    function() return assertEqual(CurrentLevel.getNumber(), 2) end,
    function() return assertEqual(Currency.get(Player.getPlayerEntity(1), Currency.Type.GOLD), 28) end,
    function() return assertEqual(GrooveChain.getMultiplier(Player.getPlayerEntity(1)), 2) end,
    
    "LLDDDDLL", -- Enter west room
    
    "LLLL", -- kill one enemy
    function() return assertEqual(GrooveChain.getMultiplier(Player.getPlayerEntity(1)), 2) end,

    "LLDDL", -- kill second enemy
    function() return assertEqual(GrooveChain.getMultiplier(Player.getPlayerEntity(1)), 3) end,
  },
}, {
  name = "BloodShopTeleport",
  seed = 294842629,
  steps = {
    "RRUUQRRUL", -- Enter blood shop
    "GU", -- Aggro the shopkeep
    function() return assertWorldItemAt(-1, 0, "Shopkeeper2") end,

    "..", -- Die to shopkeep

    "RRUUQRRUL", -- Enter blood shop
    "UGU", -- Move then throw, should get the same teleport
    function() return assertWorldItemAt(-1, 0, "Shopkeeper2") end,

    "..", -- Die to shopkeep

    "RRUUQRRUL", -- Enter blood shop
    "UUUGU", -- Move further up, then throw, should get the same teleport
    function() return assertWorldItemAt(-1, 2, "Shopkeeper2") end,
  },
}, {
  name = "ArenaKeepsEnemiesOnReplay",
  seed = 1939573472,
  steps = {
    "DRRRRRRRRDDDDRD....", -- Take the trapdoor
    function() return assertEqual(CurrentLevel.getNumber(), 2) end,
    function() return assertWorldItemAt(-2, -2, "Bat") end,
    function() return assertWorldItemAt( 2, -2, "Skeleton") end,
    function() return assertWorldItemAt( 2,  2, "Ghost") end,
    function() return assertWorldItemAt(-2,  2, "Dragon") end,
    "LULRU.DLRLRL", -- Almost clear the arena
    function() return assertWorldItemAt(-1, 0, "Dragon") end,
    -- function() return assertWorldItemAt(1, 0, "Wall2") end, -- TODO.
    "L", -- Kill the dragon and clear the arena
    function() return assertWorldItemAt(-1, 0, "ResourceCoin10") end,
    -- function() return assertWorldItemAt(1, 0, nil) end,

    "RRRRQR......", -- Die to bomb

    function() return assertEqual(CurrentLevel.getNumber(), 2) end,
    function() return assertWorldItemAt(-2, -2, "Bat") end,
    function() return assertWorldItemAt( 2, -2, "Skeleton") end,
    function() return assertWorldItemAt( 2,  2, "Ghost") end,
    function() return assertWorldItemAt(-2,  2, "Dragon") end,
    "LULRU.DLRLRL", -- Almost clear the arena
    function() return assertWorldItemAt(-1, 0, "Dragon") end,

    ".......", -- Die to dragon

    function() return assertEqual(CurrentLevel.getNumber(), 2) end,
    function() return assertWorldItemAt(-2, -2, "Bat") end,
    function() return assertWorldItemAt( 2, -2, "Skeleton") end,
    function() return assertWorldItemAt( 2,  2, "Ghost") end,
    function() return assertWorldItemAt(-2,  2, "Dragon") end,
  },
},{
  name = "ShrineOfSpace",
  seed = 334529790,
  steps = {
    "LLDDDLL", -- Enter shriner
    function() return assertWorldItemAt(-1, -2, "ShrineOfGlass") end,
    function() return assertWorldItemAt( 0, -2, "ShrineOfBoss") end,
    function() return assertWorldItemAt( 1, -2, "ShrineOfSpace") end,
    function() return giveMoney(50) end,
    "RUUDL", -- Tap shrine, leave

    "DLL.LLLL.....", -- Die to the ghost

    -- If shrine of space is preserved, the shriner will be in a different spot.
    -- (this also tests that we preserve 'seen shrines')

    "LLDDDLL", -- Enter shriner
    function() return assertWorldItemAt(-1, -2, "ShrineOfGlass") end,
    function() return assertWorldItemAt( 0, -2, "ShrineOfBoss") end,
    function() return assertWorldItemAt( 1, -2, "ShrineOfSpace") end,
  },
},{
  name = "TransmuteShop",
  seed = 1658736754,
  steps = {
    "UURRRRUUUU.UUUURUU", -- Grab transmute tome
    function() return assertInventoryItem("TomeTransmute") end,
    "DDDDLDDDLLLUUUUUULL", -- Enter shop
    function() return assertWorldItemAt(-1, -1, "WeaponSpear") end,
    function() return assertWorldItemAt( 0, -1, "BombGrenade3") end,
    function() return assertWorldItemAt( 1, -1, "Torch1") end,
    "A", -- Transmute
    function() return assertWorldItemAt(-1, -1, "WeaponBloodLongsword") end,
    function() return assertWorldItemAt( 0, -1, "WeaponWhip") end,
    function() return assertWorldItemAt( 1, -1, "Food1") end,
    "A", -- Transmute
    function() return assertWorldItemAt(-1, -1, "Sync_ShieldWooden") end,
    function() return assertWorldItemAt( 0, -1, "Torch2") end,
    function() return assertWorldItemAt( 1, -1, "WeaponRapier") end,
    "RRUULQ.....", -- Blow up Freddy and die

    -- Repeat the test and confirm the same items spawn / transmute
    -- (this also tests that we preserve 'seen items')

    "UURRRRUUUU.UUUURUU", -- Grab transmute tome
    function() return assertInventoryItem("TomeTransmute") end,
    "DDDDLDDDLLLUUUUUULL", -- Enter shop
    function() return assertWorldItemAt(-1, -1, "WeaponSpear") end,
    function() return assertWorldItemAt( 0, -1, "BombGrenade3") end,
    function() return assertWorldItemAt( 1, -1, "Torch1") end,
    "A", -- Transmute
    function() return assertWorldItemAt(-1, -1, "WeaponBloodLongsword") end,
    function() return assertWorldItemAt( 0, -1, "WeaponWhip") end,
    function() return assertWorldItemAt( 1, -1, "Food1") end,
    "A", -- Transmute
    function() return assertWorldItemAt(-1, -1, "Sync_ShieldWooden") end,
    function() return assertWorldItemAt( 0, -1, "Torch2") end,
    function() return assertWorldItemAt( 1, -1, "WeaponRapier") end,
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
    print("-- ALL TESTS PASSED --")
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
  print("-- TEST FAILED: " .. currentTest.name .. " --")
  runningTests = false
  Room.setAttribute(Netplay.RoomAttribute.TEMPO_MULTIPLIER, nil)
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
      print("Test " .. currentTest.name .. " failed assertion at step " .. tostring(stepIndex))
      testFailed()
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
    elseif key == "Z" then return Action.Special.ITEM_2
    elseif key == "W" then return Action.Special.SPELL_1
    -- Action.Special.SPELL_2
    elseif key == "." then return Action.Special.IDLE
    elseif key == "P" then -- Not perfect, because we burn a beat here.
      runningTests = false
      Room.setAttribute(Netplay.RoomAttribute.TEMPO_MULTIPLIER, nil)
      return nil
    elseif key == "@" then
      -- Special key which pairs the next two actions together, useful for an off-beat hit (e.g. triggering an ability on the stairs)
      local move = getNextTestMove()
      local doubleMove = getNextTestMove()
      return move, doubleMove
    end
  end

  print("Error while determining the next test move")
  testFailed()
end

Event.clientAddInput.add("injectInputs", {order="actionBuffer", sequence=-1}, function(evt)
  -- Check for pending transitions so we don't run while leaving the lobby.
  if runningTests and evt.action == Action.Special.IDLE and not GameSession.hasPendingTransition() then
    local move, doubleMove = getNextTestMove()
    if move ~= nil then
      evt.action = move
      evt.flags = Ability.getActionFlags(move)
      if doubleMove ~= nil then
        ClientActionBuffer.addAction(evt.playerID, ClientActionBuffer.findAvailableTurnID(evt.playerID, evt.turnID + 1), doubleMove, 0)
      end
    end
  end
end)