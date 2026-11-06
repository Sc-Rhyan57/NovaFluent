package games.backend;

import haxe.io.Path;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

class ScriptFileSanitizer
{
	public static inline final TRAILING_BAD_CHARS:String = '. ';

	public static function sanitizeFileName(name:String):String
	{
		if (name == null) return null;
		var end:Int = name.length;
		while (end > 0)
		{
			var c:String = name.charAt(end - 1);
			if (TRAILING_BAD_CHARS.indexOf(c) >= 0)
				end--;
			else
				break;
		}
		return name.substring(0, end);
	}

	public static function sanitizePath(path:String):String
	{
		if (path == null) return null;
		var dir:String = Path.directory(path);
		var file:String = Path.withoutDirectory(path);
		var clean:String = sanitizeFileName(file);
		if (dir == null || dir.length == 0 || dir == '.')
			return clean;
		return dir + '/' + clean;
	}

	public static function hasBadTrailingChar(nameOrPath:String):Bool
	{
		if (nameOrPath == null || nameOrPath.length == 0) return false;
		var file:String = Path.withoutDirectory(nameOrPath);
		if (file.length == 0) return false;
		var last:String = file.charAt(file.length - 1);
		return TRAILING_BAD_CHARS.indexOf(last) >= 0;
	}

	#if sys
	public static function findAndRenameBadFiles(dir:String, recursive:Bool = true):Array<{from:String, to:String, conflict:Bool}>
	{
		if (dir == null || dir.length == 0 || !FileSystem.exists(dir) || FileSystem.isDirectory(dir) == false)
			return null;

		var results:Array<{from:String, to:String, conflict:Bool}> = [];
		var entries:Array<String> = FileSystem.readDirectory(dir);

		for (entry in entries)
		{
			var full:String = dir + '/' + entry;

			if (FileSystem.isDirectory(full))
			{
				if (recursive)
				{
					var sub = findAndRenameBadFiles(full, recursive);
					if (sub != null) results = results.concat(sub);
				}
				continue;
			}

			if (!hasBadTrailingChar(entry)) continue;

			var cleanName:String = sanitizeFileName(entry);
			if (cleanName.length == 0) continue;
			var cleanFull:String = dir + '/' + cleanName;

			if (FileSystem.exists(cleanFull))
			{
				results.push({from: full, to: cleanFull, conflict: true});
				continue;
			}

			FileSystem.rename(full, cleanFull);
			results.push({from: full, to: cleanFull, conflict: false});
		}

		return results;
	}

	public static function safeGetContent(rawPath:String):String
	{
		if (rawPath == null) return null;

		if (FileSystem.exists(rawPath) && !FileSystem.isDirectory(rawPath))
			return File.getContent(rawPath);

		var clean:String = sanitizePath(rawPath);
		if (clean != rawPath)
		{
			if (FileSystem.exists(clean) && !FileSystem.isDirectory(clean))
				return File.getContent(clean);
		}

		return null;
	}

	public static function resolveScriptPath(rawPath:String):String
	{
		if (rawPath == null) return null;
		if (FileSystem.exists(rawPath) && !FileSystem.isDirectory(rawPath))
			return rawPath;
		var clean:String = sanitizePath(rawPath);
		if (clean != rawPath && FileSystem.exists(clean) && !FileSystem.isDirectory(clean))
			return clean;
		return null;
	}
	#end
}
