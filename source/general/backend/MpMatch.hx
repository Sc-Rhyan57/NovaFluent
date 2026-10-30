package general.backend;

import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import games.objects.Note;

typedef PendingSong =
{
	var name:String;
	var difficulty:Int;
	var mod:String;
};

class MpMatch
{
	public static var pendingSong:PendingSong = null;
	public static var socket:MpSocket = null;
	public static var room:Dynamic = null;
	public static var isHost:Bool = false;
	public static var localName:String = '';
	public static var opponentName:String = '';
	public static var active:Bool = false;
	public static var returning:Bool = false;
	public static var dieOnMiss:Bool = false;
	public static var botplay:Bool = false;
	public static var noteSpeed:Float = 1;
	public static var songName:String = '';
	public static var songDifficulty:Int = 0;
	public static var modFolder:String = '';
	public static var dead:Bool = false;
	public static var lastResults:Array<Dynamic> = [];
	public static var scriptPaths:Array<String> = [];
	public static var remotePaused:Bool = false;
	public static var remoteNotes:Map<String, Note> = new Map();
	public static var matchId:String = null;
	public static var aborted:Bool = false;
	public static var abortReason:String = '';
	public static var pendingStatus:String = null;

	static var chartEntries:Array<Dynamic> = [];
	static var chartPool:Map<String, Array<String>> = new Map();
	static var remoteHits:Array<String> = [];
	static var stats:Map<String, Dynamic> = new Map();
	static var hud:FlxText = null;
	static var tagLocal:FlxText = null;
	static var tagRemote:FlxText = null;
	static var overlayBg:FlxSprite = null;
	static var overlayText:FlxText = null;

	public static function keyOf(time:Float, lane:Int, type:String):String
	{
		return Std.int(time) + '|' + lane + '|' + type;
	}

	public static function typeOf(raw:Dynamic):String
	{
		return raw == null ? '' : Std.string(raw);
	}

	public static function isSustain(rawLength:Dynamic):Bool
	{
		return Std.parseFloat(Std.string(rawLength)) > 0;
	}

	public static function storeChart(entries:Array<Dynamic>):Void
	{
		chartEntries = entries == null ? [] : entries;
	}

	public static function takeId(key:String):String
	{
		var ids:Array<String> = chartPool.get(key);
		if (ids == null || ids.length == 0)
			return null;
		return ids.shift();
	}

	static function buildPool():Void
	{
		chartPool = new Map();
		for (e in chartEntries)
		{
			var key:String = keyOf(e.time, e.lane, Std.string(e.type));
			var list:Array<String> = chartPool.get(key);
			if (list == null)
			{
				list = [];
				chartPool.set(key, list);
			}
			list.push(Std.string(e.id));
		}
	}

	public static function buildChart(song:Dynamic):Array<Dynamic>
	{
		var mania:Int = song.mania == null ? 3 : Std.int(song.mania);
		var keys:Int = mania + 1;
		var bpm:Float = Std.parseFloat(Std.string(song.bpm));
		if (Math.isNaN(bpm) || bpm <= 0)
			bpm = 100;
		var stepCrochet:Float = ((60 / bpm) * 1000) / 4;
		var out:Array<Dynamic> = [];
		var sections:Array<Dynamic> = cast song.notes;
		if (sections == null)
			return out;

		for (section in sections)
		{
			if (section == null || section.sectionNotes == null)
				continue;
			var notes:Array<Dynamic> = cast section.sectionNotes;
			for (n in notes)
			{
				var time:Float = n[0];
				var lane:Int = Std.int(n[1]) % keys;
				var type:String = typeOf(n[3]);
				out.push({time: Std.int(time), lane: lane, type: type});

				if (!isSustain(n[2]))
					continue;
				var susLength:Float = Std.parseFloat(Std.string(n[2])) / stepCrochet;
				var floorSus:Int = Math.floor(susLength) - ClientPrefs.data.fixLNL;
				if (floorSus > 0)
				{
					for (susNote in 0...floorSus + 1)
						out.push({time: Std.int(time + (stepCrochet * susNote)), lane: lane, type: 'sustain'});
				}
			}
		}
		return out;
	}

	public static function resolveOpponent(r:Dynamic, me:String):String
	{
		var members:Array<Dynamic> = cast r.members;
		if (members == null)
			return '';
		for (m in members)
		{
			if (m.username != me)
				return Std.string(m.username);
		}
		return '';
	}

	public static function begin(r:Dynamic, me:String):Void
	{
		room = r;
		localName = me;
		isHost = r.host == me;
		opponentName = resolveOpponent(r, me);

		var s:Dynamic = r.settings;
		dieOnMiss = s.dieOnMiss == true;
		botplay = s.botplay == true;
		noteSpeed = Std.parseFloat(Std.string(s.noteSpeed));
		if (Math.isNaN(noteSpeed) || noteSpeed <= 0)
			noteSpeed = 1;
		songName = Std.string(s.song.name);
		songDifficulty = Std.int(s.song.difficulty);
		modFolder = r.mod.folder == '_base' ? '' : Std.string(r.mod.folder);

		active = true;
		returning = false;
		dead = false;
		remotePaused = false;
		aborted = false;
		abortReason = '';
		lastResults = [];
		stats = new Map();
		remoteHits = [];
		remoteNotes = new Map();
		buildPool();
		refreshHud();
	}

	public static function registerRemoteNote(id:String, note:Note):Void
	{
		remoteNotes.set(id, note);
	}

	public static function takeRemoteHits():Array<String>
	{
		var out:Array<String> = remoteHits;
		remoteHits = [];
		return out;
	}

	public static function reportHit(note:Note):Void
	{
		sendNote('hit', note);
	}

	public static function reportMiss(note:Note):Void
	{
		sendNote('miss', note);
	}

	static function sendNote(type:String, note:Note):Void
	{
		if (!active || socket == null || note == null || note.mpId == null || note.mpReported)
			return;
		note.mpReported = true;
		socket.send({
			type: type,
			matchId: matchId,
			noteId: note.mpId,
			songMs: Math.round(Conductor.songPosition)
		});
	}

	public static function sendPause():Void
	{
		if (active && isHost && socket != null)
			socket.send({type: 'pause'});
	}

	public static function sendResume():Void
	{
		if (active && isHost && socket != null)
			socket.send({type: 'resume'});
	}

	public static function createOverlay(cam:FlxCamera):Array<FlxBasic>
	{
		overlayBg = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xB0000000);
		overlayText = new FlxText(0, FlxG.height * 0.45, 0, 'PARTIDA PAUSADA PELO HOST', 32);
		overlayText.x = (FlxG.width - overlayText.width) / 2;
		overlayText.color = FlxColor.WHITE;
		overlayBg.cameras = [cam];
		overlayText.cameras = [cam];
		overlayBg.scrollFactor.set();
		overlayText.scrollFactor.set();
		overlayBg.visible = false;
		overlayText.visible = false;
		return [overlayBg, overlayText];
	}

	public static function updateOverlay():Void
	{
		var show:Bool = active && !isHost && remotePaused;
		if (overlayBg != null)
			overlayBg.visible = show;
		if (overlayText != null)
			overlayText.visible = show;
	}

	public static function createNameTags():Array<FlxText>
	{
		tagLocal = new FlxText(0, 0, 0, '', 18);
		tagRemote = new FlxText(0, 0, 0, '', 18);
		tagLocal.color = 0xFF7CFFB2;
		tagRemote.color = 0xFFFF9BD6;
		tagLocal.scrollFactor.set();
		tagRemote.scrollFactor.set();
		return [tagLocal, tagRemote];
	}

	public static function placeNameTags(player:Array<FlxSprite>, opponent:Array<FlxSprite>):Void
	{
		if (tagLocal == null || tagRemote == null)
			return;
		tagLocal.text = '[ ' + localName + ' ]';
		tagRemote.text = '[ ' + (opponentName == '' ? 'ESPERANDO' : opponentName) + ' ]';
		placeTag(tagLocal, player);
		placeTag(tagRemote, opponent);
	}

	static function placeTag(tag:FlxText, strums:Array<FlxSprite>):Void
	{
		if (strums == null || strums.length == 0)
			return;
		var first:FlxSprite = strums[0];
		var last:FlxSprite = strums[strums.length - 1];
		var centerX:Float = (first.x + last.x + last.width) / 2;
		tag.x = centerX - tag.width / 2;
		tag.y = first.y - tag.height - 6;
	}

	public static function tick():Void
	{
		var s:MpSocket = socket;
		if (s == null)
			return;
		var m:Dynamic = s.inbox.pop(false);
		while (m != null)
		{
			handle(m);
			m = s.inbox.pop(false);
		}
	}

	public static function finish():Void
	{
		active = false;
		returning = true;
		remotePaused = false;
		if (isHost && socket != null)
			socket.send({type: 'end'});
	}

	public static function exit():Void
	{
		if (socket != null)
			socket.send(isHost ? {type: 'abort'} : {type: 'leave'});
		pendingStatus = isHost ? 'Você encerrou a partida e a sala foi fechada.' : 'Você saiu da partida.';
		reset();
	}

	public static function reset():Void
	{
		active = false;
		returning = false;
		dead = false;
		remotePaused = false;
		stats = new Map();
		remoteHits = [];
		remoteNotes = new Map();
		scriptPaths = [];
		chartEntries = [];
		chartPool = new Map();
		room = null;
		isHost = false;
		matchId = null;
		aborted = false;
		abortReason = '';
		if (socket != null)
		{
			socket.close();
			socket = null;
		}
		refreshHud();
	}

	public static function createHud():FlxText
	{
		hud = new FlxText(0, 2, FlxG.width, '', 16);
		refreshHud();
		return hud;
	}

	public static function refreshHud():Void
	{
		if (hud == null)
			return;
		var parts:Array<String> = [];
		for (name in stats.keys())
		{
			var st:Dynamic = stats.get(name);
			var acc:Float = Math.round(Reflect.field(st, 'accuracy') * 10000) / 100;
			var mark:String = Reflect.field(st, 'dead') == true ? ' [MORTO]' : '';
			parts.push(name + ': ' + Reflect.field(st, 'score') + ' (' + acc + '%)' + mark);
		}
		hud.text = parts.join('   |   ');
	}

	static function abortWith(reason:String):Void
	{
		if (!active && !returning)
			return;
		aborted = true;
		abortReason = reason;
		remotePaused = false;
		socket = null;
	}

	static function handle(m:Dynamic):Void
	{
		switch (m.type)
		{
			case 'judge':
				var who:String = Std.string(m.username);
				stats.set(who, m.stats);
				if (who != localName && Std.string(m.judgement) != 'miss')
					remoteHits.push(Std.string(m.noteId));
				refreshHud();

			case 'dead':
				if (m.username == localName)
					dead = true;
				refreshHud();

			case 'paused':
				remotePaused = Std.string(m.by) != localName;

			case 'resumed':
				remotePaused = false;

			case 'end':
				lastResults = cast m.results;
				active = false;
				returning = true;
				remotePaused = false;

			case 'roomState':
				room = m.room;
				opponentName = resolveOpponent(m.room, localName);

			case 'roomClosed':
				abortWith(Std.string(m.reason));
				active = false;
				returning = false;
				remotePaused = false;
				room = null;

			case '_close':
				abortWith('A conexão com o servidor caiu.');
		}
	}
}
