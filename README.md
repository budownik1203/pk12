# PSK-12 (Projekt Strefy Kwarantanny 12)

Pierwszoosobowy, fizyczny sandbox survivalowy w duchu Project Zomboid. Godot 4.7, fizyka Jolt, tylko PC.

## Jak uruchomić

1. Otwórz Godota 4.7 i wybierz **Importuj**, wskaż plik `game/project.godot`.
2. Wciśnij **F5**.

## Stan: build 2b, ciało i dłonie

Pokój testowy z drzwiami na zawiasie, dwiema lampami z włącznikami i bryłami o masie od 0,4 do 70 kg. Postać ma widoczne ciało: nogi stawiają kroki, kucanie zgina kolana, ręce sięgają do trzymanych przedmiotów (ciężkie obiema rękami), a latarka jest w lewej dłoni, która przy obrocie zostaje w tyle za kamerą.

| Klawisz | Działanie |
| --- | --- |
| WASD | ruch (z bezwładnością) |
| Shift | sprint (zużywa wytrzymałość) |
| Ctrl | kucanie |
| Q, E | wychylanie |
| Spacja | skok; przy przeszkodzie do wysokości klatki piersiowej wspinanie |
| T | chwyt tego, na co patrzysz (celownik zmienia się w dłoń), drugi raz puszczenie |
| kółko myszy | przy chwycie: bliżej, dalej |
| lewy przycisk myszy | przy chwycie: rzut |
| F | użycie (włącznik światła) |
| X | latarka |
| F1 do F4 | styl: łagodny (domyślny), wyraźny, surowy, bez efektów |
| F5, F9 | zapis, odczyt |
| F6 | język: polski / angielski |
| F10 | ekran deweloperski |
| F11 | okno / pełny ekran |
| Esc | uwolnienie myszy |

Zrzuty: `docs/build1/`, `docs/build2a/`, `docs/build2b/`.

## Układ repozytorium

- `game/` projekt Godota (`scripts/`, `scenes/`, `shaders/`, `data/`)
- `docs/` dziennik decyzji i materiały z buildów
- `assets_src/blender/` skrypty Blendera tworzące modele (`cialo.py` → `game/models/cialo_segmenty.glb`)
- `tools/` skrypty pomocnicze (`test.sh` uruchamia testy bez okna)

## Testy

```
tools/test.sh /sciezka/do/godot
```

Sprawdza: uspokojenie brył, bezwładność ruchu, sprint i wytrzymałość, kucanie, wychylanie, wspinanie na stół, pchanie, chwyt i niesienie, wleczenie ciężkiej skrzyni, drzwi na zawiasie, włącznik światła, stopy na podłodze, zginanie nóg w kucaniu, dłonie na trzymanym przedmiocie, opóźnienie latarki w dłoni, brak brył wylatujących z pokoju, zapis i odczyt, odrzucenie uszkodzonego zapisu, komplet tłumaczeń.
