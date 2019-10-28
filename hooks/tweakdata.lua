local PROJECTILEStweak_init = TweakData.init

function TweakData:init()
    self.projectile_pin = ProjectilePinTweakData:new(self)
    log('post initing shitttttt')

    PROJECTILEStweak_init(self)
end