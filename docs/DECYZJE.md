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


## Build 4.3 (15.11.2026): drzwi, walka, chwyt oburącz

- **Drzwi:** otwierają się tylko do pokoju (limit zawiasu od -105° do 0°), opierają się o ościeżnicę. 34 kg, tłumienie obrotu 4. Zaskakują, gdy kąt spadnie poniżej 0,08 rad i skrzydło jedzie w stronę framugi (także trzymane w ręce; chwyt wtedy puszcza) albo stoi. Klamka otwiera zawsze do pokoju.
- **Trzy tryby rąk:** praca (domyślny, LPM/PPM to ręce), chwytanie (T), walka (kliknięcie kółkiem, 0,3 s na przełożenie chwytu). W walce: LPM cios, PPM garda (3 wytrzymałości/s), PPM+LPM odepchnięcie (15 wytrzymałości, co 0,8 s). Profile w items.json, pole `combat` (obrażenia, zamach, powrót, zasięg, garda, wytrzymałość, siła), pięści w `fists`. Trafienie liczy się w 20% powrotu (gdy narzędzie przechodzi przez cel); trzy promienie na łuku zamachu.
- **Chwyt oburącz:** slot `oburacz` między rękami; przyjmuje przedmioty z `two_hand: true` (łom) i duże (`bulky`, deski). Zajmuje obie ręce, w kodzie liczy się jako prawa ręka. Klawisz Z przekłada. Oburącz: cios ×1,35, zamach ×1,15 wolniej, garda ×1,3, pchnięcie ×1,3, dźwignia przy podważaniu ×1,3.
- **Worek treningowy** (40 kg, 500 punktów życia) w pokoju do prób ciosów; zombie od buildu 7.


## Build 5 (15.11.2026): zdrowie i rany

- **17 segmentów** (`scripts/health/health.gd`): głowa, szyja, klatka, brzuch, miednica, ramiona, przedramiona, dłonie, uda, łydki, stopy. Stan segmentu = 100 minus obrażenia jego ran (gojenie je zmniejsza). Zdrowie ogólne liczone z segmentów z wagami (głowa 2,5, szyja i klatka 2), utraty krwi i zakażenia.
- **Rany:** zadrapanie, rana cięta, głęboka rana, ugryzienie, stłuczenie, złamanie. Każda ma obrażenia, krwawienie (% krwi/s), krzepnięcie (zadrapanie po 45 s, rana cięta po 220 s, głęboka nie krzepnie), ból i czas gojenia. Czasy są przyspieszone (minuty), do przeskalowania, gdy dojdzie zegar doby.
- **Krew:** 100%, odnawia się 0,015%/s bez krwawienia. Poniżej 55% brak sprintu i obraz ciemnieje, poniżej 38% śmierć.
- **Opatrywanie przeciąganiem** w oknie zdrowia (H, wewnątrz ekwipunku): bandaż i szmata tamują 90% krwawienia, plaster tylko zadrapania, spirytus dezynfekuje (piecze, ma dawki), igła z nicią zszywa głęboką ranę (bez szwów głęboka rana goi się 4× wolniej), szyna usztywnia złamanie (bez szyny zrasta się ponad 3× wolniej), tabletki uśmierzają ból na 4 minuty. Czynność trwa (1,5–6 s), ranne ręce wydłużają ją. PPM zdejmuje opatrunek (bandaż wraca jako brudny) lub szynę.
- **Zakażenie:** rośnie w ranie niezdezynfekowanej bez opatrunku, pod brudnym opatrunkiem (brud ponad 50%) i pod szmatą; dezynfekcja je cofa. Ponad 30% wstrzymuje gojenie, podnosi ból i obniża zdrowie. Zakażenie zombie (ustawienie piaskownicy) dojdzie z zombie.
- **Ochrona ubrań:** pole `protection` w items.json (segmenty oraz ochrona przed cięciem, ugryzieniem i uderzeniem). Cięcie i ugryzienie mają szansę nie przebić, uderzenie słabnie. Ubranie przy tym się niszczy i nasiąka krwią z krwawiących ran pod nim. Kurtka, spodnie i kamizelka taktyczna mają ochronę.
- **Skutki:** złamana noga 0,5 prędkości (z szyną 0,8) i bez sprintu, głęboka rana nogi 0,85; ranne ręce słabiej biją, wolniej podważają i wbijają; ból spowalnia odnawianie wytrzymałości i przy dużym bólu obraz drży; utrata krwi odbarwia i przyciemnia obraz.
- **Źródła ran w tym buildzie:** upadek (od 6,5 m/s stłuczenia, od 9,5 m/s możliwe złamanie łydek) i pięść w ścianę (stłuczenie dłoni). Zombie od buildu 7.
- **Widok:** stany jak w PZ w prawym górnym rogu (krwawienie, utrata krwi, ból, złamanie, zakażenie), pasek zdrowia ukryty przy pełnym zdrowiu. Opatrunki i szyny widać na kończynach postaci. Śmierć: ekran z F9 (wczytaj) albo Enter (nowy ocalały). Zapis wersji 4 zawiera zdrowie.


## Build 6 (15.11.2026): czas i potrzeby

- **Zegar doby** (`scripts/world/clock.gd`): doba gry = godzina prawdziwego czasu (domyślne tempo PZ), start dzień 1, 8:00. Słońce (światło kierunkowe z cieniami) wschodzi o 6, zachodzi o 20 i świeci od południa, czyli przez okno pokoju; tło za oknem, światło otoczenia i mgła zmieniają się z porą dnia. Na zewnątrz jesień: 4–15 °C, najcieplej około 15:00. Zegar w prawym górnym rogu.
- **Potrzeby** (`scripts/health/needs.gd`, 0–100): głód +4/h, pragnienie +6/h, zmęczenie +5/h gry, szybciej przy wysiłku (sprint, walka, praca), pragnienie też przy przegrzaniu. Od 60 i 85 słabsze odnawianie wytrzymałości; od 85 głodu lub pragnienia, przy wychłodzeniu, przegrzaniu i zatruciu rosną obrażenia od potrzeb, które odejmują się od zdrowia ogólnego i odrabiają się, gdy wszystko jest w normie.
- **Temperatura ciała:** otoczenie z zegara, w pokoju +7 °C, minus 1,5 °C za każde brakujące zabezpieczenie okna (nieszczelne okno ciągnie zimnem). Ubrania mają pole `insulation` (kurtka 0,35, spodnie 0,2, kamizelka 0,08, plecak 0,04); odczuwana = otoczenie + izolacja × 10 + wysiłek × 6. Komfort 18–29 °C odczuwanej, poza nim ciało powoli traci lub zyskuje ciepło.
- **Jedzenie i picie przeciąganiem na postać** w oknie zdrowia (jak opatrunki): pole `food` (głód, pragnienie, porcje, czerstwienie i psucie w dniach gry, pusty pojemnik po zjedzeniu). Zepsute jedzenie syci słabiej i zatruwa. Picie po 0,25 l z pojemnika z wodą.
- **Otwieranie puszki w dłoni** (`scripts/work/hand_work.gd`): zamknięta puszka w lewej ręce, narzędzie ze zdolnością `otwieranie` w prawej, prawy przycisk i kręcenie myszą (1,5 obrotu). Otwieracz 3, nóż 2 (tępi się), łom i śrubokręt 1 (część się wylewa). Punkt pracy w dłoni pojawia się, gdy nie celujesz w żaden punkt w świecie.
- **Zlew z kranem** (pierwsze lokalne źródło wody): F z pojemnikiem w ręce napełnia go, z pustymi rękami pijesz z kranu. Odcięcie wody przyjdzie razem z budynkami i siecią.
- **Sen:** materac w komórce, F przy zmęczeniu od 20. Ekran gaśnie, czas biegnie 90 razy szybciej (8 h w około 13 s), zmęczenie spada 14/h; budzi każdy klawisz, niskie zmęczenie, silny ból, skrajny głód lub pragnienie. Nie zaśniesz, krwawiąc.
- **Nowe przedmioty:** otwarta i pusta puszka, chleb, jabłko, baton, otwieracz. Na stole jedzenie i otwieracz. Zapis w wersji 5 zawiera zegar i potrzeby.


## Build 7 (15.11.2026): zombie

- **Zombie** (`scripts/zombie/`): CharacterBody z kapsułą, ciało z segmentów gracza (widoczna głowa, szczęka, losowe ubrania), pozy liczone w kodzie: powłóczysty chód z pochylonym tułowiem, ręce wyciągnięte w pościgu, zamach, zatoczenie, leżenie.
- **Zmysły:** wzrok w stożku 120° z linią wzroku; zasięg 3–15 m zależnie od światła przy graczu (zapalona lampa, światło dzienne przy oknie, latarka), kucanie i patrzenie przez okno zmniejszają go. Słuch z każdego zdarzenia hałasu: promień = głośność × 0,25 m, przez ścianę × 0,6. Kroki są hałasem (bieg 20, chód 7, kucanie cisza).
- **Stany:** snucie się, sprawdzanie hałasu, pościg (pamięta gracza 5 s po utracie z oczu), atak (zamach 0,55 s, trafia, jeśli gracz dalej jest w zasięgu 1,35 m i przed nim; odstęp 1,3 s), okno, drzwi, zatoczenie, leżenie (2,6 s), zwłoki.
- **Nawigacja:** siatka pieczona przy starcie z brył statycznych (pokój z komórką i grunt za oknem). Strefy łączy tylko okno: zombie idzie do okna, wyrywa deski (koniec deski puszcza po 2 s plus 6 s za każdy wbity gwóźdź) i przełazi przez parapet, gdy w otworze nie ma żadnej deski. Zatrzaśnięte drzwi do komórki wyłamuje po 8 s walenia, zamknięte na zamek po 14 s plus czas zależny od tego, jak mocno trzymają nakładka i zamek. Luźne przedmioty przepycha.
- **Walka z zombie:** 100 punktów życia (piaskownica). Cios w głowę ×2,5, w leżącego ×1,6; mocny cios (oburącz albo ponad 25) zatacza. Odepchnięcie przewraca (65%). Garda gracza przodem do zombie: koszt 12 wytrzymałości, szansa zablokowania = garda broni + 25%; zablokowany zombie się zatacza.
- **Rany od zombie:** losowa część ciała (najczęściej przedramiona i ramiona, rzadko nogi), rodzaj wg piaskownicy (zadrapanie 50, rana cięta 30, ugryzienie 20). Ubranie może zatrzymać ranę. Czerwony błysk przy trafieniu.
- **Zakażenie:** szansa wg piaskownicy (jak w PZ: zadrapanie 7%, rana cięta 25%, ugryzienie 100%). Bez objawów przez 35% czasu, potem mdłości, gorączka i agonia z rosnącym bólem i spadkiem zdrowia; po `knox_hours` (48 h gry) śmierć. Lekarstwa brak.
- **Piaskownica** w `data/sandbox.json`. Na start 2 zombie na gruncie za oknem. Zapis wersji 6 zawiera zombie i liczbę zabitych. Dźwięki: jęk, warknięcie, uderzenie w ciało, upadek, walenie w drzwi.


## Build 8 (15.11.2026): pogoda

- **Rodzaje** (`scripts/world/weather.gd`): pogodnie, pochmurno, deszcz, burza, mgła, każdy z zachmurzeniem, deszczem, mgłą, wiatrem i zmianą temperatury (deszcz −3 °C, burza −4 °C). Co 2–6 godzin gry losowany jest następny rodzaj z tabeli przejść (z deszczu łatwo o burzę, z burzy wraca deszcz albo zachmurzenie); parametry dochodzą do nowych wartości w około pół godziny gry.
- **Światło i niebo:** chmury zabierają do 55% światła dziennego, niebo szarzeje, mgła zagęszcza mgłę otoczenia. Burza: grzmot co 12–40 s z błyskiem rozświetlającym niebo i ściany.
- **Deszcz:** krople nad gruntem za oknem, widoczne przez okno. Zapętlony szum deszczu: na dworze pełny, przy oknie wyraźny, w głębi pokoju stłumiony.
- **Przemakanie:** na dworze w deszczu założone rzeczy mokną (pole `waterproof` zmniejsza: plecak 0,6, kurtka 0,35, kamizelka 0,2, spodnie 0,1); plecak przepuszcza 15% do zawartości. W środku schną, szybciej przy wysiłku. Mokre ubranie traci do 70% izolacji. Stany „Mokro” i „Przemoczony”. Wiatr wychładza na dworze (do −3 °C odczuwanej).
- **Deszczówka:** stojący pionowo na dworze pojemnik z polem `liquid_capacity` łapie do 0,4 l na godzinę gry w pełnym deszczu (pusta puszka ma teraz 0,4 l pojemności, butelka 1 l). Wodę pije się jak z butelki.
- **Zombie:** deszcz zmniejsza promień słyszenia do 65%, deszcz i mgła skracają zasięg wzroku (mgła do połowy).
- Zegar pokazuje pogodę i temperaturę na zewnątrz. Zapis w wersji 7 zawiera pogodę.
- **Ograniczenie:** za oknem jest tylko kawałek gruntu; dalszy świat (budynki, miasto) przyjdzie w buildzie świata.


## Build 9 (15.11.2026): postać

- **Tworzenie postaci** przed startem i po śmierci (nowy ocalały): imię, zawód, cechy z bilansem punktów jak w PZ (zawód daje lub zabiera punkty, dobre cechy kosztują, złe dają; start możliwy przy bilansie ≥ 0; cechy wykluczające się nie wejdą razem). Świat stoi na pauzie do kliknięcia „Rozpocznij”. Dane w `data/character.json`.
- **Umiejętności 0–10** (`scripts/character/character.gd`) rosną od używania; próg poziomu 40 × (poziom + 1)^1,35 punktów, siła i kondycja zaczynają od 5 i rosną prawie 3 razy wolniej:
  - stolarstwo: wbijanie (+7% siły uderzenia na poziom), przykładanie i zrywanie desek, odzysk gwoździ (+4% na poziom);
  - majsterkowanie: szybsze kręcenie (+6% na poziom), montaż zamka wymaga poziomu 1;
  - pierwsza pomoc: opatrywanie krótsze o 6% na poziom, zszywanie wymaga poziomu 2;
  - broń tępa i ostra (pole `type` w profilu walki): +5% obrażeń i −4% wytrzymałości na poziom;
  - siła: udźwig desek, siła ciosu, dźwignia przy podważaniu; rośnie od podważania, ciosów i noszenia ciężaru;
  - kondycja: zużycie i odnawianie wytrzymałości; rośnie od biegu;
  - skradanie: kroki cichsze o 6% na poziom, trudniej zauważyć; rośnie od kucania, szybciej przy zombie.
- **Zawody:** bezrobotny (+8 pkt), cieśla, mechanik, ratownik medyczny (−2), policjant (−2), robotnik budowlany.
- **Cechy** jako mnożniki dla systemów: silny, słabowity, wysportowany, otyły, szybki i wolny uczeń, cichy krok, niezdarny (głośniej i wolniejsza praca), szybkie gojenie, hemofilik (krwawienie ×1,6), odporny, chorowity (zakażenia ran), mały apetyt, żarłoczny, śpioch.
- **Książki** (pole `book`): czytanie przeciągnięciem na postać w oknie zdrowia, 12 s, tylko w świetle; potem nauka danej umiejętności ×2,5 do poziomu 4. Trzy książki leżą na stole.
- **Okno postaci (C)** z poziomami jak w PZ i paskiem postępu. Komunikat i dźwięk przy awansie. Wspólna funkcja poziomu światła przy graczu (lampy, dzień przy oknie, latarka) służy zombie i czytaniu. Zapis w wersji 8 zawiera postać.


## Build 10 (15.11.2026): ulica i domy

- **Teren** (`scripts/world/town.gd`): 84 × 60 m wokół domu startowego: trawa, jezdnia z chodnikami i pasami, drzewa, niewidzialne granice. Kawałek gruntu za oknem zniknął: z okna wychodzi się prosto na podwórko i ulicę.
- **Domy z ziarna** (`world_seed` w `data/sandbox.json`, ten sam świat po śmierci i wczytaniu): 5 działek po obu stronach ulicy. Dom 8–11 × 7–9 m, dach, ściany z otworami: drzwi wejściowe od ulicy, dwa okna od frontu i jedno z tyłu. 2–3 pokoje przedzielone ścianami z przejściami; każdy dom ma kuchnię, reszta losowo: salon, sypialnia (łóżko: sen lepszy niż na materacu), łazienka, garaż.
- **Pojemniki z łupami** (`data/loot.json`): lodówka, szafka kuchenna, apteczka ścienna, szafa, regał, skrzynka z narzędziami, każdy z liczbą losowań i wagami. Część jedzenia na starcie już nieświeża. Nowe przedmioty: rękawice robocze (chronią dłonie, także przed szkłem) i czapka.
- **Drzwi domów** (`simple_door.gd`): zatrzask, F naciska klamkę i pcha skrzydło od gracza, otwarte F domyka (zaskakują). Działa też chwyt za klamkę. Zombie wali w zatrzaśnięte drzwi i wyważa je po 6 s. Zombie wykrywa każde zatrzaśnięte drzwi przed sobą (także te w komórce).
- **Szyby** (`glass_pane.gd`): cios tłucze szybę (głośno, hałas 75). W ramie zostają odłamki: przełażenie kaleczy przedramiona albo dłonie (rękawice mogą ochronić), F albo drugi cios wybija resztki.
- **Zombie:** strefa „w środku” to tylko dom startowy (do niego dalej wchodzi się przez okno); na dworze chodzą po całej ulicy i po domach po siatce nawigacji wypiekanej z całego terenu. Na start 10 zombie (piaskownica) losowo po ulicy, co najmniej 14 m od gracza. Strefa zombie liczy się na bieżąco z jego położenia.
- **Pod dachem:** deszcz nie pada i nie moczy w domach; w cudzym domu jest ciemno (tylko światło z okien) i tylko o 4 °C cieplej niż na dworze. Krople deszczu lecą nad graczem na dworze i za oknem domu startowego. Rzadsza mgła na otwartej ulicy.
- Zapis w wersji 9 zawiera stan drzwi i szyb; zawartość pojemników zapisuje się razem z ekwipunkiem.

## Build 11 (15.11.2026): rzemiosło i gotowanie

- **Ognisko** (`scripts/craft/heat.gd`, `fire.gd`): drewno kładzie się na ziemi na dworze (deski, deszczułki, książki, szmaty; pole `fuel` w `items.json` to minuty ognia w czasie gry). F z zapałkami albo zapalniczką w ręce zbiera stos w promieniu metra, potrzeba co najmniej 20 minut opału. Zapałki i zapalniczka mają zużycie. W domu i w ulewie nie zapłonie, deszcz przyspiesza gaśnięcie. F na ognisku z drewnem w ręce dokłada sztukę.
- **Ogień grzeje i świeci:** do 14 °C odczuwanej temperatury przy samym ogniu (3 m zasięgu), migoczące światło z cieniami. Światło liczy się do czytania i do tego, jak daleko widzą zombie. Ogień trzaszczy (zapętlony dźwięk) i jest słyszalny, gdy gaśnie.
- **Kuchenka turystyczna:** przedmiot stawiany w świecie. F ją włącza i wyłącza (niebieski płomień), Shift+F podnosi. Działa też w domu. Kartusz na 6 godzin gry, stan gazu widać w podpowiedzi.
- **Gotowanie** dzieje się w świecie: patelnia albo garnek leżące na źródle ciepła (do 0,45 m w poziomie, do 0,7 m nad nim) gotują wszystko, co mają w siatce. Pole `cook` daje czas i wynik (ziemniak → pieczony ziemniak w 40 min). Każde jedzenie zostawione za długo (1,7 czasu) zmienia się w spaleniznę; umiejętność gotowania przesuwa ten próg.
- **Zupa:** garnek (2 l) napełniony przy zlewie, do tego pokrojone warzywa (pole `soup`). Gdy wszystkie się ugotują, woda zmienia się w płyn „zupa” z sytością i nawodnieniem ze składników, z dodatkiem za gotowanie. Zupę je się jak picie, porcjami po 0,25 l, z okna zdrowia.
- **Praca w dłoni** (`hand_work.gd`) obejmuje teraz trzy rodzaje: otwieranie (kręcenie), krojenie i cięcie na szmaty (ruchy w dół, zdolność `ciecie`: nóż 3, nożyczki 2, piła 1). Pola `open`, `cut`, `rip` w danych przedmiotu.
- **Piłowanie** (`scripts/craft/saw.gd`): każda deska leżąca w świecie ma punkt pracy na środku, widoczny z piłą w ręce (zasięg 2,1 m, żeby sięgnąć podłogi). Trzy „pociągnięcia” dają dwie deszczułki; piłowanie hałasuje i uczy stolarstwa.
- **Nowe przedmioty:** zapalniczka, zapałki, piła, nożyczki, deszczułka, garnek, patelnia (też tępa broń), kuchenka, ziemniak, marchew, cebula i ich pokrojone wersje, pieczony ziemniak, spalenizna, książka kucharska. Łupy w lodówkach, szafkach i skrzynkach.
- **Postać:** umiejętność gotowania (krojenie, pieczenie, zupy), zawód kucharz.
- Zapis w wersji 10 zawiera płonące ogniska; stan kuchenki i stopień ugotowania zapisują się w przedmiotach.

### Poprawki po buildzie 11 (start gry i mysz)

- Ekran tworzenia postaci nie miał kursora: koniec startu gry chował mysz pod kamerę zaraz po tym, jak ekran ją pokazał. Teraz kursor zostaje do „Rozpocznij”, a kliknięcie nie łapie myszy, dopóki ekran jest otwarty.
- Cechy wybiera się i odznacza jednym kliknięciem (wcześniej trzeba było klikać dwa razy).
- Zombie na start pojawiały się zanim mapa nawigacji była gotowa, więc w prawdziwej grze nie było ich wcale (testy tego nie łapały, bo tam mapa była już gotowa). Teraz pojawiają się po „Rozpocznij”, po synchronizacji mapy.
- Enter na ekranie śmierci rzucał błąd skryptu przy przeładowaniu sceny.
- Otwarcie ekwipunku albo przełączenie na inny program puszcza trzymane przyciski (praca narzędziem, garda), żeby po powrocie mysz nie prowadziła dalej narzędzia zamiast kamery.
- Piła startowa nachodziła na deskę w pokoju, a ziemniak na skrzynkę (do tego starsza kolizja puszki z chlebem). Fizyka rozpychała bryły i czasem wypychała deskę przez ścianę. Przedmioty przestawione, a nowy test 0 sprawdza, że nic ze `start.json` nie nachodzi na inne przedmioty ani bryły pokoju.
- Nowa kontrola `game/tests/start_check.gd` sprawdza prawdziwy start gry z kliknięciami myszą, czego zwykłe testy (`--test`) nie widzą.

### Poprawki po buildzie 11: wyjście z domu, chodzenie, ikony, nagrywanie

- **Drzwi wyjściowe:** dom startowy dostał drzwi w ścianie południowej komórki (obok łóżka), prowadzące na podwórko i ulicę. Mapa nawigacji też przez nie prowadzi, więc zombie mogą podejść i walić w drzwi.
- **Drzwi domów** otwierały się tylko na szparę i blokowały przejście: siła szła w płaszczyźnie skrzydła. Teraz pchanie jest prostopadłe do skrzydła, przy wolnej krawędzi, a F otwiera drzwi prawie na 90°.
- **Stopień** (`scripts/step_up.gd`): gracz (do 0,3 m) i zombie (do 0,28 m) wchodzą na krawężnik, deskę czy próg bez skakania i bez utykania.
- **Podbijanie na deskach:** postać nie przejmuje już prędkości brył, na których stoi (lekka deska drgała i wyrzucała gracza w górę). Bez skoku prędkość w górę po zetknięciu z ziemią jest zerowana.
- **Ikony 3D w ekwipunku** (`scripts/ui/item_icons.gd`): każdy rodzaj przedmiotu renderuje się raz z tego samego modelu, który leży w świecie i który postać trzyma w ręce, w osobnym świecie 3D, w kadrze o proporcjach kształtu w siatce. Obrócony w siatce przedmiot ma obróconą ikonę. Ikony są też w polach ubrania i rąk.
- **Nagrywanie (F12):** klatki JPG co 0,5 s do `nagrania/<data_godzina>/`, a w `klatki.txt` czas, pozycja, kierunek patrzenia, zdrowie, tryb walki, liczba zombie i FPS. Log błędów silnika (z miejscem w skrypcie) trafia zawsze do `nagrania/log_<data>.txt`. Folder jest pominięty w repozytorium.
- Testy 24a2 i 26: droga z domu na ulicę przez drzwi, przejście przez deskę bez podbicia, wejście gracza i zombie na chodnik, szerokie otwieranie drzwi.

## Build 12 (16.11.2026): broń palna

- **Sterowanie** zgodnie z ustaleniem: w trybie walki (klik kółkiem) z bronią w prawej ręce LPM strzela, PPM przytrzymany to przyrządy celownicze (płynne przybliżenie, wolniejsza mysz, mniejszy rozrzut), R przeładowuje. Kod: `scripts/combat/guns.gd`; walka wręcz oddaje mu przyciski, gdy w ręce jest broń.
- **Strzał** to promień od oka z rozrzutem: biodro, przyrządy, ruch, ranna ręka, broń dwuręczna w jednej ręce (podwójny rozrzut, większy odrzut). Śrut to 8 promieni. Obrażenia słabną z odległością, a głowa zombie liczy się podwójnie i więcej, jak przy ciosach. Odrzut podbija kamerę, a część oddaje (ręce wracają na cel). Do tego błysk z lufy, ślady po kulach (40 ostatnich), uderzenie w luźne bryły i hałas słyszalny z daleka (pistolet 95, strzelba 130).
- **Zasilanie fizyczne:** magazynek to osobny przedmiot z nabojami. Ładuje się go w ekwipunku, przeciągając naboje (pasuje tylko ten sam kaliber), PPM rozładowuje. R wymienia na najpełniejszy magazynek (stary wraca do ekwipunku) i przeładowuje zamek, gdy komora jest pusta. Strzelba pompowa ma rurę na 5 naboi: R wkłada po jednym (strzał przerywa), a po strzale postać sama przeładowuje pompką.
- **Zacięcia:** każdy strzał brudzi broń i trochę ją zużywa. Szansa zacięcia rośnie z kwadratem brudu i ze zużyciem, smar dzieli ją przez 4, a umiejętność ją obniża. Zacięta broń nie strzela, R przeładowuje zamek i wyrzuca zacięty nabój.
- **Konserwacja** na dwóch poziomach, przez pracę w dłoni (broń w lewej ręce, ruchy w dół). Prymitywnie szmatą: brud spada o połowę, nie niżej niż 15%. Profesjonalnie: WD-40 zostawia 15% brudu i smaruje na 60 strzałów (zużywa się), wycior czyści do zera.
- **Modele broni** składane z kilku brył (`type: parts` w `items.json`), ten sam model w świecie, w dłoni (chwyt w miejscu `grip_at`, lufa do przodu) i jako ikona. Wylot lufy liczony z modelu w dłoni.
- **Postać:** umiejętność „broń palna” (rozrzut, odrzut, szybkość przeładowania, zacięcia). Policjant zaczyna z nią na poziomie 3.
- **Na start:** w szafce pistolet z magazynkiem na 6 naboi i dwie paczki 9 mm, w komórce strzelba z 2 nabojami, 8 nabojów śrutowych, zapasowy magazynek, wycior i WD-40. W domach broń i amunicja trafiają się w szafach i na regałach.
- Testy 27a–g: strzał i trafienie, hałas, przyrządy, opróżnienie i przeładowanie, ładowanie i rozładowanie magazynka, zacięcie i jego usunięcie, czyszczenie wyciorem i WD-40, strzelba z rurą, pompką i śrutem.
- Poprawka testu zapisu: krew i wilgoć na ubraniu zmieniają się z czasem, więc porównanie zapisu je pomija (stąd brało się sporadyczne „ekwipunek po odczycie różni się”).
