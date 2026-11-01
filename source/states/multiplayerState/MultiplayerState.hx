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
import general.backend.MpDropdown;
import general.backend.MpManifest;
import general.backend.MpMatch;
import general.backend.MpMatch.PendingSong;
import general.backend.MpModTransfer;
import general.backend.MpModTransfer.ModPlan;
import general.backend.MpScripts;
import general.backend.MpSocket;
import general.backend.MusicBeatState;
import general.backend.NFLog;
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
        var createSongMods:Array<String> = [];
        var songsByMod:Map<String, Array<String>> = new Map();
        var scanQueue:Array<String> = [];
        var modIndex:Int = 0;
        var dieOnMiss:Bool = false;
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
        static final CHUNK_WINDOW:Int = 2;
        var incomingQueue:Deque<Dynamic> = null;
        var incomingIndex:Int = 0;

        var pendingStart:Bool = false;
        var startAt:Float = 0;
        var startAtLocal:Float = 0;
        var requestWait:Float = 0;
        var statusKnown:Bool = false;
        var awaitingStatus:Bool = false;
        var statusWait:Float = 0;
        var joinWait:Float = 0;

        var estimateText:FlxText;
        var modDropdown:MpDropdown;
        var songDropdown:MpDropdown;
        var diffDropdown:MpDropdown;
        var roomSongDropdown:MpDropdown;
        var roomDiffDropdown:MpDropdown;
        var dropdowns:Array<{group:String, dd:MpDropdown}> = [];
        var sendModeButton:MpButton;
        var optimizeButton:MpButton;
        var createDiffIdx:Int = 0;
        var sendSongOnly:Bool = false;
        var optimizeMod:Bool = false;
        var speedAuto:Bool = true;
        var estimateToken:Int = 0;
        var pendingApplied:Bool = false;
        var diffsBySong:Map<String, Array<String>> = new Map();
        var scannedMods:Map<String, Bool> = new Map();
        var manifestKnown:Bool = false;
        var checking:Bool = false;
        var recheck:Bool = false;
        var publishing:Bool = false;
        var republish:Bool = false;
        var publishedKey:String = '';
        var needsOf:Map<String, Array<String>> = new Map();
        var plans:Map<String, ModPlan> = new Map();
        var planning:Map<String, Bool> = new Map();
        var resultTitle:FlxText;
        var resultLocal:FlxText;
        var resultRemote:FlxText;
        var waitingResults:Bool = false;

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
                buildResults();

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
                for (d in dropdowns)
                        d.dd.show(d.group == m);

                if (m == 'lobby')
                {
                        meText.text = MpApi.username == null ? '' : 'Logado como ' + MpApi.username;
                        applySlots();
                }
                if (m == 'create')
                {
                        applyPending();
                        refreshCreateSongs();
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

        function dropdown(group:String, x:Float, y:Float, w:Int, h:Int, rowCount:Int, prefix:String, cb:Int->Void):MpDropdown
        {
                var d:MpDropdown = new MpDropdown(x, y, w, h, rowCount, prefix, B_NEUTRAL, cb);
                var parts:Array<MpButton> = [d.main].concat(d.rows);
                for (b in parts)
                {
                        add(b.shadow);
                        add(b.bg);
                        add(b.label);
                }
                dropdowns.push({group: group, dd: d});
                return d;
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

                dieButton = button('create', PX + 30, 350, 240, 44, '', B_NEUTRAL, toggleDie);
                botButton = button('create', PX + 290, 350, 240, 44, '', B_NEUTRAL, toggleBot);
                sendModeButton = button('create', PX + 30, 404, 240, 44, '', B_NEUTRAL, toggleSendMode);
                optimizeButton = button('create', PX + 290, 404, 240, 44, '', B_NEUTRAL, toggleOptimize);
                speedButton = button('create', PX + 30, 458, 500, 44, '', B_NEUTRAL, cycleSpeed);
                estimateText = muted('create', PX + 560, 470, 600, '', 15);

                button('create', PX + 30, 540, 300, 52, 'CRIAR SERVIDOR', B_PRIMARY, submitCreate);
                button('create', PX + 350, 540, 300, 52, 'VOLTAR', B_NEUTRAL, function() showMode('lobby'));

                scanAvailableMods();
                diffDropdown = dropdown('create', PX + 560, 340, 560, 44, 5, 'DIFICULDADE', onCreateDiff);
                songDropdown = dropdown('create', PX + 560, 274, 560, 44, 7, 'MÚSICA', onCreateSong);
                modDropdown = dropdown('create', PX + 560, 208, 560, 44, 7, 'MOD', onCreateMod);
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

                roomDiffDropdown = dropdown('room', 904, 226, 320, 40, 5, 'DIF', onRoomDiff);
                roomSongDropdown = dropdown('room', 440, 226, 450, 40, 7, 'MÚSICA', onRoomSong);
        }

        function buildResults():Void
        {
                panel('results', PX, 60, CONTENT_W, 600);
                resultTitle = label('results', PX + 30, 84, 1100, 'RESULTADO DA PARTIDA', 30);
                panel('results', PX + 30, 150, 560, 340, C_ROW);
                panel('results', PX + 610, 150, 560, 340, C_ROW);
                resultLocal = label('results', PX + 50, 170, 520, '', 22);
                resultRemote = label('results', PX + 630, 170, 520, '', 22);
                button('results', PX + 30, 540, 320, 52, 'VOLTAR AO SERVIDOR', B_PRIMARY, backToRoom);
                button('results', PX + 370, 540, 260, 52, 'SAIR DA SALA', B_DANGER, leaveRoom);
        }

        override function update(elapsed:Float):Void
        {
                super.update(elapsed);

                try
                {
                        pumpChunks();
                }
                catch (e:Dynamic)
                {
                        chunkQueue = [];
                        NFLog.exception('mod', e);
                        setStatus('Erro ao enviar o mod: ' + Std.string(e));
                }

                var ev:Dynamic = events.pop(false);
                while (ev != null)
                {
                        try
                        {
                                handleEvent(ev);
                        }
                        catch (e:Dynamic)
                        {
                                NFLog.exception('ui', e);
                                setStatus('Erro interno: ' + Std.string(e));
                        }
                        ev = events.pop(false);
                }

                if (mode == 'room' && !isHost && !modReady && !statusKnown)
                        joinWait += elapsed;
                else
                        joinWait = 0;
                if (awaitingStatus)
                {
                        statusWait += elapsed;
                        if (statusWait > 20)
                        {
                                awaitingStatus = false;
                                statusKnown = true;
                                setStatus('O servidor não respondeu à verificação do mod. Clique em BAIXAR MOD para tentar de novo.');
                                refreshRoomUI();
                        }
                }
                else
                        statusWait = 0;
                if (joinWait > 10 && !statusKnown && !checking && !awaitingStatus)
                {
                        statusKnown = true;
                        refreshRoomUI();
                }

                if (requested && incomingQueue == null)
                {
                        requestWait += elapsed;
                        if (requestWait > 20)
                        {
                                requested = false;
                                requestWait = 0;
                                setStatus('O host não respondeu. Clique em BAIXAR MOD para tentar de novo.');
                                refreshRoomUI();
                        }
                }
                else
                        requestWait = 0;

                for (entry in buttons)
                        entry.btn.hover();
                for (d in dropdowns)
                        d.dd.hover();

                var s:MpSocket = socket;
                if (s != null)
                {
                        var msg:Dynamic = s.inbox.pop(false);
                        while (msg != null)
                        {
                                try
                                {
                                        handleServer(msg);
                                }
                                catch (e:Dynamic)
                                {
                                        NFLog.exception('ui', e);
                                        setStatus('Erro interno: ' + Std.string(e));
                                }
                                msg = s.inbox.pop(false);
                        }
                }

                if (pendingStart && Date.now().getTime() >= startAtLocal)
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

                var consumed:Bool = false;
                var di:Int = dropdowns.length - 1;
                while (di >= 0)
                {
                        if (dropdowns[di].dd.update())
                        {
                                consumed = true;
                                break;
                        }
                        di--;
                }
                if (!consumed)
                {
                        for (entry in buttons)
                        {
                                if (entry.btn.clicked())
                                {
                                        entry.btn.onClick();
                                        break;
                                }
                        }
                }

                if (controls.BACK)
                {
                        var closed:Bool = false;
                        for (d in dropdowns)
                                if (d.dd.open)
                                {
                                        d.dd.setOpen(false);
                                        closed = true;
                                }
                        if (!closed)
                        {
                                if (mode == 'results')
                                        backToRoom();
                                else if (mode == 'room')
                                        leaveRoom();
                                else
                                        goBack();
                        }
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
                return availableMods.length > 0 ? availableMods[modIndex] : BASE_FOLDER;
        }

        function modDirOf(folder:String):String
        {
                return folder == null || folder == BASE_FOLDER ? '' : folder;
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
                                        if (FileSystem.isDirectory(modsRoot + '/' + entry))
                                                availableMods.push(entry);
                                }
                        }
                }
                catch (e:Dynamic)
                {
                }
                if (availableMods.length > 1)
                        modIndex = 1;
                var p:PendingSong = MpMatch.pendingSong;
                if (p != null && p.mod != null && p.mod != '')
                {
                        var idx:Int = availableMods.indexOf(p.mod);
                        if (idx != -1)
                                modIndex = idx;
                }
        }

        function ensureSongs(folder:String):Array<String>
        {
                if (!songsByMod.exists(folder))
                        songsByMod.set(folder, songsOfMod(modDirOf(folder)));
                return songsByMod.get(folder);
        }

        function applyPending():Void
        {
                if (pendingApplied)
                        return;
                pendingApplied = true;
                var p:PendingSong = MpMatch.pendingSong;
                if (p == null)
                        return;
                var i:Int = ensureSongs(createFolder()).indexOf(p.name);
                if (i != -1)
                {
                        createSongIdx = i;
                        createDiffIdx = p.difficulty;
                }
        }

        function onCreateMod(idx:Int):Void
        {
                modIndex = idx;
                createSongIdx = 0;
                createDiffIdx = 0;
                refreshCreateSongs();
        }

        function onCreateSong(idx:Int):Void
        {
                createSongIdx = idx;
                createDiffIdx = 0;
                refreshCreateDifficulties(true);
        }

        function onCreateDiff(idx:Int):Void
        {
                createDiffIdx = idx;
                refreshCreateLabels();
        }

        function refreshCreateSongs():Void
        {
                modDropdown.setOptions([for (m in availableMods) m == BASE_FOLDER ? 'JOGO BASE (sem mod)' : m], modIndex);
                createSongs = ensureSongs(createFolder());
                if (createSongIdx >= createSongs.length)
                        createSongIdx = 0;
                songDropdown.setOptions(createSongs.length == 0 ? ['(sem músicas)'] : createSongs, createSongIdx);
                refreshCreateDifficulties(true);
        }

        function refreshCreateDifficulties(resolve:Bool):Void
        {
                var names:Array<String> = Difficulty.defaultList.copy();
                if (createSongs.length > 0)
                {
                        var modDir:String = modDirOf(createFolder());
                        names = diffNames(modDir, createSongs[createSongIdx]);
                        if (resolve)
                                createDiffIdx = resolveDifficulty(modDir, createSongs[createSongIdx], createDiffIdx);
                }
                if (createDiffIdx >= names.length)
                        createDiffIdx = 0;
                diffDropdown.setOptions(names, createDiffIdx);
                refreshCreateLabels();
                requestEstimate();
        }

        function requestEstimate():Void
        {
                if (createSongs.length == 0)
                {
                        estimateText.text = '';
                        return;
                }
                var folder:String = createFolder();
                if (folder == BASE_FOLDER)
                {
                        estimateText.text = 'Mod base: nada para enviar.';
                        return;
                }
                var song:String = createSongs[createSongIdx];
                var songOnly:Bool = sendSongOnly;
                var opt:Bool = optimizeMod;
                var token:Int = ++estimateToken;
                estimateText.text = 'Calculando o tamanho do envio...';
                Thread.create(() ->
                {
                        try
                        {
                                var sel:Array<String> = MpModTransfer.select(folder, song, songOnly, opt);
                                events.add({kind: 'estimate', token: token, count: sel.length, bytes: MpModTransfer.sizeOf(folder, sel), full: MpModTransfer.folderSize(folder)});
                        }
                        catch (e:Dynamic)
                        {
                                events.add({kind: 'estimate', token: token, error: Std.string(e)});
                        }
                });
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

        function toggleSendMode():Void
        {
                sendSongOnly = !sendSongOnly;
                refreshCreateLabels();
                requestEstimate();
        }

        function toggleOptimize():Void
        {
                optimizeMod = !optimizeMod;
                refreshCreateLabels();
                requestEstimate();
        }

        function cycleSpeed():Void
        {
                if (speedAuto)
                {
                        speedAuto = false;
                        speedIndex = 0;
                }
                else
                {
                        speedIndex++;
                        if (speedIndex >= NOTE_SPEEDS.length)
                        {
                                speedAuto = true;
                                speedIndex = 1;
                        }
                }
                refreshCreateLabels();
        }

        function refreshCreateLabels():Void
        {
                var song:String = createSongs.length == 0 ? 'nenhuma' : createSongs[createSongIdx];
                createSongText.text = 'Música: ' + song + '   ·   Mod: ' + createFolder();
                dieButton.setLabel('MORRER AO ERRAR: ' + yn(dieOnMiss));
                botButton.setLabel('BOTPLAY: ' + yn(botplay));
                sendModeButton.setLabel('ENVIO: ' + (sendSongOnly ? 'SÓ A MÚSICA' : 'MOD COMPLETO'));
                optimizeButton.setLabel('OTIMIZAR: ' + yn(optimizeMod));
                speedButton.setLabel('VELOCIDADE: ' + (speedAuto ? 'AUTO (JSON DA MÚSICA)' : Std.string(NOTE_SPEEDS[speedIndex])));
        }

        function submitCreate():Void
        {
                var folder:String = createFolder();
                if (createSongs.length == 0)
                {
                        setStatus('Escolha um mod com músicas antes de criar o servidor.');
                        return;
                }
                var modDir:String = modDirOf(folder);
                var songName:String = createSongs[createSongIdx];
                var songDifficulty:Int = resolveDifficulty(modDir, songName, createDiffIdx);

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

                var size:Float = 0;
                if (folder != BASE_FOLDER)
                        size = MpModTransfer.sizeOf(folder, MpModTransfer.select(folder, songName, sendSongOnly, optimizeMod));
                if (size > MpModTransfer.MAX_BYTES)
                {
                        setStatus('O envio tem ' + Std.int(size / 1048576) + ' MB (limite ' + Std.int(MpModTransfer.MAX_BYTES / 1048576) + ' MB). Use ENVIO: SÓ A MÚSICA ou OTIMIZAR.');
                        return;
                }
                var speed:Float = speedAuto ? chartSpeed(modDir, songName, songDifficulty) : NOTE_SPEEDS[speedIndex];
                var payload:Dynamic = {
                        name: name,
                        mod: {name: folder, folder: folder, size: size, mode: sendSongOnly ? 'song' : 'full', optimize: optimizeMod},
                        settings: {
                                dieOnMiss: dieOnMiss,
                                botplay: botplay,
                                noteSpeed: speed,
                                password: pw == '' ? null : pw,
                                song: {name: songName, difficulty: songDifficulty}
                        }
                };
                pendingPassword = pw;
                roomFolder = folder;
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
                return modDirOf(Std.string(room.mod.folder));
        }

        function hostSongOnly():Bool
        {
                return room != null && room.mod != null && room.mod.mode == 'song';
        }

        function hostOptimize():Bool
        {
                return room != null && room.mod != null && room.mod.optimize == true;
        }

        function songAvailable(modDir:String, name:String):Bool
        {
                var folder:String = Paths.formatToSongPath(name);
                var d:String = modDir == '' ? Paths.getSharedPath('data/' + folder) : Paths.mods(modDir + '/data/' + folder);
                return FileSystem.exists(d) && FileSystem.isDirectory(d);
        }

        function songsOfMod(modDir:String):Array<String>
        {
                var out:Array<String> = [];
                var previous:String = Mods.currentModDirectory;
                Mods.currentModDirectory = modDir;
                scannedMods.set(modDir, true);
                try
                {
                        WeekData.reloadWeekFiles(false);
                        for (w in WeekData.weeksList)
                        {
                                var leWeek:WeekData = WeekData.weeksLoaded.get(w);
                                if (leWeek == null || leWeek.songs == null)
                                        continue;
                                if (leWeek.folder != modDir)
                                        continue;
                                for (song in leWeek.songs)
                                {
                                        var n:String = Std.string(song[0]);
                                        if (n != '' && out.indexOf(n) == -1 && songAvailable(modDir, n))
                                        {
                                                out.push(n);
                                                diffsBySong.set(diffsKey(modDir, n), parseDiffs(leWeek.difficulties));
                                        }
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

        function diffsKey(modDir:String, song:String):String
        {
                return modDir + '|' + Paths.formatToSongPath(song);
        }

        function parseDiffs(raw:String):Array<String>
        {
                var out:Array<String> = [];
                if (raw != null)
                {
                        for (part in raw.split(','))
                        {
                                var t:String = StringTools.trim(part);
                                if (t != '')
                                        out.push(t);
                        }
                }
                return out.length == 0 ? Difficulty.defaultList.copy() : out;
        }

        function diffNames(modDir:String, song:String):Array<String>
        {
                var key:String = diffsKey(modDir, song);
                if (!diffsBySong.exists(key) && !scannedMods.exists(modDir))
                        songsOfMod(modDir);
                var d:Array<String> = diffsBySong.get(key);
                return d == null ? Difficulty.defaultList.copy() : d.copy();
        }

        function diffFile(folder:String, name:String):String
        {
                var n:String = Paths.formatToSongPath(name);
                return n == Paths.formatToSongPath(Difficulty.getDefault()) ? folder : folder + '-' + n;
        }

        function chartExists(modDir:String, folder:String, file:String):Bool
        {
                if (modDir != '' && FileSystem.exists(Paths.mods(modDir + '/data/' + folder + '/' + file + '.json')))
                        return true;
                return FileSystem.exists(Paths.getSharedPath('data/' + folder + '/' + file + '.json'));
        }

        function resolveDifficulty(modDir:String, songName:String, preferred:Int):Int
        {
                var folder:String = Paths.formatToSongPath(songName);
                var names:Array<String> = diffNames(modDir, songName);
                if (preferred < 0 || preferred >= names.length)
                        preferred = 0;
                for (i in 0...names.length)
                {
                        var idx:Int = (preferred + i) % names.length;
                        if (chartExists(modDir, folder, diffFile(folder, names[idx])))
                                return idx;
                }
                if (chartExists(modDir, folder, folder))
                {
                        for (i in 0...names.length)
                                if (Paths.formatToSongPath(names[i]) == Paths.formatToSongPath(Difficulty.getDefault()))
                                        return i;
                }
                return preferred;
        }

        function chartFileFor(modDir:String, songName:String, preferred:Int):String
        {
                var folder:String = Paths.formatToSongPath(songName);
                var names:Array<String> = diffNames(modDir, songName);
                var file:String = diffFile(folder, names[resolveDifficulty(modDir, songName, preferred)]);
                if (chartExists(modDir, folder, file))
                        return file;
                if (chartExists(modDir, folder, folder))
                        return folder;
                return file;
        }

        function chartSpeed(modDir:String, songName:String, diff:Int):Float
        {
                var v:Float = 1;
                var previous:String = Mods.currentModDirectory;
                try
                {
                        Mods.currentModDirectory = modDir;
                        var s:Dynamic = Song.loadFromJson(chartFileFor(modDir, songName, diff), Paths.formatToSongPath(songName));
                        if (s != null && s.speed != null)
                                v = Std.parseFloat(Std.string(s.speed));
                }
                catch (e:Dynamic)
                {
                }
                Mods.currentModDirectory = previous;
                if (Math.isNaN(v) || v <= 0)
                        v = 1;
                return Math.round(Math.max(0.5, Math.min(10, v)) * 100) / 100;
        }

        function loadRoomSong():Dynamic
        {
                var s:Dynamic = room.settings.song;
                var folder:String = Paths.formatToSongPath(Std.string(s.name));
                try
                {
                        var modDir:String = roomModDirectory();
                        Mods.currentModDirectory = modDir;
                        return Song.loadFromJson(chartFileFor(modDir, Std.string(s.name), Std.int(s.difficulty)), folder);
                }
                catch (e:Dynamic)
                {
                        NFLog.exception('match', e);
                        setStatus('Não consegui carregar a música: ' + Std.string(e));
                        return null;
                }
        }

        function requestMod():Void
        {
                if (socket == null || room == null || isHost || modReady || requested)
                        return;
                requested = true;
                requestWait = 0;
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

        function onRoomSong(idx:Int):Void
        {
                if (idx >= 0 && idx < songsList.length)
                        setRoomSong(songsList[idx], 0);
        }

        function onRoomDiff(idx:Int):Void
        {
                if (room != null)
                        setRoomSong(Std.string(room.settings.song.name), idx);
        }

        function setRoomSong(name:String, diffIdx:Int):Void
        {
                if (!isHost || socket == null || room == null)
                        return;
                var modDir:String = roomModDirectory();
                var d:Int = resolveDifficulty(modDir, name, diffIdx);
                var payload:Dynamic = {type: 'setSong', name: name, difficulty: d};
                if (speedAuto)
                        Reflect.setField(payload, 'noteSpeed', chartSpeed(modDir, name, d));
                socket.send(payload);
                setStatus('Trocando a música para ' + name + '...');
        }

        function canStart():Bool
        {
                if (!isHost || room == null)
                        return false;
                for (mm in cast(room.members, Array<Dynamic>))
                {
                        if (mm.username == room.host)
                                continue;
                        if (mm.downloading == true || mm.ready != true)
                                return false;
                        if (roomFolder != BASE_FOLDER && room.manifest == true && mm.modOk != true)
                                return false;
                }
                return true;
        }

        function startMatch():Void
        {
                if (socket == null || !isHost || room == null)
                        return;
                if (!canStart())
                {
                        setStatus('Aguarde: alguém não está pronto, está baixando o mod ou o mod não confere.');
                        return;
                }
                var song:Dynamic = loadRoomSong();
                if (song == null)
                        return;
                var notes:Array<Dynamic> = MpMatch.buildChart(song);
                if (notes.length == 0)
                {
                        setStatus('Essa música não tem notas.');
                        return;
                }
                var chartEvents:Array<Dynamic> = [];
                try
                {
                        if (song.events != null)
                                chartEvents = cast song.events;
                }
                catch (e:Dynamic)
                {
                }
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
                chatInput.text = '';
                if (text.charAt(0) == '/')
                {
                        runCommand(text);
                        return;
                }
                socket.send({type: 'chat', text: text});
        }

        function sayLines(lines:Array<String>):Void
        {
                for (l in lines)
                        chatLines.push(l);
                refreshRoomUI();
        }

        function runCommand(text:String):Void
        {
                var parts:Array<String> = text.substr(1).split(' ');
                var cmd:String = parts.shift().toLowerCase();
                var arg:String = StringTools.trim(parts.join(' '));
                if (!isHost)
                {
                        sayLines(['* Só o host usa comandos.']);
                        return;
                }
                var modDir:String = roomModDirectory();
                var current:String = Std.string(room.settings.song.name);
                switch (cmd)
                {
                        case 'ajuda' | 'help':
                                sayLines([
                                        '/musica <nome>  /dificuldade <nome|n>  /velocidade <n|auto>',
                                        '/morrer  /bot  /kick <jogador>  /ban <jogador>  /desbanir',
                                        '/encerrar  /config'
                                ]);
                        case 'config':
                                sayLines([
                                        '* Música: ' + current + '  Vel: ' + room.settings.noteSpeed + '  Morrer: ' + yn(room.settings.dieOnMiss)
                                        + '  Bot: ' + yn(room.settings.botplay) + '  Bloqueados: ' + room.bans
                                ]);
                        case 'musica' | 'song':
                                var found:String = null;
                                for (n in songsList)
                                        if (n.toLowerCase().indexOf(arg.toLowerCase()) != -1)
                                        {
                                                found = n;
                                                break;
                                        }
                                if (found == null || arg == '')
                                        sayLines(['* Música não encontrada.']);
                                else
                                        setRoomSong(found, 0);
                        case 'dificuldade' | 'diff':
                                var names:Array<String> = diffNames(modDir, current);
                                var idx:Int = -1;
                                var asNum:Null<Int> = Std.parseInt(arg);
                                if (asNum != null && asNum >= 1 && asNum <= names.length)
                                        idx = asNum - 1;
                                else
                                        for (i in 0...names.length)
                                                if (names[i].toLowerCase() == arg.toLowerCase())
                                                        idx = i;
                                if (idx == -1)
                                        sayLines(['* Opções: ' + names.join(', ')]);
                                else
                                        setRoomSong(current, idx);
                        case 'velocidade' | 'speed':
                                if (arg.toLowerCase() == 'auto')
                                {
                                        speedAuto = true;
                                        socket.send({type: 'setSettings', noteSpeed: chartSpeed(modDir, current, Std.int(room.settings.song.difficulty))});
                                }
                                else
                                {
                                        var v:Float = Std.parseFloat(arg);
                                        if (Math.isNaN(v) || v < 0.5 || v > 10)
                                                sayLines(['* Use um valor entre 0.5 e 10, ou auto.']);
                                        else
                                        {
                                                speedAuto = false;
                                                socket.send({type: 'setSettings', noteSpeed: v});
                                        }
                                }
                        case 'morrer':
                                socket.send({type: 'setSettings', dieOnMiss: room.settings.dieOnMiss != true});
                        case 'bot':
                                socket.send({type: 'setSettings', botplay: room.settings.botplay != true});
                        case 'kick' | 'expulsar':
                                socket.send({type: 'kick', username: arg, ban: false});
                        case 'ban' | 'banir':
                                socket.send({type: 'kick', username: arg, ban: true});
                        case 'desbanir':
                                socket.send({type: 'clearBans'});
                        case 'encerrar':
                                socket.send({type: 'end'});
                        default:
                                sayLines(['* Comando desconhecido. Use /ajuda.']);
                }
        }

        function backToRoom():Void
        {
                MpMatch.lastResults = [];
                if (room == null)
                {
                        showMode('lobby');
                        return;
                }
                showMode('room');
                setStatus('De volta ao servidor.');
        }

        function leaveRoom():Void
        {
                if (mode != 'room' && mode != 'results')
                        return;
                stopIncoming();
                chunkQueue = [];
                plans = new Map();
                planning = new Map();
                if (socket != null)
                        socket.send({type: 'leave'});
                closeSocket();
                room = null;
                isHost = false;
                pendingStart = false;
                waitingResults = false;
                MpMatch.lastResults = [];
                setProgress(0, '');
                showMode('lobby');
                setStatus('Você saiu da sala.');
                refreshRooms();
        }

        function resetRoomState():Void
        {
                stopIncoming();
                hostPlan = null;
                pendingSend = [];
                chunkQueue = [];
                inFlight = new Map();
                sentTo = new Map();
                sendTotalTo = new Map();
                needsOf = new Map();
                plans = new Map();
                planning = new Map();
                requested = false;
                manifestKnown = false;
                checking = false;
                recheck = false;
                publishing = false;
                republish = false;
                publishedKey = '';
                waitingResults = false;
        }

        function enterRoom(r:Dynamic):Void
        {
                room = r;
                isHost = r.host == MpApi.username;
                myReady = false;
                chatLines = [];
                chatText.text = '';
                roomFolder = r.mod.folder;
                resetRoomState();
                statusKnown = false;
                awaitingStatus = false;
                statusWait = 0;
                joinWait = 0;
                scannedMods.remove(roomModDirectory());
                modReady = isHost || roomFolder == BASE_FOLDER;
                if (isHost)
                        scanSongs();
                showMode('room');
                setProgress(modReady ? 1 : 0, modReady ? 'Mod pronto.' : 'Aguardando o host publicar o mod...');
                setStatus(modReady ? 'Pronto para jogar. Digite /ajuda no chat para configurar a sala.' : 'Aguardando o host publicar o mod...');
                if (isHost)
                        publishManifest();
        }

        function resumeRoom():Void
        {
                socket = MpMatch.socket;
                room = MpMatch.room;
                MpMatch.returning = false;
                MpMatch.active = false;
                if (socket == null || room == null)
                {
                        closeSocket();
                        room = null;
                        showMode('lobby');
                        setStatus('A sala não existe mais.');
                        return;
                }
                isHost = MpMatch.isHost;
                roomFolder = room.mod.folder;
                modReady = true;
                myReady = false;
                chatLines = [];
                if (isHost)
                        scanSongs();
                showMode('room');
                setProgress(1, 'Mod pronto.');
                if (MpMatch.lastResults.length > 0)
                        showResults();
                else
                {
                        waitingResults = true;
                        setStatus('Você terminou! Aguardando o oponente terminar...');
                }
        }

        function describeResult(r:Dynamic, name:String):String
        {
                if (r == null)
                        return '[ ' + name.toUpperCase() + ' ]\n\nSem dados.';
                var c:Dynamic = r.counts;
                var acc:Float = Math.round(Std.parseFloat(Std.string(r.accuracy)) * 10000) / 100;
                return '[ ' + Std.string(r.username).toUpperCase() + ' ]\n\nPTS: ' + r.score + '\nPRECISÃO: ' + acc + '%\nCOMBO MÁX: ' + r.maxCombo
                        + '\nERROS: ' + c.miss + '\n\nSICK: ' + c.sick + '  GOOD: ' + c.good + '\nBAD: ' + c.bad + '  SHIT: ' + c.shit;
        }

        function showResults():Void
        {
                var local:Dynamic = null;
                var other:Dynamic = null;
                for (r in MpMatch.lastResults)
                {
                        if (r.username == MpApi.username)
                                local = r;
                        else if (other == null)
                                other = r;
                }
                resultLocal.text = describeResult(local, MpApi.username);
                resultRemote.text = describeResult(other, MpMatch.opponentName == '' ? 'OPONENTE' : MpMatch.opponentName);
                if (local != null && other != null)
                        resultTitle.text = local.score > other.score ? 'VOCÊ VENCEU!' : (local.score < other.score ? 'VOCÊ PERDEU' : 'EMPATE');
                else
                        resultTitle.text = 'RESULTADO DA PARTIDA';
                showMode('results');
                setStatus('Partida encerrada.');
        }

        function refreshRoomUI():Void
        {
                if (room == null)
                        return;
                var s:Dynamic = room.settings;
                var members:Array<Dynamic> = cast room.members;
                for (mm in members)
                {
                        if (mm.username == MpApi.username)
                        {
                                myReady = mm.ready == true;
                                if (!isHost && roomFolder != BASE_FOLDER)
                                        modReady = mm.modOk == true;
                        }
                }
                var names:Array<String> = diffNames(roomModDirectory(), Std.string(s.song.name));
                var di:Int = Std.int(s.song.difficulty);
                roomTitle.text = Std.string(room.name);
                roomInfo.text = 'Mod: ' + room.mod.name + (hostSongOnly() ? ' (só a música)' : '') + '   ·   Morrer ao errar: ' + yn(s.dieOnMiss)
                        + '   ·   Botplay: ' + yn(s.botplay) + '   ·   Velocidade: ' + s.noteSpeed;
                songTitle.text = Std.string(s.song.name) + '   (dificuldade ' + (di < names.length ? names[di] : Std.string(di)) + ')';

                var lines:Array<String> = [];
                for (mm in members)
                {
                        var tag:String = mm.username == room.host ? '[HOST] ' : '';
                        var st:String = '  - aguardando';
                        if (mm.downloading == true)
                                st = '  - BAIXANDO MOD';
                        else if (mm.ready == true)
                                st = '  - PRONTO';
                        else if (mm.username != room.host && roomFolder != BASE_FOLDER && room.manifest == true && mm.modOk != true)
                                st = '  - MOD DIFERENTE';
                        lines.push(tag + mm.username + st);
                }
                membersText.text = lines.join('\n');
                chatText.text = chatLines.slice(Std.int(Math.max(0, chatLines.length - 9))).join('\n');

                var showHostUi:Bool = isHost && mode == 'room';
                if (showHostUi && !roomSongDropdown.open && !roomDiffDropdown.open)
                {
                        roomSongDropdown.setOptions(songsList, songsList.indexOf(Std.string(s.song.name)));
                        roomDiffDropdown.setOptions(names, di);
                }
                roomSongDropdown.show(showHostUi);
                roomDiffDropdown.show(showHostUi);

                readyButton.show(!isHost && modReady);
                readyButton.setLabel(myReady ? 'CANCELAR' : 'PRONTO');
                playButton.show(isHost);
                playButton.setEnabled(canStart());
                requestButton.show(!isHost && !modReady && statusKnown && !requested && !downloadingNow() && !checking && !awaitingStatus && roomFolder != BASE_FOLDER);
        }

        function downloadingNow():Bool
        {
                return incomingQueue != null;
        }

        function appendChat(line:String):Void
        {
                chatLines.push(line);
                if (mode == 'room')
                        refreshRoomUI();
        }

        function publishManifest():Void
        {
                if (!isHost || room == null || socket == null || roomFolder == BASE_FOLDER)
                        return;
                if (publishing)
                {
                        republish = true;
                        return;
                }
                publishing = true;
                var folder:String = roomFolder;
                var song:String = Std.string(room.settings.song.name);
                var songOnly:Bool = hostSongOnly();
                var opt:Bool = hostOptimize();
                publishedKey = song;
                Thread.create(() ->
                {
                        try
                        {
                                var entries = MpManifest.build(folder, MpModTransfer.select(folder, song, songOnly, opt));
                                MpManifest.save(folder, entries);
                                events.add({kind: 'hostManifest', parts: MpManifest.parts(entries), count: entries.length});
                        }
                        catch (e:Dynamic)
                        {
                                events.add({kind: 'hostManifest', error: Std.string(e)});
                        }
                });
        }

        function maybeRepublish():Void
        {
                if (!isHost || room == null || roomFolder == BASE_FOLDER)
                        return;
                if ((hostSongOnly() || hostOptimize()) && Std.string(room.settings.song.name) != publishedKey)
                        publishManifest();
        }

        function checkLocalMod():Void
        {
                if (isHost || room == null || socket == null || roomFolder == BASE_FOLDER)
                        return;
                if (checking)
                {
                        recheck = true;
                        return;
                }
                checking = true;
                var folder:String = roomFolder;
                setProgress(0, 'Verificando os arquivos do mod...');
                Thread.create(() ->
                {
                        try
                        {
                                var entries = MpManifest.build(folder, null);
                                MpManifest.save(folder, entries);
                                events.add({kind: 'checked', parts: MpManifest.parts(entries)});
                        }
                        catch (e:Dynamic)
                        {
                                events.add({kind: 'checked', error: Std.string(e)});
                        }
                });
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
                                        setStatus(errorOf(ev.json));

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
                                        setStatus(errorOf(ev.json));

                        case 'estimate':
                                if (ev.token == estimateToken)
                                {
                                        if (ev.error != null)
                                                estimateText.text = 'Falha ao calcular: ' + ev.error;
                                        else
                                                estimateText.text = 'Envio: ' + ev.count + ' arquivos, ' + Std.int(ev.bytes / 1048576) + ' MB  (mod completo: '
                                                        + Std.int(ev.full / 1048576) + ' MB)' + (ev.bytes > MpModTransfer.MAX_BYTES ? '  - GRANDE DEMAIS!' : '');
                                }

                        case 'hostManifest':
                                publishing = false;
                                if (ev.error != null)
                                        setStatus('Falha ao preparar o manifesto: ' + ev.error);
                                else if (socket != null && isHost)
                                {
                                        var mparts:Array<Array<Dynamic>> = ev.parts;
                                        for (i in 0...mparts.length)
                                                socket.send({type: 'manifest', part: i, parts: mparts.length, files: mparts[i]});
                                        setStatus('Manifesto do mod publicado (' + ev.count + ' arquivos).');
                                }
                                if (republish)
                                {
                                        republish = false;
                                        publishManifest();
                                }

                        case 'checked':
                                checking = false;
                                if (ev.error != null)
                                {
                                        awaitingStatus = false;
                                        statusKnown = true;
                                        setStatus('Falha ao verificar o mod: ' + ev.error);
                                }
                                else if (socket != null)
                                {
                                        var cparts:Array<Array<Dynamic>> = ev.parts;
                                        awaitingStatus = true;
                                        statusWait = 0;
                                        for (i in 0...cparts.length)
                                                socket.send({type: 'modCheck', part: i, parts: cparts.length, files: cparts[i]});
                                        setStatus('Verificando o mod com o host...');
                                }
                                if (recheck)
                                {
                                        recheck = false;
                                        checkLocalMod();
                                }

                        case 'plan':
                                var to:String = Std.string(ev.to);
                                planning.remove(to);
                                if (ev.error != null)
                                {
                                        setProgress(0, 'Falha ao preparar o mod.');
                                        setStatus('Falha ao preparar o mod: ' + ev.error);
                                        return;
                                }
                                plans.set(to, ev.data);
                                sendChunks(to);

                        case 'modProgress':
                                var progDone:Float = ev.done;
                                var progTotal:Float = ev.total;
                                var progPct:Int = progTotal > 0 ? Std.int(progDone * 100 / progTotal) : 0;
                                var progText:String = 'Baixando o mod do host (' + ev.stage + ')   ' + progPct + '%   ·   ' + ev.files + '/' + ev.filesTotal + ' arquivos';
                                setProgress(progTotal > 0 ? progDone / progTotal : 0, progText);
                                setStatus(progText);

                        case 'modDone':
                                requested = false;
                                if (socket != null)
                                        socket.send({type: 'modState', downloading: false});
                                if (ev.ok == true)
                                {
                                        statusKnown = false;
                                        awaitingStatus = true;
                                        statusWait = 0;
                                        scannedMods.remove(roomModDirectory());
                                        setProgress(1, 'Mod instalado. Verificando...');
                                        setStatus('Mod instalado. Verificando com o host...');
                                        checkLocalMod();
                                }
                                else
                                {
                                        setProgress(0, 'Download do mod interrompido.');
                                        setStatus('Download do mod interrompido: ' + ev.error);
                                        refreshRoomUI();
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
                                if (mode == 'room' || mode == 'results')
                                {
                                        stopIncoming();
                                        setStatus('Conexão com a sala caiu.');
                                        closeSocket();
                                        room = null;
                                        showMode('lobby');
                                        refreshRooms();
                                }

                        case 'error':
                                if (Std.string(m.message) != 'Jogador não está no servidor.')
                                        setStatus(Std.string(m.message));

                        case 'joinedRoom':
                                enterRoom(m.room);

                        case 'roomState':
                                room = m.room;
                                if (isHost)
                                {
                                        syncSongIndex();
                                        maybeRepublish();
                                }
                                refreshRoomUI();

                        case 'manifestReady':
                                manifestKnown = true;
                                checkLocalMod();

                        case 'modStatus':
                                if (m.pending == true)
                                {
                                        manifestKnown = false;
                                        return;
                                }
                                manifestKnown = true;
                                awaitingStatus = false;
                                statusKnown = true;
                                if (m.ok == true)
                                {
                                        modReady = true;
                                        requested = false;
                                        setProgress(1, 'Mod verificado.');
                                        setStatus('Mod confere com o do host. Clique em PRONTO.');
                                }
                                else
                                {
                                        modReady = false;
                                        var example:String = '';
                                        if (m.sample != null)
                                        {
                                                var sampleList:Array<String> = cast m.sample;
                                                if (sampleList.length > 0)
                                                        example = ' Ex.: ' + sampleList.slice(0, 3).join(', ');
                                        }
                                        setProgress(0, 'Faltam ' + m.missing + ' arquivos e ' + m.changed + ' diferem do host.');
                                        setStatus('Seu mod não confere: faltam ' + m.missing + ' e ' + m.changed + ' diferem.' + example);
                                }
                                refreshRoomUI();

                        case 'modNeeds':
                                if (isHost)
                                {
                                        var who:String = Std.string(m.from);
                                        if (m.ok == true || m.all == true)
                                                needsOf.remove(who);
                                        else
                                                needsOf.set(who, cast m.files);
                                }

                        case 'kicked':
                                stopIncoming();
                                closeSocket();
                                room = null;
                                isHost = false;
                                showMode('lobby');
                                setStatus(Std.string(m.reason));
                                refreshRooms();

                        case 'kickOk':
                                appendChat('* ' + m.username + (m.banned == true ? ' foi banido por IP' : ' foi expulso'));

                        case 'bansCleared':
                                appendChat('* Bloqueios removidos.');

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
                                        plans.remove(requester);
                                        ensurePlan(requester);
                                }

                        case 'playerLeft':
                                appendChat('* ' + m.username + ' saiu');
                                if (isHost)
                                {
                                        var gone:String = Std.string(m.username);
                                        inFlight.remove(gone);
                                        sentTo.remove(gone);
                                        sendTotalTo.remove(gone);
                                        plans.remove(gone);
                                        planning.remove(gone);
                                        needsOf.remove(gone);
                                        chunkQueue = chunkQueue.filter(function(c) return c.to != gone);
                                }

                        case 'modAck':
                                if (isHost && m.index != null && inFlight.exists(m.from))
                                {
                                        var left:Int = inFlight.get(m.from) - 1;
                                        inFlight.set(m.from, left < 0 ? 0 : left);
                                }
                                if (isHost && m.index != null && sendTotalTo.exists(m.from))
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
                                startAtLocal = socket != null ? socket.localTime(Std.parseFloat(Std.string(m.startAt))) : startAt;
                                MpMatch.matchId = Std.string(m.matchId);
                                pendingStart = true;
                                MpMatch.scriptPaths = [];
                                MpScripts.fetch(function(paths:Array<String>) events.add({kind: 'scripts', paths: paths}));
                                setStatus('Partida começando...');

                        case 'playerLoaded':
                                if (room != null && m.username != null)
                                        appendChat('* ' + m.username + ' carregou a partida');

                        case 'allLoaded':
                                setStatus('Todos carregaram! Iniciando...');

                        case 'end':
                                MpMatch.lastResults = cast m.results;
                                waitingResults = false;
                                showResults();

                        case 'roomClosed':
                                stopIncoming();
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

        function ensurePlan(to:String):Void
        {
                if (room == null || roomFolder == null || roomFolder == BASE_FOLDER || planning.exists(to))
                        return;
                planning.set(to, true);
                var folder:String = roomFolder;
                var song:String = Std.string(room.settings.song.name);
                var songOnly:Bool = hostSongOnly();
                var opt:Bool = hostOptimize();
                var needs:Array<String> = needsOf.get(to);
                setProgress(0, 'Preparando o mod para ' + to + '...');
                setStatus('Preparando o mod para ' + to + '...');
                Thread.create(() ->
                {
                        try
                        {
                                var sel:Array<String> = MpModTransfer.select(folder, song, songOnly, opt);
                                if (needs != null)
                                {
                                        var set:Map<String, Bool> = new Map();
                                        for (n in needs)
                                                set.set(n, true);
                                        sel = sel.filter(function(r:String):Bool return set.exists(r));
                                }
                                events.add({kind: 'plan', to: to, data: MpModTransfer.plan(folder, sel)});
                        }
                        catch (e:Dynamic)
                        {
                                events.add({kind: 'plan', to: to, error: Std.string(e)});
                        }
                });
        }

        function sendChunks(to:String):Void
        {
                var plan:ModPlan = plans.get(to);
                if (socket == null || plan == null)
                        return;
                for (c in chunkQueue)
                        if (c.to == to)
                                return;
                var total:Int = plan.chunks;
                sentTo.set(to, 0);
                sendTotalTo.set(to, total);
                for (i in 0...total)
                        chunkQueue.push({to: to, index: i, total: total});
                setProgress(0, 'Enviando o mod para ' + to + ' (' + plan.files + ' arquivos)...');
                setStatus('Enviando o mod para ' + to + ' (' + plan.files + ' arquivos, ' + total + ' pedaços)...');
        }

        function pumpChunks():Void
        {
                if (chunkQueue.length == 0 || socket == null)
                        return;
                var i:Int = 0;
                while (i < chunkQueue.length)
                {
                        var c = chunkQueue[i];
                        var plan:ModPlan = plans.get(c.to);
                        if (plan == null)
                        {
                                chunkQueue.splice(i, 1);
                                continue;
                        }
                        var flying:Int = inFlight.exists(c.to) ? inFlight.get(c.to) : 0;
                        if (flying >= CHUNK_WINDOW)
                        {
                                i++;
                                continue;
                        }
                        chunkQueue.splice(i, 1);
                        inFlight.set(c.to, flying + 1);
                        socket.send({type: 'modChunk', to: c.to, index: c.index, total: c.total, data: MpModTransfer.chunkBase64(plan, c.index)});
                        return;
                }
        }

        function receiveChunk(m:Dynamic):Void
        {
                var index:Int = m.index;
                var total:Int = m.total;
                if (socket != null)
                        socket.send({type: 'modAck', index: index});
                if (room == null || roomFolder == null || isHost)
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
                if (socket != null)
                        socket.send({type: 'modState', downloading: true});
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
                var modDir:String = roomModDirectory();
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
                        Mods.currentModDirectory = modDir;
                        MpMatch.songDifficulty = resolveDifficulty(modDir, MpMatch.songName, MpMatch.songDifficulty);
                        Difficulty.copyFrom(diffNames(modDir, MpMatch.songName));
                        var chartFile:String = chartFileFor(modDir, MpMatch.songName, MpMatch.songDifficulty);
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
                stopIncoming();
                if (!MpMatch.active && !MpMatch.returning)
                        closeSocket();
                super.destroy();
        }
}
