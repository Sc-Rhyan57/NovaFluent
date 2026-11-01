package general.backend;

import haxe.crypto.Base64;
import haxe.io.Bytes;
import haxe.io.Path;
import haxe.Json;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileInput;
import sys.io.FileOutput;
import sys.io.FileSeek;
import sys.thread.Deque;

typedef ModEntry =
{
	var rel:String;
	var size:Int;
	var stage:Int;
};

typedef ModPiece = {length:Int, ?bytes:Bytes, ?path:String, ?offset:Int};

typedef ModPlan =
{
	var folder:String;
	var pieces:Array<ModPiece>;
	var length:Int;
	var chunks:Int;
	var files:Int;
	var bytes:Float;
};

typedef ReceiveState =
{
	var root:String;
	var manifested:Bool;
	var out:Null<FileOutput>;
	var outRel:Null<String>;
	var stage:Int;
	var filesTotal:Int;
	var filesDone:Int;
	var bytesTotal:Float;
	var bytesDone:Float;
};

class MpModTransfer
{
	public static final CHUNK_CHARS:Int = 32000;
	public static final MAX_BYTES:Float = 512 * 1024 * 1024;
	public static final STAGE_NAMES:Array<String> = ['scripts', 'dados', 'mídia'];

	static final CHUNK_RAW:Int = Std.int(CHUNK_CHARS * 3 / 4);
	static final PART_BYTES:Int = 1024 * 1024;
	static final SCRIPT_EXT:Array<String> = ['hx', 'hxs', 'hscript', 'lua', 'frag', 'vert', 'glsl'];
	static final DATA_EXT:Array<String> = ['json', 'xml', 'txt', 'csv', 'tsv', 'ini', 'lang'];
	static final MEDIA_EXT:Array<String> = ['mp4', 'webm', 'mov', 'avi', 'mkv', 'ogg', 'mp3', 'wav', 'flac'];
	static final KNOWN_EXT:Array<String> = [
		'png', 'jpg', 'jpeg', 'xml', 'json', 'ogg', 'mp3', 'wav', 'mp4', 'webm', 'txt', 'lua', 'hx', 'frag', 'vert', 'ttf', 'otf', 'mov', 'avi', 'mkv', 'flac'
	];
	static final ALWAYS_DIRS:Array<String> = ['scripts/', 'weeks/', 'custom_events/', 'custom_notetypes/', 'characters/', 'stages/'];

	public static function folderSize(folder:String):Float
	{
		var dirs:Array<String> = [];
		var files:Array<ModEntry> = [];
		collect(Paths.mods(folder), '', dirs, files);
		var total:Float = 0;
		for (f in files)
			total += f.size;
		return total;
	}

	public static function select(folder:String, song:String, songOnly:Bool, optimize:Bool):Array<String>
	{
		var root:String = Paths.mods(folder);
		var dirs:Array<String> = [];
		var files:Array<ModEntry> = [];
		collect(root, '', dirs, files);
		var all:Array<String> = [for (f in files) f.rel];
		if (!songOnly && !optimize)
			return all;
		var songPath:String = Paths.formatToSongPath(song);
		var tokens:Map<String, Bool> = assetTokens(root, songPath, files);
		var songDirs:Array<String> = ['data/' + songPath + '/', 'songs/' + songPath + '/'];
		var out:Array<String> = [];
		for (rel in all)
		{
			var lower:String = rel.toLowerCase();
			if (isAlways(lower) || inDirs(lower, songDirs) || matchesToken(lower, tokens))
			{
				out.push(rel);
				continue;
			}
			if (!songOnly && MEDIA_EXT.indexOf(Path.extension(lower)) == -1)
				out.push(rel);
		}
		return out;
	}

	public static function sizeOf(folder:String, rels:Array<String>):Float
	{
		var root:String = Paths.mods(folder);
		var total:Float = 0;
		for (r in rels)
		{
			var full:String = root + '/' + r;
			if (FileSystem.exists(full) && !FileSystem.isDirectory(full))
				total += FileSystem.stat(full).size;
		}
		return total;
	}

	static function isAlways(lower:String):Bool
	{
		if (lower.indexOf('/') == -1)
			return true;
		for (d in ALWAYS_DIRS)
			if (StringTools.startsWith(lower, d))
				return true;
		return false;
	}

	static function inDirs(lower:String, dirs:Array<String>):Bool
	{
		for (d in dirs)
			if (StringTools.startsWith(lower, d))
				return true;
		return false;
	}

	static function matchesToken(lower:String, tokens:Map<String, Bool>):Bool
	{
		var noExt:String = Path.extension(lower) == '' ? lower : Path.withoutExtension(lower);
		var segs:Array<String> = noExt.split('/');
		for (i in 0...segs.length)
			if (tokens.exists(segs.slice(i).join('/')))
				return true;
		return false;
	}

	static function norm(raw:String):String
	{
		var t:String = StringTools.trim(raw).toLowerCase().split('\\').join('/');
		while (StringTools.startsWith(t, './'))
			t = t.substr(2);
		while (StringTools.startsWith(t, '/'))
			t = t.substr(1);
		var ext:String = Path.extension(t);
		if (ext != '' && KNOWN_EXT.indexOf(ext) != -1)
			t = Path.withoutExtension(t);
		return t;
	}

	static function addToken(tokens:Map<String, Bool>, raw:String):Void
	{
		var t:String = norm(raw);
		if (t.length < 2 || t.length > 120 || !Math.isNaN(Std.parseFloat(t)))
			return;
		tokens.set(t, true);
	}

	static function walk(v:Dynamic, tokens:Map<String, Bool>, depth:Int = 0):Void
	{
		if (v == null || depth > 24)
			return;
		if (Std.isOfType(v, String))
		{
			addToken(tokens, cast v);
			return;
		}
		if (Std.isOfType(v, Array))
		{
			var list:Array<Dynamic> = cast v;
			for (item in list)
				walk(item, tokens, depth + 1);
			return;
		}
		if (Reflect.isObject(v))
			for (k in Reflect.fields(v))
				walk(Reflect.field(v, k), tokens, depth + 1);
	}

	static function readJson(path:String):Dynamic
	{
		try
		{
			var text:String = File.getContent(path);
			if (text.length > 0 && text.charCodeAt(0) == 0xFEFF)
				text = text.substr(1);
			return Json.parse(text);
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	static function scanLua(path:String, tokens:Map<String, Bool>):Void
	{
		try
		{
			var re:EReg = ~/["']([^"'\r\n]{2,120})["']/g;
			re.map(File.getContent(path), function(r:EReg):String
			{
				addToken(tokens, r.matched(1));
				return '';
			});
		}
		catch (e:Dynamic)
		{
		}
	}

	static function assetTokens(root:String, songPath:String, files:Array<ModEntry>):Map<String, Bool>
	{
		var tokens:Map<String, Bool> = new Map();
		var lowerMap:Map<String, String> = new Map();
		for (f in files)
			lowerMap.set(f.rel.toLowerCase(), f.rel);

		var stage:String = 'stage';
		var chars:Array<String> = [];
		var songPrefix:String = 'data/' + songPath + '/';

		for (f in files)
		{
			var lower:String = f.rel.toLowerCase();
			var ext:String = Path.extension(lower);
			var inSong:Bool = StringTools.startsWith(lower, songPrefix);
			if (inSong && ext == 'json')
			{
				var data:Dynamic = readJson(root + '/' + f.rel);
				if (data == null)
					continue;
				walk(data, tokens);
				var song:Dynamic = Reflect.field(data, 'song');
				if (song == null || Std.isOfType(song, String))
					song = data;
				var st:Dynamic = Reflect.field(song, 'stage');
				if (st != null)
					stage = Std.string(st);
				for (k in ['player1', 'player2', 'player3', 'gfVersion'])
				{
					var v:Dynamic = Reflect.field(song, k);
					if (v != null)
						chars.push(Std.string(v));
				}
			}
			if (ext == 'lua' && (inSong || StringTools.startsWith(lower, 'scripts/') || StringTools.startsWith(lower, 'custom_events/')
				|| StringTools.startsWith(lower, 'custom_notetypes/')))
				scanLua(root + '/' + f.rel, tokens);
		}

		addToken(tokens, stage);
		var stageJson:String = lowerMap.get('stages/' + stage.toLowerCase() + '.json');
		if (stageJson != null)
			walk(readJson(root + '/' + stageJson), tokens);
		var stageLua:String = lowerMap.get('stages/' + stage.toLowerCase() + '.lua');
		if (stageLua != null)
			scanLua(root + '/' + stageLua, tokens);

		var doneChars:Map<String, Bool> = new Map();
		var queue:Array<String> = chars.copy();
		var progress:Bool = true;
		while (progress)
		{
			progress = false;
			for (t in tokens.keys())
			{
				var short:String = StringTools.startsWith(t, 'characters/') ? t.substr(11) : t;
				if (!doneChars.exists(short.toLowerCase()) && lowerMap.exists('characters/' + short.toLowerCase() + '.json') && queue.indexOf(short) == -1)
					queue.push(short);
			}
			while (queue.length > 0)
			{
				var c:String = queue.shift();
				var key:String = c.toLowerCase();
				if (doneChars.exists(key))
					continue;
				doneChars.set(key, true);
				progress = true;
				addToken(tokens, c);
				var cj:String = lowerMap.get('characters/' + key + '.json');
				if (cj == null)
					continue;
				var cdata:Dynamic = readJson(root + '/' + cj);
				walk(cdata, tokens);
				var icon:Dynamic = cdata == null ? null : Reflect.field(cdata, 'healthicon');
				if (icon != null)
				{
					addToken(tokens, 'icons/icon-' + Std.string(icon));
					addToken(tokens, 'icons/' + Std.string(icon));
				}
			}
		}

		for (f in files)
		{
			var lower:String = f.rel.toLowerCase();
			if (!StringTools.startsWith(lower, 'weeks/') || Path.extension(lower) != 'json')
				continue;
			var week:Dynamic = readJson(root + '/' + f.rel);
			if (week == null || !Reflect.hasField(week, 'songs'))
				continue;
			var songs:Array<Dynamic> = cast Reflect.field(week, 'songs');
			for (entry in songs)
			{
				var e:Array<Dynamic> = cast entry;
				if (e != null && e.length > 1 && Paths.formatToSongPath(Std.string(e[0])) == songPath)
				{
					addToken(tokens, 'icons/icon-' + Std.string(e[1]));
					addToken(tokens, 'icons/' + Std.string(e[1]));
				}
			}
		}
		return tokens;
	}

	public static function plan(folder:String, ?keep:Array<String>):ModPlan
	{
		var root:String = Paths.mods(folder);
		if (!FileSystem.exists(root))
			throw 'pasta do mod não existe: ' + folder;

		var dirs:Array<String> = [];
		var files:Array<ModEntry> = [];
		collect(root, '', dirs, files);
		if (keep != null)
		{
			var keepSet:Map<String, Bool> = new Map();
			for (k in keep)
				keepSet.set(k, true);
			files = files.filter(function(f:ModEntry):Bool return keepSet.exists(f.rel));
			var seen:Map<String, Bool> = new Map();
			dirs = [];
			for (f in files)
			{
				var parts:Array<String> = f.rel.split('/');
				var cur:String = '';
				for (i in 0...parts.length - 1)
				{
					cur = cur == '' ? parts[i] : cur + '/' + parts[i];
					if (!seen.exists(cur))
					{
						seen.set(cur, true);
						dirs.push(cur);
					}
				}
			}
		}
		dirs.sort(compareText);
		files.sort(function(a:ModEntry, b:ModEntry):Int return a.stage != b.stage ? a.stage - b.stage : compareText(a.rel, b.rel));

		var total:Float = 0;
		for (f in files)
			total += f.size;

		var manifest:Bytes = Bytes.ofString(Json.stringify({
			folder: folder,
			dirs: dirs,
			files: [for (f in files) {p: f.rel, s: f.size, g: f.stage}],
			total: total
		}));

		var pieces:Array<ModPiece> = [];
		var head:Bytes = header(0, '', manifest.length, true);
		pieces.push({length: head.length, bytes: head});
		pieces.push({length: manifest.length, bytes: manifest});

		for (f in files)
		{
			var abs:String = root + '/' + f.rel;
			var parts:Int = f.size == 0 ? 1 : Std.int((f.size + PART_BYTES - 1) / PART_BYTES);
			for (p in 0...parts)
			{
				var offset:Int = p * PART_BYTES;
				var len:Int = Std.int(Math.min(PART_BYTES, f.size - offset));
				var h:Bytes = header(1, f.rel, len, p == parts - 1);
				pieces.push({length: h.length, bytes: h});
				if (len > 0)
					pieces.push({length: len, path: abs, offset: offset});
			}
		}

		var length:Int = 0;
		for (piece in pieces)
			length += piece.length;

		return {
			folder: folder,
			pieces: pieces,
			length: length,
			chunks: Std.int(Math.max(1, Math.ceil(length / CHUNK_RAW))),
			files: files.length,
			bytes: total
		};
	}

	public static function chunkBase64(plan:ModPlan, index:Int):String
	{
		var from:Int = index * CHUNK_RAW;
		var to:Int = Std.int(Math.min(plan.length, from + CHUNK_RAW));
		var out:Bytes = Bytes.alloc(to - from);
		var written:Int = 0;
		var pos:Int = 0;

		for (piece in plan.pieces)
		{
			var start:Int = pos;
			var end:Int = pos + piece.length;
			pos = end;
			if (end <= from)
				continue;
			if (start >= to)
				break;

			var s:Int = from > start ? from : start;
			var e:Int = to < end ? to : end;
			var n:Int = e - s;
			var inner:Int = s - start;

			if (piece.bytes != null)
				out.blit(written, piece.bytes, inner, n);
			else
			{
				var input:FileInput = File.read(piece.path, true);
				input.seek(piece.offset + inner, FileSeek.SeekBegin);
				input.readFullBytes(out, written, n);
				input.close();
			}
			written += n;
		}

		return Base64.encode(out);
	}

	public static function receive(queue:Deque<Dynamic>, events:Deque<Dynamic>, folder:String):Void
	{
		var st:ReceiveState = {
			root: Paths.mods(folder),
			manifested: false,
			out: null,
			outRel: null,
			stage: 0,
			filesTotal: 0,
			filesDone: 0,
			bytesTotal: 0,
			bytesDone: 0
		};
		var pending:Bytes = Bytes.alloc(0);
		var complete:Bool = false;
		var error:String = null;

		try
		{
			while (!complete)
			{
				var msg:Dynamic = queue.pop(true);
				if (msg == null)
					break;
				var index:Int = msg.index;
				var total:Int = msg.total;
				var data:String = msg.data;

				pending = consume(join(pending, Base64.decode(data)), st);
				events.add({
					kind: 'modProgress',
					done: st.bytesDone,
					total: st.bytesTotal,
					files: st.filesDone,
					filesTotal: st.filesTotal,
					stage: STAGE_NAMES[st.stage]
				});
				complete = index == total - 1;
			}

			if (!complete)
				throw 'transferência do mod interrompida';
			if (!st.manifested || pending.length != 0 || st.filesDone != st.filesTotal)
				throw 'transferência do mod incompleta';
		}
		catch (e:Dynamic)
		{
			error = Std.string(e);
		}

		var partial:String = st.outRel;
		closeOut(st);
		if (error != null && partial != null)
		{
			try
			{
				FileSystem.deleteFile(st.root + '/' + partial);
			}
			catch (e:Dynamic)
			{
			}
		}
		if (error == null)
			events.add({kind: 'modDone', ok: true});
		else
			events.add({kind: 'modDone', ok: false, error: error});
	}

	static function consume(buf:Bytes, st:ReceiveState):Bytes
	{
		var pos:Int = 0;
		while (buf.length - pos >= 10)
		{
			var kind:Int = buf.get(pos);
			var pathLen:Int = getU32(buf, pos + 1);
			if (pathLen < 0 || buf.length - pos < 10 + pathLen)
				break;

			var rel:String = buf.getString(pos + 5, pathLen);
			var dataAt:Int = pos + 5 + pathLen;
			var dataLen:Int = getU32(buf, dataAt);
			var last:Bool = buf.get(dataAt + 4) == 1;
			var start:Int = dataAt + 5;
			if (dataLen < 0 || buf.length - start < dataLen)
				break;

			if (kind == 0)
				applyManifest(st, buf.getString(start, dataLen));
			else
				applyPart(st, rel, buf, start, dataLen, last);
			pos = start + dataLen;
		}
		return buf.sub(pos, buf.length - pos);
	}

	static function applyManifest(st:ReceiveState, json:String):Void
	{
		var info:Dynamic = Json.parse(json);
		var dirs:Array<String> = cast info.dirs;
		var files:Array<Dynamic> = cast info.files;

		mkdirs(st.root);
		for (d in dirs)
		{
			if (!isSafe(d))
				throw 'caminho inseguro no mod recebido: ' + d;
			mkdirs(st.root + '/' + d);
		}

		st.filesTotal = files.length;
		st.bytesTotal = info.total;
		st.manifested = true;
	}

	static function applyPart(st:ReceiveState, rel:String, buf:Bytes, start:Int, len:Int, last:Bool):Void
	{
		if (!st.manifested)
			throw 'mod recebido sem estrutura';
		if (!isSafe(rel))
			throw 'caminho inseguro no mod recebido: ' + rel;

		if (st.outRel != rel)
		{
			closeOut(st);
			var target:String = st.root + '/' + rel;
			mkdirs(Path.directory(target));
			st.out = File.write(target, true);
			st.outRel = rel;
			st.stage = stageOf(rel);
		}

		if (len > 0)
			st.out.writeBytes(buf, start, len);
		st.bytesDone += len;

		if (last)
		{
			closeOut(st);
			st.filesDone++;
		}
	}

	static function closeOut(st:ReceiveState):Void
	{
		if (st.out != null)
		{
			st.out.close();
			st.out = null;
		}
		st.outRel = null;
	}

	static function header(kind:Int, rel:String, dataLen:Int, last:Bool):Bytes
	{
		var path:Bytes = Bytes.ofString(rel);
		var out:Bytes = Bytes.alloc(10 + path.length);
		out.set(0, kind);
		putU32(out, 1, path.length);
		out.blit(5, path, 0, path.length);
		putU32(out, 5 + path.length, dataLen);
		out.set(9 + path.length, last ? 1 : 0);
		return out;
	}

	static function putU32(b:Bytes, at:Int, v:Int):Void
	{
		b.set(at, (v >>> 24) & 0xFF);
		b.set(at + 1, (v >>> 16) & 0xFF);
		b.set(at + 2, (v >>> 8) & 0xFF);
		b.set(at + 3, v & 0xFF);
	}

	static function getU32(b:Bytes, at:Int):Int
	{
		return (b.get(at) << 24) | (b.get(at + 1) << 16) | (b.get(at + 2) << 8) | b.get(at + 3);
	}

	static function join(a:Bytes, b:Bytes):Bytes
	{
		var out:Bytes = Bytes.alloc(a.length + b.length);
		out.blit(0, a, 0, a.length);
		out.blit(a.length, b, 0, b.length);
		return out;
	}

	static function stageOf(rel:String):Int
	{
		var ext:String = Path.extension(rel).toLowerCase();
		if (SCRIPT_EXT.indexOf(ext) != -1)
			return 0;
		if (DATA_EXT.indexOf(ext) != -1)
			return 1;
		return 2;
	}

	static function isSafe(rel:String):Bool
	{
		return rel != '' && rel.charAt(0) != '/' && rel.indexOf(':') == -1 && rel.indexOf('\\') == -1 && rel.split('/').indexOf('..') == -1;
	}

	static function collect(root:String, prefix:String, dirs:Array<String>, files:Array<ModEntry>):Void
	{
		var dir:String = prefix == '' ? root : root + '/' + prefix;
		for (name in FileSystem.readDirectory(dir))
		{
			var rel:String = prefix == '' ? name : prefix + '/' + name;
			var full:String = root + '/' + rel;
			if (FileSystem.isDirectory(full))
			{
				dirs.push(rel);
				collect(root, rel, dirs, files);
			}
			else
				files.push({rel: rel, size: FileSystem.stat(full).size, stage: stageOf(rel)});
		}
	}

	static function compareText(a:String, b:String):Int
	{
		return a < b ? -1 : a > b ? 1 : 0;
	}

	static function mkdirs(dir:String):Void
	{
		if (dir == '' || FileSystem.exists(dir))
			return;
		mkdirs(Path.directory(dir));
		FileSystem.createDirectory(dir);
	}
}
