-- Construye el modelo visual de una especie. Lo usa el cliente (CreatureController) y los tests.
-- Para sustituir una especie por un modelo de artista basta con cambiar su módulo en Species/
-- manteniendo los anclajes (Head, Mouth, Top, AuraAnchor, Ground) y las articulaciones.
local CreatureConfig = require(script.Parent.Parent.Config.CreatureConfig)
local Kit = require(script.Parent.Kit)

local CreatureBuilder = {}

local speciesModules = {}

function CreatureBuilder.speciesModule(speciesId)
	local cached = speciesModules[speciesId]
	if cached then
		return cached
	end
	local def = CreatureConfig.Species[speciesId]
	if not def then
		return nil
	end
	local moduleScript = script.Parent.Species:FindFirstChild(def.builder)
	if not moduleScript then
		return nil
	end
	local module = require(moduleScript)
	speciesModules[speciesId] = module
	return module
end

-- Devuelve un Visual (ver Kit.Visual) o nil si la especie no existe.
function CreatureBuilder.build(speciesId)
	local module = CreatureBuilder.speciesModule(speciesId)
	if not module then
		return nil
	end
	local kit = Kit.new(speciesId, module.unit or 1)
	local info = module.build(kit)
	local visual = kit:finish(info)
	visual.species = module
	return visual
end

return CreatureBuilder
