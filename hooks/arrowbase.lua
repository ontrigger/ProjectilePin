local mvec1 = Vector3()
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

			if alive(pin_ray.body) then
				self._attached_body_disabled_cbk_data = {
					cbk = callback(self, self, "_cbk_attached_body_disabled"),
					unit = pin_ray.unit,
					body = pin_ray.body
				}

				pin_ray.unit:add_body_enabled_callback(self._attached_body_disabled_cbk_data.cbk)
			end

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

	log("destroy", tostring(unit:key()), tostring(self._unit:key()))

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

	self:_unfreeze_pin_unit(managers.projectile:pin_data_by_arrow(unit:key()))

	self._pin_data = nil

	self:_remove_switch_to_pickup_clbk()
	self:_remove_attached_body_disabled_cbk()
	self:_kill_trail()
	ArrowBase.super.destroy(self, unit)
end

Hooks:PostHook(ArrowBase, "clbk_hit_unit_destroyed", "ProjectilePinclbk_hit_unit_destroyed", function(_, unit)
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
			if alive(data.body) and alive(data.arrow_unit) then
				self:_reattach_arrow_to_body(data)
			end
			managers.projectile:remove_pin_data(key)
		end
		self:_remove_attached_body_disabled_cbk()

		local has_pinned_unit = table.find_value(all_pin_data, function(pin_data)
			return pin_data.arrow_unit:key() == self._unit:key()
		end)

		if not self._is_dynamic_pickup and not has_pinned_unit then
			self:_switch_to_pickup(true)
		end
	end
end

function ArrowBase:_unfreeze_pin_unit(pin_data)
	if pin_data and pin_data.freeze_listener_id and alive(pin_data.hit_unit) then
		pin_data.hit_unit:character_damage():remove_listener(pin_data.freeze_listener_id)
		-- i just got lazy, this fixes units freezing again if you time breaking the glass right
		managers.enemy:remove_delayed_clbk("freeze_rag" .. tostring(pin_data.hit_unit:key()))

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

	pin_data.arrow_unit:set_position(pin_data.ray.position)
	pin_data.arrow_unit:set_position(pin_data.ray.position)
	pin_data.arrow_unit:set_rotation(mrot1)

	pin_data.hit_unit:link(pin_data.body:root_object():name(), pin_data.arrow_unit)
	self._already_attached = true
end