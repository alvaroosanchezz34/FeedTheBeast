-- Representación visual de las mutaciones sobre un Visual (ver Kit).
-- No duplica modelos ni código por especie: cada pieza tiene un rol (Body, Belly, Accent, Detail)
-- y la mutación define qué material/color recibe cada rol. Los ojos, la boca y los dientes no se
-- tocan para que la criatura siga siendo reconocible.
local MutationConfig = require(script.Parent.Parent.Config.MutationConfig)

local MutationVisuals = {}

-- Aplica (o quita, con NORMAL) la mutación a las piezas del visual.
function MutationVisuals.apply(visual, mutationId)
	local mutation = MutationConfig.Mutations[mutationId] or MutationConfig.Mutations.NORMAL
	local overrides = mutation.visual
	for _, record in ipairs(visual.records) do
		local override = overrides and record.role and overrides[record.role] or nil
		local part = record.part
		if override then
			part.Color = override.color or record.baseColor
			part.Material = override.material or record.baseMaterial
			part.Reflectance = override.reflectance or 0
			-- Las piezas translúcidas (p. ej. el orbe de Glorb) conservan su transparencia.
			part.Transparency = record.hidden and 1 or record.baseTransparency
		else
			part.Color = record.baseColor
			part.Material = record.baseMaterial
			part.Reflectance = record.baseReflectance
			part.Transparency = record.hidden and 1 or record.baseTransparency
		end
	end
	visual.mutation = mutation.id
	return mutation
end

-- Cuántas piezas cambia una mutación en un visual (lo usan los tests para garantizar que la
-- mutación se distingue en todas las especies).
function MutationVisuals.affectedCount(visual, mutationId)
	local mutation = MutationConfig.Mutations[mutationId]
	if not mutation or not mutation.visual then
		return 0
	end
	local count = 0
	for _, record in ipairs(visual.records) do
		if record.role and mutation.visual[record.role] then
			count += 1
		end
	end
	return count
end

return MutationVisuals
