# PSK-12 (Projekt Strefy Kwarantanny 12)

Pierwszoosobowy, fizyczny sandbox survivalowy w duchu Project Zomboid. Godot 4.7, fizyka Jolt, tylko PC.

## Jak uruchomić

1. Otwórz Godota 4.7 i wybierz **Importuj**, wskaż plik `game/project.godot`.
2. Wciśnij **F5**.

## Stan: build 1, pokój testowy

Sala z bryłami fizycznymi i ciemna komórka za ścianką. Służy do wyboru stylu graficznego i sprawdzenia fundamentów.

| Klawisz | Działanie |
| --- | --- |
| WASD, Shift, Spacja | ruch, sprint, skok |
| T | latarka |
| F1, F2, F3 | styl: łagodny, wyraźny, surowy |
| F4 | obraz bez efektów (do porównania) |
| F5, F9 | zapis, odczyt |
| F6 | język: polski / angielski |
| F10 | ekran deweloperski |
| F11 | okno / pełny ekran |
| Esc | uwolnienie myszy |

Zrzuty wariantów stylu: `docs/build1/`.

## Układ repozytorium

- `game/` projekt Godota (`scripts/`, `scenes/`, `shaders/`, `data/`)
- `docs/` dziennik decyzji i materiały z buildów
- `tools/` skrypty pomocnicze (`test.sh` uruchamia testy bez okna)

## Testy

```
tools/test.sh /sciezka/do/godot
```

Sprawdza: uspokojenie brył, pchanie skrzynki przez gracza, zapis i odczyt stanu, odrzucenie uszkodzonego zapisu, komplet tłumaczeń.
