# Dziennik decyzji

Źródłem prawdy o projekcie są cztery dokumenty (Claude Docs) i to repozytorium. Ten plik zbiera decyzje techniczne podjęte w trakcie buildów; decyzje projektowe są w dokumencie projektu gry.

- Projekt gry (GDD): https://claude.ai/artifact/TzCza4fgQ1AynxayzfoNAP
- Ustalenia techniczne: https://claude.ai/artifact/K4EfyNCC9ykBgwp7tDTJtS
- Plan buildów: https://claude.ai/artifact/VM2fXG6nDnkeMJkxiHGhYu
- Pytania, runda 1: https://claude.ai/artifact/58bHB7GKajz5ZUHVezDtZb

## 2026-11-14, build 1

- **Nazwa:** PSK-12 (Projekt Strefy Kwarantanny 12). Repozytorium `budownik1203/pk12`.
- **Silnik:** Godot 4.7.2, renderer Forward+, fizyka Jolt, GDScript. Tylko PC, klawiatura i mysz.
- **Sprzęt docelowy:** GTX 1660 Super, Ryzen 7 5800X, 16 GB RAM, Full HD. Cel: 60 klatek na sekundę.
- **Render świata:** osobny SubViewport w obniżonej rozdzielczości, powiększany bez wygładzania; shader `retro_post` (kwantyzacja kolorów z ditheringiem, ziarno, winieta). Interfejs rysowany osobno w pełnej rozdzielczości.
- **Styl:** trzy warianty do wyboru przez testera (F1 do F3). Decyzja otwarta.
- **Sceny budowane w kodzie:** pokój testowy powstaje w `room_builder.gd`, nie w edytorze. Pliki są małe i czytelne w historii zmian.
- **Bez autoloadów i `class_name`:** skrypty łączą się przez `preload`, dzięki czemu projekt działa od razu po sklonowaniu i w testach bez okna.
- **Sterowanie:** akcje rejestrowane w `controls.gd`. Układ: WASD, Shift sprint, Ctrl kucanie, Q/E wychylanie, F interakcja, Tab ekwipunek, H zdrowie, R obrót przedmiotu, lewy i prawy przycisk myszy to lewa i prawa ręka (build 4.1).
- **Zapis:** JSON z numerem wersji (`save_game.gd`). Uszkodzony plik lub inna wersja są odrzucane bez zmiany stanu gry.
- **Języki:** `data/lang/pl.json` i `en.json`; w kodzie tylko klucze i `tr()`.
- **Tekstury zastępcze:** generowane w kodzie, 64 piksele, bez filtrowania.
- **Testy bez okna:** `-- --test-zapisu`; zrzuty ekranu: `-- --zrzuty=<folder>`.

### Sprawdzone po stronie Claude

- Godot 4.7.2 uruchamia się bez okna: import projektu i testy działają.
- Zrzuty ekranu działają przez wirtualny ekran z rendererem zgodności (OpenGL, programowo). Obraz może się nieznacznie różnić od Forward+ na karcie graficznej; liczba klatek z tych zrzutów nic nie mówi o wydajności.
- Blender jako moduł Pythona (`bpy` 5.3) jest dostępny do pobrania; instalacja i eksport glTF do sprawdzenia w buildzie 2.

## 2026-11-14, build 2a

- **Styl:** wybrany łagodny (render świata 960 × 540, 48 poziomów koloru, lekkie ziarno). Pozostałe warianty zostają pod F2 do F4 do porównań.
- **Chwyt pod T:** celownik zamienia się w dłoń nad każdą bryłą, którą da się chwycić. Bryła jest ciągnięta siłą przyłożoną w punkcie chwytu, więc ciężkie rzeczy się wlecze, lekkie unosi, a drzwi na zawiasie otwierają się po łuku. Limity: 420 N w poziomie, 260 N w pionie (unosi około 26 kg). Chwyt zrywa się, gdy punkt chwytu odjedzie dalej niż 2,6 m od oczu.
- **Użycie pod F:** obiekty z własną funkcją (na razie włącznik światła).
- **Latarka przeniesiona na X**, bo T zajął chwyt.
- **Masa trzymanego przedmiotu spowalnia postać:** do 5 kg bez zmian, przy 80 kg 30% prędkości; powyżej 20 kg brak sprintu.
- **Ruch:** rozpędzanie 6,5 m/s², hamowanie 8,5 m/s², chód 2,4 m/s, sprint 4,6 m/s, kucanie 1,2 m/s. Wytrzymałość 100, sprint 9 na sekundę, regeneracja 7 na sekundę po 1 s przerwy.
- **Wspinanie:** przeszkody od 0,35 do 1,35 m, gdy nad krawędzią jest miejsce przynajmniej na kucającą postać.
- **Teleport postaci wyłącza jej zderzenia na dwie klatki.** Bez tego silnik fizyki traktował przeniesienie (np. przy wczytaniu zapisu) jak ruch z ogromną prędkością i wystrzeliwał stykające się bryły poza świat.
- **Drzwi:** bryła 22 kg na zawiasie, zakres ±100°, na razie bez klamki i zamka (wchodzą w buildzie 4).

## 2026-11-14, build 2b

- **Model pracy:** od tego buildu prace prowadzi Claude Opus 5.5 (wcześniej Fable 5.2); ciągłość zapewniają te dokumenty i repozytorium.
- **Blender działa po stronie Claude** jako moduł Pythona (`bpy` 5.3). Modele powstają ze skryptów w `assets_src/blender/` i są eksportowane do glTF (`game/models/`). Pierwszy model: segmenty ciała postaci.
- **Ciało z segmentów zamiast skórowanego modelu z gotowymi animacjami.** Osobne bryły na stawach pasują do stylu PS1/PS2 i nie wymagają animacji z zewnątrz. Nogi i ręce ustawia odwrotna kinematyka dwóch kości (`body.gd`), krok jest proceduralny i zależy od prędkości. Do skórowanego modelu z klipami można wrócić później, jeśli segmenty nie wystarczą.
- **Proporcje:** biodro na 0,95 m, udo i podudzie po 0,44 m, ramię 0,31 m, przedramię 0,29 m, dłoń 0,07 m do środka. Ciało jest 0,17 m za kamerą, stopy 0,07 m przed środkiem postaci, żeby patrząc w dół widzieć tors i buty. Głowa rzuca tylko cień.
- **Dłonie z własną fizyką:** cel dłoni wynika z kamery, dłoń goni go na sprężynie. Latarka w lewej dłoni zostaje w tyle przy obrocie (około 20° przy gwałtownym obrocie o 60°) i dogania kamerę w ułamku sekundy. Luźne ręce bujają się przeciwnie do nóg.
- **Trzymanie w zasięgu rąk:** chwycony przedmiot przyciągany jest na 0,6 m od oczu, kółkiem 0,4–0,75 m (wcześniej do 2 m, poza zasięgiem rąk). Przedmioty od 8 kg trzyma się obiema rękami, rozstawionymi o 0,16 m na boki od punktu chwytu; wtedy latarka przypina się do piersi.
- **Ograniczenie:** przy wleczeniu przedmiotu, którego nie da się unieść, ręka nie sięga do podłogi, bo tułów się jeszcze nie pochyla. Pochylanie tułowia: do zrobienia przy okazji walki wręcz albo podnoszenia z ziemi.

## 2026-11-14, build 3

- **Przedmioty i sloty w danych:** `game/data/items.json` (masa, kształt, materiał, kategoria, siatki pojemnika, redukcja wagi, czas sięgania, stos, ciecz, model zastępczy), stan początkowy w `game/data/start.json`. Kod nie zna żadnego przedmiotu z nazwy.
- **Siatki:** kształty dowolne (tetrisowe), obrót o 90° klawiszem R. Pojemniki zagnieżdżone (apteczka w plecaku), pojemnik nie wejdzie do siebie. Pusty plecak zajmuje 3 × 2 zamiast 3 × 4; włożenie czegoś do pustego plecaka leżącego w innej siatce wymaga miejsca na rozłożenie.
- **Sloty:** głowa, twarz, kurtka, kamizelka, plecak, pas, spodnie, rękawice, buty, na plecach (długie przedmioty), w ręce. Na starcie: spodnie (2 kieszenie 1 × 2) i kurtka (2 kieszenie 2 × 2). Kamizelka i pas to sloty szybkiego dostępu (skróty 1–9).
- **Waga:** masa niesiona i odczuwana; założony pojemnik zmniejsza wagę zawartości o swój procent (plecak 35%, kamizelka 10%). Limit miękki: do 18 kg odczuwanych bez kar, potem spadek prędkości do 45% przy 45 kg i szybsze zużycie wytrzymałości.
- **Czas:** każde przełożenie trwa (sięgnięcie do źródła + do celu + 0,04 s/kg); zakładanie odzieży i pojemników 2 s. Czynności idą po kolei w kolejce, cel jest rezerwowany od razu, gra się nie zatrzymuje. Podnoszenie przerywa się po odejściu dalej niż 3 m.
- **Świat:** przedmiot wyjęty z ekwipunku staje się bryłą fizyczną z tym samym stanem; F podnosi do pierwszego wolnego miejsca, a gdy brak miejsca, do ręki. Podniesiony plecak, kamizelka czy pas od razu się zakłada, jeśli slot jest wolny. Szafka to pojemnik świata (siatka 6 × 4) otwierany pod F.
- **Przedmiot w ręce:** widoczny w prawej dłoni z tym samym opóźnieniem co latarka; chwyt pod T wymaga wolnej ręki.
- **Zapis:** wersja formatu 2 (ekwipunek i przedmioty w świecie). Zapisy z buildów 1–2 są odrzucane jako zapis z innej wersji.
- **Grzechotanie:** na razie tylko licznik luźnych metalowych przedmiotów na ekranie deweloperskim; dźwięk i wpływ na zombie dojdą z systemem hałasu.
- **Przemoczenie:** pole w danych przedmiotu, bez działania do czasu pogody (build 8).
- **Naprawiony wyciek pamięci:** odwołania z siatki do właściciela i z przedmiotu do siatki są słabe, bez cyklu.

## 2026-11-14, build 4

- **Zdolności narzędzi w danych:** pole `abilities` w `items.json` (łom: podważanie 3; młotek: wbijanie 3, podważanie 1; śrubokręt: wkręcanie 3; moneta i nóż: wkręcanie 1, nóż także podważanie 1), `length` jako ramię dźwigni, `wear` jako zużycie końcówki na obrót. Obiekty pytają o zdolność i poziom, nie o konkretny przedmiot.
- **Punkty pracy** (`scripts/work/`): miejsca w świecie z rodzajem pracy (dźwignia, kręcenie, uderzenie, przyłożenie). Wybierany jest punkt najbliżej linii wzroku w zasięgu 1,7 m, niezasłonięty. Właściciel punktu (okno, drzwi) decyduje o skutku.
- **Dwie ręce (build 4.1):** sloty `w_lewej` i `w_reku`, przyciski myszy odpowiadają rękom. Wbijanie: przytrzymany przycisk ręki z gwoździami przykłada gwóźdź, kliknięcia ręki z młotkiem uderzają co najmniej co 0,45 s, bez oceny jakości i bez wyginania. Mysz zostaje przy narzędziu, dopóki przycisk jest trzymany, także po skończonej pracy (kamera nie ucieka).
- **Mysz prowadzi narzędzie:** trzymany przycisk ręki z narzędziem przełącza mysz z kamery na narzędzie. Dźwignia: 0,005 postępu na piksel ruchu w dół przy poziomie 3 i ramieniu 0,6 m. Kręcenie: kąt wirtualnego kursora wokół środka (zgodnie z ruchem wskazówek zegara wkręca) albo kółko (1/12 obrotu na ząbek). (Zamach myszą z buildu 4 zastąpiony klikaniem w 4.1.)
- **Okno:** 3 deski po 2 gwoździe na każdym końcu. Opór końca: 1 + 0,8 na każdy wbity gwóźdź (z łomem około 440 px dla 2 gwoździ). Odzysk gwoździ 50%. Deska trzyma, gdy na obu końcach jest przynajmniej jeden wbity gwóźdź.
- **Drzwi:** zamknięte drzwi trzymają się na zatrzasku (bryła zamrożona) i same zaskakują po domknięciu. Klamkę naciska F albo chwyt i pochylenie wzroku o 10° w dół. Zamek działa przy 2 wkrętach zamka i 1 wkręcie nakładki dokręconych co najmniej do połowy. Zamyka się kluczem o pasującym `key_id` albo od środka komórki.
- **Wkręty:** 4 obroty na wkręt. Wykręcenie osłabia otwór (granica dokręcenia 1 / (1 + 0,35 × liczba wykręceń)). Zużyta końcówka (stan poniżej 30%) zrywa łeb z szansą 8% na obrót.
- **Wyważanie:** zatrzask 1,2; drzwi zamknięte na klucz: 2 + 0,6 × suma dokręcenia wkrętów (pełny zamek około 5,4, z łomem około 880 px). Wyłamany zamek i nakładka spadają na ziemię jako uszkodzone przedmioty (stan 30%).
- **Hałas** (`noise.gd`): zdarzenia z miejscem i głośnością (wkręcanie 15, klamka 25, podważanie 55–60, młotek 70, wyważenie 85). Na razie widać je na ekranie deweloperskim; zombie usłyszą je od buildu 7.
- **Okno w ścianie południowej** z kawałkiem gruntu i niewidzialnymi granicami za nim.
- **Zapis:** wersja 3 (okno i drzwi). Starsze zapisy są odrzucane.
- **Odłożone:** blokowanie czynności przez brak umiejętności (build 9), klinowanie drzwi, osobne modele narzędzi (na razie bryły zastępcze), dźwięk.


## Build 4.2 (14.11.2026): poprawki po testach

- **Styl PS1 w geometrii, bez szumu:** usunięte animowane ziarno. Wszystkie materiały standardowe są w locie zamieniane na shader PS1 (`scripts/psx.gd`): wierzchołki przyciągane do siatki pikseli (drgania przy ruchu), tekstury bez korekcji perspektywy (affine), duże pudełka dzielone co 0,75 m. Post-process: kolor 15-bitowy (32 poziomy) z nieruchomym ditheringiem Bayera 4×4 z PS1 i lekką winietą. Style: F1 Łagodny PS1 (domyślny, 2× mniej pikseli, snap 1,5, affine 0,35), F2 Klasyczny PS1 (426×240 przy 720p, affine 0,8), F3 Surowy, F4 bez efektów.
- **Dźwięk syntetyzowany** (`scripts/sound.gd`): 18 dźwięków po 3 warianty, 22 kHz, generowane przy starcie. Każde zdarzenie hałasu ma dźwięk; do tego kroki (zależne od kucania, biegu i obciążenia), lądowanie, uderzenia brył o otoczenie (zmiana prędkości ponad 1,3 m/s; drewno lub metal), podniesienie, rzut, przekładanie w ekwipunku, włącznik. Dźwięki zakończenia: dobity gwóźdź „tiiing”, dokręcony wkręt „klik”.
- **Kolory znaczników:** czerwony demontaż (podważanie, wyciąganie gwoździ, dokręcony wkręt do wykręcenia), żółty dołożenie części, niebieski montaż (wbijanie, wkręcanie). Właściciel punktu może nadpisać kolor przez `work_category`.
- **Postęp na przedmiocie zamiast pasków:** gwoździe wystają coraz mniej z każdym uderzeniem (wygięty sterczy krzywo), wkręty chowają się z każdym obrotem, a nacięcie łba obraca się. Paski i liczby pod numpadem 0, domyślnie wyłączone.
- **Młotek:** model z Blendera (trzonek, obuch, pazur), w dłoni trzonek pionowo (`"grip": "up"`). Zamach przód-tył: młotek czeka przechylony do tyłu, kliknięcie przerzuca go do przodu w 0,09 s i dopiero wtedy liczy się uderzenie (z dźwiękiem), potem wraca. Zasięg pracy zależy od rodzaju: wbijanie 0,95 m, wkręcanie 1 m, dźwignia 1,3 m, przykładanie 1,7 m.
- **Duże przedmioty oburącz:** pole `bulky` w items.json (deska: 0,6 sztuki na punkt siły). Nie wchodzą do siatek, zajmują obie ręce, kolejne podniesione sztuki dokładają się do stosu do limitu `siła × per_strength` (siła 5: 3 deski). Przyłożenie zabiera jedną sztukę, upuszczenie zrzuca stos jako osobne deski. Siła na razie stała (5), cechy postaci w buildzie 9.
- **Tryb chwytania (T):** przełącznik zamiast pojedynczego chwytu; lewy przycisk przytrzymany trzyma, puszczony puszcza, prawy rzuca. Rzut przez środek masy z lekkim obrotem (wcześniej siła w punkcie chwytu rozkręcała przedmioty).
- **Postać:** nowe segmenty z Blendera (sylwetka V, kurtka z kołnierzem, pas, dżinsy, buty robocze z podeszwą, dłonie z palcami). Stopy stawiane pionowo pod biodrami (wcześniej wysunięte przed tułów, przez co postać wyglądała na przygarbioną).
- **Modele przedmiotów** (`assets_src/blender/przedmioty.py` → `game/models/przedmioty.glb`): młotek, łom z hakiem, śrubokręt, nóż, wiązka gwoździ, pudełko wkrętów, deska ze sfazowanymi krawędziami, nakładka, zamek, klucz. Bryły kolizji bez zmian (`model.size`).
