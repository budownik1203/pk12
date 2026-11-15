# PSK-12 (Projekt Strefy Kwarantanny 12)

Pierwszoosobowy, fizyczny sandbox survivalowy w duchu Project Zomboid. Godot 4.7, fizyka Jolt, tylko PC.

## Jak uruchomić

1. Otwórz Godota 4.7 i wybierz **Importuj**, wskaż plik `game/project.godot`.
2. Wciśnij **F5**.

## Stan: build 12, broń palna

Koniec fundamentu (buildy 1–4). W pokoju: okno zabite trzema deskami, drzwi do komórki na zatrzasku z klamką, w szafce nakładka, zamek i wkręty, na stole klucz.

| Klawisz | Działanie |
| --- | --- |
| WASD, Shift, Ctrl, Q/E, Spacja | ruch, sprint, kucanie, wychylanie, skok i wspinanie |
| T | tryb chwytania: lewy przycisk przytrzymany chwyta rzecz pod kursorem (też drzwi za klamkę), puszczony puszcza, prawy rzuca, kółko odsuwa; T ponownie wyłącza |
| kółko (kliknięcie) | tryb walki: LPM cios, PPM przytrzymany garda, PPM + LPM odepchnięcie; ponowne kliknięcie wyłącza |
| Z | chwyt oburącz przedmiotu z prawej ręki (łom) i z powrotem; okienko „Oburącz” w ekwipunku |
| H | okno zdrowia (razem z ekwipunkiem): przeciągnij bandaż, plaster, szmatę, spirytus, igłę, szynę albo tabletki na część ciała; PPM na części zdejmuje opatrunek lub szynę |
| F8 / Shift+F8 | (dev) losowa rana / wyleczenie |
| F (zlew, materac) | zlew: z butelką w ręce napełnia, z pustymi rękami pijesz z kranu; materac w komórce: sen, gdy jesteś zmęczony (każdy klawisz budzi) |
| F7 / Shift+F7 | (dev) +1 godzina / zerowanie potrzeb |
| numpad + / − | (dev) zombie za oknem / usunięcie wszystkich zombie |
| numpad / | (dev) następny rodzaj pogody |
| C | okno postaci: zawód, cechy, umiejętności (poziomy 0–10 i postęp) |
| R (broń w prawej ręce) | przeładowanie: najpełniejszy magazynek z ekwipunku i zamek, w strzelbie naboje do rury po jednym; przy zacięciu przeładowanie zamka |
| F12 | nagrywanie sesji: klatki co pół sekundy do folderu `nagrania/` obok gry (z opisem każdej klatki w `klatki.txt`); log błędów silnika zapisuje się tam zawsze |
| F (drewno, ognisko, kuchenka) | z zapałkami lub zapalniczką w ręce na drewnie leżącym na dworze: ognisko (stos w promieniu metra); na ognisku z drewnem w ręce: dokładanie; na kuchence: włącz/wyłącz, Shift+F podnosi |
| F (drzwi domu, rama okna) | drzwi: klamka i pchnięcie, otwarte domyka; rama z odłamkami: wybicie resztek szkła |
| numpad 0 | paski i liczby postępu pracy (domyślnie wyłączone: postęp widać na gwoździach i wkrętach) |
| F | użycie: klamka i pchnięcie drzwi, zamek (z kluczem albo od środka), szafka, podniesienie przedmiotu |
| lewy / prawy przycisk | lewa / prawa ręka: każdy przycisk działa tym, co trzyma jego ręka; trzymany przy łomie i śrubokręcie przełącza mysz z kamery na narzędzie aż do puszczenia |
| G / Shift+G | upuść z prawej / lewej ręki |
| lewy przycisk | przyłożenie części trzymanej w ręce (deska, nakładka, zamek) |
| kółko przy pracy | wkręcanie i wykręcanie |
| O | podświetlenie miejsc pracy |
| Tab, 1–9, G, X | ekwipunek, skróty, upuszczenie z ręki, latarka |
| F1–F4, F5/F9, F6, F10, F11, Esc | styl, zapis/odczyt, język, dane, okno, mysz |

Praca narzędziem:

- **Łom** (podważanie 3, ramię 0,75 m): koniec deski albo szczelina drzwi przy zamku, ruch myszy w dół. Opór rośnie z liczbą gwoździ i z zamkiem.
- **Młotek** (wbijanie 3): gwoździe w jednej ręce, młotek w drugiej. Przytrzymaj przycisk ręki z gwoździami (gwóźdź przyłożony), klikaj przyciskiem ręki z młotkiem; między uderzeniami 0,45 s przerwy, 3 uderzenia na gwóźdź. Gwoździe ubywają z garści.
- **Śrubokręt** (wkręcanie 3): koła myszą zgodnie z ruchem wskazówek zegara wkręcają, przeciwnie wykręcają; 4 obroty na wkręt. Końcówka się zużywa; zużyta zrywa łby. Wykręcony otwór trzyma słabiej.
- **Moneta i nóż** (wkręcanie 1): trzy razy wolniej; nóż szybko się tępi.
- **Piła** (piłowanie 3): celuj w środek deski leżącej w świecie, prawy przycisk i ruchy myszy w dół. Deska rozpada się na dwie deszczułki (opał albo szyna).
- **Nóż, nożyczki** (cięcie): warzywo albo ubranie w lewej ręce, prawy przycisk i ruchy w dół. Warzywa kroją się do zupy, ubrania tną się na szmaty (zawartość kieszeni wraca do ekwipunku).

Broń palna (tryb walki, klik kółkiem): LPM strzał, PPM przytrzymany przyrządy celownicze (przybliżenie, mniejszy rozrzut), R przeładowanie. Magazynki ładuje się w ekwipunku: przeciągnij naboje na magazynek (albo na strzelbę), PPM na magazynku lub broni rozładowuje. Każdy strzał brudzi broń, a brud, zużycie i brak smaru grożą zacięciem. Czyszczenie: broń w lewej ręce, w prawej szmata (z grubsza), WD-40 (czyści i smaruje na 60 strzałów) albo wycior (do zera), PPM i ruchy w dół. Strzał słychać z daleka.

Gotowanie: patelnia albo garnek postawione na ognisku lub włączonej kuchence gotują zawartość. Ziemniak na patelni piecze się w 40 minut gry, zostawiony dłużej robi się spalenizną. Garnek ze zlewu z wodą i pokrojonymi warzywami daje zupę, którą je się porcjami (przeciągnij garnek na postać w oknie zdrowia, H).

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

Kontrola prawdziwego startu gry (z oknem, bez trybu testowego): ekran tworzenia postaci z kursorem, klikanie myszką w cechy i w „Rozpocznij”, zombie na ulicy po starcie, kursor przy ekwipunku, puszczanie trzymanych przycisków, nowa postać po śmierci:

```
godot --path game -s res://tests/start_check.gd
```

Ustawienia piaskownicy: `game/data/sandbox.json` (liczba zombie na start, szybkość, wytrzymałość, rodzaje ran, zakażenie, czas do śmierci po zakażeniu).
