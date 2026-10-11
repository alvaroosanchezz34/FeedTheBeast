-- Validación de argumentos recibidos por remotos (pura).
local Validate = {}

function Validate.isFinite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function Validate.isInteger(n, min, max)
	if not Validate.isFinite(n) or n % 1 ~= 0 then
		return false
	end
	if min and n < min then
		return false
	end
	if max and n > max then
		return false
	end
	return true
end

function Validate.isNumber(n, min, max)
	if not Validate.isFinite(n) then
		return false
	end
	if min and n < min then
		return false
	end
	if max and n > max then
		return false
	end
	return true
end

-- Identificador: letras, números y guion bajo, longitud limitada.
function Validate.isId(s, maxLen)
	if type(s) ~= "string" then
		return false
	end
	local len = #s
	if len == 0 or len > (maxLen or 40) then
		return false
	end
	return string.match(s, "^[%w_]+$") ~= nil
end

function Validate.isString(s, maxLen)
	return type(s) == "string" and #s <= (maxLen or 200)
end

function Validate.isOneOf(v, list)
	for _, item in ipairs(list) do
		if item == v then
			return true
		end
	end
	return false
end

-- Valida una lista de argumentos contra un esquema: { {type="id"}, {type="int", min=1, max=50}, ... }
-- Devuelve (ok, motivo). Rechaza argumentos de más.
function Validate.args(schema, args, argCount)
	argCount = argCount or #args
	if argCount > #schema then
		return false, "too_many_args"
	end
	for i, rule in ipairs(schema) do
		local v = args[i]
		if v == nil then
			if not rule.optional then
				return false, "missing_arg_" .. i
			end
		elseif rule.type == "id" then
			if not Validate.isId(v, rule.maxLen) then
				return false, "bad_id_" .. i
			end
		elseif rule.type == "int" then
			if not Validate.isInteger(v, rule.min, rule.max) then
				return false, "bad_int_" .. i
			end
		elseif rule.type == "number" then
			if not Validate.isNumber(v, rule.min, rule.max) then
				return false, "bad_number_" .. i
			end
		elseif rule.type == "string" then
			if not Validate.isString(v, rule.maxLen) then
				return false, "bad_string_" .. i
			end
		elseif rule.type == "enum" then
			if type(v) ~= "string" or not Validate.isOneOf(v, rule.values) then
				return false, "bad_enum_" .. i
			end
		elseif rule.type == "setting" then
			-- Valor de ajuste: string corto o número finito.
			if not (Validate.isString(v, 20) or Validate.isFinite(v)) then
				return false, "bad_setting_" .. i
			end
		elseif rule.type == "boolean" then
			if type(v) ~= "boolean" then
				return false, "bad_boolean_" .. i
			end
		else
			return false, "unknown_rule_" .. i
		end
	end
	return true, nil
end

return Validate
