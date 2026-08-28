# Gang Helper — v2.1.3

Gang Helper este un script Lua pentru SA-MP/MoonLoader, cu interfață RO/EN, profiluri B-ZONE și BUGGED, funcții pentru arme, sensibilitate, scurtături, overlay-uri și utilitare locale.

## Instalare

1. Închide GTA San Andreas.
2. Elimină orice versiune veche `GangHelper*.lua`; scriptul curent se numește simplu `GangHelper.lua`.
3. Copiază folderul `moonloader` din arhivă peste folderul `GTA San Andreas/moonloader`.
4. Pornește SA-MP. Imediat ce interfața SA-MP este disponibilă, mesajul este trimis după un singur `wait(0)` și este împărțit în două linii scurte.
5. Deschide meniul cu `Del` sau `/gh`.

`v2.1.3` este ultima versiune care trebuie instalată manual. Ea conține adresa publică permanentă a manifestului GitHub; de la `v2.1.4` încolo, versiunile noi vor înlocui automat același `GangHelper.lua`, numai după confirmarea utilizatorului.

Nu mai există folder de fonturi și nu trebuie instalat nimic pentru aspectul meniului. Interfața folosește Segoe UI/Segoe UI Variable din Windows, cu fallback la Tahoma sau Arial.

Configurația se salvează în `moonloader/config/gang_helper.ini`. Dacă există vechiul `gang_helper_by_semaka.ini`, setările sunt importate automat o singură dată și salvate sub noul nume.

## Update fără un client nou

v2.1.3 activează updaterul GitHub pentru versiunile următoare:

- verificare automată la pornire, dacă este activată;
- clopoțel în dreapta sus, în locul butonului rapid Setări;
- punct roșu numai când există o versiune mai nouă;
- changelog RO/EN în centrul de notificări;
- instalare numai după confirmarea utilizatorului;
- descărcare într-un fișier temporar;
- validare sintactică Lua și verificare SHA-256;
- înlocuirea sigură a fișierului stabil `GangHelper.lua`;
- backup automat cu extensia inactivă `.gh-backup`;
- restaurarea versiunii vechi dacă înlocuirea nu reușește;
- reîncărcarea automată a scriptului după instalare.

Manifestul este configurat direct la `https://raw.githubusercontent.com/semaka47/GangHelper/main/updater/manifest.json`. Nu există marker de completat și utilizatorul nu trebuie să modifice nimic. Instrucțiunile de publicare pentru versiunile următoare se află în `UPDATE-GUIDE.md`.

## Meniul Acasă

Pagina Acasă conține:

- descrierea completă a Gang Helper Lua, cu pasajele importante evidențiate;
- secțiunea `FUNCȚIE UPDATE`, cu explicația clopoțelului și a notificării roșii;
- instrucțiunea scurtă pentru publicarea versiunilor următoare;
- contactul Discord `semaka47` pentru buguri, sugestii și propuneri.

În v2.1.3, toate cele trei zone sunt prezentate în carduri compacte care încap pe pagina Acasă fără scroll. Spațiul inutil de sub `DESPRE MOD` a fost eliminat, explicația update-ului este așezată în dreapta pictogramei, iar contactul folosește un logo Discord vectorial înainte de `semaka47`.

## Funcții noi

### Infinite Run

Activează starea locală „never tired”. Setarea este reaplicată după spawn și este restaurată la oprirea scriptului.

### Funcții FPS

- `FPS Boost` reduce numai efecte decorative locale compatibile ale clientului SA-MP; nu modifică jucătorii, vehiculele sau datele serverului, iar setările sunt restaurate la debifare.
- `FPS Lock` folosește un limiter local de înaltă rezoluție între 20 și 100 FPS, implicit 100, fără `/fpslimit` și fără mesaje în chat.
- `FPS Unlocker` dezactivează limitatorul GTA și caută semnăturile compatibile ale limitatorului SA-MP înainte de orice patch; nu scrie în memorie dacă semnătura nu corespunde.

`FPS Lock` și `FPS Unlocker` sunt exclusiv reciproce: activarea unuia îl oprește automat pe celălalt.

FPS foarte mare poate modifica fizica GTA SA. VSync, driverul video sau alte pluginuri pot limita în continuare rata de cadre. Câștigul FPS Boost depinde de procesor, placă video, rezoluție și modpack și nu poate fi garantat procentual pe toate sistemele.

### Time și Weather

- ora locală poate fi aleasă între `0` și `23`;
- vremea locală poate fi aleasă între ID `0` și `22`;
- debifarea redă controlul jocului/serverului;
- valorile sunt locale și nu schimbă ora ori vremea celorlalți jucători.

### Bullet-track

- citește sincronizarea oficială `BulletSyncData` prin SAMP.Lua;
- afișează traseele tale și ale jucătorilor din apropiere;
- folosește culoarea jucătorului din TAB;
- limitează fiecare traseu la raza reală a armei (de exemplu Rifle 100 m, M4 90 m, Sniper 300 m);
- folosește direct segmentul valid `origin → target` din pachet, fără animații care să schimbe impresia direcției;
- acceptă focurile în aer chiar dacă `center-of-hit` este zero; numai un target local invalid este reconstruit din direcția reală a camerei;
- desenează o linie clară și un capăt poligonal în stilul fișierului `btrack.lua` furnizat;
- păstrează culoarea trăgătorului din TAB și marchează distinct, auriu/alb, impactul confirmat într-un jucător;
- are distanță locală configurabilă și durată între `0.25` și `5.00` secunde;
- păstrează maximum 48 de trasee într-un buffer fix;
- păstrează și un foc de la distanță atunci când pachetul indică drept țintă ID-ul tău;
- se oprește sigur dacă `lib.samp.events` nu este disponibilă.

### Changeskin

Skinul ales este local și este reaplicat după respawn. Controllerul permite introducerea directă a ID-ului și pași exacți de câte `1`, astfel încât valorile intermediare nu mai sunt sărite. Dacă serverul trimite intenționat un skin nou în afara secvenței de moarte/spawn, Changeskin se dezactivează și lasă skinul serverului activ. ID-ul `74` este exclus deoarece GTA SA nu conține acel model de jucător.

### Ultra Fast Connect și Reconectare

- detectează evenimentele SAMP.Lua pentru server plin, conexiune eșuată, conexiune pierdută, închidere și restart de gamemode;
- reîncearcă automat la un interval configurabil între `0.50` și `5.00` secunde;
- permite IP sau DNS, port și nickname propriu;
- poate elimina un clan tag configurat din nickname înainte de reconectare;
- câmpurile lăsate goale folosesc automat serverul și nickname-ul curent;
- butonul `Reconectează acum` funcționează fără comenzi și fără spam în chat.

## Sensitivity Fix

Comutatorul principal poate rămâne activ, iar toate armele pornesc de la sensibilitatea citită direct din joc:

- nu mai există bife separate pe arme; fiecare rând are direct reglajul său;
- numai valorile care diferă de standard sunt aplicate;
- fiecare reglaj afișează `STANDARD JOC` la bază și numai diferența cu semn `-` sau `+` după modificare;
- valoarea se aplică exclusiv cât timp este ținut click dreapta;
- armele lăsate la standard nu sunt scrise în memorie;
- schimbarea armei sau eliberarea clickului dreapta restaurează imediat valoarea jocului;
- `Resetează toate la standardul jocului` readuce fiecare rând la baza capturată și este poziționat sub listă;
- butonul vechi de copiere a valorii a fost eliminat.

Funcția de memorie necesită GTA San Andreas 1.0 US. Dacă adresele nu pot fi validate, funcția rămâne oprită.

## Weapon Switch

Cele cinci rânduri sunt etichetate `Armă / Tastă` / `Weapon / Key`. Popup-urile folosesc explicit culorile temei active, astfel încât selecția și textul rămân lizibile inclusiv pe tema Light. Mesajele implicite pentru cererile de arme sunt trimise în chatul normal, fără prefixul `/f`; pot fi personalizate în continuare.

Auto Accept Gun ține oferta în așteptare dacă jucătorul se află într-un vehicul. Întârzierea configurată începe numai după coborâre, iar comanda este trimisă cât timp oferta și jucătorul sursă sunt încă valide.

## Cerințe

- GTA San Andreas 1.0 US;
- SA-MP;
- MoonLoader;
- SAMPFUNCS;
- `imgui` clasic sau `mimgui`;
- `inicfg`, `memory` și `vkeys`;
- SAMP.Lua (`lib.samp.events`) pentru Bullet-track, Ultra Fast Connect, Auto Accept Gun și scurtăturile care interceptează comenzile.

Fără SAMP.Lua, scriptul rămâne încărcat, iar funcțiile independente continuă să funcționeze.

## Control și compatibilitate

- `/gh` sau `Del`: deschide/închide meniul;
- `ESC`: anulează selectarea unei taste;
- `BACKSPACE` sau `DELETE`: șterge bind-ul selectat;
- bind-urile din `COMENZI ȘI BIND-URI` acceptă și `MOUSE 1–5`, inclusiv butonul lateral `MOUSE 5`;
- rotița este rezervată exclusiv scroll-ului meniului, inclusiv când cursorul se află peste checkboxuri, slidere sau carduri;
- overlay-urile pot fi mutate cu mouse-ul cât timp meniul este deschis, acceptă coduri HEX și au scalare între `0.25x` și `0.75x`;
- tastele și mouse-ul sunt desenate separat pe un canvas ImGui transparent, fără grilă sau chenare între taste, cu colțuri rotunjite antialias și alb real implicit;
- pagina Overlay oferă patru stiluri (`Clean`, `Soft`, `Solid`, `Contrast`), rotunjire, spațiere și intensitatea umbrei;
- selectorul de culoare este compact, pe două coloane: selectorul vizual în stânga și culoarea curentă, HEX, Aplică și Copiază în dreapta;
- tema implicită este Light, iar selectorul afișează Soare în stânga și Lună în dreapta;
- valoarea FPS este aliniată într-un câmp fix, astfel încât textul `FPS` nu se deplasează la trecerea între două și trei cifre;
- pozițiile implicite ale overlay-urilor sunt în partea stângă a ecranului;
- nu rula simultan o versiune veche și v2.1.3;
- v2.1.3 păstrează compatibilitatea cu interfața clasică MoonImGui și evită identificatorii de stil care au produs assertion-uri în beta-urile vechi.

## Referințe tehnice

- [MoonLoader Lua reference](https://gist.github.com/THE-FYP/abc6f8bea87f4cb42331fc6dd7a84576)
- [SAMP.Lua events](https://github.com/THE-FYP/SAMP.Lua/blob/master/samp/events.lua)
- [SAMP.Lua BulletSyncData](https://github.com/THE-FYP/SAMP.Lua/blob/master/samp/synchronization.lua)
- [open.mp Weather IDs](https://open.mp/docs/scripting/resources/weatherid)
