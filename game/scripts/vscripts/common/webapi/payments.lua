Payments = Payments or {}

ACTIVE_POLLING_DURATION = 600

function Payments:Init()
	RegisterCustomEventListener("Payments:request_url", Payments.GetPaymentURL, Payments)

	Payments.pending_payments = {}
	Payments.timeout_timers = {}
	Payments.valid_payment_methods = {
		stripe = {
			card = true,
			alipay = true,
			wechat_pay = true,
		},
		-- xsolla has own method selection inside
		xsolla = {
			card = true,
		}
	}
end


function Payments:ValidatePaymentMethod(system, method)
	if not Payments.valid_payment_methods[system] then return false end
	if not Payments.valid_payment_methods[system][method] then return false end

	return true
end


function Payments:SetPaymentStatus(player_id, status)
	-- print("[Payments] payment status changed", player_id, status)
	Payments.pending_payments[player_id] = status

	if status then
		MatchEvents:SetActivePolling(true)
		if Payments.timeout_timers[player_id] then Timers:RemoveTimer(Payments.timeout_timers[player_id]) end
		Payments.timeout_timers[player_id] = Timers:CreateTimer(ACTIVE_POLLING_DURATION, function()
			-- print("[Payments] payment status timeout for ", player_id)
			Payments:SetPaymentStatus(player_id, false)
		end)
	else
		if Payments.timeout_timers[player_id] then
			Timers:RemoveTimer(Payments.timeout_timers[player_id])
			Payments.timeout_timers[player_id] = nil
		end
		if next(Payments.pending_payments) == nil then
			MatchEvents:SetActivePolling(false)
		end
	end
end


function Payments:GetPaymentURL(event)
	local player_id = event.PlayerID
	if not player_id or not PlayerResource:IsValidPlayerID(player_id) then return end

	local steam_id = Battlepass:GetSteamId(player_id)

	if not Payments:ValidatePaymentMethod(event.payment_system, event.payment_method) then
		print("[Payments] invalid payment method or system: ", event.payment_method, event.payment_system)
		return
	end

	if event.quantity <= 0 then
		print("[Payments] invalid item quantity: ", event.quantity)
		return
	end

	WebApi:Send(
		"payment/get_payment_url",
		{
			steam_id = steam_id,
			match_id = WebApi.matchId,
			product_name = event.product_name,
			quantity = event.quantity or 1,
			payment_method = event.payment_method,
			payment_system = event.payment_system,
			region = event.region,
			as_gift_code = event.as_gift_code or false,
			custom_game = WebApi.customGame,
			map_name = GetMapName(),
		},
		function(response)
			local player = PlayerResource:GetPlayer(player_id)
			if not player or player:IsNull() then return end

			Payments:SetPaymentStatus(player_id, true)

			CustomGameEventManager:Send_ServerToPlayer(player, "Payments:open_url", {
				url = response.url,
				method = response.method,
			})
		end,
		function(error)
			print("[Payments] failed to get payment url for", event.product_name)
		end
	)
end


MatchEvents.event_handlers.payment_success = function(event_data)
	local steam_id = event_data.steamId
	local player_id = GetPlayerIdBySteamId(steam_id)

	WebApi:ProcessMetadata(player_id, steam_id, event_data)
	Payments:SetPaymentStatus(player_id, false)

	Toasts:NewForPlayer(player_id, "payment_success", event_data)
end


Payments:Init()
