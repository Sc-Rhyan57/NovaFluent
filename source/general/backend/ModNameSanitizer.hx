package general.backend;

import sys.FileSystem;
import sys.io.File;

class ModNameSanitizer
{
	static final TEXT_EXTENSIONS:Array<String> = ['lua', 'hx', 'hxc', 'hscript', 'json', 'txt', 'xml', 'csv', 'ini', 'cfg'];

	static final GROUPS:Array<Array<String>> = [
		['a', 'àáâãäåāăą'], ['A', 'ÀÁÂÃÄÅĀĂĄ'], ['c', 'çćĉċč'], ['C', 'ÇĆĈĊČ'],
		['d', 'ďđ'], ['D', 'ĎĐ'], ['e', 'èéêëēĕėęě'], ['E', 'ÈÉÊËĒĔĖĘĚ'],
		['g', 'ĝğġģ'], ['G', 'ĜĞĠĢ'], ['h', 'ĥħ'], ['H', 'ĤĦ'],
		['i', 'ìíîïĩīĭįı'], ['I', 'ÌÍÎÏĨĪĬĮİ'], ['j', 'ĵ'], ['J', 'Ĵ'],
		['k', 'ķ'], ['K', 'Ķ'], ['l', 'ĺļľŀł'], ['L', 'ĹĻĽĿŁ'],
		['n', 'ñńņňŉ'], ['N', 'ÑŃŅŇ'], ['o', 'òóôõöøōŏő'], ['O', 'ÒÓÔÕÖØŌŎŐ'],
		['r', 'ŕŗř'], ['R', 'ŔŖŘ'], ['s', 'śŝşš'], ['S', 'ŚŜŞŠ'],
		['t', 'ţťŧ'], ['T', 'ŢŤŦ'], ['u', 'ùúûüũūŭůűų'], ['U', 'ÙÚÛÜŨŪŬŮŰŲ'],
		['w', 'ŵ'], ['W', 'Ŵ'], ['y', 'ýÿŷ'], ['Y', 'ÝŸŶ'],
		['z', 'źżž'], ['Z', 'ŹŻŽ'], ['ae', 'æ'], ['AE', 'Æ'],
		['oe', 'œ'], ['OE', 'Œ'], ['ss', 'ß'], ['-', '–—']
	];

	static var map:Map<Int, String>;

	public static function run(modsRoot:String):Int
	{
		#if windows
		while (modsRoot.length > 1 && StringTools.endsWith(modsRoot, '/'))
			modsRoot = modsRoot.substr(0, modsRoot.length - 1);
		if (!FileSystem.exists(modsRoot) || !FileSystem.isDirectory(modsRoot))
			return 0;
		buildMap();
		var total:Int = 0;
		for (mod in FileSystem.readDirectory(modsRoot))
		{
			var modPath:String = modsRoot + '/' + mod;
			if (!FileSystem.isDirectory(modPath))
				continue;
			try
			{
				var renamed:Map<String, String> = new Map();
				renameChildren(modPath, renamed);
				var count:Int = 0;
				for (_ in renamed.keys())
					count++;
				if (count > 0)
				{
					rewriteReferences(modPath, renamed);
					total += count;
				}
			}
			catch (e:Dynamic)
			{
				trace('ModNameSanitizer: falha em "$mod": $e');
			}
		}
		return total;
		#else
		return 0;
		#end
	}

	public static function clean(name:String):String
	{
		buildMap();
		var out:StringBuf = new StringBuf();
		var i:Int = 0;
		while (i < name.length)
		{
			var c:Int = name.charCodeAt(i);
			if (c < 128)
				out.add(String.fromCharCode(c));
			else if (c >= 0x300 && c <= 0x36F)
			{
			}
			else if (c >= 0xD800 && c <= 0xDBFF)
			{
				out.add('_');
				i++;
			}
			else if (map.exists(c))
				out.add(map.get(c));
			else
				out.add('_');
			i++;
		}
		return out.toString();
	}

	static function buildMap():Void
	{
		if (map != null)
			return;
		map = new Map();
		for (g in GROUPS)
			for (i in 0...g[1].length)
				map.set(g[1].charCodeAt(i), g[0]);
	}

	static function needsClean(name:String):Bool
	{
		for (i in 0...name.length)
			if (name.charCodeAt(i) >= 128)
				return true;
		return false;
	}

	static function uniqueName(dir:String, wanted:String, original:String):String
	{
		if (!FileSystem.exists(dir + '/' + wanted) || wanted == original)
			return wanted;
		var dot:Int = wanted.lastIndexOf('.');
		var stem:String = dot > 0 ? wanted.substr(0, dot) : wanted;
		var ext:String = dot > 0 ? wanted.substr(dot) : '';
		var n:Int = 1;
		while (FileSystem.exists(dir + '/' + stem + '_' + n + ext))
			n++;
		return stem + '_' + n + ext;
	}

	static function renameChildren(dir:String, renamed:Map<String, String>):Void
	{
		for (name in FileSystem.readDirectory(dir))
		{
			var full:String = dir + '/' + name;
			if (FileSystem.isDirectory(full))
				renameChildren(full, renamed);
			if (!needsClean(name))
				continue;
			var target:String = uniqueName(dir, clean(name), name);
			if (target == name)
				continue;
			FileSystem.rename(full, dir + '/' + target);
			renamed.set(name, target);
			trace('ModNameSanitizer: "$name" -> "$target"');
		}
	}

	static function stemOf(name:String):String
	{
		var dot:Int = name.lastIndexOf('.');
		return dot > 0 ? name.substr(0, dot) : name;
	}

	static function rewriteReferences(dir:String, renamed:Map<String, String>):Void
	{
		var pairs:Array<{from:String, to:String}> = [];
		for (from => to in renamed)
		{
			pairs.push({from: from, to: to});
			var fromStem:String = stemOf(from);
			var toStem:String = stemOf(to);
			if (fromStem != from && needsClean(fromStem))
				pairs.push({from: fromStem, to: toStem});
		}
		pairs.sort((a, b) -> b.from.length - a.from.length);
		patchFiles(dir, pairs);
	}

	static function patchFiles(dir:String, pairs:Array<{from:String, to:String}>):Void
	{
		for (name in FileSystem.readDirectory(dir))
		{
			var full:String = dir + '/' + name;
			if (FileSystem.isDirectory(full))
			{
				patchFiles(full, pairs);
				continue;
			}
			var dot:Int = name.lastIndexOf('.');
			var ext:String = dot >= 0 ? name.substr(dot + 1).toLowerCase() : '';
			if (TEXT_EXTENSIONS.indexOf(ext) < 0)
				continue;
			try
			{
				var content:String = File.getContent(full);
				var changed:String = content;
				for (p in pairs)
					changed = StringTools.replace(changed, p.from, p.to);
				if (changed != content)
					File.saveContent(full, changed);
			}
			catch (e:Dynamic)
			{
			}
		}
	}
}
