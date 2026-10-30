package general.backend;

import flixel.FlxG;
import haxe.Json;
import haxe.Timer;
import sys.thread.Deque;

class MpSocket
{
	static final PING_EVERY:Float = 20;
	static final TIMEOUT_AFTER:Float = 45;

	public static var current:MpSocket = null;
	static var hooked:Bool = false;

	public var inbox:Deque<Dynamic> = new Deque();
	public var open:Bool = false;
	public var rtt:Float = -1;

	var ws:Dynamic;
	var outbox:Array<String> = [];
	var closedSent:Bool = false;
	var lastPing:Float = 0;
	var lastSeen:Float = 0;

	public function new(url:String)
	{
		current = this;
		lastPing = Timer.stamp();
		lastSeen = lastPing;
		if (!hooked)
		{
			hooked = true;
			FlxG.signals.postUpdate.add(frame);
		}

		ws = new hx.ws.WebSocket(url);

		ws.onopen = function()
		{
			open = true;
			lastSeen = Timer.stamp();
			var pending:Array<String> = outbox;
			outbox = [];
			for (text in pending)
				rawSend(text);
			inbox.add({type: '_open'});
		};

		ws.onmessage = function(m:Dynamic)
		{
			var text:String = null;
			if (Std.isOfType(m, String))
				text = cast m;
			else if (Type.enumConstructor(m) == 'StrMessage')
				text = Std.string(Type.enumParameters(m)[0]);
			if (text == null)
				return;
			lastSeen = Timer.stamp();
			try
			{
				var msg:Dynamic = Json.parse(text);
				if (msg != null && msg.type == 'pong')
					measure(msg);
				inbox.add(msg);
			}
			catch (e:Dynamic)
			{
			}
		};

		ws.onerror = function(e:Dynamic)
		{
			inbox.add({type: '_error', message: Std.string(e)});
		};

		ws.onclose = function(?e:Dynamic)
		{
			open = false;
			if (closedSent)
				return;
			closedSent = true;
			inbox.add({type: '_close'});
		};
	}

	public function send(obj:Dynamic):Void
	{
		if (ws == null)
			return;
		var text:String = Json.stringify(obj);
		if (!open)
		{
			outbox.push(text);
			return;
		}
		rawSend(text);
	}

	function rawSend(text:String):Void
	{
		if (ws == null)
			return;
		try
		{
			ws.send(text);
		}
		catch (e:Dynamic)
		{
			inbox.add({type: '_error', message: Std.string(e)});
		}
	}

	function measure(msg:Dynamic):Void
	{
		if (msg.t == null)
			return;
		var sent:Float = msg.t;
		rtt = Timer.stamp() * 1000 - sent;
	}

	static function frame():Void
	{
		var s:MpSocket = current;
		if (s == null)
			return;
		s.pump();
		s.heartbeat();
	}

	function heartbeat():Void
	{
		if (ws == null)
			return;
		var now:Float = Timer.stamp();
		if (now - lastSeen > TIMEOUT_AFTER)
		{
			dropDead();
			return;
		}
		if (!open)
			return;
		if (now - lastPing < PING_EVERY)
			return;
		lastPing = now;
		rawSend(Json.stringify({type: 'ping', t: now * 1000}));
	}

	function dropDead():Void
	{
		if (closedSent)
			return;
		inbox.add({type: '_error', message: 'timeout'});
		inbox.add({type: '_close'});
		close();
	}

	public function pump():Void
	{
		if (ws == null)
			return;
		var fn:Dynamic = Reflect.field(ws, 'process');
		if (fn == null)
			return;
		try
		{
			Reflect.callMethod(ws, fn, []);
		}
		catch (e:Dynamic)
		{
			inbox.add({type: '_error', message: Std.string(e)});
		}
	}

	public function close():Void
	{
		if (current == this)
			current = null;
		open = false;
		outbox = [];
		closedSent = true;
		var target:Dynamic = ws;
		ws = null;
		if (target == null)
			return;
		var fn:Dynamic = Reflect.field(target, 'close');
		if (fn != null)
		{
			try
			{
				Reflect.callMethod(target, fn, []);
			}
			catch (e:Dynamic)
			{
			}
		}
	}
}
