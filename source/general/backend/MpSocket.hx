package general.backend;

import flixel.FlxG;
import haxe.Json;
import haxe.Timer;
import sys.thread.Deque;

class MpSocket
{
	// Intervalo do ping de keepalive (segundos). O servidor responde com pong.
	static final PING_EVERY:Float = 20;

	// Socket atual. Só existe um por vez; o hook de frame usa essa referência.
	public static var current:MpSocket = null;
	static var hooked:Bool = false;

	public var inbox:Deque<Dynamic> = new Deque();
	public var open:Bool = false;

	var ws:Dynamic;
	var outbox:Array<String> = [];
	var closedSent:Bool = false;
	var lastPing:Float = 0;

	public function new(url:String)
	{
		current = this;
		lastPing = Timer.stamp();
		if (!hooked)
		{
			hooked = true;
			// Lê o socket e mantém o ping em qualquer tela (menu, pausa, loading, partida).
			FlxG.signals.postUpdate.add(frame);
		}

		ws = new hx.ws.WebSocket(url);

		ws.onopen = function()
		{
			open = true;
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
			try
			{
				inbox.add(Json.parse(text));
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
		if (!open)
			return;
		var now:Float = Timer.stamp();
		if (now - lastPing < PING_EVERY)
			return;
		lastPing = now;
		rawSend('{"type":"ping"}');
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
