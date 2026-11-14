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
