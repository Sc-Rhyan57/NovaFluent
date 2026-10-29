package general.backend;

import haxe.Http;
import haxe.Json;
import haxe.crypto.Sha256;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.BytesInput;
import haxe.io.Path;
import haxe.zip.Entry;
import haxe.zip.Reader;
import sys.FileSystem;
import sys.io.File;
import sys.thread.Thread;

typedef OnlineMod =
{
	var name:String;
	var folder:String;
	var description:String;
	var author:String;
	var version:String;
	var cover:String;
	var download:String;
	var size:Float;
	var sha256:String;
};

class OnlineMods
{
	public static final LIST_URL:String = 'https://raw.githubusercontent.com/Sc-Rhyan57/RandomFnfMods/refs/heads/main/NovaMe/MYNAMEISRHYAN.json';

	static final USER_AGENT:String = 'NovaFlareEngine';
	static final ZERO_HASH:String = '0000000000000000000000000000000000000000000000000000000000000000';

	public static function cacheRoot(path:String):String
	{
		#if mobile
		return Sys.getCwd() + 'cache/onlinemods/' + path;
		#else
		return 'cache/onlinemods/' + path;
		#end
	}

	public static function fetchList(onDone:Array<OnlineMod>->String->Void):Void
	{
		Thread.create(() ->
		{
			var body:String = null;
			var error:String = null;
			var status:Int = 0;

			var http = new Http(LIST_URL);
			http.setHeader('User-Agent', USER_AGENT);
			http.onStatus = function(s:Int) status = s;
			http.onData = function(d:String) body = d;
			http.onError = function(e:String) error = e;
			http.request();

			if (error != null)
			{
				onDone(null, 'Sem conexão com a lista: ' + error);
				return;
			}
			if (status >= 400 || body == null)
			{
				onDone(null, 'Lista indisponível (HTTP ' + status + ').');
				return;
			}

			try
			{
				onDone(parseList(body), null);
			}
			catch (e:Dynamic)
			{
				onDone(null, 'JSON da lista inválido: ' + Std.string(e));
			}
		});
	}

	public static function parseList(text:String):Array<OnlineMod>
	{
		var root:Dynamic = Json.parse(text);
		var entries:Array<Dynamic> = Std.isOfType(root, Array) ? cast root : cast field(root, 'mods', []);
		var mods:Array<OnlineMod> = [];

		for (e in entries)
		{
			var name:String = Std.string(field(e, 'name', ''));
			var download:String = Std.string(field(e, 'download', ''));
			if (name == '' || download == '')
				continue;

			var folder:String = safeFolder(Std.string(field(e, 'folder', name)));
			if (folder == null)
				continue;

			mods.push({
				name: name,
				folder: folder,
				description: Std.string(field(e, 'description', '')),
				author: Std.string(field(e, 'author', '')),
				version: Std.string(field(e, 'version', '')),
				cover: Std.string(field(e, 'cover', '')),
				download: download,
				size: Std.parseFloat(Std.string(field(e, 'size', 0))),
				sha256: Std.string(field(e, 'sha256', '')).toLowerCase()
			});
		}

		return mods;
	}

	public static function fetchBytes(url:String):Bytes
	{
		var result:Bytes = null;
		var error:String = null;
		var status:Int = 0;

		var http = new Http(url);
		http.setHeader('User-Agent', USER_AGENT);
		http.onStatus = function(s:Int) status = s;
		http.onBytes = function(b:Bytes) result = b;
		http.onError = function(e:String) error = e;
		http.request();

		if (error != null)
			throw 'falha de rede: ' + error;
		if (status >= 400)
			throw 'servidor respondeu HTTP ' + status;
		if (result == null)
			throw 'download veio vazio';
		return result;
	}

	public static function fetchBytesProgress(url:String, expected:Float, onProgress:Int->Void):Bytes
	{
		var buf:BytesBuffer = new BytesBuffer();
		var offset:Int = 0;
		var chunk:Int = 1048576;

		while (true)
		{
			var got:Bytes = null;
			var error:String = null;
			var status:Int = 0;

			var http = new Http(url);
			http.setHeader('User-Agent', USER_AGENT);
			http.setHeader('Range', 'bytes=' + offset + '-' + (offset + chunk - 1));
			http.onStatus = function(s:Int) status = s;
			http.onBytes = function(b:Bytes) got = b;
			http.onError = function(e:String) error = e;
			http.request();

			if (error != null)
				throw 'falha de rede: ' + error;
			if (status >= 400 && status != 416)
				throw 'servidor respondeu HTTP ' + status;
			if (status == 416)
				break;
			if (got == null)
				throw 'download veio vazio';

			if (status == 200)
			{
				onProgress(100);
				return got;
			}

			buf.addBytes(got, 0, got.length);
			offset += got.length;
			if (expected > 0)
				onProgress(Std.int(Math.min(100, offset * 100 / expected)));
			if (got.length < chunk)
				break;
		}

		if (buf.length == 0)
			throw 'download vazio';
		return buf.getBytes();
	}

	public static function fetchCover(mod:OnlineMod):String
	{
		if (mod.cover == '')
			return null;

		var target:String = cacheRoot(mod.folder + '.png');
		try
		{
			if (!FileSystem.exists(target))
			{
				mkdirs(Path.directory(target));
				File.saveBytes(target, fetchBytes(mod.cover));
			}
			return target;
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	public static function install(mod:OnlineMod, onPhase:String->Void):Void
	{
		var bytes:Bytes = fetchBytesProgress(mod.download, mod.size, function(p:Int) onPhase('Baixando ' + p + '%'));

		onPhase('Verificando');
		verify(bytes, mod.sha256);

		onPhase('Extraindo');
		extract(bytes, mod.folder);
	}

	static function verify(bytes:Bytes, expected:String):Void
	{
		if (expected == '' || expected == ZERO_HASH)
			return;

		var actual:String = Sha256.make(bytes).toHex();
		if (actual != expected)
			throw 'SHA-256 não confere (esperado ' + expected + ', recebido ' + actual + ').';
	}

	static function extract(bytes:Bytes, folder:String):Void
	{
		var entries:List<Entry> = new Reader(new BytesInput(bytes)).read();
		var list:Array<Entry> = [for (e in entries) e];
		var prefix:String = commonRoot(list);
		var dest:String = Paths.mods(folder);

		mkdirs(dest);

		for (e in list)
		{
			var name:String = e.fileName.split('\\').join('/');
			if (prefix != '' && StringTools.startsWith(name, prefix))
				name = name.substr(prefix.length);
			if (name == '')
				continue;

			if (name.charAt(0) == '/' || name.indexOf(':') != -1 || name.split('/').indexOf('..') != -1)
				throw 'caminho inseguro dentro do zip: ' + e.fileName;

			var target:String = dest + '/' + name;

			if (StringTools.endsWith(name, '/'))
			{
				mkdirs(target);
				continue;
			}

			mkdirs(Path.directory(target));
			File.saveBytes(target, e.data);
		}
	}

	static function commonRoot(list:Array<Entry>):String
	{
		var root:String = null;
		for (e in list)
		{
			var name:String = e.fileName.split('\\').join('/');
			var idx:Int = name.indexOf('/');
			if (idx == -1)
				return '';

			var top:String = name.substr(0, idx + 1);
			if (root == null)
				root = top;
			else if (root != top)
				return '';
		}
		return root == null ? '' : root;
	}

	static function mkdirs(dir:String):Void
	{
		if (dir == '' || FileSystem.exists(dir))
			return;
		mkdirs(Path.directory(dir));
		FileSystem.createDirectory(dir);
	}

	static function safeFolder(raw:String):String
	{
		var f:String = StringTools.trim(raw);
		if (f == '' || f == '.' || f == '..')
			return null;
		if (f.indexOf('/') != -1 || f.indexOf('\\') != -1 || f.indexOf(':') != -1)
			return null;
		return f;
	}

	static function field(obj:Dynamic, name:String, def:Dynamic):Dynamic
	{
		var v:Dynamic = Reflect.field(obj, name);
		return v == null ? def : v;
	}
}
