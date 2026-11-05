--!strict
--[[
	RateLimiter.luau — giới hạn tần suất theo người chơi (token bucket).

	  local limiter = RateLimiter.new(6, 3)   -- tối đa 6 lần / 3 giây (cho phép bùng nổ 6 lần)
	  if not limiter:Allow(player) then return end

	Bảng bucket dùng khoá yếu nên không rò rỉ bộ nhớ khi người chơi rời game.
]]

type Bucket = {
	Tokens: number,
	Last: number,
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable(
	{} :: {
		_capacity: number,
		_refillPerSecond: number,
		_buckets: { [Player]: Bucket },
	},
	RateLimiter
))

function RateLimiter.new(maxCalls: number, windowSeconds: number): RateLimiter
	local buckets = setmetatable({}, { __mode = "k" }) :: any
	return setmetatable({
		_capacity = maxCalls,
		_refillPerSecond = maxCalls / windowSeconds,
		_buckets = buckets :: { [Player]: Bucket },
	}, RateLimiter)
end

-- true nếu cho phép gọi (và tiêu một token), false nếu vượt giới hạn
function RateLimiter.Allow(self: RateLimiter, player: Player): boolean
	local now = os.clock()
	local bucket = self._buckets[player]
	if not bucket then
		bucket = { Tokens = self._capacity, Last = now }
		self._buckets[player] = bucket
	end

	local elapsed = now - bucket.Last
	bucket.Last = now
	bucket.Tokens = math.min(self._capacity, bucket.Tokens + elapsed * self._refillPerSecond)

	if bucket.Tokens >= 1 then
		bucket.Tokens -= 1
		return true
	end
	return false
end

function RateLimiter.Clear(self: RateLimiter, player: Player)
	self._buckets[player] = nil
end

return RateLimiter
