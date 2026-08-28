# Gang Helper â€” v2.1.3

**Gang Helper** este un mod Lua pentru SA-MP/MoonLoader care reuneÈ™te Ã®ntr-un singur meniu funcÈ›ii pentru arme, sensibilitate, comenzi rapide, overlay-uri È™i optimizarea experienÈ›ei de joc. InterfaÈ›a este disponibilÄƒ Ã®n romÃ¢nÄƒ È™i englezÄƒ, cu teme Light È™i Dark È™i profiluri dedicate serverelor B-ZONE È™i BUGGED.

## FuncÈ›ii principale

- **Weapon Switch** â€” configurezi armele È™i tastele preferate pentru schimbare rapidÄƒ. Auto Accept Gun poate accepta automat ofertele È™i aÈ™teaptÄƒ coborÃ¢rea din vehicul Ã®nainte de executare.
- **Sensitivity Fix** â€” reglezi separat sensibilitatea armelor, pornind de la valoarea standard a jocului. Modificarea se aplicÄƒ numai atunci cÃ¢nd È›ii click dreapta pentru a È›inti.
- **Comenzi È™i scurtÄƒturi** â€” creezi aliasuri pentru comenzile lungi È™i bind-uri pe tastaturÄƒ sau pe butoanele mouse-ului, inclusiv `MOUSE 1â€“5`.
- **Cereri È™i vÃ¢nzÄƒri de arme** â€” comenzile pot fi personalizate È™i executate direct din chatul normal.
- **Keyboard & Mouse Overlay** â€” overlay-uri compacte, repoziÈ›ionabile È™i redimensionabile, cu alegerea culorii normale È™i a culorii pentru tastele apÄƒsate prin cod HEX.
- **Bullet Track** â€” afiÈ™eazÄƒ direcÈ›ia focurilor proprii È™i ale jucÄƒtorilor din apropiere, respectÄƒ raza armei È™i culoarea jucÄƒtorului din TAB, iar loviturile confirmate sunt evidenÈ›iate separat.

## FuncÈ›ii utile

- **Infinite Run** â€” eliminÄƒ consumul de staminÄƒ.
- **FPS Boost** â€” aplicÄƒ optimizÄƒri vizuale locale pentru clientul SA-MP.
- **FPS Lock** â€” limiteazÄƒ local rata de cadre Ã®ntre 20 È™i 100 FPS, fÄƒrÄƒ comenzi sau mesaje Ã®n chat.
- **FPS Unlocker** â€” eliminÄƒ limitatoarele compatibile GTA SA/SA-MP.
- **Time & Weather** â€” schimbÄƒ local ora È™i vremea din joc.
- **ChangeSkin** â€” aplicÄƒ local skinul ales È™i Ã®l pÄƒstreazÄƒ dupÄƒ respawn, pÃ¢nÄƒ cÃ¢nd serverul seteazÄƒ alt skin.
- **Ultra Fast Connect & Reconectare** â€” reconectare rapidÄƒ la server, cu IP/DNS, port, nickname È™i eliminare opÈ›ionalÄƒ a clan tagului.

## ActualizÄƒri automate

`v2.1.3` este ultima versiune care trebuie instalatÄƒ manual. Pentru versiunile urmÄƒtoare, Gang Helper verificÄƒ automat dacÄƒ existÄƒ un update È™i afiÈ™eazÄƒ un punct roÈ™u pe clopoÈ›el.

Actualizarea porneÈ™te numai dupÄƒ confirmarea utilizatorului. FiÈ™ierul descÄƒrcat este verificat prin SHA-256, versiunea curentÄƒ este salvatÄƒ ca backup, iar scriptul este Ã®nlocuit È™i reÃ®ncÄƒrcat automat.

## Instalare

1. ÃŽnchide GTA San Andreas.
2. EliminÄƒ orice versiune veche `GangHelper*.lua`.
3. CopiazÄƒ folderul `moonloader` din arhivÄƒ Ã®n folderul jocului.
4. PorneÈ™te SA-MP È™i deschide meniul cu `Del` sau `/gh`.

ConfiguraÈ›ia este salvatÄƒ Ã®n `moonloader/config/gang_helper.ini`. SetÄƒrile vechi din `gang_helper_by_semaka.ini` sunt importate automat.

## Controale

- `Del` sau `/gh` â€” deschide ori Ã®nchide meniul;
- `ESC` â€” anuleazÄƒ selectarea unei taste;
- `BACKSPACE` sau `DELETE` â€” eliminÄƒ bind-ul selectat;
- rotiÈ›a mouse-ului â€” scroll prin paginile meniului.

## CerinÈ›e

- GTA San Andreas 1.0 US;
- SA-MP È™i MoonLoader;
- SAMPFUNCS;
- `imgui` clasic sau `mimgui`;
- `inicfg`, `memory` È™i `vkeys`;
- SAMP.Lua pentru Bullet Track, reconectare, Auto Accept Gun È™i interceptarea comenzilor.

Nu sunt necesare fonturi externe. Nu rula simultan mai multe versiuni Gang Helper.

## Contact

Pentru sugestii, propuneri sau raportarea problemelor: **Discord `semaka47`**.
