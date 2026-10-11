-- Máquina de estados pura de un objeto robable (caja de comida).
-- No conoce instancias de Roblox: TheftService la envuelve y aplica los efectos en el mundo.
local StealStateMachine = {}
StealStateMachine.__index = StealStateMachine

local S = {
	AVAILABLE = "AVAILABLE",
	BEING_STOLEN = "BEING_STOLEN",
	CARRIED = "CARRIED",
	RECOVERED = "RECOVERED",
	DELIVERED = "DELIVERED",
	PROTECTED = "PROTECTED",
}
StealStateMachine.States = S

local TRANSITIONS = {
	[S.AVAILABLE] = { [S.CARRIED] = true, [S.PROTECTED] = true },
	[S.CARRIED] = { [S.BEING_STOLEN] = true, [S.DELIVERED] = true, [S.AVAILABLE] = true },
	[S.PROTECTED] = { [S.CARRIED] = true, [S.DELIVERED] = true, [S.AVAILABLE] = true },
	[S.BEING_STOLEN] = { [S.CARRIED] = true, [S.RECOVERED] = true, [S.PROTECTED] = true, [S.AVAILABLE] = true },
	[S.RECOVERED] = { [S.PROTECTED] = true, [S.CARRIED] = true, [S.DELIVERED] = true, [S.AVAILABLE] = true },
	[S.DELIVERED] = {},
}

function StealStateMachine.canTransition(from, to)
	local row = TRANSITIONS[from]
	return row ~= nil and row[to] == true
end

function StealStateMachine.new(id, tier)
	return setmetatable({
		id = id,
		tier = tier,
		state = S.AVAILABLE,
		carrier = nil, -- userId
		thief = nil, -- userId con robo en curso
		previousCarrier = nil,
		firstCarrier = nil,
		stolenAt = nil,
		protectedUntil = 0,
		transfers = 0,
	}, StealStateMachine)
end

function StealStateMachine:_set(to)
	if not StealStateMachine.canTransition(self.state, to) then
		return false
	end
	self.state = to
	return true
end

-- Un jugador recoge la caja del suelo.
function StealStateMachine:pickup(userId, now, protectSeconds)
	if self.state ~= S.AVAILABLE then
		return false, "not_available"
	end
	if protectSeconds and protectSeconds > 0 then
		self:_set(S.PROTECTED)
		self.protectedUntil = now + protectSeconds
	else
		self:_set(S.CARRIED)
	end
	self.carrier = userId
	self.firstCarrier = self.firstCarrier or userId
	return true, nil
end

-- Expira la protección temporal.
function StealStateMachine:tick(now)
	if self.state == S.PROTECTED and now >= self.protectedUntil and self.carrier ~= nil then
		self:_set(S.CARRIED)
		return true
	end
	return false
end

-- Empieza un robo (el ladrón empieza a mantener el prompt).
-- opts = { victimProtected = bool }
function StealStateMachine:beginSteal(thiefId, now, opts)
	self:tick(now)
	if self.state == S.PROTECTED then
		return false, "protected"
	end
	if self.state ~= S.CARRIED then
		return false, "not_carried"
	end
	if thiefId == self.carrier then
		return false, "own_crate"
	end
	if opts and opts.victimProtected then
		return false, "victim_protected"
	end
	self:_set(S.BEING_STOLEN)
	self.thief = thiefId
	return true, nil
end

-- El ladrón suelta el prompt antes de tiempo o falla una validación.
function StealStateMachine:cancelSteal(thiefId)
	if self.state ~= S.BEING_STOLEN or (thiefId ~= nil and self.thief ~= thiefId) then
		return false
	end
	self.thief = nil
	self:_set(S.CARRIED)
	return true
end

-- Completa el robo. Devuelve (ok, info) con info = { victim, recovered }.
function StealStateMachine:completeSteal(thiefId, now, immunitySeconds, recoveryWindow)
	if self.state ~= S.BEING_STOLEN or self.thief ~= thiefId then
		return false, "not_stealing"
	end
	local victim = self.carrier
	local recovered = self.previousCarrier == thiefId
		and self.stolenAt ~= nil
		and (now - self.stolenAt) <= (recoveryWindow or 0)
	if recovered then
		self:_set(S.RECOVERED)
	end
	self.previousCarrier = victim
	self.carrier = thiefId
	self.thief = nil
	self.stolenAt = now
	self.transfers += 1
	if immunitySeconds and immunitySeconds > 0 then
		self:_set(S.PROTECTED)
		self.protectedUntil = now + immunitySeconds
	else
		self:_set(S.CARRIED)
	end
	return true, { victim = victim, recovered = recovered }
end

-- La caja cae al suelo (desconexión, muerte, anti-teleport, soltar).
function StealStateMachine:drop()
	if self.state == S.DELIVERED or self.state == S.AVAILABLE then
		return false
	end
	self.previousCarrier = self.carrier or self.previousCarrier
	self.carrier = nil
	self.thief = nil
	self.protectedUntil = 0
	self:_set(S.AVAILABLE)
	return true
end

-- Un jugador abandona el servidor: resuelve el estado de forma segura.
-- Devuelve "dropped" si la caja cayó, "cancelled" si solo se canceló un robo en curso, o nil.
function StealStateMachine:playerLeft(userId)
	if self.state == S.DELIVERED then
		return nil
	end
	if self.carrier == userId then
		self:drop()
		return "dropped"
	end
	if self.state == S.BEING_STOLEN and self.thief == userId then
		self:cancelSteal(userId)
		return "cancelled"
	end
	if self.previousCarrier == userId then
		self.previousCarrier = nil
	end
	return nil
end

-- Entrega en la parcela del portador. Devuelve (ok, info) con info = { stolen = bool }.
function StealStateMachine:deliver(userId)
	if self.carrier ~= userId then
		return false, "not_carrier"
	end
	if self.state == S.BEING_STOLEN then
		-- La entrega gana: se cancela el robo en curso.
		self:cancelSteal(nil)
	end
	if not self:_set(S.DELIVERED) then
		return false, "bad_state"
	end
	-- "Robada" = quien la entrega no es quien la recogió del suelo originalmente.
	local info = { stolen = self.transfers > 0 and self.firstCarrier ~= userId }
	self.carrier = nil
	return true, info
end

function StealStateMachine:isTerminal()
	return self.state == S.DELIVERED
end

return StealStateMachine
