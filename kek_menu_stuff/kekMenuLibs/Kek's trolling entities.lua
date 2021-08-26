-- Lib Kek's trolling entities version: 1.0.4
-- Copyright © 2020-2021 Kektram

local troll_entity = {}

local weapon_mapper = require("Weapon mapper")
local location_mapper = require("Location mapper")
local vehicle_mapper = require("Vehicle mapper")
local ped_mapper = require("Ped mapper")
local essentials = require("Essentials")
local kek_entity = require("Kek's entity functions")
local custom_vehicles = require("Custom vehicle spawner")

local home = utils.get_appdata_path("PopstarDevs", "").."\\2Take1Menu\\"
local kek_menu_stuff_path = home.."scripts\\kek_menu_stuff\\"

-- Spawning standards
	function troll_entity.spawn_standard(f, pid, grief_function)
		for pid = 0, 31 do
			system.yield(0)
			if essentials.is_player_completely_valid(pid)
			and essentials.is_not_friend(pid)
			and (not kek_menu.toggle["Exclude yourself from trolling"].on or player.player_id() ~= pid) then
				repeat
					system.yield(0)
					local Entity = grief_function(pid)
				until not essentials.is_player_completely_valid(pid) or not f.on or kek_entity.is_entity_valid(Entity) or Entity == -1
			end
		end
	end

-- Send generic angry vehicle
	function troll_entity.setup_peds_and_put_in_seats(seats, hash, Vehicle, pid, dont_clear_vehicle)
		if not entity.is_entity_a_vehicle(Vehicle) then
			return
		end
		vehicle.set_vehicle_doors_locked_for_all_players(Vehicle, true)
		vehicle.set_vehicle_can_be_locked_on(Vehicle, false, true)
		for i = 1, #seats do
			if seats[i] <= vehicle.get_vehicle_model_number_of_seats(entity.get_entity_model_hash(Vehicle)) - 2 and not entity.is_an_entity(vehicle.get_ped_in_vehicle_seat(Vehicle, seats[i])) then
				kek_menu.create_thread(function(Ped)
					local weapon_hash = weapon_mapper.get_table_of_weapons(true, true)[math.random(1, #weapon_mapper.get_table_of_weapons(true, true))]
					weapon.give_delayed_weapon_to_ped(Ped, weapon_hash, 0, 1)
					weapon_mapper.set_ped_weapon_attachments(Ped, true, weapon_hash)
					kek_entity.set_combat_attributes(Ped, false, false, true, true, true, false, true, true, true, true, true)
					ped.set_ped_can_ragdoll(Ped, false)
					if not ped.set_ped_into_vehicle(Ped, Vehicle, seats[i]) then
						kek_entity.clear_entities({Ped})
						return
					end
					local time = utils.time_ms() + 240000
					if seats[i] == -1 then
						while time > utils.time_ms() and kek_entity.is_entity_valid(Ped) and not entity.is_entity_dead(Ped) and kek_entity.is_entity_valid(Vehicle) and not entity.is_entity_dead(Vehicle) and player.is_player_valid(pid) do
							vehicle.set_heli_blades_full_speed(Vehicle)
							ai.task_vehicle_follow(Ped, Vehicle, player.get_player_ped(pid), 150, kek_menu.settings["Drive style"], 6)
							system.yield(500)
							ai.task_combat_ped(Ped, player.get_player_ped(pid), 0, 16)
							essentials.wait_conditional(15000, function()
								return time > utils.time_ms() and kek_entity.is_entity_valid(Ped) and not entity.is_entity_dead(Ped) and kek_entity.is_entity_valid(Vehicle) and not entity.is_entity_dead(Vehicle) and player.is_player_valid(pid)
							end)
						end
						if dont_clear_vehicle then
							entity.detach_entity(ped.get_vehicle_ped_is_using(Ped) or 0)
							kek_entity.clear_entities({Ped})
						else
							kek_entity.clear_entities({Ped})
							kek_entity.hard_remove_entity_and_its_attachments(Vehicle)
						end
					else
						while time > utils.time_ms() and kek_entity.is_entity_valid(Ped) and not entity.is_entity_dead(Ped) and not entity.is_entity_dead(Vehicle) and player.is_player_valid(pid) do
							essentials.wait_conditional(15000, function()
								return time > utils.time_ms() and kek_entity.is_entity_valid(Ped) and not entity.is_entity_dead(Ped) and not entity.is_entity_dead(Vehicle) and player.is_player_valid(pid)
							end)
							ai.task_combat_ped(Ped, player.get_player_ped(pid), 0, 16)
						end
						kek_entity.clear_entities({Ped})
					end
				end, kek_menu.spawn_entity(hash, function()
					return entity.get_entity_coords(essentials.get_ped_closest_to_your_pov()) + v3(0, 0, 20), 0
				end, false, true, false, 4, false, 1.5))
			end
		end
	end

	function troll_entity.send_army(pid)
		if select(2, table.update_entity_pools()) > kek_menu.ENTITY_PED_LIMIT - 9 then
			return -2
		end
		local valkyrie = kek_menu.spawn_entity(1543134283, function()
			return location_mapper.get_most_accurate_position(player.get_player_coords(pid) + essentials.get_offset(player.get_player_coords(pid), -80, 80, 45, 75), true) + v3(0, 0, 35), 0
		end, false, true, true)
		if not entity.is_an_entity(valkyrie) then
			return -2
		end
		troll_entity.setup_peds_and_put_in_seats({-1, 1, 2}, gameplay.get_hash_key("s_m_y_swat_01"), valkyrie, pid)

		local half_track = kek_menu.spawn_entity(4262731174, function()
			return location_mapper.get_most_accurate_position(player.get_player_coords(pid) + essentials.get_offset(player.get_player_coords(pid), -80, 80, 45, 75), true), 0
		end, false, true, true)
		if not entity.is_an_entity(half_track) then
			return -1
		end
		troll_entity.setup_peds_and_put_in_seats({-1, 1}, gameplay.get_hash_key("s_m_y_swat_01"), half_track, pid)

		local thruster = kek_menu.spawn_entity(1489874736, function()
			return location_mapper.get_most_accurate_position(player.get_player_coords(pid) + essentials.get_offset(player.get_player_coords(pid), -80, 80, 45, 75), true) + v3(0, 0, 35), 0
		end, false, true, true)
		if not entity.is_an_entity(thruster) then
			return -1
		end
		troll_entity.setup_peds_and_put_in_seats({-1}, gameplay.get_hash_key("s_m_y_swat_01"), thruster, pid)

		local khanjali = kek_menu.spawn_entity(2859440138, function()
			return location_mapper.get_most_accurate_position(player.get_player_coords(pid) + essentials.get_offset(player.get_player_coords(pid), -80, 80, 45, 75), true), 0
		end, false, true, true)
		if not entity.is_an_entity(khanjali) then
			return -1
		end
		vehicle.set_vehicle_mod(khanjali, 10, 1)
		troll_entity.setup_peds_and_put_in_seats({-1}, gameplay.get_hash_key("s_m_y_swat_01"), khanjali, pid)
		return valkyrie
	end

-- Send attack chopper
	function troll_entity.send_attack_chopper(pid)
		if select(2, table.update_entity_pools()) > kek_menu.ENTITY_PED_LIMIT - 3 then
			return -2
		end
		local hash = vehicle_mapper.HELICOPTERS[math.random(1, 8)]
		local chopper = kek_menu.spawn_entity(hash, function()
			return location_mapper.get_most_accurate_position(player.get_player_coords(pid) + essentials.get_offset(player.get_player_coords(pid), -80, 80, 45, 75), true) + v3(0, 0, 35), 0
		end, false, true, true)
		if not entity.is_an_entity(chopper) then
			return -2
		end
		vehicle.control_landing_gear(chopper, 3)
		vehicle.set_vehicle_can_be_locked_on(chopper, false, true)
		vehicle.set_vehicle_doors_locked_for_all_players(chopper, true)
		local pilot = kek_menu.spawn_entity(0x9CF26183, function() 
			return location_mapper.get_most_accurate_position(player.get_player_coords(pid)) + v3(0, 0, 10), 0
		end, false, true, false, 4, false, 1.5)
		if not ped.set_ped_into_vehicle(pilot, chopper, -1) then
			kek_entity.clear_entities({pilot, chopper})
			return -2
		end
		kek_entity.set_combat_attributes(pilot, false, false, true, true, false, false, true, true, true, true, true)

		kek_menu.create_thread(function()
			local timer = 0
			local time = utils.time_ms() + 240000
			while time > utils.time_ms() and kek_entity.is_entity_valid(pilot) and kek_entity.is_entity_valid(chopper) and not entity.is_entity_dead(chopper) and player.is_player_valid(pid) do
				vehicle.set_heli_blades_full_speed(chopper)
				ai.task_vehicle_follow(pilot, chopper, player.get_player_ped(pid), 150, kek_menu.settings["Drive style"], 6)
				system.yield(250)
				ai.task_combat_ped(pilot, player.get_player_ped(pid), 0, 16)
				system.yield(250)
				if utils.time_ms() > timer and essentials.get_distance_between(player.get_player_ped(pid), chopper) < 120 then
					ai.task_vehicle_shoot_at_ped(pilot, player.get_player_ped(pid), 2000)
					timer = utils.time_ms() + 5000
					system.yield(250)
				end
			end
			kek_entity.clear_entities({pilot, chopper})
		end, nil)
		troll_entity.setup_peds_and_put_in_seats({0, 1, 2, 3}, gameplay.get_hash_key("s_m_y_swat_01"), chopper, pid)
		return chopper
	end

-- Send kek's chopper
	function troll_entity.send_kek_chopper(pid)
		if select(2, table.update_entity_pools()) > kek_menu.ENTITY_PED_LIMIT - 2 then
			return -2
		end
		local chopper = kek_menu.spawn_entity(2310691317, function() 
			return location_mapper.get_most_accurate_position(player.get_player_coords(pid)) + v3(math.random(-50, 50), math.random(-50, 50), 30), 0
		end, true, true, true)
		if not entity.is_an_entity(chopper) then
			return -2
		end
		vehicle.control_landing_gear(chopper, 3)
		entity.set_entity_collision(chopper, false, true, true)
		local pilot = kek_menu.spawn_entity(0x8D8F1B10, function()
			return location_mapper.get_most_accurate_position(player.get_player_coords(pid)) + v3(0, 0, 20), 0
		end, true, true, false, 4, false, 2)
		kek_entity.set_combat_attributes(pilot, true, false, true, false, false, false, true, true, true, true, true)
		entity.set_entity_collision(pilot, false, true, true)
		if not ped.set_ped_into_vehicle(pilot, chopper, -1) then
			kek_entity.clear_entities({pilot, chopper})
			return -2
		end
		kek_menu.create_thread(function()
			local time = utils.time_ms() + 240000
			while time > utils.time_ms() and player.is_player_valid(pid) and kek_entity.is_entity_valid(pilot) and kek_entity.is_entity_valid(chopper) do
				vehicle.set_heli_blades_full_speed(chopper)
				ai.task_vehicle_follow(pilot, chopper, player.get_player_ped(pid), 300, 17039872, 75)
				system.yield(250)
			end
			kek_entity.clear_entities({pilot, chopper})
		end, nil)

		kek_menu.create_thread(function()
			local time = utils.time_ms() + 240000
			local entities = {}
			while time > utils.time_ms() and player.is_player_valid(pid) and kek_entity.is_entity_valid(pilot) and kek_entity.is_entity_valid(chopper) do
				system.yield(0)
				if essentials.get_distance_between(chopper, player.get_player_ped(pid)) < 170 and not entity.is_entity_dead(player.get_player_ped(pid)) then
					for i = 1, 4 do
						if not entity.is_an_entity(entities[i] or 0) then
							entities[i] = kek_menu.spawn_entity(vehicle.get_all_vehicle_model_hashes()[math.random(1, #vehicle.get_all_vehicle_model_hashes())], function()
								return kek_entity.get_vector_relative_to_entity(chopper, 5, 0, -3), entity.get_entity_heading(chopper)
							end)
						else
							kek_entity.teleport(entities[i], kek_entity.get_vector_relative_to_entity(chopper, 5, 0, -3))
							entity.set_entity_heading(entities[i], entity.get_entity_heading(chopper))
						end
						for i2 = 1, i do
							entity.set_entity_no_collsion_entity(entities[i], entities[i2], true)
						end
						entity.set_entity_rotation(entities[i], entity.get_entity_rotation(chopper))
						vehicle.set_vehicle_forward_speed(entities[i], 100)
						essentials.use_ptfx_function(vehicle.set_vehicle_out_of_control, entities[i], false, true)
					end
					system.yield(1750)
					local temp = {}
					for i = 1, #entities do
						if entity.is_an_entity(entities[i]) then
							temp[#temp + 1] = entities[i]
							kek_entity.repair_car(entities[i], true)
						end
					end
					entities = temp
				end
			end
			kek_entity.clear_entities(entities)
		end, nil)
		return chopper
	end

-- Send clown van
	function troll_entity.send_clown_van(pid)
		if select(2, table.update_entity_pools()) > kek_menu.ENTITY_PED_LIMIT - 3 then
			return -2
		end
		local hash = entity.get_entity_model_hash(player.get_player_vehicle(pid))
		if not essentials.is_player_completely_valid(pid) 
		or (player.is_player_in_any_vehicle(pid) and (streaming.is_model_a_boat(hash) or streaming.is_model_a_heli(hash) or streaming.is_model_a_plane(hash))) then
			return -1
		end
		local clown_van = kek_menu.spawn_entity(728614474, function() 
			return location_mapper.get_most_accurate_position(player.get_player_coords(pid) + essentials.get_offset(player.get_player_coords(pid), -80, 80, 45, 75), true), 0
		end, false, true, true)
		if not entity.is_an_entity(clown_van) then
			return -2
		end
		vehicle.set_vehicle_mod(clown_van, 14, 2)
		local driver = kek_menu.spawn_entity(0x04498DDE, function()
			return entity.get_entity_coords(essentials.get_ped_closest_to_your_pov()) + v3(0, 0, 20), 0
		end, false, true, false, 4, false, 1.5)
		weapon.give_delayed_weapon_to_ped(driver, 584646201, 0, 1)
		weapon_mapper.set_ped_weapon_attachments(driver, false, 584646201)
		if not ped.set_ped_into_vehicle(driver, clown_van, -1) then
			kek_entity.clear_entities({driver, clown_van})
			return -2
		end
		kek_entity.set_combat_attributes(driver, false, false, true, true, false, false, true, true, true, true, false)
		local weapons = essentials.merge_tables(weapon_mapper.get_table_of_rifles(), {weapon_mapper.get_table_of_explosive_weapons(), weapon_mapper.get_table_of_smgs()})
		local close_range = essentials.merge_tables(weapon_mapper.get_table_of_melee_weapons(), {{911657153, 2939590305}})
		local ai_follow_tracker = 0
		kek_menu.create_thread(function()
			local time = utils.time_ms() + 240000
			while time > utils.time_ms() and player.is_player_valid(pid) and kek_entity.is_entity_valid(clown_van) and not entity.is_entity_dead(clown_van) and kek_entity.is_entity_valid(driver) do
				if not ped.is_ped_in_vehicle(driver, clown_van) then
					ped.clear_ped_tasks_immediately(vehicle.get_ped_in_vehicle_seat(clown_van, -1))
					ped.set_ped_into_vehicle(driver, clown_van, -1)
					system.yield(500)
				end
				if ped.is_ped_in_vehicle(driver, clown_van) and utils.time_ms() > ai_follow_tracker then
					ai.task_vehicle_follow(driver, clown_van, player.get_player_ped(pid), 120, kek_menu.settings["Drive style"], 10)
					ai_follow_tracker = utils.time_ms() + 8000
				end
				if entity.is_entity_dead(driver) then
					system.yield(math.random(500, 1500))
					if essentials.request_ptfx("scr_rcbarry2") then
						essentials.use_ptfx_function(graphics.start_networked_particle_fx_non_looped_at_coord, "scr_clown_death", entity.get_entity_coords(driver), v3(), 1, true, true, true)
					end
					ped.resurrect_ped(driver)
					ped.clear_ped_tasks_immediately(driver)
					system.yield(250)
					ped.set_ped_into_vehicle(driver, clown_van, -1)
				end
				if vehicle.is_vehicle_stuck_on_roof(clown_van) then
					vehicle.set_vehicle_forward_speed(clown_van, 50)
				end
				system.yield(250)
			end
			kek_entity.clear_entities({clown_van, driver})
		end, nil)

		local clown_spawn_weapons = {
			584646201, 
			3686625920, 
			3686625920
		}
		for i = 1, math.random(1, 3) do
			kek_menu.create_thread(function(clown)
				local clown_weapon = clown_spawn_weapons[i]
				weapon.give_delayed_weapon_to_ped(clown, clown_weapon, 0, 1)
				weapon_mapper.set_ped_weapon_attachments(clown, true, clown_weapon)
				kek_entity.set_combat_attributes(clown, false, false, false, true, true, true, true, false, true, true, true)
				ped.set_ped_into_vehicle(clown, clown_van, i - 1)
				local Ped = player.get_player_ped(pid)
				ai.task_combat_ped(clown, player.get_player_ped(pid), 0, 16)
				local time = utils.time_ms() + 240000
				while time > utils.time_ms() and player.is_player_valid(pid) and kek_entity.is_entity_valid(clown) and kek_entity.is_entity_valid(clown_van) and not entity.is_entity_dead(clown_van) and kek_entity.is_entity_valid(driver) do
					if entity.is_entity_dead(clown) then
						system.yield(math.random(1000, 2500))
						if essentials.request_ptfx("scr_rcbarry2") then
							essentials.use_ptfx_function(graphics.start_networked_particle_fx_non_looped_at_coord, "scr_clown_death", entity.get_entity_coords(clown), v3(), 1, true, true, true)
						end
						ped.resurrect_ped(clown)
						ped.clear_ped_tasks_immediately(clown)
						ped.set_ped_into_vehicle(clown, clown_van, i - 1)
						system.yield(250)
						ai.task_combat_ped(clown, player.get_player_ped(pid), 0, 16)
					end
					if not ped.is_ped_in_vehicle(clown, clown_van) then
						if player.is_player_in_any_vehicle(pid) or essentials.get_distance_between(player.get_player_ped(pid), clown) > 40 then
							if not essentials.get_index_of_value(weapons, clown_weapon) then
								if weapon.has_ped_got_weapon(clown, clown_weapon) then
									weapon.remove_weapon_from_ped(clown, clown_weapon)
								end
								clown_weapon = weapons[math.random(1, #weapons)]
								weapon.give_delayed_weapon_to_ped(clown, clown_weapon, 0, 1)
								weapon_mapper.set_ped_weapon_attachments(clown, true, clown_weapon)
							end
						elseif not essentials.get_index_of_value(close_range, clown_weapon) then
							if weapon.has_ped_got_weapon(clown, clown_weapon) then
								weapon.remove_weapon_from_ped(clown, clown_weapon)
							end
							clown_weapon = close_range[math.random(1, #close_range)]
							weapon.give_delayed_weapon_to_ped(clown, clown_weapon, 0, 1)
							weapon_mapper.set_ped_weapon_attachments(clown, true, clown_weapon)
						end
					end
					if not ped.is_ped_in_vehicle(clown, clown_van) and essentials.get_distance_between(player.get_player_ped(pid), clown) > 70 then
						ped.set_ped_into_vehicle(clown, clown_van, vehicle.get_free_seat(clown_van))
					elseif ped.is_ped_in_vehicle(clown, clown_van) 
					and not entity.is_entity_dead(player.get_player_ped(pid)) 
					and essentials.get_distance_between(clown_van, player.get_player_ped(pid)) < 30 then
						ai.task_leave_vehicle(clown, clown_van, 256)
						system.yield(250)
					end
					system.yield(250)
					if Ped ~= player.get_player_ped(pid) then
						Ped = player.get_player_ped(pid)
						ai.task_combat_ped(clown, player.get_player_ped(pid), 0, 16)
					end
				end
				kek_entity.clear_entities({clown})
			end, kek_menu.spawn_entity(gameplay.get_hash_key(ped_mapper.LIST_OF_SPECIAL_PEDS[math.random(1, #ped_mapper.LIST_OF_SPECIAL_PEDS)]), function()
				return entity.get_entity_coords(essentials.get_ped_closest_to_your_pov()) + v3(0, 0, 20), 0
			end, false, true, false, 4, false, 1.5))
		end
		return clown_van, driver
	end

return troll_entity