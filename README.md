# PSK-12 (Projekt Strefy Kwarantanny 12)

Pierwszoosobowy, fizyczny sandbox survivalowy w duchu Project Zomboid. Godot 4.7, fizyka Jolt, tylko PC.

## Jak uruchomić

1. Otwórz Godota 4.7 i wybierz **Importuj**, wskaż plik `game/project.godot`.
2. Wciśnij **F5**.

## Stan: build 4, narzędzia i montaż

Koniec fundamentu (buildy 1–4). W pokoju: okno zabite trzema deskami, drzwi do komórki na zatrzasku z klamką, w szafce nakładka, zamek i wkręty, na stole klucz.

| Klawisz | Działanie |
| --- | --- |
| WASD, Shift, Ctrl, Q/E, Spacja | ruch, sprint, kucanie, wychylanie, skok i wspinanie |
| T | chwyt fizyczny; na drzwiach z zatrzaskiem: chwyć i pociągnij wzrok w dół, by nacisnąć klamkę |
| F | użycie: klamka i pchnięcie drzwi, zamek (z kluczem albo od środka), szafka, podniesienie przedmiotu |
| prawy przycisk (trzymany) | praca narzędziem: mysz prowadzi narzędzie zamiast kamery |
| lewy przycisk | przyłożenie części trzymanej w ręce (deska, nakładka, zamek) |
| kółko przy pracy | wkręcanie i wykręcanie |
| O | podświetlenie miejsc pracy |
| Tab, 1–9, G, X | ekwipunek, skróty, upuszczenie z ręki, latarka |
| F1–F4, F5/F9, F6, F10, F11, Esc | styl, zapis/odczyt, język, dane, okno, mysz |

Praca narzędziem:

- **Łom** (podważanie 3, ramię 0,75 m): koniec deski albo szczelina drzwi przy zamku, ruch myszy w dół. Opór rośnie z liczbą gwoździ i z zamkiem.
- **Młotek** (wbijanie 3): zamach myszą w górę i uderzenie w dół, 3 uderzenia na gwóźdź. Za mocny zamach wygina gwóźdź; wyciąga się go pazurem młotka albo łomem.
- **Śrubokręt** (wkręcanie 3): koła myszą zgodnie z ruchem wskazówek zegara wkręcają, przeciwnie wykręcają; 4 obroty na wkręt. Końcówka się zużywa; zużyta zrywa łby. Wykręcony otwór trzyma słabiej.
- **Moneta i nóż** (wkręcanie 1): trzy razy wolniej; nóż szybko się tępi.

Zrzuty: `docs/build1/` do `docs/build4/`.

## Układ repozytorium

- `game/` projekt Godota (`scripts/`, `scenes/`, `shaders/`, `data/`); przedmioty i sloty w `game/data/items.json`, stan początkowy w `game/data/start.json`
- `docs/` dziennik decyzji i materiały z buildów
- `assets_src/blender/` skrypty Blendera tworzące modele (`cialo.py` → `game/models/cialo_segmenty.glb`)
- `tools/` skrypty pomocnicze (`test.sh` uruchamia testy bez okna)

## Testy

```
tools/test.sh /sciezka/do/godot
```

Sprawdza: uspokojenie brył, bezwładność ruchu, sprint i wytrzymałość, kucanie, wychylanie, wspinanie na stół, pchanie, chwyt i niesienie, wleczenie ciężkiej skrzyni, drzwi na zawiasie, włącznik światła, stopy na podłodze, zginanie nóg w kucaniu, dłonie na trzymanym przedmiocie, opóźnienie latarki w dłoni, kształty i obrót w siatce, podnoszenie, plecak i redukcja wagi, stosy, skróty 1–9, wyrzucanie, przeciąganie w oknie, zapis ekwipunku, zrywanie i przybijanie desek, wygięte gwoździe, klamka i zatrzask, nakładka i zamek na wkręty, klucz, wykręcanie i słabe otwory, zużycie końcówki, moneta, wyważanie zamkniętych drzwi, hałas, brak brył wylatujących z pokoju, zapis i odczyt, odrzucenie uszkodzonego zapisu, komplet tłumaczeń.
