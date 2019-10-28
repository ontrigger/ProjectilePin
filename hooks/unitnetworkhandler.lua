local tmp_rot1 = Rotation()
log('in unit')

function UnitNetworkHandler:sync_pin_body(body, damage, sender)
	if not self._verify_gamestate(self._gamestate_filter.any_ingame) or not self._verify_sender(sender) then
		return
	end
end