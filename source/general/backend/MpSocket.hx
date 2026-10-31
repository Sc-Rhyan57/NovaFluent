package general.backend;

import flixel.FlxG;
import haxe.Json;
import haxe.Timer;
import sys.thread.Deque;

class MpSocket
{
	static final PING_EVERY:Float = 20;
	static final TIMEOUT_AFTER:Float = 45;
	static final BLOCKED_RETRY:Float = 0.05;

	public static var current:MpSocket = null;
	static var hooked:Bool = false;

	public var inbox:Deque<Dynamic> = new Deque();
	public var open:Bool = false;
	public var rtt:Float = -1;

	var ws:Dynamic;
	var outbox:Array<String> = [];
	var backlog:Array<{text:String, at:Float}> = [];
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
			NFLog.info('net', 'ws aberto');
			open = true;
			lastSeen = Timer.stamp();
			var pending:Array<String> = outbox;
			outbox = [];
			for (text in pending)
				enqueue(text);
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
				logIncoming(msg);
				inbox.add(msg);
			}
			catch (e:Dynamic)
			{
				NFLog.warn('net', 'mensagem inválida recebida (' + text.length + ' caracteres): ' + Std.string(e));
			}
		};

		ws.onerror = function(e:Dynamic)
		{
			if (isBlocked(e))
			{
				NFLog.warn('net', 'buffer de envio cheio (Blocked), a sala continua');
				return;
			}
			NFLog.warn('net', 'erro no websocket: ' + Std.string(e));
			inbox.add({type: '_error', message: Std.string(e)});
		};

		ws.onclose = function(?e:Dynamic)
		{
			NFLog.info('net', 'ws fechado');
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
		var kind:String = Std.string(Reflect.field(obj, 'type'));
		if (kind != 'modChunk' && kind != 'modAck' && kind != 'ping')
			NFLog.info('net', '> ' + kind);
		if (!open)
		{
			outbox.push(text);
			return;
		}
		enqueue(text);
	}

	function enqueue(text:String):Void
	{
		if (backlog.length > 0)
		{
			backlog.push({text: text, at: 0});
			return;
		}
		rawSend(text);
	}

	static function isBlocked(e:Dynamic):Bool
	{
		return Std.string(e).indexOf('Blocked') != -1;
	}

	function flushBacklog():Void
	{
		if (!open || ws == null || backlog.length == 0)
			return;
		if (backlog[0].at > Timer.stamp())
			return;
		var item = backlog[0];
		try
		{
			ws.send(item.text);
			backlog.shift();
		}
		catch (e:Dynamic)
		{
			if (isBlocked(e))
			{
				item.at = Timer.stamp() + BLOCKED_RETRY;
				return;
			}
			backlog.shift();
			NFLog.warn('net', 'falha ao reenviar: ' + Std.string(e));
			inbox.add({type: '_error', message: Std.string(e)});
		}
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
			if (isBlocked(e))
			{
				backlog.push({text: text, at: Timer.stamp() + BLOCKED_RETRY});
				return;
			}
			NFLog.warn('net', 'falha ao enviar: ' + Std.string(e));
			inbox.add({type: '_error', message: Std.string(e)});
		}
	}

	function logIncoming(msg:Dynamic):Void
	{
		if (msg == null)
			return;
		var kind:String = Std.string(msg.type);
		if (kind == 'pong' || kind == 'modChunk' || kind == 'judge')
			return;
		if (kind == 'error')
			NFLog.warn('net', '< error: ' + Std.string(msg.message));
		else
			NFLog.info('net', '< ' + kind);
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
		try
		{
			s.pump();
			s.flushBacklog();
			s.heartbeat();
		}
		catch (e:Dynamic)
		{
			s.inbox.add({type: '_error', message: Std.string(e)});
		}
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
		NFLog.warn('net', 'sem resposta do servidor por ' + TIMEOUT_AFTER + 's - desconectando');
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
		backlog = [];
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
