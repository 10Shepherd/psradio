-- Token bucket. `now` is a millisecond clock (GetGameTimer()).
local Bucket = {}
Bucket.__index = Bucket

function PSR.newBucket(ratePerSecond, burst)
    return setmetatable({ rate = ratePerSecond, burst = burst, tokens = burst, last = nil }, Bucket)
end

function Bucket:take(now, cost)
    cost = cost or 1
    if self.last then
        local elapsed = (now - self.last) / 1000
        if elapsed > 0 then
            self.tokens = math.min(self.burst, self.tokens + elapsed * self.rate)
        end
    end
    self.last = now
    if self.tokens >= cost then
        self.tokens = self.tokens - cost
        return true
    end
    return false
end
