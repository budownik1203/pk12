extends Node
## Doczytywanie obszarów: to, co daleko od gracza, przestaje istnieć dla silnika
## (nie rysuje się i nie ma fizyki), ale jego stan zostaje nietknięty: zawartość
## mebli, otwarte drzwi, wybite szyby, zwłoki i porzucone rzeczy czekają, aż gracz
## wróci. Kolejność progów pilnuje, żeby nic nie spadło przez wyłączoną podłogę:
## przedmioty i zombie zasypiają bliżej niż wyłącza się dom, a budzą się dalej
## niż on się włącza.
##   dom:     wyłącza się powyżej HOUSE_OUT, włącza poniżej HOUSE_IN,
##   zombie i przedmioty: zasypiają powyżej THING_OUT, budzą się poniżej THING_IN.

const HOUSE_OUT := 58.0
const HOUSE_IN := 48.0
const THING_OUT := 52.0
const THING_IN := 44.0
const PERIOD := 0.4

var main
var enabled := true
var active_houses := 0
var sleeping_things := 0
var _t := 0.0


func setup(main_node) -> void:
	main = main_node


func _physics_process(delta: float) -> void:
	if main == null or main.player == null or main.town == null or not enabled:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = PERIOD
	update_now()


## Jedno przejście (testy wołają je bez czekania).
func update_now() -> void:
	var p: Vector3 = main.player.global_position
	var q := Vector2(p.x, p.z)
	sleeping_things = 0
	# najpierw rzeczy i zombie (zasypiają przed wyłączeniem domu)
	for b in main.world_items.bodies:
		if not is_instance_valid(b):
			continue
		var d := q.distance_to(Vector2(b.global_position.x, b.global_position.z))
		var asleep: bool = b.get_meta("stream_frozen", false)
		if not asleep and d > THING_OUT:
			b.set_meta("stream_frozen", true)
			b.set_meta("stream_was_frozen", b.freeze)
			b.freeze = true
			b.visible = false
		elif asleep and d < THING_IN:
			b.set_meta("stream_frozen", false)
			b.freeze = bool(b.get_meta("stream_was_frozen", false))
			b.visible = true
		if b.get_meta("stream_frozen", false):
			sleeping_things += 1
	for z in main.zombies.zombies:
		var d := q.distance_to(Vector2(z.global_position.x, z.global_position.z))
		var asleep: bool = z.process_mode == Node.PROCESS_MODE_DISABLED
		if not asleep and d > THING_OUT:
			z.process_mode = Node.PROCESS_MODE_DISABLED
			z.visible = false
		elif asleep and d < THING_IN:
			z.process_mode = Node.PROCESS_MODE_INHERIT
			z.visible = true
		if z.process_mode == Node.PROCESS_MODE_DISABLED:
			sleeping_things += 1
	active_houses = 0
	for i in main.town.house_nodes.size():
		var node: Node3D = main.town.house_nodes[i]
		var rect: Rect2 = main.town.buildings[i]
		var d := _dist_to_rect(q, rect)
		var off := node.process_mode == Node.PROCESS_MODE_DISABLED
		if not off and d > HOUSE_OUT:
			node.process_mode = Node.PROCESS_MODE_DISABLED  # bryły wypadają z fizyki (disable_mode: usunięcie)
			node.visible = false
		elif off and d < HOUSE_IN:
			node.process_mode = Node.PROCESS_MODE_INHERIT
			node.visible = true
		if node.process_mode != Node.PROCESS_MODE_DISABLED:
			active_houses += 1


static func _dist_to_rect(q: Vector2, r: Rect2) -> float:
	var cx := clampf(q.x, r.position.x, r.end.x)
	var cy := clampf(q.y, r.position.y, r.end.y)
	return q.distance_to(Vector2(cx, cy))


## Wszystko włączone (zapis, testy wymagające pełnego świata).
func wake_all() -> void:
	for b in main.world_items.bodies:
		if is_instance_valid(b) and b.get_meta("stream_frozen", false):
			b.set_meta("stream_frozen", false)
			b.freeze = bool(b.get_meta("stream_was_frozen", false))
			b.visible = true
	for z in main.zombies.zombies:
		z.process_mode = Node.PROCESS_MODE_INHERIT
		z.visible = true
	for node in main.town.house_nodes:
		node.process_mode = Node.PROCESS_MODE_INHERIT
		node.visible = true
