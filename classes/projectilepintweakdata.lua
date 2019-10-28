ProjectilePinTweakData = ProjectilePinTweakData or class()

ProjectilePinTweakData.DEFAULT_RAYCAST_DIST = 600
function ProjectilePinTweakData:init(tweak_data)
    log('[ProjectilePinTweakData]')
    self._body_pin_raycast_dist = {
        ["rag_Spine"] = 400,
        ["rag_Spine1"] = 400,
        ["rag_Spine2"] = 400,
        ["rag_LeftForeArm"] = 250,
        ["rag_RightForeArm"] = 250,
        ["rag_LeftArm"] = 200,
        ["rag_RightArm"] = 200,
        ["rag_LeftUpLeg"] = 250,
        ["rag_RightUpLeg"] = 250,
        ["rag_LeftLeg"] = 200,
        ["rag_RightLeg"] = 200,
        ["rag_Hips"] = 300,
    }
end

function ProjectilePinTweakData:raycast_dist_from_body(body_name)
    return self._body_pin_raycast_dist[body_name] or self.DEFAULT_RAYCAST_DIST
end