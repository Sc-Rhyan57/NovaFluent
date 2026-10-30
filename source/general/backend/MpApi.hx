package general.backend;

import haxe.Http;
import haxe.Json;
import sys.thread.Thread;

class MpApi
{
	public static final BASE:String = 'https://nfserver.msdoors-gg.workers.dev/api/v1/multiplayer';
	public static final WS_URL:String = 'wss://nfserver.msdoors-gg.workers.dev/api/v1/multiplayer/socket';

	public static var token:String = null;
	public static var username:String = null;

	public static function call(method:String, path:String, body:Dynamic, onDone:Int->Dynamic->Void):Void
	{
		Thread.create(() ->
		{
			var status:Int = 0;
			var raw:String = '';
			var error:String = null;

			var http = new Http(BASE + path);
			http.setHeader('Content-Type', 'application/json');
			http.setHeader('User-Agent', 'NovaFlareEngine');
			if (token != null)
				http.setHeader('Authorization', 'Bearer ' + token);
			http.onStatus = function(s:Int) status = s;
			http.onData = function(d:String) raw = d;
			http.onError = function(e:String) error = e;
			if (body != null)
				http.setPostData(Json.stringify(body));
			http.request(method == 'POST');

			if (error != null)
			{
				onDone(0, {success: false, message: 'Sem conexão com o servidor.'});
				return;
			}

			var json:Dynamic = {success: false, message: 'Resposta inválida do servidor.'};
			if (raw != '')
			{
				try
				{
					json = Json.parse(raw);
				}
				catch (e:Dynamic)
				{
				}
			}
			onDone(status, json);
		});
	}

	public static function register(user:String, pass:String, onDone:Int->Dynamic->Void):Void
	{
		call('POST', '/account/register', {username: user, password: pass}, function(s:Int, j:Dynamic)
		{
			if (s == 201 && j.success == true)
				setSession(user, j.token);
			onDone(s, j);
		});
	}

	public static function login(user:String, pass:String, onDone:Int->Dynamic->Void):Void
	{
		call('POST', '/account/login', {username: user, password: pass}, function(s:Int, j:Dynamic)
		{
			if (s == 200 && j.success == true)
				setSession(user, j.token);
			onDone(s, j);
		});
	}

	public static function logout(onDone:Int->Dynamic->Void):Void
	{
		call('POST', '/account/logout', {}, function(s:Int, j:Dynamic)
		{
			clearSession();
			onDone(s, j);
		});
	}

	public static function listServers(onDone:Int->Dynamic->Void):Void
	{
		call('GET', '/rooms', null, onDone);
	}

	public static function createServer(payload:Dynamic, onDone:Int->Dynamic->Void):Void
	{
		call('POST', '/rooms', payload, onDone);
	}

	public static function getScripts(onDone:Int->Dynamic->Void):Void
	{
		call('GET', '/scripts', null, onDone);
	}

	static function setSession(user:String, tok:String):Void
	{
		username = user;
		token = tok;
	}

	static function clearSession():Void
	{
		username = null;
		token = null;
	}
}
