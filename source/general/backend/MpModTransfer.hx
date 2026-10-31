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
	public static final CHUNK_CHARS:Int = 250000;
	public static final MAX_BYTES:Float = 512 * 1024 * 1024;
	public static final STAGE_NAMES:Array<String> = ['scripts', 'dados', 'mídia'];

	static final CHUNK_RAW:Int = Std.int(CHUNK_CHARS * 3 / 4);
	static final PART_BYTES:Int = 1024 * 1024;
	static final SCRIPT_EXT:Array<String> = ['hx', 'hxs', 'hscript', 'lua', 'frag', 'vert', 'glsl'];
	static final DATA_EXT:Array<String> = ['json', 'xml', 'txt', 'csv', 'tsv', 'ini', 'lang'];

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

	public static function plan(folder:String):ModPlan
	{
		var root:String = Paths.mods(folder);
		if (!FileSystem.exists(root))
			throw 'pasta do mod não existe: ' + folder;

		var dirs:Array<String> = [];
		var files:Array<ModEntry> = [];
		collect(root, '', dirs, files);
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

		closeOut(st);
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
