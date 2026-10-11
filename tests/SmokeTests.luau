--!nocheck
local Harness = require("./lib/Harness")
local TestKit = require("./lib/TestKit")
local expect = TestKit.expect

return function()
TestKit.suite("Smoke: arranque del servidor")

TestKit.test("el servidor arranca y un jugador entra con parcela y criatura inicial", function()
	local h = Harness.new({ isStudio = false })
	local s = h:bootServer()
	local player, session = h:joinPlayer(101, "Ana")
	expect.truthy(session, "session")
	expect.equal(session.plotIndex, 1)
	expect.equal(session.profile.coins, 50)
	local count = 0
	for _ in pairs(session.profile.creatures) do count += 1 end
	expect.equal(count, 1)
	for _, w in ipairs(h.warnings) do print("    warn: " .. w) end
	expect.equal(#h.warnings, 0, "warnings")
	local state = h:stateFor(101)
	expect.equal(state.coins, 50)
	expect.truthy(state.creatures and #state.creatures == 1, "creatures view")
end)

end
