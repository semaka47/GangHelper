script_name('Gang Helper - Beta')
script_author('SeMaKa')
script_version('2.1.1-beta')
script_version_number(20101)
script_description('Gang Helper 2.1.1 beta with refined scrolling, updater and bullet tracers.')

require 'lib.moonloader'

local legacyImgui, imgui = pcall(require, 'imgui')
if not legacyImgui then
    imgui = require 'mimgui'
end
local inicfg = require 'inicfg'
local memory = require 'memory'
local vkeys = require 'vkeys'
local ffi = require 'ffi'
local bit = require 'bit'
local CHILD_BG_COLOR = imgui.Col.ChildBg or imgui.Col.ChildWindowBg
local NON_SCROLLING_CHILD_FLAGS = (imgui.WindowFlags.NoScrollbar or 0)
    + (imgui.WindowFlags.NoScrollWithMouse or 0)
local moonloaderModuleAvailable, moonloaderModule = pcall(require, 'moonloader')
local downloadStatus = moonloaderModuleAvailable and moonloaderModule.download_status or {
    STATUS_DOWNLOADINGDATA = 5,
    STATUS_ENDDOWNLOADDATA = 6,
    STATUSEX_ENDDOWNLOAD = 58
}

local processClockKernel = nil
local processStartedAt100ns = nil
local processClockReady = pcall(function()
    ffi.cdef([[
        typedef struct {
            unsigned long dwLowDateTime;
            unsigned long dwHighDateTime;
        } GH_FILETIME;
        void* __stdcall GetCurrentProcess(void);
        int __stdcall GetProcessTimes(void* process, GH_FILETIME* creation,
            GH_FILETIME* exitTime, GH_FILETIME* kernelTime, GH_FILETIME* userTime);
        void __stdcall GetSystemTimeAsFileTime(GH_FILETIME* systemTime);
    ]])
    processClockKernel = ffi.load('kernel32')
    local creation = ffi.new('GH_FILETIME[1]')
    local exitTime = ffi.new('GH_FILETIME[1]')
    local kernelTime = ffi.new('GH_FILETIME[1]')
    local userTime = ffi.new('GH_FILETIME[1]')
    if processClockKernel.GetProcessTimes(processClockKernel.GetCurrentProcess(),
            creation, exitTime, kernelTime, userTime) ~= 0 then
        processStartedAt100ns = tonumber(creation[0].dwHighDateTime) * 4294967296
            + tonumber(creation[0].dwLowDateTime)
    end
end)
if not processClockReady or not processStartedAt100ns then
    processClockKernel = nil
    processStartedAt100ns = nil
end

-- High-resolution timing and guarded module patching are kept separate from
-- the process-session clock. Every native write is preceded by a signature
-- check and the original bytes are retained for restoration on unload.
local fpsKernel, fpsPsapi = nil, nil
local fpsClockFrequency = nil
local fpsNativeReady = pcall(function()
    ffi.cdef([[
        typedef struct {
            void* lpBaseOfDll;
            unsigned long SizeOfImage;
            void* EntryPoint;
        } GH_MODULEINFO;
        void* __stdcall GetModuleHandleA(const char* moduleName);
        int __stdcall VirtualProtect(void* address, unsigned long size,
            unsigned long newProtect, unsigned long* oldProtect);
        int __stdcall FlushInstructionCache(void* process, const void* baseAddress,
            unsigned long size);
        int __stdcall QueryPerformanceCounter(long long* value);
        int __stdcall QueryPerformanceFrequency(long long* value);
        void __stdcall Sleep(unsigned long milliseconds);
        int __stdcall GetModuleInformation(void* process, void* module,
            GH_MODULEINFO* moduleInfo, unsigned long size);
    ]])
    fpsKernel = ffi.load('kernel32')
    fpsPsapi = ffi.load('psapi')
    local frequency = ffi.new('long long[1]')
    if fpsKernel.QueryPerformanceFrequency(frequency) ~= 0 then
        fpsClockFrequency = tonumber(frequency[0])
    end
end)
if not fpsNativeReady or not fpsClockFrequency or fpsClockFrequency <= 0 then
    fpsKernel, fpsPsapi, fpsClockFrequency = nil, nil, nil
end

local function uiBool(value)
    return legacyImgui and imgui.ImBool(value) or imgui.new.bool(value)
end

local function uiInt(value)
    return legacyImgui and imgui.ImInt(value) or imgui.new.int(value)
end

local function uiFloat(value)
    return legacyImgui and imgui.ImFloat(value) or imgui.new.float(value)
end

local function uiFloat4()
    return legacyImgui and imgui.ImFloat4(0.0, 0.0, 0.0, 1.0) or imgui.new.float[4]()
end

local function uiBuffer(size)
    return legacyImgui and imgui.ImBuffer(size) or imgui.new.char[size]()
end

local function uiGet(value, index)
    if legacyImgui then
        if index ~= nil then
            return value.v[index + 1]
        end
        return value.v
    end
    return value[index or 0]
end

local function uiSet(value, newValue, index)
    if legacyImgui then
        if index ~= nil then
            value.v[index + 1] = newValue
        else
            value.v = newValue
        end
    else
        value[index or 0] = newValue
    end
end

local function uiItemWidth(width)
    if legacyImgui then
        imgui.PushItemWidth(width)
        return true
    end
    imgui.SetNextItemWidth(width)
    return false
end

local function uiEndItemWidth(pushed)
    if pushed then
        imgui.PopItemWidth()
    end
end
local sampEventsAvailable, sampev = pcall(require, 'lib.samp.events')
sampEventsAvailable = sampEventsAvailable and type(sampev) == 'table'
local encodingAvailable, encoding = pcall(require, 'encoding')
if encodingAvailable then
    encoding.default = 'CP1250'
end

local VERSION = 'v2.1.1-beta'
local CONFIG_NAME = 'gang_helper'
local LEGACY_CONFIG_NAME = 'gang_helper_by_semaka'
local DEFAULT_SENSITIVITY = 0.002500
local GH_CHAT_PREFIX = '{202020}G{292929}a{323232}n{3B3B3B}g {444444}H{505050}e{5C5C5C}l{686868}p{747474}e{808080}r'
local Updater = {
    -- Replace this marker once, before distributing v2.1.1-beta. Every later
    -- update is discovered and installed without another client pack.
    manifestUrl = 'PASTE_HTTPS_MANIFEST_URL_HERE',
    checkDelay = 2500,
    centerOpen = false,
    state = 'idle',
    message = '',
    available = false,
    manifest = nil,
    progress = 0.0,
    checkStarted = false
}
local Runtime = {
    maxBulletTraces = 48,
    fpsLimiterFlag = 0xBA6794,
    bulletTraces = {},
    fpsOriginalMemory = {},
    fpsMemoryCaptured = false,
    fpsFeaturesApplied = false,
    lastAppliedFpsLimit = nil,
    fpsLastCounter = nil,
    sampFpsPatches = {},
    sampFpsPatched = false,
    sampFpsPatchAttempted = false,
    sampFpsPatchStatus = 'idle',
    timeOverrideStored = false,
    nextWorldOverrideUpdate = 0,
    nextUtilityRefresh = 0,
    lastServerHour = nil,
    lastServerMinute = nil,
    lastServerWeather = nil,
    nextSkinUpdate = 0,
    changeSkinApplyPending = false,
    changeSkinDeathGraceUntil = 0,
    changeSkinIgnoreServerUntil = 0,
    bulletRendererFailed = false,
    lastServerSkin = nil,
    changeSkinRestoreModel = nil
}
local UI_LAYOUT = {
    menuWidth = 800,
    menuHeight = 600,
    headerHeight = 46,
    footerHeight = 34,
    sidebarWidth = 194,
    sidebarInset = 17,
    navigationWidth = 160,
    contentWidth = 606,
    pageHorizontalMargin = 20,
    pageTop = 18,
    pageBottomMargin = 18
}
local SENSITIVITY_X = 0xB6EC1C
local SENSITIVITY_Y = 0xB6EC18

local weapons = {
    { id = 22, name = 'Colt 45' },
    { id = 23, name = 'Silenced Pistol' },
    { id = 24, name = 'Desert Eagle' },
    { id = 25, name = 'Shotgun' },
    { id = 26, name = 'Sawnoff Shotgun' },
    { id = 27, name = 'Combat Shotgun' },
    { id = 28, name = 'UZI' },
    { id = 29, name = 'MP5' },
    { id = 30, name = 'AK-47' },
    { id = 31, name = 'M4' },
    { id = 32, name = 'TEC-9' },
    { id = 33, name = 'Rifle' },
    { id = 34, name = 'Sniper Rifle' }
}

local tradeWeapons = {
    { name = 'Deagle', command = 'deagle' },
    { name = 'M4', command = 'm4' },
    { name = 'Rifle', command = 'rifle' },
    { name = 'Shotgun', command = 'shotgun' }
}

local sensitivityWeapons = {
    { id = 24, name = 'Desert Eagle' },
    { id = 31, name = 'M4' },
    { id = 33, name = 'Rifle' },
    { id = 27, name = 'Combat Shotgun' },
    { id = 32, name = 'TEC-9' }
}

-- Effective weapon ranges used by SA-MP/GTA SA bullet weapons. A received
-- endpoint is never extended; it is only clamped when it exceeds the weapon's
-- real maximum range.
local bulletWeaponRanges = {
    [22] = 35.0, [23] = 35.0, [24] = 35.0,
    [25] = 40.0, [26] = 35.0, [27] = 40.0,
    [28] = 35.0, [29] = 45.0, [30] = 70.0,
    [31] = 90.0, [32] = 35.0, [33] = 100.0,
    [34] = 300.0, [38] = 75.0
}

local weaponOptions = {
    { id = 0, name = 'Dezactivat / Disabled' }
}
for _, weapon in ipairs(weapons) do
    weaponOptions[#weaponOptions + 1] = weapon
end

local defaults = {
    settings = {
        language = 1,
        profile = 1,
        theme = 1,
        theme_mode = 1,
        open_on_delete = true,

        bzone_cancel_key = vkeys.VK_X,
        bzone_cocaine_key = 0,
        bzone_meth_key = 0,
        bugged_cancel_key = vkeys.VK_X,
        bugged_drugs_key = 0,

        weapon_switch = false,
        sensitivity_fix = false,

        update_auto_check = true,

        infinite_run = false,
        fps_boost = false,
        fps_lock = false,
        fps_limit = 100,
        fps_unlocker = false,
        time_override = false,
        time_hour = 12,
        weather_override = false,
        weather_id = 0,
        bullet_track = false,
        bullet_track_distance = 45.0,
        bullet_track_duration = 0.85,
        change_skin = false,
        change_skin_id = 0,

        auto_accept_gun = false,
        auto_accept_delay = 250,
        sellgun_distance = 8.0,

        keyboard_overlay = false,
        mouse_overlay = false,
        keyboard_r = 237,
        keyboard_g = 85,
        keyboard_b = 101,
        mouse_r = 237,
        mouse_g = 85,
        mouse_b = 101,
        keyboard_opacity = 0.72,
        mouse_opacity = 0.72,
        overlay_scale = 1.0,
        overlay_rounding = 7.0,
        overlay_spacing = 4.0,
        overlay_border = 1.25,
        keyboard_x = 55,
        keyboard_y = 390,
        mouse_x = 650,
        mouse_y = 470
    }
}

local defaultSlotWeapons = { 24, 31, 25, 29, 34 }
for slot = 1, 5 do
    defaults.settings['weapon_slot_' .. slot] = defaultSlotWeapons[slot]
    defaults.settings['weapon_key_' .. slot] = 48 + slot
end
for _, weapon in ipairs(sensitivityWeapons) do
    defaults.settings['sens_' .. weapon.id] = DEFAULT_SENSITIVITY
    defaults.settings['sens_override_' .. weapon.id] = false
end
for _, weapon in ipairs(tradeWeapons) do
    local uppercaseName = weapon.name:upper()
    defaults.settings['request_' .. weapon.command .. '_ro'] = '/f <<< VREAU ' .. uppercaseName .. ', ID {id} >>>'
    defaults.settings['request_' .. weapon.command .. '_en'] = '/f <<< I WANT ' .. uppercaseName .. ', ID {id} >>>'
    defaults.settings['sell_' .. weapon.command] = '/sellgun {id} ' .. weapon.command
    defaults.settings['request_alias_' .. weapon.command] = '/c' .. weapon.command
    defaults.settings['sell_alias_' .. weapon.command] = '/v' .. weapon.command
end
for slot = 1, 10 do
    defaults.settings['shortcut_full_' .. slot] = ''
    defaults.settings['shortcut_alias_' .. slot] = ''
end

local function deepCopy(value)
    if type(value) ~= 'table' then
        return value
    end
    local copy = {}
    for key, item in pairs(value) do
        copy[deepCopy(key)] = deepCopy(item)
    end
    return copy
end

-- inicfg may merge loaded values into the table it receives. Keep the immutable
-- defaults separate so reset actions always restore the real factory values.
local function configFileExists(name)
    local checked, exists = pcall(function()
        local workingDirectory = getWorkingDirectory()
        return doesFileExist(workingDirectory .. '\\config\\' .. name .. '.ini')
            or doesFileExist(workingDirectory .. '/config/' .. name .. '.ini')
    end)
    return checked and exists == true
end

local configSource = CONFIG_NAME
if not configFileExists(CONFIG_NAME) and configFileExists(LEGACY_CONFIG_NAME) then
    -- One-time, non-destructive migration: load the user's old settings and
    -- save them under gang_helper.ini after validation below.
    configSource = LEGACY_CONFIG_NAME
end
local config = inicfg.load(deepCopy(defaults), configSource) or deepCopy(defaults)

local windowOpen = uiBool(false)
local currentPage = 1
local pendingPage = nil
local pageFade = 1.0
local pageFadeOut = false
local menuTargetOpen = false
local menuFade = 0.0
local animationLastTick = 0
local languageToggleAnim = config.settings.language == 2 and 1.0 or 0.0
local themeToggleAnim = config.settings.theme == 2 and 1.0 or 0.0
local uiFonts = { body = nil, semibold = nil, title = nil, hero = nil }
local captureField = nil
local captureReadyAt = 0
local baseSensitivityX = nil
local baseSensitivityY = nil
local sensitivityMemoryValid = false
local sensitivityApplied = false
local nextSensitivityUpdate = 0
local overlayFonts = {}
local overlayDragKind = nil
local overlayDragOffsetX = 0
local overlayDragOffsetY = 0
local overlayWasLeftDown = false
local overlayRendererFailed = false
local repeatedMessages = {}
local commandInlineBuffers = {}
local gameSessionStartedAt = tonumber(getGameTimer()) or 0

local translations = {
    ro = {
        home = 'Acasă',
        weapons = 'Setări arme',
        sensitivity = 'Sensibilitate',
        functions = 'Funcții',
        overlay = 'Suprapunerea tastaturii',
        overlay_nav = 'Overlay tastatură',
        shortcuts = 'Scurtături',
        settings = 'Setări',
        workspace = 'GANG HELPER',
        navigation = 'MENIU',
        account_section = 'CONT ȘI PREFERINȚE',
        all_settings = 'Toate setările',
        changes_saved = 'Modificări salvate',
        version = 'VERSIUNEA ' .. VERSION,
        welcome = 'Bine ai venit',
        hero_text = 'Tot ce ai nevoie pentru acțiunile de gang, într-un singur loc.',
        home_about_title = 'DESPRE MOD',
        home_about_text = 'Modul a fost dezvoltat ca o soluție completă, menită să îmbine într-un singur mod **funcționalitatea, rapiditatea și confortul**. Cuprinde numeroase funcții, prescurtări, setări și opțiuni utile, atent integrate pentru a face fiecare acțiune **mai ușoară, mai intuitivă și mai accesibilă**.',
        home_update_title = 'FUNCȚIE UPDATE',
        home_update_info = 'Clopoțelul din dreapta sus verifică dacă există o versiune nouă. Când apare punctul roșu, apasă clopoțelul și apoi „Actualizează acum”.',
        home_update_future = 'Actualizarea se descarcă și se instalează automat. Setările tale rămân salvate, iar modul se redeschide singur când instalarea s-a terminat.',
        home_feedback_title = 'CONTACT ȘI FEEDBACK',
        home_feedback_text = 'Ai găsit un bug sau ai o sugestie, o propunere ori o idee de modificare? Contactează-mă direct pe Discord și spune-mi ce ai vrea să îmbunătățim.',
        home_discord_label = 'CONTACT DEVELOPER',
        active_profile = 'PROFIL ACTIV',
        menu_command = 'COMANDĂ MENIU',
        cancel_bind = 'ANULARE ANIMAȚIE',
        quick_overview = 'PREZENTARE RAPIDĂ',
        module_activation = 'ACTIVARE MODULE',
        system_monitor = 'MONITORIZARE SISTEM',
        quick_actions = 'ACȚIUNI RAPIDE',
        module_status = 'STARE MODUL',
        enabled = 'Activ',
        disabled = 'Inactiv',
        configured = 'configurat',
        not_set = 'Nesetat',
        server_profile = 'PROFIL SERVER',
        server_profile_hint = 'Profilul ales controlează comenzile și bind-urile active.',
        bzone_hint = 'Comenzi dedicate serverului B-ZONE.',
        bugged_hint = 'Comenzi dedicate serverului BUGGED.',
        command_binds = 'COMENZI ȘI BIND-URI',
        cancel_animation = 'Anulare animație',
        cocaine = 'Cocaină',
        meth = 'Metamfetamină',
        drugs = 'Droguri',
        press_key = 'Apasă o tastă sau un buton mouse...',
        clear = 'Șterge',
        esc_cancel = 'ESC anulează selecția. Poți folosi și MOUSE 3, MOUSE 4 sau MOUSE 5. BACKSPACE ori DELETE șterge bind-ul.',
        weapon_switch_title = 'SETĂRI ARME',
        weapon_switch_enable = 'Activează schimbarea rapidă a armelor',
        weapon_switch_hint = 'Asociază cinci arme cu tastele numerice 1–5. Arma este selectată doar dacă o ai în inventar.',
        slot = 'Armă / Tastă',
        weapon = 'Armă',
        numeric_key = 'Tastă numerică',
        gun_tools_title = 'CERERI ȘI VÂNZĂRI DE ARME',
        auto_accept_gun = 'Acceptă automat ofertele de arme',
        auto_accept_hint = 'Detectează oferta serverului și trimite automat /accept gun ID. Dacă ești într-o mașină, oferta rămâne în așteptare și este acceptată numai după ce cobori.',
        auto_accept_delay = 'Întârziere acceptare',
        samp_events_missing = 'Auto Accept necesită biblioteca SAMP.Lua (lib.samp.events). Restul modului funcționează normal.',
        request_command = 'Comandă pentru cerere',
        request_template = 'Comandă în limba activă',
        request_hint = 'Personalizează comanda completă și scurtătura ei. Acțiunea se execută când scrii scurtătura în chat.',
        request_weapon = 'Cere',
        request_edit = 'Cerere',
        sell_edit = 'Vânzare',
        request_dialog_title = 'Configurare cerere armă',
        request_dialog_hint = 'Personalizează comanda completă. {id} va fi înlocuit automat cu ID-ul tău.',
        sell_dialog_title = 'Configurare vânzare armă',
        sell_dialog_hint = 'Personalizează comanda completă. {id}, {name} și {weapon} sunt completate automat pentru jucătorul apropiat.',
        repeat_hint = 'Anti-spam activ: aceeași formulare alternează între mesajul simplu și mesajul cu un punct la final.',
        command_template = 'Comandă completă',
        command_alias = 'Scurtătură',
        save = 'Salvează',
        send = 'Trimite',
        cancel = 'Renunță',
        sellgun_distance = 'Distanță maximă pentru țintă',
        sellgun_hint = 'Sunt acceptați doar jucători apropiați, stream-uiți, pe ecran și cu un nume vizibil. Variabile: {id}, {weapon}, {name}.',
        sell_weapon = 'Vinde',
        sell_no_target = 'Nu există un jucător eligibil în apropiere sau numele este ascuns.',
        sell_target = 'Ofertă pregătită pentru',
        request_sent = 'Cerere trimisă',
        auto_accept_sent = 'Oferta de armă a fost acceptată automat de la ID',
        sensitivity_title = 'SENSITIVITY FIX PE ARMĂ',
        sensitivity_enable = 'Activează Sensitivity Fix',
        sensitivity_hint = 'Toate armele pornesc de la sensibilitatea reală a jocului. Modifică doar valorile dorite; cele rămase la standard nu sunt atinse. Ajustarea se aplică exclusiv cât timp ții click dreapta.',
        current_weapon = 'Armă curentă',
        current_value = 'Valoare curentă',
        custom_sensitivity = 'Personalizat',
        reset_sensitivity = 'Resetează toate la standardul jocului',
        without_weapon = 'Fără armă',
        game_default = 'STANDARD JOC',
        game_default_status = 'STANDARD JOC',
        memory_unavailable = 'Adresele de sensibilitate nu au putut fi validate. Funcția rămâne oprită.',
        functions_title = 'FUNCȚII UTILE',
        functions_hint = 'Funcțiile de mai jos sunt locale, reversibile și se salvează automat.',
        infinite_run = 'Infinite Run',
        infinite_run_hint = 'Păstrează stamina la maximum până când debifezi opțiunea.',
        fps_functions = 'FUNCȚII FPS',
        fps_boost = 'FPS Boost',
        fps_boost_hint = 'Reduce procesele vizuale locale care nu țin de jucătorii sau vehiculele sincronizate SA-MP: trafic ambiental, pietoni, gunoaie, trenuri, avioane și nori, acolo unde clientul permite. Rezultatul depinde de PC și modpack.',
        fps_lock = 'FPS Lock',
        fps_lock_hint = 'Aplică local o limită precisă, fără comenzi SA-MP și fără mesaje în chat. Valoarea implicită și maximă este 100 FPS.',
        fps_limit = 'Limită maximă FPS',
        fps_unlocker = 'FPS Unlocker',
        fps_unlocker_hint = 'Elimină limitatorul GTA și limitările SA-MP compatibile, fără comenzi în chat. VSync, driverul video sau alte pluginuri pot impune în continuare o limită.',
        fps_warning = 'FPS foarte mare poate afecta fizica GTA SA; pentru peste 60 FPS este recomandat un fix dedicat de frame-rate.',
        world_overrides = 'TIMP ȘI VREME',
        time_override = 'Schimbă ora locală',
        time_hour = 'Ora din joc',
        weather_override = 'Schimbă vremea locală',
        weather_id = 'ID vreme',
        world_hint = 'Ora acceptă 0–23, iar vremea folosește ID-urile stabile GTA SA 0–22. Debifarea redă controlul jocului/serverului.',
        bullet_track_title = 'BULLET-TRACK',
        bullet_track = 'Afișează direcția gloanțelor',
        bullet_track_hint = 'Traiectorii continue cu proiectil direcțional, glow, impact și fade, colorate după jucătorul din TAB. Lungimea este limitată de raza reală a armei. Sunt procesate focurile apropiate și orice foc îndreptat spre hitboxul tău.',
        bullet_track_distance = 'Distanță locală',
        bullet_track_duration = 'Durată traseu',
        bullet_library_missing = 'Bullet-track necesită biblioteca SAMP.Lua (lib.samp.events).',
        change_skin_title = 'CHANGESKIN',
        change_skin = 'Activează skinul local',
        change_skin_id = 'Skin ID',
        change_skin_hint = 'Introdu direct orice ID valid 0–311 sau folosește - / +, câte un skin pe pas. Skinul rămâne după respawn; o schimbare intenționată primită de la server dezactivează override-ul.',
        change_skin_invalid = 'ID-ul 74 nu conține un model de jucător valid în GTA San Andreas.',
        change_skin_server = 'Serverul a schimbat skinul; Changeskin a fost dezactivat.',
        input_title = 'SUPRAPUNEREA TASTATURII',
        keyboard_enable = 'Afișează overlay-ul de tastatură',
        mouse_enable = 'Afișează overlay-ul de mouse',
        overlay_hint = 'Overlay-urile nu au fundal sau titlu. Cât timp meniul /gh este deschis, le poți trage oriunde pe ecran.',
        keyboard_color = 'Culoare tastatură',
        mouse_color = 'Culoare mouse',
        select_color = 'Deschide selectorul de culoare',
        keyboard_opacity = 'Opacitate tastatură',
        mouse_opacity = 'Opacitate mouse',
        color_picker_hint = 'Apasă pe culoare și alege vizual nuanța dorită direct din selector.',
        menu_error = 'Interfața a întâmpinat o eroare, dar scriptul a rămas activ:',
        font_error = 'Fontul cu diacritice nu a putut fi încărcat:',
        overlay_error = 'Rendererul overlay-ului a întâmpinat o eroare și a fost oprit în siguranță:',
        overlay_scale = 'Dimensiune overlay',
        overlay_rounding = 'Rotunjirea tastelor',
        overlay_spacing = 'Spațiere între taste',
        overlay_border = 'Grosimea conturului',
        overlay_style_hint = 'Tastele folosesc un contur fin, umbră discretă și colțuri rotunjite. Reglajele se aplică instant tastaturii și mouse-ului.',
        appearance = 'ASPECT',
        language = 'Limba interfeței',
        language_hint = 'Textele se schimbă instant între română și engleză.',
        theme = 'Tema interfeței',
        theme_hint = 'Tema și limba se schimbă rapid din bara de sus.',
        dark_theme = 'Temă întunecată',
        light_theme = 'Temă luminoasă',
        controls = 'CONTROL MENIU',
        open_delete = 'Deschide meniul cu tasta Del',
        open_delete_hint = 'Tasta Del este ignorată când scrii în chat sau ai un dialog SA-MP deschis.',
        reset_all = 'Resetează toate setările',
        reset_done = 'Toate setările au fost resetate.',
        notifications_update = 'NOTIFICĂRI ȘI UPDATE',
        update_check = 'Verifică update',
        update_now = 'Actualizează acum',
        update_later = 'Mai târziu',
        update_idle = 'Apasă „Verifică update” pentru a vedea dacă există o versiune nouă.',
        update_checking = 'Se caută o versiune nouă...',
        update_current = 'Gang Helper este actualizat. Nu trebuie să faci nimic.',
        update_available = 'Este disponibilă versiunea',
        update_downloading = 'Se descarcă versiunea nouă...',
        update_installing = 'Update-ul este pregătit și se instalează...',
        update_error = 'Actualizarea nu a putut fi terminată. Verifică internetul și încearcă din nou.',
        update_unconfigured = 'Verificarea automată nu este disponibilă momentan. Modul poate fi folosit în continuare.',
        update_auto_check = 'Anunță-mă automat când apare un update',
        update_changelog = 'NOUTĂȚI ÎN VERSIUNEA NOUĂ',
        update_backup = 'Update-ul se instalează automat, iar setările tale rămân salvate.',
        close = 'Închide',
        romanian = 'Română',
        english = 'English',
        overlay_drag = 'Mută-mă cu mouse-ul',
        keyboard = 'TASTATURĂ',
        mouse = 'MOUSE',
        live_data = 'DATE LIVE',
        server_name = 'SERVER',
        player_name = 'JUCĂTOR',
        session = 'SESIUNE',
        fps = 'FPS',
        ping = 'PING',
        shortcuts_title = 'SCURTĂTURI PERSONALIZATE',
        shortcuts_hint = 'Configurează până la 10 comenzi locale. Scrierea scurtăturii în chat va executa comanda completă.',
        shortcut_slot = 'Scurtătura',
        shortcuts_library_missing = 'Scurtăturile necesită biblioteca SAMP.Lua (lib.samp.events).',
        contact_developer = 'CONTACT DEVELOPER',
        discord_contact = 'Discord: semaka47',
        contact_hint = 'Contactează dezvoltatorul pentru buguri, sugestii sau modificări ale modului.',
        command_saved = 'Comanda este salvată automat',
        no_weapon = 'Nu ai arma configurată în inventar.',
        bind_saved = 'Bind salvat',
        unbound = 'FĂRĂ TASTĂ'
    },
    en = {
        home = 'Home',
        weapons = 'Weapon settings',
        sensitivity = 'Sensivity',
        functions = 'Functions',
        overlay = 'Keyboard overlay',
        overlay_nav = 'Keyboard overlay',
        shortcuts = 'Shortcuts',
        settings = 'Settings',
        workspace = 'GANG HELPER',
        navigation = 'MENU',
        account_section = 'ACCOUNT & PREFERENCES',
        all_settings = 'All settings',
        changes_saved = 'Changes saved',
        version = 'VERSION ' .. VERSION,
        welcome = 'Welcome',
        hero_text = 'Everything you need for gang activity, in one place.',
        home_about_title = 'ABOUT THE MOD',
        home_about_text = 'The mod was developed as a complete solution designed to combine **functionality, speed, and comfort** in one place. It includes numerous useful features, shortcuts, settings, and options, carefully integrated to make every action **easier, more intuitive, and more accessible**.',
        home_update_title = 'UPDATE FEATURE',
        home_update_info = 'The bell in the top-right checks for a new version. When the red dot appears, press the bell and then “Update now”.',
        home_update_future = 'The update downloads and installs automatically. Your settings stay saved, and the mod reloads when installation is complete.',
        home_feedback_title = 'CONTACT & FEEDBACK',
        home_feedback_text = 'Found a bug, have a suggestion, a proposal, or an idea for a change? Contact me directly on Discord and tell me what you would like to improve.',
        home_discord_label = 'CONTACT DEVELOPER',
        active_profile = 'ACTIVE PROFILE',
        menu_command = 'MENU COMMAND',
        cancel_bind = 'CANCEL ANIMATION',
        quick_overview = 'QUICK OVERVIEW',
        module_activation = 'MODULE ACTIVATION',
        system_monitor = 'SYSTEM MONITOR',
        quick_actions = 'QUICK ACTIONS',
        module_status = 'MODULE STATUS',
        enabled = 'Enabled',
        disabled = 'Disabled',
        configured = 'configured',
        not_set = 'Not set',
        server_profile = 'SERVER PROFILE',
        server_profile_hint = 'The selected profile controls the active commands and keybinds.',
        bzone_hint = 'Commands dedicated to the B-ZONE server.',
        bugged_hint = 'Commands dedicated to the BUGGED server.',
        command_binds = 'COMMANDS AND KEYBINDS',
        cancel_animation = 'Cancel animation',
        cocaine = 'Cocaine',
        meth = 'Methamphetamine',
        drugs = 'Drugs',
        press_key = 'Press a key or mouse button...',
        clear = 'Clear',
        esc_cancel = 'ESC cancels selection. You can also use MOUSE 3, MOUSE 4, or MOUSE 5. BACKSPACE or DELETE clears the bind.',
        weapon_switch_title = 'WEAPON SETTINGS',
        weapon_switch_enable = 'Enable Weapon Switch',
        weapon_switch_hint = 'Assign five weapons to number keys 1–5. A weapon is selected only when it is in your inventory.',
        slot = 'Weapon / Key',
        weapon = 'Weapon',
        numeric_key = 'Number key',
        gun_tools_title = 'WEAPON REQUESTS AND SALES',
        auto_accept_gun = 'Automatically accept gun offers',
        auto_accept_hint = 'Detects the server offer and automatically sends /accept gun ID. If you are in a vehicle, the offer waits and is accepted only after you get out.',
        auto_accept_delay = 'Accept delay',
        samp_events_missing = 'Auto Accept requires SAMP.Lua (lib.samp.events). The rest of the mod works normally.',
        request_command = 'Weapon request command',
        request_template = 'Active-language command',
        request_hint = 'Customize the complete command and its shortcut. The action runs when you type the shortcut in chat.',
        request_weapon = 'Request',
        request_edit = 'Request',
        sell_edit = 'Sale',
        request_dialog_title = 'Weapon request setup',
        request_dialog_hint = 'Customize the complete command. {id} is automatically replaced with your ID.',
        sell_dialog_title = 'Weapon sale setup',
        sell_dialog_hint = 'Customize the complete command. {id}, {name}, and {weapon} are filled automatically for the nearby player.',
        repeat_hint = 'Anti-spam is active: the same text alternates between the plain message and one ending in a period.',
        command_template = 'Complete command',
        command_alias = 'Shortcut',
        save = 'Save',
        send = 'Send',
        cancel = 'Cancel',
        sellgun_distance = 'Maximum target distance',
        sellgun_hint = 'Only nearby, streamed, on-screen players with a visible name are accepted. Variables: {id}, {weapon}, {name}.',
        sell_weapon = 'Sell',
        sell_no_target = 'No eligible nearby player was found or the name is hidden.',
        sell_target = 'Offer prepared for',
        request_sent = 'Request sent',
        auto_accept_sent = 'Gun offer automatically accepted from ID',
        sensitivity_title = 'PER-WEAPON SENSITIVITY FIX',
        sensitivity_enable = 'Enable Sensitivity Fix',
        sensitivity_hint = 'Every weapon starts at the game\'s real sensitivity. Change only the values you need; values left at default are never touched. Adjustments apply only while right-click aiming.',
        current_weapon = 'Current weapon',
        current_value = 'Current value',
        custom_sensitivity = 'Custom',
        reset_sensitivity = 'Reset all to the game default',
        without_weapon = 'Without weapon',
        game_default = 'GAME DEFAULT',
        game_default_status = 'GAME DEFAULT',
        memory_unavailable = 'Sensitivity addresses could not be validated. The feature remains disabled.',
        functions_title = 'UTILITY FUNCTIONS',
        functions_hint = 'The functions below are local, reversible, and saved automatically.',
        infinite_run = 'Infinite Run',
        infinite_run_hint = 'Keeps stamina at maximum until the option is disabled.',
        fps_functions = 'FPS FUNCTIONS',
        fps_boost = 'FPS Boost',
        fps_boost_hint = 'Reduces local visual work unrelated to synchronized SA-MP players or vehicles: ambient traffic, pedestrians, rubbish, trains, planes, and clouds where supported. Results depend on the PC and modpack.',
        fps_lock = 'FPS Lock',
        fps_lock_hint = 'Applies a precise local cap without SA-MP commands or chat messages. The default and maximum value is 100 FPS.',
        fps_limit = 'Maximum FPS limit',
        fps_unlocker = 'FPS Unlocker',
        fps_unlocker_hint = 'Removes the GTA limiter and compatible SA-MP caps without chat commands. VSync, the display driver, or another plugin may still impose a limit.',
        fps_warning = 'Very high FPS can affect GTA SA physics; a dedicated frame-rate fix is recommended above 60 FPS.',
        world_overrides = 'TIME AND WEATHER',
        time_override = 'Override local time',
        time_hour = 'Game hour',
        weather_override = 'Override local weather',
        weather_id = 'Weather ID',
        world_hint = 'Time accepts 0–23 and weather uses the stable GTA SA IDs 0–22. Disabling gives control back to the game/server.',
        bullet_track_title = 'BULLET-TRACK',
        bullet_track = 'Show bullet direction',
        bullet_track_hint = 'Continuous trajectories with a directional projectile, glow, impact, and fade, colored from each player’s TAB color. Length is capped to the weapon’s real range. Nearby shots and every shot aimed at your hitbox are processed.',
        bullet_track_distance = 'Local distance',
        bullet_track_duration = 'Trace duration',
        bullet_library_missing = 'Bullet-track requires SAMP.Lua (lib.samp.events).',
        change_skin_title = 'CHANGESKIN',
        change_skin = 'Enable local skin',
        change_skin_id = 'Skin ID',
        change_skin_hint = 'Enter any valid ID from 0–311 directly or use - / + one skin at a time. The skin persists after respawn; an intentional server skin change disables the override.',
        change_skin_invalid = 'ID 74 does not contain a valid player model in GTA San Andreas.',
        change_skin_server = 'The server changed your skin; Changeskin was disabled.',
        input_title = 'KEYBOARD OVERLAY',
        keyboard_enable = 'Show keyboard overlay',
        mouse_enable = 'Show mouse overlay',
        overlay_hint = 'The overlays have no background or title. While /gh is open, you can drag them anywhere on the screen.',
        keyboard_color = 'Keyboard color',
        mouse_color = 'Mouse color',
        select_color = 'Open the color picker',
        keyboard_opacity = 'Keyboard opacity',
        mouse_opacity = 'Mouse opacity',
        color_picker_hint = 'Click the color and choose the desired shade visually in the picker.',
        menu_error = 'The interface encountered an error, but the script remained active:',
        font_error = 'The font containing Romanian glyphs could not be loaded:',
        overlay_error = 'The overlay renderer encountered an error and was safely stopped:',
        overlay_scale = 'Overlay size',
        overlay_rounding = 'Key rounding',
        overlay_spacing = 'Key spacing',
        overlay_border = 'Border thickness',
        overlay_style_hint = 'Keys use a subtle outline, soft shadow, and rounded corners. Changes apply instantly to keyboard and mouse.',
        appearance = 'APPEARANCE',
        language = 'Interface language',
        language_hint = 'Text switches instantly between Romanian and English.',
        theme = 'Interface theme',
        theme_hint = 'Theme and language can be changed quickly from the top bar.',
        dark_theme = 'Dark theme',
        light_theme = 'Light theme',
        controls = 'MENU CONTROL',
        open_delete = 'Open the menu with the Del key',
        open_delete_hint = 'The Del key is ignored while typing in chat or while a SA-MP dialog is open.',
        reset_all = 'Reset all settings',
        reset_done = 'All settings have been reset.',
        notifications_update = 'NOTIFICATIONS & UPDATE',
        update_check = 'Check for updates',
        update_now = 'Update now',
        update_later = 'Later',
        update_idle = 'Press “Check for updates” to see whether a new version is available.',
        update_checking = 'Looking for a new version...',
        update_current = 'Gang Helper is up to date. You do not need to do anything.',
        update_available = 'Available version',
        update_downloading = 'Downloading the new version...',
        update_installing = 'The update is ready and is being installed...',
        update_error = 'The update could not be completed. Check your connection and try again.',
        update_unconfigured = 'Automatic update checks are temporarily unavailable. The mod can still be used normally.',
        update_auto_check = 'Notify me automatically when an update appears',
        update_changelog = 'WHAT IS NEW',
        update_backup = 'The update installs automatically and keeps your settings.',
        close = 'Close',
        romanian = 'Romana',
        english = 'English',
        overlay_drag = 'Drag me with the mouse',
        keyboard = 'KEYBOARD',
        mouse = 'MOUSE',
        live_data = 'LIVE DATA',
        server_name = 'SERVER',
        player_name = 'PLAYER',
        session = 'SESSION',
        fps = 'FPS',
        ping = 'PING',
        shortcuts_title = 'CUSTOM SHORTCUTS',
        shortcuts_hint = 'Configure up to 10 local commands. Typing the shortcut in chat executes the complete command.',
        shortcut_slot = 'Shortcut',
        shortcuts_library_missing = 'Shortcuts require SAMP.Lua (lib.samp.events).',
        contact_developer = 'CONTACT DEVELOPER',
        discord_contact = 'Discord: semaka47',
        contact_hint = 'Contact the developer for bugs, suggestions, or changes to the mod.',
        command_saved = 'The command is saved automatically',
        no_weapon = 'The configured weapon is not in your inventory.',
        bind_saved = 'Keybind saved',
        unbound = 'UNBOUND'
    }
}

local function color(r, g, b, a)
    return imgui.ImVec4(r / 255, g / 255, b / 255, a or 1.0)
end

local themes = {
    {
        ro = 'Întunecată', en = 'Dark', mode = 'dark',
        accent = color(245, 245, 247), hover = color(255, 255, 255), active = color(216, 216, 220),
        bg = color(10, 10, 12), side = color(13, 13, 15), panel = color(16, 17, 18),
        header = color(18, 18, 22), control = color(20, 20, 23), controlHover = color(28, 28, 32),
        panelHover = color(30, 30, 34), buttonActive = color(39, 39, 44), border = color(39, 39, 44),
        text = color(241, 241, 244), muted = color(143, 143, 151), strong = color(255, 255, 255),
        avatarBg = color(245, 245, 247), avatarText = color(20, 20, 22), separator = color(31, 31, 36),
        glass = color(10, 10, 12), glassStrong = color(13, 13, 15), glassSoft = color(20, 20, 23),
        glassBorder = color(39, 39, 44), shadow = color(0, 0, 0, 0.22), glow = color(0, 0, 0, 0),
        green = color(45, 210, 91), blue = color(47, 148, 255)
    },
    {
        ro = 'Luminoasă', en = 'Light', mode = 'light',
        accent = color(28, 28, 31), hover = color(0, 0, 0), active = color(68, 68, 72),
        bg = color(244, 244, 246), side = color(237, 237, 240), panel = color(252, 252, 253),
        header = color(235, 235, 238), control = color(232, 232, 235), controlHover = color(220, 220, 224),
        panelHover = color(218, 218, 222), buttonActive = color(205, 205, 210), border = color(205, 205, 210),
        text = color(28, 28, 31), muted = color(100, 100, 106), strong = color(0, 0, 0),
        avatarBg = color(28, 28, 31), avatarText = color(255, 255, 255), separator = color(214, 214, 218),
        glass = color(244, 244, 246), glassStrong = color(237, 237, 240), glassSoft = color(232, 232, 235),
        glassBorder = color(205, 205, 210), shadow = color(0, 0, 0, 0.10), glow = color(0, 0, 0, 0),
        green = color(36, 190, 82), blue = color(0, 122, 255)
    }
}

local weaponById = {}
for _, weapon in ipairs(weapons) do
    weaponById[weapon.id] = weapon
end

local sensitivityWeaponById = {}
for _, weapon in ipairs(sensitivityWeapons) do
    sensitivityWeaponById[weapon.id] = weapon
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function validWeaponOption(id)
    if id == 0 then
        return true
    end
    return weaponById[id] ~= nil
end

local function clampSettings()
    local s = config.settings
    s.language = clamp(tonumber(s.language) or 1, 1, 2)
    s.profile = clamp(tonumber(s.profile) or 1, 1, 2)
    s.theme_mode = clamp(tonumber(s.theme_mode) or 1, 1, #themes)
    s.theme = s.theme_mode
    if s.open_on_delete == nil then
        s.open_on_delete = s.open_on_l ~= false
    end
    s.open_on_delete = s.open_on_delete == true
    s.weapon_switch = s.weapon_switch == true
    s.sensitivity_fix = s.sensitivity_fix == true
    s.update_auto_check = s.update_auto_check ~= false
    s.infinite_run = s.infinite_run == true
    s.fps_boost = s.fps_boost == true
    s.fps_lock = s.fps_lock == true
    s.fps_limit = tonumber(s.fps_limit) or defaults.settings.fps_limit
    if s.fps_limit == 90 then
        s.fps_limit = 100
    end
    s.fps_limit = clamp(s.fps_limit, 20, 100)
    s.fps_unlocker = s.fps_unlocker == true
    if s.fps_lock and s.fps_unlocker then
        s.fps_unlocker = false
    end
    s.time_override = s.time_override == true
    s.time_hour = clamp(tonumber(s.time_hour) or defaults.settings.time_hour, 0, 23)
    s.weather_override = s.weather_override == true
    s.weather_id = clamp(tonumber(s.weather_id) or defaults.settings.weather_id, 0, 22)
    s.bullet_track = s.bullet_track == true and sampEventsAvailable
    s.bullet_track_distance = clamp(tonumber(s.bullet_track_distance)
        or defaults.settings.bullet_track_distance, 10.0, 100.0)
    s.bullet_track_duration = clamp(tonumber(s.bullet_track_duration)
        or defaults.settings.bullet_track_duration, 0.25, 2.0)
    s.change_skin = s.change_skin == true
    s.change_skin_id = clamp(tonumber(s.change_skin_id) or defaults.settings.change_skin_id, 0, 311)
    s.auto_accept_gun = s.auto_accept_gun == true
    if s.auto_accept_gun and not sampEventsAvailable then
        s.auto_accept_gun = false
    end
    s.auto_accept_delay = clamp(tonumber(s.auto_accept_delay) or 250, 0, 1500)
    for _, weapon in ipairs(tradeWeapons) do
        local roField = 'request_' .. weapon.command .. '_ro'
        local enField = 'request_' .. weapon.command .. '_en'
        local sellField = 'sell_' .. weapon.command
        local requestAliasField = 'request_alias_' .. weapon.command
        local sellAliasField = 'sell_alias_' .. weapon.command
        s[roField] = tostring(s[roField] or defaults.settings[roField])
        s[enField] = tostring(s[enField] or defaults.settings[enField])
        s[sellField] = tostring(s[sellField] or defaults.settings[sellField])
        s[requestAliasField] = tostring(s[requestAliasField] or defaults.settings[requestAliasField])
        s[sellAliasField] = tostring(s[sellAliasField] or defaults.settings[sellAliasField])
        if s[roField] == '/f [<<< Am nevoie de ' .. weapon.name .. ', ID {id} >>>]' then
            s[roField] = defaults.settings[roField]
        end
        if s[enField] == '/f [<<< I need ' .. weapon.name .. ', ID {id} >>>]' then
            s[enField] = defaults.settings[enField]
        end
    end
    for slot = 1, 10 do
        local fullField = 'shortcut_full_' .. slot
        local aliasField = 'shortcut_alias_' .. slot
        s[fullField] = tostring(s[fullField] or '')
        s[aliasField] = tostring(s[aliasField] or '')
    end
    s.sellgun_distance = clamp(tonumber(s.sellgun_distance) or 8.0, 2.0, 25.0)
    s.keyboard_overlay = s.keyboard_overlay == true
    s.mouse_overlay = s.mouse_overlay == true
    for _, prefix in ipairs({ 'keyboard', 'mouse' }) do
        s[prefix .. '_r'] = clamp(tonumber(s[prefix .. '_r']) or defaults.settings[prefix .. '_r'], 0, 255)
        s[prefix .. '_g'] = clamp(tonumber(s[prefix .. '_g']) or defaults.settings[prefix .. '_g'], 0, 255)
        s[prefix .. '_b'] = clamp(tonumber(s[prefix .. '_b']) or defaults.settings[prefix .. '_b'], 0, 255)
        s[prefix .. '_opacity'] = clamp(tonumber(s[prefix .. '_opacity']) or defaults.settings[prefix .. '_opacity'], 0.0, 1.0)
    end
    s.overlay_scale = clamp(tonumber(s.overlay_scale) or 1.0, 0.25, 1.5)
    s.overlay_rounding = clamp(tonumber(s.overlay_rounding) or 7.0, 0.0, 12.0)
    s.overlay_spacing = clamp(tonumber(s.overlay_spacing) or 4.0, 2.0, 8.0)
    s.overlay_border = clamp(tonumber(s.overlay_border) or 1.25, 0.75, 3.0)
    s.keyboard_x = tonumber(s.keyboard_x) or 55
    s.keyboard_y = tonumber(s.keyboard_y) or 390
    s.mouse_x = tonumber(s.mouse_x) or 650
    s.mouse_y = tonumber(s.mouse_y) or 470

    local keyFields = {
        'bzone_cancel_key', 'bzone_cocaine_key', 'bzone_meth_key',
        'bugged_cancel_key', 'bugged_drugs_key'
    }
    for _, field in ipairs(keyFields) do
        s[field] = clamp(tonumber(s[field]) or defaults.settings[field], 0, 255)
    end

    for slot = 1, 5 do
        local weaponField = 'weapon_slot_' .. slot
        local keyField = 'weapon_key_' .. slot
        s[weaponField] = tonumber(s[weaponField]) or defaults.settings[weaponField]
        if not validWeaponOption(s[weaponField]) then
            s[weaponField] = 0
        end
        s[keyField] = clamp(tonumber(s[keyField]) or defaults.settings[keyField], 49, 53)
    end

    for _, weapon in ipairs(sensitivityWeapons) do
        local field = 'sens_' .. weapon.id
        local overrideField = 'sens_override_' .. weapon.id
        s[field] = clamp(tonumber(s[field]) or defaults.settings[field], 0.000312, 0.005000)
        s[overrideField] = s[overrideField] == true
    end
end

clampSettings()
inicfg.save(config, CONFIG_NAME)

local keyboardColorPicker = uiFloat4()
local mouseColorPicker = uiFloat4()
local romanianGlyphRanges = ffi.new('unsigned short[5]', { 0x0020, 0x024F, 0x2013, 0x2014, 0 })
local legacyRomanianGlyphRanges = nil

local function setTextBuffer(buffer, size, value)
    local text = tostring(value or '')
    if legacyImgui then
        buffer.v = text:sub(1, size - 1)
    else
        ffi.fill(buffer, size, 0)
        ffi.copy(buffer, text, math.min(#text, size - 1))
    end
end

local function getTextBuffer(buffer)
    return legacyImgui and buffer.v or ffi.string(buffer)
end

local function getInlineCommandBuffer(field)
    if not commandInlineBuffers[field] then
        commandInlineBuffers[field] = uiBuffer(257)
        setTextBuffer(commandInlineBuffers[field], 257, config.settings[field])
    end
    return commandInlineBuffers[field]
end

local function syncTextBuffers()
    uiSet(keyboardColorPicker, config.settings.keyboard_r / 255, 0)
    uiSet(keyboardColorPicker, config.settings.keyboard_g / 255, 1)
    uiSet(keyboardColorPicker, config.settings.keyboard_b / 255, 2)
    uiSet(keyboardColorPicker, 1.0, 3)
    uiSet(mouseColorPicker, config.settings.mouse_r / 255, 0)
    uiSet(mouseColorPicker, config.settings.mouse_g / 255, 1)
    uiSet(mouseColorPicker, config.settings.mouse_b / 255, 2)
    uiSet(mouseColorPicker, 1.0, 3)
end

syncTextBuffers()

local function tr(key)
    local language = config.settings.language == 2 and translations.en or translations.ro
    return language[key] or key
end

local function toGameEncoding(text)
    text = tostring(text or '')
    if encodingAvailable and encoding.UTF8 then
        return encoding.UTF8:decode(text)
    end
    return text
end

local function profileName()
    return config.settings.profile == 1 and 'B-ZONE' or 'BUGGED'
end

local function saveSettings()
    inicfg.save(config, CONFIG_NAME)
end

local function smoothValue(current, target, speed, deltaTime)
    local factor = 1.0 - math.exp(-speed * deltaTime)
    return current + (target - current) * factor
end

local function menuShouldRender()
    return menuTargetOpen or menuFade > 0.01
end

local function requestMenu(open)
    menuTargetOpen = open == true
    if menuTargetOpen then
        uiSet(windowOpen, true)
    else
        captureField = nil
    end
end

local function toggleMenu()
    requestMenu(not menuTargetOpen)
end

local function requestPage(page)
    if page ~= currentPage and page ~= pendingPage then
        pendingPage = page
        pageFadeOut = true
    end
end

local function updateInterfaceAnimations()
    local now = getGameTimer()
    local deltaTime = animationLastTick > 0 and clamp((now - animationLastTick) / 1000.0, 0.0, 0.05) or (1.0 / 60.0)
    animationLastTick = now

    menuFade = smoothValue(menuFade, menuTargetOpen and 1.0 or 0.0, 12.0, deltaTime)
    if menuTargetOpen and menuFade > 0.995 then
        menuFade = 1.0
    elseif not menuTargetOpen and menuFade < 0.01 then
        menuFade = 0.0
        uiSet(windowOpen, false)
    end

    languageToggleAnim = smoothValue(languageToggleAnim,
        config.settings.language == 2 and 1.0 or 0.0, 14.0, deltaTime)
    themeToggleAnim = smoothValue(themeToggleAnim,
        config.settings.theme == 2 and 1.0 or 0.0, 14.0, deltaTime)

    if pendingPage and pageFadeOut then
        pageFade = math.max(0.0, pageFade - deltaTime * 10.0)
        if pageFade <= 0.0 then
            currentPage = pendingPage
            pendingPage = nil
            pageFadeOut = false
        end
    else
        pageFade = math.min(1.0, pageFade + deltaTime * 10.0)
    end
end

local function applyTheme(index)
    local theme = themes[index] or themes[1]
    local style = imgui.GetStyle()
    local colors = style.Colors

    local function setStyle(name, value)
        pcall(function()
            style[name] = value
        end)
    end
    local function setColor(name, value)
        if imgui.Col[name] ~= nil then
            colors[imgui.Col[name]] = value
        end
    end

    setStyle('WindowPadding', imgui.ImVec2(0, 0))
    setStyle('WindowRounding', 12.0)
    setStyle('ChildRounding', 9.0)
    setStyle('ChildWindowRounding', 9.0)
    setStyle('FrameRounding', 7.0)
    setStyle('PopupRounding', 8.0)
    setStyle('ScrollbarRounding', 7.0)
    setStyle('GrabRounding', 12.0)
    setStyle('WindowBorderSize', 0.0)
    setStyle('ChildBorderSize', 0.0)
    setStyle('FrameBorderSize', 0.0)
    setStyle('FramePadding', imgui.ImVec2(9, 5))
    setStyle('ItemSpacing', imgui.ImVec2(7, 7))
    setStyle('ItemInnerSpacing', imgui.ImVec2(7, 6))
    setStyle('ScrollbarSize', 8.0)
    setStyle('GrabMinSize', 8.0)
    setStyle('ButtonTextAlign', imgui.ImVec2(0.5, 0.50))
    setStyle('AntiAliasedLines', true)
    setStyle('AntiAliasedFill', true)

    setColor('Text', theme.text)
    setColor('TextDisabled', theme.muted)
    setColor('WindowBg', theme.bg)
    setColor('ChildBg', theme.bg)
    setColor('ChildWindowBg', theme.bg)
    setColor('PopupBg', theme.panel)
    setColor('Border', color(0, 0, 0, 0))
    setColor('BorderShadow', color(0, 0, 0, 0))
    setColor('FrameBg', theme.control)
    setColor('FrameBgHovered', theme.controlHover)
    setColor('FrameBgActive', theme.buttonActive)
    setColor('TitleBg', theme.bg)
    setColor('TitleBgActive', theme.bg)
    setColor('Button', theme.control)
    setColor('ButtonHovered', theme.panelHover)
    setColor('ButtonActive', theme.buttonActive)
    setColor('Header', theme.panelHover)
    setColor('HeaderHovered', theme.panelHover)
    setColor('HeaderActive', theme.buttonActive)
    setColor('CheckMark', theme.blue)
    setColor('SliderGrab', theme.accent)
    setColor('SliderGrabActive', theme.hover)
    setColor('ScrollbarBg', color(0, 0, 0, 0))
    setColor('ScrollbarGrab', theme.border)
    setColor('ScrollbarGrabHovered', theme.accent)
    setColor('ScrollbarGrabActive', theme.active)
    setColor('Separator', theme.separator)
    setColor('ResizeGrip', color(0, 0, 0, 0))
    setColor('ResizeGripHovered', color(0, 0, 0, 0))
    setColor('ResizeGripActive', color(0, 0, 0, 0))
end

local function pushFont(font)
    if font ~= nil then
        imgui.PushFont(font)
        return true
    end
    return false
end

local function popFont(pushed)
    if pushed then
        imgui.PopFont()
    end
end

local function mutedText(text)
    imgui.TextColored(themes[config.settings.theme].muted, text)
end

local function mutedWrapped(text, width)
    imgui.PushTextWrapPos(width or imgui.GetContentRegionAvail().x)
    mutedText(text)
    imgui.PopTextWrapPos()
end

local function richWrappedText(text, width)
    local theme = themes[config.settings.theme]
    local start = imgui.GetCursorScreenPos()
    local drawList = imgui.GetWindowDrawList()
    local maxWidth = math.max(40, width or imgui.GetContentRegionAvail().x)
    local x, y = start.x, start.y
    local lineHeight = imgui.CalcTextSize('Ag').y + 4
    local bold = false

    for token in tostring(text or ''):gmatch('%S+') do
        local startsBold = token:sub(1, 2) == '**'
        if startsBold then
            bold = true
            token = token:sub(3)
        end
        local endsBold = token:find('**', 1, true) ~= nil
        if endsBold then
            token = token:gsub('%*%*', '')
        end
        if token ~= '' then
            local fontPushed = pushFont(bold and uiFonts.semibold or uiFonts.body)
            local word = token .. ' '
            local wordSize = imgui.CalcTextSize(word)
            if x > start.x and x + wordSize.x > start.x + maxWidth then
                x = start.x
                y = y + lineHeight
            end
            drawList:AddText(imgui.ImVec2(x, y),
                imgui.GetColorU32(bold and theme.text or theme.muted), word)
            x = x + wordSize.x
            popFont(fontPushed)
        end
        if endsBold then
            bold = false
        end
    end
    imgui.Dummy(imgui.ImVec2(maxWidth, (y - start.y) + lineHeight))
end

local function sectionTitle(text)
    local theme = themes[config.settings.theme]
    local cursorX = imgui.GetCursorPosX()
    local screenPos = imgui.GetCursorScreenPos()
    imgui.GetWindowDrawList():AddRectFilled(screenPos,
        imgui.ImVec2(screenPos.x + 3, screenPos.y + 15), imgui.GetColorU32(theme.accent), 2)
    imgui.SetCursorPosX(cursorX + 13)
    local fontPushed = pushFont(uiFonts.semibold)
    imgui.TextColored(theme.text, text)
    popFont(fontPushed)
    imgui.Spacing()
end

local function getLocalPlayerName()
    local found, playerId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if found then
        return sampGetPlayerNickname(playerId)
    end
    return 'Player'
end

local function getLocalPlayerId()
    local found, playerId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    return found and playerId or -1
end

local function shortened(text, maximum)
    text = tostring(text or '')
    local byteIndex, characters = 1, 0
    while byteIndex <= #text and characters < maximum do
        local firstByte = text:byte(byteIndex)
        local sequenceLength = firstByte >= 240 and 4
            or firstByte >= 224 and 3
            or firstByte >= 192 and 2
            or 1
        byteIndex = byteIndex + sequenceLength
        characters = characters + 1
    end
    if byteIndex > #text then
        return text
    end

    byteIndex, characters = 1, 0
    local visibleCharacters = math.max(1, maximum - 3)
    while byteIndex <= #text and characters < visibleCharacters do
        local firstByte = text:byte(byteIndex)
        local sequenceLength = firstByte >= 240 and 4
            or firstByte >= 224 and 3
            or firstByte >= 192 and 2
            or 1
        byteIndex = byteIndex + sequenceLength
        characters = characters + 1
    end
    return text:sub(1, byteIndex - 1) .. '...'
end

local function fittedText(text, maximumWidth)
    text = tostring(text or '')
    if imgui.CalcTextSize(text).x <= maximumWidth then
        return text
    end
    for maximum = 36, 4, -1 do
        local candidate = shortened(text, maximum)
        if imgui.CalcTextSize(candidate).x <= maximumWidth then
            return candidate
        end
    end
    return '...'
end

local function currentServerLabel()
    if type(sampGetCurrentServerName) == 'function' then
        local ok, name = pcall(sampGetCurrentServerName)
        if ok and type(name) == 'string' and name ~= '' then
            return name
        end
    end
    if type(sampGetCurrentServerAddress) == 'function' then
        local ok, address, port = pcall(sampGetCurrentServerAddress)
        if ok and type(address) == 'string' and address ~= '' then
            if port ~= nil and tostring(port) ~= '' and tonumber(port) ~= 0 then
                return address .. ':' .. tostring(port)
            end
            return address
        end
    end
    return profileName()
end

local function currentFrameRate()
    local ok, value = pcall(function()
        return imgui.GetIO().Framerate
    end)
    return ok and math.max(0, math.floor((tonumber(value) or 0) + 0.5)) or 0
end

local liveServerCache = ''
local nextLiveInfoRefresh = 0
local function liveSidebarData()
    local now = getGameTimer()
    if liveServerCache == '' or now >= nextLiveInfoRefresh then
        liveServerCache = currentServerLabel()
        nextLiveInfoRefresh = now + 500
    end
    return liveServerCache
end

local function currentSessionLabel()
    local elapsed = nil
    if processClockKernel and processStartedAt100ns then
        local clockOk, processElapsed = pcall(function()
            local systemTime = ffi.new('GH_FILETIME[1]')
            processClockKernel.GetSystemTimeAsFileTime(systemTime)
            local now100ns = tonumber(systemTime[0].dwHighDateTime) * 4294967296
                + tonumber(systemTime[0].dwLowDateTime)
            return math.max(0, (now100ns - processStartedAt100ns) / 10000)
        end)
        if clockOk then
            elapsed = processElapsed
        end
    end
    if elapsed == nil then
        local now = tonumber(getGameTimer()) or gameSessionStartedAt
        elapsed = now - gameSessionStartedAt
        if elapsed < 0 then
            elapsed = elapsed + 4294967296
        end
    end
    local totalSeconds = math.max(0, math.floor(elapsed / 1000))
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = totalSeconds % 60
    return string.format('%02d:%02d:%02d', hours, minutes, seconds)
end

local function ghChat(message)
    local whiteMessage = tostring(message or ''):gsub('{%x%x%x%x%x%x}', '')
    sampAddChatMessage(toGameEncoding(GH_CHAT_PREFIX .. ' {FFFFFF}' .. whiteMessage), -1)
end

local function showInjectionMessage()
    local message
    if config.settings.language == 2 then
        message = GH_CHAT_PREFIX
            .. ' {FFFFFF}loaded successfully. Use the {808080}Del {FFFFFF}key or the {808080}/gh'
    else
        message = GH_CHAT_PREFIX
            .. ' {FFFFFF}s-a incarcat cu succes. Foloseste tasta {808080}Del {FFFFFF}sau comanda {808080}/gh'
    end
    sampAddChatMessage(toGameEncoding(message), -1)
end

Updater.sha256K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

function Updater.sha256(data)
    local lengthInBits = #data * 8
    data = data .. string.char(0x80)
    data = data .. string.rep('\0', (56 - (#data % 64)) % 64)
    local high = math.floor(lengthInBits / 4294967296)
    local low = lengthInBits % 4294967296
    data = data .. string.char(
        bit.band(bit.rshift(high, 24), 0xff), bit.band(bit.rshift(high, 16), 0xff),
        bit.band(bit.rshift(high, 8), 0xff), bit.band(high, 0xff),
        bit.band(bit.rshift(low, 24), 0xff), bit.band(bit.rshift(low, 16), 0xff),
        bit.band(bit.rshift(low, 8), 0xff), bit.band(low, 0xff))

    local h = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    }
    for offset = 1, #data, 64 do
        local w = {}
        for index = 0, 15 do
            local position = offset + index * 4
            local a, b, c, d = data:byte(position, position + 3)
            w[index] = bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(c, 8), d)
        end
        for index = 16, 63 do
            local s0 = bit.bxor(bit.ror(w[index - 15], 7), bit.ror(w[index - 15], 18),
                bit.rshift(w[index - 15], 3))
            local s1 = bit.bxor(bit.ror(w[index - 2], 17), bit.ror(w[index - 2], 19),
                bit.rshift(w[index - 2], 10))
            w[index] = bit.tobit(w[index - 16] + s0 + w[index - 7] + s1)
        end

        local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
        for index = 0, 63 do
            local sum1 = bit.bxor(bit.ror(e, 6), bit.ror(e, 11), bit.ror(e, 25))
            local choose = bit.bxor(bit.band(e, f), bit.band(bit.bnot(e), g))
            local temp1 = bit.tobit(hh + sum1 + choose + Updater.sha256K[index + 1] + w[index])
            local sum0 = bit.bxor(bit.ror(a, 2), bit.ror(a, 13), bit.ror(a, 22))
            local majority = bit.bxor(bit.band(a, b), bit.band(a, c), bit.band(b, c))
            local temp2 = bit.tobit(sum0 + majority)
            hh, g, f, e, d, c, b, a = g, f, e, bit.tobit(d + temp1), c, b, a, bit.tobit(temp1 + temp2)
        end
        h[1] = bit.tobit(h[1] + a)
        h[2] = bit.tobit(h[2] + b)
        h[3] = bit.tobit(h[3] + c)
        h[4] = bit.tobit(h[4] + d)
        h[5] = bit.tobit(h[5] + e)
        h[6] = bit.tobit(h[6] + f)
        h[7] = bit.tobit(h[7] + g)
        h[8] = bit.tobit(h[8] + hh)
    end
    local result = {}
    for index = 1, 8 do
        result[index] = bit.tohex(h[index], 8)
    end
    return table.concat(result)
end

function Updater.readBinaryFile(path)
    local handle = io.open(path, 'rb')
    if not handle then
        return nil
    end
    local data = handle:read('*a')
    handle:close()
    return data
end

function Updater.updaterConfigured()
    return type(Updater.manifestUrl) == 'string'
        and Updater.manifestUrl:match('^https://') ~= nil
        and Updater.manifestUrl:find('PASTE_HTTPS', 1, true) == nil
end

function Updater.versionParts(value)
    local parts = {}
    for number in tostring(value or ''):gmatch('%d+') do
        parts[#parts + 1] = tonumber(number)
    end
    return parts
end

function Updater.compareVersions(remote, installed)
    local remoteParts, installedParts = Updater.versionParts(remote), Updater.versionParts(installed)
    for index = 1, math.max(#remoteParts, #installedParts) do
        local left, right = remoteParts[index] or 0, installedParts[index] or 0
        if left ~= right then
            return left > right and 1 or -1
        end
    end
    local remotePrerelease = tostring(remote):find('-', 1, true) ~= nil
    local installedPrerelease = tostring(installed):find('-', 1, true) ~= nil
    if remotePrerelease ~= installedPrerelease then
        return remotePrerelease and -1 or 1
    end
    return 0
end

function Updater.updateChangelogText(manifest)
    if type(manifest) ~= 'table' then
        return ''
    end
    local value = config.settings.language == 2 and manifest.changelog_en or manifest.changelog_ro
    value = value or manifest.changelog
    if type(value) == 'table' then
        local lines = {}
        for _, line in ipairs(value) do
            lines[#lines + 1] = '- ' .. tostring(line)
        end
        return table.concat(lines, '\n')
    end
    return tostring(value or '')
end

function Updater.setUpdateError(reason)
    Updater.state = Updater.updaterConfigured() and 'error' or 'unconfigured'
    Updater.message = tostring(reason or '')
    Updater.available = false
    Updater.progress = 0.0
end

function Updater.processUpdateManifest(path)
    local raw = Updater.readBinaryFile(path)
    pcall(os.remove, path)
    if not raw or raw == '' then
        Updater.setUpdateError('manifest gol / empty manifest')
        return
    end
    local decodedOk, manifest = pcall(decodeJson, raw)
    if not decodedOk or type(manifest) ~= 'table' then
        Updater.setUpdateError('manifest JSON invalid')
        return
    end
    local version = tostring(manifest.version or '')
    local downloadUrl = tostring(manifest.download_url or manifest.download or '')
    local expectedHash = tostring(manifest.sha256 or ''):lower()
    if version == '' or not downloadUrl:match('^https://') or not expectedHash:match('^[0-9a-f]+$')
            or #expectedHash ~= 64 then
        Updater.setUpdateError('câmpuri manifest invalide / invalid manifest fields')
        return
    end
    Updater.manifest = manifest
    if Updater.compareVersions(version, VERSION) > 0 then
        Updater.available = true
        Updater.state = 'available'
        Updater.message = version
    else
        Updater.available = false
        Updater.state = 'current'
        Updater.message = VERSION
    end
end

function Updater.checkForUpdates()
    if Updater.state == 'checking' or Updater.state == 'downloading' or Updater.state == 'installing' then
        return
    end
    Updater.checkStarted = true
    Updater.manifest = nil
    Updater.available = false
    Updater.progress = 0.0
    if not Updater.updaterConfigured() then
        Updater.setUpdateError('')
        return
    end
    local scriptPath = thisScript().path
    local manifestPath = scriptPath .. '.gh-manifest.tmp.json'
    pcall(os.remove, manifestPath)
    Updater.state = 'checking'
    Updater.message = ''
    local completed = false
    local startedOk = pcall(downloadUrlToFile, Updater.manifestUrl, manifestPath,
        function(_, status)
            if (status == downloadStatus.STATUS_ENDDOWNLOADDATA
                    or status == downloadStatus.STATUSEX_ENDDOWNLOAD) and not completed then
                completed = true
                if doesFileExist(manifestPath) then
                    Updater.processUpdateManifest(manifestPath)
                else
                    Updater.setUpdateError('descărcarea manifestului a eșuat / manifest download failed')
                end
            end
        end)
    if not startedOk then
        pcall(os.remove, manifestPath)
        Updater.setUpdateError('downloadUrlToFile indisponibil')
    else
        lua_thread.create(function()
            wait(15000)
            if Updater.state == 'checking' and not completed then
                completed = true
                pcall(os.remove, manifestPath)
                Updater.setUpdateError('timeout la verificarea manifestului')
            end
        end)
    end
end

function Updater.installAvailableUpdate()
    if not Updater.available or type(Updater.manifest) ~= 'table' or Updater.state == 'downloading' then
        return
    end
    local scriptPath = thisScript().path
    local temporaryPath = scriptPath .. '.gh-update.tmp'
    local backupPath = scriptPath .. '.gh-backup.lua'
    pcall(os.remove, temporaryPath)
    Updater.state = 'downloading'
    Updater.progress = 0.0
    local completed = false
    local downloadUrl = tostring(Updater.manifest.download_url or Updater.manifest.download)
    local startedOk = pcall(downloadUrlToFile, downloadUrl, temporaryPath,
        function(_, status, downloaded, total)
            if status == downloadStatus.STATUS_DOWNLOADINGDATA and tonumber(total) and tonumber(total) > 0 then
                Updater.progress = clamp((tonumber(downloaded) or 0) / tonumber(total), 0.0, 1.0)
            elseif (status == downloadStatus.STATUS_ENDDOWNLOADDATA
                    or status == downloadStatus.STATUSEX_ENDDOWNLOAD) and not completed then
                completed = true
                local data = Updater.readBinaryFile(temporaryPath)
                local expectedHash = tostring(Updater.manifest.sha256 or ''):lower()
                local expectedVersion = tostring(Updater.manifest.version or '')
                if not data or #data < 1000 or not data:find('script_name', 1, true)
                        or not data:find('function main', 1, true)
                        or not data:find(expectedVersion, 1, true) then
                    pcall(os.remove, temporaryPath)
                    Updater.setUpdateError('fișierul descărcat nu este un script Gang Helper valid')
                    return
                end
                local compiledChunk, compileError = loadfile(temporaryPath)
                if not compiledChunk then
                    pcall(os.remove, temporaryPath)
                    Updater.setUpdateError('sintaxă Lua invalidă: ' .. tostring(compileError))
                    return
                end
                if Updater.sha256(data) ~= expectedHash then
                    pcall(os.remove, temporaryPath)
                    Updater.setUpdateError('SHA-256 nu corespunde; instalarea a fost anulată')
                    return
                end

                Updater.state = 'installing'
                pcall(os.remove, backupPath)
                local backedUp, backupError = os.rename(scriptPath, backupPath)
                if not backedUp then
                    pcall(os.remove, temporaryPath)
                    Updater.setUpdateError('backup eșuat: ' .. tostring(backupError))
                    return
                end
                local installed, installError = os.rename(temporaryPath, scriptPath)
                if not installed then
                    os.rename(backupPath, scriptPath)
                    Updater.setUpdateError('instalare eșuată: ' .. tostring(installError))
                    return
                end
                Updater.available = false
                Updater.progress = 1.0
                lua_thread.create(function()
                    wait(650)
                    thisScript():reload()
                end)
            end
        end)
    if not startedOk then
        pcall(os.remove, temporaryPath)
        Updater.setUpdateError('downloadUrlToFile indisponibil')
    else
        lua_thread.create(function()
            wait(60000)
            if Updater.state == 'downloading' and not completed then
                completed = true
                pcall(os.remove, temporaryPath)
                Updater.setUpdateError('timeout la descărcarea update-ului')
            end
        end)
    end
end

local function stripColorTags(text)
    return tostring(text or ''):gsub('{%x%x%x%x%x%x}', '')
end

local function findConnectedPlayerByName(text)
    local haystack = stripColorTags(text):lower()
    local localId = getLocalPlayerId()
    for playerId = 0, 1003 do
        if playerId ~= localId and sampIsPlayerConnected(playerId) then
            local nickname = sampGetPlayerNickname(playerId)
            if nickname and nickname ~= '' and haystack:find(nickname:lower(), 1, true) then
                return playerId
            end
        end
    end
    return nil
end

local function extractGunOfferPlayerId(text)
    local clean = stripColorTags(text)
    local lower = clean:lower()
    local isOffer = lower:find('/accept gun', 1, true)
        or ((lower:find('sell', 1, true) or lower:find('vinde', 1, true) or lower:find('vanda', 1, true))
            and (lower:find('gun', 1, true) or lower:find('weapon', 1, true) or lower:find('arm', 1, true)))
    if not isOffer then
        return nil
    end

    local playerId = clean:match('/[Aa][Cc][Cc][Ee][Pp][Tt]%s+[Gg][Uu][Nn]%s+(%d+)')
        or clean:match('[Ii][Dd]%s*[:#%-]?%s*(%d+)')
        or clean:match('%[(%d+)%]')
    if playerId then
        playerId = tonumber(playerId)
        if playerId and playerId >= 0 and playerId <= 1003 then
            return playerId
        end
    end
    return findConnectedPlayerByName(clean)
end

local lastAutoAcceptAt = -2000
if sampEventsAvailable and type(sampev) == 'table' then
    function sampev.onServerMessage(_, text)
        if not config.settings.auto_accept_gun then
            return
        end
        local playerId = extractGunOfferPlayerId(text)
        local now = getGameTimer()
        if not playerId or now - lastAutoAcceptAt < 1500 then
            return
        end
        lastAutoAcceptAt = now
        lua_thread.create(function()
            local startedAt = getGameTimer()
            local outsideSince = nil
            while config.settings.auto_accept_gun and sampIsPlayerConnected(playerId) do
                wait(50)
                local tick = getGameTimer()
                if tick - startedAt > 45000 then
                    return
                end
                if doesCharExist(PLAYER_PED) and not isCharInAnyCar(PLAYER_PED) then
                    outsideSince = outsideSince or tick
                    if tick - outsideSince >= config.settings.auto_accept_delay then
                        sampSendChat('/accept gun ' .. playerId)
                        ghChat(tr('auto_accept_sent') .. ': ' .. playerId)
                        return
                    end
                else
                    -- The configured delay starts only after the player is
                    -- continuously outside a vehicle.
                    outsideSince = nil
                end
            end
        end)
    end
end

local keyNames = {
    [0] = 'UNBOUND',
    [1] = 'MOUSE 1', [2] = 'MOUSE 2', [4] = 'MOUSE 3',
    [5] = 'MOUSE 4', [6] = 'MOUSE 5',
    [8] = 'BACKSPACE', [9] = 'TAB', [13] = 'ENTER', [16] = 'SHIFT',
    [17] = 'CTRL', [18] = 'ALT', [20] = 'CAPS LOCK', [27] = 'ESC',
    [32] = 'SPACE', [33] = 'PAGE UP', [34] = 'PAGE DOWN', [35] = 'END',
    [36] = 'HOME', [37] = 'LEFT', [38] = 'UP', [39] = 'RIGHT', [40] = 'DOWN',
    [45] = 'INSERT', [46] = 'DELETE', [96] = 'NUM 0', [97] = 'NUM 1',
    [98] = 'NUM 2', [99] = 'NUM 3', [100] = 'NUM 4', [101] = 'NUM 5',
    [102] = 'NUM 6', [103] = 'NUM 7', [104] = 'NUM 8', [105] = 'NUM 9',
    [106] = 'NUM *', [107] = 'NUM +', [109] = 'NUM -', [110] = 'NUM .',
    [111] = 'NUM /'
}

local function keyName(code)
    code = tonumber(code) or 0
    if code == 0 then
        return tr('unbound')
    end
    if code >= 48 and code <= 57 then
        return string.char(code)
    end
    if code >= 65 and code <= 90 then
        return string.char(code)
    end
    if code >= 112 and code <= 123 then
        return 'F' .. tostring(code - 111)
    end
    return keyNames[code] or ('VK ' .. tostring(code))
end

local pageIconKinds = { 'home', 'weapon', 'sensitivity', 'functions', 'overlay', 'shortcut', 'settings' }

local function drawIosIcon(kind, x, y, size, selected)
    local drawList = imgui.GetWindowDrawList()
    local theme = themes[config.settings.theme]
    local strokeU32 = imgui.GetColorU32(selected and theme.text or theme.muted)
    local left, top = x + size * 0.16, y + size * 0.16
    local right, bottom = x + size * 0.84, y + size * 0.84
    local cx, cy = x + size * 0.5, y + size * 0.5
    local thickness = math.max(1.15, size * 0.072)
    local function line(ax, ay, bx, by, customThickness)
        drawList:AddLine(imgui.ImVec2(ax, ay), imgui.ImVec2(bx, by),
            strokeU32, customThickness or thickness)
    end
    local function rect(ax, ay, bx, by, rounding)
        drawList:AddRect(imgui.ImVec2(ax, ay), imgui.ImVec2(bx, by),
            strokeU32, rounding or 2.0, 0, thickness)
    end
    local function circle(px, py, radius, filled)
        if filled then
            drawList:AddCircleFilled(imgui.ImVec2(px, py), radius, strokeU32, 20)
        else
            drawList:AddCircle(imgui.ImVec2(px, py), radius, strokeU32, 20, thickness)
        end
    end

    if kind == 'brand' then
        rect(left - size * 0.03, top - size * 0.03,
            right + size * 0.03, bottom + size * 0.03, size * 0.13)
        -- Compact vector GH monogram; it stays sharp at every UI scale.
        line(cx - size * 0.05, top + size * 0.10,
            left + size * 0.08, top + size * 0.10)
        line(left + size * 0.08, top + size * 0.10,
            left + size * 0.08, bottom - size * 0.10)
        line(left + size * 0.08, bottom - size * 0.10,
            cx - size * 0.05, bottom - size * 0.10)
        line(cx - size * 0.05, bottom - size * 0.10,
            cx - size * 0.05, cy + size * 0.02)
        line(cx - size * 0.05, cy + size * 0.02,
            cx - size * 0.15, cy + size * 0.02)
        line(cx + size * 0.08, top + size * 0.10,
            cx + size * 0.08, bottom - size * 0.10)
        line(right - size * 0.07, top + size * 0.10,
            right - size * 0.07, bottom - size * 0.10)
        line(cx + size * 0.08, cy,
            right - size * 0.07, cy)
    elseif kind == 'home' then
        line(left, cy - size * 0.02, cx, top)
        line(cx, top, right, cy - size * 0.02)
        line(left + size * 0.08, cy - size * 0.08, left + size * 0.08, bottom)
        line(right - size * 0.08, cy - size * 0.08, right - size * 0.08, bottom)
        line(left + size * 0.08, bottom, right - size * 0.08, bottom)
        rect(cx - size * 0.085, cy + size * 0.10, cx + size * 0.085, bottom, 1.0)
    elseif kind == 'server' then
        for index = 0, 2 do
            local yy = top + index * size * 0.23
            rect(left, yy, right, yy + size * 0.16, size * 0.045)
            drawList:AddCircleFilled(imgui.ImVec2(left + size * 0.10, yy + size * 0.08),
                math.max(1.0, size * 0.035), strokeU32, 10)
        end
    elseif kind == 'weapon' then
        local barrelY = top + size * 0.12
        line(left, barrelY, right, barrelY)
        line(right, barrelY, right, barrelY + size * 0.17)
        line(right, barrelY + size * 0.17, cx + size * 0.06, barrelY + size * 0.17)
        line(cx + size * 0.06, barrelY + size * 0.17, cx, cy)
        line(cx, cy, left + size * 0.10, cy)
        line(left + size * 0.10, cy, left, barrelY)
        line(left + size * 0.22, cy, left + size * 0.30, bottom)
        line(left + size * 0.30, bottom, cx - size * 0.03, bottom)
        line(cx - size * 0.03, bottom, cx + size * 0.01, cy)
        circle(cx + size * 0.16, cy - size * 0.005, size * 0.085, false)
    elseif kind == 'sensitivity' then
        drawList:AddCircle(imgui.ImVec2(cx, cy), size * 0.23, strokeU32, 22, thickness)
        drawList:AddCircleFilled(imgui.ImVec2(cx, cy), size * 0.055, strokeU32, 12)
        line(cx, top, cx, cy - size * 0.28)
        line(cx, cy + size * 0.28, cx, bottom)
        line(left, cy, cx - size * 0.28, cy)
        line(cx + size * 0.28, cy, right, cy)
    elseif kind == 'overlay' then
        rect(left, top + size * 0.06, right, bottom - size * 0.06, size * 0.10)
        for row = 0, 1 do
            for column = 0, 3 do
                local keyX = left + size * (0.12 + column * 0.15)
                local keyY = top + size * (0.22 + row * 0.18)
                drawList:AddCircleFilled(imgui.ImVec2(keyX, keyY),
                    math.max(1.0, size * 0.026), strokeU32, 8)
            end
        end
        line(left + size * 0.18, bottom - size * 0.20,
            right - size * 0.18, bottom - size * 0.20, thickness)
    elseif kind == 'shortcut' then
        line(left + size * 0.02, cy - size * 0.22, cx - size * 0.08, cy)
        line(cx - size * 0.08, cy, left + size * 0.02, cy + size * 0.22)
        line(right - size * 0.02, cy - size * 0.22, cx + size * 0.08, cy)
        line(cx + size * 0.08, cy, right - size * 0.02, cy + size * 0.22)
        line(cx - size * 0.02, top, cx + size * 0.02, bottom)
    elseif kind == 'functions' then
        local square = size * 0.22
        local gap = size * 0.10
        local startX, startY = cx - square - gap / 2, cy - square - gap / 2
        for row = 0, 1 do
            for column = 0, 1 do
                local ax = startX + column * (square + gap)
                local ay = startY + row * (square + gap)
                rect(ax, ay, ax + square, ay + square, size * 0.055)
            end
        end
    elseif kind == 'settings' then
        for index = 0, 2 do
            local yy = top + size * (0.09 + index * 0.25)
            local knobX = index == 0 and cx + size * 0.15
                or (index == 1 and cx - size * 0.17 or cx + size * 0.03)
            line(left, yy, right, yy)
            drawList:AddCircleFilled(imgui.ImVec2(knobX, yy), size * 0.075,
                imgui.GetColorU32(theme.side), 16)
            drawList:AddCircle(imgui.ImVec2(knobX, yy), size * 0.075,
                strokeU32, 16, thickness)
        end
    elseif kind == 'developer' then
        circle(cx, top + size * 0.16, size * 0.13, false)
        line(cx - size * 0.24, bottom, cx - size * 0.20, cy + size * 0.17)
        line(cx - size * 0.20, cy + size * 0.17, cx, cy + size * 0.09)
        line(cx, cy + size * 0.09, cx + size * 0.20, cy + size * 0.17)
        line(cx + size * 0.20, cy + size * 0.17, cx + size * 0.24, bottom)
        line(left - size * 0.05, cy - size * 0.01, left + size * 0.06, cy + size * 0.09)
        line(left + size * 0.06, cy + size * 0.09, left - size * 0.05, cy + size * 0.19)
        line(right + size * 0.05, cy - size * 0.01, right - size * 0.06, cy + size * 0.09)
        line(right - size * 0.06, cy + size * 0.09, right + size * 0.05, cy + size * 0.19)
    elseif kind == 'discord' then
        rect(left, top + size * 0.07, right, bottom - size * 0.10, size * 0.18)
        drawList:AddCircleFilled(imgui.ImVec2(cx - size * 0.14, cy), size * 0.052, strokeU32, 10)
        drawList:AddCircleFilled(imgui.ImVec2(cx + size * 0.14, cy), size * 0.052, strokeU32, 10)
        line(cx - size * 0.26, bottom - size * 0.14, left + size * 0.05, bottom)
        line(cx + size * 0.26, bottom - size * 0.14, right - size * 0.05, bottom)
    elseif kind == 'search' then
        drawList:AddCircle(imgui.ImVec2(cx - size * 0.06, cy - size * 0.06),
            size * 0.22, strokeU32, 18, thickness)
        line(cx + size * 0.10, cy + size * 0.10, right, bottom)
    elseif kind == 'notification' then
        local bellTop = top + size * 0.08
        local bellBottom = bottom - size * 0.13
        line(cx, bellTop, cx - size * 0.18, bellTop + size * 0.14)
        line(cx - size * 0.18, bellTop + size * 0.14,
            left + size * 0.02, bellBottom)
        line(cx, bellTop, cx + size * 0.18, bellTop + size * 0.14)
        line(cx + size * 0.18, bellTop + size * 0.14,
            right - size * 0.02, bellBottom)
        line(left + size * 0.02, bellBottom, right - size * 0.02, bellBottom)
        circle(cx, bottom - size * 0.02, size * 0.045, true)
    elseif kind == 'update' then
        drawList:AddCircle(imgui.ImVec2(cx, cy), size * 0.28, strokeU32, 24, thickness)
        line(cx, top + size * 0.07, cx, bottom - size * 0.16)
        line(cx, bottom - size * 0.16, cx - size * 0.12, bottom - size * 0.28)
        line(cx, bottom - size * 0.16, cx + size * 0.12, bottom - size * 0.28)
    end
end

local function setThemeMode(index)
    index = clamp(tonumber(index) or 1, 1, #themes)
    config.settings.theme_mode = index
    config.settings.theme = index
    applyTheme(index)
    saveSettings()
end

local function slimSlider(label, id, value, minimum, maximum, format, width, integer)
    local theme = themes[config.settings.theme]
    value = clamp(tonumber(value) or minimum, minimum, maximum)
    width = width or imgui.GetContentRegionAvail().x

    if imgui.InvisibleButton == nil then
        imgui.Text(label)
        local valueObject = integer and uiInt(math.floor(value + 0.5)) or uiFloat(value)
        local widthPushed = uiItemWidth(width)
        local changed
        local nativeFormat = type(format) == 'string' and format or '%.6f'
        if integer then
            changed = imgui.SliderInt('##' .. id, valueObject, minimum, maximum, nativeFormat)
        else
            changed = imgui.SliderFloat('##' .. id, valueObject, minimum, maximum, nativeFormat)
        end
        uiEndItemWidth(widthPushed)
        return changed, uiGet(valueObject)
    end

    local position = imgui.GetCursorScreenPos()
    imgui.InvisibleButton('##slimSlider_' .. id, imgui.ImVec2(width, 35))
    local changed = false
    if imgui.IsItemActive() then
        local mouseOk, mouseX = pcall(function()
            return imgui.GetIO().MousePos.x
        end)
        if mouseOk and tonumber(mouseX) then
            local ratio = clamp((tonumber(mouseX) - position.x) / math.max(1, width), 0.0, 1.0)
            local updated = minimum + (maximum - minimum) * ratio
            if integer then
                updated = math.floor(updated + 0.5)
            end
            if updated ~= value then
                value = updated
                changed = true
            end
        end
    end

    local displayValue = integer and math.floor(value + 0.5) or value
    local valueText
    if type(format) == 'function' then
        local formatted, result = pcall(format, displayValue)
        valueText = formatted and tostring(result) or tostring(displayValue)
    else
        valueText = string.format(format, displayValue)
    end
    local valueSize = imgui.CalcTextSize(valueText)
    local drawList = imgui.GetWindowDrawList()
    drawList:AddText(position, imgui.GetColorU32(theme.text), label)
    drawList:AddText(imgui.ImVec2(position.x + width - valueSize.x, position.y),
        imgui.GetColorU32(theme.muted), valueText)

    local trackY = position.y + 27
    local ratio = clamp((value - minimum) / math.max(0.000001, maximum - minimum), 0.0, 1.0)
    local knobX = position.x + 4 + math.max(0, width - 8) * ratio
    drawList:AddRectFilled(imgui.ImVec2(position.x, trackY - 1),
        imgui.ImVec2(position.x + width, trackY + 1), imgui.GetColorU32(theme.separator), 1.0)
    drawList:AddRectFilled(imgui.ImVec2(position.x, trackY - 1),
        imgui.ImVec2(knobX, trackY + 1), imgui.GetColorU32(theme.muted), 1.0)
    drawList:AddCircleFilled(imgui.ImVec2(knobX, trackY),
        imgui.IsItemHovered() and 4.8 or 4.2, imgui.GetColorU32(theme.strong), 16)
    return changed, value
end

local function preciseIntegerControl(id, value, minimum, maximum, width)
    local theme = themes[config.settings.theme]
    local valueObject = uiInt(math.floor(clamp(tonumber(value) or minimum, minimum, maximum)))
    imgui.PushStyleColor(imgui.Col.FrameBg, theme.control)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, theme.controlHover)
    imgui.PushStyleColor(imgui.Col.FrameBgActive, theme.buttonActive)
    imgui.PushStyleColor(imgui.Col.Text, theme.text)
    local widthPushed = uiItemWidth(width)
    local inputAvailable = type(imgui.InputInt) == 'function'
    local inputOk, changed = false, false
    if inputAvailable then
        inputOk, changed = pcall(imgui.InputInt,
            '##preciseInt_' .. id, valueObject, 1, 10)
    end
    uiEndItemWidth(widthPushed)
    imgui.PopStyleColor(4)

    if inputOk then
        return changed,
            math.floor(clamp(tonumber(uiGet(valueObject)) or minimum, minimum, maximum))
    end

    -- Very old MoonImGui builds may not expose InputInt. Keep the menu usable
    -- and the full 0..311 range reachable instead of letting the frame crash.
    return slimSlider('', 'fallbackPreciseInt_' .. id, value, minimum, maximum,
        '%d', width, true)
end

local function drawSunMoonGlyph(drawList, kind, cx, cy, colorValue, cutout)
    local strokeU32 = imgui.GetColorU32(colorValue)
    if kind == 'sun' then
        drawList:AddCircle(imgui.ImVec2(cx, cy), 3.8, strokeU32, 16, 1.3)
        for index = 0, 7 do
            local angle = index * math.pi / 4
            drawList:AddLine(
                imgui.ImVec2(cx + math.cos(angle) * 6.2, cy + math.sin(angle) * 6.2),
                imgui.ImVec2(cx + math.cos(angle) * 8.2, cy + math.sin(angle) * 8.2),
                strokeU32, 1.2)
        end
    else
        drawList:AddCircleFilled(imgui.ImVec2(cx - 0.5, cy), 6.2, strokeU32, 20)
        drawList:AddCircleFilled(imgui.ImVec2(cx + 2.7, cy - 2.6), 5.8,
            imgui.GetColorU32(cutout), 20)
    end
end

local function compactToggleButton(id, animation, leftLabel, rightLabel, isTheme)
    local theme = themes[config.settings.theme]
    local width, height = 52, 26
    local position = imgui.GetCursorScreenPos()

    imgui.PushStyleColor(imgui.Col.Button, color(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, color(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonActive, color(0, 0, 0, 0))
    local clicked = imgui.Button('##' .. id, imgui.ImVec2(width, height))
    local hovered = imgui.IsItemHovered()
    imgui.PopStyleColor(3)

    local drawList = imgui.GetWindowDrawList()
    drawList:AddRectFilled(imgui.ImVec2(position.x, position.y + 2),
        imgui.ImVec2(position.x + width, position.y + height - 2),
        imgui.GetColorU32(hovered and theme.controlHover or theme.control), 11)
    local indicatorX = position.x + 13 + animation * 26
    local indicatorColor = theme.mode == 'dark' and color(72, 72, 74) or color(255, 255, 255)
    if isTheme then
        drawList:AddCircleFilled(imgui.ImVec2(indicatorX, position.y + height / 2),
            10.0, imgui.GetColorU32(indicatorColor), 24)
    else
        drawList:AddRectFilled(
            imgui.ImVec2(indicatorX - 12, position.y + 3),
            imgui.ImVec2(indicatorX + 12, position.y + height - 3),
            imgui.GetColorU32(indicatorColor), 9)
    end

    if isTheme then
        drawSunMoonGlyph(drawList, 'moon', position.x + 13, position.y + 13,
            animation < 0.5 and theme.text or theme.muted,
            animation < 0.5 and indicatorColor or theme.control)
        drawSunMoonGlyph(drawList, 'sun', position.x + 39, position.y + 13,
            animation >= 0.5 and theme.text or theme.muted, indicatorColor)
    else
        local languageFontPushed = pushFont(uiFonts.semibold)
        local leftSize = imgui.CalcTextSize(leftLabel)
        local rightSize = imgui.CalcTextSize(rightLabel)
        local leftY = position.y + math.floor((height - leftSize.y) / 2)
        local rightY = position.y + math.floor((height - rightSize.y) / 2)
        drawList:AddText(imgui.ImVec2(position.x + 13 - leftSize.x / 2, leftY),
            imgui.GetColorU32(animation < 0.5 and theme.strong or theme.text), leftLabel)
        drawList:AddText(imgui.ImVec2(position.x + 39 - rightSize.x / 2, rightY),
            imgui.GetColorU32(animation >= 0.5 and theme.strong or theme.text), rightLabel)
        popFont(languageFontPushed)
    end
    return clicked
end

local function optionButton(label, selected, width, id)
    local theme = themes[config.settings.theme]
    imgui.PushStyleColor(imgui.Col.Button, selected and theme.panelHover or theme.control)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, theme.panelHover)
    imgui.PushStyleColor(imgui.Col.ButtonActive, theme.buttonActive)
    imgui.PushStyleColor(imgui.Col.Text, selected and theme.strong or theme.text)
    local clicked = imgui.Button(label .. '##' .. (id or label), imgui.ImVec2(width or 122, 30))
    imgui.PopStyleColor(4)
    return clicked
end

local function navButton(label, page)
    local theme = themes[config.settings.theme]
    local selected = (pendingPage or currentPage) == page
    imgui.PushStyleColor(imgui.Col.Button, selected and theme.control or color(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, theme.panelHover)
    imgui.PushStyleColor(imgui.Col.ButtonActive, theme.buttonActive)
    local itemPos = imgui.GetCursorScreenPos()
    if imgui.Button('##nav' .. page, imgui.ImVec2(UI_LAYOUT.navigationWidth, 31)) then
        requestPage(page)
    end
    imgui.PopStyleColor(3)
    local drawList = imgui.GetWindowDrawList()
    if selected then
        drawList:AddRectFilled(imgui.ImVec2(itemPos.x + 2, itemPos.y + 8),
            imgui.ImVec2(itemPos.x + 4, itemPos.y + 23), imgui.GetColorU32(theme.text), 1.0)
    end
    drawIosIcon(pageIconKinds[page], itemPos.x + 11, itemPos.y + 6, 19, selected)
    local navFontPushed = selected and pushFont(uiFonts.semibold) or false
    local textSize = imgui.CalcTextSize(label)
    drawList:AddText(imgui.ImVec2(itemPos.x + 42,
        itemPos.y + math.floor((31 - textSize.y) / 2)),
        imgui.GetColorU32(selected and theme.text or theme.muted), label)
    popFont(navFontPushed)
end

local function sidebarLink(label, page, iconKind)
    local theme = themes[config.settings.theme]
    imgui.PushStyleColor(imgui.Col.Button, color(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, theme.panelHover)
    imgui.PushStyleColor(imgui.Col.ButtonActive, theme.buttonActive)
    imgui.PushStyleColor(imgui.Col.Text, theme.muted)
    imgui.PushStyleVar(imgui.StyleVar.ButtonTextAlign, imgui.ImVec2(0.0, 0.5))
    local itemPos = imgui.GetCursorScreenPos()
    if imgui.Button('       ' .. label .. '##sidebarLink' .. page .. iconKind, imgui.ImVec2(174, 34)) then
        requestPage(page)
    end
    imgui.PopStyleVar()
    imgui.PopStyleColor(4)
    drawIosIcon(iconKind, itemPos.x + 10, itemPos.y + 7, 22, false)
end

local function toggleSetting(label, field)
    local value = uiBool(config.settings[field])
    if imgui.Checkbox(label .. '##' .. field, value) then
        config.settings[field] = uiGet(value)
        saveSettings()
        return true
    end
    return false
end

local function beginKeyCapture(field)
    captureField = field
    captureReadyAt = getGameTimer() + 250
end

local function keyBindControl(field, width)
    local theme = themes[config.settings.theme]
    local label = captureField == field and tr('press_key') or keyName(config.settings[field])
    imgui.PushStyleColor(imgui.Col.Button, captureField == field and theme.accent or theme.side)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, theme.panelHover)
    imgui.PushStyleColor(imgui.Col.ButtonActive, theme.buttonActive)
    imgui.PushStyleColor(imgui.Col.Text, captureField == field and theme.avatarText or theme.text)
    if imgui.Button(label .. '##bind_' .. field, imgui.ImVec2(width or 126, 30)) then
        beginKeyCapture(field)
    end
    imgui.PopStyleColor(4)
    imgui.SameLine()
    imgui.PushStyleColor(imgui.Col.Button, color(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, theme.panelHover)
    if imgui.Button(tr('clear') .. '##clear_' .. field, imgui.ImVec2(62, 30)) then
        config.settings[field] = 0
        if captureField == field then
            captureField = nil
        end
        saveSettings()
    end
    imgui.PopStyleColor(2)
end

local function commandBindRow(id, title, command, field)
    local theme = themes[config.settings.theme]
    local width = imgui.GetContentRegionAvail().x
    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##command_' .. id, imgui.ImVec2(width, 76), true)
    local commandPos = imgui.GetWindowPos()
    drawIosIcon('server', commandPos.x + 14, commandPos.y + 22, 28, true)
    imgui.SetCursorPos(imgui.ImVec2(54, 13))
    imgui.Text(title)
    imgui.SetCursorPos(imgui.ImVec2(54, 40))
    imgui.TextColored(theme.accent, command)
    imgui.SetCursorPos(imgui.ImVec2(width - 224, 21))
    keyBindControl(field, 140)
    imgui.EndChild()
    imgui.PopStyleColor()
end

local function dashboardCard(id, label, value, width, iconKind)
    local theme = themes[config.settings.theme]
    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##dash_' .. id, imgui.ImVec2(width, 92), true)
    local cardPos = imgui.GetWindowPos()
    drawIosIcon(iconKind, cardPos.x + 14, cardPos.y + 18, 28, true)
    imgui.SetCursorPos(imgui.ImVec2(52, 14))
    mutedText(label)
    imgui.SetCursorPosX(52)
    imgui.TextColored(theme.accent, value)
    imgui.EndChild()
    imgui.PopStyleColor()
end

local function systemMonitorCard(id, label, value, width, iconKind)
    local theme = themes[config.settings.theme]
    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##monitor_' .. id, imgui.ImVec2(width, 68), true)
    local cardPos = imgui.GetWindowPos()
    drawIosIcon(iconKind, cardPos.x + 13, cardPos.y + 19, 30, false)
    imgui.SetCursorPos(imgui.ImVec2(56, 10))
    mutedText(label)
    imgui.SetCursorPos(imgui.ImVec2(56, 32))
    local valueFontPushed = pushFont(uiFonts.semibold)
    imgui.TextColored(theme.text, value)
    popFont(valueFontPushed)
    imgui.EndChild()
    imgui.PopStyleColor()
end

local function currentCancelKey()
    if config.settings.profile == 1 then
        return config.settings.bzone_cancel_key
    end
    return config.settings.bugged_cancel_key
end

local function drawHome()
    local theme = themes[config.settings.theme]
    local width = imgui.GetContentRegionAvail().x
    sectionTitle(tr('home_about_title'))
    imgui.Dummy(imgui.ImVec2(0, 5))
    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##homeAboutMod', imgui.ImVec2(width, 136), false)
    local aboutCardPos = imgui.GetWindowPos()
    drawIosIcon('brand', aboutCardPos.x + 18, aboutCardPos.y + 19, 42, true)
    imgui.SetCursorPos(imgui.ImVec2(78, 15))
    richWrappedText(tr('home_about_text'), width - 94)
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.Dummy(imgui.ImVec2(0, 19))
    sectionTitle(tr('home_update_title'))
    imgui.Dummy(imgui.ImVec2(0, 5))
    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##homeUpdateInformation', imgui.ImVec2(width, 150), false)
    local updateCardPos = imgui.GetWindowPos()
    drawIosIcon('update', updateCardPos.x + 17, updateCardPos.y + 15, 34, true)
    imgui.SetCursorPos(imgui.ImVec2(66, 14))
    local updateFontPushed = pushFont(uiFonts.semibold)
    imgui.TextColored(theme.text, tr('notifications_update'))
    popFont(updateFontPushed)
    imgui.SetCursorPos(imgui.ImVec2(17, 50))
    mutedWrapped(tr('home_update_info'), width - 34)
    imgui.SetCursorPos(imgui.ImVec2(17, imgui.GetCursorPosY() + 7))
    imgui.PushStyleColor(imgui.Col.Text, theme.blue)
    imgui.PushTextWrapPos(width - 17)
    imgui.Text(tr('home_update_future'))
    imgui.PopTextWrapPos()
    imgui.PopStyleColor()
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.Dummy(imgui.ImVec2(0, 19))
    sectionTitle(tr('home_feedback_title'))
    imgui.Dummy(imgui.ImVec2(0, 5))
    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##homeDeveloperContact', imgui.ImVec2(width, 128), false)
    local cardPos = imgui.GetWindowPos()
    drawIosIcon('developer', cardPos.x + 18, cardPos.y + 14, 36, true)
    imgui.SetCursorPos(imgui.ImVec2(70, 14))
    mutedText(tr('home_discord_label'))
    imgui.SetCursorPos(imgui.ImVec2(70, 35))
    local discordFontPushed = pushFont(uiFonts.title)
    imgui.TextColored(theme.text, 'semaka47')
    popFont(discordFontPushed)
    imgui.SetCursorPos(imgui.ImVec2(18, 76))
    mutedWrapped(tr('home_feedback_text'), width - 36)
    imgui.EndChild()
    imgui.PopStyleColor()
end

local function drawServer()
    sectionTitle(tr('server_profile'))
    mutedWrapped(tr('server_profile_hint'))

    if optionButton('B-ZONE', config.settings.profile == 1, 160, 'profileBzone') then
        config.settings.profile = 1
        saveSettings()
    end
    imgui.SameLine()
    if optionButton('BUGGED', config.settings.profile == 2, 160, 'profileBugged') then
        config.settings.profile = 2
        saveSettings()
    end
    imgui.Dummy(imgui.ImVec2(0, 2))
    mutedText(config.settings.profile == 1 and tr('bzone_hint') or tr('bugged_hint'))

    imgui.Dummy(imgui.ImVec2(0, 13))
    sectionTitle(tr('command_binds'))

    if config.settings.profile == 1 then
        commandBindRow('bzoneCancel', tr('cancel_animation'), '/omg', 'bzone_cancel_key')
        commandBindRow('bzoneCocaine', tr('cocaine'), '/usedrugs cocaine', 'bzone_cocaine_key')
        commandBindRow('bzoneMeth', tr('meth'), '/usedrugs meth', 'bzone_meth_key')
    else
        commandBindRow('buggedCancel', tr('cancel_animation'), '/stopanim', 'bugged_cancel_key')
        commandBindRow('buggedDrugs', tr('drugs'), '/usedrugs', 'bugged_drugs_key')
    end

    imgui.Dummy(imgui.ImVec2(0, 5))
    mutedText(tr('esc_cancel'))
end

local function weaponOptionIndex(weaponId)
    for index, weapon in ipairs(weaponOptions) do
        if weapon.id == weaponId then
            return index
        end
    end
    return 1
end

local weaponComboParts = {}
for _, weapon in ipairs(weaponOptions) do
    weaponComboParts[#weaponComboParts + 1] = weapon.name
end
local weaponComboString = table.concat(weaponComboParts, '\0') .. '\0\0'
local numberComboString = table.concat({ '1', '2', '3', '4', '5' }, '\0') .. '\0\0'

local function fillWeaponTemplate(template, weapon, playerId, playerName)
    local result = tostring(template or '')
    result = result:gsub('{weapon}', tostring(weapon or ''))
    result = result:gsub('{id}', tostring(playerId or ''))
    result = result:gsub('{name}', tostring(playerName or ''))
    return result
end

local function actionFieldForWeapon(actionType, weapon)
    if actionType == 'request' then
        local languageSuffix = config.settings.language == 2 and '_en' or '_ro'
        return 'request_' .. weapon.command .. languageSuffix
    end
    return 'sell_' .. weapon.command
end

local function actionAliasFieldForWeapon(actionType, weapon)
    return actionType .. '_alias_' .. weapon.command
end

local executeWeaponAction

local function nameLooksCovered(nickname)
    local name = tostring(nickname or ''):lower()
    return name == ''
        or name:find('stranger', 1, true) ~= nil
        or name:find('unknown', 1, true) ~= nil
        or name:find('necunoscut', 1, true) ~= nil
        or name:find('namecover', 1, true) ~= nil
end

local function playerHasVisibleName(playerId, ped)
    if not isCharOnScreen(ped) then
        return false
    end
    local nickname = sampGetPlayerNickname(playerId)
    if nameLooksCovered(nickname) then
        return false
    end
    local ok, playerColor = pcall(sampGetPlayerColor, playerId)
    if ok and type(playerColor) == 'number'
        and bit.band(bit.rshift(playerColor, 24), 0xFF) == 0 then
        return false
    end
    return true
end

local function findNearestVisiblePlayer(maxDistance)
    local localId = getLocalPlayerId()
    local x, y, z = getCharCoordinates(PLAYER_PED)
    local nearestId, nearestName, nearestDistance = nil, nil, maxDistance + 0.001

    for playerId = 0, 1003 do
        if playerId ~= localId and sampIsPlayerConnected(playerId) then
            local streamed, ped = sampGetCharHandleBySampPlayerId(playerId)
            if streamed and doesCharExist(ped) then
                local px, py, pz = getCharCoordinates(ped)
                local dx, dy, dz = px - x, py - y, pz - z
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
                if distance <= nearestDistance and playerHasVisibleName(playerId, ped) then
                    nearestId = playerId
                    nearestName = sampGetPlayerNickname(playerId)
                    nearestDistance = distance
                end
            end
        end
    end

    return nearestId, nearestName, nearestDistance
end

local function antiRepeatMessage(actionKey, message)
    local state = repeatedMessages[actionKey]
    if not state or state.message ~= message then
        state = { message = message, count = 1 }
        repeatedMessages[actionKey] = state
        return message
    end
    state.count = state.count + 1

    -- Gameplay commands must remain exact; chat commands receive the alternating period.
    if message:lower():match('^/sellgun%s') or message:lower():match('^/accept%s') then
        return message
    end
    return state.count % 2 == 0 and (message .. '.') or message
end

executeWeaponAction = function(actionType, weapon, template)
    local playerId, playerName
    if actionType == 'sell' then
        playerId, playerName = findNearestVisiblePlayer(config.settings.sellgun_distance)
        if not playerId then
            ghChat(tr('sell_no_target'))
            return
        end
    else
        playerId = getLocalPlayerId()
        playerName = getLocalPlayerName()
        if playerId < 0 then
            return
        end
    end

    local weaponValue = actionType == 'sell' and weapon.command or weapon.name
    local message = fillWeaponTemplate(template, weaponValue, playerId, playerName)
    if message == '' then
        return
    end
    local actionKey = actionType .. ':' .. weapon.command
    sampSendChat(toGameEncoding(antiRepeatMessage(actionKey, message)))
    if actionType == 'sell' then
        ghChat(tr('sell_target') .. ' ' .. playerName .. ' [' .. playerId .. ']')
    else
        ghChat(tr('request_sent') .. ': ' .. weapon.name)
    end
end

local shortcutDispatching = false
local function normalizeShortcutAlias(value)
    local alias = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if alias == '' then
        return ''
    end
    if alias:sub(1, 1) ~= '/' then
        alias = '/' .. alias
    end
    return alias:lower()
end

local function dispatchShortcutAction(callback)
    shortcutDispatching = true
    local executed, executeError = pcall(callback)
    shortcutDispatching = false
    if not executed then
        print('[Gang Helper] Shortcut error: ' .. tostring(executeError))
    end
end

if sampEventsAvailable and type(sampev) == 'table' then
    function sampev.onSendCommand(command)
        if shortcutDispatching then
            return
        end
        local outgoing = normalizeShortcutAlias(command)
        if outgoing == '' then
            return
        end

        for slot = 1, 10 do
            local fullCommand = tostring(config.settings['shortcut_full_' .. slot] or '')
            local alias = normalizeShortcutAlias(config.settings['shortcut_alias_' .. slot])
            if alias ~= '' and fullCommand ~= '' and outgoing == alias then
                dispatchShortcutAction(function()
                    sampSendChat(toGameEncoding(fullCommand))
                end)
                return false
            end
        end

        for _, weapon in ipairs(tradeWeapons) do
            for _, actionType in ipairs({ 'request', 'sell' }) do
                local aliasField = actionAliasFieldForWeapon(actionType, weapon)
                local alias = normalizeShortcutAlias(config.settings[aliasField])
                if alias ~= '' and outgoing == alias then
                    local template = config.settings[actionFieldForWeapon(actionType, weapon)]
                    dispatchShortcutAction(function()
                        executeWeaponAction(actionType, weapon, template)
                    end)
                    return false
                end
            end
        end
    end
end

local function drawEditableWeaponCommandRow(actionType, weapon)
    local theme = themes[config.settings.theme]
    local width = imgui.GetContentRegionAvail().x
    local field = actionFieldForWeapon(actionType, weapon)
    local aliasField = actionAliasFieldForWeapon(actionType, weapon)
    local buffer = getInlineCommandBuffer(field)
    local aliasBuffer = getInlineCommandBuffer(aliasField)
    local labelKey = actionType == 'sell' and 'sell_edit' or 'request_edit'

    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##commandEditor_' .. actionType .. '_' .. weapon.command,
        imgui.ImVec2(width, 54), true)
    imgui.SetCursorPos(imgui.ImVec2(13, 18))
    imgui.Text(tr(labelKey) .. ' ' .. weapon.name)

    local inputX = 122
    local aliasWidth = 106
    local fieldGap = 8
    local inputWidth = math.max(210, width - inputX - aliasWidth - fieldGap - 14)
    imgui.SetCursorPos(imgui.ImVec2(inputX, 9))
    local inputWidthPushed = uiItemWidth(inputWidth)
    local changed
    if legacyImgui then
        changed = imgui.InputText('##inline_' .. field, buffer)
    else
        changed = imgui.InputText('##inline_' .. field, buffer, 257)
    end
    if changed then
        config.settings[field] = getTextBuffer(buffer)
        saveSettings()
    end
    uiEndItemWidth(inputWidthPushed)

    imgui.SetCursorPos(imgui.ImVec2(inputX + inputWidth + fieldGap, 9))
    local aliasWidthPushed = uiItemWidth(aliasWidth)
    local aliasChanged
    if legacyImgui then
        aliasChanged = imgui.InputText('##inline_' .. aliasField, aliasBuffer)
    else
        aliasChanged = imgui.InputText('##inline_' .. aliasField, aliasBuffer, 257)
    end
    if aliasChanged then
        config.settings[aliasField] = getTextBuffer(aliasBuffer)
        saveSettings()
    end
    uiEndItemWidth(aliasWidthPushed)
    imgui.EndChild()
    imgui.PopStyleColor()
end

local function drawWeaponSlot(slot)
    local theme = themes[config.settings.theme]
    local width = imgui.GetContentRegionAvail().x
    local weaponField = 'weapon_slot_' .. slot
    local keyField = 'weapon_key_' .. slot

    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##weaponSlot' .. slot, imgui.ImVec2(width, 50), true)
    imgui.SetCursorPos(imgui.ImVec2(14, 15))
    imgui.TextColored(theme.text, tr('slot'))

    -- Keep popup and selected text readable in both themes, including old MoonImGui.
    imgui.PushStyleColor(imgui.Col.Text, theme.text)
    imgui.PushStyleColor(imgui.Col.PopupBg or imgui.Col.WindowBg, theme.panel)
    imgui.PushStyleColor(imgui.Col.FrameBg, theme.control)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, theme.controlHover)
    imgui.PushStyleColor(imgui.Col.FrameBgActive, theme.buttonActive)
    imgui.PushStyleColor(imgui.Col.Header, theme.panelHover)
    imgui.PushStyleColor(imgui.Col.HeaderHovered, theme.controlHover)
    imgui.PushStyleColor(imgui.Col.HeaderActive, theme.buttonActive)
    local comboStyleCount = 8
    if imgui.Col.ComboBg ~= nil then
        imgui.PushStyleColor(imgui.Col.ComboBg, theme.panel)
        comboStyleCount = comboStyleCount + 1
    end

    imgui.SetCursorPos(imgui.ImVec2(130, 8))
    local weaponWidthPushed = uiItemWidth(272)
    local selectedWeapon = uiInt(weaponOptionIndex(config.settings[weaponField]) - 1)
    local weaponChanged
    if legacyImgui then
        weaponChanged = imgui.Combo('##weaponSelect' .. slot, selectedWeapon, weaponComboParts)
    else
        weaponChanged = imgui.ComboStr('##weaponSelect' .. slot, selectedWeapon, weaponComboString)
    end
    if weaponChanged then
        config.settings[weaponField] = weaponOptions[uiGet(selectedWeapon) + 1].id
        saveSettings()
    end
    uiEndItemWidth(weaponWidthPushed)

    imgui.SetCursorPos(imgui.ImVec2(414, 8))
    local keyWidthPushed = uiItemWidth(math.max(86, width - 428))
    local selectedKey = uiInt(config.settings[keyField] - 49)
    local keyChanged
    if legacyImgui then
        keyChanged = imgui.Combo('##weaponKey' .. slot, selectedKey, { '1', '2', '3', '4', '5' })
    else
        keyChanged = imgui.ComboStr('##weaponKey' .. slot, selectedKey, numberComboString)
    end
    if keyChanged then
        config.settings[keyField] = uiGet(selectedKey) + 49
        saveSettings()
    end
    uiEndItemWidth(keyWidthPushed)
    imgui.PopStyleColor(comboStyleCount)
    imgui.EndChild()
    imgui.PopStyleColor()
end

local function drawWeapons()
    sectionTitle(tr('weapon_switch_title'))
    toggleSetting(tr('weapon_switch_enable'), 'weapon_switch')
    mutedWrapped(tr('weapon_switch_hint'))
    imgui.Dummy(imgui.ImVec2(0, 10))

    for slot = 1, 5 do
        drawWeaponSlot(slot)
    end

    imgui.Dummy(imgui.ImVec2(0, 15))
    sectionTitle(tr('gun_tools_title'))

    local autoAccept = uiBool(config.settings.auto_accept_gun)
    if imgui.Checkbox(tr('auto_accept_gun') .. '##auto_accept_gun', autoAccept) then
        if uiGet(autoAccept) and not sampEventsAvailable then
            config.settings.auto_accept_gun = false
            ghChat(tr('samp_events_missing'))
        else
            config.settings.auto_accept_gun = uiGet(autoAccept)
        end
        saveSettings()
    end
    mutedWrapped(tr('auto_accept_hint'))
    if not sampEventsAvailable then
        imgui.TextColored(color(239, 105, 105), tr('samp_events_missing'))
    end
    local delayChanged, delayValue = slimSlider(tr('auto_accept_delay'), 'autoAcceptDelay',
        config.settings.auto_accept_delay, 0, 1500, '%d ms', 360, true)
    if delayChanged then
        config.settings.auto_accept_delay = delayValue
        saveSettings()
    end

    imgui.Dummy(imgui.ImVec2(0, 8))
    mutedWrapped(tr('request_hint'))
    mutedText(tr('command_saved'))
    imgui.SetCursorPosX(122)
    mutedText(tr('command_template'))
    imgui.SameLine()
    imgui.SetCursorPosX(446)
    mutedText(tr('command_alias'))

    for _, weapon in ipairs(tradeWeapons) do
        drawEditableWeaponCommandRow('request', weapon)
    end

    imgui.Dummy(imgui.ImVec2(0, 11))
    mutedWrapped(tr('sellgun_hint'))
    local distanceChanged, distanceValue = slimSlider(tr('sellgun_distance'), 'sellgunDistance',
        config.settings.sellgun_distance, 2.0, 25.0, '%.1f m', 360, false)
    if distanceChanged then
        config.settings.sellgun_distance = distanceValue
        saveSettings()
    end

    imgui.SetCursorPosX(122)
    mutedText(tr('command_template'))
    imgui.SameLine()
    imgui.SetCursorPosX(446)
    mutedText(tr('command_alias'))

    for _, weapon in ipairs(tradeWeapons) do
        drawEditableWeaponCommandRow('sell', weapon)
    end
end

local function drawShortcutRow(slot)
    local theme = themes[config.settings.theme]
    local width = imgui.GetContentRegionAvail().x
    local fullField = 'shortcut_full_' .. slot
    local aliasField = 'shortcut_alias_' .. slot
    local fullBuffer = getInlineCommandBuffer(fullField)
    local aliasBuffer = getInlineCommandBuffer(aliasField)

    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##shortcutRow' .. slot, imgui.ImVec2(width, 48), true)
    imgui.SetCursorPos(imgui.ImVec2(13, 16))
    imgui.TextColored(theme.muted, string.format('%02d', slot))

    imgui.SetCursorPos(imgui.ImVec2(48, 7))
    local fullWidthPushed = uiItemWidth(344)
    local fullChanged
    if legacyImgui then
        fullChanged = imgui.InputText('##' .. fullField, fullBuffer)
    else
        fullChanged = imgui.InputText('##' .. fullField, fullBuffer, 257)
    end
    if fullChanged then
        config.settings[fullField] = getTextBuffer(fullBuffer)
        saveSettings()
    end
    uiEndItemWidth(fullWidthPushed)

    imgui.SetCursorPos(imgui.ImVec2(402, 7))
    local aliasWidthPushed = uiItemWidth(width - 416)
    local aliasChanged
    if legacyImgui then
        aliasChanged = imgui.InputText('##' .. aliasField, aliasBuffer)
    else
        aliasChanged = imgui.InputText('##' .. aliasField, aliasBuffer, 257)
    end
    if aliasChanged then
        config.settings[aliasField] = getTextBuffer(aliasBuffer)
        saveSettings()
    end
    uiEndItemWidth(aliasWidthPushed)
    imgui.EndChild()
    imgui.PopStyleColor()
end

local function drawShortcuts()
    sectionTitle(tr('shortcuts_title'))
    mutedWrapped(tr('shortcuts_hint'))
    if not sampEventsAvailable then
        imgui.TextColored(color(239, 105, 105), tr('shortcuts_library_missing'))
    end
    imgui.Dummy(imgui.ImVec2(0, 8))
    imgui.SetCursorPosX(48)
    mutedText(tr('command_template'))
    imgui.SameLine()
    imgui.SetCursorPosX(402)
    mutedText(tr('command_alias'))
    for slot = 1, 10 do
        drawShortcutRow(slot)
    end
end

local function captureBaseSensitivity()
    if not isGameVersionOriginal() then
        sensitivityMemoryValid = false
        return false
    end
    local horizontal = memory.getfloat(SENSITIVITY_X, true)
    local vertical = memory.getfloat(SENSITIVITY_Y, true)
    if horizontal >= 0.00005 and horizontal <= 0.02 and vertical >= 0.00005 and vertical <= 0.02 then
        baseSensitivityX = horizontal
        baseSensitivityY = vertical
        sensitivityMemoryValid = true
        -- Preserve values explicitly customized in older configurations, but
        -- migrate every untouched weapon to the actual sensitivity read from
        -- this user's game.
        for _, weapon in ipairs(sensitivityWeapons) do
            local field = 'sens_' .. weapon.id
            local overrideField = 'sens_override_' .. weapon.id
            if config.settings[overrideField] ~= true then
                config.settings[field] = horizontal
            end
        end
        return true
    end
    sensitivityMemoryValid = false
    return false
end

local function restoreSensitivity()
    if sensitivityMemoryValid and sensitivityApplied and baseSensitivityX and baseSensitivityY then
        memory.setfloat(SENSITIVITY_X, baseSensitivityX, true)
        memory.setfloat(SENSITIVITY_Y, baseSensitivityY, true)
    end
    sensitivityApplied = false
end

local function setSensitivityEnabled(enabled)
    if enabled then
        restoreSensitivity()
        if not captureBaseSensitivity() then
            config.settings.sensitivity_fix = false
            ghChat(tr('memory_unavailable'))
            saveSettings()
            return false
        end
        config.settings.sensitivity_fix = true
    else
        restoreSensitivity()
        config.settings.sensitivity_fix = false
    end
    saveSettings()
    return true
end

local function currentWeaponName()
    local weaponId = getCurrentCharWeapon(PLAYER_PED)
    if weaponId == 0 then
        return tr('without_weapon')
    end
    return weaponById[weaponId] and weaponById[weaponId].name or ('ID ' .. tostring(weaponId))
end

local function sensitivityOffsetText(value, gameDefault)
    local difference = (tonumber(value) or gameDefault) - gameDefault
    if math.abs(difference) <= 0.0000005 then
        return tr('game_default_status')
    end
    return string.format('%+.6f', difference)
end

local function drawSensitivity()
    local theme = themes[config.settings.theme]
    sectionTitle(tr('sensitivity_title'))

    local enabled = uiBool(config.settings.sensitivity_fix)
    if imgui.Checkbox(tr('sensitivity_enable') .. '##sensitivity_fix', enabled) then
        setSensitivityEnabled(uiGet(enabled))
    end
    mutedWrapped(tr('sensitivity_hint'))

    imgui.Dummy(imgui.ImVec2(0, 7))
    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##sensitivityStatus', imgui.ImVec2(imgui.GetContentRegionAvail().x, 70), true)
    imgui.SetCursorPos(imgui.ImVec2(15, 11))
    mutedText(tr('current_weapon'))
    imgui.SetCursorPosX(15)
    imgui.TextColored(theme.accent, currentWeaponName())
    imgui.SetCursorPos(imgui.ImVec2(350, 11))
    mutedText(tr('current_value'))
    imgui.SetCursorPosX(350)
    local currentWeaponId = getCurrentCharWeapon(PLAYER_PED)
    local currentValue = config.settings['sens_' .. currentWeaponId]
    local gameDefault = baseSensitivityX or DEFAULT_SENSITIVITY
    local currentIsCustom = sensitivityWeaponById[currentWeaponId] and currentValue
        and math.abs(currentValue - gameDefault) > 0.0000005
    if currentIsCustom then
        imgui.TextColored(theme.accent, sensitivityOffsetText(currentValue, gameDefault))
    else
        imgui.TextColored(theme.accent, tr('game_default_status'))
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.Dummy(imgui.ImVec2(0, 7))
    for _, weapon in ipairs(sensitivityWeapons) do
        local field = 'sens_' .. weapon.id
        local overrideField = 'sens_override_' .. weapon.id
        imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
        imgui.BeginChild('##sensitivityWeapon' .. weapon.id,
            imgui.ImVec2(imgui.GetContentRegionAvail().x, 54), true)
        imgui.SetCursorPos(imgui.ImVec2(14, 19))
        local weaponFontPushed = pushFont(uiFonts.semibold)
        imgui.TextColored(theme.text, weapon.name)
        popFont(weaponFontPushed)
        imgui.SetCursorPos(imgui.ImVec2(174, 7))
        local minimum = math.max(0.000050, gameDefault * 0.125)
        local maximum = math.min(0.020000, gameDefault * 1.60)
        local sensitivityChanged, sensitivityValue = slimSlider('', field,
            config.settings[field], minimum, maximum, function(sliderValue)
                return sensitivityOffsetText(sliderValue, gameDefault)
            end,
            math.max(240, imgui.GetContentRegionAvail().x - 14), false)
        if sensitivityChanged then
            config.settings[field] = sensitivityValue
            config.settings[overrideField] = math.abs(sensitivityValue - gameDefault) > 0.0000005
            if not config.settings[overrideField] and sensitivityApplied
                    and getCurrentCharWeapon(PLAYER_PED) == weapon.id then
                restoreSensitivity()
            end
            saveSettings()
        end
        imgui.EndChild()
        imgui.PopStyleColor()
    end

    imgui.Dummy(imgui.ImVec2(0, 7))
    if optionButton(tr('reset_sensitivity'), false, 250, 'resetSensitivity') then
        restoreSensitivity()
        local resetValue = clamp(baseSensitivityX or DEFAULT_SENSITIVITY, 0.000050, 0.020000)
        for _, weapon in ipairs(sensitivityWeapons) do
            config.settings['sens_' .. weapon.id] = resetValue
            config.settings['sens_override_' .. weapon.id] = false
        end
        saveSettings()
    end
end

local function drawFunctions()
    local theme = themes[config.settings.theme]
    local width = imgui.GetContentRegionAvail().x
    sectionTitle(tr('functions_title'))
    mutedWrapped(tr('functions_hint'))

    imgui.Dummy(imgui.ImVec2(0, 8))
    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##infiniteRunCard', imgui.ImVec2(width, 70), false)
    imgui.SetCursorPos(imgui.ImVec2(15, 10))
    local infiniteRun = uiBool(config.settings.infinite_run)
    if imgui.Checkbox(tr('infinite_run') .. '##infinite_run', infiniteRun) then
        Runtime.setInfiniteRunEnabled(uiGet(infiniteRun))
    end
    imgui.SetCursorPos(imgui.ImVec2(15, 38))
    mutedWrapped(tr('infinite_run_hint'), width - 30)
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.Dummy(imgui.ImVec2(0, 15))
    sectionTitle(tr('fps_functions'))
    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##fpsFunctionsCard', imgui.ImVec2(width, 340), false)
    imgui.SetCursorPos(imgui.ImVec2(15, 10))
    local fpsBoost = uiBool(config.settings.fps_boost)
    if imgui.Checkbox(tr('fps_boost') .. '##fps_boost', fpsBoost) then
        config.settings.fps_boost = uiGet(fpsBoost)
        Runtime.applyFpsFeatures()
        saveSettings()
    end
    imgui.SetCursorPos(imgui.ImVec2(15, 38))
    mutedWrapped(tr('fps_boost_hint'), width - 30)

    imgui.SetCursorPos(imgui.ImVec2(15, 96))
    local fpsLock = uiBool(config.settings.fps_lock)
    if imgui.Checkbox(tr('fps_lock') .. '##fps_lock', fpsLock) then
        config.settings.fps_lock = uiGet(fpsLock)
        if config.settings.fps_lock then
            config.settings.fps_unlocker = false
            Runtime.applyFpsFeatures()
        end
        Runtime.applyFpsLock(true)
        saveSettings()
    end
    imgui.SetCursorPos(imgui.ImVec2(15, 123))
    mutedWrapped(tr('fps_lock_hint'), width - 30)
    imgui.SetCursorPos(imgui.ImVec2(15, 166))
    local fpsLimitChanged, fpsLimitValue = slimSlider(tr('fps_limit'), 'fpsLimit',
        config.settings.fps_limit, 20, 100, '%d FPS', width - 30, true)
    if fpsLimitChanged then
        config.settings.fps_limit = fpsLimitValue
        Runtime.applyFpsLock(true)
        saveSettings()
    end

    imgui.SetCursorPos(imgui.ImVec2(15, 207))
    local fpsUnlocker = uiBool(config.settings.fps_unlocker)
    if imgui.Checkbox(tr('fps_unlocker') .. '##fps_unlocker', fpsUnlocker) then
        config.settings.fps_unlocker = uiGet(fpsUnlocker)
        if config.settings.fps_unlocker then
            config.settings.fps_lock = false
            Runtime.applyFpsLock(true)
        end
        Runtime.applyFpsFeatures()
        saveSettings()
    end
    imgui.SetCursorPos(imgui.ImVec2(15, 235))
    mutedWrapped(tr('fps_unlocker_hint'), width - 30)
    imgui.SetCursorPos(imgui.ImVec2(15, imgui.GetCursorPosY() + 5))
    imgui.PushStyleColor(imgui.Col.Text, color(239, 170, 55))
    imgui.PushTextWrapPos(width - 15)
    imgui.Text(tr('fps_warning'))
    imgui.PopTextWrapPos()
    imgui.PopStyleColor()
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.Dummy(imgui.ImVec2(0, 15))
    sectionTitle(tr('world_overrides'))
    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##worldOverridesCard', imgui.ImVec2(width, 174), false)
    imgui.SetCursorPos(imgui.ImVec2(15, 10))
    local timeOverride = uiBool(config.settings.time_override)
    if imgui.Checkbox(tr('time_override') .. '##time_override', timeOverride) then
        Runtime.setTimeOverrideEnabled(uiGet(timeOverride))
    end
    imgui.SetCursorPos(imgui.ImVec2(250, 8))
    local timeChanged, timeValue = slimSlider(tr('time_hour'), 'timeHour',
        config.settings.time_hour, 0, 23, '%02d:00', width - 265, true)
    if timeChanged then
        config.settings.time_hour = timeValue
        saveSettings()
    end

    imgui.SetCursorPos(imgui.ImVec2(15, 61))
    local weatherOverride = uiBool(config.settings.weather_override)
    if imgui.Checkbox(tr('weather_override') .. '##weather_override', weatherOverride) then
        Runtime.setWeatherOverrideEnabled(uiGet(weatherOverride))
    end
    imgui.SetCursorPos(imgui.ImVec2(250, 59))
    local weatherChanged, weatherValue = slimSlider(tr('weather_id'), 'weatherId',
        config.settings.weather_id, 0, 22, 'ID %d', width - 265, true)
    if weatherChanged then
        config.settings.weather_id = weatherValue
        saveSettings()
    end
    imgui.SetCursorPos(imgui.ImVec2(15, 112))
    mutedWrapped(tr('world_hint'), width - 30)
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.Dummy(imgui.ImVec2(0, 15))
    sectionTitle(tr('bullet_track_title'))
    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##bulletTrackCard', imgui.ImVec2(width, 174), false)
    imgui.SetCursorPos(imgui.ImVec2(15, 10))
    local bulletTrack = uiBool(config.settings.bullet_track)
    if imgui.Checkbox(tr('bullet_track') .. '##bullet_track', bulletTrack) then
        if uiGet(bulletTrack) and not sampEventsAvailable then
            config.settings.bullet_track = false
            ghChat(tr('bullet_library_missing'))
        else
            config.settings.bullet_track = uiGet(bulletTrack)
            if not config.settings.bullet_track then
                Runtime.bulletTraces = {}
            end
        end
        saveSettings()
    end
    imgui.SetCursorPos(imgui.ImVec2(15, 39))
    mutedWrapped(tr('bullet_track_hint'), width - 30)
    if not sampEventsAvailable then
        imgui.SetCursorPos(imgui.ImVec2(15, 76))
        imgui.TextColored(color(239, 105, 105), tr('bullet_library_missing'))
    end
    imgui.SetCursorPos(imgui.ImVec2(15, 100))
    local bulletDistanceChanged, bulletDistanceValue = slimSlider(tr('bullet_track_distance'),
        'bulletDistance', config.settings.bullet_track_distance, 10.0, 100.0,
        '%.0f m', 255, false)
    if bulletDistanceChanged then
        config.settings.bullet_track_distance = bulletDistanceValue
        saveSettings()
    end
    imgui.SetCursorPos(imgui.ImVec2(295, 100))
    local bulletDurationChanged, bulletDurationValue = slimSlider(tr('bullet_track_duration'),
        'bulletDuration', config.settings.bullet_track_duration, 0.25, 2.0,
        '%.2f s', width - 310, false)
    if bulletDurationChanged then
        config.settings.bullet_track_duration = bulletDurationValue
        saveSettings()
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.Dummy(imgui.ImVec2(0, 15))
    sectionTitle(tr('change_skin_title'))
    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##changeSkinCard', imgui.ImVec2(width, 126), false)
    imgui.SetCursorPos(imgui.ImVec2(15, 10))
    local changeSkin = uiBool(config.settings.change_skin)
    if imgui.Checkbox(tr('change_skin') .. '##change_skin', changeSkin) then
        Runtime.setChangeSkinEnabled(uiGet(changeSkin))
    end
    imgui.SetCursorPos(imgui.ImVec2(250, 17))
    imgui.Text(tr('change_skin_id'))
    imgui.SetCursorPos(imgui.ImVec2(320, 8))
    local skinChanged, skinValue = preciseIntegerControl('changeSkinId',
        config.settings.change_skin_id, 0, 311, math.max(142, width - 335))
    if skinChanged then
        config.settings.change_skin_id = skinValue
        if not Runtime.validSkinId(skinValue) and config.settings.change_skin then
            Runtime.setChangeSkinEnabled(false)
            ghChat(tr('change_skin_invalid'))
        else
            Runtime.changeSkinApplyPending = config.settings.change_skin
        end
        saveSettings()
    end
    imgui.SetCursorPos(imgui.ImVec2(15, 62))
    mutedWrapped(tr('change_skin_hint'), width - 30)
    if config.settings.change_skin_id == 74 then
        imgui.SetCursorPos(imgui.ImVec2(15, 98))
        imgui.TextColored(color(239, 105, 105), tr('change_skin_invalid'))
    end
    imgui.EndChild()
    imgui.PopStyleColor()
end

local function persistColorPicker(prefix, picker)
    config.settings[prefix .. '_r'] = math.floor(uiGet(picker, 0) * 255 + 0.5)
    config.settings[prefix .. '_g'] = math.floor(uiGet(picker, 1) * 255 + 0.5)
    config.settings[prefix .. '_b'] = math.floor(uiGet(picker, 2) * 255 + 0.5)
    saveSettings()
end

local function drawColorPickerSetting(label, prefix, picker, id)
    local theme = themes[config.settings.theme]
    local popupId = '##colorPickerPopup' .. id
    local width, height = 44, 26
    local position = imgui.GetCursorScreenPos()

    imgui.PushStyleColor(imgui.Col.Button, color(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, color(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonActive, color(0, 0, 0, 0))
    local clicked = imgui.Button('##colorSwatch' .. id, imgui.ImVec2(width, height))
    local hovered = imgui.IsItemHovered()
    imgui.PopStyleColor(3)

    local drawList = imgui.GetWindowDrawList()
    local selectedColor = imgui.ImVec4(uiGet(picker, 0), uiGet(picker, 1), uiGet(picker, 2), 1.0)
    drawList:AddRectFilled(
        imgui.ImVec2(position.x, position.y + 2),
        imgui.ImVec2(position.x + width, position.y + height - 2),
        imgui.GetColorU32(selectedColor), 11)
    if hovered then
        drawList:AddCircleFilled(imgui.ImVec2(position.x + width - 5, position.y + 5),
            2.2, imgui.GetColorU32(theme.strong), 12)
    end

    local helper = tr('select_color')
    local helperSize = imgui.CalcTextSize(helper)
    drawList:AddText(
        imgui.ImVec2(position.x + width + 11, position.y + (height - helperSize.y) / 2),
        imgui.GetColorU32(theme.muted), helper)

    if clicked then
        imgui.OpenPopup(popupId)
    end

    if imgui.Cond and imgui.Cond.Appearing then
        imgui.SetNextWindowSize(imgui.ImVec2(300, 340), imgui.Cond.Appearing)
    end
    imgui.PushStyleVar(imgui.StyleVar.WindowPadding, imgui.ImVec2(14, 14))
    if imgui.BeginPopup(popupId) then
        local titlePushed = pushFont(uiFonts.title)
        imgui.Text(label)
        popFont(titlePushed)
        mutedText(tr('select_color'))
        imgui.Dummy(imgui.ImVec2(0, 5))

        local pickerFlags = 0
        if imgui.ColorEditFlags then
            pickerFlags = (imgui.ColorEditFlags.NoInputs or 0)
                + (imgui.ColorEditFlags.NoAlpha or 0)
                + (imgui.ColorEditFlags.NoLabel or 0)
                + (imgui.ColorEditFlags.PickerHueBar or 0)
        end
        local pickerWidthPushed = uiItemWidth(270)
        if imgui.ColorPicker4('##visualColorPicker' .. id, picker, pickerFlags) then
            persistColorPicker(prefix, picker)
        end
        uiEndItemWidth(pickerWidthPushed)
        imgui.EndPopup()
    end
    imgui.PopStyleVar()
end

local function drawOverlaySettings()
    local theme = themes[config.settings.theme]
    sectionTitle(tr('input_title'))
    mutedWrapped(tr('overlay_hint'))

    imgui.Dummy(imgui.ImVec2(0, 10))
    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##keyboardOverlayCard',
        imgui.ImVec2(imgui.GetContentRegionAvail().x, 132), true, NON_SCROLLING_CHILD_FLAGS)
    local keyboardCardPos = imgui.GetWindowPos()
    local keyboardCardWidth = imgui.GetWindowWidth()
    local keyboardCardDrawList = imgui.GetWindowDrawList()
    drawIosIcon('overlay', keyboardCardPos.x + imgui.GetWindowWidth() - 44, keyboardCardPos.y + 12, 28, true)
    imgui.SetCursorPos(imgui.ImVec2(15, 12))
    toggleSetting(tr('keyboard_enable'), 'keyboard_overlay')
    keyboardCardDrawList:AddLine(
        imgui.ImVec2(keyboardCardPos.x + 15, keyboardCardPos.y + 48),
        imgui.ImVec2(keyboardCardPos.x + keyboardCardWidth - 15, keyboardCardPos.y + 48),
        imgui.GetColorU32(theme.separator), 1.0)
    imgui.SetCursorPos(imgui.ImVec2(16, 57))
    mutedText(tr('keyboard_color'))
    imgui.SetCursorPos(imgui.ImVec2(16, 82))
    drawColorPickerSetting(tr('keyboard_color'), 'keyboard', keyboardColorPicker, 'Keyboard')
    imgui.SetCursorPos(imgui.ImVec2(310, 57))
    local keyboardOpacityChanged, keyboardOpacityValue = slimSlider(tr('keyboard_opacity'), 'keyboardOpacity',
        config.settings.keyboard_opacity, 0.0, 1.0, '%.2f', 230, false)
    if keyboardOpacityChanged then
        config.settings.keyboard_opacity = keyboardOpacityValue
        saveSettings()
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.Dummy(imgui.ImVec2(0, 8))
    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##mouseOverlayCard',
        imgui.ImVec2(imgui.GetContentRegionAvail().x, 132), true, NON_SCROLLING_CHILD_FLAGS)
    local mouseCardPos = imgui.GetWindowPos()
    local mouseCardWidth = imgui.GetWindowWidth()
    local mouseCardDrawList = imgui.GetWindowDrawList()
    drawIosIcon('sensitivity', mouseCardPos.x + imgui.GetWindowWidth() - 44, mouseCardPos.y + 12, 28, true)
    imgui.SetCursorPos(imgui.ImVec2(15, 12))
    toggleSetting(tr('mouse_enable'), 'mouse_overlay')
    mouseCardDrawList:AddLine(
        imgui.ImVec2(mouseCardPos.x + 15, mouseCardPos.y + 48),
        imgui.ImVec2(mouseCardPos.x + mouseCardWidth - 15, mouseCardPos.y + 48),
        imgui.GetColorU32(theme.separator), 1.0)
    imgui.SetCursorPos(imgui.ImVec2(16, 57))
    mutedText(tr('mouse_color'))
    imgui.SetCursorPos(imgui.ImVec2(16, 82))
    drawColorPickerSetting(tr('mouse_color'), 'mouse', mouseColorPicker, 'Mouse')
    imgui.SetCursorPos(imgui.ImVec2(310, 57))
    local mouseOpacityChanged, mouseOpacityValue = slimSlider(tr('mouse_opacity'), 'mouseOpacity',
        config.settings.mouse_opacity, 0.0, 1.0, '%.2f', 230, false)
    if mouseOpacityChanged then
        config.settings.mouse_opacity = mouseOpacityValue
        saveSettings()
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.Dummy(imgui.ImVec2(0, 8))
    mutedWrapped(tr('color_picker_hint'))
    mutedWrapped(tr('overlay_style_hint'))
    imgui.Dummy(imgui.ImVec2(0, 3))

    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##overlayAppearanceCard', imgui.ImVec2(imgui.GetContentRegionAvail().x, 132), true)
    imgui.SetCursorPos(imgui.ImVec2(15, 8))
    local scaleChanged, scaleValue = slimSlider(tr('overlay_scale'), 'overlayScale',
        config.settings.overlay_scale, 0.25, 1.5, '%.2fx', 535, false)
    if scaleChanged then
        config.settings.overlay_scale = scaleValue
        saveSettings()
    end

    imgui.SetCursorPos(imgui.ImVec2(15, 47))
    local roundingChanged, roundingValue = slimSlider(tr('overlay_rounding'), 'overlayRounding',
        config.settings.overlay_rounding, 0.0, 12.0, '%.1f px', 535, false)
    if roundingChanged then
        config.settings.overlay_rounding = roundingValue
        saveSettings()
    end

    imgui.SetCursorPos(imgui.ImVec2(15, 86))
    local spacingChanged, spacingValue = slimSlider(tr('overlay_spacing'), 'overlaySpacing',
        config.settings.overlay_spacing, 2.0, 8.0, '%.1f px', 255, false)
    if spacingChanged then
        config.settings.overlay_spacing = spacingValue
        saveSettings()
    end
    imgui.SetCursorPos(imgui.ImVec2(295, 86))
    local borderChanged, borderValue = slimSlider(tr('overlay_border'), 'overlayBorder',
        config.settings.overlay_border, 0.75, 3.0, '%.2f', 255, false)
    if borderChanged then
        config.settings.overlay_border = borderValue
        saveSettings()
    end
    imgui.EndChild()
    imgui.PopStyleColor()
end

local function resetAllSettings()
    restoreSensitivity()
    if config.settings.change_skin then
        Runtime.setChangeSkinEnabled(false)
    end
    pcall(setPlayerNeverGetsTired, PLAYER_HANDLE, false)
    pcall(releaseWeather)
    if Runtime.timeOverrideStored then
        pcall(restoreClock)
        Runtime.timeOverrideStored = false
    end
    for field, value in pairs(defaults.settings) do
        config.settings[field] = value
    end
    Runtime.restoreFpsFeatures()
    Runtime.applyFpsLock(true)
    Runtime.bulletTraces = {}
    captureField = nil
    commandInlineBuffers = {}
    syncTextBuffers()
    applyTheme(config.settings.theme)
    languageToggleAnim = config.settings.language == 2 and 1.0 or 0.0
    themeToggleAnim = config.settings.theme == 2 and 1.0 or 0.0
    saveSettings()
end

local function drawSettings()
    local theme = themes[config.settings.theme]
    sectionTitle(tr('appearance'))
    imgui.Text(tr('language'))
    if optionButton('RO', config.settings.language == 1, 92, 'settingsLanguageRo') then
        config.settings.language = 1
        saveSettings()
    end
    imgui.SameLine()
    if optionButton('EN', config.settings.language == 2, 92, 'settingsLanguageEn') then
        config.settings.language = 2
        saveSettings()
    end
    imgui.SameLine(0, 14)
    mutedText(tr('language_hint'))

    imgui.Dummy(imgui.ImVec2(0, 5))
    imgui.Text(tr('theme'))
    if optionButton(tr('dark_theme'), config.settings.theme == 1, 132, 'settingsThemeDark') then
        setThemeMode(1)
    end
    imgui.SameLine()
    if optionButton(tr('light_theme'), config.settings.theme == 2, 132, 'settingsThemeLight') then
        setThemeMode(2)
    end

    imgui.Dummy(imgui.ImVec2(0, 15))
    drawServer()
    imgui.Dummy(imgui.ImVec2(0, 17))
    sectionTitle(tr('controls'))
    toggleSetting(tr('open_delete'), 'open_on_delete')
    mutedWrapped(tr('open_delete_hint'))

    imgui.Dummy(imgui.ImVec2(0, 13))
    imgui.PushStyleColor(imgui.Col.Button, theme.side)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, theme.panelHover)
    if imgui.Button(tr('reset_all'), imgui.ImVec2(196, 30)) then
        resetAllSettings()
        ghChat(tr('reset_done'))
    end
    imgui.PopStyleColor(2)
end

local function drawCurrentPage()
    if currentPage == 1 then
        drawHome()
    elseif currentPage == 2 then
        drawWeapons()
    elseif currentPage == 3 then
        drawSensitivity()
    elseif currentPage == 4 then
        drawFunctions()
    elseif currentPage == 5 then
        drawOverlaySettings()
    elseif currentPage == 6 then
        drawShortcuts()
    else
        drawSettings()
    end
end

local pageTranslationKeys = {
    'home', 'weapons', 'sensitivity', 'functions', 'overlay_nav', 'shortcuts', 'settings'
}

local function initializeImguiTheme()
    local io = imgui.GetIO()
    if not legacyImgui then
        io.IniFilename = nil
    end

    local fontsDirectory = 'C:\\Windows\\Fonts'
    if type(getFolderPath) == 'function' then
        local pathFound, pathValue = pcall(getFolderPath, 0x14)
        if pathFound and type(pathValue) == 'string' and pathValue ~= '' then
            fontsDirectory = pathValue
        end
    end
    local regularFontCandidates = {
        fontsDirectory .. '\\SegUIVar.ttf',
        fontsDirectory .. '\\segoeui.ttf',
        fontsDirectory .. '\\tahoma.ttf',
        fontsDirectory .. '\\arial.ttf'
    }
    local semiboldFontCandidates = {
        fontsDirectory .. '\\seguisb.ttf',
        fontsDirectory .. '\\segoeuib.ttf',
        fontsDirectory .. '\\tahomabd.ttf',
        fontsDirectory .. '\\arialbd.ttf'
    }
    local function firstExistingFont(candidates)
        for _, candidate in ipairs(candidates) do
            if doesFileExist(candidate) then
                return candidate
            end
        end
        return nil
    end
    local regularFontPath = firstExistingFont(regularFontCandidates)
    local semiboldFontPath = firstExistingFont(semiboldFontCandidates) or regularFontPath

    if regularFontPath and legacyImgui then
        local ranges = nil
        if imgui.ImGlyphRanges then
            local rangeCreated, rangeValue = pcall(imgui.ImGlyphRanges, { 0x0020, 0x024F, 0x2013, 0x2014 })
            if rangeCreated then
                legacyRomanianGlyphRanges = rangeValue
                ranges = legacyRomanianGlyphRanges
            end
        end
        io.Fonts:Clear()
        uiFonts.body = io.Fonts:AddFontFromFileTTF(regularFontPath, 13.5, nil, ranges)
        uiFonts.semibold = io.Fonts:AddFontFromFileTTF(semiboldFontPath, 13.8, nil, ranges)
        uiFonts.title = io.Fonts:AddFontFromFileTTF(semiboldFontPath, 18.5, nil, ranges)
        uiFonts.hero = io.Fonts:AddFontFromFileTTF(semiboldFontPath, 22.0, nil, ranges)
        if imgui.RebuildFonts then
            imgui.RebuildFonts()
        end
    elseif regularFontPath then
        uiFonts.body = io.Fonts:AddFontFromFileTTF(regularFontPath, 13.5, nil, romanianGlyphRanges)
        uiFonts.semibold = io.Fonts:AddFontFromFileTTF(semiboldFontPath, 13.8, nil, romanianGlyphRanges)
        uiFonts.title = io.Fonts:AddFontFromFileTTF(semiboldFontPath, 18.5, nil, romanianGlyphRanges)
        uiFonts.hero = io.Fonts:AddFontFromFileTTF(semiboldFontPath, 22.0, nil, romanianGlyphRanges)
    end

    applyTheme(config.settings.theme)
end

if not legacyImgui then
    imgui.OnInitialize(initializeImguiTheme)
end

local function drawSidebarLiveCard(theme, cardWidth)
    local serverName = liveSidebarData()
    cardWidth = cardWidth or (UI_LAYOUT.sidebarWidth - UI_LAYOUT.sidebarInset * 2)
    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##systemStatusCard', imgui.ImVec2(cardWidth, 110), false)

    local rows = {
        { tr('player_name'), getLocalPlayerName() },
        { tr('server_name'), serverName },
        { tr('session'), currentSessionLabel() }
    }
    for index, row in ipairs(rows) do
        local rowY = 5 + (index - 1) * 34
        imgui.SetCursorPos(imgui.ImVec2(11, rowY))
        mutedText(row[1])
        imgui.SetCursorPos(imgui.ImVec2(11, rowY + 14))
        imgui.TextColored(theme.text, fittedText(row[2], cardWidth - 22))
    end
    imgui.EndChild()
    imgui.PopStyleColor()
end

local function updateStatusText()
    if Updater.state == 'checking' then
        return tr('update_checking')
    elseif Updater.state == 'current' then
        return tr('update_current')
    elseif Updater.state == 'available' then
        return tr('update_available') .. ' ' .. tostring(Updater.message)
    elseif Updater.state == 'downloading' then
        return tr('update_downloading')
    elseif Updater.state == 'installing' then
        return tr('update_installing')
    elseif Updater.state == 'error' then
        return tr('update_error')
    elseif Updater.state == 'unconfigured' then
        return tr('update_unconfigured')
    end
    return tr('update_idle')
end

local function drawUpdateCenter(theme, notificationHovered)
    if not Updater.centerOpen then
        return
    end

    local width, height = 334, 320
    imgui.SetCursorPos(imgui.ImVec2(UI_LAYOUT.menuWidth - width - 12,
        UI_LAYOUT.headerHeight + 9))
    local centerScreenPos = imgui.GetCursorScreenPos()
    local clickOk, clicked = pcall(function()
        return imgui.IsMouseClicked(0)
    end)
    if not clickOk then
        clicked = wasKeyPressed(vkeys.VK_LBUTTON or 1)
    end
    if clicked and not notificationHovered then
        local mouseOk, mouseX, mouseY = pcall(function()
            local mousePosition = imgui.GetIO().MousePos
            return tonumber(mousePosition.x), tonumber(mousePosition.y)
        end)
        local insideCenter = mouseOk and mouseX and mouseY
            and mouseX >= centerScreenPos.x and mouseX <= centerScreenPos.x + width
            and mouseY >= centerScreenPos.y and mouseY <= centerScreenPos.y + height
        if not insideCenter then
            Updater.centerOpen = false
            return
        end
    end
    imgui.PushStyleColor(CHILD_BG_COLOR, theme.panel)
    imgui.BeginChild('##notificationUpdateCenter', imgui.ImVec2(width, height), true)
    local centerPos = imgui.GetWindowPos()
    drawIosIcon('notification', centerPos.x + 15, centerPos.y + 14, 25, true)
    imgui.SetCursorPos(imgui.ImVec2(52, 15))
    local titlePushed = pushFont(uiFonts.semibold)
    imgui.TextColored(theme.text, tr('notifications_update'))
    popFont(titlePushed)

    imgui.SetCursorPos(imgui.ImVec2(width - 35, 8))
    imgui.PushStyleColor(imgui.Col.Button, color(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, theme.controlHover)
    imgui.PushStyleColor(imgui.Col.ButtonActive, theme.buttonActive)
    if imgui.Button('x##closeUpdateCenter', imgui.ImVec2(27, 27)) then
        Updater.centerOpen = false
    end
    imgui.PopStyleColor(3)

    imgui.SetCursorPos(imgui.ImVec2(15, 52))
    local statusColor = Updater.available and color(239, 76, 76)
        or (Updater.state == 'error' and color(239, 105, 105) or theme.muted)
    imgui.PushStyleColor(imgui.Col.Text, statusColor)
    imgui.PushTextWrapPos(width - 15)
    imgui.Text(updateStatusText())
    imgui.PopTextWrapPos()
    imgui.PopStyleColor()

    if Updater.state == 'downloading' or Updater.state == 'installing' then
        local progressPosition = imgui.ImVec2(centerPos.x + 15, centerPos.y + 98)
        local drawList = imgui.GetWindowDrawList()
        drawList:AddRectFilled(progressPosition,
            imgui.ImVec2(progressPosition.x + width - 30, progressPosition.y + 4),
            imgui.GetColorU32(theme.separator), 2)
        drawList:AddRectFilled(progressPosition,
            imgui.ImVec2(progressPosition.x + (width - 30) * clamp(Updater.progress, 0, 1),
                progressPosition.y + 4), imgui.GetColorU32(theme.blue), 2)
    end

    imgui.SetCursorPos(imgui.ImVec2(15, 116))
    local autoCheck = uiBool(config.settings.update_auto_check)
    if imgui.Checkbox(tr('update_auto_check') .. '##updateAutoCheck', autoCheck) then
        config.settings.update_auto_check = uiGet(autoCheck)
        saveSettings()
    end

    imgui.SetCursorPos(imgui.ImVec2(15, 151))
    imgui.PushStyleColor(imgui.Col.Button, theme.control)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, theme.controlHover)
    imgui.PushStyleColor(imgui.Col.ButtonActive, theme.buttonActive)
    if imgui.Button(tr('update_check') .. '##checkUpdate', imgui.ImVec2(143, 30)) then
        Updater.checkForUpdates()
    end
    if Updater.available then
        imgui.SameLine()
        imgui.PushStyleColor(imgui.Col.Button, color(207, 55, 55))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, color(226, 67, 67))
        imgui.PushStyleColor(imgui.Col.ButtonActive, color(178, 42, 42))
        imgui.PushStyleColor(imgui.Col.Text, color(255, 255, 255))
        if imgui.Button(tr('update_now') .. '##installUpdate', imgui.ImVec2(143, 30)) then
            Updater.installAvailableUpdate()
        end
        imgui.PopStyleColor(4)
    end
    imgui.PopStyleColor(3)

    imgui.SetCursorPos(imgui.ImVec2(15, 198))
    local changelog = Updater.updateChangelogText(Updater.manifest)
    if changelog ~= '' then
        local labelPushed = pushFont(uiFonts.semibold)
        imgui.TextColored(theme.text, tr('update_changelog'))
        popFont(labelPushed)
        imgui.SetCursorPos(imgui.ImVec2(15, 222))
        mutedWrapped(changelog, width - 30)
    else
        mutedWrapped(tr('update_backup'), width - 30)
    end
    imgui.EndChild()
    imgui.PopStyleColor()
end

local function drawMainMenu()
    local display = imgui.GetIO().DisplaySize
    imgui.SetNextWindowSize(imgui.ImVec2(UI_LAYOUT.menuWidth, UI_LAYOUT.menuHeight), imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(display.x / 2, display.y / 2),
        imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))

    local flags = imgui.WindowFlags.NoTitleBar
        + imgui.WindowFlags.NoResize
        + imgui.WindowFlags.NoCollapse
        + imgui.WindowFlags.NoScrollbar

    local rootAlphaPushed = false
    if imgui.StyleVar and imgui.StyleVar.Alpha ~= nil then
        imgui.PushStyleVar(imgui.StyleVar.Alpha, clamp(menuFade, 0.01, 1.0))
        rootAlphaPushed = true
    end
    local fontPushed = pushFont(uiFonts.body)
    if imgui.Begin('##GangHelperBeta211', windowOpen, flags) then
        local theme = themes[config.settings.theme]
        local windowPos = imgui.GetWindowPos()
        local windowDrawList = imgui.GetWindowDrawList()
        local bodyHeight = UI_LAYOUT.menuHeight - UI_LAYOUT.headerHeight - UI_LAYOUT.footerHeight
        local footerY = UI_LAYOUT.menuHeight - UI_LAYOUT.footerHeight

        windowDrawList:AddRectFilled(
            imgui.ImVec2(windowPos.x + 1, windowPos.y + 1),
            imgui.ImVec2(windowPos.x + UI_LAYOUT.menuWidth - 1, windowPos.y + UI_LAYOUT.headerHeight),
            imgui.GetColorU32(theme.header), 11)
        windowDrawList:AddRectFilled(
            imgui.ImVec2(windowPos.x + 1, windowPos.y + UI_LAYOUT.headerHeight / 2),
            imgui.ImVec2(windowPos.x + UI_LAYOUT.menuWidth - 1, windowPos.y + UI_LAYOUT.headerHeight),
            imgui.GetColorU32(theme.header), 0)
        windowDrawList:AddRectFilled(
            imgui.ImVec2(windowPos.x + 1, windowPos.y + footerY),
            imgui.ImVec2(windowPos.x + UI_LAYOUT.menuWidth - 1, windowPos.y + UI_LAYOUT.menuHeight - 1),
            imgui.GetColorU32(theme.header), 11)
        windowDrawList:AddRectFilled(
            imgui.ImVec2(windowPos.x + 1, windowPos.y + footerY),
            imgui.ImVec2(windowPos.x + UI_LAYOUT.menuWidth - 1,
                windowPos.y + footerY + UI_LAYOUT.footerHeight / 2),
            imgui.GetColorU32(theme.header), 0)

        windowDrawList:AddCircleFilled(imgui.ImVec2(windowPos.x + 22, windowPos.y + 23),
            5.0, imgui.GetColorU32(color(255, 95, 87)))
        windowDrawList:AddCircleFilled(imgui.ImVec2(windowPos.x + 42, windowPos.y + 23),
            5.0, imgui.GetColorU32(color(255, 189, 46)))
        windowDrawList:AddCircleFilled(imgui.ImVec2(windowPos.x + 62, windowPos.y + 23),
            5.0, imgui.GetColorU32(color(40, 200, 64)))
        local headerFontPushed = pushFont(uiFonts.semibold)
        local headerTitleHeight = imgui.CalcTextSize('GANG HELPER').y
        imgui.SetCursorPos(imgui.ImVec2(92,
            math.floor((UI_LAYOUT.headerHeight - headerTitleHeight) / 2) - 1))
        imgui.TextColored(theme.text, 'GANG HELPER')
        popFont(headerFontPushed)

        imgui.SetCursorPos(imgui.ImVec2(UI_LAYOUT.menuWidth - 185, 10))
        if compactToggleButton('headerTheme', themeToggleAnim, '', '', true) then
            setThemeMode(config.settings.theme == 1 and 2 or 1)
        end

        imgui.SetCursorPos(imgui.ImVec2(UI_LAYOUT.menuWidth - 127, 10))
        if compactToggleButton('headerLanguage', languageToggleAnim, 'RO', 'EN', false) then
            config.settings.language = config.settings.language == 1 and 2 or 1
            saveSettings()
        end

        local notificationHovered = false
        imgui.SetCursorPos(imgui.ImVec2(UI_LAYOUT.menuWidth - 69, 10))
        imgui.PushStyleColor(imgui.Col.Button, color(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, theme.controlHover)
        imgui.PushStyleColor(imgui.Col.ButtonActive, theme.buttonActive)
        if imgui.Button('##headerNotifications', imgui.ImVec2(26, 26)) then
            Updater.centerOpen = not Updater.centerOpen
            if Updater.centerOpen and Updater.state == 'idle' then
                Updater.checkForUpdates()
            end
        end
        notificationHovered = imgui.IsItemHovered()
        imgui.PopStyleColor(3)
        drawIosIcon('notification', windowPos.x + UI_LAYOUT.menuWidth - 66,
            windowPos.y + 13, 20, Updater.centerOpen)
        if Updater.available then
            windowDrawList:AddCircleFilled(
                imgui.ImVec2(windowPos.x + UI_LAYOUT.menuWidth - 47, windowPos.y + 12),
                4.0, imgui.GetColorU32(color(239, 76, 76)), 16)
        end

        imgui.SetCursorPos(imgui.ImVec2(UI_LAYOUT.menuWidth - 35, 10))
        imgui.PushStyleColor(imgui.Col.Button, color(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, theme.controlHover)
        imgui.PushStyleColor(imgui.Col.ButtonActive, theme.buttonActive)
        imgui.PushStyleColor(imgui.Col.Text, theme.muted)
        if imgui.Button('x##close', imgui.ImVec2(25, 25)) then
            requestMenu(false)
        end
        imgui.PopStyleColor(4)

        imgui.SetCursorPos(imgui.ImVec2(0, UI_LAYOUT.headerHeight))
        imgui.PushStyleColor(CHILD_BG_COLOR, theme.side)
        imgui.BeginChild('##sidebar', imgui.ImVec2(UI_LAYOUT.sidebarWidth, bodyHeight), false)
        local sidebarPos = imgui.GetWindowPos()
        local sidebarDrawList = imgui.GetWindowDrawList()
        sidebarDrawList:AddLine(
            imgui.ImVec2(sidebarPos.x + UI_LAYOUT.sidebarWidth - 1, sidebarPos.y),
            imgui.ImVec2(sidebarPos.x + UI_LAYOUT.sidebarWidth - 1, sidebarPos.y + bodyHeight),
            imgui.GetColorU32(theme.separator), 1.0)

        imgui.SetCursorPos(imgui.ImVec2(UI_LAYOUT.sidebarInset, 18))
        for page, key in ipairs(pageTranslationKeys) do
            navButton(tr(key), page)
            imgui.SetCursorPosX(UI_LAYOUT.sidebarInset)
            imgui.Dummy(imgui.ImVec2(0, 1))
            imgui.SetCursorPosX(UI_LAYOUT.sidebarInset)
        end

        imgui.SetCursorPos(imgui.ImVec2(UI_LAYOUT.sidebarInset, bodyHeight - 120))
        drawSidebarLiveCard(theme, UI_LAYOUT.sidebarWidth - UI_LAYOUT.sidebarInset * 2)
        imgui.EndChild()
        imgui.PopStyleColor()

        imgui.SetCursorPos(imgui.ImVec2(UI_LAYOUT.sidebarWidth, UI_LAYOUT.headerHeight))
        imgui.PushStyleColor(CHILD_BG_COLOR, theme.bg)
        imgui.BeginChild('##content', imgui.ImVec2(UI_LAYOUT.contentWidth, bodyHeight), false)
        imgui.SetCursorPos(imgui.ImVec2(UI_LAYOUT.pageHorizontalMargin, UI_LAYOUT.pageTop))
        local pageAlphaPushed = false
        if imgui.StyleVar and imgui.StyleVar.Alpha ~= nil then
            imgui.PushStyleVar(imgui.StyleVar.Alpha, math.min(menuFade, pageFade))
            pageAlphaPushed = true
        end
        imgui.PushStyleColor(CHILD_BG_COLOR, color(0, 0, 0, 0))
        imgui.BeginChild('##pageContent', imgui.ImVec2(
            UI_LAYOUT.contentWidth - UI_LAYOUT.pageHorizontalMargin * 2,
            bodyHeight - UI_LAYOUT.pageTop - UI_LAYOUT.pageBottomMargin), false)
        drawCurrentPage()
        imgui.EndChild()
        imgui.PopStyleColor()
        if pageAlphaPushed then
            imgui.PopStyleVar()
        end
        imgui.EndChild()
        imgui.PopStyleColor()

        drawUpdateCenter(theme, notificationHovered)

        local footerTextHeight = imgui.CalcTextSize('CONNECTED').y
        local footerLeftY = windowPos.y + footerY
            + math.floor((UI_LAYOUT.footerHeight - footerTextHeight) / 2) - 1
        windowDrawList:AddCircleFilled(
            imgui.ImVec2(windowPos.x + 20, windowPos.y + footerY + UI_LAYOUT.footerHeight / 2 - 1),
            3.5, imgui.GetColorU32(theme.green), 12)
        windowDrawList:AddText(imgui.ImVec2(windowPos.x + 30, footerLeftY),
            imgui.GetColorU32(theme.muted), 'CONNECTED')
        local fps = tonumber(imgui.GetIO().Framerate) or currentFrameRate()
        local fpsText = string.format('%3d FPS', math.floor(fps + 0.5))
        windowDrawList:AddText(imgui.ImVec2(windowPos.x + 109, footerLeftY),
            imgui.GetColorU32(theme.separator), '|')
        windowDrawList:AddText(imgui.ImVec2(windowPos.x + 122, footerLeftY),
            imgui.GetColorU32(theme.muted), fpsText)

        local footerRightEdge = windowPos.x + UI_LAYOUT.menuWidth - 18
        local versionText = (config.settings.language == 2 and 'VERSION ' or 'VERSIUNEA ')
            .. VERSION:upper()
        local versionTextSize = imgui.CalcTextSize(versionText)
        local authorText = 'BY SEMAKA'
        local authorTextSize = imgui.CalcTextSize(authorText)
        local authorX = footerRightEdge - authorTextSize.x
        local separatorX = authorX - 13
        windowDrawList:AddText(
            imgui.ImVec2(separatorX - versionTextSize.x - 13, footerLeftY),
            imgui.GetColorU32(theme.muted), versionText)
        windowDrawList:AddText(imgui.ImVec2(separatorX, footerLeftY),
            imgui.GetColorU32(theme.separator), '|')
        windowDrawList:AddText(
            imgui.ImVec2(authorX, footerLeftY),
            imgui.GetColorU32(theme.muted), authorText)
    end
    imgui.End()
    popFont(fontPushed)
    if rootAlphaPushed then
        imgui.PopStyleVar()
    end
end

local menuDrawErrorReported = false
local function safeDrawMainMenu()
    local drawn, drawError = pcall(drawMainMenu)
    if drawn then
        return
    end
    menuTargetOpen = false
    menuFade = 0.0
    uiSet(windowOpen, false)
    if not menuDrawErrorReported then
        menuDrawErrorReported = true
        print('[Gang Helper] Menu error: ' .. tostring(drawError))
        ghChat(tr('menu_error') .. ' ' .. tostring(drawError))
    end
end

local menuFrame = nil
if legacyImgui then
    imgui.LockPlayer = false
    function imgui.OnDrawFrame()
        imgui.ShowCursor = menuShouldRender()
        if menuShouldRender() then
            safeDrawMainMenu()
        end
    end
else
    menuFrame = imgui.OnFrame(function()
        return menuShouldRender()
    end, safeDrawMainMenu)
    menuFrame.LockPlayer = false
    menuFrame.HideCursor = false
end

function Runtime.argb(alpha, red, green, blue)
    return bit.bor(
        bit.lshift(clamp(math.floor(alpha), 0, 255), 24),
        bit.lshift(clamp(math.floor(red), 0, 255), 16),
        bit.lshift(clamp(math.floor(green), 0, 255), 8),
        clamp(math.floor(blue), 0, 255)
    )
end

function Runtime.overlayColor(prefix, alpha)
    return Runtime.argb(alpha,
        config.settings[prefix .. '_r'],
        config.settings[prefix .. '_g'],
        config.settings[prefix .. '_b'])
end

function Runtime.overlayContrastText(prefix, alpha)
    local red = config.settings[prefix .. '_r']
    local green = config.settings[prefix .. '_g']
    local blue = config.settings[prefix .. '_b']
    local luminance = red * 0.299 + green * 0.587 + blue * 0.114
    if luminance > 165 then
        return Runtime.argb(alpha, 24, 24, 27)
    end
    return Runtime.argb(alpha, 255, 255, 255)
end

function Runtime.renderRoundedBox(x, y, width, height, radius, boxColor)
    if width <= 0 or height <= 0 then
        return
    end
    radius = clamp(tonumber(radius) or 0, 0, math.min(width, height) / 2)
    if radius < 1.0 then
        renderDrawBox(x, y, width, height, boxColor)
        return
    end

    renderDrawBox(x + radius, y, math.max(0, width - radius * 2), height, boxColor)
    renderDrawBox(x, y + radius, width, math.max(0, height - radius * 2), boxColor)
    local segments = math.max(1, math.min(6, math.ceil(radius)))
    local segmentHeight = radius / segments
    for segment = 0, segments - 1 do
        local rowY = segment * segmentHeight
        local distance = radius - (rowY + segmentHeight * 0.5)
        local inset = radius - math.sqrt(math.max(0, radius * radius - distance * distance))
        local rowWidth = math.max(0, width - inset * 2)
        renderDrawBox(x + inset, y + rowY, rowWidth, segmentHeight + 0.10, boxColor)
        renderDrawBox(x + inset, y + height - rowY - segmentHeight, rowWidth, segmentHeight + 0.10, boxColor)
    end
end

function Runtime.overlayDimensions(kind)
    local scale = config.settings.overlay_scale
    local gap = config.settings.overlay_spacing
    if kind == 'keyboard' then
        return (274 + gap * 5) * scale, (160 + gap * 4) * scale
    end
    return (194 + gap * 3) * scale, (105 + gap * 2) * scale
end

function Runtime.currentOverlayFont()
    local scale = config.settings.overlay_scale
    if scale < 0.42 then
        return overlayFonts.tiny
    elseif scale < 0.72 then
        return overlayFonts.small
    elseif scale < 1.18 then
        return overlayFonts.normal
    end
    return overlayFonts.large
end

function Runtime.drawOverlayTextCentered(font, text, x, y, width, height, textColor)
    local renderedText = toGameEncoding(text)
    local textWidth = renderGetFontDrawTextLength(font, renderedText)
    local textHeight = renderGetFontDrawHeight(font)
    renderFontDrawText(font, renderedText,
        math.floor(x + (width - textWidth) / 2),
        math.floor(y + (height - textHeight) / 2),
        textColor)
end

function Runtime.drawOverlayKey(label, keyCode, x, y, width, height, prefix, forcedPressed)
    local font = Runtime.currentOverlayFont()
    if not font then
        return
    end
    local pressed = forcedPressed == true or (keyCode and isKeyDown(keyCode))
    local opacity = config.settings[prefix .. '_opacity']
    local scale = config.settings.overlay_scale
    local radius = config.settings.overlay_rounding * scale
    local border = math.max(0.6, config.settings.overlay_border * scale)
    local outlineAlpha = math.floor(255 * opacity * (pressed and 1.0 or 0.82))
    local inactiveAlpha = math.floor(255 * opacity * 0.18)
    local pressedAlpha = math.floor(255 * opacity * 0.88)
    local textAlpha = math.floor(255 * opacity)
    local accent = Runtime.overlayColor(prefix, outlineAlpha)
    local textColor = pressed and Runtime.overlayContrastText(prefix, textAlpha) or Runtime.overlayColor(prefix, textAlpha)
    local shadowOffset = math.max(0.75, 1.5 * scale)
    Runtime.renderRoundedBox(x, y + shadowOffset, width, height, radius, Runtime.argb(math.floor(90 * opacity), 0, 0, 0))
    Runtime.renderRoundedBox(x, y, width, height, radius, accent)
    Runtime.renderRoundedBox(x + border, y + border, width - border * 2, height - border * 2,
        math.max(0, radius - border),
        pressed and Runtime.overlayColor(prefix, pressedAlpha) or Runtime.overlayColor(prefix, inactiveAlpha))
    Runtime.drawOverlayTextCentered(font, label, x, y, width, height, textColor)
end

local wheelUpUntil = 0
local wheelDownUntil = 0

function Runtime.drawKeyboardRenderOverlay()
    if not Runtime.currentOverlayFont() then
        return
    end
    local scale = config.settings.overlay_scale
    local x, y = config.settings.keyboard_x, config.settings.keyboard_y
    local width = Runtime.overlayDimensions('keyboard')
    local gap, keyWidth, keyHeight = config.settings.overlay_spacing * scale, 38 * scale, 30 * scale

    local rowY = y + 5 * scale
    local numberWidth = keyWidth * 5 + gap * 4
    local rowX = x + (width - numberWidth) / 2
    for key = 49, 53 do
        Runtime.drawOverlayKey(string.char(key), key, rowX, rowY, keyWidth, keyHeight, 'keyboard')
        rowX = rowX + keyWidth + gap
    end

    rowY = rowY + keyHeight + gap
    local tabRowWidth = 55 * scale + keyWidth * 5 + gap * 5
    rowX = x + (width - tabRowWidth) / 2
    Runtime.drawOverlayKey('TAB', 9, rowX, rowY, 55 * scale, keyHeight, 'keyboard')
    rowX = rowX + 55 * scale + gap
    for _, key in ipairs({ 81, 87, 69, 82, 84 }) do
        Runtime.drawOverlayKey(string.char(key), key, rowX, rowY, keyWidth, keyHeight, 'keyboard')
        rowX = rowX + keyWidth + gap
    end

    rowY = rowY + keyHeight + gap
    local capsRowWidth = 64 * scale + keyWidth * 5 + gap * 5
    rowX = x + (width - capsRowWidth) / 2
    Runtime.drawOverlayKey('CAPS', 20, rowX, rowY, 64 * scale, keyHeight, 'keyboard')
    rowX = rowX + 64 * scale + gap
    for _, key in ipairs({ 65, 83, 68, 70, 71 }) do
        Runtime.drawOverlayKey(string.char(key), key, rowX, rowY, keyWidth, keyHeight, 'keyboard')
        rowX = rowX + keyWidth + gap
    end

    rowY = rowY + keyHeight + gap
    local shiftWidth = 70 * scale
    local shiftRowWidth = shiftWidth + keyWidth * 4 + gap * 4
    rowX = x + (width - shiftRowWidth) / 2
    Runtime.drawOverlayKey('SHIFT', 16, rowX, rowY, shiftWidth, keyHeight, 'keyboard')
    rowX = rowX + shiftWidth + gap
    for _, key in ipairs({ 90, 88, 67, 86 }) do
        Runtime.drawOverlayKey(string.char(key), key, rowX, rowY, keyWidth, keyHeight, 'keyboard')
        rowX = rowX + keyWidth + gap
    end

    rowY = rowY + keyHeight + gap
    local ctrlWidth, altWidth, spaceWidth = 60 * scale, 50 * scale, 126 * scale
    local bottomRowWidth = ctrlWidth + altWidth + spaceWidth + gap * 2
    rowX = x + (width - bottomRowWidth) / 2
    Runtime.drawOverlayKey('CTRL', 17, rowX, rowY, ctrlWidth, keyHeight, 'keyboard')
    rowX = rowX + ctrlWidth + gap
    Runtime.drawOverlayKey('ALT', 18, rowX, rowY, altWidth, keyHeight, 'keyboard')
    rowX = rowX + altWidth + gap
    Runtime.drawOverlayKey('SPACE', 32, rowX, rowY, spaceWidth, keyHeight, 'keyboard')
end

function Runtime.drawMouseRenderOverlay()
    if not Runtime.currentOverlayFont() then
        return
    end
    local scale = config.settings.overlay_scale
    local x, y = config.settings.mouse_x, config.settings.mouse_y
    local width = Runtime.overlayDimensions('mouse')
    local gap = config.settings.overlay_spacing * scale

    local wheelWidth, wheelHeight = 46 * scale, 26 * scale
    local rowX, rowY = x + (width - wheelWidth) / 2, y + 2 * scale
    Runtime.drawOverlayKey('WU', nil, rowX, rowY, wheelWidth, wheelHeight, 'mouse', getGameTimer() < wheelUpUntil)

    local topRowWidth = (58 + 50 + 58) * scale + gap * 2
    rowX, rowY = x + (width - topRowWidth) / 2, rowY + wheelHeight + gap
    Runtime.drawOverlayKey('LMB', 1, rowX, rowY, 58 * scale, 43 * scale, 'mouse')
    rowX = rowX + 58 * scale + gap
    Runtime.drawOverlayKey('MMB', 4, rowX, rowY, 50 * scale, 43 * scale, 'mouse')
    rowX = rowX + 50 * scale + gap
    Runtime.drawOverlayKey('RMB', 2, rowX, rowY, 58 * scale, 43 * scale, 'mouse')

    local bottomRowWidth = (42 + 46 + 42) * scale + gap * 2
    rowX, rowY = x + (width - bottomRowWidth) / 2, rowY + 43 * scale + gap
    Runtime.drawOverlayKey('M4', 5, rowX, rowY, 42 * scale, 28 * scale, 'mouse')
    rowX = rowX + 42 * scale + gap
    Runtime.drawOverlayKey('WD', nil, rowX, rowY, 46 * scale, 28 * scale, 'mouse', getGameTimer() < wheelDownUntil)
    rowX = rowX + 46 * scale + gap
    Runtime.drawOverlayKey('M5', 6, rowX, rowY, 42 * scale, 28 * scale, 'mouse')
end

function Runtime.pointInside(x, y, left, top, width, height)
    return x >= left and x <= left + width and y >= top and y <= top + height
end

function Runtime.updateOverlayDragging()
    local leftDown = isKeyDown(1)
    if not uiGet(windowOpen) then
        if overlayDragKind then
            saveSettings()
        end
        overlayDragKind = nil
        overlayWasLeftDown = leftDown
        return
    end

    local cursorX, cursorY = getCursorPos()
    if leftDown and not overlayWasLeftDown then
        for _, kind in ipairs({ 'mouse', 'keyboard' }) do
            if config.settings[kind .. '_overlay'] then
                local width, height = Runtime.overlayDimensions(kind)
                local x, y = config.settings[kind .. '_x'], config.settings[kind .. '_y']
                if Runtime.pointInside(cursorX, cursorY, x, y, width, height) then
                    overlayDragKind = kind
                    overlayDragOffsetX = cursorX - x
                    overlayDragOffsetY = cursorY - y
                    break
                end
            end
        end
    end

    if overlayDragKind and leftDown then
        local screenWidth, screenHeight = getScreenResolution()
        local width, height = Runtime.overlayDimensions(overlayDragKind)
        config.settings[overlayDragKind .. '_x'] = clamp(cursorX - overlayDragOffsetX, 0, math.max(0, screenWidth - width))
        config.settings[overlayDragKind .. '_y'] = clamp(cursorY - overlayDragOffsetY, 0, math.max(0, screenHeight - height))
    elseif overlayDragKind and not leftDown then
        overlayDragKind = nil
        saveSettings()
    end
    overlayWasLeftDown = leftDown
end

function Runtime.renderInputOverlays()
    Runtime.updateOverlayDragging()
    if config.settings.keyboard_overlay then
        Runtime.drawKeyboardRenderOverlay()
    end
    if config.settings.mouse_overlay then
        Runtime.drawMouseRenderOverlay()
    end
end

function Runtime.updateMouseWheelOverlay()
    if not config.settings.mouse_overlay then
        return
    end
    local menuActive = menuShouldRender()
    local delta = 0
    -- getMousewheelDelta may consume the native wheel event on older clients.
    -- While the menu is open, leave that event entirely to ImGui scrolling.
    if not menuActive then
        local rawOk, rawDelta = pcall(getMousewheelDelta)
        if rawOk and type(rawDelta) == 'number' then
            delta = rawDelta
        end
    end
    local imguiOk, imguiDelta = pcall(function()
        return tonumber(imgui.GetIO().MouseWheel) or 0
    end)
    if imguiOk and math.abs(imguiDelta) > math.abs(delta) then
        delta = imguiDelta
    end
    if not menuActive then
        if vkeys.VK_WHEELUP and wasKeyPressed(vkeys.VK_WHEELUP) then
            delta = math.max(delta, 1)
        elseif vkeys.VK_WHEELDOWN and wasKeyPressed(vkeys.VK_WHEELDOWN) then
            delta = math.min(delta, -1)
        end
    end
    if delta == 0 then
        return
    end
    local activeUntil = getGameTimer() + 140
    if delta > 0 then
        wheelUpUntil = activeUntil
    else
        wheelDownUntil = activeUntil
    end
end

function Runtime.processKeyCapture()
    if not captureField or getGameTimer() < captureReadyAt then
        return
    end
    if wasKeyPressed(vkeys.VK_ESCAPE) then
        captureField = nil
        return
    end
    if wasKeyPressed(vkeys.VK_BACK) or wasKeyPressed(vkeys.VK_DELETE) then
        config.settings[captureField] = 0
        captureField = nil
        saveSettings()
        return
    end
    for key = 1, 255 do
        if key ~= vkeys.VK_ESCAPE and key ~= vkeys.VK_BACK and key ~= vkeys.VK_DELETE and wasKeyPressed(key) then
            config.settings[captureField] = key
            ghChat(tr('bind_saved') .. ': ' .. keyName(key))
            captureField = nil
            saveSettings()
            return
        end
    end
end

function Runtime.gameInputAvailable()
    return not sampIsChatInputActive() and not sampIsDialogActive()
end

function Runtime.imguiTextInputActive()
    local checked, active = pcall(function()
        return imgui.GetIO().WantTextInput == true
    end)
    return checked and active
end

function Runtime.pressedConfiguredKey(key)
    return key and key > 0 and wasKeyPressed(key)
end

function Runtime.processServerBinds()
    if config.settings.profile == 1 then
        if Runtime.pressedConfiguredKey(config.settings.bzone_cancel_key) then
            sampSendChat('/omg')
            return true
        elseif Runtime.pressedConfiguredKey(config.settings.bzone_cocaine_key) then
            sampSendChat('/usedrugs cocaine')
            return true
        elseif Runtime.pressedConfiguredKey(config.settings.bzone_meth_key) then
            sampSendChat('/usedrugs meth')
            return true
        end
    else
        if Runtime.pressedConfiguredKey(config.settings.bugged_cancel_key) then
            sampSendChat('/stopanim')
            return true
        elseif Runtime.pressedConfiguredKey(config.settings.bugged_drugs_key) then
            sampSendChat('/usedrugs')
            return true
        end
    end
    return false
end

function Runtime.processWeaponSwitch()
    if not config.settings.weapon_switch or isCharInAnyCar(PLAYER_PED) then
        return false
    end
    for slot = 1, 5 do
        local key = config.settings['weapon_key_' .. slot]
        if wasKeyPressed(key) then
            local weaponId = config.settings['weapon_slot_' .. slot]
            if weaponId > 0 and hasCharGotWeapon(PLAYER_PED, weaponId) then
                setCurrentCharWeapon(PLAYER_PED, weaponId)
            elseif weaponId > 0 then
                ghChat(tr('no_weapon'))
            end
            return true
        end
    end
    return false
end

function Runtime.updateSensitivity()
    if not config.settings.sensitivity_fix or not sensitivityMemoryValid then
        if sensitivityApplied then
            restoreSensitivity()
        end
        return
    end
    local weaponId = getCurrentCharWeapon(PLAYER_PED)
    local weapon = sensitivityWeaponById[weaponId]
    local value = weapon and tonumber(config.settings['sens_' .. weaponId]) or nil
    local hasCustomValue = value and baseSensitivityX
        and math.abs(value - baseSensitivityX) > 0.0000005
    local isAiming = isKeyDown(2)
        and not uiGet(windowOpen)
        and not sampIsChatInputActive()
        and not sampIsDialogActive()
    if not weapon or not hasCustomValue or not isAiming then
        if sensitivityApplied then
            restoreSensitivity()
        end
        return
    end
    memory.setfloat(SENSITIVITY_X, value, true)
    memory.setfloat(SENSITIVITY_Y, value, true)
    sensitivityApplied = true
end

function Runtime.captureFpsMemory()
    if Runtime.fpsMemoryCaptured then
        return true
    end
    local versionOk, originalVersion = pcall(isGameVersionOriginal)
    if not versionOk or not originalVersion then
        return false
    end
    for _, address in ipairs({ Runtime.fpsLimiterFlag }) do
        local readOk, value = pcall(memory.getuint8, address, true)
        if readOk and tonumber(value) then
            Runtime.fpsOriginalMemory[address] = tonumber(value)
        end
    end
    Runtime.fpsMemoryCaptured = Runtime.fpsOriginalMemory[Runtime.fpsLimiterFlag] ~= nil
    return Runtime.fpsMemoryCaptured
end

function Runtime.setFpsMemoryByte(address, value)
    if Runtime.fpsOriginalMemory[address] == nil then
        return
    end
    pcall(memory.setuint8, address, value, true)
end

function Runtime.highResolutionNow()
    if not fpsKernel or not fpsClockFrequency then
        return nil
    end
    local counter = ffi.new('long long[1]')
    if fpsKernel.QueryPerformanceCounter(counter) == 0 then
        return nil
    end
    return tonumber(counter[0]) / fpsClockFrequency
end

function Runtime.writeNativeBytes(address, bytes)
    if not fpsKernel or not address or type(bytes) ~= 'string' or #bytes == 0 then
        return false
    end
    local oldProtect = ffi.new('unsigned long[1]')
    local pointer = ffi.cast('void*', address)
    if fpsKernel.VirtualProtect(pointer, #bytes, 0x40, oldProtect) == 0 then
        return false
    end
    ffi.copy(pointer, bytes, #bytes)
    local ignoredProtect = ffi.new('unsigned long[1]')
    fpsKernel.VirtualProtect(pointer, #bytes, oldProtect[0], ignoredProtect)
    local process = processClockKernel and processClockKernel.GetCurrentProcess()
        or fpsKernel.GetCurrentProcess()
    fpsKernel.FlushInstructionCache(process, pointer, #bytes)
    return true
end

function Runtime.patchNativeBytes(address, replacement)
    local original = ffi.string(ffi.cast('const char*', address), #replacement)
    if original == replacement then
        return nil
    end
    if not Runtime.writeNativeBytes(address, replacement) then
        return nil
    end
    return { address = address, original = original }
end

function Runtime.sampModuleImage()
    if not fpsKernel or not fpsPsapi then
        return nil
    end
    local module = fpsKernel.GetModuleHandleA('samp.dll')
    if module == nil or module == ffi.NULL then
        return nil
    end
    local info = ffi.new('GH_MODULEINFO[1]')
    local process = processClockKernel and processClockKernel.GetCurrentProcess()
        or fpsKernel.GetCurrentProcess()
    if fpsPsapi.GetModuleInformation(process, module, info, ffi.sizeof(info[0])) == 0 then
        return nil
    end
    local base = tonumber(ffi.cast('unsigned long', info[0].lpBaseOfDll))
    local size = tonumber(info[0].SizeOfImage)
    if not base or not size or size < 0x10000 or size > 0x1000000 then
        return nil
    end
    return base, ffi.string(ffi.cast('const char*', info[0].lpBaseOfDll), size)
end

function Runtime.findSampLimiterCaller(image)
    local prefix = string.char(0x89, 0x65, 0xE8, 0x8B, 0x0D)
    local suffix = string.char(0x85, 0xC9, 0x74, 0x05, 0xE8)
    local searchFrom = 1
    while true do
        local position = image:find(prefix, searchFrom, true)
        if not position then
            return nil
        end
        if image:sub(position + 9, position + 13) == suffix then
            return position
        end
        searchFrom = position + 1
    end
end

function Runtime.applySampFpsPatches()
    if Runtime.sampFpsPatched then
        return true
    end
    if Runtime.sampFpsPatchAttempted then
        return false
    end
    Runtime.sampFpsPatchAttempted = true
    local base, image = Runtime.sampModuleImage()
    if not base or not image then
        Runtime.sampFpsPatchStatus = 'module-unavailable'
        return false
    end

    local patches = {}
    local callerPosition = Runtime.findSampLimiterCaller(image)
    if callerPosition then
        local patch = Runtime.patchNativeBytes(base + callerPosition - 1 + 3,
            string.rep(string.char(0x90), 15))
        if patch then
            patches[#patches + 1] = patch
        end
    end

    local hardSleepPattern = string.char(0xBA, 0x80, 0x1A, 0x56, 0x00, 0xFF, 0xE2)
    local hardSleepPosition = image:find(hardSleepPattern, 1, true)
    if hardSleepPosition and hardSleepPosition > 7 then
        local patch = Runtime.patchNativeBytes(base + hardSleepPosition - 1 - 7, string.char(0x00))
        if patch then
            patches[#patches + 1] = patch
        end
    end

    Runtime.sampFpsPatches = patches
    Runtime.sampFpsPatched = #patches > 0
    Runtime.sampFpsPatchStatus = #patches >= 2 and 'full'
        or (#patches == 1 and 'partial' or 'unsupported')
    return Runtime.sampFpsPatched
end

function Runtime.restoreSampFpsPatches()
    for index = #Runtime.sampFpsPatches, 1, -1 do
        local patch = Runtime.sampFpsPatches[index]
        Runtime.writeNativeBytes(patch.address, patch.original)
    end
    Runtime.sampFpsPatches = {}
    Runtime.sampFpsPatched = false
    Runtime.sampFpsPatchAttempted = false
    Runtime.sampFpsPatchStatus = 'idle'
end

function Runtime.setOptionalWorldFeature(name, value)
    local callback = rawget(_G, name)
    if type(callback) == 'function' then
        pcall(callback, value)
    end
end

function Runtime.applySampFpsBoost(enabled)
    local density = enabled and 0.0 or 1.0
    pcall(function() setCarDensityMultiplier(density) end)
    pcall(function() setPedDensityMultiplier(density) end)
    pcall(function() setGenerateCarsAroundCamera(not enabled) end)
    pcall(function() switchRubbish(not enabled) end)
    Runtime.setOptionalWorldFeature('switchAmbientPlanes', not enabled)
    Runtime.setOptionalWorldFeature('switchRandomTrains', not enabled)
    Runtime.setOptionalWorldFeature('setCloudsEnabled', not enabled)
    Runtime.setOptionalWorldFeature('setBirdsEnabled', not enabled)
end

Runtime.restoreFpsFeatures = function()
    if Runtime.fpsMemoryCaptured then
        for address, value in pairs(Runtime.fpsOriginalMemory) do
            pcall(memory.setuint8, address, value, true)
        end
    end
    Runtime.restoreSampFpsPatches()
    Runtime.applySampFpsBoost(false)
    Runtime.fpsFeaturesApplied = false
    Runtime.fpsLastCounter = nil
    Runtime.lastAppliedFpsLimit = nil
end

Runtime.applyFpsFeatures = function()
    Runtime.captureFpsMemory()
    Runtime.applySampFpsBoost(config.settings.fps_boost)
    local removeCap = config.settings.fps_unlocker or config.settings.fps_lock
    if removeCap then
        Runtime.setFpsMemoryByte(Runtime.fpsLimiterFlag, 0)
        Runtime.applySampFpsPatches()
    elseif Runtime.fpsOriginalMemory[Runtime.fpsLimiterFlag] ~= nil then
        Runtime.setFpsMemoryByte(Runtime.fpsLimiterFlag, Runtime.fpsOriginalMemory[Runtime.fpsLimiterFlag])
        Runtime.restoreSampFpsPatches()
    end
    Runtime.fpsFeaturesApplied = config.settings.fps_boost or removeCap
end

Runtime.applyFpsLock = function(force)
    if config.settings.fps_lock then
        local limit = math.floor(clamp(config.settings.fps_limit, 20, 100) + 0.5)
        if force or Runtime.lastAppliedFpsLimit ~= limit then
            Runtime.lastAppliedFpsLimit = limit
            Runtime.fpsLastCounter = nil
            Runtime.applyFpsFeatures()
        end
    elseif Runtime.lastAppliedFpsLimit ~= nil then
        Runtime.lastAppliedFpsLimit = nil
        Runtime.fpsLastCounter = nil
        Runtime.applyFpsFeatures()
    end
end

function Runtime.limitFrameRate()
    if not config.settings.fps_lock then
        Runtime.fpsLastCounter = nil
        return
    end
    local now = Runtime.highResolutionNow()
    if not now then
        return
    end
    local limit = math.floor(clamp(config.settings.fps_limit, 20, 100) + 0.5)
    local frameSeconds = 1.0 / limit
    local previous = Runtime.fpsLastCounter
    if previous and now >= previous and now - previous < 0.25 then
        local remaining = frameSeconds - (now - previous)
        if remaining > 0 then
            local sleepMilliseconds = math.floor(math.max(0, remaining * 1000 - 0.8))
            if sleepMilliseconds > 0 then
                fpsKernel.Sleep(sleepMilliseconds)
            end
            repeat
                now = Runtime.highResolutionNow() or now
            until now - previous >= frameSeconds
        end
    end
    Runtime.fpsLastCounter = now
end

Runtime.setInfiniteRunEnabled = function(enabled)
    config.settings.infinite_run = enabled == true
    pcall(setPlayerNeverGetsTired, PLAYER_HANDLE, config.settings.infinite_run)
    saveSettings()
end

Runtime.setTimeOverrideEnabled = function(enabled)
    config.settings.time_override = enabled == true
    if config.settings.time_override then
        Runtime.timeOverrideStored = pcall(storeClock)
        pcall(setTimeOfDay, math.floor(config.settings.time_hour), 0)
    else
        if Runtime.lastServerHour ~= nil then
            pcall(setTimeOfDay, Runtime.lastServerHour, Runtime.lastServerMinute or 0)
        elseif Runtime.timeOverrideStored then
            pcall(restoreClock)
        end
        Runtime.timeOverrideStored = false
    end
    saveSettings()
end

Runtime.setWeatherOverrideEnabled = function(enabled)
    config.settings.weather_override = enabled == true
    if config.settings.weather_override then
        pcall(forceWeatherNow, math.floor(config.settings.weather_id))
    else
        pcall(releaseWeather)
        if Runtime.lastServerWeather ~= nil then
            pcall(forceWeatherNow, Runtime.lastServerWeather)
        end
    end
    saveSettings()
end

function Runtime.updateWorldOverrides()
    local now = getGameTimer()
    if now < Runtime.nextWorldOverrideUpdate then
        return
    end
    Runtime.nextWorldOverrideUpdate = now + 500
    if config.settings.time_override then
        pcall(setTimeOfDay, math.floor(config.settings.time_hour), 0)
    end
    if config.settings.weather_override then
        pcall(forceWeatherNow, math.floor(config.settings.weather_id))
    end
end

function Runtime.validSkinId(model)
    model = math.floor(tonumber(model) or -1)
    return model >= 0 and model <= 311 and model ~= 74
end

Runtime.setChangeSkinEnabled = function(enabled)
    if enabled and not Runtime.validSkinId(config.settings.change_skin_id) then
        config.settings.change_skin = false
        ghChat(tr('change_skin_invalid'))
        saveSettings()
        return false
    end
    if enabled then
        local modelOk, currentModel = pcall(getCharModel, PLAYER_PED)
        if modelOk and Runtime.validSkinId(currentModel) then
            Runtime.lastServerSkin = currentModel
        end
        Runtime.changeSkinRestoreModel = nil
        config.settings.change_skin = true
        Runtime.changeSkinApplyPending = true
        Runtime.changeSkinDeathGraceUntil = getGameTimer() + 8000
    else
        config.settings.change_skin = false
        Runtime.changeSkinApplyPending = false
        if Runtime.validSkinId(Runtime.lastServerSkin) then
            Runtime.changeSkinRestoreModel = Runtime.lastServerSkin
        end
    end
    saveSettings()
    return true
end

function Runtime.updateChangeSkin()
    local now = getGameTimer()
    if now < Runtime.nextSkinUpdate then
        return
    end
    local model = Runtime.changeSkinRestoreModel
    if not model and config.settings.change_skin and Runtime.changeSkinApplyPending then
        model = config.settings.change_skin_id
    end
    if not Runtime.validSkinId(model) then
        return
    end
    if not doesCharExist(PLAYER_PED) or isCharDead(PLAYER_PED) then
        Runtime.nextSkinUpdate = now + 250
        return
    end
    if not hasModelLoaded(model) then
        requestModel(model)
        Runtime.nextSkinUpdate = now + 100
        return
    end
    local applied = pcall(setPlayerModel, PLAYER_HANDLE, model)
    pcall(markModelAsNoLongerNeeded, model)
    Runtime.nextSkinUpdate = now + 500
    if applied then
        Runtime.changeSkinIgnoreServerUntil = now + 900
        if Runtime.changeSkinRestoreModel then
            Runtime.changeSkinRestoreModel = nil
        else
            Runtime.changeSkinApplyPending = false
        end
    end
end

function Runtime.bulletVector(data, field)
    local ok, x, y, z = pcall(function()
        local value = data[field]
        return tonumber(value.x), tonumber(value.y), tonumber(value.z)
    end)
    if not ok or not x or not y or not z then
        return nil
    end
    return { x = x, y = y, z = z }
end

function Runtime.playerTabColor(playerId)
    local ok, playerColor = pcall(sampGetPlayerColor, playerId)
    playerColor = ok and tonumber(playerColor) or nil
    if not playerColor then
        return 255, 255, 255
    end
    local byteA = bit.band(bit.rshift(playerColor, 24), 0xff)
    local byteB = bit.band(bit.rshift(playerColor, 16), 0xff)
    local byteC = bit.band(bit.rshift(playerColor, 8), 0xff)
    local byteD = bit.band(playerColor, 0xff)
    local red, green, blue
    if byteD == 0xff or byteA ~= 0xff then
        -- SA-MP exposes player colors as RGBA on supported clients.
        red, green, blue = byteA, byteB, byteC
    else
        -- Compatibility fallback for wrappers returning ARGB.
        red, green, blue = byteB, byteC, byteD
    end
    local brightest = math.max(red, green, blue)
    if brightest > 0 and brightest < 72 then
        local scale = 72 / brightest
        red = math.min(255, math.floor(red * scale + 0.5))
        green = math.min(255, math.floor(green * scale + 0.5))
        blue = math.min(255, math.floor(blue * scale + 0.5))
    end
    return red, green, blue
end

function Runtime.playerWeaponId(playerId)
    if playerId == getLocalPlayerId() then
        local ok, weaponId = pcall(getCurrentCharWeapon, PLAYER_PED)
        return ok and tonumber(weaponId) or 0
    end
    local getNetworkWeapon = rawget(_G, 'sampGetPlayerWeapon')
    if type(getNetworkWeapon) == 'function' then
        local ok, weaponId = pcall(getNetworkWeapon, playerId)
        if ok and tonumber(weaponId) and tonumber(weaponId) > 0 then
            return tonumber(weaponId)
        end
    end
    local ok, streamed, ped = pcall(sampGetCharHandleBySampPlayerId, playerId)
    if ok and streamed and ped and doesCharExist(ped) then
        local weaponOk, weaponId = pcall(getCurrentCharWeapon, ped)
        if weaponOk and tonumber(weaponId) then
            return tonumber(weaponId)
        end
    end
    return 0
end

function Runtime.addBulletTrace(playerId, data)
    if not config.settings.bullet_track or type(data) ~= 'table' and type(data) ~= 'cdata' then
        return
    end
    local origin, target = Runtime.bulletVector(data, 'origin'), Runtime.bulletVector(data, 'target')
    if not origin or not target then
        return
    end
    local targetType, targetId, packetWeaponId = 0, -1, 0
    pcall(function()
        targetType = tonumber(data.targetType) or 0
        targetId = tonumber(data.targetId) or -1
        packetWeaponId = tonumber(data.weaponId) or 0
    end)
    local localId = getLocalPlayerId()
    local targetsLocalPlayer = targetType == 1 and targetId == localId
    local coordinatesOk, localX, localY, localZ = pcall(getCharCoordinates, PLAYER_PED)
    if not coordinatesOk then
        return
    end
    local dx, dy, dz = origin.x - localX, origin.y - localY, origin.z - localZ
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if distance > config.settings.bullet_track_distance and not targetsLocalPlayer then
        return
    end
    local vectorX = target.x - origin.x
    local vectorY = target.y - origin.y
    local vectorZ = target.z - origin.z
    local rawLength = math.sqrt(vectorX * vectorX + vectorY * vectorY + vectorZ * vectorZ)
    if rawLength < 0.05 then
        return
    end
    -- BulletSyncData carries the weapon used for this exact shot. Prefer it
    -- over the ped's current weapon, which can already have changed by the
    -- time this frame is rendered.
    local weaponId = packetWeaponId > 0 and packetWeaponId
        or Runtime.playerWeaponId(playerId)
    local weaponRange = bulletWeaponRanges[weaponId] or 100.0
    local traceLength = math.min(rawLength, weaponRange)
    local unitX, unitY, unitZ = vectorX / rawLength, vectorY / rawLength, vectorZ / rawLength
    target = {
        x = origin.x + unitX * traceLength,
        y = origin.y + unitY * traceLength,
        z = origin.z + unitZ * traceLength
    }
    local red, green, blue = Runtime.playerTabColor(playerId)
    Runtime.bulletTraces[#Runtime.bulletTraces + 1] = {
        origin = origin,
        target = target,
        created = getGameTimer(),
        red = red,
        green = green,
        blue = blue,
        weaponId = weaponId,
        weaponRange = weaponRange,
        length = traceLength,
        targetsLocalPlayer = targetsLocalPlayer
    }
    while #Runtime.bulletTraces > Runtime.maxBulletTraces do
        table.remove(Runtime.bulletTraces, 1)
    end
end

if sampEventsAvailable and type(sampev) == 'table' then
    function sampev.onSendBulletSync(data)
        Runtime.addBulletTrace(getLocalPlayerId(), data)
    end

    function sampev.onBulletSync(playerId, data)
        Runtime.addBulletTrace(playerId, data)
    end

    function sampev.onSetPlayerTime(hour, minute)
        Runtime.lastServerHour = clamp(tonumber(hour) or 0, 0, 23)
        Runtime.lastServerMinute = clamp(tonumber(minute) or 0, 0, 59)
    end

    function sampev.onSetWeather(weatherId)
        Runtime.lastServerWeather = clamp(tonumber(weatherId) or 0, 0, 255)
    end

    function sampev.onSendDeathNotification()
        if config.settings.change_skin then
            Runtime.changeSkinDeathGraceUntil = getGameTimer() + 12000
            Runtime.changeSkinApplyPending = true
        end
    end

    function sampev.onSendSpawn()
        if config.settings.change_skin then
            Runtime.changeSkinDeathGraceUntil = getGameTimer() + 5000
            Runtime.changeSkinApplyPending = true
        end
    end

    function sampev.onSetPlayerSkin(playerId, skinId)
        if tonumber(playerId) ~= getLocalPlayerId() or not Runtime.validSkinId(skinId) then
            return
        end
        Runtime.lastServerSkin = math.floor(tonumber(skinId))
        local now = getGameTimer()
        if config.settings.change_skin then
            if now <= Runtime.changeSkinDeathGraceUntil or now <= Runtime.changeSkinIgnoreServerUntil then
                Runtime.changeSkinApplyPending = true
            else
                config.settings.change_skin = false
                Runtime.changeSkinApplyPending = false
                Runtime.changeSkinRestoreModel = nil
                saveSettings()
                ghChat(tr('change_skin_server'))
            end
        end
    end
end

function Runtime.projectWorldPoint(point)
    if type(convert3DCoordsToScreenEx) == 'function' then
        local ok, first, second, third = pcall(convert3DCoordsToScreenEx,
            point.x, point.y, point.z, true, true)
        if ok and type(first) == 'boolean' then
            return first and tonumber(second) and tonumber(third) and second or nil,
                first and tonumber(second) and tonumber(third) and third or nil
        elseif ok and tonumber(first) and tonumber(second) then
            return first, second
        end
    end
    local ok, first, second, third = pcall(convert3DCoordsToScreen, point.x, point.y, point.z)
    if ok and type(first) == 'boolean' then
        return first and second or nil, first and third or nil
    elseif ok and tonumber(first) and tonumber(second) then
        return first, second
    end
    return nil, nil
end

function Runtime.tracePoint(trace, progress)
    return {
        x = trace.origin.x + (trace.target.x - trace.origin.x) * progress,
        y = trace.origin.y + (trace.target.y - trace.origin.y) * progress,
        z = trace.origin.z + (trace.target.z - trace.origin.z) * progress
    }
end

function Runtime.renderBulletTracks()
    if not config.settings.bullet_track then
        Runtime.bulletTraces = {}
        return
    end
    local now = getGameTimer()
    local durationMs = math.max(250, config.settings.bullet_track_duration * 1000)
    for index = #Runtime.bulletTraces, 1, -1 do
        local trace = Runtime.bulletTraces[index]
        local age = now - trace.created
        if age < 0 or age > durationMs then
            table.remove(Runtime.bulletTraces, index)
        else
            local normalizedAge = clamp(age / durationMs, 0.0, 1.0)
            local fadeStart = 0.48
            local fade = normalizedAge <= fadeStart and 1.0
                or math.pow(clamp((1.0 - normalizedAge) / (1.0 - fadeStart), 0.0, 1.0), 1.2)
            local revealLinear = clamp(age / 70.0, 0.0, 1.0)
            local reveal = 1.0 - math.pow(1.0 - revealLinear, 3.0)
            local visibleStartT = trace.targetsLocalPlayer
                and math.max(0.0, 1.0 - math.min(30.0, trace.length) / trace.length)
                or 0.0
            local visibleEndT = visibleStartT + (1.0 - visibleStartT) * reveal
            if visibleEndT > visibleStartT + 0.0001 then
                local startX, startY = Runtime.projectWorldPoint(
                    Runtime.tracePoint(trace, visibleStartT))
                local endX, endY = Runtime.projectWorldPoint(
                    Runtime.tracePoint(trace, visibleEndT))
                if startX and startY and endX and endY then
                    local screenDx, screenDy = endX - startX, endY - startY
                    local screenLength = math.sqrt(screenDx * screenDx + screenDy * screenDy)
                    if screenLength > 1.0 then
                        local coreRed = math.min(255, math.floor(trace.red * 0.55 + 115))
                        local coreGreen = math.min(255, math.floor(trace.green * 0.55 + 115))
                        local coreBlue = math.min(255, math.floor(trace.blue * 0.55 + 115))
                        local emphasis = trace.targetsLocalPlayer and 1.18 or 1.0

                        -- Continuous trajectory, matching the reference style,
                        -- with a restrained shadow, colored glow and crisp core.
                        renderDrawLine(startX, startY, endX, endY, 6.2 * emphasis,
                            Runtime.argb(math.floor(52 * fade), 0, 0, 0))
                        renderDrawLine(startX, startY, endX, endY, 4.1 * emphasis,
                            Runtime.argb(math.floor(88 * fade),
                                trace.red, trace.green, trace.blue))
                        renderDrawLine(startX, startY, endX, endY, 1.35 * emphasis,
                            Runtime.argb(math.floor(235 * fade),
                                coreRed, coreGreen, coreBlue))

                        local travelLinear = clamp(age / (trace.targetsLocalPlayer and 115.0 or 150.0),
                            0.0, 1.0)
                        local travel = 1.0 - math.pow(1.0 - travelLinear, 3.0)
                        local bulletT = visibleStartT + (1.0 - visibleStartT) * travel
                        local bulletTail = math.min(0.10,
                            math.max(0.015, 1.6 / math.max(trace.length, 0.05)))
                        local bulletBackT = math.max(visibleStartT, bulletT - bulletTail)
                        local bulletX, bulletY = Runtime.projectWorldPoint(
                            Runtime.tracePoint(trace, bulletT))
                        local bulletBackX, bulletBackY = Runtime.projectWorldPoint(
                            Runtime.tracePoint(trace, bulletBackT))
                        if bulletX and bulletY and bulletBackX and bulletBackY then
                            local bulletDx, bulletDy = bulletX - bulletBackX, bulletY - bulletBackY
                            local bulletLength = math.sqrt(bulletDx * bulletDx + bulletDy * bulletDy)
                            if bulletLength > 0.6 then
                                local ux, uy = bulletDx / bulletLength, bulletDy / bulletLength
                                local sideX, sideY = -uy, ux
                                local tipX, tipY = bulletX + ux * 2.2, bulletY + uy * 2.2
                                local baseX, baseY = bulletX - ux * 6.5, bulletY - uy * 6.5
                                local bulletGlow = Runtime.argb(math.floor(125 * fade),
                                    trace.red, trace.green, trace.blue)
                                local bulletCore = Runtime.argb(math.floor(250 * fade),
                                    coreRed, coreGreen, coreBlue)
                                renderDrawLine(bulletBackX, bulletBackY, bulletX, bulletY,
                                    7.0 * emphasis, bulletGlow)
                                renderDrawLine(bulletBackX, bulletBackY, bulletX, bulletY,
                                    2.7 * emphasis, bulletCore)
                                renderDrawLine(tipX, tipY,
                                    baseX + sideX * 3.0, baseY + sideY * 3.0,
                                    1.25 * emphasis, bulletCore)
                                renderDrawLine(tipX, tipY,
                                    baseX - sideX * 3.0, baseY - sideY * 3.0,
                                    1.25 * emphasis, bulletCore)
                                pcall(renderDrawPolygon, bulletX, bulletY,
                                    3.2 * emphasis, 3.2 * emphasis, 8, 0, bulletCore)
                            end
                        end

                        if reveal > 0.98 then
                            local impactX, impactY = Runtime.projectWorldPoint(trace.target)
                            if impactX and impactY then
                                local impactSize = trace.targetsLocalPlayer and 6.5 or 4.8
                                pcall(renderDrawPolygon, impactX, impactY,
                                    impactSize, impactSize, 4, 45,
                                    Runtime.argb(math.floor(68 * fade),
                                        trace.red, trace.green, trace.blue))
                                pcall(renderDrawPolygon, impactX, impactY,
                                    2.2, 2.2, 4, 45,
                                    Runtime.argb(math.floor(210 * fade),
                                        coreRed, coreGreen, coreBlue))
                            end
                        end
                    end
                end
            end
        end
    end
end

addEventHandler('onScriptTerminate', function(scr)
    if scr == thisScript() then
        restoreSensitivity()
        Runtime.restoreFpsFeatures()
        pcall(setPlayerNeverGetsTired, PLAYER_HANDLE, false)
        pcall(releaseWeather)
        if Runtime.timeOverrideStored then
            pcall(restoreClock)
        elseif Runtime.lastServerHour ~= nil then
            pcall(setTimeOfDay, Runtime.lastServerHour, Runtime.lastServerMinute or 0)
        end
        if config.settings.change_skin and Runtime.validSkinId(Runtime.lastServerSkin) then
            pcall(function()
                if hasModelLoaded(Runtime.lastServerSkin) then
                    setPlayerModel(PLAYER_HANDLE, Runtime.lastServerSkin)
                end
            end)
        end
        for name, font in pairs(overlayFonts) do
            if font then
                renderReleaseFont(font)
                overlayFonts[name] = nil
            end
        end
    end
end)

function main()
    while not isSampAvailable() do
        wait(0)
    end

    sampRegisterChatCommand('gh', function()
        toggleMenu()
    end)
    -- SA:MP is available at this point. Publish on the very next frame, with no
    -- login/spawn timer and no artificial delay.
    lua_thread.create(function()
        wait(0)
        showInjectionMessage()
    end)

    if config.settings.update_auto_check and Updater.updaterConfigured() then
        lua_thread.create(function()
            wait(Updater.checkDelay)
            Updater.checkForUpdates()
        end)
    end

    if legacyImgui then
        local themeInitialized, themeError = pcall(initializeImguiTheme)
        if not themeInitialized then
            ghChat(tr('font_error') .. ' ' .. tostring(themeError))
        end
    end

    local overlayFontSizes = { tiny = 5, small = 7, normal = 10, large = 12 }
    for name, size in pairs(overlayFontSizes) do
        local created, font = pcall(renderCreateFont, 'Segoe UI', size, 5)
        if created and font then
            overlayFonts[name] = font
        else
            overlayRendererFailed = true
            break
        end
    end

    local sensitivityInitialized = pcall(captureBaseSensitivity)
    if not sensitivityInitialized then
        sensitivityMemoryValid = false
    end
    if config.settings.sensitivity_fix and not sensitivityMemoryValid then
        config.settings.sensitivity_fix = false
        saveSettings()
    end

    pcall(setPlayerNeverGetsTired, PLAYER_HANDLE, config.settings.infinite_run)
    Runtime.applyFpsFeatures()
    Runtime.applyFpsLock(true)
    if config.settings.time_override then
        Runtime.setTimeOverrideEnabled(true)
    end
    if config.settings.weather_override then
        Runtime.setWeatherOverrideEnabled(true)
    end
    if config.settings.change_skin then
        Runtime.setChangeSkinEnabled(true)
    end

    while true do
        wait(0)
        Runtime.limitFrameRate()
        updateInterfaceAnimations()
        if legacyImgui then
            imgui.Process = menuShouldRender()
            imgui.ShowCursor = menuShouldRender()
        end
        Runtime.updateMouseWheelOverlay()
        Runtime.updateWorldOverrides()
        Runtime.updateChangeSkin()
        Runtime.applyFpsLock(false)
        local now = getGameTimer()
        if now >= Runtime.nextUtilityRefresh then
            Runtime.nextUtilityRefresh = now + 1000
            if config.settings.infinite_run then
                pcall(setPlayerNeverGetsTired, PLAYER_HANDLE, true)
            end
        end
        if not Runtime.bulletRendererFailed then
            local bulletsRendered = pcall(Runtime.renderBulletTracks)
            if not bulletsRendered then
                Runtime.bulletRendererFailed = true
                Runtime.bulletTraces = {}
            end
        end
        if not overlayRendererFailed then
            local rendered, renderError = pcall(Runtime.renderInputOverlays)
            if not rendered then
                overlayRendererFailed = true
                ghChat(tr('overlay_error') .. ' ' .. tostring(renderError))
            end
        end

        if captureField then
            Runtime.processKeyCapture()
        elseif Runtime.gameInputAvailable() then
            if config.settings.open_on_delete and not Runtime.imguiTextInputActive() and wasKeyPressed(vkeys.VK_DELETE) then
                toggleMenu()
            elseif not uiGet(windowOpen) then
                local handled = Runtime.processServerBinds()
                if not handled then
                    Runtime.processWeaponSwitch()
                end
            end
        end

        if getGameTimer() >= nextSensitivityUpdate then
            nextSensitivityUpdate = getGameTimer() + 16
            Runtime.updateSensitivity()
        end
    end
end
