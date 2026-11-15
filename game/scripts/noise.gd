extends Node
## Zdarzenia hałasu: każdy głośny czyn (uderzenie młotkiem, trzask wyważanych
## drzwi) zostawia tu ślad z miejscem i głośnością. Dziś czyta je tylko ekran
## deweloperski; od buildu 7 będą je słyszeć zombie, a dźwięk powstanie z tych
## samych zdarzeń.

const KEEP := 40

var events: Array = []
var sound   # sound.gd: każdy hałas ma swój dźwięk

signal noise_made(pos: Vector3, loudness: float)  # słyszą to zombie


func emit_noise(pos: Vector3, loudness: float, label_key: String) -> void:
	events.append({"pos": pos, "loud": loudness, "label": label_key,
			"time": Time.get_ticks_msec() / 1000.0})
	if events.size() > KEEP:
		events.pop_front()
	if sound != null:
		sound.on_noise(pos, label_key)
	noise_made.emit(pos, loudness)


func last() -> Dictionary:
	return events[events.size() - 1] if not events.is_empty() else {}


func count_label(label_key: String) -> int:
	var n := 0
	for e in events:
		if e["label"] == label_key:
			n += 1
	return n
