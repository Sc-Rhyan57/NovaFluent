package general.backend;

import haxe.Json;
import sys.thread.Deque;

class MpSocket
{
	public var inbox:Deque<Dynamic> = new Deque();
	public var open:Bool = false;

	var ws:Dynamic;

	public function new(url:String)
	{
		ws = new hx.ws.WebSocket(url);

		ws.onopen = function()
		{
			open = true;
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
			inbox.add({type: '_close'});
		};
	}

	public function send(obj:Dynamic):Void
	{
		if (ws == null)
			return;
		ws.send(Json.stringify(obj));
	}

	public function pump():Void
	{
		var fn:Dynamic = Reflect.field(ws, 'process');
		if (fn != null)
			Reflect.callMethod(ws, fn, []);
	}

	public function close():Void
	{
		open = false;
		var fn:Dynamic = Reflect.field(ws, 'close');
		if (fn != null)
			Reflect.callMethod(ws, fn, []);
		ws = null;
	}
}
