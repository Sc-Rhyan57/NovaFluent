package general.backend;

import flixel.FlxG;
import flixel.text.FlxText;

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

	static var stats:Map<String, Dynamic> = new Map();
	static var hud:FlxText = null;

	public static function noteIdOf(strumTime:Float, noteData:Int):Int
	{
		return Std.int(strumTime) * 8 + (noteData % 8);
	}

	public static function judgementOf(ratingMod:Float):String
	{
		if (ratingMod >= 1)
			return 'sick';
		if (ratingMod >= 0.75)
			return 'good';
		if (ratingMod >= 0.5)
			return 'bad';
		if (ratingMod > 0)
			return 'shit';
		return 'miss';
	}

	public static function begin(r:Dynamic, me:String):Void
	{
		room = r;
		localName = me;
		isHost = r.host == me;

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
		lastResults = [];
		stats = new Map();
		refreshHud();
	}

	public static function reportNote(strumTime:Float, noteData:Int, ratingMod:Float, diffMs:Float):Void
	{
		if (!active || socket == null)
			return;
		socket.send({
			type: 'judge',
			noteId: noteIdOf(strumTime, noteData),
			judgement: judgementOf(ratingMod),
			time: diffMs
		});
	}

	public static function reportMiss(strumTime:Float, noteData:Int):Void
	{
		if (!active || socket == null)
			return;
		socket.send({
			type: 'judge',
			noteId: noteIdOf(strumTime, noteData),
			judgement: 'miss',
			time: 0
		});
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
		if (isHost && socket != null)
			socket.send({type: 'end'});
	}

	public static function reset():Void
	{
		active = false;
		returning = false;
		dead = false;
		stats = new Map();
		room = null;
		isHost = false;
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

	static function handle(m:Dynamic):Void
	{
		switch (m.type)
		{
			case 'judge':
				stats.set(Std.string(m.username), m.stats);
				refreshHud();

			case 'dead':
				if (m.username == localName)
					dead = true;
				refreshHud();

			case 'end':
				lastResults = cast m.results;
				active = false;
				returning = true;

			case 'roomState':
				room = m.room;

			case 'roomClosed':
				active = false;
				returning = false;
				socket = null;
				room = null;
		}
	}
}
