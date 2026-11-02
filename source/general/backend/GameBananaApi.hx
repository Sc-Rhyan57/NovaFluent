package general.backend;

import general.backend.OnlineMods.OnlineMod;
import haxe.Http;
import haxe.Json;
import sys.thread.Thread;

typedef GbResult =
{
	var mods:Array<OnlineMod>;
	var more:Bool;
}

class GameBananaApi
{
	public static final PROFILE_PREFIX:String = 'https://gamebanana.com/mods/';
	public static final PER_PAGE:Int = 15;

	static final GAME_ID:Int = 8694;
	static final API:String = 'https://gamebanana.com/apiv11/';
	static final USER_AGENT:String = 'NovaFlareEngine';

	public static function isGb(mod:OnlineMod):Bool
	{
		return mod.download.indexOf(PROFILE_PREFIX) == 0;
	}

	public static function search(query:String, page:Int, onDone:GbResult->String->Void):Void
	{
		Thread.create(() ->
		{
			try
			{
				var url:String = API + 'Game/' + GAME_ID + '/Subfeed?_nPage=' + page + '&_sSort=default&_csvModelInclusions=Mod';
				var q:String = query == null ? '' : StringTools.trim(query);
				if (q != '')
					url += '&_sName=' + StringTools.urlEncode(q);
				var root:Dynamic = getJson(url);
				var records:Array<Dynamic> = Reflect.field(root, '_aRecords') == null ? [] : cast Reflect.field(root, '_aRecords');
				var mods:Array<OnlineMod> = [];
				for (rec in records)
				{
					var mod:OnlineMod = toMod(rec);
					if (mod != null)
						mods.push(mod);
				}
				var meta:Dynamic = Reflect.field(root, '_aMetadata');
				var more:Bool = meta != null && Reflect.field(meta, '_bIsComplete') != null
					? Reflect.field(meta, '_bIsComplete') == false
					: records.length >= PER_PAGE;
				onDone({mods: mods, more: more}, null);
			}
			catch (e:Dynamic)
			{
				onDone(null, Std.string(e));
			}
		});
	}

	public static function install(mod:OnlineMod, onPhase:String->Float->Void):Void
	{
		onPhase('Consultando o GameBanana', -1);
		var id:String = mod.download.substr(PROFILE_PREFIX.length);
		var page:Dynamic = getJson(API + 'Mod/' + id + '/DownloadPage');
		if (Reflect.field(page, '_bIsTrashed') == true || Reflect.field(page, '_bIsWithheld') == true)
			throw 'esse mod foi removido do GameBanana';

		var files:Array<Dynamic> = Reflect.field(page, '_aFiles') == null ? [] : cast Reflect.field(page, '_aFiles');
		var best:Dynamic = null;
		var bestCount:Float = -1;
		for (f in files)
		{
			var name:String = Std.string(Reflect.field(f, '_sFile')).toLowerCase();
			if (!StringTools.endsWith(name, '.zip'))
				continue;
			if (Reflect.field(f, '_bContainsExe') == true)
				continue;
			if (Std.string(Reflect.field(f, '_sClamAvResult')) != 'clean')
				continue;
			var count:Float = num(Reflect.field(f, '_nDownloadCount'));
			if (count > bestCount)
			{
				best = f;
				bestCount = count;
			}
		}

		if (best == null)
			throw 'nenhum .zip verificado nesse mod; baixe pela página: ' + mod.download;

		var md5:Dynamic = Reflect.field(best, '_sMd5Checksum');
		var resolved:OnlineMod =
		{
			name: mod.name,
			folder: mod.folder,
			description: mod.description,
			author: mod.author,
			version: mod.version,
			cover: mod.cover,
			download: Std.string(Reflect.field(best, '_sDownloadUrl')),
			size: num(Reflect.field(best, '_nFilesize')),
			sha256: '',
			md5: md5 == null ? '' : Std.string(md5).toLowerCase()
		};
		OnlineMods.install(resolved, onPhase);
	}

	static function toMod(rec:Dynamic):OnlineMod
	{
		if (Std.string(Reflect.field(rec, '_sModelName')) != 'Mod')
			return null;
		var id:String = Std.string(Std.int(num(Reflect.field(rec, '_idRow'))));
		var name:String = Std.string(Reflect.field(rec, '_sName'));
		if (id == '0' || name == '' || name == 'null')
			return null;

		var submitter:Dynamic = Reflect.field(rec, '_aSubmitter');
		var author:String = submitter == null ? '' : Std.string(Reflect.field(submitter, '_sName'));
		var version:Dynamic = Reflect.field(rec, '_sVersion');

		return {
			name: name,
			folder: folderFor(name, id),
			description: '',
			author: author == 'null' ? '' : author,
			version: version == null ? '' : Std.string(version),
			cover: coverOf(rec),
			download: PROFILE_PREFIX + id,
			size: 0,
			sha256: ''
		};
	}

	static function coverOf(rec:Dynamic):String
	{
		var media:Dynamic = Reflect.field(rec, '_aPreviewMedia');
		if (media == null)
			return '';
		var images:Array<Dynamic> = Reflect.field(media, '_aImages') == null ? [] : cast Reflect.field(media, '_aImages');
		if (images.length == 0)
			return '';
		var img:Dynamic = images[0];
		var base:Dynamic = Reflect.field(img, '_sBaseUrl');
		if (base == null)
			return '';
		for (key in ['_sFile220', '_sFile100', '_sFile'])
		{
			var file:Dynamic = Reflect.field(img, key);
			if (file != null)
				return Std.string(base) + '/' + Std.string(file);
		}
		return '';
	}

	static function folderFor(name:String, id:String):String
	{
		var out:StringBuf = new StringBuf();
		for (i in 0...name.length)
		{
			var c:Int = name.charCodeAt(i);
			var ok:Bool = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 32 || c == 45 || c == 95;
			out.add(ok ? String.fromCharCode(c) : '_');
		}
		var clean:String = StringTools.trim(out.toString());
		if (clean.length > 48)
			clean = StringTools.trim(clean.substr(0, 48));
		return (clean == '' ? 'gb' : clean) + '_' + id;
	}

	static function num(v:Dynamic):Float
	{
		var n:Float = Std.parseFloat(Std.string(v));
		return Math.isNaN(n) ? 0 : n;
	}

	static function getJson(url:String):Dynamic
	{
		var body:String = null;
		var error:String = null;
		var status:Int = 0;

		var http = new Http(url);
		http.setHeader('User-Agent', USER_AGENT);
		http.onStatus = function(s:Int) status = s;
		http.onData = function(d:String) body = d;
		http.onError = function(e:String) error = e;
		http.request();

		if (error != null)
			throw 'sem conexão com o GameBanana: ' + error;
		if (body == null || status >= 400)
			throw 'GameBanana respondeu HTTP ' + status;

		var root:Dynamic;
		try
		{
			root = Json.parse(body);
		}
		catch (e:Dynamic)
		{
			throw 'resposta inválida do GameBanana';
		}
		if (Reflect.field(root, '_sErrorCode') != null)
			throw Std.string(Reflect.field(root, '_sErrorMessage'));
		return root;
	}
}
