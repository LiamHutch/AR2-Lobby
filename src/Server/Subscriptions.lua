-- Paid visibility: a public private-server needs an active subscription
-- (Private.PublicSubscriptionId, a SubscriptionService id). Friends and
-- private are free. With no id configured, public is free too, so a test
-- lobby works before the subscription exists.
--
-- Checks go through MarketplaceService:GetUserSubscriptionStatusAsync, cached
-- per player for STATUS_CACHE seconds; a failed check keeps the last answer,
-- or says no the first time. A purchase prompt finishing clears the cache.

local marketplaceService = game:GetService("MarketplaceService")
local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

local private = require(replicatedStorage.Shared.Private)

local library = {}

----

local STATUS_CACHE = 60

-- [client] = { at, subscribed }
local cache = {}

-- fired with the client once a purchase prompt closes, so sessions can refresh
library.Changed = Instance.new("BindableEvent")

----

function library:Id()
	return private.PublicSubscriptionId
end

-- whether the client may set a session public
function library:CanPublic(client)
	local id = private.PublicSubscriptionId

	if not id then
		return true
	end

	local held = cache[client]

	if held and os.clock() - held.at < STATUS_CACHE then
		return held.subscribed
	end

	local worked, status = pcall(function()
		return marketplaceService:GetUserSubscriptionStatusAsync(client, id)
	end)

	local subscribed

	if worked and type(status) == "table" then
		subscribed = status.IsSubscribed == true
	else
		warn("Subscriptions: status check failed for", client.Name, status)
		subscribed = held and held.subscribed or false
	end

	cache[client] = { at = os.clock(), subscribed = subscribed }

	return subscribed
end

-- asks the client to open the subscription purchase prompt
function library:Offer(client, remote)
	local id = private.PublicSubscriptionId

	if id and client.Parent then
		remote:FireClient(client, "subscribe", id)
	end
end

function library:Forget(client)
	cache[client] = nil
end

----

marketplaceService.PromptSubscriptionPurchaseFinished:Connect(function(client, id, purchased)
	if id == private.PublicSubscriptionId then
		cache[client] = nil
		library.Changed:Fire(client)
	end
end)

playersService.PlayerRemoving:Connect(function(client)
	cache[client] = nil
end)

return library
