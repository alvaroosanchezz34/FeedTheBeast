-- Token bucket puro. `now` se inyecta para poder probarlo.
local RateLimiter = {}
RateLimiter.__index = RateLimiter

-- rate: tokens por segundo. burst: capacidad máxima.
function RateLimiter.new(rate, burst)
	return setmetatable({ rate = rate, burst = burst, buckets = {} }, RateLimiter)
end

function RateLimiter:allow(key, now, cost)
	cost = cost or 1
	local bucket = self.buckets[key]
	if not bucket then
		bucket = { tokens = self.burst, last = now }
		self.buckets[key] = bucket
	end
	local elapsed = math.max(0, now - bucket.last)
	bucket.tokens = math.min(self.burst, bucket.tokens + elapsed * self.rate)
	bucket.last = now
	if bucket.tokens >= cost then
		bucket.tokens -= cost
		return true
	end
	return false
end

function RateLimiter:forget(key)
	self.buckets[key] = nil
end

return RateLimiter
