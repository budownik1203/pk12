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
- **Sterowanie:** akcje rejestrowane w `controls.gd`. Układ: WASD, Shift sprint, Ctrl kucanie, Q/E wychylanie, F interakcja, Tab ekwipunek, H zdrowie, R obrót przedmiotu, lewy przycisk myszy użycie, prawy przycisk praca narzędziem.
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
