# PSK-12 (Projekt Strefy Kwarantanny 12)

Pierwszoosobowy, fizyczny sandbox survivalowy w duchu Project Zomboid. Godot 4.7, fizyka Jolt, tylko PC.

## Jak uruchomić

1. Otwórz Godota 4.7 i wybierz **Importuj**, wskaż plik `game/project.godot`.
2. Wciśnij **F5**.

## Stan: build 3, ekwipunek

Pokój testowy z szafką, przedmiotami na stole, regale i podłodze. Ekwipunek w stylu Tarkova z wagą z Project Zomboid: sloty na ciele, siatki z kształtami tetrisowymi, plecak zmniejszający odczuwaną wagę, czas przekładania, przedmiot w ręce.

| Klawisz | Działanie |
| --- | --- |
| WASD, Shift, Ctrl, Q/E, Spacja | ruch, sprint, kucanie, wychylanie, skok i wspinanie |
| T | chwyt fizyczny (kółko: bliżej/dalej, lewy przycisk: rzut) |
| F | użycie: włącznik, otwarcie szafki, podniesienie przedmiotu do ekwipunku |
| Tab | ekwipunek |
| 1–9 | przedmiot z kamizelki lub pasu do ręki i z powrotem |
| G | upuszczenie przedmiotu z ręki |
| X | latarka |
| F1–F4, F5/F9, F6, F10, F11, Esc | styl, zapis/odczyt, język, dane, okno, mysz |

W oknie ekwipunku: przeciąganie lewym przyciskiem, R obraca, Ctrl przy chwycie bierze połowę stosu, dwuklik otwiera pojemnik (apteczka), klawisz 1–9 nad przedmiotem w kamizelce lub pasie przypisuje skrót, upuszczenie poza oknami wyrzuca na ziemię.

Zrzuty: `docs/build1/` do `docs/build3/`.

## Układ repozytorium

- `game/` projekt Godota (`scripts/`, `scenes/`, `shaders/`, `data/`); przedmioty i sloty w `game/data/items.json`, stan początkowy w `game/data/start.json`
- `docs/` dziennik decyzji i materiały z buildów
- `assets_src/blender/` skrypty Blendera tworzące modele (`cialo.py` → `game/models/cialo_segmenty.glb`)
- `tools/` skrypty pomocnicze (`test.sh` uruchamia testy bez okna)

## Testy

```
tools/test.sh /sciezka/do/godot
```

Sprawdza: uspokojenie brył, bezwładność ruchu, sprint i wytrzymałość, kucanie, wychylanie, wspinanie na stół, pchanie, chwyt i niesienie, wleczenie ciężkiej skrzyni, drzwi na zawiasie, włącznik światła, stopy na podłodze, zginanie nóg w kucaniu, dłonie na trzymanym przedmiocie, opóźnienie latarki w dłoni, kształty i obrót w siatce, podnoszenie, plecak i redukcja wagi, stosy, skróty 1–9, wyrzucanie, przeciąganie w oknie, zapis ekwipunku, brak brył wylatujących z pokoju, zapis i odczyt, odrzucenie uszkodzonego zapisu, komplet tłumaczeń.
