--!nocheck
-- Mini framework de tests: describe/it con aserciones y resumen final.
local TestKit = {}

local results = { passed = 0, failed = 0, failures = {} }
local currentSuite = ""

function TestKit.suite(name)
	currentSuite = name
	print("\n" .. name)
end

function TestKit.test(name, fn)
	local ok, err = xpcall(fn, function(message)
		return tostring(message) .. "\n" .. debug.traceback("", 2)
	end)
	if ok then
		results.passed += 1
		print("  ✓ " .. name)
	else
		results.failed += 1
		table.insert(results.failures, { suite = currentSuite, name = name, err = err })
		print("  ✗ " .. name)
		print("      " .. string.gsub(tostring(err), "\n", "\n      "))
	end
end

local expect = {}

function expect.equal(actual, expected, label)
	if actual ~= expected then
		error(string.format("%sexpected %s, got %s", label and (label .. ": ") or "", tostring(expected), tostring(actual)), 2)
	end
end

function expect.near(actual, expected, epsilon, label)
	if type(actual) ~= "number" or math.abs(actual - expected) > (epsilon or 1e-6) then
		error(string.format("%sexpected ~%s, got %s", label and (label .. ": ") or "", tostring(expected), tostring(actual)), 2)
	end
end

function expect.truthy(value, label)
	if not value then
		error((label or "value") .. " expected to be truthy, got " .. tostring(value), 2)
	end
end

function expect.falsy(value, label)
	if value then
		error((label or "value") .. " expected to be falsy, got " .. tostring(value), 2)
	end
end

function expect.greater(actual, than, label)
	if not (type(actual) == "number" and actual > than) then
		error(string.format("%sexpected > %s, got %s", label and (label .. ": ") or "", tostring(than), tostring(actual)), 2)
	end
end

function expect.atMost(actual, limit, label)
	if not (type(actual) == "number" and actual <= limit) then
		error(string.format("%sexpected <= %s, got %s", label and (label .. ": ") or "", tostring(limit), tostring(actual)), 2)
	end
end

function expect.fails(fn, label)
	local ok = pcall(fn)
	if ok then
		error((label or "function") .. " expected to error", 2)
	end
end

TestKit.expect = expect

function TestKit.results()
	return results
end

return TestKit
