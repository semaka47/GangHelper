# Publicarea update-urilor Gang Helper

Gang Helper v2.1.3 folosește un singur canal public și verifică automat manifestul GitHub:

```text
https://raw.githubusercontent.com/semaka47/GangHelper/main/updater/manifest.json
```

Utilizatorul este notificat prin punctul roșu al clopoțelului și decide dacă apasă `Actualizează acum`. Update-ul nu se instalează fără confirmare.

## Ce se întâmplă în client

1. Gang Helper descarcă manifestul prin HTTPS, fără cache.
2. Compară versiunea online cu versiunea instalată.
3. Dacă există o versiune mai nouă, clopoțelul primește punctul roșu.
4. După confirmare, scriptul descarcă noul `GangHelper.lua` într-un fișier temporar.
5. Verifică numele, versiunea, sintaxa Lua și SHA-256.
6. Creează un backup inactiv al versiunii curente.
7. Înlocuiește scriptul și îl reîncarcă automat.

Configurația `moonloader/config/gang_helper.ini` nu este înlocuită.

## Manifestul

Fișierul `updater/manifest.json` trebuie să aibă forma:

```json
{
  "version": "v2.1.4",
  "file_name": "GangHelper.lua",
  "download_url": "https://raw.githubusercontent.com/semaka47/GangHelper/v2.1.4/GangHelper.lua",
  "sha256": "HASH_SHA256_CU_64_DE_CARACTERE",
  "changelog_ro": [
    "Prima modificare.",
    "A doua modificare."
  ],
  "changelog_en": [
    "First change.",
    "Second change."
  ]
}
```

Folosește versiuni stabile precum `v2.1.4`, nu `v2.1.4-final`. Sufixele `-beta` sunt rezervate exclusiv versiunilor beta.

## Ordinea obligatorie pentru fiecare versiune

Exemplu pentru `v2.1.4`:

1. Modifică și testează `GangHelper.lua`.
2. Actualizează în script:
   - `script_version('2.1.4')`;
   - `script_version_number(20104)`;
   - `VERSION = 'v2.1.4'`.
3. Nu schimba numele fișierului: trebuie să rămână `GangHelper.lua`.
4. Calculează SHA-256 pentru fișierul final.
5. Publică mai întâi commitul care conține noul script.
6. Creează tagul fix `v2.1.4` pe acel commit și publică GitHub Release-ul.
7. Verifică adresa raw a tagului și hash-ul fișierului descărcat.
8. Modifică manifestul cu versiunea, URL-ul, hash-ul și changelog-ul.
9. Publică manifestul ultimul.

Manifestul publicat ultimul împiedică apariția unei notificări înainte ca fișierul nou să fie disponibil. Git tagul nu trebuie șters, mutat sau refolosit pentru alt fișier.

## SHA-256 în Windows

PowerShell:

```powershell
(Get-FileHash .\GangHelper.lua -Algorithm SHA256).Hash.ToLower()
```

Command Prompt:

```bat
certutil -hashfile GangHelper.lua SHA256
```

Copiază numai cele 64 de caractere hexazecimale. După calcularea hash-ului, nu mai modifica fișierul.

## Test înainte de publicare

- scriptul trebuie să treacă verificarea de sintaxă Lua;
- versiunea din manifest trebuie să apară în script;
- URL-ul `download_url` trebuie să returneze direct codul Lua, nu o pagină HTML;
- SHA-256 local trebuie să fie identic cu SHA-256 al fișierului descărcat de la URL;
- manifestul trebuie să fie JSON valid;
- `file_name` trebuie să rămână `GangHelper.lua`.

## Revenire după un update cu probleme

Nu modifica în loc un tag deja publicat. Repară problema și publică o versiune cu număr mai mare, de exemplu `v2.1.5`.

Pentru recuperare manuală pe un client:

1. închide GTA San Andreas;
2. mută fișierul defect `GangHelper.lua`;
3. redenumește `GangHelper.lua.gh-backup` în `GangHelper.lua`;
4. corectează manifestul înainte de a continua distribuirea.

Updaterul instalează un singur fișier Lua. Păstrează iconițele, fonturile și celelalte resurse desenate sau incluse direct în script. Un update care ar necesita DLL-uri ori alte fișiere trebuie să extindă mai întâi formatul updaterului.
