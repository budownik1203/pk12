extends Control
## Kółko opcji pod przytrzymanym F (jak w Project Zomboid). Opcje dotyczą tego,
## na co patrzysz (urządzenie, drzwi, pojemnik, przedmiot), plus stałe: tryb
## narzędziowy i walki, latarka, chwyt oburącz. Wybór ruchem myszy w stronę
## opcji; puszczenie F albo lewy przycisk wykonuje, prawy przycisk albo Esc anuluje.
## Każda opcja: {"label": tekst, "do": Callable, "on": bool (opcjonalnie: stan
## przełącznika do podświetlenia)}.

const RADIUS := 150.0
const INNER := 46.0
const DEAD := 26.0                  # tyle ruchu myszy, zanim cokolwiek się wybierze

var options: Array = []
var selected := -1
var title := ""
var _aim := Vector2.ZERO
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func is_open() -> bool:
	return visible


func open(opts: Array, head: String = "") -> void:
	options = opts
	title = head
	selected = -1
	_aim = Vector2.ZERO
	visible = not options.is_empty()
	queue_redraw()


func close() -> void:
	visible = false
	options = []


## Ruch myszy (przechwycony): kierunek wybiera opcję.
func aim(relative: Vector2) -> void:
	_aim = (_aim + relative).limit_length(RADIUS)
	if _aim.length() < DEAD:
		selected = -1
	else:
		var n := options.size()
		var ang := fposmod(_aim.angle() + PI / 2.0 + PI / n, TAU)  # 0 = góra, zgodnie z zegarem
		selected = int(ang / (TAU / n)) % n
	queue_redraw()


## Wykonuje wybraną opcję i zamyka. Zwraca, czy coś wykonano.
func confirm() -> bool:
	var ok := false
	if selected >= 0 and selected < options.size():
		var c: Callable = options[selected]["do"]
		close()
		c.call()
		ok = true
	else:
		close()
	return ok


func _center() -> Vector2:
	return size * 0.5


func _draw() -> void:
	if options.is_empty():
		return
	var c := _center()
	var n := options.size()
	draw_circle(c, RADIUS + 34.0, Color(0, 0, 0, 0.45))
	draw_circle(c, INNER, Color(0.08, 0.08, 0.08, 0.8))
	for i in n:
		var a0 := -PI / 2.0 + (i - 0.5) * TAU / n
		var a1 := a0 + TAU / n
		var pts := PackedVector2Array()
		var steps := 10
		for k in steps + 1:
			pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(k) / steps)) * (RADIUS + 30.0))
		for k in range(steps, -1, -1):
			pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(k) / steps)) * (INNER + 4.0))
		var on: bool = bool(options[i].get("on", false))
		var col := Color(0.55, 0.45, 0.25, 0.85) if i == selected else (Color(0.25, 0.32, 0.22, 0.75) if on else Color(0.16, 0.16, 0.16, 0.7))
		draw_colored_polygon(pts, col)
		draw_polyline(pts, Color(0, 0, 0, 0.6), 1.5, true)
		var mid := c + Vector2.from_angle((a0 + a1) * 0.5) * (RADIUS * 0.68 + 14.0)
		var label := str(options[i]["label"])
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(font, mid - Vector2(minf(w, 150.0) * 0.5, -5.0), label, HORIZONTAL_ALIGNMENT_LEFT, 150, 15, Color(0.95, 0.92, 0.85))
	if title != "":
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(font, c - Vector2(minf(tw, 84.0) * 0.5, -5.0), title, HORIZONTAL_ALIGNMENT_LEFT, 84, 14, Color(0.85, 0.82, 0.7))
	if _aim.length() >= DEAD:
		draw_line(c, c + _aim.normalized() * INNER, Color(0.95, 0.85, 0.5), 3.0)
