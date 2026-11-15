extends Node
## Potrzeby: głód, pragnienie, zmęczenie (0 = brak, 100 = skrajne), temperatura
## ciała i zatrucie pokarmowe. Narastają w czasie gry (zegar doby), szybciej
## przy wysiłku. Skrajne stany odbierają zdrowie (needs_damage w health.gd).
## Jedzenie i picie: przeciągnięcie na ciało w oknie zdrowia (H). Sen: F na
## materacu; czas biegnie wtedy 90 razy szybciej.
## Temperatura: na zewnątrz z zegara, w pokoju cieplej, a im mniej desek
## w oknie, tym bardziej ciągnie zimnem. Ubrania mają pole "insulation".

const HUNGER_PER_HOUR := 4.0
const THIRST_PER_HOUR := 6.0
const FATIGUE_PER_HOUR := 5.0
const SLEEP_RECOVERY := 14.0          # zmęczenie na godzinę snu na materacu
const SLEEP_SPEED := 90.0            # 8 godzin snu w około 13 sekund
const BODY_NORMAL := 37.0
const DAMAGE_REGEN := 6.0             # punkty na godzinę, gdy potrzeby są w normie

var main
var hunger := 15.0
var thirst := 15.0
var fatigue := 10.0
var body_temp := 37.0
var poison := 0.0                     # 0..1 zatrucie pokarmowe
var damage := 0.0                     # obrażenia od głodu, pragnienia, zimna i zatrucia (0..100)
var sleeping := false
var exertion := 0.0                   # 0..1, wygładzony wysiłek (sprint, walka, praca)
var _sleep_quality := 1.0


func setup(main_node) -> void:
	main = main_node


func _physics_process(delta: float) -> void:
	if main == null or main.player == null or main.health.dead:
		return
	var hours: float = main.clock.game_hours(delta)
	var pl = main.player
	var busy: float = 0.0
	if Vector2(pl.velocity.x, pl.velocity.z).length() > pl.WALK_SPEED + 0.5:
		busy = 1.0
	if main.combat.state != "idle" or main.work.is_active():
		busy = maxf(busy, 0.7)
	exertion = move_toward(exertion, busy, delta * 0.5)
	var mult := 1.0 + exertion * 1.2
	if sleeping:
		hunger += HUNGER_PER_HOUR * 0.5 * hours
		thirst += THIRST_PER_HOUR * 0.5 * hours
		fatigue -= SLEEP_RECOVERY * _sleep_quality * hours
		if fatigue <= 2.0 or main.health.pain > 70.0 or thirst > 95.0 or hunger > 95.0:
			wake()
	else:
		hunger += HUNGER_PER_HOUR * (1.0 + exertion * 0.5) * hours
		thirst += THIRST_PER_HOUR * mult * (1.3 if body_temp > 37.6 else 1.0) * hours
		fatigue += FATIGUE_PER_HOUR * (1.0 + exertion * 0.5 + main.health.pain / 200.0) * hours
	hunger = clampf(hunger, 0.0, 100.0)
	thirst = clampf(thirst, 0.0, 100.0)
	fatigue = clampf(fatigue, 0.0, 100.0)
	_update_temperature(hours)
	poison = maxf(0.0, poison - 0.08 * hours)
	# obrażenia od skrajnych stanów i ich odrabianie
	var harm := 0.0
	if hunger > 85.0:
		harm += (hunger - 85.0) * 0.4
	if thirst > 85.0:
		harm += (thirst - 85.0) * 0.8
	if body_temp < 35.5:
		harm += (35.5 - body_temp) * 12.0
	if body_temp > 38.8:
		harm += (body_temp - 38.8) * 10.0
	harm += poison * 8.0
	if harm > 0.0:
		damage = minf(100.0, damage + harm * hours)
	else:
		damage = maxf(0.0, damage - DAMAGE_REGEN * hours)
	_apply_effects()


## Temperatura otoczenia w miejscu gracza (°C).
func ambient_temp() -> float:
	var outside: float = main.clock.outside_temp()
	var inside: bool = main.player.global_position.z < 3.5 + 0.05
	if not inside:
		return outside
	var boards: int = main.window_boards.secure_count() if main.window_boards != null else 3
	var draft := (3.0 - boards) * 1.5  # nieszczelne okno: ciągnie zimnem
	return outside + 7.0 - draft


## Izolacja ubrań: suma pól "insulation" założonych rzeczy (0..1+).
func insulation() -> float:
	var s := 0.0
	for slot in main.inventory.slots:
		if slot in ["w_reku", "w_lewej", "oburacz"]:
			continue
		var it = main.inventory.slots[slot]
		s += float(it.get_def().get("insulation", 0.0)) * clampf(it.condition() + 0.3, 0.3, 1.0)
	return s


## Odczuwana temperatura: otoczenie, ubrania, wysiłek.
func felt_temp() -> float:
	return ambient_temp() + insulation() * 10.0 + exertion * 6.0 + (3.0 if sleeping else 0.0)


func _update_temperature(hours: float) -> void:
	var felt := felt_temp()
	# komfort 18–29 °C odczuwanej; poza nim ciało powoli traci lub zyskuje ciepło
	var target := BODY_NORMAL
	if felt < 18.0:
		target = BODY_NORMAL - (18.0 - felt) * 0.18
	elif felt > 29.0:
		target = BODY_NORMAL + (felt - 29.0) * 0.12
	body_temp = move_toward(body_temp, target, 1.2 * hours)


func _apply_effects() -> void:
	var pl = main.player
	var regen := 1.0
	if fatigue > 60.0:
		regen *= 0.75
	if fatigue > 85.0:
		regen *= 0.7
	if thirst > 70.0:
		regen *= 0.7
	if hunger > 75.0:
		regen *= 0.8
	if body_temp < 36.2:
		regen *= 0.8
	pl.needs_regen = regen


# --- jedzenie i picie ------------------------------------------------------------

## Zjedzenie porcji jedzenia (z danych "food"); zwraca, czy coś zostało zjedzone.
func eat(item) -> bool:
	var f: Dictionary = item.get_def().get("food", {})
	if f.is_empty() or bool(f.get("sealed", false)):
		return false
	var portions := int(f.get("portions", 1))
	var share := 1.0 / float(portions)
	var fresh := freshness(item)
	hunger = maxf(0.0, hunger - float(f.get("hunger", 10.0)) * share * (0.6 if fresh == "rotten" else 1.0))
	thirst = clampf(thirst - float(f.get("thirst", 0.0)) * share, 0.0, 100.0)
	if fresh == "rotten":
		poison = minf(1.0, poison + 0.5 * share + 0.15)
		main.hud.show_message(tr("MSG_ATE_ROTTEN"))
	elif fresh == "stale":
		poison = minf(1.0, poison + 0.05)
	var left := int(item.props.get("portions", portions)) - 1
	if left <= 0:
		var empty := str(f.get("empty", ""))
		main.inventory.remove_item(item)
		if empty != "":
			main.inventory.give(preload("res://scripts/inventory/item.gd").new(empty, 1))
	else:
		item.props["portions"] = left
		main.inventory.changed.emit()
	main.sound.play_ui("eat", -6.0)
	return true


## Wypicie łyku z pojemnika z wodą (do 0,25 l).
func drink(item) -> bool:
	if item.liquid.is_empty() or float(item.liquid.get("amount", 0.0)) <= 0.001:
		return false
	var amount := minf(0.25, float(item.liquid["amount"]))
	item.liquid["amount"] = float(item.liquid["amount"]) - amount
	if item.liquid["amount"] <= 0.001:
		item.liquid = {}
	drink_water(amount)
	main.inventory.changed.emit()
	return true


func drink_water(liters: float) -> void:
	thirst = maxf(0.0, thirst - liters * 100.0)
	main.sound.play_ui("drink", -6.0)


## "fresh", "stale" albo "rotten" (psucie od dnia gry zapisanego w props "made").
func freshness(item) -> String:
	var f: Dictionary = item.get_def().get("food", {})
	if not f.has("rot_days"):
		return "fresh"
	var made := float(item.props.get("made", 0.0))
	var age: float = main.clock.minutes / 1440.0 - made
	if age >= float(f["rot_days"]):
		return "rotten"
	if age >= float(f.get("stale_days", f["rot_days"])):
		return "stale"
	return "fresh"


# --- sen -------------------------------------------------------------------------

func try_sleep(quality: float) -> bool:
	if sleeping:
		return false
	if fatigue < 20.0:
		main.hud.show_message(tr("MSG_NOT_SLEEPY"))
		return false
	if main.health.bleed_rate() > 0.01:
		main.hud.show_message(tr("MSG_CANT_SLEEP_BLEED"))
		return false
	sleeping = true
	_sleep_quality = quality
	main.clock.speed = SLEEP_SPEED
	main.player.controls_locked = true
	main.hud.set_sleep(true)
	return true


func wake() -> void:
	if not sleeping:
		return
	sleeping = false
	main.clock.speed = 1.0
	main.player.controls_locked = false
	main.hud.set_sleep(false)
	main.hud.show_message(tr("MSG_WOKE") % main.clock.text())


func to_dict() -> Dictionary:
	return {"hunger": hunger, "thirst": thirst, "fatigue": fatigue, "body_temp": body_temp,
			"poison": poison, "damage": damage}


func from_dict(d: Dictionary) -> void:
	hunger = float(d.get("hunger", 15.0))
	thirst = float(d.get("thirst", 15.0))
	fatigue = float(d.get("fatigue", 10.0))
	body_temp = float(d.get("body_temp", 37.0))
	poison = float(d.get("poison", 0.0))
	damage = float(d.get("damage", 0.0))
	if sleeping:
		wake()
