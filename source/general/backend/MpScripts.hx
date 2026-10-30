package general.backend;

import sys.FileSystem;
import sys.io.File;

class MpScripts
{
	static final NAME_RE:EReg = ~/^[A-Za-z0-9_-]{1,60}\.lua$/;

	public static function fetch(onDone:Array<String>->Void):Void
	{
		MpApi.getScripts(function(s:Int, j:Dynamic)
		{
			var paths:Array<String> = [];
			if (s == 200 && j.success == true)
			{
				try
				{
					paths = write(cast j.scripts);
				}
				catch (e:Dynamic)
				{
					paths = [];
				}
			}
			onDone(paths);
		});
	}

	static function write(list:Array<Dynamic>):Array<String>
	{
		var dir:String = OnlineMods.cacheRoot('match_scripts/');
		mkdirs(dir);

		for (old in FileSystem.readDirectory(dir))
		{
			if (NAME_RE.match(old))
				FileSystem.deleteFile(dir + old);
		}

		var out:Array<String> = [];
		if (list == null)
			return out;

		for (entry in list)
		{
			var name:String = Std.string(Reflect.field(entry, 'name'));
			var source:String = Std.string(Reflect.field(entry, 'source'));
			if (!NAME_RE.match(name) || source == 'null')
				continue;

			var path:String = dir + name;
			File.saveContent(path, source);
			out.push(path);
		}
		return out;
	}

	static function mkdirs(dir:String):Void
	{
		var parts:Array<String> = dir.split('/');
		var current:String = '';
		for (part in parts)
		{
			if (part == '')
				continue;
			current += part + '/';
			if (!FileSystem.exists(current))
				FileSystem.createDirectory(current);
		}
	}
}
