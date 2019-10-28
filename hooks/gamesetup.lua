Hooks:PostHook(GameSetup, "init_managers", "PROJECTILESGameSetup", function(self, managers)
    managers.projectile = ProjectileManager:new()
end)