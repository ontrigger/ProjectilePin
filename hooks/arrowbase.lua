local mvec1 = Vector3()
local mvec2 = Vector3()
local mrot1 = Rotation()

local PROJECTILES_ArrowBase_update = ArrowBase.update

function ArrowBase:update(unit, t, dt)
	if self._pin_data and alive(self._pin_data.body) and not self._already_attached then
		if mvector3.distance(self._pin_data.body:position(), self._pin_data.ray.position) < 150 then
			self:_attach_to_pin_wall()
		end
	end

	PROJECTILES_ArrowBase_update(self, unit, t, dt)
end

function ArrowBase:_on_collision(col_ray)
	local damage_mult = self._weapon_damage_mult or 1
	local loose_shoot = self._weapon_charge_fail

	if not loose_shoot and alive(col_ray.unit) then
		local client_damage = self._damage_class_string == "InstantExplosiveBulletBase" or alive(col_ray.unit) and col_ray.unit:id() ~= -1

		if Network:is_server() or client_damage then
			self._damage_class:on_collision(col_ray, self._weapon_unit or self._unit, self._thrower_unit, self._damage * damage_mult, false, false)
		end
	end

	if not loose_shoot and tweak_data.projectiles[self._tweak_projectile_entry].remove_on_impact then
		self._unit:set_slot(0)

		return
	end

	self._unit:body("dynamic_body"):set_deactivate_tag(Idstring())

	self._col_ray = col_ray
	local hit_unit = col_ray.unit

	if managers.projectile:can_pin_unit(hit_unit) and not managers.projectile:is_unit_pinned(hit_unit) then
		-- needed because there are body and head bodies blocking everything
		local impact_body = managers.projectile:get_impact_body(col_ray.position, hit_unit)
		local raycast_dist = ProjectilePin.tweak:raycast_dist_from_body(impact_body)

		mvector3.set(mvec1, self._unit:rotation():y())
		mvector3.multiply(mvec1, raycast_dist)
		mvector3.add(mvec1, col_ray.position)

		local pin_ray = World:raycast("ray", col_ray.position, mvec1, "ignore_unit", hit_unit, "slot_mask", managers.projectile:pin_mask())
		
		Draw:brush(Color(0.5, 1, 0, 0), nil, 10):line(col_ray.position, mvec1)

		if pin_ray and alive(pin_ray.unit) then
			-- dont push if there is a non-static unit in the way
			if not pin_ray.unit:in_slot(1) and not (pin_ray.unit:base() and pin_ray.unit:base().add_destroy_listener) then
				self:_attach_to_hit_unit(nil, loose_shoot)
				return
			end

			pin_ray.velocity = self._unit:rotation():y()

			managers.projectile:force_ragdoll(hit_unit)

			managers.projectile:add_pinned_unit(hit_unit)

			local physic_effect_name = "physic_effects/shotgun_wat"
			Draw:brush(Color(0.5, 1, 0, 1), nil, 10):line(col_ray.position, pin_ray.position)
			Draw:brush(Color(0.5, 0, 0, 1), nil, 10):sphere(pin_ray.position + (pin_ray.normal * 10), 10)

			local phys_effect = World:play_physic_effect(
				Idstring(physic_effect_name), 
				impact_body, 
				pin_ray.position + (pin_ray.normal * 10),
				hit_unit:mass() * 2
			)

			local freeze_listener_id = "on_rag_frozen" .. tostring(hit_unit:key())
			hit_unit:character_damage():add_listener(freeze_listener_id, {
				"on_ragdoll_frozen"
			}, ClassClbk(self, "clbk_pinned_unit_frozen"))

			local pin_data = {
				attached_unit = pin_ray.unit,
				attached_body = pin_ray.body,
				hit_unit = hit_unit,
				arrow_unit = self._unit,
				body = impact_body,
				ray = pin_ray,
				phys_effect = phys_effect,
				freeze_listener_id = freeze_listener_id,
			}
			self._pin_data = pin_data

			managers.projectile:add_pin_data(hit_unit:key(), pin_data)

			if managers.network:session() then
				managers.network:session():send_to_peers_synched("sync_start_body_pin", nil, "sync_ragdoll_pin")
			end
		end
	end
	self:_attach_to_hit_unit(nil, loose_shoot)
end

function ArrowBase:destroy(unit)
	self:_check_stop_flyby_sound()

	if self._owner_peer_id and ArrowBase._arrow_units[self._owner_peer_id] then
		ArrowBase._arrow_units[self._owner_peer_id][self._unit:key()] = nil
	end

	if self._death_listener_id and alive(self._col_ray.unit) then
		self._col_ray.unit:character_damage():remove_listener(self._death_listener_id)
	end

	self._death_listener_id = nil

	if self._destroy_listener_id and alive(self._col_ray.unit) then
		self._col_ray.unit:base():remove_destroy_listener(self._destroy_listener_id)
	end

	self._destroy_listener_id = nil

	log("DESTROY CALLED", tostring(managers.projectile:pin_data_by_arrow(unit:key())))
	self:_unfreeze_pin_unit(managers.projectile:pin_data_by_arrow(unit:key()))

	self._pin_data = nil

	self:_remove_switch_to_pickup_clbk()
	self:_remove_attached_body_disabled_cbk()
	self:_kill_trail()
	ArrowBase.super.destroy(self, unit)
end

Hooks:PostHook(ArrowBase, "clbk_hit_unit_destroyed", "ProjectilePinclbk_hit_unit_destroyed", function(self, unit)
	local pin_data = managers.projectile:pin_data(unit:key())
	if pin_data then
		World:stop_physic_effect(pin_data.phys_effect)
		
		managers.projectile:remove_pinned_unit(unit)
		managers.projectile:remove_pin_data(unit:key())
	end
end)

function ArrowBase:clbk_pinned_unit_frozen(unit_key)
	if not self._pin_data then
		return
	end
	
	if unit_key == self._col_ray.unit:key() then
		World:stop_physic_effect(self._pin_data.phys_effect)
	end
end

function ArrowBase:_cbk_attached_body_disabled(unit, body)
	if not self._attached_body_disabled_cbk_data then
		log("Got callback but didn't have data!")

		return
	end

	if self._attached_body_disabled_cbk_data.body ~= body then
		return
	end

	if not body:enabled() then
		local all_pin_data = managers.projectile:all_pin_data_for_attached(unit:key())
		for key, data in pairs(all_pin_data) do
			self:_unfreeze_pin_unit(data)
			if alive(data.body) then
				self:_reattach_arrow_to_body(data)
			end
			managers.projectile:remove_pin_data(key)
		end
		self:_remove_attached_body_disabled_cbk()

		if not self._is_dynamic_pickup then
			self:_switch_to_pickup(true)
		end
	end
end

function ArrowBase:_unfreeze_pin_unit(pin_data)
	print_table(pin_data)
	if pin_data and pin_data.freeze_listener_id and alive(pin_data.hit_unit) then
		pin_data.hit_unit:character_damage():remove_listener(pin_data.freeze_listener_id)

		managers.projectile:unfreeze_pinned_ragdoll(pin_data.hit_unit:key())
		managers.projectile:remove_pinned_unit(pin_data.hit_unit:key())
		World:stop_physic_effect(pin_data.phys_effect)
	end
end

function ArrowBase:_attach_to_pin_wall()
	local static_unit = self._pin_data.attached_unit

	mrotation.set_look_at(mrot1, self._col_ray.velocity, math.UP)
	self._unit:set_position(self._pin_data.ray.position)
	self._unit:set_position(self._pin_data.ray.position)
	self._unit:set_rotation(mrot1)

	static_unit:link(static_unit:orientation_object():name(), self._unit)
	self._already_attached = true
end

function ArrowBase:sync_ragdoll_pin()

end

function ArrowBase:_reattach_arrow_to_body(pin_data)
	mrotation.set_look_at(mrot1, pin_data.ray.velocity, math.UP)

	self._unit:set_position(pin_data.ray.position)
	self._unit:set_position(pin_data.ray.position)
	self._unit:set_rotation(mrot1)

	pin_data.hit_unit:link(pin_data.body:root_object():name(), self._unit)
	self._already_attached = true
end

function ArrowBase:_attach_to_hit_unit(is_remote, dynamic_pickup_wanted)
	local instant_dynamic_pickup = dynamic_pickup_wanted and (is_remote or Network:is_server())
	self._attached_to_unit = true

	self:reload_contour()
	self._unit:set_enabled(true)
	self:_set_body_enabled(instant_dynamic_pickup)
	self:_check_stop_flyby_sound(dynamic_pickup_wanted)
	self:_kill_trail()
	mrotation.set_look_at(mrot1, self._col_ray.velocity, math.UP)
	self._unit:set_rotation(mrot1)

	local hit_unit = self._col_ray.unit
	local switch_to_pickup = true
	local switch_to_dynamic_pickup = instant_dynamic_pickup or not alive(hit_unit)
	local local_pos = nil
	local global_pos = self._col_ray.position
	local parent_obj, child_obj, parent_body = nil

	if switch_to_dynamic_pickup then
		self._unit:set_position(global_pos)
		self._unit:set_position(global_pos)

		if alive(hit_unit) and hit_unit:character_damage() then
			self:_set_body_enabled(false)
		end

		self:_set_body_enabled(true)
	elseif alive(hit_unit) then
		local damage_ext = hit_unit:character_damage()

		if damage_ext and damage_ext.get_impact_segment then
			parent_obj, child_obj = damage_ext:get_impact_segment(self._col_ray.position)

			if parent_obj then
				if not child_obj then
					log('doing primitive link')
					hit_unit:link(parent_obj:name(), self._unit, self._unit:orientation_object():name())
				else
					local parent_pos = parent_obj:position()
					local child_pos = child_obj:position()
					local segment_dir = Vector3()
					local segment_dist = mvector3.direction(segment_dir, parent_pos, child_pos)
					local collision_to_parent = Vector3()

					mvector3.set(collision_to_parent, global_pos)
					mvector3.subtract(collision_to_parent, parent_pos)

					local projected_dist = mvector3.dot(collision_to_parent, segment_dir)
					projected_dist = math.clamp(projected_dist, 0, segment_dist)
					local projected_pos = parent_pos + projected_dist * segment_dir
					local max_dist_from_segment = 10
					local dir_from_segment = Vector3()
					local dist_from_segment = mvector3.direction(dir_from_segment, projected_pos, global_pos)

					if max_dist_from_segment < dist_from_segment then
						global_pos = projected_pos + max_dist_from_segment * dir_from_segment
					end

					local_pos = (global_pos - parent_pos):rotate_with(parent_obj:rotation():inverse())
				end
			end

			if not hit_unit:character_damage():dead() and damage_ext:can_kill() then
				switch_to_pickup = false
			end
		elseif damage_ext and damage_ext.can_attach_projectiles and not damage_ext:can_attach_projectiles() then
			switch_to_dynamic_pickup = true
		elseif not alive(self._col_ray.body) or not self._col_ray.body:enabled() then
			local_pos = (global_pos - hit_unit:position()):rotate_with(hit_unit:rotation():inverse())
			switch_to_dynamic_pickup = true
		else
			parent_body = self._col_ray.body
			parent_obj = self._col_ray.body:root_object()
			local_pos = (global_pos - parent_obj:position()):rotate_with(parent_obj:rotation():inverse())
		end

		if damage_ext and not damage_ext:dead() and damage_ext.add_listener and not self._death_listener_id then
			self._death_listener_id = "ArrowBase_death" .. tostring(self._unit:key())

			damage_ext:add_listener(self._death_listener_id, {
				"death"
			}, callback(self, self, "clbk_hit_unit_death"))
		end

		local hit_base = hit_unit:base()

		if hit_base and hit_base.add_destroy_listener and not self._destroy_listener_id then
			self._destroy_listener_id = "ArrowBase_destroy" .. tostring(self._unit:key())

			hit_base:add_destroy_listener(self._destroy_listener_id, callback(self, self, "clbk_hit_unit_destroyed"))
		end

		if hit_base and hit_base._tweak_table == tweak_data.achievement.pincushion.enemy and alive(self:weapon_unit()) and self:weapon_unit():base():is_category(tweak_data.achievement.pincushion.weapon_category) then
			hit_base._num_attached_arrows = (hit_base._num_attached_arrows or 0) + 1

			if hit_base._num_attached_arrows == tweak_data.achievement.pincushion.count then
				managers.achievment:award(tweak_data.achievement.pincushion.award)
			end
		end
	end

	self._unit:set_position(global_pos)
	self._unit:set_position(global_pos)

	if parent_obj then
		hit_unit:link(parent_obj:name(), self._unit)
		log('attaching by parent obj', tostring(parent_obj))
	else
		print("ArrowBase:_attach_to_hit_unit(): No parent object!!")
	end

	if not switch_to_dynamic_pickup then
		local vip_unit = hit_unit and hit_unit:parent() or hit_unit

		if vip_unit and vip_unit:base() and vip_unit:base()._tweak_table == "phalanx_vip" then
			switch_to_pickup = true
			switch_to_dynamic_pickup = true
		end
	end

	if switch_to_pickup then
		if switch_to_dynamic_pickup then
			self:_set_body_enabled(true)
		end

		self:_switch_to_pickup_delayed(switch_to_dynamic_pickup)
	end

	if alive(hit_unit) and parent_body then
		self._attached_body_disabled_cbk_data = {
			cbk = callback(self, self, "_cbk_attached_body_disabled"),
			unit = hit_unit,
			body = parent_body
		}

		hit_unit:add_body_enabled_callback(self._attached_body_disabled_cbk_data.cbk)
	end
	local pin_data = managers.projectile:pin_data_by_arrow(self._unit:key()) or {}

	if alive(pin_data.attached_unit) and alive(pin_data.attached_body) then
		self._attached_body_disabled_cbk_data = {
			cbk = callback(self, self, "_cbk_attached_body_disabled"),
			unit = pin_data.attached_unit,
			body = pin_data.attached_body
		}
		log("adding a body disable clbk!", tostring(hit_unit:key()))
		pin_data.attached_unit:add_body_enabled_callback(self._attached_body_disabled_cbk_data.cbk)
	end

	if not is_remote then
		local dir = self._col_ray.velocity

		mvector3.normalize(dir)

		if managers.network:session() then
			local unit = alive(hit_unit) and hit_unit:id() ~= -1 and hit_unit

			managers.network:session():send_to_peers_synched("sync_attach_projectile", self._unit:id() ~= -1 and self._unit or nil, dynamic_pickup_wanted or false, unit or nil, unit and parent_body or nil, unit and parent_obj or nil, unit and local_pos or self._unit:position(), dir, tweak_data.blackmarket:get_index_from_projectile_id(self._tweak_projectile_entry), managers.network:session():local_peer():id())
		end
	end

	if alive(hit_unit) then
		local dir = self._col_ray.velocity

		mvector3.normalize(dir)

		if parent_body then
			local id = hit_unit:editor_id()

			if id ~= -1 then
				self._sync_attach_data = {
					parent_unit = hit_unit,
					parent_unit_id = id,
					parent_body = parent_body,
					local_pos = local_pos or self._unit:position(),
					dir = dir
				}
			end
		else
			local id = hit_unit:id()

			if id ~= -1 then
				self._sync_attach_data = {
					character = true,
					parent_unit = hit_unit:id() ~= -1 and hit_unit or nil,
					parent_obj = hit_unit:id() ~= -1 and parent_obj or nil,
					parent_body = hit_unit:id() ~= -1 and parent_body or nil,
					local_pos = hit_unit:id() ~= -1 and local_pos or self._unit:position(),
					dir = dir
				}
			end
		end
	end
end