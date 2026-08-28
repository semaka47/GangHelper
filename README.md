# Gang Helper — v2.1.3

**Gang Helper** este un mod Lua pentru SA-MP/MoonLoader care reunește într-un singur meniu funcții pentru arme, sensibilitate, comenzi rapide, overlay-uri și optimizarea experienței de joc. Interfața este disponibilă în română și engleză, cu teme Light și Dark și profiluri dedicate serverelor B-ZONE și BUGGED.

## Funcții principale

- **Weapon Switch** — configurezi armele și tastele preferate pentru schimbare rapidă. Auto Accept Gun poate accepta automat ofertele și așteaptă coborârea din vehicul înainte de executare.
- **Sensitivity Fix** — reglezi separat sensibilitatea armelor, pornind de la valoarea standard a jocului. Modificarea se aplică numai atunci când ții click dreapta pentru a ținti.
- **Comenzi și scurtături** — creezi aliasuri pentru comenzile lungi și bind-uri pe tastatură sau pe butoanele mouse-ului, inclusiv `MOUSE 1–5`.
- **Cereri și vânzări de arme** — comenzile pot fi personalizate și executate direct din chatul normal.
- **Keyboard & Mouse Overlay** — overlay-uri compacte, repoziționabile și redimensionabile, cu alegerea culorii normale și a culorii pentru tastele apăsate prin cod HEX.
- **Bullet Track** — afișează direcția focurilor proprii și ale jucătorilor din apropiere, respectă raza armei și culoarea jucătorului din TAB, iar loviturile confirmate sunt evidențiate separat.

## Funcții utile

- **Infinite Run** — elimină consumul de stamină.
- **FPS Boost** — aplică optimizări vizuale locale pentru clientul SA-MP.
- **FPS Lock** — limitează local rata de cadre între 20 și 100 FPS, fără comenzi sau mesaje în chat.
- **FPS Unlocker** — elimină limitatoarele compatibile GTA SA/SA-MP.
- **Time & Weather** — schimbă local ora și vremea din joc.
- **ChangeSkin** — aplică local skinul ales și îl păstrează după respawn, până când serverul setează alt skin.
- **Ultra Fast Connect & Reconectare** — reconectare rapidă la server, cu IP/DNS, port, nickname și eliminare opțională a clan tagului.

## Actualizări automate

`v2.1.3` este ultima versiune care trebuie instalată manual. Pentru versiunile următoare, Gang Helper verifică automat dacă există un update și afișează un punct roșu pe clopoțel.

Actualizarea pornește numai după confirmarea utilizatorului. Fișierul descărcat este verificat prin SHA-256, versiunea curentă este salvată ca backup, iar scriptul este înlocuit și reîncărcat automat.

## Instalare

1. Închide GTA San Andreas.
2. Elimină orice versiune veche `GangHelper*.lua`.
3. Copiază folderul `moonloader` din arhivă în folderul jocului.
4. Pornește SA-MP și deschide meniul cu `Del` sau `/gh`.

Configurația este salvată în `moonloader/config/gang_helper.ini`. Setările vechi din `gang_helper_by_semaka.ini` sunt importate automat.

## Controale

- `Del` sau `/gh` — deschide ori închide meniul;
- `ESC` — anulează selectarea unei taste;
- `BACKSPACE` sau `DELETE` — elimină bind-ul selectat;
- rotița mouse-ului — scroll prin paginile meniului.

## Cerințe

- GTA San Andreas 1.0 US;
- SA-MP și MoonLoader;
- SAMPFUNCS;
- `imgui` clasic sau `mimgui`;
- `inicfg`, `memory` și `vkeys`;
- SAMP.Lua pentru Bullet Track, reconectare, Auto Accept Gun și interceptarea comenzilor.

Nu sunt necesare fonturi externe. Nu rula simultan mai multe versiuni Gang Helper.

## Contact

Pentru sugestii, propuneri sau raportarea problemelor: **Discord `semaka47`**.
