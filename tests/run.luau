--!nocheck
-- Ejecuta todas las baterías de pruebas:  lune run tests/run            (desde la raíz del repo)
-- Una sola batería:                        lune run tests/run Economy
--
-- Cada archivo tests/*Tests.luau devuelve una función. Se cargan todos primero y se ejecutan
-- después: Lune no permite registrar los mocks de `@lune/roblox` mientras hay un `require` en curso.
local fs = require("@lune/fs")
local process = require("@lune/process")
local TestKit = require("./lib/TestKit")

local filter = process.args[1]
local names = {}
for _, name in ipairs(fs.readDir("tests")) do
	local base = string.match(name, "^(.+Tests)%.luau$")
	if base and (not filter or string.find(string.lower(base), string.lower(filter), 1, true)) then
		table.insert(names, base)
	end
end
table.sort(names)

local suites = {}
for _, base in ipairs(names) do
	local ok, result = pcall(function()
		return require("./" .. base)
	end)
	table.insert(suites, { name = base, ok = ok, result = result })
end

for _, suite in ipairs(suites) do
	if suite.ok and type(suite.result) == "function" then
		local ok, err = xpcall(suite.result, debug.traceback)
		if not ok then
			TestKit.suite(suite.name)
			TestKit.test("(la batería terminó sin errores fuera de los tests)", function()
				error(err, 0)
			end)
		end
	else
		TestKit.suite(suite.name)
		TestKit.test("(la batería se cargó y devuelve una función)", function()
			error(tostring(suite.result), 0)
		end)
	end
end

local results = TestKit.results()
print(string.format("\n%d passed, %d failed (%d suites)", results.passed, results.failed, #names))
if results.failed > 0 then
	print("\nFallos:")
	for _, failure in ipairs(results.failures) do
		print(string.format("  [%s] %s", failure.suite, failure.name))
	end
	process.exit(1)
end
