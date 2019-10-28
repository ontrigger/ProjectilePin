ProjectileManager = ProjectileManager or class()

function ProjectileManager:init()
	self._pinned_units = {}
	self._pin_data = {}
    -- go through dynamics (11)
	-- but stop at civs (21, 22)
	-- or sentry guns (25, 26)
	self._pin_mask = World:make_slot_mask(1, 8, 21, 22, 25, 26, 39)
end

local blacklisted_bodies = {
	[Idstring('body')] = true,
	[Idstring('head')] = true,
}

function ProjectileManager:_chk_body_blacklisted(body)
	for bl_body in pairs(blacklisted_bodies) do
		if body:name() == bl_body then
			return true
		end
	end

	return false
end

local impact_bones_tmp = {
	[Idstring("Hips")] = "rag_Hips",
	[Idstring("Spine")] = "rag_Spine",
	[Idstring("Spine1")] = "rag_Spine1",
	[Idstring("Spine2")] = "rag_Spine2",
	[Idstring("Neck")] = "rag_Head",
	[Idstring("Head")] = "rag_Head",
	[Idstring("LeftShoulder")] = "rag_LeftArm",
	[Idstring("LeftArm")] = "rag_LeftArm",
	[Idstring("LeftForeArm")] = "rag_LeftForeArm",
	[Idstring("RightShoulder")] = "rag_RightArm",
	[Idstring("RightArm")] = "rag_RightArm",
	[Idstring("RightForeArm")] = "rag_RightForeArm",
	[Idstring("LeftUpLeg")] = "rag_LeftUpLeg",
	[Idstring("LeftLeg")] = "rag_LeftLeg",
	[Idstring("LeftFoot")] = "rag_LeftLeg",
	[Idstring("RightUpLeg")] = "rag_RightUpLeg",
	[Idstring("RightLeg")] = "rag_RightLeg",
	[Idstring("RightFoot")] = "rag_RightLeg"
}

function ProjectileManager:pin_mask()
    return self._pin_mask
end

function ProjectileManager:temp_bones()
	return impact_bones_tmp
end

function ProjectileManager:add_pinned_unit(unit)
    self._pinned_units[unit:key()] = unit
end

function ProjectileManager:is_unit_pinned(unit) 
    return self._pinned_units[unit:key()] and true or false
end

function ProjectileManager:remove_pinned_unit(unit_key)
    self._pinned_units[unit_key] = nil
end

function ProjectileManager:add_pin_data(unit_key, pin_data)
	self._pin_data[unit_key] = pin_data
end

function ProjectileManager:remove_pin_data(unit_key)
	self._pin_data[unit_key] = nil
end

function ProjectileManager:pin_data(unit_key)
	return self._pin_data[unit_key]
end

function ProjectileManager:pin_data_by_arrow(arrow_key)
	local pin_data
	for k, data in pairs(self._pin_data) do
		if data.arrow_unit:key() == arrow_key then
			pin_data = data
			break
		end
	end

	return pin_data
end

function ProjectileManager:all_pin_data_for_attached(attached_key)
	local all_pin_data = {}
	for k, data in pairs(self._pin_data) do
		if data.attached_unit:key() == attached_key then
			table.insert(all_pin_data, data)
		end
	end

	return all_pin_data
end



function ProjectileManager:get_impact_body(impact_pos, impact_unit) 
	local obj = impact_unit:character_damage():get_impact_segment(impact_pos)

	for obj_name_id, body_name in pairs(impact_bones_tmp) do
		if obj:name() == obj_name_id then
			return impact_unit:body(body_name)
		end
	end
	
    return impact_unit:body(Idstring("rag_Head"))
end

function ProjectileManager:get_closest_bodies_to_body(orig_body)
	local bodies = {}
	local my_unit = orig_body:unit()

	local nr_bodies = my_unit:num_bodies()
	local i_body = 0

	while nr_bodies > i_body do
		local test_body = my_unit:body(i_body)

		if test_body:name() ~= orig_body:name() and not self:_chk_body_blacklisted(test_body) then
			
			table.insert(bodies, {
				body = test_body, 
				dist = mvector3.distance(test_body:center_of_mass(), orig_body:center_of_mass())
			})
		end

		i_body = i_body + 1
	end

	table.sort(bodies, function(left, right)
		return left.dist < right.dist
	end)

	return bodies
end

function ProjectileManager:on_ragdoll_frozen(rag_key)
	local ragdoll = self._pinned_units[rag_key]


	if ragdoll then
		self:unfreeze_pinned_ragdoll(rag_key)
	end
end

function ProjectileManager:can_pin_unit(unit)
	if alive(unit) and unit:character_damage() and unit:character_damage():dead() then
		if not unit:movement()._active_actions[1]._ragdolled then
			return true
		end
	end

	return false
end

function ProjectileManager:force_ragdoll(unit)
	if unit:movement() and unit:movement()._active_actions and unit:movement()._active_actions[1] and unit:movement()._active_actions[1]:type() == "hurt" then
		unit:movement()._active_actions[1]:force_ragdoll()
	end
end

function ProjectileManager:freeze_pinned_ragdoll(rag_key)
	local ragdoll = self._pinned_units[rag_key]

	if ragdoll and alive(ragdoll) then
		ragdoll:damage():run_sequence_simple("freeze_ragdoll")
	end
end

function ProjectileManager:unfreeze_pinned_ragdoll(rag_key)
	local ragdoll = self._pinned_units[rag_key]
	
	if ragdoll and alive(ragdoll) then
		log("unfreezing", tostring(ragdoll))
		ragdoll:damage():run_sequence_simple("switch_to_ragdoll")

		managers.enemy:add_delayed_clbk(
			"freeze_rag" .. tostring(rag_key) , 
			ClassClbk(ragdoll:movement()._active_actions[1], "clbk_chk_freeze_ragdoll"), 
			TimerManager:game():time() + 3
		)
	end

end
