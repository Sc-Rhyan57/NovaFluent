package games.backend;

import haxe.io.Path;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * ScriptFileSanitizer
 * ----------------------------------------------------------------------------------
 * Handles Lua/HScript files whose names end with a period or space — names that
 * Windows (and therefore the PC build of the engine) refuses to accept.
 *
 *   Typical bad name received inside a .zip from another modder:
 *       "Arquivolua.lua."          <-- trailing period
 *       "Some Script.hx "          <-- trailing space
 *       "custom_notetype.lua.."    <-- double trailing period
 *
 * On Windows these files either can't be extracted at all, or they extract but
 * `sys.FileSystem.exists()` / `sys.io.File.getContent()` silently fail to find
 * them, so the Lua/HScript loader throws "script not found" and the song crashes.
 *
 * This utility does two things:
 *   1. `sanitizeFileName(name)` / `sanitizePath(path)` — pure string helpers,
 *      safe on every target. They strip trailing dots + spaces from the file
 *      name portion only (directory components are left alone).
 *   2. `findAndRenameBadFiles(dir)` — a `#if sys` filesystem pass that walks a
 *      directory (recursively by default), finds any file whose real on-disk
 *      name ends with `.` or ` `, and renames it to the sanitized form. This
 *      is the "rename them" path the user asked for. It is intended to be
 *      called once at startup (e.g. from PlayState.createScripts or from the
 *      mod loader) before any Lua script is loaded.
 *
 * Integration note:
 *   The Lua/HScript loader itself lives in `psychlua/` (FunkinLua / HScript /
 *   ModFolder side of the engine) and is NOT part of the files you uploaded.
 *   To fully wire this in, call one of the following from that loader right
 *   before it reads a script file:
 *
 *       var clean = ScriptFileSanitizer.sanitizePath(rawPath);
 *       if (clean != rawPath) {
 *           // try the cleaned name first, fall back to the original
 *           if (FileSystem.exists(clean)) rawPath = clean;
 *       }
 *
 *   …or, at engine startup, run once:
 *
 *       ScriptFileSanitizer.findAndRenameBadFiles('mods');
 *       ScriptFileSanitizer.findAndRenameBadFiles('assets');
 *
 *   If you want me to patch the psychlua loader directly, send me the relevant
 *   FunkinLua.hx / HScript.hx / ModFolder.hx files and I will insert the call.
 */
class ScriptFileSanitizer
{
	/** Characters Windows forbids at the END of a file name. */
	public static inline final TRAILING_BAD_CHARS:String = '. ';

	/**
	 * Strip trailing dots and spaces from a bare file name.
	 * Directory components are NOT touched — pass only the name here, or use
	 * `sanitizePath()` for full paths.
	 *
	 *   "Arquivolua.lua."      -> "Arquivolua.lua"
	 *   "custom_notetype.lua.." -> "custom_notetype.lua"
	 *   "Some Script.hx "      -> "Some Script.hx"
	 *   "normal_file.lua"      -> "normal_file.lua"   (unchanged)
	 *   "."                    -> ""                  (edge case, becomes empty)
	 */
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

	/**
	 * Sanitize just the file-name portion of a full path.
	 * The directory part is preserved verbatim.
	 *
	 *   "mods/song/foo.lua."   -> "mods/song/foo.lua"
	 *   "C:\\mods\\bar.hx."    -> "C:\\mods\\bar.hx"
	 */
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

	/**
	 * True if the given file name (or path) would be rejected by Windows
	 * because of a trailing dot or space.
	 */
	public static function hasBadTrailingChar(nameOrPath:String):Bool
	{
		if (nameOrPath == null || nameOrPath.length == 0) return false;
		var file:String = Path.withoutDirectory(nameOrPath);
		if (file.length == 0) return false;
		var last:String = file.charAt(file.length - 1);
		return TRAILING_BAD_CHARS.indexOf(last) >= 0;
	}

#if sys
	/**
	 * Walk `dir` (recursively by default) and rename every file whose on-disk
	 * name ends with a dot or space to the sanitized form. Returns the list of
	 * renames that were performed, as {from, to} pairs (full paths).
	 *
	 * Conflicts: if the sanitized target name already exists as a different
	 * file, the bad-named file is left alone and reported with a `conflict`
	 * flag so the caller can decide what to do (the engine will still fail to
	 * load it, but at least it won't silently overwrite a good file).
	 *
	 * Returns null if `dir` does not exist or is not a directory.
	 */
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

			// It's a file — check its name.
			if (!hasBadTrailingChar(entry)) continue;

			var cleanName:String = sanitizeFileName(entry);
			if (cleanName.length == 0) continue; // name was only dots/spaces, skip
			var cleanFull:String = dir + '/' + cleanName;

			if (FileSystem.exists(cleanFull))
			{
				// Target already exists — don't clobber. Report as conflict.
				results.push({from: full, to: cleanFull, conflict: true});
				continue;
			}

			// Rename the file on disk.
			FileSystem.rename(full, cleanFull);
			results.push({from: full, to: cleanFull, conflict: false});
		}

		return results;
	}

	/**
	 * Try to read a script file, transparently handling a trailing-dot/space
	 * name. Returns the file contents, or null if no variant (raw or sanitized)
	 * could be found.
	 *
	 * Use this from the Lua/HScript loader when you only have the raw path
	 * string and aren't sure whether the on-disk file has a bad name.
	 */
	public static function safeGetContent(rawPath:String):String
	{
		if (rawPath == null) return null;

		// 1. Try the raw path as-is.
		if (FileSystem.exists(rawPath) && !FileSystem.isDirectory(rawPath))
			return File.getContent(rawPath);

		// 2. Try the sanitized path (handles trailing-dot/space names that
		//    Windows reports differently).
		var clean:String = sanitizePath(rawPath);
		if (clean != rawPath)
		{
			if (FileSystem.exists(clean) && !FileSystem.isDirectory(clean))
				return File.getContent(clean);
		}

		return null;
	}

	/**
	 * Returns the path that actually exists on disk for a given raw script
	 * path — either the raw one or the sanitized one. null if neither exists.
	 */
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
