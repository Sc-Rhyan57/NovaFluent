package general.backend;

import haxe.Json;
import sys.thread.Deque;

class MpSocket
{
	public var inbox:Deque<Dynamic> = new Deque();
	public var open:Bool = false;

	var ws:Dynamic;
	var outbox:Array<String> = [];
	var closedSent:Bool = false;

	public function new(url:String)
	{
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
