package general.backend;

import haxe.Json;
import haxe.crypto.Crc32;
import haxe.io.Bytes;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileInput;
import sys.io.FileSeek;

typedef ManifestEntry =
{
	var p:String;
	var s:Int;
	var c:String;
};

class MpManifest
{
	public static final PART_ENTRIES:Int = 1500;
	static final SAMPLE:Int = 65536;

	public static function dir():String
	{
		var d:String = OnlineMods.cacheRoot('manifests/');
		mkdirs(d);
		return d;
	}

	public static function signature(abs:String, size:Int):String
	{
		var input:FileInput = File.read(abs, true);
		var head:Int = Std.int(Math.min(size, SAMPLE));
		var a:Bytes = Bytes.alloc(head);
		if (head > 0)
			input.readFullBytes(a, 0, head);
		var crcTail:Int = 0;
		if (size > SAMPLE * 2)
		{
			input.seek(size - SAMPLE, FileSeek.SeekBegin);
			var b:Bytes = Bytes.alloc(SAMPLE);
			input.readFullBytes(b, 0, SAMPLE);
			crcTail = Crc32.make(b);
		}
		input.close();
		return StringTools.hex(Crc32.make(a), 8) + StringTools.hex(crcTail, 8);
	}

	public static function build(folder:String, only:Null<Array<String>>):Array<ManifestEntry>
	{
		var root:String = Paths.mods(folder);
		var rels:Array<String> = [];
		if (only != null)
		{
			for (r in only)
				if (FileSystem.exists(root + '/' + r) && !FileSystem.isDirectory(root + '/' + r))
					rels.push(r);
		}
		else if (FileSystem.exists(root))
			collect(root, '', rels);
		rels.sort(function(a:String, b:String):Int return a < b ? -1 : a > b ? 1 : 0);
		var out:Array<ManifestEntry> = [];
		for (r in rels)
		{
			var size:Int = FileSystem.stat(root + '/' + r).size;
			out.push({p: r, s: size, c: signature(root + '/' + r, size)});
		}
		return out;
	}

	static function row(e:ManifestEntry):Array<Dynamic>
	{
		var r:Array<Dynamic> = [];
		r.push(e.p);
		r.push(e.s);
		r.push(e.c);
		return r;
	}

	public static function parts(entries:Array<ManifestEntry>):Array<Array<Dynamic>>
	{
		var out:Array<Array<Dynamic>> = [];
		var cur:Array<Dynamic> = [];
		for (e in entries)
		{
			cur.push(row(e));
			if (cur.length >= PART_ENTRIES)
			{
				out.push(cur);
				cur = [];
			}
		}
		if (cur.length > 0 || out.length == 0)
			out.push(cur);
		return out;
	}

	public static function save(folder:String, entries:Array<ManifestEntry>):Bool
	{
		try
		{
			var safe:String = ~/[^A-Za-z0-9_\-]/g.replace(folder, '_');
			File.saveContent(dir() + safe + '.json', Json.stringify({
				folder: folder,
				created: Date.now().getTime(),
				count: entries.length,
				files: [for (e in entries) row(e)]
			}));
			return true;
		}
		catch (e:Dynamic)
		{
			return false;
		}
	}

	static function collect(root:String, prefix:String, out:Array<String>):Void
	{
		var dirPath:String = prefix == '' ? root : root + '/' + prefix;
		for (name in FileSystem.readDirectory(dirPath))
		{
			var rel:String = prefix == '' ? name : prefix + '/' + name;
			if (FileSystem.isDirectory(root + '/' + rel))
				collect(root, rel, out);
			else
				out.push(rel);
		}
	}

	static function mkdirs(d:String):Void
	{
		while (d.length > 1 && StringTools.endsWith(d, '/'))
			d = d.substr(0, d.length - 1);
		if (d == '' || FileSystem.exists(d))
			return;
		mkdirs(haxe.io.Path.directory(d));
		FileSystem.createDirectory(d);
	}
}
