Hooks:PostHook(CopActionHurt, "_freeze_ragdoll", "PROJECTILES_freeze_ragdoll", function(self)
    self._unit:character_damage():call_listener("on_ragdoll_frozen", self._unit:key())
end)