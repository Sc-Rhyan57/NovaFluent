package states.multiplayerState;

import flixel.FlxBasic;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.ui.FlxInputText;
import flixel.math.FlxRect;
import flixel.util.FlxSave;
import flixel.text.FlxText;
import games.PlayState;
import games.backend.Highscore;
import games.backend.Song;
import games.backend.StageData;
import games.backend.WeekData;
import general.backend.MpApi;
import general.backend.MpButton;
import general.backend.MpMatch;
import general.backend.MpMatch.PendingSong;
import general.backend.MpModTransfer;
import general.backend.MpModTransfer.ModPlan;
import general.backend.MpScripts;
import general.backend.MpSocket;
import general.backend.MusicBeatState;
import general.backend.Mods;
import general.backend.Paths;
import states.freeplayState.FreeplayState;
import states.loadingState.LoadingState;
import sys.FileSystem;
import sys.io.File;
import sys.thread.Deque;
import sys.thread.Thread;

typedef RoomSlot =
{
        var bg:FlxSprite;
        var name:FlxText;
        var info:FlxText;
        var join:MpButton;
};

typedef ButtonEntry =
{
        var group:String;
        var btn:MpButton;
};

class MultiplayerState extends MusicBeatState
{
        static inline final PX:Int = 40;
        static inline final SLOTS:Int = 6;
        static inline final BASE_FOLDER:String = '_base';
        static inline final CONTENT_W:Int = 1200;
        static inline final C_BG:Int = 0xFF0B0F14;
        static inline final C_PANEL:Int = 0xFF141B23;
        static inline final C_ROW:Int = 0xFF1C2631;
        static inline final C_TRACK:Int = 0xFF1A222C;
        static inline final C_TEXT:Int = 0xFFEAF2FF;
        static inline final C_MUTED:Int = 0xFF8A97A8;
        static inline final C_ACCENT:Int = 0xFF52FCC0;
        static inline final B_PRIMARY:Int = 0xFF178A69;
        static inline final B_SECOND:Int = 0xFF5B3FA8;
        static inline final B_NEUTRAL:Int = 0xFF2A3644;
        static inline final B_DANGER:Int = 0xFF8E2A44;
        static final NOTE_SPEEDS:Array<Float> = [0.5, 1, 1.5, 2, 2.5, 3, 4, 5];
        static final USER_RE = ~/^[A-Za-z0-9]{3,20}$/;
        static final PASS_RE = ~/^\d{6}$/;

        static var menuMusicOn:Bool = false;

        var loginSave:FlxSave;
        var events:Deque<Dynamic> = new Deque();
        var mode:String = 'auth';
        var groups:Map<String, Array<FlxBasic>> = new Map();
        var buttons:Array<ButtonEntry> = [];
        var status:FlxText;

        var userInput:FlxInputText;
        var passInput:FlxInputText;

        var meText:FlxText;
        var slots:Array<RoomSlot> = [];
        var listRooms:Array<Dynamic> = [];
        var roomCount:Int = 0;
        var joinPassInput:FlxInputText;
        var refreshTimer:Float = 0;

        var nameInput:FlxInputText;
        var createPassInput:FlxInputText;
        var createSongText:FlxText;
        var dieButton:MpButton;
        var botButton:MpButton;
        var speedButton:MpButton;
        var modButton:MpButton;
        var songPickButton:MpButton;
        var createSongs:Array<String> = [];
        var createSongIdx:Int = 0;
        var requestButton:MpButton;
        var requested:Bool = false;
        var sentTo:Map<String, Int> = new Map();
        var sendTotalTo:Map<String, Int> = new Map();
        var availableMods:Array<String> = ['_base'];
        var modIndex:Int = 0;
        var dieOnMiss:Bool = true;
        var botplay:Bool = false;
        var speedIndex:Int = 1;
        var pendingPassword:String = '';

        var socket:MpSocket = null;
        var pendingJoin:Null<{roomId:String, password:String}> = null;
        var room:Dynamic = null;
        var isHost:Bool = false;
        var myReady:Bool = false;
        var modReady:Bool = false;
        var roomFolder:String = null;

        var roomTitle:FlxText;
        var roomInfo:FlxText;
        var membersText:FlxText;
        var songTitle:FlxText;
        var prevSongButton:MpButton;
        var nextSongButton:MpButton;
        var progressBg:FlxSprite;
        var progressFill:FlxSprite;
        var progressText:FlxText;
        var chatText:FlxText;
        var chatInput:FlxInputText;
        var chatLines:Array<String> = [];
        var readyButton:MpButton;
        var playButton:MpButton;
        var songsList:Array<String> = [];
        var songIdx:Int = 0;

        var hostPlan:ModPlan = null;
        var encoding:Bool = false;
        var pendingSend:Array<String> = [];
        var chunkQueue:Array<{to:String, index:Int, total:Int}> = [];
        // Pedaços enviados e ainda não confirmados (modAck), por destinatário.
        var inFlight:Map<String, Int> = new Map();
        static final CHUNK_WINDOW:Int = 4;
        var incomingQueue:Deque<Dynamic> = null;
        var incomingIndex:Int = 0;

        var pendingStart:Bool = false;
        var startAt:Float = 0;

        public static var storedEvents:Array<Dynamic> = [];

        override function create():Void
        {
                super.create();

                add(new FlxSprite().makeGraphic(FlxG.width, FlxG.height, C_BG));

                status = new FlxText(PX, FlxG.height - 40, FlxG.width - PX * 2, '', 18);
                status.color = C_ACCENT;
                add(status);

                buildAuth();
                buildLobby();
                buildCreate();
                buildRoom();

                loginSave = new FlxSave();
                loginSave.bind('novaflareMpLogin');
                if (loginSave.data.username != null)
                        userInput.text = Std.string(loginSave.data.username);
                if (loginSave.data.password != null)
                        passInput.text = Std.string(loginSave.data.password);
                playMenuMusic();

                if (MpMatch.pendingStatus != null)
                {
                        setStatus(MpMatch.pendingStatus);
                        MpMatch.pendingStatus = null;
                }
                if (MpMatch.socket != null && (MpMatch.active || MpMatch.returning))
                        resumeRoom();
                else if (MpApi.token != null)
                        showMode('lobby');
                else
                        showMode('auth');
        }

        function track<T:FlxBasic>(group:String, obj:T):T
        {
                if (!groups.exists(group))
                        groups.set(group, []);
                groups.get(group).push(obj);
                add(obj);
                return obj;
        }

        function label(group:String, x:Float, y:Float, w:Int, s:String, size:Int = 18):FlxText
        {
                var t:FlxText = new FlxText(x, y, w, s, size);
                t.color = C_TEXT;
                return track(group, t);
        }

        function muted(group:String, x:Float, y:Float, w:Int, s:String, size:Int = 15):FlxText
        {
                var t:FlxText = new FlxText(x, y, w, s, size);
                t.color = C_MUTED;
                return track(group, t);
        }

        function panel(group:String, x:Float, y:Float, w:Int, h:Int, color:Int = C_PANEL):FlxSprite
        {
                return track(group, new FlxSprite(x, y).makeGraphic(w, h, color));
        }

        function button(group:String, x:Float, y:Float, w:Int, h:Int, s:String, color:Int, cb:Void->Void):MpButton
        {
                var b:MpButton = new MpButton(x, y, w, h, s, color, cb);
                add(b.shadow);
                add(b.bg);
                add(b.label);
                buttons.push({group: group, btn: b});
                return b;
        }

        function input(group:String, x:Float, y:Float, w:Int, password:Bool):FlxInputText
        {
                var field:FlxInputText = track(group, new FlxInputText(x, y, w, '', 18));
                field.passwordMode = password;
                return field;
        }

        function showMode(m:String):Void
        {
                mode = m;
                for (k in groups.keys())
                {
                        var show:Bool = k == m;
                        for (o in groups.get(k))
                        {
                                o.visible = show;
                                o.active = show;
                        }
                }
                for (entry in buttons)
                        entry.btn.show(entry.group == m);

                if (m == 'lobby')
                {
                        meText.text = MpApi.username == null ? '' : 'Logado como ' + MpApi.username;
                        applySlots();
                }
                if (m == 'create')
                {
                        refreshCreateSongs();
                        refreshCreateLabels();
                }
                if (m == 'room')
                        refreshRoomUI();
        }

        function buildAuth():Void
        {
                panel('auth', PX, 60, 560, 420);
                label('auth', PX + 30, 84, 500, 'MULTIPLAYER', 34);
                muted('auth', PX + 30, 130, 500, 'Entre na sua conta ou crie uma nova.', 16);
                muted('auth', PX + 30, 172, 500, 'USUÁRIO (3 a 20 letras e números)', 14);
                userInput = input('auth', PX + 30, 194, 500, false);
                muted('auth', PX + 30, 242, 500, 'SENHA', 14);
                passInput = input('auth', PX + 30, 264, 500, true);
                button('auth', PX + 30, 330, 240, 48, 'ENTRAR', B_PRIMARY, submitLogin);
                button('auth', PX + 290, 330, 240, 48, 'CRIAR CONTA', B_SECOND, submitRegister);
                button('auth', PX + 30, 400, 500, 44, 'VOLTAR', B_NEUTRAL, goBack);
        }

        function buildLobby():Void
        {
                panel('lobby', PX, 60, 380, 600);
                meText = label('lobby', PX + 24, 84, 340, '', 22);
                muted('lobby', PX + 24, 124, 340, 'A lista atualiza sozinha a cada 5 segundos.', 14);
                button('lobby', PX + 24, 170, 332, 50, 'CRIAR SERVIDOR', B_PRIMARY, function() showMode('create'));
                button('lobby', PX + 24, 236, 332, 50, 'SAIR DA CONTA', B_DANGER, logout);
                button('lobby', PX + 24, 602, 332, 44, 'VOLTAR', B_NEUTRAL, goBack);

                var listX:Int = PX + 400;
                var panelW:Int = FlxG.width - listX - PX;
                panel('lobby', listX, 60, panelW, 600);
                label('lobby', listX + 24, 84, 400, 'SERVIDORES ABERTOS', 24);

                for (i in 0...SLOTS)
                {
                        var idx:Int = i;
                        var y:Float = 130 + i * 70;
                        var bg:FlxSprite = panel('lobby', listX + 16, y, panelW - 32, 60, C_ROW);
                        var name:FlxText = label('lobby', listX + 36, y + 8, panelW - 240, '', 18);
                        var info:FlxText = muted('lobby', listX + 36, y + 34, panelW - 240, '', 14);
                        var join:MpButton = button('lobby', listX + panelW - 170, y + 10, 130, 40, 'ENTRAR', B_PRIMARY, function() joinFromSlot(idx));
                        slots.push({bg: bg, name: name, info: info, join: join});
                }

                muted('lobby', listX + 24, 566, 400, 'Senha da sala (se a sala tiver):', 14);
                joinPassInput = input('lobby', listX + 24, 590, 300, true);
        }

        function buildCreate():Void
        {
                panel('create', PX, 60, CONTENT_W, 600);
                label('create', PX + 30, 84, 900, 'NOVO SERVIDOR', 28);
                createSongText = muted('create', PX + 30, 130, 1100, '', 16);
                muted('create', PX + 30, 186, 500, 'NOME DO SERVIDOR', 14);
                nameInput = input('create', PX + 30, 208, 500, false);
                muted('create', PX + 30, 262, 500, 'SENHA DA SALA (6 dígitos, opcional)', 14);
                createPassInput = input('create', PX + 30, 284, 300, false);
                songPickButton = button('create', PX + 560, 208, 410, 44, '', B_NEUTRAL, cycleCreateSong);

                dieButton = button('create', PX + 30, 360, 300, 48, '', B_NEUTRAL, toggleDie);
                botButton = button('create', PX + 350, 360, 300, 48, '', B_NEUTRAL, toggleBot);
                speedButton = button('create', PX + 670, 360, 300, 48, '', B_NEUTRAL, cycleSpeed);

                muted('create', PX + 30, 420, 300, 'MOD DA PARTIDA', 14);
                modButton = button('create', PX + 30, 442, 940, 44, '', B_NEUTRAL, cycleMod);
                scanAvailableMods();

                button('create', PX + 30, 510, 300, 52, 'CRIAR SERVIDOR', B_PRIMARY, submitCreate);
                button('create', PX + 350, 510, 300, 52, 'VOLTAR', B_NEUTRAL, function() showMode('lobby'));
        }

        function buildRoom():Void
        {
                panel('room', PX, 40, CONTENT_W, 76);
                roomTitle = label('room', PX + 24, 54, CONTENT_W - 48, '', 26);
                roomInfo = muted('room', PX + 24, 90, CONTENT_W - 48, '', 15);

                panel('room', PX, 130, 360, 430);
                label('room', PX + 20, 146, 320, 'JOGADORES', 18);
                membersText = label('room', PX + 20, 178, 320, '', 18);

                panel('room', 420, 130, 820, 150);
                muted('room', 440, 146, 780, 'MÚSICA DA PARTIDA', 14);
                songTitle = label('room', 440, 168, 780, '', 24);
                prevSongButton = button('room', 440, 226, 170, 40, '< MÚSICA', B_NEUTRAL, function() cycleSong(-1));
                nextSongButton = button('room', 624, 226, 170, 40, 'MÚSICA >', B_NEUTRAL, function() cycleSong(1));

                progressBg = track('room', new FlxSprite(420, 296).makeGraphic(820, 22, C_TRACK));
                progressFill = track('room', new FlxSprite(420, 296).makeGraphic(820, 22, C_ACCENT));
                progressFill.clipRect = FlxRect.get(0, 0, 0, 22);
                progressText = muted('room', 420, 324, 820, '', 14);

                panel('room', 420, 352, 820, 208);
                chatText = label('room', 440, 366, 780, '', 15);
                chatInput = input('room', 440, 528, 600, false);
                button('room', 1060, 524, 160, 40, 'ENVIAR', B_PRIMARY, sendChat);

                readyButton = button('room', PX, 580, 230, 56, 'PRONTO', B_PRIMARY, toggleReady);
                playButton = button('room', PX + 250, 580, 230, 56, 'PLAY', B_SECOND, startMatch);
                button('room', PX + 500, 580, 260, 56, 'SAIR DA SALA', B_DANGER, leaveRoom);
                requestButton = button('room', PX + 780, 580, 260, 56, 'BAIXAR MOD', B_SECOND, requestMod);
        }

        override function update(elapsed:Float):Void
        {
                super.update(elapsed);

                pumpChunks();

                var ev:Dynamic = events.pop(false);
                while (ev != null)
                {
                        handleEvent(ev);
                        ev = events.pop(false);
                }

                var s:MpSocket = socket;
                if (s != null)
                {
                        var msg:Dynamic = s.inbox.pop(false);
                        while (msg != null)
                        {
                                handleServer(msg);
                                msg = s.inbox.pop(false);
                        }
                }

                if (pendingStart && Date.now().getTime() >= startAt)
                {
                        pendingStart = false;
                        launchMatch();
                }

                if (mode == 'lobby')
                {
                        refreshTimer += elapsed;
                        if (refreshTimer > 5)
                        {
                                refreshTimer = 0;
                                refreshRooms();
                        }
                }

                for (entry in buttons)
                {
                        if (entry.btn.clicked())
                        {
                                entry.btn.onClick();
                                break;
                        }
                }

                if (controls.BACK)
                {
                        if (mode == 'room')
                                leaveRoom();
                        else
                                goBack();
                }
        }

        function setStatus(s:String):Void
        {
                status.text = s;
        }

        function saveLogin(user:String, pass:String):Void
        {
                loginSave.data.username = user;
                loginSave.data.password = pass;
                loginSave.flush();
        }

        function playMenuMusic():Void
        {
                if (menuMusicOn)
                        return;
                menuMusicOn = true;
                FlxG.sound.playMusic(Paths.music('freakyMenu'), 0.7);
        }

        function setProgress(p:Float, text:String):Void
        {
                var clamped:Float = Math.max(0, Math.min(1, p));
                progressFill.clipRect = FlxRect.get(0, 0, Std.int(820 * clamped), 22);
                progressText.text = text;
        }

        function yn(v:Dynamic):String
        {
                return v == true ? 'SIM' : 'NÃO';
        }

        function errorOf(json:Dynamic):String
        {
                var e:Dynamic = Reflect.field(json, 'message');
                return e == null ? 'Erro desconhecido.' : Std.string(e);
        }

        function submitLogin():Void
        {
                var u:String = StringTools.trim(userInput.text);
                if (!USER_RE.match(u))
                {
                        setStatus('Usuário: de 3 a 20 letras ou números, sem espaço.');
                        return;
                }
                setStatus('Entrando...');
                var p:String = passInput.text;
                MpApi.login(u, p, function(s:Int, j:Dynamic) events.add({kind: 'login', status: s, json: j, user: u, pass: p}));
        }

        function submitRegister():Void
        {
                var u:String = StringTools.trim(userInput.text);
                if (!USER_RE.match(u))
                {
                        setStatus('Usuário: de 3 a 20 letras ou números, sem espaço.');
                        return;
                }
                setStatus('Criando conta...');
                var p:String = passInput.text;
                MpApi.register(u, p, function(s:Int, j:Dynamic) events.add({kind: 'register', status: s, json: j, user: u, pass: p}));
        }

        function logout():Void
        {
                closeSocket();
                setStatus('Saindo...');
                MpApi.logout(function(s:Int, j:Dynamic) events.add({kind: 'logout', status: s, json: j}));
        }

        function refreshRooms():Void
        {
                MpApi.listServers(function(s:Int, j:Dynamic) events.add({kind: 'list', status: s, json: j}));
        }

        function applySlots():Void
        {
                for (i in 0...slots.length)
                {
                        var show:Bool = i < roomCount;
                        slots[i].bg.visible = show;
                        slots[i].bg.active = show;
                        slots[i].name.visible = show;
                        slots[i].name.active = show;
                        slots[i].info.visible = show;
                        slots[i].info.active = show;
                        slots[i].join.show(show);
                }
        }

        function fillSlots(list:Array<Dynamic>):Void
        {
                listRooms = list;
                roomCount = Std.int(Math.min(list.length, SLOTS));
                for (i in 0...roomCount)
                {
                        var r:Dynamic = list[i];
                        slots[i].name.text = Std.string(r.name) + (r.hasPassword == true ? '   [SENHA]' : '');
                        slots[i].info.text = 'Host: ' + r.host + '   ·   ' + r.players + '/' + r.max + ' jogadores   ·   Música: ' + r.settings.song.name;
                }
                applySlots();
                if (list.length == 0)
                        setStatus('Nenhum servidor aberto. Crie um!');
        }

        function joinFromSlot(i:Int):Void
        {
                var r:Dynamic = listRooms[i];
                if (r == null)
                        return;
                var pw:String = StringTools.trim(joinPassInput.text);
                if (r.hasPassword == true && !PASS_RE.match(pw))
                {
                        setStatus('Essa sala tem senha de 6 dígitos.');
                        return;
                }
                pendingJoin = {roomId: r.id, password: pw};
                connectSocket();
        }

        function createFolder():String
        {
                // The host can now pick any installed mod via the mod button.
                // Fall back to the song's mod only if the user hasn't cycled away.
                if (availableMods.length > 0)
                        return availableMods[modIndex];
                var p:PendingSong = MpMatch.pendingSong;
                if (p == null)
                        return null;
                return p.mod == null || p.mod == '' ? BASE_FOLDER : p.mod;
        }

        function scanAvailableMods():Void
        {
                availableMods = ['_base'];
                try
                {
                        var modsRoot:String = Paths.mods('');
                        if (modsRoot != null && FileSystem.exists(modsRoot))
                        {
                                for (entry in FileSystem.readDirectory(modsRoot))
                                {
                                        if (entry == null || entry == '')
                                                continue;
                                        var full:String = modsRoot + '/' + entry;
                                        if (FileSystem.isDirectory(full))
                                                availableMods.push(entry);
                                }
                        }
                }
                catch (e:Dynamic)
                {
                }
                // If the pending song came from a mod, pre-select it.
                var p:PendingSong = MpMatch.pendingSong;
                if (p != null && p.mod != null && p.mod != '')
                {
                        var idx:Int = availableMods.indexOf(p.mod);
                        if (idx != -1)
                                modIndex = idx;
                }
        }

        function cycleMod():Void
        {
                if (availableMods.length == 0)
                        return;
                modIndex = (modIndex + 1) % availableMods.length;
                refreshCreateSongs();
                refreshCreateLabels();
        }

        function refreshCreateSongs():Void
        {
                var folder:String = createFolder();
                createSongs = folder == null ? [] : songsOfMod(folder == BASE_FOLDER ? '' : folder);
                createSongIdx = 0;
                var p:PendingSong = MpMatch.pendingSong;
                if (p != null)
                {
                        var idx:Int = createSongs.indexOf(p.name);
                        if (idx != -1)
                                createSongIdx = idx;
                }
        }

        function cycleCreateSong():Void
        {
                if (createSongs.length == 0)
                        return;
                createSongIdx = (createSongIdx + 1) % createSongs.length;
                refreshCreateLabels();
        }

        function toggleDie():Void
        {
                dieOnMiss = !dieOnMiss;
                refreshCreateLabels();
        }

        function toggleBot():Void
        {
                botplay = !botplay;
                refreshCreateLabels();
        }

        function cycleSpeed():Void
        {
                speedIndex = (speedIndex + 1) % NOTE_SPEEDS.length;
                refreshCreateLabels();
        }

        function refreshCreateLabels():Void
        {
                var song:String = createSongs.length == 0 ? 'nenhuma' : createSongs[createSongIdx];
                createSongText.text = 'Música: ' + song + '   ·   Mod: ' + createFolder();
                songPickButton.setLabel(createSongs.length == 0 ? 'SEM MÚSICAS' : 'MÚSICA: ' + song + '  (' + (createSongIdx + 1) + '/' + createSongs.length + ')');
                dieButton.setLabel('MORRER AO ERRAR: ' + yn(dieOnMiss));
                botButton.setLabel('BOTPLAY: ' + yn(botplay));
                speedButton.setLabel('VELOCIDADE: ' + NOTE_SPEEDS[speedIndex]);
                var modLabel:String = availableMods.length > 0 ? availableMods[modIndex] : BASE_FOLDER;
                modButton.setLabel('MOD: ' + modLabel + '  (' + (modIndex + 1) + '/' + availableMods.length + ')');
        }

        function submitCreate():Void
        {
                var folder:String = createFolder();
                if (folder == null || createSongs.length == 0)
                {
                        setStatus('Escolha um mod com músicas antes de criar o servidor.');
                        return;
                }
                var songName:String = createSongs[createSongIdx];
                var p:PendingSong = MpMatch.pendingSong;
                var songDifficulty:Int = p != null && p.name == songName ? p.difficulty : 0;

                var name:String = StringTools.trim(nameInput.text);
                if (name == '')
                {
                        setStatus('Dê um nome para o servidor.');
                        return;
                }

                var pw:String = StringTools.trim(createPassInput.text);
                if (pw != '' && !PASS_RE.match(pw))
                {
                        setStatus('Senha da sala: exatamente 6 dígitos.');
                        return;
                }

                var size:Float = folder == BASE_FOLDER ? 0 : MpModTransfer.folderSize(folder);
                if (size > MpModTransfer.MAX_BYTES)
                {
                        setStatus('O mod tem ' + Std.int(size / 1048576) + ' MB; o limite do servidor é ' + Std.int(MpModTransfer.MAX_BYTES / 1048576) + ' MB.');
                        return;
                }
                var payload:Dynamic = {
                        name: name,
                        mod: {name: folder, folder: folder, size: size},
                        settings: {
                                dieOnMiss: dieOnMiss,
                                botplay: botplay,
                                noteSpeed: NOTE_SPEEDS[speedIndex],
                                password: pw == '' ? null : pw,
                                song: {name: songName, difficulty: songDifficulty}
                        }
                };

                pendingPassword = pw;
                roomFolder = folder;
                hostPlan = null;
                setStatus('Criando servidor...');
                MpApi.createServer(payload, function(s:Int, j:Dynamic) events.add({kind: 'create', status: s, json: j}));
        }

        function connectSocket():Void
        {
                closeSocket();
                socket = new MpSocket(MpApi.WS_URL + '?token=' + MpApi.token);
                MpMatch.socket = socket;
                setStatus('Conectando à sala...');
        }

        function closeSocket():Void
        {
                var s:MpSocket = socket;
                socket = null;
                MpMatch.socket = null;
                if (s != null)
                        s.close();
        }

        function toggleReady():Void
        {
                if (socket == null || !modReady || isHost)
                        return;
                myReady = !myReady;
                socket.send({type: 'ready', ready: myReady});
                refreshRoomUI();
        }

        function roomModDirectory():String
        {
                if (room == null || room.mod == null)
                        return '';
                var folder:String = Std.string(room.mod.folder);
                return folder == BASE_FOLDER ? '' : folder;
        }

        function songsOfMod(modDir:String):Array<String>
        {
                var out:Array<String> = [];
                var previous:String = Mods.currentModDirectory;
                Mods.currentModDirectory = modDir;
                try
                {
                        WeekData.reloadWeekFiles(false);
                        for (w in WeekData.weeksList)
                        {
                                var leWeek:WeekData = WeekData.weeksLoaded.get(w);
                                if (leWeek == null || leWeek.songs == null)
                                        continue;
                                for (song in leWeek.songs)
                                {
                                        var n:String = Std.string(song[0]);
                                        if (n != '' && out.indexOf(n) == -1)
                                                out.push(n);
                                }
                        }
                }
                catch (e:Dynamic)
                {
                }
                Mods.currentModDirectory = previous;
                return out;
        }

        function scanSongs():Void
        {
                songsList = songsOfMod(roomModDirectory());
                syncSongIndex();
        }

        function requestMod():Void
        {
                if (socket == null || room == null || isHost || modReady || requested)
                        return;
                requested = true;
                socket.send({type: 'modRequest'});
                setStatus('Pedido enviado. Aguardando o host enviar o mod...');
                refreshRoomUI();
        }

        function updateSendProgress(to:String):Void
        {
                if (!sendTotalTo.exists(to))
                        return;
                var total:Int = sendTotalTo.get(to);
                var done:Int = sentTo.exists(to) ? sentTo.get(to) : 0;
                if (done >= total)
                {
                        setProgress(1, 'Mod entregue para ' + to + '.');
                        setStatus('Mod entregue para ' + to + '.');
                        return;
                }
                var text:String = 'Enviando o mod para ' + to + ': ' + Std.int(done * 100 / total) + '%   (' + done + '/' + total + ' pedaços)';
                setProgress(done / total, text);
                setStatus(text);
        }

        function syncSongIndex():Void
        {
                if (room == null)
                        return;
                var current:String = Std.string(room.settings.song.name);
                songIdx = songsList.indexOf(current);
                if (songIdx == -1)
                {
                        songsList.unshift(current);
                        songIdx = 0;
                }
        }

        function cycleSong(delta:Int):Void
        {
                if (!isHost || socket == null || room == null || songsList.length == 0)
                        return;
                songIdx = (songIdx + delta + songsList.length) % songsList.length;
                socket.send({type: 'setSong', name: songsList[songIdx], difficulty: room.settings.song.difficulty});
                setStatus('Trocando a música para ' + songsList[songIdx] + '...');
        }

        function loadRoomSong():Dynamic
        {
                var s:Dynamic = room.settings.song;
                var folder:String = Paths.formatToSongPath(Std.string(s.name));
                try
                {
                        // roomModDirectory() already converts _base -> '' so the chart
                        // lookup falls back to the base assets folder correctly.
                        Mods.currentModDirectory = roomModDirectory();
                        return Song.loadFromJson(Highscore.formatSong(folder, Std.int(s.difficulty)), folder);
                }
                catch (e:Dynamic)
                {
                        setStatus('Não consegui carregar a música: ' + Std.string(e));
                        return null;
                }
        }

        function startMatch():Void
        {
                if (socket == null || !isHost || room == null)
                        return;
                var song:Dynamic = loadRoomSong();
                if (song == null)
                        return;
                var notes:Array<Dynamic> = MpMatch.buildChart(song);
                if (notes.length == 0)
                {
                        setStatus('Essa música não tem notas.');
                        return;
                }
                // Also send chart events so non-host clients can trigger them.
                // Events come from the song data and include things like camera
                // moves, character swaps, screen shakes, etc.
                var chartEvents:Array<Dynamic> = [];
                try
                {
                        if (song != null && song.events != null)
                                chartEvents = cast song.events;
                }
                catch(e:Dynamic) {}
                socket.send({type: 'chart', notes: notes, events: chartEvents});
                socket.send({type: 'start'});
                setStatus('Enviando a música para o servidor...');
        }

        function sendChat():Void
        {
                if (socket == null)
                        return;
                var text:String = StringTools.trim(chatInput.text);
                if (text == '')
                        return;
                socket.send({type: 'chat', text: text});
                chatInput.text = '';
        }

        function leaveRoom():Void
        {
                if (mode != 'room')
                        return;
                if (socket != null)
                        socket.send({type: 'leave'});
                closeSocket();
                room = null;
                isHost = false;
                pendingStart = false;
                setProgress(0, '');
                showMode('lobby');
                setStatus('Você saiu da sala.');
                refreshRooms();
        }

        function enterRoom(r:Dynamic):Void
        {
                room = r;
                isHost = r.host == MpApi.username;
                myReady = false;
                chatLines = [];
                chatText.text = '';
                roomFolder = r.mod.folder;
                stopIncoming();
                hostPlan = null;
                pendingSend = [];
                chunkQueue = [];
                inFlight = new Map();
                sentTo = new Map();
                sendTotalTo = new Map();
                requested = false;
                modReady = isHost || roomFolder == BASE_FOLDER || FileSystem.exists(Paths.mods(roomFolder));
                if (isHost)
                        scanSongs();
                showMode('room');
                setProgress(modReady ? 1 : 0, modReady ? 'Mod pronto.' : 'Aguardando o host enviar o mod.');
                setStatus(modReady ? 'Pronto para jogar.' : 'Aguardando o host enviar o mod...');
        }

        function resumeRoom():Void
        {
                socket = MpMatch.socket;
                room = MpMatch.room;
                isHost = MpMatch.isHost;
                roomFolder = room.mod.folder;
                modReady = true;
                myReady = false;
                chatLines = [];
                MpMatch.returning = false;
                MpMatch.active = false;
                if (isHost)
                        scanSongs();
                showMode('room');
                setProgress(1, 'Mod pronto.');
                if (MpMatch.lastResults.length > 0)
                        setStatus('Partida encerrada. ' + formatResults());
                else
                        setStatus('Voltou para a sala.');
        }

        function formatResults():String
        {
                var parts:Array<String> = [];
                for (r in MpMatch.lastResults)
                        parts.push(r.username + ' ' + r.score + ' pts' + (r.dead == true ? ' (morreu)' : ''));
                return parts.join('  |  ');
        }

        function refreshRoomUI():Void
        {
                if (room == null)
                        return;

                var s:Dynamic = room.settings;
                roomTitle.text = Std.string(room.name);
                roomInfo.text = 'Mod: ' + room.mod.name + '   ·   Morrer ao errar: ' + yn(s.dieOnMiss) + '   ·   Botplay: ' + yn(s.botplay)
                        + '   ·   Velocidade: ' + s.noteSpeed;
                songTitle.text = Std.string(s.song.name) + '   (dificuldade ' + s.song.difficulty + ')';

                var lines:Array<String> = [];
                for (m in cast(room.members, Array<Dynamic>))
                {
                        var tag:String = m.username == room.host ? '[HOST] ' : '';
                        var state:String = m.ready == true ? '  - PRONTO' : '  - aguardando';
                        lines.push(tag + m.username + state);
                }
                membersText.text = lines.join('\n');

                chatText.text = chatLines.slice(Std.int(Math.max(0, chatLines.length - 9))).join('\n');

                prevSongButton.show(isHost);
                nextSongButton.show(isHost);

                readyButton.show(!isHost && modReady);
                readyButton.setLabel(myReady ? 'CANCELAR' : 'PRONTO');
                playButton.show(isHost);
                requestButton.show(!isHost && !modReady && roomFolder != BASE_FOLDER && !requested);
        }

        function appendChat(line:String):Void
        {
                chatLines.push(line);
                if (mode == 'room')
                        refreshRoomUI();
        }

        function handleEvent(ev:Dynamic):Void
        {
                switch (ev.kind)
                {
                        case 'login' | 'register':
                                if ((ev.status == 200 || ev.status == 201) && ev.json.success == true)
                                {
                                        saveLogin(ev.user, ev.pass);
                                        showMode('lobby');
                                        setStatus('Escolha um servidor ou crie um.');
                                        refreshRooms();
                                }
                                else
                                {
                                        setStatus(errorOf(ev.json));
                                }

                        case 'logout':
                                closeSocket();
                                showMode('auth');
                                setStatus('Você saiu da conta.');

                        case 'list':
                                if (ev.status == 200 && ev.json.success == true)
                                        fillSlots(cast ev.json.rooms);
                                else
                                        setStatus(errorOf(ev.json));

                        case 'create':
                                if (ev.status == 201 && ev.json.success == true)
                                {
                                        pendingJoin = {roomId: ev.json.roomId, password: pendingPassword};
                                        connectSocket();
                                }
                                else
                                {
                                        setStatus(errorOf(ev.json));
                                }

                        case 'plan':
                                encoding = false;
                                if (ev.error != null)
                                {
                                        setProgress(0, 'Falha ao preparar o mod.');
                                        setStatus('Falha ao preparar o mod: ' + ev.error);
                                        return;
                                }
                                hostPlan = ev.data;
                                flushPending();

                        case 'modProgress':
                                var progDone:Float = ev.done;
                                var progTotal:Float = ev.total;
                                var progPct:Int = progTotal > 0 ? Std.int(progDone * 100 / progTotal) : 0;
                                var progText:String = 'Baixando o mod do host (' + ev.stage + ')   ' + progPct + '%   ·   ' + ev.files + '/' + ev.filesTotal + ' arquivos';
                                setProgress(progTotal > 0 ? progDone / progTotal : 0, progText);
                                setStatus(progText);

                        case 'modDone':
                                if (ev.ok == true)
                                {
                                        modReady = true;
                                        setProgress(1, 'Mod instalado.');
                                        setStatus('Mod instalado. Clique em PRONTO.');
                                        refreshRoomUI();
                                }
                                else
                                {
                                        requested = false;
                                        setProgress(0, 'Falha ao instalar o mod.');
                                        setStatus('Falha ao instalar o mod: ' + ev.error);
                                }

                        case 'scripts':
                                MpMatch.scriptPaths = cast ev.paths;
                }
        }

        function handleServer(m:Dynamic):Void
        {
                switch (m.type)
                {
                        case '_open':
                                if (pendingJoin != null && socket != null)
                                {
                                        socket.send({type: 'join', roomId: pendingJoin.roomId, password: pendingJoin.password});
                                        pendingJoin = null;
                                }

                        case '_error':
                                setStatus('Erro de conexão: ' + m.message);

                        case '_close':
                                if (mode == 'room')
                                {
                                        setStatus('Conexão com a sala caiu.');
                                        closeSocket();
                                        showMode('lobby');
                                        refreshRooms();
                                }

                        case 'error':
                                setStatus(Std.string(m.message));

                        case 'joinedRoom':
                                enterRoom(m.room);

                        case 'roomState':
                                room = m.room;
                                if (isHost)
                                        syncSongIndex();
                                refreshRoomUI();

                        case 'chart':
                                MpMatch.storeChart(cast m.entries);
                                if (m.events != null)
                                        storedEvents = cast m.events;

                        case 'chartOk':
                                setStatus('Música enviada: ' + m.count + ' notas. Iniciando...');

                        case 'playerJoined':
                                appendChat('* ' + m.username + ' entrou');

                        case 'modRequest':
                                if (isHost && roomFolder != BASE_FOLDER)
                                {
                                        var requester:String = Std.string(m.from);
                                        appendChat('* ' + requester + ' pediu o mod');
                                        if (pendingSend.indexOf(requester) == -1)
                                                pendingSend.push(requester);
                                        ensurePayload();
                                }

                        case 'playerLeft':
                                appendChat('* ' + m.username + ' saiu');
                                if (isHost)
                                {
                                        inFlight.remove(m.username);
                                        chunkQueue = chunkQueue.filter(function(c) return c.to != m.username);
                                }

                        case 'modAck':
                                if (isHost && m.index != null && inFlight.exists(m.from))
                                {
                                        var left:Int = inFlight.get(m.from) - 1;
                                        inFlight.set(m.from, left < 0 ? 0 : left);
                                }
                                if (isHost && m.index != null)
                                {
                                        var ackedBy:String = Std.string(m.from);
                                        sentTo.set(ackedBy, (sentTo.exists(ackedBy) ? sentTo.get(ackedBy) : 0) + 1);
                                        updateSendProgress(ackedBy);
                                }

                        case 'chat':
                                appendChat(m.from + ': ' + m.text);

                        case 'modChunk':
                                receiveChunk(m);

                        case 'start':
                                startAt = m.startAt;
                                MpMatch.matchId = Std.string(m.matchId);
                                pendingStart = true;
                                MpMatch.scriptPaths = [];
                                MpScripts.fetch(function(paths:Array<String>) events.add({kind: 'scripts', paths: paths}));
                                setStatus('Partida começando...');

                        case 'playerLoaded':
                                if (room != null && m.username != null)
                                {
                                        var who:String = Std.string(m.username);
                                        appendChat('* ' + who + ' carregou a partida');
                                }

                        case 'allLoaded':
                                setStatus('Todos carregaram! Iniciando...');

                        case 'end':
                                MpMatch.lastResults = cast m.results;
                                setStatus('Partida encerrada. ' + formatResults());

                        case 'roomClosed':
                                room = null;
                                isHost = false;
                                closeSocket();
                                showMode('lobby');
                                setStatus('O servidor foi fechado: ' + m.reason);
                                refreshRooms();

                        case 'leftRoom':
                                closeSocket();
                                room = null;
                                showMode('lobby');
                                refreshRooms();
                }
        }

        function ensurePayload():Void
        {
                if (hostPlan != null)
                {
                        flushPending();
                        return;
                }
                if (encoding || roomFolder == null || roomFolder == BASE_FOLDER)
                        return;

                encoding = true;
                var folder:String = roomFolder;
                setProgress(0, 'Preparando o mod para enviar...');
                setStatus('Preparando o mod para enviar...');
                Thread.create(() ->
                {
                        try
                        {
                                events.add({kind: 'plan', data: MpModTransfer.plan(folder)});
                        }
                        catch (e:Dynamic)
                        {
                                events.add({kind: 'plan', error: Std.string(e)});
                        }
                });
        }

        function flushPending():Void
        {
                var targets:Array<String> = pendingSend;
                pendingSend = [];
                for (to in targets)
                        sendChunks(to);
        }

        function sendChunks(to:String):Void
        {
                if (socket == null || hostPlan == null)
                        return;
                for (c in chunkQueue)
                        if (c.to == to)
                                return;

                var total:Int = hostPlan.chunks;
                sentTo.set(to, 0);
                sendTotalTo.set(to, total);
                for (i in 0...total)
                        chunkQueue.push({to: to, index: i, total: total});
                setProgress(0, 'Enviando o mod para ' + to + ' (' + hostPlan.files + ' arquivos)...');
                setStatus('Enviando o mod para ' + to + ' (' + hostPlan.files + ' arquivos, ' + total + ' pedaços)...');
        }

        function pumpChunks():Void
        {
                if (chunkQueue.length == 0 || socket == null || hostPlan == null)
                        return;

                // Um pedaço por frame, e só para quem ainda tem menos de CHUNK_WINDOW pedaços sem confirmação.
                var i:Int = 0;
                while (i < chunkQueue.length)
                {
                        var c = chunkQueue[i];
                        var flying:Int = inFlight.exists(c.to) ? inFlight.get(c.to) : 0;
                        if (flying >= CHUNK_WINDOW)
                        {
                                i++;
                                continue;
                        }
                        chunkQueue.splice(i, 1);
                        inFlight.set(c.to, flying + 1);
                        socket.send({
                                type: 'modChunk',
                                to: c.to,
                                index: c.index,
                                total: c.total,
                                data: MpModTransfer.chunkBase64(hostPlan, c.index)
                        });
                        return;
                }
        }

        function receiveChunk(m:Dynamic):Void
        {
                var index:Int = m.index;
                var total:Int = m.total;
                if (socket != null)
                        socket.send({type: 'modAck', index: index});
                if (modReady || roomFolder == null)
                        return;

                if (index == 0)
                        startIncoming();
                else if (incomingQueue == null)
                        return;
                if (index != incomingIndex)
                        return;

                incomingIndex++;
                incomingQueue.add({index: index, total: total, data: m.data});
                if (index == total - 1)
                        incomingQueue = null;
        }

        function startIncoming():Void
        {
                stopIncoming();
                var queue:Deque<Dynamic> = new Deque();
                var folder:String = roomFolder;
                incomingQueue = queue;
                incomingIndex = 0;
                setProgress(0, 'Recebendo a estrutura do mod...');
                setStatus('Recebendo o mod do host...');
                Thread.create(() -> MpModTransfer.receive(queue, events, folder));
        }

        function stopIncoming():Void
        {
                if (incomingQueue != null)
                        incomingQueue.add(null);
                incomingQueue = null;
                incomingIndex = 0;
        }

        function launchMatch():Void
        {
                if (room == null)
                        return;

                // MpMatch.modFolder can be '_base' (the multiplayer sentinel) when the
                // room uses no mod.  Mods.currentModDirectory expects '' in that case,
                // otherwise Song.loadFromJson looks in mods/_base/ instead of the base
                // assets and the chart fails to load with a "TEXT resource" error.
                var modDir:String = MpMatch.modFolder;
                if (modDir == null || modDir == BASE_FOLDER)
                        modDir = '';

                // Debug: log what we're about to load so crash reports are useful.
                try { File.saveContent('mp_launch_debug.log',
                        'modFolder=' + MpMatch.modFolder + '\n' +
                        'modDir=' + modDir + '\n' +
                        'songName=' + MpMatch.songName + '\n' +
                        'songDifficulty=' + MpMatch.songDifficulty + '\n' +
                        'modsRoot=' + Paths.mods('') + '\n' +
                        'modExists=' + (modDir != '' ? Std.string(FileSystem.exists(Paths.mods(modDir))) : 'N/A') + '\n' +
                        'songPath=' + Paths.mods(modDir + '/songs/' + Paths.formatToSongPath(MpMatch.songName) + '/') + '\n'
                ); } catch(e:Dynamic) {}

                if (modDir != '' && !FileSystem.exists(Paths.mods(modDir)))
                {
                        launchFailed('Mod não instalado: ' + modDir + ' (esperado em: ' + Paths.mods(modDir) + ')');
                        return;
                }

                MpMatch.begin(room, MpApi.username);
                MpMatch.socket = socket;

                var songFolder:String = Paths.formatToSongPath(MpMatch.songName);
                try
                {
                        // Set the mod directory BEFORE any Paths/Song call so that
                        // the chart JSON, Inst.ogg, Voices.ogg, stage data, etc. are
                        // all resolved from mods/<modDir>/songs/<song>/ instead of
                        // assets/shared/data/<song>/.
                        Mods.currentModDirectory = modDir;

                        // Verify the chart file exists before trying to load it.
                        var chartFile:String = Highscore.formatSong(songFolder, MpMatch.songDifficulty);
                        #if sys
                        var chartPath:String = modDir != ''
                                ? Paths.mods(modDir + '/data/' + songFolder + '/' + chartFile + '.json')
                                : '';
                        if (chartPath != '' && !FileSystem.exists(chartPath))
                        {
                                // Also check the mod's songs folder structure
                                chartPath = Paths.mods(modDir + '/songs/' + songFolder + '/' + chartFile + '.json');
                        }
                        #end

                        PlayState.SONG = Song.loadFromJson(chartFile, songFolder);
                        PlayState.SONG.speed = MpMatch.noteSpeed;
                        StageData.loadDirectory(PlayState.SONG);
                        PlayState.isStoryMode = false;
                        PlayState.storyDifficulty = MpMatch.songDifficulty;
                }
                catch (e:Dynamic)
                {
                        launchFailed(Std.string(e) + ' (mod=' + modDir + ', song=' + songFolder + ')');
                        return;
                }

                LoadingState.prepareToSong();
                LoadingState.loadAndSwitchState(new PlayState());
        }

        function launchFailed(reason:String):Void
        {
                MpMatch.active = false;
                MpMatch.returning = false;
                MpMatch.socket = null;
                MpMatch.matchId = null;
                try
                {
                        File.saveContent('mp_launch_error.log', 'Motivo: ' + reason + '\n' + haxe.CallStack.toString(haxe.CallStack.callStack()) + '\n');
                }
                catch (e:Dynamic)
                {
                }
                setStatus('Não consegui iniciar a partida: ' + reason + ' (detalhes em mp_launch_error.log)');
        }

        function goBack():Void
        {
                if (mode == 'create')
                {
                        showMode('lobby');
                        return;
                }
                if (mode == 'lobby' || mode == 'auth')
                {
                        closeSocket();
                        MusicBeatState.switchState(new FreeplayState());
                }
        }

        override function destroy():Void
        {
                menuMusicOn = false;
                if (!MpMatch.active && !MpMatch.returning)
                        closeSocket();
                super.destroy();
        }
}
