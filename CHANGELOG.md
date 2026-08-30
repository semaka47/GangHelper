# Changelog

## v2.1.4 — setări persistente, scroll și overlay-uri

- rotița paginii principale funcționează inclusiv peste controale, iar lista deschisă din Weapon Switch preia exclusiv scroll-ul cât cursorul se află în interiorul ei;
- toate setările sunt salvate automat, iar la prima instalare funcțiile și overlay-urile sunt oprite;
- mesajele despre arme lipsă nu mai produc spam în chat;
- Mouse Overlay include o linie smooth care urmărește direcția mouse-ului;
- Bullet Track folosește implicit culorile jucătorilor din TAB, permite opțional o culoare preferată și evidențiază HIT-urile prin contrast alb/negru;
- fonturile, overlay-urile și hook-urile SAMP.Events sunt inițializate după conectare.

## v2.1.3 — versiunea finală și update-uri GitHub

- updaterul este conectat definitiv la manifestul public din `semaka47/GangHelper`; nu mai există niciun placeholder;
- mesajul de injectare este pus în coadă imediat după `isSampAvailable()` și apare în frame-ul următor printr-un singur `wait(0)`, fără să mai aștepte callbackul de conectare sau spawn;
- `v2.1.3` este ultima instalare manuală, iar versiunile următoare sunt semnalate prin punctul roșu al clopoțelului și instalate numai după confirmare;
- manifestul este cerut fără cache, iar fișierul nou trece verificările de versiune, nume, sintaxă și SHA-256 înainte de instalare;
- pagina Acasă a fost compactată: eliminat spațiul gol din `DESPRE MOD`, eliminat subtitlul redundant din cardul update și mutate explicațiile în dreapta pictogramei;
- Contact Developer afișează direct `semaka47`, precedat de un logo Discord vectorial plin și antialias, fără chenarul vechi;
- logo-ul Discord folosește exclusiv primitivele grafice confirmate în MoonImGui legacy; apelul nou incompatibil care putea opri scriptul la deschiderea paginii Acasă a fost eliminat;
- selectorul de culoare este mai mic și folosește două coloane, cu HEX, `Aplică` și `Copiază` în dreapta selectorului vizual;
- mostrele de culoare nu mai au contur dreptunghiular și păstrează numai o umbră rotunjită discretă;
- meniul Overlay a fost reorganizat în carduri compacte și oferă patru stiluri: `Clean`, `Soft`, `Solid` și `Contrast`;
- overlay-urile pornesc cu alb real și opacitate completă; fiecare tastă este o formă rotunjită separată, fără grilă sau chenare între taste;
- Bullet Track acceptă și focurile fără țintă atunci când `center-of-hit` este zero, fără să devieze un target valid din pachet;
- un target local invalid este reconstruit numai pentru focul propriu, folosind direcția reală a camerei și raza armei;
- traseul păstrează culoarea trăgătorului din TAB, iar impacturile confirmate în jucători folosesc un marcaj auriu/alb distinct;
- actualizate textele RO/EN ale centrului de update pentru utilizatori noi și eliminată terminologia tehnică inutilă.

## v2.1.2-beta — input, Bullet-track, reconnect și overlay compact

- scriptul livrat se numește simplu `GangHelper.lua`, iar update-urile viitoare înlocuiesc același fișier;
- mesajul de încărcare este împărțit în două linii scurte, astfel încât limita chatului SA-MP nu mai taie instrucțiunile;
- rotița nu mai este citită de overlay; este direcționată exclusiv către scroll-ul paginii, inclusiv peste checkboxuri, butoane, slidere și carduri;
- cardul `DESPRE MOD` folosește un simbol abstract fără litere sau chenar, iar pagina Acasă încape fără scroll;
- cardul `CONTACT DEVELOPER` afișează explicit `Discord: semaka47`;
- distanța dintre explicațiile din `FUNCȚIE UPDATE` a fost redusă, ghilimelele incompatibile au fost eliminate, iar `Actualizează acum` este evidențiat bold;
- selectorul de culoare acceptă coduri `#RRGGBB`, aplicare directă, copiere în clipboard și are un stroke/shadow vizibil inclusiv pentru alb;
- bind-ul B-ZONE trimite `/omg`, apoi pulsează imediat click dreapta pentru un frame;
- FPS Boost nu mai modifică densitatea traficului, pietonii sau trenurile și descrie doar optimizările locale relevante clientului SA-MP;
- controllerul Changeskin este aliniat pe același rând cu activarea;
- Bullet-track ignoră pachetele cu `center` invalid și desenează direct `origin → target`, ca referința `btrack.lua`; durata maximă este 5 secunde;
- adăugate `Ultra Fast Connect` și `Reconectare`, cu IP/DNS, port, nickname, clan tag, eliminarea tag-ului și retry automat limitat la minimum 0,50 s;
- butonul `X` este mai mare, bold și centrat;
- overlay-urile sunt redesenate pe un canvas ImGui antialias, au colțuri perfect uniforme, culoare implicită albă, poziții în stânga și scalare `0.25x–0.75x`;
- tema implicită este Light, iar pozițiile Soare/Lună au fost inversate;
- cardurile Sensitivity Fix sunt mai apropiate și nu mai cer scroll pentru lista de arme;
- cererile implicite de arme folosesc chatul normal, fără `/f`;
- footerul afișează direct `V2.1.2-BETA`, fără cuvântul „VERSIUNE”, iar eticheta `FPS` rămâne fixă;
- toate mesajele de sistem încep cu literă mică după prefixul multicolor, iar mesajul de injectare rămâne împărțit în două linii prin `wait(0)`.

## v2.1.1-beta — scroll, updater și trasee profesionale

- rotița mouse-ului este transmisă paginii principale chiar când cursorul se află peste cardurile fixe ale overlay-ului;
- cardul `FUNCȚIE UPDATE` are spațiere compactă, iar centrul de update se închide la click în exterior;
- toate textele centrului de update au fost rescrise pentru utilizatorul final, fără detalii tehnice inutile;
- `DESPRE MOD` este prezentat într-un card cu monogram GH vectorial;
- Changeskin are eticheta `Skin ID` centrată corect și folosește caracterele compatibile `- / +`;
- Bullet-track folosește acum o traiectorie continuă în stilul referinței, trei straturi vizuale, proiectil direcțional și marcaj de impact;
- Sensitivity Fix afișează `STANDARD JOC` la bază și numai diferențe semnate după reglare;
- `COMENZI ȘI BIND-URI` acceptă butoanele `MOUSE 1–5`, inclusiv `MOUSE 5`;
- avertismentul FPS a fost apropiat de descrierea FPS Unlocker;
- footerul afișează versiunea înainte de `BY SEMAKA`, care rămâne ultimul element;
- prefixul chat folosește noul gradient `{202020}`–`{808080}`, iar tot textul mesajelor modului este alb;
- mesajul `wait(0)` a fost înlocuit cu formularea exactă solicitată.
- scriptul se numește acum `GangHelper.lua`, configurația este `gang_helper.ini`, iar setările vechi sunt migrate automat.

## v2.1.0-beta — SA-MP FPS, Bullet-track și finisare UI

- reparată detecția Wheel Up/Down prin fallback combinat MoonLoader, ImGui și taste virtuale; scroll-ul meniului nu mai este blocat de fereastra principală;
- Bullet-track reconstruit cu raze pe armă, buffer fix de 48 de focuri, filtru local, captarea focurilor către hitboxul propriu, culoare RGBA corectă din TAB, animație segmentată, glow, fade și cap direcțional;
- FPS Unlocker extins cu dezactivarea limitatorului GTA și patch-uri SA-MP bazate exclusiv pe semnături verificate, restaurate la dezactivare sau unload;
- FPS Lock nu mai trimite comenzi în chat și folosește un timer local de înaltă rezoluție, cu interval 20–100 FPS și valoare implicită 100;
- FPS Boost folosește optimizări ambientale locale relevante pentru clientul SA-MP și restaurează setările la debifare;
- Changeskin folosește introducere numerică directă și pași exacți de câte un ID; nu mai sare valori din cauza sliderului;
- cardul JUCĂTOR/SERVER/SESIUNE afișează din nou eticheta și valoarea pe rânduri separate, cu spațiere verticală compactă și tăiere după lățimea reală;
- Contact Developer există numai pe Acasă și folosește o iconiță developer dedicată;
- eliminate bordurile fine ale ferestrei, cardurilor, headerului, footerului și mostrelor de culoare; popup-urile Weapon Switch au contrast compatibil Dark/Light;
- etichetele Weapon Switch nu mai sunt numerotate; toate afișează `Armă / Tastă`;
- Auto Accept Gun așteaptă coborârea din vehicul înainte să înceapă delay-ul și să trimită comanda;
- Sensitivity Fix folosește direct câte un reglaj pe armă, cu standardul real al jocului drept bază și fără activare separată pe fiecare rând;
- footerul afișează `CONNECTED · FPS` în stânga și `BY SEMAKA · V2.1.0-BETA` în dreapta;
- prefixul mesajelor locale este noul gradient gri, iar mesajul de încărcare este trimis după un singur `wait(0)`.

## v2.0.0-beta — updater, utility functions, sensitivity and interface

- adăugat updaterul din client cu manifest HTTPS, confirmare, changelog RO/EN, SHA-256, verificare sintactică, backup, rollback și reload;
- butonul rapid Setări din header a fost înlocuit cu un clopoțel; punctul roșu indică exclusiv un update disponibil;
- pagina Acasă conține noua descriere, secțiunea `FUNCȚIE UPDATE`, instrucțiuni și Discord `semaka47`;
- cardul JUCĂTOR/SERVER/SESIUNE a fost compactat la 110 px și folosește rânduri de 34 px;
- iconițele vectoriale, pictograma Funcții, clopoțelul și selectorul RO/EN au fost redesenate pentru lizibilitate;
- fonturile Rubik au fost eliminate; meniul folosește fonturile standard Windows;
- Sensitivity Fix are override separat pentru fiecare armă, iar armele nebifate păstrează sensibilitatea reală a jocului;
- eliminat butonul de copiere a sensibilității; resetarea se află sub listă și dezactivează toate valorile personalizate;
- Weapon Switch folosește eticheta `Armă / Tastă`, cu popup și text contrastante pe Dark și Light;
- adăugată pagina `Funcții`: Infinite Run, FPS Boost, FPS Lock, FPS Unlocker, Time, Weather, Bullet-track și Changeskin;
- Bullet-track folosește maximum 32 de trasee cu rază, durată, fade, glow, săgeată și culorile jucătorilor din TAB;
- Changeskin persistă după respawn și cedează automat controlul când serverul schimbă intenționat skinul;
- mesajul de injectare este trimis prin `wait(0)` în primul frame în care jucătorul și chatul SA-MP sunt pregătite;
- starea funcțiilor a fost grupată pentru a rămâne sub limita de 200 de variabile locale din Lua 5.1.

## v1.9.0-beta

- font Rubik inclus, navigare compactă, sesiunea procesului GTA SA și pagină Acasă simplificată;
- reset Sensitivity Fix reparat la `0.002500`;
- selectoare Dark/Light și RO/EN fără chenarele vechi.

## v1.8-beta

- deschidere pe `Del`, mesaj RO/EN, slidere slim, scurtături configurabile și overlay extins.

## v1.7.2-beta

- interfață tehnică minimalistă `800×600`, branding textual și footer live.
