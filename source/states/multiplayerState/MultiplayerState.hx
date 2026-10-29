package states.multiplayerState;

import flixel.FlxBasic;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.ui.FlxInputText;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import games.PlayState;
import games.backend.Highscore;
import games.backend.Song;
import games.backend.StageData;
import general.backend.MpApi;
import general.backend.MpMatch;
import general.backend.MpMatch.PendingSong;
import general.backend.MpModTransfer;
import general.backend.MpSocket;
import general.backend.MusicBeatState;
import general.backend.Mods;
import general.backend.Paths;
import states.freeplayState.FreeplayState;
import states.loadingState.LoadingState;
import sys.FileSystem;
import sys.thread.Deque;
import sys.thread.Thread;

typedef RoomSlot =
{
	var bg:FlxSprite;
	var text:FlxText;
	var join:FlxButton;
};

class MultiplayerState extends MusicBeatState
{
	static inline final PX:Int = 40;
	static inline final SLOTS:Int = 6;
	static inline final BASE_FOLDER:String = '_base';
	static final NOTE_SPEEDS:Array<Float> = [0.5, 1, 1.5, 2, 2.5, 3, 4, 5];
	static final USER_RE = ~/^[A-Za-z0-9]{3,20}$/;
	static final PASS_RE = ~/^\d{6}$/;

	var events:Deque<Dynamic> = new Deque();
	var mode:String = 'auth';
	var groups:Map<String, Array<FlxBasic>> = new Map();
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
	var songText:FlxText;
	var dieButton:FlxButton;
	var botButton:FlxButton;
	var speedButton:FlxButton;
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
	var roomText:FlxText;
	var membersText:FlxText;
	var chatText:FlxText;
	var chatInput:FlxInputText;
	var chatLines:Array<String> = [];
	var readyButton:FlxButton;
	var playButton:FlxButton;

	var hostPayload:String = null;
	var encoding:Bool = false;
	var pendingSend:Array<String> = [];
	var incoming:Array<String> = null;
	var incomingCount:Int = 0;

	var pendingStart:Bool = false;
	var startAt:Float = 0;

	override function create():Void
	{
		super.create();

		add(new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF0E1216));

		status = new FlxText(PX, FlxG.height - 44, FlxG.width - PX * 2, '', 18);
		add(status);

		buildAuth();
		buildLobby();
		buildCreate();
		buildRoom();

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
		return track(group, new FlxText(x, y, w, s, size));
	}

	function button(group:String, x:Float, y:Float, s:String, cb:Void->Void):FlxButton
	{
		return track(group, new FlxButton(x, y, s, cb));
	}

	function input(group:String, x:Float, y:Float, w:Int, s:String, password:Bool):FlxInputText
	{
		var field:FlxInputText = track(group, new FlxInputText(x, y, w, s, 18));
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

		if (m == 'lobby')
		{
			meText.text = MpApi.username == null ? '' : 'Logado como ' + MpApi.username;
			applySlots();
		}
		if (m == 'create')
			refreshCreateLabels();
		if (m == 'room')
			refreshRoomUI();
	}

	function buildAuth():Void
	{
		label('auth', PX, 110, 600, 'MULTIPLAYER', 32);
		userInput = input('auth', PX, 170, 360, '', false);
		passInput = input('auth', PX, 220, 360, '', true);
		button('auth', PX, 280, 'ENTRAR', submitLogin);
		button('auth', PX, 330, 'CRIAR CONTA', submitRegister);
		button('auth', PX, 380, 'VOLTAR', goBack);
	}

	function buildLobby():Void
	{
		meText = label('lobby', PX, 110, 380, '', 20);
		button('lobby', PX, 160, 'SAIR DA CONTA', logout);
		button('lobby', PX, 210, 'CRIAR SERVIDOR', function() showMode('create'));
		button('lobby', PX, 260, 'VOLTAR', goBack);

		var listX:Int = Std.int(FlxG.width * 0.45);
		var panelW:Int = Std.int(FlxG.width * 0.5);
		label('lobby', listX, 110, 500, 'SERVIDORES', 22);

		for (i in 0...SLOTS)
		{
			var idx:Int = i;
			var bg:FlxSprite = track('lobby', new FlxSprite(listX, 150 + i * 62).makeGraphic(panelW, 52, 0xFF1C232B));
			var text:FlxText = label('lobby', listX + 12, 164 + i * 62, panelW - 150, '', 16);
			var join:FlxButton = button('lobby', listX + panelW - 120, 158 + i * 62, 'ENTRAR', function() joinFromSlot(idx));
			slots.push({bg: bg, text: text, join: join});
		}

		joinPassInput = input('lobby', listX, 150 + SLOTS * 62 + 20, 260, '', true);
	}

	function buildCreate():Void
	{
		label('create', PX, 110, 600, 'NOVO SERVIDOR', 28);
		songText = label('create', PX, 150, FlxG.width - PX * 2, '', 18);
		nameInput = input('create', PX, 200, 360, '', false);
		dieButton = button('create', PX, 250, '', toggleDie);
		botButton = button('create', PX, 300, '', toggleBot);
		speedButton = button('create', PX, 350, '', cycleSpeed);
		createPassInput = input('create', PX, 400, 260, '', false);
		button('create', PX, 460, 'CRIAR', submitCreate);
		button('create', PX + 170, 460, 'VOLTAR', function() showMode('lobby'));
	}

	function buildRoom():Void
	{
		roomText = label('room', PX, 100, FlxG.width - PX * 2, '', 20);
		membersText = label('room', PX, 150, Std.int(FlxG.width * 0.4), '', 18);
		chatText = label('room', Std.int(FlxG.width * 0.45), 150, Std.int(FlxG.width * 0.5), '', 16);
		chatInput = input('room', Std.int(FlxG.width * 0.45), FlxG.height - 160, 300, '', false);
		button('room', Std.int(FlxG.width * 0.45) + 310, FlxG.height - 160, 'ENVIAR', sendChat);
		readyButton = button('room', PX, FlxG.height - 110, 'PRONTO', toggleReady);
		playButton = button('room', PX + 170, FlxG.height - 110, 'PLAY', startMatch);
		button('room', PX + 340, FlxG.height - 110, 'SAIR DA SALA', leaveRoom);
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		var ev:Dynamic = events.pop(false);
		while (ev != null)
		{
			handleEvent(ev);
			ev = events.pop(false);
		}

		var s:MpSocket = socket;
		if (s != null)
		{
			s.pump();
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

	function errorOf(json:Dynamic):String
	{
		var e:Dynamic = Reflect.field(json, 'error');
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
		MpApi.login(u, passInput.text, function(s:Int, j:Dynamic) events.add({kind: 'login', status: s, json: j}));
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
		MpApi.register(u, passInput.text, function(s:Int, j:Dynamic) events.add({kind: 'register', status: s, json: j}));
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
			slots[i].text.visible = show;
			slots[i].text.active = show;
			slots[i].join.visible = show;
			slots[i].join.active = show;
		}
	}

	function fillSlots(list:Array<Dynamic>):Void
	{
		listRooms = list;
		roomCount = Std.int(Math.min(list.length, SLOTS));
		for (i in 0...roomCount)
		{
			var r:Dynamic = list[i];
			var lock:String = r.hasPassword == true ? '  [SENHA]' : '';
			slots[i].text.text = r.name + '  ·  ' + r.host + '  ·  ' + r.players + '/' + r.max + '  ·  ' + r.settings.song.name + lock;
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
		var p:PendingSong = MpMatch.pendingSong;
		if (p == null)
			return null;
		return p.mod == null || p.mod == '' ? BASE_FOLDER : p.mod;
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
		var p:PendingSong = MpMatch.pendingSong;
		if (p == null)
			songText.text = 'Abra o MULTI pelo Freeplay, depois de escolher a música.';
		else
			songText.text = 'MÚSICA: ' + p.name + ' (dificuldade ' + p.difficulty + ')   ·   MOD: ' + createFolder();
		dieButton.label.text = 'MORRER AO ERRAR: ' + (dieOnMiss ? 'SIM' : 'NÃO');
		botButton.label.text = 'BOTPLAY: ' + (botplay ? 'SIM' : 'NÃO');
		speedButton.label.text = 'VELOCIDADE: ' + NOTE_SPEEDS[speedIndex];
	}

	function submitCreate():Void
	{
		var p:PendingSong = MpMatch.pendingSong;
		var folder:String = createFolder();
		if (p == null || folder == null)
		{
			setStatus('Escolha uma música no Freeplay antes de criar o servidor.');
			return;
		}

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
		var payload:Dynamic = {
			name: name,
			mod: {name: folder, folder: folder, size: size},
			settings: {
				dieOnMiss: dieOnMiss,
				botplay: botplay,
				noteSpeed: NOTE_SPEEDS[speedIndex],
				password: pw == '' ? null : pw,
				song: {name: p.name, difficulty: p.difficulty}
			}
		};

		pendingPassword = pw;
		roomFolder = folder;
		hostPayload = null;
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

	function startMatch():Void
	{
		if (socket == null || !isHost)
			return;
		socket.send({type: 'start'});
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
		incoming = null;
		incomingCount = 0;
		hostPayload = null;
		pendingSend = [];
		modReady = isHost || roomFolder == BASE_FOLDER || FileSystem.exists(Paths.mods(roomFolder));
		showMode('room');
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
		showMode('room');
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
		roomText.text = room.name + '  ·  música: ' + s.song.name + ' (dif ' + s.song.difficulty + ')  ·  mod: ' + room.mod.name
			+ '  ·  morrer ao errar: ' + (s.dieOnMiss == true ? 'sim' : 'não') + '  ·  botplay: ' + (s.botplay == true ? 'sim' : 'não')
			+ '  ·  velocidade: ' + s.noteSpeed;

		var lines:Array<String> = [];
		for (m in cast(room.members, Array<Dynamic>))
			lines.push((m.username == room.host ? '[HOST] ' : '') + m.username + (m.ready == true ? '  (pronto)' : ''));
		membersText.text = 'Jogadores:\n' + lines.join('\n');

		chatText.text = chatLines.slice(Std.int(Math.max(0, chatLines.length - 10))).join('\n');

		readyButton.visible = !isHost && modReady;
		readyButton.active = !isHost && modReady;
		readyButton.label.text = myReady ? 'CANCELAR' : 'PRONTO';

		playButton.visible = isHost;
		playButton.active = isHost;
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
				if ((ev.status == 200 || ev.status == 201) && ev.json.ok == true)
				{
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
				if (ev.status == 200 && ev.json.ok == true)
					fillSlots(cast ev.json.rooms);
				else
					setStatus(errorOf(ev.json));

			case 'create':
				if (ev.status == 201 && ev.json.ok == true)
				{
					pendingJoin = {roomId: ev.json.roomId, password: pendingPassword};
					connectSocket();
				}
				else
				{
					setStatus(errorOf(ev.json));
				}

			case 'payload':
				encoding = false;
				if (ev.error != null)
				{
					setStatus('Falha ao preparar o mod: ' + ev.error);
					return;
				}
				hostPayload = ev.data;
				flushPending();

			case 'modDone':
				if (ev.ok == true)
				{
					modReady = true;
					setStatus('Mod instalado. Clique em PRONTO.');
					refreshRoomUI();
				}
				else
				{
					setStatus('Falha ao instalar o mod: ' + ev.error);
				}
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
				refreshRoomUI();

			case 'playerJoined':
				appendChat('* ' + m.username + ' entrou');
				if (isHost && m.username != MpApi.username && roomFolder != BASE_FOLDER)
				{
					pendingSend.push(m.username);
					ensurePayload();
				}

			case 'playerLeft':
				appendChat('* ' + m.username + ' saiu');

			case 'chat':
				appendChat(m.from + ': ' + m.text);

			case 'modChunk':
				receiveChunk(m);

			case 'start':
				startAt = m.startAt;
				pendingStart = true;
				setStatus('Partida começando...');

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
		if (hostPayload != null)
		{
			flushPending();
			return;
		}
		if (encoding || roomFolder == null || roomFolder == BASE_FOLDER)
			return;

		encoding = true;
		var folder:String = roomFolder;
		setStatus('Preparando o mod para enviar...');
		Thread.create(() ->
		{
			try
			{
				events.add({kind: 'payload', data: MpModTransfer.encode(folder)});
			}
			catch (e:Dynamic)
			{
				events.add({kind: 'payload', error: Std.string(e)});
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
		if (socket == null || hostPayload == null)
			return;

		var size:Int = MpModTransfer.CHUNK_CHARS;
		var total:Int = Std.int(Math.max(1, Math.ceil(hostPayload.length / size)));
		for (i in 0...total)
		{
			socket.send({
				type: 'modChunk',
				to: to,
				index: i,
				total: total,
				data: hostPayload.substr(i * size, size)
			});
		}
		setStatus('Mod enviado para ' + to + ' (' + total + ' pedaços).');
	}

	function receiveChunk(m:Dynamic):Void
	{
		if (modReady || roomFolder == null)
			return;

		var total:Int = m.total;
		var idx:Int = m.index;
		if (incoming == null || incoming.length != total)
		{
			incoming = [for (i in 0...total) (null : String)];
			incomingCount = 0;
		}

		if (incoming[idx] == null)
			incomingCount++;
		incoming[idx] = m.data;

		var pct:Int = Std.int(incomingCount * 100 / total);
		setStatus('Recebendo o mod: ' + pct + '% (' + incomingCount + '/' + total + ' pedaços)');

		if (incomingCount == total)
		{
			var joined:String = incoming.join('');
			var folder:String = roomFolder;
			incoming = null;
			incomingCount = 0;
			setStatus('Instalando o mod...');
			Thread.create(() ->
			{
				try
				{
					MpModTransfer.decodeInto(joined, folder);
					events.add({kind: 'modDone', ok: true});
				}
				catch (e:Dynamic)
				{
					events.add({kind: 'modDone', ok: false, error: Std.string(e)});
				}
			});
		}
	}

	function launchMatch():Void
	{
		if (room == null)
			return;

		MpMatch.begin(room, MpApi.username);
		MpMatch.socket = socket;

		var songFolder:String = Paths.formatToSongPath(MpMatch.songName);
		try
		{
			Mods.currentModDirectory = MpMatch.modFolder;
			var chart:String = Highscore.formatSong(songFolder, MpMatch.songDifficulty);
			PlayState.SONG = Song.loadFromJson(chart, songFolder);
			PlayState.SONG.speed = MpMatch.noteSpeed;
			StageData.loadDirectory(PlayState.SONG);
			PlayState.isStoryMode = false;
			PlayState.storyDifficulty = MpMatch.songDifficulty;
		}
		catch (e:Dynamic)
		{
			MpMatch.reset();
			setStatus('Não consegui carregar a música: ' + Std.string(e));
			return;
		}

		LoadingState.prepareToSong();
		LoadingState.loadAndSwitchState(new PlayState());
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
		if (!MpMatch.active && !MpMatch.returning)
			closeSocket();
		super.destroy();
	}
}
