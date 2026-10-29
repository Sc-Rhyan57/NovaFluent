package general.backend;

import haxe.Http;
import haxe.Json;
import sys.thread.Thread;

class MpApi
{
	public static final BASE:String = 'https://novaflare-mp.SEU-SUBDOMINIO.workers.dev';
	public static final WS_URL:String = 'wss://novaflare-mp.SEU-SUBDOMINIO.workers.dev/ws';

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
				onDone(0, {ok: false, error: 'Sem conexão com o servidor.'});
				return;
			}

			var json:Dynamic = {ok: false, error: 'Resposta inválida do servidor.'};
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
		call('POST', '/api/register', {username: user, password: pass}, function(s:Int, j:Dynamic)
		{
			if (s == 201 && j.ok == true)
				setSession(user, j.token);
			onDone(s, j);
		});
	}

	public static function login(user:String, pass:String, onDone:Int->Dynamic->Void):Void
	{
		call('POST', '/api/login', {username: user, password: pass}, function(s:Int, j:Dynamic)
		{
			if (s == 200 && j.ok == true)
				setSession(user, j.token);
			onDone(s, j);
		});
	}

	public static function logout(onDone:Int->Dynamic->Void):Void
	{
		call('POST', '/api/logout', {}, function(s:Int, j:Dynamic)
		{
			clearSession();
			onDone(s, j);
		});
	}

	public static function listServers(onDone:Int->Dynamic->Void):Void
	{
		call('GET', '/api/servers', null, onDone);
	}

	public static function createServer(payload:Dynamic, onDone:Int->Dynamic->Void):Void
	{
		call('POST', '/api/servers', payload, onDone);
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
