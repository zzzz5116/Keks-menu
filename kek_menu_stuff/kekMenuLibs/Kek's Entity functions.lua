-- Copyright © 2020-2022 Kektram

local kek_entity <const> = {version = "1.2.7"}

local lang <const> = require("Kek's Language").lang
local memoize <const> = require("Kek's Memoize")
local location_mapper <const> = require("Kek's Location mapper")
local vehicle_mapper <const> = require("Kek's Vehicle mapper")
local essentials <const> = require("Kek's Essentials")
local enums <const> = require("Kek's Enums")
local keys_and_input <const> = require("Kek's Keys and input")
local object_mapper <const> = require("Kek's Object mapper")
local ped_mapper <const> = require("Kek's Ped mapper")
local settings <const> = require("Kek's Settings")
local globals <const> = require("Kek's Globals")

kek_entity.user_vehicles = {}

kek_entity.entity_manager = {
	entities = {},
	counts = {
		ped = 0, 
		object = 0, 
		vehicle = 0
	},
	entity_type_to_str = {
		[3] = "vehicle",
		[4] = "ped",
		[5] = "object"
	},
	flag_to_str = {
		[1 << 5] = "vehicle",
		[1 << 6] = "ped",
		[1 << 7] = "object"
	},
	entity_type_to_return_type = setmetatable({
		[3] = "is_vehicle_limit_not_breached",
		[4] = "is_ped_limit_not_breached",
		[5] = "is_object_limit_not_breached"
	}, {
		__index = function()
			return "is_object_limit_not_breached"
		end
	})
}

do
	local update_buf <const> = {} -- Faster than creating a new table every time. This function is called tens of thousands of times.
	function kek_entity.entity_manager:update() -- Weight can't be more than 31. Weight has 5 bits to work with.
		for Entity, flags in pairs(self.entities) do
			if not entity.is_an_entity(Entity) then
				local weight <const> = flags & 0x1F
				local entity_type <const> = flags & 0xE0
				local type_string <const> = self.flag_to_str[entity_type]
				self.counts[type_string] = self.counts[type_string] - weight
				self.entities[Entity] = nil
			end
		end
		update_buf.is_ped_limit_not_breached = self.counts.ped <= settings.valuei["ped limits"].value * 10

		update_buf.is_object_limit_not_breached = self.counts.object < settings.valuei["object limits"].value * 10

		update_buf.is_vehicle_limit_not_breached = self.counts.vehicle < settings.valuei["vehicle limits"].value * 10

		return update_buf
	end

	function kek_entity.entity_manager:clear(dont_clear_user_vehicle)
		self:update()
		for Entity in pairs(essentials.deep_copy(self.entities)) do
			if entity.is_an_entity(Entity) and (not dont_clear_user_vehicle or player.get_player_vehicle(player.player_id()) ~= Entity) and kek_entity.get_control_of_entity(Entity) then
				kek_entity.hard_remove_entity_and_its_attachments(Entity)
			end
		end
		self:update()
	end
end

setmetatable(kek_entity.entity_manager, {
	__newindex = function(Table, Entity, weight)
		local entity_type <const> = entity.get_entity_type(Entity)
		if entity_type >= 3 
		and entity_type <= 5
		and not Table.entities[Entity] 
		and (not entity.is_entity_a_ped(Entity) or not ped.is_ped_a_player(Entity)) then
			weight = math.tointeger(weight)
			if math.type(weight) ~= "integer" or weight > 31 or (weight ~= 0 and weight < 1) then -- In case other scripts accidentally pass a value as weight
				weight = 10
			end
			local type_string <const> = Table.entity_type_to_str[entity.get_entity_type(Entity)] or "object"
			local flags <const> = weight | (1 << (2 + entity_type))

			Table.entities[Entity] = flags
			Table.counts[type_string] = Table.counts[type_string] + weight
		end
	end
})

function kek_entity.get_random_offset(...)
	local min_random_range <const>,
	max_random_range <const>,
	min_magnitude <const>,
	max_magnitude <const> = ...
	essentials.assert(max_random_range * 0.8 >= min_random_range, "Max random range must be at least 20% bigger than min random range.", max_random_range, min_random_range)
	essentials.assert(max_magnitude * 0.8 > min_magnitude, "Max magnitude must be at least 20% bigger than min magnitude.", max_magnitude, min_magnitude)
	essentials.assert(max_magnitude > 0 and min_magnitude > 0, "Min and max magnitude must be a positive number.", max_magnitude, min_magnitude)
	local min_absolute_number = min_random_range
	if min_absolute_number < 0 and max_random_range > 0 then
		min_absolute_number = 0
	elseif min_absolute_number < 0 and max_random_range < 0 then
		min_absolute_number = math.abs(math.max(min_random_range, max_random_range))
	end
	local max_absolute_number <const> = math.max(math.abs(min_random_range), math.abs(max_random_range))
	essentials.assert(
		memoize.v3(
			min_absolute_number,
			min_absolute_number,
			0
		):magnitude() < max_magnitude * 0.8,
		"Min random range is too big.",
		min_absolute_number,
		max_absolute_number
	)
	essentials.assert(
		memoize.v3(
			max_absolute_number, 
			max_absolute_number, 
			0
		):magnitude() > min_magnitude * 1.2, 
		"Max random range is too small.",
		min_absolute_number,
		max_absolute_number
	)
	local offset
	repeat 
	--[[
		Any combination of arguments that could cause infinite loop will raise error.
		The random range is required to be reasonable and will raise error if it's too small.
	--]]
		offset = v3(
			math.random(min_random_range, max_random_range),
			math.random(min_random_range, max_random_range), 
			0
		)
		local dist <const> = offset:magnitude()
	until dist >= min_magnitude and dist <= max_magnitude
	return offset
end

function kek_entity.get_control_of_entity(...)
	local Entity <const>, time_to_wait <const>, no_condition <const>, send_msg <const> = ...
	if not network.has_control_of_entity(Entity) 
	and entity.is_an_entity(Entity) 
	and (not entity.is_entity_a_ped(Entity) or not ped.is_ped_a_player(Entity)) 
	and globals.is_fully_transitioned_into_session()
	and (no_condition or kek_entity.entity_manager:update()[kek_entity.entity_manager.entity_type_to_return_type[entity.get_entity_type(Entity)]]) then
		local time <const> = utils.time_ms() + (time_to_wait or 1000)
		network.request_control_of_entity(Entity, true)
		while not network.has_control_of_entity(Entity) and entity.is_an_entity(Entity) and time > utils.time_ms() do
			system.yield(0)
		end
	end
	if send_msg and not network.has_control_of_entity(Entity) then
		essentials.msg(lang["Failed to get control. If you're blocking \"give control\" in net event hooks, disable it. Even if it's disabled, it can fail to get control for a variety of reasons."], "blue", 8)
	end
	return network.has_control_of_entity(Entity)
end

function kek_entity.set_wheel_type(Vehicle, wheel_type)
	if entity.is_an_entity(Vehicle) then
		essentials.assert(entity.is_entity_a_vehicle(Vehicle), "Expected a vehicle from argument \"Vehicle\".")
		if kek_entity.get_control_of_entity(Vehicle) then
			vehicle.set_vehicle_wheel_type(Vehicle, wheel_type)
			vehicle.set_vehicle_mod_kit_type(Vehicle, 0)
			vehicle.set_vehicle_mod(
				Vehicle, 
				enums.vehicle_mods.wheel_customization, 
				math.random(0, vehicle.get_num_vehicle_mods(Vehicle, enums.vehicle_mods.wheel_customization) - 1)
			)
		end
	end
end

kek_entity.spawn_queue, kek_entity.spawn_queue_id = {}, 0
local function wait_until_spawn_can_be_done()
	kek_entity.spawn_queue_id = kek_entity.spawn_queue_id + 1
	local local_id <const> = kek_entity.spawn_queue_id
	kek_entity.spawn_queue[#kek_entity.spawn_queue + 1] = local_id
	while kek_entity.spawn_queue[1] ~= local_id and globals.is_fully_transitioned_into_session() do
		system.yield(0)
	end
end

function kek_entity.spawn_networked_vehicle(...)
	local hash <const>, coords_and_heading <const>, properties <const> = ...
	essentials.assert(hash and streaming.is_model_a_vehicle(hash), "Tried to use an invalid model hash.", hash)
	wait_until_spawn_can_be_done()
	local Vehicle = 0
	if globals.is_fully_transitioned_into_session() then -- Clears spawn queue immediately if new session
		local status <const> = kek_entity.request_model(hash)
		if status then
			local coords <const>, dir <const> = coords_and_heading()
			Vehicle = vehicle.create_vehicle(hash, coords, dir, true, false, 10)
			if settings.toggle["Always f1 wheels on #vehicle#"].on then
				kek_entity.set_wheel_type(Vehicle, enums.wheel_types.f1_wheels)				
			end
			if properties.max then
				kek_entity.max_car(Vehicle)
			elseif type(settings.in_use["Plate vehicle text"]) == "string" then -- Crashes if plate text is nil
				vehicle.set_vehicle_number_plate_text(Vehicle, settings.in_use["Plate vehicle text"])
			end
			decorator.decor_set_int(Vehicle, "MPBitset", 1 << 10) -- Stops the game from kicking people out of the vehicle
			if properties.persistent then -- They will never leave memory automatically, only when removed by you or someone.
				entity.set_entity_as_mission_entity(Vehicle, true, true)
				entity.set_entity_should_freeze_waiting_on_collision(Vehicle, false)
				kek_entity.constantize_network_id(Vehicle)
			end
			if properties.godmode then
				entity.set_entity_god_mode(Vehicle, true)
			end
		end
	end
	streaming.set_model_as_no_longer_needed(hash) -- The game will crash if requesting many hashes and never setting as no longer needed
	table.remove(kek_entity.spawn_queue, 1)
	return Vehicle
end

function kek_entity.spawn_networked_mission_vehicle(...) -- Players won't be able to drive these vehicles
	local hash <const>, coords_and_heading <const> = ...
	essentials.assert(hash and streaming.is_model_a_vehicle(hash), "Tried to use an invalid model hash.", hash)
	wait_until_spawn_can_be_done()
	local Vehicle = 0
	if globals.is_fully_transitioned_into_session() then -- Clears spawn queue immediately if new session
		local status <const> = kek_entity.request_model(hash)
		if status then
			local coords <const>, dir <const> = coords_and_heading()
			Vehicle = vehicle.create_vehicle(hash, coords, dir, true, false, 10)
			kek_entity.max_car(Vehicle)
			entity.set_entity_as_mission_entity(Vehicle, true, true)
			entity.set_entity_should_freeze_waiting_on_collision(Vehicle, false)
			kek_entity.constantize_network_id(Vehicle)
			network.set_network_id_can_migrate(network.veh_to_net(Vehicle), false)
		end
	end
	streaming.set_model_as_no_longer_needed(hash) -- The game will crash if requesting many hashes and never setting as no longer needed
	table.remove(kek_entity.spawn_queue, 1)
	return Vehicle
end

function kek_entity.spawn_local_mission_vehicle(...) -- Players won't be able to drive these vehicles
	local hash <const>, coords_and_heading <const> = ...
	essentials.assert(hash and streaming.is_model_a_vehicle(hash), "Tried to use an invalid model hash.", hash)
	wait_until_spawn_can_be_done()
	local Vehicle = 0
	if globals.is_fully_transitioned_into_session() then -- Clears spawn queue immediately if new session
		local status <const> = kek_entity.request_model(hash)
		if status then
			local coords <const>, dir <const> = coords_and_heading()
			Vehicle = vehicle.create_vehicle(hash, coords, dir, false, true, 10)
			entity.set_entity_as_mission_entity(Vehicle, true, true)
		end
	end
	streaming.set_model_as_no_longer_needed(hash) -- The game will crash if requesting many hashes and never setting as no longer needed
	table.remove(kek_entity.spawn_queue, 1)
	return Vehicle
end

function kek_entity.spawn_networked_ped(...)
	local hash <const>, coords_and_heading <const>, ped_type <const> = ...
	essentials.assert(hash and streaming.is_model_a_ped(hash), "Tried to use an invalid model hash.", hash)
	essentials.assert(not ped_mapper.BLACKLISTED_PEDS[hash], "Tried to spawn a crash ped.")
	wait_until_spawn_can_be_done()
	local Ped = 0
	if globals.is_fully_transitioned_into_session() then -- Clears spawn queue immediately if new session
		local status <const> = kek_entity.request_model(hash)
		if status then
			local coords <const>, dir <const> = coords_and_heading()
			Ped = ped.create_ped(
				ped_type or enums.ped_types.civmale, -- Ped type is irrelevant in most cases
				hash, 
				coords, 
				dir, 
				true, 
				false, 
				15
			)
			system.yield(0)
			ped.clear_ped_tasks_immediately(Ped) -- Peds won't start animation & possibly other problems if not clearing tasks.
			entity.set_entity_should_freeze_waiting_on_collision(Ped, false)
			entity.set_entity_as_mission_entity(Ped, false, false)
			kek_entity.constantize_network_id(Ped)
			network.set_network_id_can_migrate(network.ped_to_net(Ped), false)
		end
	end
	streaming.set_model_as_no_longer_needed(hash) -- The game will crash if requesting many hashes and never setting as no longer needed
	table.remove(kek_entity.spawn_queue, 1)
	return Ped
end

function kek_entity.spawn_local_ped(...)
	local hash <const>, coords_and_heading <const>, ped_type <const> = ...
	essentials.assert(hash and streaming.is_model_a_ped(hash), "Tried to use an invalid model hash.", hash)
	essentials.assert(not ped_mapper.BLACKLISTED_PEDS[hash], "Tried to spawn a crash ped.")
	wait_until_spawn_can_be_done()
	local Ped = 0
	if globals.is_fully_transitioned_into_session() then -- Clears spawn queue immediately if new session
		local status <const> = kek_entity.request_model(hash)
		if status then
			local coords <const>, dir <const> = coords_and_heading()
			Ped = ped.create_ped(
				ped_type or enums.ped_types.civmale, -- Ped type is irrelevant in most cases
				hash, 
				coords, 
				dir, 
				false, 
				true, 
				10
			)
			system.yield(0)
			ped.clear_ped_tasks_immediately(Ped) -- Peds won't start animation & possibly other problems if not clearing tasks.
			entity.set_entity_as_mission_entity(Ped, true, true)
		end
	end
	streaming.set_model_as_no_longer_needed(hash) -- The game will crash if requesting many hashes and never setting as no longer needed
	table.remove(kek_entity.spawn_queue, 1)
	return Ped
end

function kek_entity.spawn_networked_object(...)
	local hash <const>, coords <const>, not_dynamic_object <const> = ...
	essentials.assert(streaming.is_model_an_object(hash), "Tried to use an invalid model hash.", hash)
	wait_until_spawn_can_be_done()
	local Object = 0
	if globals.is_fully_transitioned_into_session() then
		local status <const> = kek_entity.request_model(hash)
		if status then
			local coords <const> = coords()
			if streaming.is_model_a_world_object(hash) then
				Object = object.create_world_object(hash, coords, true, not not_dynamic_object, 10)
			elseif streaming.is_model_an_object(hash) then
				Object = object.create_object(hash, coords, true, not not_dynamic_object, 10)
			end
			entity.set_entity_as_mission_entity(Object, false, true)
			entity.set_entity_should_freeze_waiting_on_collision(Object, false)
			kek_entity.constantize_network_id(Object)
			network.set_network_id_can_migrate(network.obj_to_net(Object), false)
		end
	end
	streaming.set_model_as_no_longer_needed(hash)
	table.remove(kek_entity.spawn_queue, 1)
	return Object
end

function kek_entity.spawn_local_object(...)
	local hash <const>, coords <const>, not_dynamic_object <const> = ...
	essentials.assert(streaming.is_model_an_object(hash), "Tried to use an invalid model hash.", hash)
	wait_until_spawn_can_be_done()
	local Object = 0
	if globals.is_fully_transitioned_into_session() then
		local status <const> = kek_entity.request_model(hash)
		if status then
			local coords <const> = coords()
			if streaming.is_model_a_world_object(hash) then
				Object = object.create_world_object(hash, coords, false, not not_dynamic_object, 5)
			elseif streaming.is_model_an_object(hash) then
				Object = object.create_object(hash, coords, false, not not_dynamic_object, 5)
			end
			entity.set_entity_as_mission_entity(Object, false, true)
		end
	end
	streaming.set_model_as_no_longer_needed(hash)
	table.remove(kek_entity.spawn_queue, 1)
	return Object
end

function kek_entity.get_net_objects()
	local objects <const> = object.get_all_objects()
	local net_objects <const> = {}
	for i = 1, #objects do
		if network.network_get_entity_is_networked(objects[i]) then
			net_objects[#net_objects + 1] = objects[i]
		end
	end
	return net_objects
end

function kek_entity.get_net_peds()
	local peds <const> = ped.get_all_peds()
	local net_peds <const> = {}
	for i = 1, #peds do
		if network.network_get_entity_is_networked(peds[i]) then
			net_peds[#net_peds + 1] = peds[i]
		end
	end
	return net_peds
end

function kek_entity.get_net_vehicles()
	local vehicles <const> = vehicle.get_all_vehicles()
	local net_vehicles <const> = {}
	for i = 1, #vehicles do
		if network.network_get_entity_is_networked(vehicles[i]) then
			net_vehicles[#net_vehicles + 1] = vehicles[i]
		end
	end
	return net_vehicles
end

function kek_entity.is_entity_valid(Entity)
	return entity.is_an_entity(Entity)
	and not entity.is_entity_static(Entity)
	and (not entity.is_entity_a_vehicle(Entity) or not vehicle.is_vehicle_stuck_on_roof(Entity))
end

function kek_entity.teleport(...)
	local Entity <const>,
	coords <const>,
	time <const> = ...
	if kek_entity.get_control_of_entity(Entity, time) then
		entity.set_entity_coords_no_offset(Entity, coords)
		return true
	end
end

function kek_entity.is_any_tasks_active(...)
	local Ped <const>, tasks <const> = ...
	local active_tasks <const> = {}
	if entity.is_an_entity(Ped) then
		essentials.assert(entity.is_entity_a_ped(Ped), "Expected a ped from argument \"Ped\".")
		for i = 1, #tasks do
			if ai.is_task_active(Ped, tasks[i]) then
				active_tasks[#active_tasks + 1] = tasks[i]
			end
		end
	end
	return active_tasks
end

function kek_entity.get_most_relevant_entity(...)
	local pid <const> = ...
	if player.is_player_in_any_vehicle(pid) then
		return kek_entity.get_parent_of_attachment(player.get_player_vehicle(pid))
	else
		return kek_entity.get_parent_of_attachment(player.get_player_ped(pid))
	end
end

function kek_entity.check_player_vehicle_and_teleport_if_necessary(...)
	local pid <const>, feature <const> = ...
	local had_to_teleport = false
	local time <const> = utils.time_ms() + 3000
	while time > utils.time_ms() and essentials.is_in_vehicle(pid) do
		if player.is_player_in_any_vehicle(pid) then
			return true, had_to_teleport
		else
			had_to_teleport = true
			kek_entity.teleport(kek_entity.get_most_relevant_entity(player.player_id()), location_mapper.get_ground_z(memoize.get_player_coords(pid)) + memoize.v3(0, 0, 45))
		end
		if feature and not feature.on then
			break
		end
		system.yield(0)
	end
	return false, had_to_teleport
end

function kek_entity.remove_player_entities(...)
	local table_of_entities <const> = ...
	local new <const> = {}
	for Entity in essentials.entities(table_of_entities) do
		if not entity.is_entity_a_ped(Entity) or not ped.is_ped_a_player(Entity) then
			local status = true
			if entity.is_entity_a_vehicle(Entity) then
				for pid in essentials.players(true) do
					if player.get_player_vehicle(pid) == Entity then
						status = false
						break
					end
				end
			end
			if status then
				new[#new + 1] = Entity
			end
		end
	end
	return new
end

function kek_entity.get_all_attached_entities(Entity, entities)
	entity.process_entity_attachments(Entity)
	local entities <const> = entities or {}
	for _, all_entities in pairs({
		vehicle.get_all_vehicles(),
		ped.get_all_peds(),
		object.get_all_objects()
	}) do
		for i = 1, #all_entities do
			if entity.get_entity_attached_to(all_entities[i]) == Entity and (not entity.is_entity_a_ped(all_entities[i]) or not ped.is_ped_a_player(all_entities[i])) then
				entities[#entities + 1] = all_entities[i]
				kek_entity.get_all_attached_entities(all_entities[i], entities)
			end
		end
	end
	return entities
end

function kek_entity.is_vehicle_an_attachment_to(parent, child)
	if parent == child then
		return true
	end
	local attachments <const> = kek_entity.get_all_attached_entities(parent)
	for i = 1, #attachments do
		if attachments[i] == child then
			return true
		end
	end
end

function kek_entity.get_bone_entity_is_attached_to(child, parent) -- ONLY WORKS IF ENTITY IS ATTACHED WITH NO OFFSET.
	local child_pos <const> = entity.get_entity_coords(child)
	for i = 0, entity.get_entity_bone_count(parent) - 1 do
		if entity.get_world_position_of_entity_bone(parent, i) == child_pos then
			return i
		end
	end
end

function kek_entity.get_parent_of_attachment(...)
	local Entity <const> = ...
	if entity.is_entity_attached(Entity) then
		return kek_entity.get_parent_of_attachment(entity.get_entity_attached_to(Entity))
	else
		return Entity
	end
end

function kek_entity.hard_remove_entity_and_its_attachments(...)
	local Entity = ...
	if entity.is_an_entity(Entity) then
		Entity = kek_entity.get_parent_of_attachment(Entity)
		if entity.is_an_entity(Entity) and (not entity.is_entity_a_ped(Entity) or not ped.is_ped_a_player(Entity)) then
			kek_entity.clear_entities(kek_entity.get_all_attached_entities(Entity), 5000)
			kek_entity.clear_entities({Entity}, 5000)
		end
	end
end

function kek_entity.get_entity_proofs(Entity)
	local status, bullet, fire, explosion, collision, melee, steam, unknown, drown = entity.get_entity_proofs(Entity)
	return {
		status = status,
		bullet = bullet,
		fire = fire,
		explosion = explosion,
		collision = collision,
		melee = melee,
		steam = steam,
		unknown = unknown,
		drown = drown
	}
end

function kek_entity.clear_entities(...)
	local table_of_entities <const>, time_to_wait_for_control = ...
	time_to_wait_for_control = time_to_wait_for_control or 3000
	local timeout <const> = utils.time_ms() + 30000
	local count = 1
	for Entity in essentials.entities(table_of_entities) do
		essentials.assert(not entity.is_entity_a_ped(Entity) or not ped.is_ped_a_player(Entity), "Tried to delete a player ped.")
		if entity.is_entity_a_vehicle(Entity) or not entity.is_entity_a_ped(entity.get_entity_attached_to(Entity)) or not ped.is_ped_a_player(entity.get_entity_attached_to(Entity)) then
			ui.remove_blip(ui.get_blip_from_entity(Entity))
			if kek_entity.get_control_of_entity(Entity, timeout > utils.time_ms() and time_to_wait_for_control or 200) then
				if entity.is_entity_attached(Entity) then
					entity.detach_entity(Entity)
				end
				if not entity.is_entity_attached(Entity) then
					if entity.is_entity_a_vehicle(Entity) then
						entity.set_entity_as_mission_entity(Entity, true, true)
					elseif entity.is_entity_an_object(Entity) then
						entity.set_entity_as_mission_entity(Entity, false, true)
					elseif entity.is_entity_a_ped(Entity) then
						entity.set_entity_as_mission_entity(Entity, false, false)
					end
					local hash <const> = entity.get_entity_model_hash(Entity)
					entity.delete_entity(Entity)
					streaming.set_model_as_no_longer_needed(hash)
				end
				count = count + 1
			end
		end
		if count % 10 == 0 then
			system.yield(0)
		end
	end
end			

function kek_entity.get_number_of_passengers(...)
	local Vehicle <const> = ...
	if entity.is_an_entity(Vehicle) then
		essentials.assert(entity.is_entity_a_vehicle(Vehicle), "Expected a vehicle from argument \"Vehicle\".")
		local passengers <const>, is_there_a_player_in_the_vehicle = {}
		for i = -1, vehicle.get_vehicle_max_number_of_passengers(Vehicle) - 2 do
			local Ped <const> = vehicle.get_ped_in_vehicle_seat(Vehicle, i)
			if entity.is_entity_a_ped(Ped) then
				passengers[#passengers + 1] = Ped
				if ped.is_ped_a_player(Ped) and player.get_player_from_ped(Ped) ~= player.player_id() then
					is_there_a_player_in_the_vehicle = true
				end
			end
		end
		return passengers, is_there_a_player_in_the_vehicle
	else
		return {}, false
	end
end

function kek_entity.is_player_in_vehicle(...)
	local Vehicle <const> = ...
	local player_in_vehicle, friend_in_vehicle
	if entity.is_an_entity(Vehicle) then
		essentials.assert(entity.is_entity_a_vehicle(Vehicle), "Expected a vehicle from argument \"Vehicle\".")
		for i = -1, vehicle.get_vehicle_max_number_of_passengers(Vehicle) - 2 do
			local Ped <const> = vehicle.get_ped_in_vehicle_seat(Vehicle, i)
			if ped.is_ped_a_player(Ped) and network.is_scid_friend(player.get_player_scid(player.get_player_from_ped(Ped))) then
				friend_in_vehicle = true
			end
			if ped.is_ped_a_player(Ped) then
				player_in_vehicle = true
			end
		end
	end
	return player_in_vehicle, friend_in_vehicle
end

function kek_entity.set_entity_as_networked(Entity, timeout)
	local time <const> = utils.time_ms() + (timeout or 1500)
	while time > utils.time_ms() and not network.network_get_entity_is_networked(Entity) do
		network.network_register_entity_as_networked(Entity)
		system.yield(0)
	end
	return network.network_get_entity_is_networked(Entity)
end

function kek_entity.constantize_network_id(Entity)
	kek_entity.set_entity_as_networked(Entity, 25)
	local net_id <const> = network.network_get_network_id_from_entity(Entity)
	-- network.set_network_id_can_migrate(net_id, false) -- Caused players unable to drive vehicles
	network.set_network_id_exists_on_all_machines(net_id, true)
	network.set_network_id_always_exists_for_player(net_id, player.player_id(), true)
	return net_id
end

function kek_entity.request_model(...)
	local model_hash <const> = ...
	while streaming.get_number_of_streaming_requests() > 0 do
		system.yield(0)
	end
	local is_hash_already_loaded <const> = not streaming.has_model_loaded(model_hash)
	essentials.assert(streaming.is_model_valid(model_hash), "Tried to request invalid model hash.", model_hash)
	if is_hash_already_loaded then
		streaming.request_model(model_hash)
		local time <const> = utils.time_ms() + 2000
		while not streaming.has_model_loaded(model_hash) and time > utils.time_ms() do
			system.yield(0)
		end
	end
	return streaming.has_model_loaded(model_hash), is_hash_already_loaded
end

function kek_entity.get_rotated_heading(...)
	local Entity <const>,
	angle <const>,
	pid <const>,
	heading = ...
	if entity.is_an_entity(Entity) then
		if not heading then
			if pid then
				heading = player.get_player_heading(pid)
			else
				heading = entity.get_entity_heading(Entity)
			end
		end
		heading = heading + angle
		if heading > 179.99999 then
			heading = -179.99999 + (math.abs(heading) - 179.99999)
		elseif heading < -179.99999 then
			heading = 179.99999 - (math.abs(heading) - 179.99999)
		end
		return heading
	else
		return 0
	end
end

function kek_entity.get_vector_relative_to_entity(...)
	local Entity <const>,
	distance_from_entity <const>,
	angle <const>,
	get_z_axis <const>,
	pid <const> = ...
	if entity.is_an_entity(Entity) then
		local rot, heading = v3(), 0
		if pid then
			heading = kek_entity.get_rotated_heading(Entity, angle or 0, pid)
		else
			heading = entity.get_entity_heading(Entity)
		end
		local pos = 
		entity.is_entity_a_ped(Entity) and ped.is_ped_a_player(Entity) and essentials.get_player_coords(player.get_player_from_ped(Entity))
		or entity.get_entity_coords(Entity)

		if get_z_axis then
			rot = entity.get_entity_rotation(Entity)
			rot.z = kek_entity.get_rotated_heading(Entity, angle or 0, nil, rot.z)
			rot:transformRotToDir()
			pos = pos + (rot * distance_from_entity)
		else
			heading = math.rad((heading - 180) * -1)
			pos.x = pos.x + (math.sin(heading) * -distance_from_entity)
			pos.y = pos.y + (math.cos(heading) * -distance_from_entity)
		end
		return pos
	else
		return v3()
	end
end

function kek_entity.get_vector_relative_to_pos(...)
	local pos <const>,
	distance_from_entity <const>,
	heading = ...
	local pos <const> = v3(pos.x, pos.y, pos.z) -- To not modify original v3
	heading = math.rad((heading - 180) * -1)
	pos.x = pos.x + (math.sin(heading) * -distance_from_entity)
	pos.y = pos.y + (math.cos(heading) * -distance_from_entity)
	return pos
end

function kek_entity.get_longest_dimension(...)
	local hash <const> = ...
	local min <const>, max <const> = vehicle_mapper.get_dimensions(hash)
	return essentials.get_max_variadic(
		math.abs(min.y), 
		math.abs(max.y),
		math.abs(min.x),
		math.abs(max.x)
	)
end

function kek_entity.vehicle_get_vec_rel_to_dims(...)
	local hash <const>, Entity <const>, extra_offset <const> = ...
	if entity.is_an_entity(Entity) and hash ~= 0 then
		essentials.assert(streaming.is_model_a_vehicle(hash), "Tried to get dimensions from a non vehicle hash.", hash)
		local additional_offset
		if entity.is_entity_a_ped(Entity) and ped.is_ped_in_any_vehicle(Entity) then
			local Entity <const> = ped.get_vehicle_ped_is_using(Entity)
			additional_offset = kek_entity.get_longest_dimension(entity.get_entity_model_hash(Entity)) / 3
		end
		return kek_entity.get_vector_relative_to_entity(Entity,
			kek_entity.get_longest_dimension(hash) + (extra_offset or 3) + (additional_offset or 0)
		)
	else
		return v3()
	end
end

function kek_entity.get_vector_in_front_of_me(...)
	local distance_from_entity <const> = ...
	local rot = cam.get_gameplay_cam_rot()
	rot:transformRotToDir()
	return cam.get_gameplay_cam_pos() + (rot * distance_from_entity)
end

function kek_entity.get_empty_seats(...)
	local Vehicle <const> = ...
	local seats <const> = {}
	if entity.is_an_entity(Vehicle) then
		essentials.assert(entity.is_entity_a_vehicle(Vehicle), "Expected a vehicle from argument \"Vehicle\".")
		for i = -1, vehicle.get_vehicle_model_number_of_seats(entity.get_entity_model_hash(Vehicle)) - 2 do
			if not entity.is_entity_a_ped(vehicle.get_ped_in_vehicle_seat(Vehicle, i)) then
				seats[#seats + 1] = i
			end
		end
	end
	return seats 	
end

function kek_entity.get_entity_altitude(...)
	local Entity <const> = ...
	if entity.is_an_entity(Entity) then
		local pos <const> = entity.get_entity_coords(Entity)
		return pos.z - location_mapper.get_ground_z(pos).z
	end
	return 0
end

function kek_entity.get_seat_ped_is_in(...)
	local Vehicle <const>, Ped <const> = ...
	if entity.is_an_entity(Vehicle) and entity.is_an_entity(Ped) then
		essentials.assert(entity.is_entity_a_ped(Ped), "Expected a ped from argument \"Ped\".")
		essentials.assert(entity.is_entity_a_vehicle(Vehicle), "Expected a vehicle from argument \"Vehicle\".")
		for i = -1, vehicle.get_vehicle_model_number_of_seats(entity.get_entity_model_hash(Vehicle)) - 2 do
			if vehicle.get_ped_in_vehicle_seat(Vehicle, i) == Ped then
				return i
			end
		end
	end
	return -2
end

-- Ped is kicked out then put back into vehicle in the same frame, causing the illusion he never left the vehicle
function kek_entity.clear_tasks_without_leaving_vehicle(...)
	local Ped <const>, Vehicle <const> = ...
	if entity.is_an_entity(Ped) and entity.is_an_entity(Vehicle) then
		essentials.assert(entity.is_entity_a_ped(Ped), "Expected a ped from argument \"Ped\".")
		essentials.assert(entity.is_entity_a_vehicle(Vehicle), "Expected a vehicle from argument \"Vehicle\".")
		essentials.assert(Ped == player.get_player_ped(player.player_id()) or not ped.is_ped_a_player(Ped), "Expected your player ped or a non-player ped.")
		if ped.is_ped_in_any_vehicle(Ped) then
			local seat <const> = kek_entity.get_seat_ped_is_in(Vehicle, Ped)
			ped.clear_ped_tasks_immediately(Ped)
			ped.set_ped_into_vehicle(Ped, Vehicle, seat)
		else
			ped.clear_ped_tasks_immediately(Ped)
		end
	end
end

function kek_entity.add_rope_between_entities(Entity1, Entity2)
	essentials.assert(entity.is_an_entity(Entity1) and entity.is_an_entity(Entity2), "Tried to attach entities that doesn't exist anymore to rope.")

	local pos1 <const> = entity.get_entity_coords(Entity1)
	local pos2 <const> = entity.get_entity_coords(Entity2)
	local distance <const> = math.max(10, pos1:magnitude(pos2))
	essentials.assert(distance < 600, "Tried to create a rope longer than 600 meters.")

	if not rope.rope_are_textures_loaded() then
		rope.rope_load_textures()
		system.yield(0)
	end
	local rope_id <const> = rope.add_rope(
		pos1, 			-- pos
		memoize.v3(), 	-- Rot
		distance, 		-- Max length
		1, 				-- Rope type
		distance, 		-- Init length
		5, 				-- Min length
		5, 				-- Change rate
		false, 			-- Onlyppu
		false, 			-- Collision
		false, 			-- Lock from front
		1.0, 			-- Physics multiplier 1.0 default
		false 			-- Breakable
	)
	essentials.assert(rope.does_rope_exist(rope_id), "Failed to create rope")

	rope.attach_entities_to_rope(
		rope_id, 	-- Rope id 
		Entity1,	-- Entity 1
		Entity2, 	-- Entity 2
		pos1, 		-- Entity pos 1
		pos2, 		-- Entity pos 2
		distance, 	-- Length
		0, 			-- a7
		0, 			-- a8
		nil, 		-- Entity bone name 1
		nil 		-- Entity bone name 2
	)
	return rope_id
end

function kek_entity.modify_entity_godmode(...)
	local Entity <const>, toggle_on_god <const> = ...
	if entity.is_an_entity(Entity) then
		essentials.assert(entity.is_entity_a_ped(Entity) or entity.is_entity_a_vehicle(Entity), "Expected a vehicle or ped from argument \"Entity\".")
		if entity.get_entity_god_mode(Entity) ~= toggle_on_god and kek_entity.get_control_of_entity(Entity) then
			entity.set_entity_god_mode(Entity, toggle_on_god)
			if entity.is_entity_a_vehicle(Entity) then
				vehicle.set_vehicle_can_be_visibly_damaged(Entity, false)
			end
		end
	end
end

function kek_entity.repair_car(...)
	local Vehicle <const>, preserve_velocity <const> = ...
	if entity.is_an_entity(Vehicle) then
		essentials.assert(entity.is_entity_a_vehicle(Vehicle), "Expected a vehicle from argument \"Vehicle\".")
		if kek_entity.get_control_of_entity(Vehicle) then
			vehicle.set_vehicle_undriveable(Vehicle, false)
			local velocity <const> = entity.get_entity_velocity(Vehicle)
			if entity.is_entity_on_fire(Vehicle) then
				fire.stop_entity_fire(Vehicle)
			end
			vehicle.set_vehicle_fixed(Vehicle)
			vehicle.set_vehicle_engine_health(Vehicle, 1000)
			vehicle.set_vehicle_engine_on(Vehicle, true, true, true)
			if preserve_velocity and velocity ~= memoize.v3() then
				entity.set_entity_velocity(Vehicle, velocity)
			end
		end
	end
end

function kek_entity.set_entity_heading(Entity, heading) -- Removes rotation velocity
	entity.freeze_entity(Entity, true)
	local status <const> = entity.set_entity_heading(Entity, heading)
	entity.freeze_entity(Entity, false)
	rope.activate_physics(Entity)
	return status
end

function kek_entity.set_entity_rotation(Entity, rot) -- Removes rotation velocity
	entity.freeze_entity(Entity, true)
	local status <const> = entity.set_entity_rotation(Entity, rot)
	entity.freeze_entity(Entity, false)
	rope.activate_physics(Entity)
	return status
end

do
	local toggle_vehicle_mods <const> = essentials.const({
		unk1 = 17,
		unk2 = 19, 
		unk3 = 21,
		turbo = 18, 
		tire_smoke = 20, 
		xenon_lights = 22
	})

	local toggle_vehicle_mods_map <const> = essentials.const((function()
		local t <const> = {}
		for name, mod in pairs(toggle_vehicle_mods) do
			t[mod] = true
		end
		return t
	end)())

	local performance_mods <const> = essentials.const({
		engine = 11,
		brakes = 12,
		transmission = 13,
		suspension = 15,
		armor = 16
	})

	local accepted_wheel_types <const> = {}
	for i = 0, 5 do
		accepted_wheel_types[#accepted_wheel_types + 1] = i
	end
	for i = 7, 12 do
		accepted_wheel_types[#accepted_wheel_types + 1] = i
	end

	local function random_rgb()
		return essentials.get_rgb(math.random(0, 255), math.random(0, 255), math.random(0, 255))
	end

	function kek_entity.max_car(...)
		local Vehicle <const>,
		only_performance_upgrades <const>,
		dont_freeze <const> = ... -- The freezing nullifies rotation velocity, so this is useful
		essentials.assert(not entity.is_an_entity(Vehicle) or entity.is_entity_a_vehicle(Vehicle), "Expected a vehicle from argument \"Vehicle\".")
		if not kek_entity.get_control_of_entity(Vehicle) then
			return
		end
		local velocity <const> = entity.get_entity_velocity(Vehicle)
		if not dont_freeze and velocity ~= memoize.v3() then -- get_entity_velocity isn't that reliable, completely unreliable at long distances
			entity.freeze_entity(Vehicle, true) -- Not freezing can cause vehicles to be slung into the air
		end
		vehicle.set_vehicle_mod_kit_type(Vehicle, 0)
		if not only_performance_upgrades then
			if type(settings.in_use["Plate vehicle text"]) == "string" then -- Crashes if plate text is nil
				vehicle.set_vehicle_number_plate_text(Vehicle, settings.in_use["Plate vehicle text"])
			end
			if not streaming.is_model_a_bike(entity.get_entity_model_hash(Vehicle)) then
				if not settings.toggle["Always f1 wheels on #vehicle#"].on then 
				--[[
					Setting wheel type can cause crashes in certain cases. 
					Death race - Buick riviera 2.xml caused this crash until applying wheel type before all other vehicle mods.
				--]]
					kek_entity.set_wheel_type(Vehicle, accepted_wheel_types[math.random(1, #accepted_wheel_types)])
				else
					kek_entity.set_wheel_type(Vehicle, enums.wheel_types.f1_wheels)
				end
			end
			if  entity.get_entity_model_hash(Vehicle) ~= gameplay.get_hash_key("banshee") 
			and entity.get_entity_model_hash(Vehicle) ~= gameplay.get_hash_key("sentinel") then
				for i = 0, 75 do 
				--[[
					Certain vehicles, banshee & sentinel XS in particular, get white boxes that crashes other player's games.
					HSW upgrades appears to be the culprit. (mod id 36)
				--]]
					if not toggle_vehicle_mods_map[i] and vehicle.get_num_vehicle_mods(Vehicle, i) > 0 then
						if i ~= enums.vehicle_mods.VMT_LIVERY_MOD or math.random(1, 3) == 1 then
							vehicle.set_vehicle_mod(Vehicle, i, math.random(0, vehicle.get_num_vehicle_mods(Vehicle, i) - 1))
						else
							vehicle.set_vehicle_mod(Vehicle, i, -1)
						end
					end
				end
			end
			for _, mod in pairs(toggle_vehicle_mods) do -- This must go before set_vehicle_headlight_color. Xenon has to be enabled.
				vehicle.toggle_vehicle_mod(Vehicle, mod, true)
			end
			vehicle.set_vehicle_headlight_color(Vehicle, math.random(-1, 12))
			vehicle.set_vehicle_neon_light_enabled(Vehicle, math.random(-1, 4), true)
			vehicle.set_vehicle_tire_smoke_color(Vehicle, math.random(0, 255), math.random(0, 255), math.random(0, 255))
			vehicle.set_vehicle_number_plate_index(Vehicle, math.random(0, 3))
			vehicle.set_vehicle_fullbeam(Vehicle, true)
			vehicle.set_vehicle_custom_wheel_colour(Vehicle, random_rgb())
			vehicle.set_vehicle_neon_lights_color(Vehicle, random_rgb()) -- Is BGR, but it's fine since it's just random colour

			vehicle.clear_vehicle_custom_primary_colour(Vehicle)
			vehicle.clear_vehicle_custom_secondary_colour(Vehicle)

			vehicle.set_vehicle_extra_colors(Vehicle, math.random(0, 159), math.random(0, 159))
			vehicle.set_vehicle_custom_primary_colour(Vehicle, random_rgb())
			vehicle.set_vehicle_custom_secondary_colour(Vehicle, random_rgb())
			if math.random(1, 3) == 1 then
				vehicle.set_vehicle_custom_pearlescent_colour(Vehicle, random_rgb())
			end
			vehicle.set_vehicle_enveff_scale(Vehicle, essentials.random_real(0, 1))
			if not streaming.is_model_a_heli(entity.get_entity_model_hash(Vehicle)) then -- Prevent removal of heli rotors
				for i = 2, 9 do -- Extra 1 causes vehicles to get teleported around
					if vehicle.does_extra_exist(Vehicle, i) then
						vehicle.set_vehicle_extra(Vehicle, i, math.random(0, 1) == 0)
					end
				end
			end
		end
		vehicle.set_vehicle_bulletproof_tires(Vehicle, true)
		vehicle.set_vehicle_dirt_level(Vehicle, 0.0)
		for _, mod in pairs(performance_mods) do
			vehicle.set_vehicle_mod(Vehicle, mod, vehicle.get_num_vehicle_mods(Vehicle, mod) - 1)
		end
		if vehicle.get_num_vehicle_mods(Vehicle, enums.vehicle_mods.VMT_ROOF) == 1 then
		--[[ 
			Sets best vehicle weapon, not confirmed to work for every vehicle. 
		--]]
			vehicle.set_vehicle_mod(Vehicle, enums.vehicle_mods.VMT_ROOF, 0)
		else
			vehicle.set_vehicle_mod(Vehicle, enums.vehicle_mods.VMT_ROOF, 1)
		end
		if velocity ~= memoize.v3() then
			if not dont_freeze then
				entity.freeze_entity(Vehicle, false)
				rope.activate_physics(Vehicle)
			end
			entity.set_entity_velocity(Vehicle, velocity)
		end
		return
	end
end

--[[ https://docs.fivem.net/natives/?_0xA551BE18C11A476D
	paintType:
	0: Normal
	1: Metallic
	2: Pearl
	3: Matte
	4: Metal
	5: Chrome
]]
function kek_entity.get_paint_type(Vehicle)
	if entity.is_an_entity(Vehicle) then
		essentials.assert(entity.is_entity_a_vehicle(Vehicle), "Expected a vehicle from argument \"Vehicle\".")
		local colour_name <const> = enums.vehicle_colors[vehicle.get_vehicle_mod(Vehicle, 66)] or ""
		if colour_name:find("Metallic", 1, true) then
			return 1
		elseif colour_name:find("Matte", 1, true) then
			return 3
		elseif colour_name:find("Chrome", 1, true) then
			return 5
		elseif colour_name:find("Brushed", 1, true) or colour_name:find("Gold", 1, true) then
			return 4
		else
			return 0
		end
	end
end

-- Gets the position on a surface the player is looking at.
function kek_entity.get_collision_vector(...)
	local pid <const> = ...
	local rot = cam.get_gameplay_cam_rot()
	rot:transformRotToDir()
	local hit_pos <const> = select(2, worldprobe.raycast(essentials.get_player_coords(pid), rot * 1000 + cam.get_gameplay_cam_pos(), -1, player.get_player_ped(pid)))
	return hit_pos
end

--[[
	Applies modifications to one or more tables of entities.
	Does not support enums.
	- Remove player entities
	- Remove all entities outside of range
	- Sort entities from closest to farthest away
	- Limit number of entities
	Each table has its own set of properties to apply.
	Returns the tables merged into one table.
--]]
function kek_entity.get_table_of_entities_with_respect_to_distance_and_set_limit(...)
	local entity_tables <const>, Ped <const> = ...
	essentials.assert(not entity.is_an_entity(Ped) or ped.is_ped_a_player(Ped), "Expected a player ped from argument \"Ped\".")
	local new_sorted_tables <const> = {}
	for i, entity_table in pairs(entity_tables) do
		if entity_table.remove_player_entities then
			entity_table.entities = kek_entity.remove_player_entities(entity_table.entities)
		end
		if entity_table.max_range then
			local temp <const> = {}
			for i = 1, #entity_table.entities do
				if memoize.get_distance_between(Ped, entity_table.entities[i]) < entity_table.max_range then
					temp[#temp + 1] = entity_table.entities[i]
				end
			end
			entity_table.entities = temp
		end
		if entity_table.sort_by_closest then
			table.sort(entity_table.entities, function(a, b) 
				return memoize.get_distance_between(Ped, a) < memoize.get_distance_between(Ped, b)
			end)
		end
		if entity_table.max_number_of_entities then
			for _ = entity_table.max_number_of_entities, #entity_table.entities do
				entity_table.entities[#entity_table.entities] = nil
			end
		end
		new_sorted_tables[i] = entity_table.entities
	end
	return new_sorted_tables
end

function kek_entity.remove_player_vehicle(...)
	local pid <const> = ...
	globals.send_script_event(pid, "Destroy personal vehicle", nil, pid)
	local initial_pos <const> = essentials.get_player_coords(player.player_id())
	local status <const>, had_to_teleport <const> = kek_entity.check_player_vehicle_and_teleport_if_necessary(pid)
	if status then
		local time <const> = utils.time_ms() + 2000
		while player.is_player_in_any_vehicle(pid) and time > utils.time_ms() do
			system.yield(0)
			ped.clear_ped_tasks_immediately(player.get_player_ped(pid))
		end
		kek_entity.clear_entities({player.get_player_vehicle(pid)}, 5000)
	end
	local was_succesful <const> = not entity.is_entity_a_vehicle(player.get_player_vehicle(pid))
	if had_to_teleport then
		kek_entity.teleport(kek_entity.get_most_relevant_entity(player.player_id()), initial_pos)
	end
	return was_succesful
end

do
	local offset <const> = {0x2E}
	function kek_entity.is_entity_frozen(Entity)
		if entity.is_an_entity(Entity) then -- read_u8 crashes the game if nil is passed. get_entity returns nil if entity doesn't exist.
			return memory.read_u8(memory.get_entity(Entity), offset) & 1 << 1 ~= 0
		else
			return false
		end
	end
end

function kek_entity.spawn_and_push_a_vehicle_in_direction(...)
	local pid <const>,
	clear_vehicle_after_ram <const>,
	distance_from_target,
	hash_or_entity <const> = ...
	local speed
	if math.random(0, 1) == 1 then -- Whether vehicle is pushed from behind or front of player
		speed = 120
		distance_from_target = -math.abs(distance_from_target)
	else
		speed = -120
	end
	if not player.is_player_dead(pid) then
		if player.is_player_in_any_vehicle(pid) then
			kek_entity.get_control_of_entity(player.get_player_vehicle(pid), 0)
		end
		local Vehicle = hash_or_entity
		local spawn_pos
		if not entity.is_entity_a_vehicle(hash_or_entity) then
			essentials.assert(streaming.is_model_a_vehicle(hash_or_entity), "Expected a valid vehicle hash.", hash_or_entity)
			Vehicle = kek_entity.spawn_networked_mission_vehicle(hash_or_entity, function()
				spawn_pos = kek_entity.get_vector_relative_to_entity(kek_entity.get_most_relevant_entity(pid), distance_from_target, nil, nil, pid)
				spawn_pos.z = select(2, ped.get_ped_bone_coords(player.get_player_ped(pid), 0x60f1, memoize.v3())).z
				return spawn_pos, player.get_player_heading(pid)
			end)
		else
			essentials.assert(not entity.is_an_entity(hash_or_entity) or entity.is_entity_a_vehicle(hash_or_entity), "Expected a vehicle from argument \"hash_or_entity\".")
		end
		if kek_entity.get_control_of_entity(Vehicle) then
			vehicle.set_vehicle_out_of_control(Vehicle, false, true)
			vehicle.set_vehicle_forward_speed(Vehicle, speed)
			if clear_vehicle_after_ram then
				system.yield(300)
				kek_entity.clear_entities({Vehicle})
			end
			return Vehicle
		end
	end
	return 0
end

function kek_entity.ram_player(pid)
	local count = 0
	while count < 5 and player.is_player_valid(pid) and not player.is_player_dead(pid) do
		essentials.use_ptfx_function(kek_entity.spawn_and_push_a_vehicle_in_direction, pid, true, 8, gameplay.get_hash_key("tanker"))
		system.yield(150)
		count = count + 1
	end
end

function kek_entity.set_combat_attributes(...)
	local Ped <const>, 
	set_all_attributes_to_true <const>,
	attributes <const> = ...
	if entity.is_an_entity(Ped) then
		essentials.assert(entity.is_entity_a_ped(Ped), "Expected a ped from argument \"Ped\".")
		essentials.assert(not ped.is_ped_a_player(Ped), "Expected a non-player ped.")
		for attribute_id, is_on in pairs({
			[0] = attributes.cover or false,
			[1] = attributes.use_vehicle or false,
			[2] = attributes.driveby or false,
			[3] = attributes.leave_vehicle or false,
			[5] = attributes.unarmed_fight_armed or false, 
			[20] = attributes.taunt_in_vehicle or false,
			[46] = attributes.always_fight or false,
			[52] = attributes.ignore_traffic or false,
			[1424] = attributes.use_fireing_weapons or false
		}) do
			ped.set_ped_combat_attributes(Ped, attribute_id, set_all_attributes_to_true or is_on == true)
		end
		ped.set_ped_combat_ability(Ped, 100)
		ped.set_ped_combat_range(Ped, enums.combat_range.CR_Far)
		ped.set_ped_combat_movement(Ped, enums.combat_movement.offensive)
		ped.set_ped_can_switch_weapons(Ped, true)
		ped.set_ped_relationship_group_hash(Ped, gameplay.get_hash_key("HATES_PLAYER"))
	end
end

local tracker <const> = {}
function kek_entity.create_cage(...)
	local pid <const> = ...
	if tracker[pid] then
		return -1
	end
	tracker[pid] = true

	ped.clear_ped_tasks_immediately(player.get_player_ped(pid))
	system.yield(250)
	local temp_ped <const> = kek_entity.spawn_networked_ped(ped_mapper.get_hash_from_user_input("?"), function() 
		return player.get_player_coords(player.player_id()) + memoize.v3(0, 0, 10), 0
	end)
	kek_entity.modify_entity_godmode(temp_ped, true)

	if entity.is_entity_a_ped(temp_ped) then
		entity.set_entity_visible(temp_ped, false)
		ped.set_ped_config_flag(temp_ped, enums.ped_config_flags.InVehicle, 1)
		entity.freeze_entity(temp_ped, true)
		local cage <const> = kek_entity.spawn_networked_object(gameplay.get_hash_key("prop_test_elevator"), function()
			return player.get_player_coords(player.player_id()) + memoize.v3(0, 0, 10)
		end)
		local cage_2 <const> = kek_entity.spawn_networked_object(gameplay.get_hash_key("prop_test_elevator"), function()
			return player.get_player_coords(player.player_id()) + memoize.v3(0, 0, 10)
		end)
		entity.set_entity_visible(temp_ped, true)
		entity.attach_entity_to_entity(cage, temp_ped, 0, memoize.v3(), memoize.v3(), false, true, true, 0, true)
		entity.process_entity_attachments(temp_ped)
		entity.attach_entity_to_entity(cage_2, temp_ped, 0, memoize.v3(), memoize.v3(0, 0, 90), false, true, false, 0, true)
		entity.process_entity_attachments(temp_ped)
		entity.set_entity_visible(temp_ped, false)

		kek_entity.teleport(temp_ped, select(2, ped.get_ped_bone_coords(player.get_player_ped(pid), 0x3779, memoize.v3())))
		essentials.create_thread(function()
			while player.is_player_valid(pid)
			and entity.is_entity_a_ped(temp_ped)
			and entity.is_entity_an_object(cage)
			and entity.is_entity_an_object(cage_2)
			and essentials.get_player_coords(pid):magnitude(entity.get_entity_coords(temp_ped)) < 5 do
				ped.clear_ped_tasks_immediately(temp_ped)
				system.yield(0)
			end
			kek_entity.clear_entities({cage, cage_2, temp_ped}, 5000)
			tracker[pid] = false
		end, nil)
		return temp_ped
	else
		kek_entity.clear_entities({temp_ped})
	end
	tracker[pid] = false
	return -2
end

local function get_prefered_vehicle_pos(...)
	local hash <const> = ...
	local pos <const> = kek_entity.vehicle_get_vec_rel_to_dims(hash, player.get_player_ped(player.player_id()))
	essentials.assert(streaming.is_model_a_vehicle(hash), "Expected a valid vehicle hash.", hash)
	if settings.toggle["Air #vehicle# spawn mid-air"].on and settings.toggle["Spawn inside of spawned #vehicle#"].on and streaming.is_model_a_heli(hash) then
		return location_mapper.get_most_accurate_position(pos, true) + v3(0, 0, 100 - kek_entity.get_entity_altitude(kek_entity.get_most_relevant_entity(player.player_id())))
	elseif settings.toggle["Air #vehicle# spawn mid-air"].on and settings.toggle["Spawn inside of spawned #vehicle#"].on and streaming.is_model_a_plane(hash) then
		return location_mapper.get_most_accurate_position(pos, true) + v3(0, 0, 250 - kek_entity.get_entity_altitude(kek_entity.get_most_relevant_entity(player.player_id())))
	else
		return location_mapper.get_most_accurate_position(pos, true)
	end
end

function kek_entity.clear_owned_vehicles()
	for Vehicle in pairs(essentials.deep_copy(kek_entity.user_vehicles)) do -- MUST BE IN PAIRS. If using essentials.entities, it won't nil out invalid vehicle handles, which sooner or later is reused by new entities.
		kek_entity.user_vehicles[Vehicle] = nil
		if entity.is_an_entity(Vehicle) then
			essentials.assert(entity.is_entity_a_vehicle(Vehicle), "Expected only vehicles in user_vehicles table.")
			kek_entity.hard_remove_entity_and_its_attachments(Vehicle)
		end
	end
end

function kek_entity.vehicle_preferences(...)
	local Vehicle <const>, teleport <const> = ...
	if entity.is_an_entity(Vehicle) then
		essentials.assert(entity.is_entity_a_vehicle(Vehicle), "Expected a vehicle from argument \"Vehicle\".")
		kek_entity.user_vehicles[player.get_player_vehicle(player.player_id())] = player.get_player_vehicle(player.player_id())
		if settings.toggle["Delete old #vehicle#"].on then
			essentials.create_thread(kek_entity.clear_owned_vehicles)
			system.yield(0)
		end
		if entity.is_entity_a_vehicle(Vehicle) then
			essentials.assert(entity.is_entity_a_vehicle(Vehicle), "Expected a vehicle from argument \"Vehicle\".")
			local hash <const> = entity.get_entity_model_hash(Vehicle)
			if teleport then
				kek_entity.teleport(Vehicle, get_prefered_vehicle_pos(hash))
			end
			if settings.toggle["Spawn inside of spawned #vehicle#"].on then
				if streaming.is_model_a_heli(hash) then
					vehicle.set_heli_blades_full_speed(Vehicle)
				elseif streaming.is_model_a_plane(hash) then
					vehicle.set_vehicle_forward_speed(Vehicle, 100)
				end
				ped.set_ped_into_vehicle(player.get_player_ped(player.player_id()), Vehicle, enums.vehicle_seats.driver)
			end
		end
	end
end

function kek_entity.set_blip(...)
	local Entity <const>,
	sprite_id <const>,
	color <const> = ...
	if entity.is_an_entity(Entity) then
		local blip <const> = ui.add_blip_for_entity(Entity)
		ui.set_blip_sprite(blip, sprite_id or 0)
		ui.set_blip_colour(blip, color or 0)
		return blip
	else
		return -1
	end
end

function kek_entity.spawn_car()
	if settings.toggle["Always ask what #vehicle#"].on then
		local input <const>, status <const> = keys_and_input.input_user_entity("vehicle")
		if status == 2 then
			return
		end
		settings:update_user_entity(input, "vehicle")
	end
	local hash <const> = vehicle_mapper.get_hash_from_user_input(settings.in_use["User vehicle"])
	if streaming.is_model_a_vehicle(hash) then
		if not kek_entity.entity_manager:update().is_vehicle_limit_not_breached then
			essentials.msg(lang["Failed to spawn vehicle. Vehicle limit was reached"], "red", 6)
			return -1
		end
		kek_entity.user_vehicles[player.get_player_vehicle(player.player_id())] = player.get_player_vehicle(player.player_id())
		if settings.toggle["Delete old #vehicle#"].on then
			essentials.create_thread(kek_entity.clear_owned_vehicles)
			system.yield(0)
		end
		local velocity <const> = entity.get_entity_velocity(kek_entity.get_most_relevant_entity(player.player_id()))
		local Vehicle <const> = kek_entity.spawn_networked_vehicle(hash, function()
			return get_prefered_vehicle_pos(hash), player.get_player_heading(player.player_id())
		end, {
			godmode = settings.toggle["Spawn #vehicle# in godmode"].on, 
			max = settings.toggle["Spawn #vehicle# maxed"].on,
			persistent = false
		})
		if settings.toggle["Always f1 wheels on #vehicle#"].on then
			kek_entity.set_wheel_type(Vehicle, enums.wheel_types.f1_wheels)
		end
		kek_entity.vehicle_preferences(Vehicle)
		vehicle.set_vehicle_engine_on(Vehicle, true, true, false)
		kek_entity.user_vehicles[Vehicle] = Vehicle
	else
		essentials.msg(lang["Failed to spawn vehicle. Invalid vehicle hash."], "red", 6)
		return -1
	end
end

do
	local table_of_glitch_entity_models <const> = essentials.const({
		"prop_ld_dstcover_02",
		"prop_torture_ch_01",
		"prop_ld_farm_rail01",
		"prop_ld_ferris_wheel",
		"prop_alien_egg_01",
		"prop_cs_dildo_01",
		"prop_sh_bong_01",
		"banshee2",
		"molotok",
		"moonbeam2",
		"sanctus",
		"bmx",
		"buzzard2",
		"swift2",
		"a_f_y_hiker_01",
		"a_m_m_genfat_01",
		"a_c_killerwhale",
		"a_c_cat_01",
		"a_c_humpback",
		"a_c_crow"
	})

	function kek_entity.glitch_vehicle(...)
		local Vehicle <const> = ...
		if entity.is_an_entity(Vehicle) then
			essentials.assert(entity.is_entity_a_vehicle(Vehicle), "Expected a vehicle from argument \"Vehicle\".")
			local seat <const> = vehicle.get_free_seat(Vehicle)
			if seat ~= -2 then
				local Ped <const> = kek_entity.spawn_networked_ped(gameplay.get_hash_key("a_f_y_topless_01"), function() 
					return entity.get_entity_coords(essentials.get_ped_closest_to_your_pov()) + memoize.v3(0, 0, 10), 0
				end)
				kek_entity.modify_entity_godmode(Ped, true)
				if entity.is_entity_a_ped(Ped) then
					entity.set_entity_collision(Ped, false, false, false)
					entity.set_entity_visible(Ped, false)
					ped.set_ped_into_vehicle(Ped, Vehicle, seat)
					local hash <const>, Entity = gameplay.get_hash_key(table_of_glitch_entity_models[math.random(1, #table_of_glitch_entity_models)])
					if streaming.is_model_an_object(hash) then
						Entity = kek_entity.spawn_networked_object(hash, function()
							return entity.get_entity_coords(essentials.get_ped_closest_to_your_pov()) + memoize.v3(0, 0, 10)
						end)
					elseif streaming.is_model_a_ped(hash) then
						Entity = kek_entity.spawn_networked_ped(hash, function()
							return entity.get_entity_coords(essentials.get_ped_closest_to_your_pov()) + memoize.v3(0, 0, 10), 0
						end)
						kek_entity.modify_entity_godmode(Entity, true)
					elseif streaming.is_model_a_vehicle(hash) then
						Entity = kek_entity.spawn_networked_mission_vehicle(hash, function()
							return entity.get_entity_coords(essentials.get_ped_closest_to_your_pov()) + memoize.v3(0, 0, 10), 0
						end)
						kek_entity.modify_entity_godmode(Entity, true)
					end
					if entity.is_an_entity(Entity) then
						entity.set_entity_visible(Entity, false)
						entity.attach_entity_to_entity(Entity, Ped, 0, memoize.v3(), v3(math.random(0, 180), math.random(0, 180), math.random(0, 180)), false, true, entity.is_entity_a_ped(Entity), 0, false)
						entity.process_entity_attachments(Ped)
					else
						kek_entity.clear_entities({Ped, Entity})
					end
				end
			end
		end
	end
end

function kek_entity.teleport_player_and_vehicle_to_position(...)
	local pid <const>,
	pos <const>,
	show_message <const>,
	f <const>,
	dont_teleport_back <const> = ...

	local teleport_you_back_to_original_pos = false
	if pid ~= player.player_id() then
		teleport_you_back_to_original_pos = not (
			player.get_player_vehicle(pid) == player.get_player_vehicle(player.player_id()) 
			and player.is_player_in_any_vehicle(pid)
			and player.is_player_in_any_vehicle(player.player_id())
		)
	end

	local initial_pos <const> = essentials.get_player_coords(player.player_id())
	local value
	if f then
		value = f.value
	end
	local is_player_in_vehicle <const>, is_in_spectator_mode <const> = essentials.is_in_vehicle(pid) or player.player_id() == pid, network.network_is_in_spectator_mode()
	if is_player_in_vehicle then
		if is_in_spectator_mode then
			network.network_set_in_spectator_mode(false, player.get_player_ped(pid))
		end
		local thread
		if player.player_id() ~= pid and (not player.is_player_in_any_vehicle(player.player_id()) 
		or not player.is_player_in_any_vehicle(pid) 
		or player.get_player_vehicle(player.player_id()) ~= player.get_player_vehicle(pid)) then
			thread = essentials.create_thread(function()
				while true do
					local my_entity <const> = kek_entity.get_most_relevant_entity(player.player_id())
					entity.set_entity_coords_no_offset(my_entity, essentials.get_player_coords(pid) + memoize.v3(0, 0, 6))
					entity.set_entity_velocity(my_entity, memoize.v3())
					system.yield(0)
				end
			end, nil)
		end
		local time <const> = utils.time_ms() + 3000 -- Waits for their vehicle to load into memory
		while not player.is_player_in_any_vehicle(pid) and essentials.is_in_vehicle(pid) and time > utils.time_ms() do
			system.yield(0)
		end
		local time <const> = utils.time_ms() + 3000
		repeat
			kek_entity.get_control_of_entity(player.get_player_vehicle(pid), 25)
			system.yield(0)
		until utils.time_ms() > time
		or (f and not f.on)
		or (f and f.value ~= value)
		or not essentials.is_in_vehicle(pid)
		or network.has_control_of_entity(player.get_player_vehicle(pid)) 
		or not player.is_player_in_any_vehicle(pid)
		kek_entity.teleport(
			player.player_id() == pid and kek_entity.get_most_relevant_entity(player.player_id())
			or player.get_player_vehicle(pid), 
			pos, 
			0
		)
		if thread then
			essentials.delete_thread(thread)
		end
		if is_in_spectator_mode then
			network.network_set_in_spectator_mode(true, player.get_player_ped(pid))
		end
	elseif show_message then
		essentials.msg(string.format("%s %s", player.get_player_name(pid), lang["is not in a vehicle."]), "red")
	end
	if not dont_teleport_back and teleport_you_back_to_original_pos then
		kek_entity.teleport(kek_entity.get_most_relevant_entity(player.player_id()), initial_pos)
	end
	return is_player_in_vehicle
end

do
	local threads <const> = {}
	function kek_entity.teleport_session(...)
		local pos <const>, f <const> = ...
		local pids <const> = {}
		for pid in essentials.players() do
			if not threads[pid] and pos:magnitude(essentials.get_player_coords(pid)) > 150 and not player.is_player_dead(pid) and essentials.is_not_friend(pid) then
				pids[#pids + 1] = pid
			end
		end
		local value <const> = f.value
		while #pids > 0 and f.on and f.value == value do
			local my_pos <const> = player.get_player_coords(player.player_id())
			table.sort(pids, function(a, b) -- Makes sure closest player is teleported at all times. Needs to be updated on each iteration.
				local score_a, score_b = my_pos:magnitude(essentials.get_player_coords(a)), my_pos:magnitude(essentials.get_player_coords(b))
				
				-- Makes those in a vehicle come last in the list.
				if essentials.is_in_vehicle(a) then
					score_a = score_a + 10^8
				end
				if essentials.is_in_vehicle(b) then
					score_b = score_b + 10^8
				end

				return score_a < score_b
			end)

			local pid <const> = pids[1]
			table.remove(pids, 1)

			if not essentials.is_in_vehicle(pid) then
				threads[pid] = essentials.create_thread(function()
					globals.force_player_into_vehicle(pid)
					threads[pid] = nil
				end)
			else
				kek_entity.teleport_player_and_vehicle_to_position(pid, pos, nil, f, true)
			end
		end
		return threads
	end
end

function kek_entity.generate_vehicle_list(...)
	local feat_type <const>,
	feat_str <const>,
	parent <const>,
	value_i_func <const>,
	func <const>,
	add_to_vehicle_blacklist <const> = ...
	for id, name in pairs(enums.vehicle_class_ids_to_name) do
		local parent <const> = essentials.add_feature(lang[name], "parent", parent.id, function(f)
			if f.child_count == 0 then
				local hashes <const> = vehicle.get_all_vehicle_model_hashes()
				for i = 1, #hashes do
					if vehicle.get_vehicle_class_from_name(hashes[i]) == id then
						local feature <const> = essentials.add_feature(vehicle_mapper.get_vehicle_name(hashes[i]), feat_type, f.id, func)
						feature.data = hashes[i]
						feature:set_str_data(feat_str)
						feature.value = value_i_func(hashes[i])
						if add_to_vehicle_blacklist then
							local setting_name <const> = "vehicle_blacklist_"..vehicle_mapper.GetModelFromHash(hashes[i])
							settings.valuei[setting_name] = settings.valuei[setting_name] or feature
						end
					end
				end
			end
		end)
	end
end

function kek_entity.generate_player_vehicle_list(...)
	local feature_info <const>,
	parent <const>,
	func <const>,
	initial_name <const> = ...
	for id, name in pairs(enums.vehicle_class_ids_to_name) do
		local parent <const> = essentials.add_player_feature(lang[name], "parent", parent, function(f, pid)
			if f.child_count == 0 then
				local hashes <const> = vehicle.get_all_vehicle_model_hashes()
				for i = 1, #hashes do
					if vehicle.get_vehicle_class_from_name(hashes[i]) == id then
						local feature_id <const> = essentials.add_player_feature(vehicle_mapper.get_vehicle_name(hashes[i])..initial_name, feature_info.type, f.id, func).id
						local player_feat <const> = menu.get_player_feature(feature_id)
						if feature_info.type:find("value_i", 1, true) then
							player_feat.max = feature_info.max
							player_feat.min = feature_info.min
							player_feat.mod = feature_info.mod
							player_feat.value = feature_info.value
						end
						for pid = 0, 31 do
							player_feat.feats[pid].data = hashes[i]
						end
					end
				end
			end
		end).id
	end
end

return kek_entity -- Not a const table, certain members need write permission.