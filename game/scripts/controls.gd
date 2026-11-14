extends RefCounted
## Rejestracja akcji sterowania w kodzie (tylko PC: klawiatura i mysz).
## Kolejne buildy dopisują tu swoje akcje; układ uzgodniony 14.11.2026.

const KEYS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"sprint": KEY_SHIFT,
	"jump": KEY_SPACE,
	"crouch": KEY_CTRL,
	"lean_left": KEY_Q,
	"lean_right": KEY_E,
	"grab": KEY_T,
	"interact": KEY_F,
	"inventory": KEY_TAB,
	"flashlight": KEY_X,
	"drop_hand": KEY_G,
	# zarezerwowane na kolejne buildy:
	"health": KEY_H,
	"rotate_item": KEY_R,
}


static func register() -> void:
	for action in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEYS[action]
		InputMap.action_add_event(action, ev)
