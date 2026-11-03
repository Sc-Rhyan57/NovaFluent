package general.backend;

import haxe.io.Bytes;
import haxe.io.Error;
import hx.ws.State;
import hx.ws.WebSocket;
import sys.thread.Mutex;

class MpWebSocket extends WebSocket
{
	var sendQueue:Array<Bytes>;
	var sendOffset:Int;
	var queued:Int;
	var sendLock:Mutex;

	public function new(url:String)
	{
		super(url, false);
		sendQueue = [];
		sendOffset = 0;
		queued = 0;
		sendLock = new Mutex();
		open();
	}

	@:keep
	public function getQueuedBytes():Int
	{
		return queued;
	}

	private override function writeBytes(data:Bytes):Void
	{
		if (sendLock == null)
		{
			super.writeBytes(data);
			return;
		}
		sendLock.acquire();
		sendQueue.push(data);
		queued += data.length;
		sendLock.release();
	}

	private override function process():Void
	{
		drain();
		super.process();
		drain();
	}

	function drain():Void
	{
		if (sendLock == null)
			return;
		var failure:Dynamic = null;
		sendLock.acquire();
		if (state == State.Closed)
		{
			sendQueue = [];
			sendOffset = 0;
			queued = 0;
			sendLock.release();
			return;
		}
		try
		{
			while (sendQueue.length > 0)
			{
				var head:Bytes = sendQueue[0];
				var written:Int = 0;
				try
				{
					written = _socket.output.writeBytes(head, sendOffset, head.length - sendOffset);
				}
				catch (e:Dynamic)
				{
					if (isBlockedError(e))
						break;
					throw e;
				}
				if (written <= 0)
					break;
				sendOffset += written;
				queued -= written;
				if (sendOffset >= head.length)
				{
					sendQueue.shift();
					sendOffset = 0;
				}
			}
		}
		catch (e:Dynamic)
		{
			failure = e;
			sendQueue = [];
			sendOffset = 0;
			queued = 0;
		}
		sendLock.release();
		if (failure != null && onerror != null)
			onerror(Std.string(failure));
	}

	static function isBlockedError(e:Dynamic):Bool
	{
		if (Std.isOfType(e, String))
			return cast(e, String) == 'Blocking';
		return Std.isOfType(e, Error) && Type.enumEq(e, Error.Blocked);
	}
}
