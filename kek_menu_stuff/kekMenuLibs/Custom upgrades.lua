-- Lib Keks Custom upgrades version: 0.1.2
-- Copyright © 2020-2021 Kektram

local custom_upgrades = {}

local essentials = require("Essentials")
local kek_entity = require("Kek's entity functions")
local weapon_mapper = require("Weapon mapper")

function custom_upgrades.create_combat_ped(Vehicle)
	if vehicle.get_free_seat(Vehicle) ~= -2 then
		local Ped = kek_menu.spawn_entity(0x9CF26183, function()
			return kek_entity.get_vector_relative_to_entity(player.get_player_ped(player.player_id()), 8), player.get_player_heading(player.player_id())
		end, true, true, true, 4)
		kek_entity.set_combat_attributes(Ped, true, true)
		local weapon_hash = weapon.get_all_weapon_hashes()[math.random(1, #weapon.get_all_weapon_hashes())]
		weapon.give_delayed_weapon_to_ped(Ped, weapon_hash, 0, 1)
		weapon_mapper.set_ped_weapon_attachments(Ped, true, weapon_hash)
		ped.set_ped_into_vehicle(Ped, Vehicle, vehicle.get_free_seat(Vehicle))
	end
end

function custom_upgrades.vehicle_turret(Vehicle, turret, offset)
	kek_menu.create_thread(function()
		while entity.is_an_entity(turret) and entity.is_an_entity(Vehicle) do
			system.yield(0)
			if player.get_player_vehicle(player.player_id()) == Vehicle and player.is_player_in_any_vehicle(player.player_id()) then
				entity.attach_entity_to_entity(turret, Vehicle, 0, offset, cam.get_gameplay_cam_rot() + v3(cam.get_gameplay_cam_rot().x * -2, 0, 180), false, true, false, 0, false)
				if controls.is_disabled_control_pressed(0, 114) then
					gameplay.shoot_single_bullet_between_coords(kek_entity.get_vector_in_front_of_me(turret, 0.5), kek_entity.get_vector_in_front_of_me(turret, 2000), 100, 177293209, player.get_player_ped(player.player_id()), true, false, 3000)
				end
				if controls.is_disabled_control_pressed(0, 142) then
					essentials.use_ptfx_function(
						gameplay.shoot_single_bullet_between_coords, 
						kek_entity.get_vector_in_front_of_me(turret, 8), 
						kek_entity.get_vector_in_front_of_me(turret, 2000), 
						100, 
						gameplay.get_hash_key("weapon_airstrike_rocket"), 
						player.get_player_ped(player.player_id()), 
						true, 
						false, 
						3000
					)
				end
			end
		end
	end, nil)
end

function custom_upgrades.torque_modifier(Vehicle, multiplier)
	kek_menu.create_thread(function()
		entity.set_entity_as_mission_entity(Vehicle, false, true)
		while entity.is_an_entity(Vehicle) and player.get_player_from_ped(vehicle.get_ped_in_vehicle_seat(Vehicle, -1)) == player.player_id() do
			system.yield(0)
			kek_menu.get_control_of_entity(Vehicle, 0)
			vehicle.set_vehicle_engine_torque_multiplier_this_frame(Vehicle, multiplier)
		end
	end, nil)
end

function custom_upgrades.immune_to_fire(Entity)
	kek_menu.create_thread(function()
		entity.set_entity_as_mission_entity(Entity, false, true)
		while entity.is_an_entity(Entity) do
			system.yield(0)
			if (not entity.is_entity_a_vehicle(Entity) or vehicle.get_ped_in_vehicle_seat(Entity, -1) == 0 or player.get_player_from_ped(vehicle.get_ped_in_vehicle_seat(Entity, -1)) == player.player_id()) and entity.is_entity_on_fire(Entity) and kek_menu.get_control_of_entity(Entity, 0) then
				fire.stop_entity_fire(Entity)
			end
		end
	end, nil)
end

return custom_upgrades	