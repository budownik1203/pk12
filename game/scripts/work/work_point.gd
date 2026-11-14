extends RefCounted
## Punkt pracy: miejsce w świecie, w którym narzędziem albo częścią można coś
## zrobić (koniec deski do podważenia, gwóźdź do wbicia, wkręt, gniazdo na
## zamek). Właściciel (okno, drzwi) dostaje zdarzenia pracy i decyduje o skutku.
##
## Rodzaje:
##   lever   prawy przycisk + ruch myszy w dół (podważanie, wyciąganie)
##   rotate  prawy przycisk + kręcenie myszą albo kółkiem (wkręcanie)
##   strike  prawy przycisk + zamach w górę i uderzenie w dół (wbijanie)
##   attach  lewy przycisk z częścią w ręce (przyłożenie deski, nakładki, zamka)

var id := ""
var owner                       # obiekt z work_apply(point, event) i work_status(point)
var node: Node3D                # węzeł, do którego przypięty jest punkt
var local := Vector3.ZERO       # położenie w układzie węzła
var kind := "lever"
var ability := ""               # wymagana zdolność narzędzia (np. "podwazanie")
var min_level := 1
var accepts := ""               # attach: rodzaj montażu przedmiotu w ręce
var enabled := true
var label_key := ""             # podpowiedź (klucz tłumaczenia)
var data := {}                  # dane właściciela (numer deski, końca, wkrętu)


func world_pos() -> Vector3:
	return node.global_transform * local
