package general.backend;

import haxe.CallStack;
import haxe.CallStack.StackItem;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileOutput;
import sys.thread.Mutex;

class NFLog
{
	public static final KEEP_SESSIONS:Int = 10;

	static var out:FileOutput = null;
	static var lock:Mutex = new Mutex();
	static var ready:Bool = false;
	static var sessionPath:String = null;

	public static function init(commit:String):Void
	{
		if (ready)
			return;
		try
		{
			var dir:String = directory();
			if (!FileSystem.exists(dir))
				FileSystem.createDirectory(dir);
			prune(dir);
			sessionPath = Path.join([dir, 'session-' + stamp(true).split(':').join('') + '.log']);
			out = File.append(sessionPath, false);
			ready = true;
		}
		catch (e:Dynamic)
		{
			Sys.println('nflog:init_failed ' + Std.string(e));
		}
		write('INFO', 'boot', 'commit=' + commit + ' os=' + safe(function() return Sys.systemName()) + ' cwd=' + safe(function() return Sys.getCwd()) + ' arquivo=' + (sessionPath == null ? 'nenhum' : sessionPath));
	}

	public static function currentPath():String
	{
		return sessionPath;
	}

	public static function tail(lines:Int):String
	{
		if (sessionPath == null)
			return 'sem arquivo de log';
		try
		{
			var all:Array<String> = File.getContent(sessionPath).split('\n');
			var from:Int = Std.int(Math.max(0, all.length - lines));
			return all.slice(from).join('\n');
		}
		catch (e:Dynamic)
		{
			return 'falha ao ler o log: ' + Std.string(e);
		}
	}

	public static function info(tag:String, msg:String):Void
	{
		write('INFO', tag, msg);
	}

	public static function warn(tag:String, msg:String):Void
	{
		write('WARN', tag, msg);
	}

	public static function error(tag:String, msg:String):Void
	{
		write('ERROR', tag, msg);
	}

	public static function exception(tag:String, e:Dynamic, ?stack:Array<StackItem>):Void
	{
		var trail:String = stack == null ? '' : '\n' + safe(function() return CallStack.toString(stack));
		write('ERROR', tag, Std.string(e) + trail);
	}

	public static function write(level:String, tag:String, msg:String):Void
	{
		var line:String = '[' + stamp(false) + '] ' + level + ' ' + tag + ' ' + msg;
		try
		{
			Sys.println(line);
		}
		catch (_:Dynamic)
		{
		}
		if (!ready || out == null)
			return;
		lock.acquire();
		try
		{
			out.writeString(line + '\n');
			out.flush();
		}
		catch (_:Dynamic)
		{
		}
		lock.release();
	}

	static function directory():String
	{
		var root:String = Sys.getEnv('NOVAFLARE_DIAGNOSTIC_DIR');
		return root != null && root.length > 0 ? Path.join([root, 'logs']) : Path.join([Sys.getCwd(), 'logs']);
	}

	static function prune(dir:String):Void
	{
		var names:Array<String> = [];
		for (n in FileSystem.readDirectory(dir))
			if (StringTools.startsWith(n, 'session-') && StringTools.endsWith(n, '.log'))
				names.push(n);
		names.sort(function(a:String, b:String):Int return a < b ? -1 : (a > b ? 1 : 0));
		while (names.length >= KEEP_SESSIONS)
		{
			try
			{
				FileSystem.deleteFile(Path.join([dir, names.shift()]));
			}
			catch (_:Dynamic)
			{
				names.shift();
			}
		}
	}

	static function pad(n:Int):String
	{
		return n < 10 ? '0' + n : '' + n;
	}

	static function stamp(full:Bool):String
	{
		var d:Date = Date.now();
		var time:String = pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds());
		if (!full)
			return time;
		return d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate()) + '-' + time;
	}

	static function safe(f:Void->String):String
	{
		try
		{
			return f();
		}
		catch (_:Dynamic)
		{
			return '?';
		}
	}
}
