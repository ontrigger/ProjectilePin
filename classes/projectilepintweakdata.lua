ProjectilePinTweakData = ProjectilePinTweakData or class()

ProjectilePinTweakData.DEFAULT_RAYCAST_DIST = 600
function ProjectilePinTweakData:init(tweak_data)
    self._body_pin_raycast_dist = {
        [Idstring("rag_Spine")] = 600,
        [Idstring("rag_Head")] = 1600,
        [Idstring("rag_Spine1")] = 600,
        [Idstring("rag_Spine2")] = 600,
        [Idstring("rag_LeftForeArm")] = 450,
        [Idstring("rag_RightForeArm")] = 450,
        [Idstring("rag_LeftArm")] = 450,
        [Idstring("rag_RightArm")] = 450,
        [Idstring("rag_LeftUpLeg")] = 350,
        [Idstring("rag_RightUpLeg")] = 350,
        [Idstring("rag_LeftLeg")] = 250,
        [Idstring("rag_RightLeg")] = 250,
        [Idstring("rag_Hips")] = 600,
    }

    self._blacklisted_bodies = {

    }
end

function ProjectilePinTweakData:raycast_dist_from_body(body)
    return self._body_pin_raycast_dist[body:name()] or self.DEFAULT_RAYCAST_DIST
end