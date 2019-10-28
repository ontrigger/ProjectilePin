function ProjectilePin:Init()
	Hooks:Add("MenuUpdate", "ProjectilePinMenuUpdate", ClassClbk(self, "update"))
    Hooks:Add("GameSetupUpdate", "ProjectilePinGameSetupUpdate", ClassClbk(self, "update"))
    Hooks:Add("GameSetupPauseUpdate", "ProjectilePinGameSetupPausedUpdate", ClassClbk(self, "paused_update"))

	if not self.FileWatcher and FileIO:Exists("mods/developer.txt") then
        self.FileWatcher = FileWatcher:new(ModPath, {
            callback = ClassClbk(self, "reload_code"),
            scan_t = 0.5
		})
	end

	self.tweak = ProjectilePinTweakData:new(tweak_data)
end

function ProjectilePin:reload_code()
	if self then return end

	for i, v in ipairs(self._config) do
		for i2, v2 in ipairs(v) do
			if v2.file then
				dofile(Path:Combine(self.ModPath, v.directory, v2.file))
			end
		end
	end
end

function ProjectilePin:update(t, dt)
	if self.FileWatcher then
        self.FileWatcher:Update(t, dt)
    end
end

function ProjectilePin:paused_update(t, dt)
	if self.FileWatcher then
        self.FileWatcher:Update(t, dt)
    end
end

if not _G.ProjectilePin then
	local success, err = pcall(function() ProjectilePin:new() end)
	if not success then
		log("[ERROR] An error occured on the initialization of ProjectilePin. " .. tostring(err))
	end
end


log("regregrtgrtgrtgrtgt")