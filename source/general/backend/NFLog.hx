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
	static final RECENT_LINES:Int = 120;
	static final NATIVE_LINES:Int = 40;

	static var out:FileOutput = null;
	static var lock:Mutex = new Mutex();
	static var ready:Bool = false;
	static var sessionPath:String = null;
	static var recent:Array<String> = [];
	static var lastNative:Float = 0;
	static var lockPath:String = null;
	static var previousCrash:String = null;

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
			lockPath = Path.join([dir, 'running.lock']);
			if (FileSystem.exists(lockPath))
				previousCrash = summarizePrevious(dir, lockPath);
			File.saveContent(lockPath, sessionPath);
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
			Sys.println(line)
		catch (_:Dynamic) {}

		lock.acquire();
		recent.push(line);
		if (recent.length > RECENT_LINES)
			recent.shift();
		if (ready && out != null)
		{
			try
			{
				out.writeString(line + '\n');
				out.flush();
			}
			catch (_:Dynamic) {}
		}
		lock.release();

		if (level == 'ERROR' || Date.now().getTime() - lastNative > 1000)
			syncNative();
	}

	public static function syncNative():Void
	{
		lastNative = Date.now().getTime();
		#if (cpp && (windows || android))
		lock.acquire();
		var from:Int = Std.int(Math.max(0, recent.length - NATIVE_LINES));
		var text:String = recent.slice(from).join('\n');
		lock.release();
		general.backend.NativeCrashHandler.setHaxeRuntimeSnapshot('[nflog]\n' + text);
		#end
	}

	public static function takePreviousCrash():String
	{
		var text:String = previousCrash;
		previousCrash = null;
		return text;
	}

	public static function closeClean():Void
	{
		write('INFO', 'shutdown', 'encerramento normal');
		try
		{
			if (lockPath != null && FileSystem.exists(lockPath))
				FileSystem.deleteFile(lockPath);
		}
		catch (_:Dynamic) {}
	}

	static function summarizePrevious(dir:String, lockFile:String):String
	{
		var previous:String = '?';
		var lines:Array<String> = [];
		try
		{
			previous = StringTools.trim(File.getContent(lockFile));
			lines = File.getContent(previous).split('\n');
		}
		catch (_:Dynamic) {}

		var problems:Array<String> = [];
		for (l in lines)
			if (l.indexOf(' ERROR ') != -1 || l.indexOf(' WARN ') != -1)
				problems.push(l);
		var recentProblems:Array<String> = problems.slice(Std.int(Math.max(0, problems.length - 12)));
		var recentLines:Array<String> = lines.slice(Std.int(Math.max(0, lines.length - 25)));
		var reportPath:String = newestCrashReport(dir);

		var text:String = 'A sessão anterior não foi encerrada normalmente.\n'
			+ 'Log: ' + previous + '\n'
			+ 'Relatório nativo: ' + (reportPath == null ? 'nenhum salvo' : reportPath) + '\n\n'
			+ '== Erros e avisos da sessão ==\n' + recentProblems.join('\n') + '\n\n'
			+ '== Últimas ações antes da queda ==\n' + recentLines.join('\n') + '\n';
		try
			File.saveContent(Path.join([dir, 'ultimo-crash.txt']), text)
		catch (_:Dynamic) {}
		return text;
	}

	static function newestCrashReport(dir:String):String
	{
		var best:String = null;
		var bestTime:Float = -1;
		try
		{
			var roots:Array<String> = [Path.directory(dir), Sys.getCwd()];
			for (root in roots)
				for (sub in ['crash', 'haxe-crash'])
				{
					var folder:String = Path.join([root, sub]);
					if (!FileSystem.exists(folder) || !FileSystem.isDirectory(folder))
						continue;
					for (n in FileSystem.readDirectory(folder))
					{
						var p:String = Path.join([folder, n]);
						var t:Float = FileSystem.stat(p).mtime.getTime();
						if (t > bestTime)
						{
							bestTime = t;
							best = p;
						}
					}
				}
		}
		catch (_:Dynamic) {}
		return best;
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
