package general.backend;

import haxe.crypto.Base64;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class MpModTransfer
{
	public static final CHUNK_CHARS:Int = 250000;

	public static function folderSize(folder:String):Float
	{
		var root:String = Paths.mods(folder);
		var total:Float = 0;
		for (rel in listFiles(root, ''))
			total += FileSystem.stat(root + '/' + rel).size;
		return total;
	}

	public static function encode(folder:String):String
	{
		var root:String = Paths.mods(folder);
		if (!FileSystem.exists(root))
			throw 'pasta do mod não existe: ' + folder;
		var out = new BytesOutput();

		for (rel in listFiles(root, ''))
		{
			var data:Bytes = File.getBytes(root + '/' + rel);
			var pathBytes:Bytes = Bytes.ofString(rel);

			out.writeInt32(pathBytes.length);
			out.writeBytes(pathBytes, 0, pathBytes.length);
			out.writeInt32(data.length);
			out.writeBytes(data, 0, data.length);
		}

		return Base64.encode(out.getBytes());
	}

	public static function decodeInto(base64:String, folder:String):Void
	{
		if (base64 == null || base64 == '')
			throw 'mod recebido vazio: ' + folder;
		var bytes:Bytes = Base64.decode(base64);
		var input = new BytesInput(bytes);
		var root:String = Paths.mods(folder);

		mkdirs(root);

		while (input.position < bytes.length)
		{
			var pathLen:Int = input.readInt32();
			var rel:String = input.readString(pathLen);
			var dataLen:Int = input.readInt32();
			var data:Bytes = input.read(dataLen);

			if (rel == '' || rel.charAt(0) == '/' || rel.indexOf(':') != -1 || rel.split('/').indexOf('..') != -1)
				throw 'caminho inseguro no mod recebido: ' + rel;

			var target:String = root + '/' + rel;
			mkdirs(Path.directory(target));
			File.saveBytes(target, data);
		}
	}

	static function listFiles(root:String, prefix:String):Array<String>
	{
		var out:Array<String> = [];
		var dir:String = prefix == '' ? root : root + '/' + prefix;

		for (name in FileSystem.readDirectory(dir))
		{
			var rel:String = prefix == '' ? name : prefix + '/' + name;
			if (FileSystem.isDirectory(root + '/' + rel))
				out = out.concat(listFiles(root, rel));
			else
				out.push(rel);
		}

		return out;
	}

	static function mkdirs(dir:String):Void
	{
		if (dir == '' || FileSystem.exists(dir))
			return;
		mkdirs(Path.directory(dir));
		FileSystem.createDirectory(dir);
	}
}
