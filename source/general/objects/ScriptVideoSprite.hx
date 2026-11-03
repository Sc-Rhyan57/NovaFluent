package general.objects;

#if (VIDEOS_ALLOWED && hxvlc)
import hxvlc.flixel.FlxVideoSprite;

/**
 * Vídeo para usar DENTRO do cenário (Lua / HScript), diferente do `VideoSprite`
 * (que é o player de cutscene em tela cheia).
 *
 * É um FlxSprite de verdade, então `scale`, `screenCenter`, `scrollFactor`, `cameras`,
 * `alpha`, `angle`, `shader`, `addBehindBF(...)`, etc. funcionam como em qualquer sprite.
 *
 * - Por padrão o vídeo é encaixado na largura do jogo (como a cutscene faz). O `scale`
 *   que você define é RELATIVO a esse encaixe: scale 1.2 = 20% maior que a tela.
 * - Se você chamar `screenCenter()` antes do vídeo carregar (o tamanho ainda é
 *   desconhecido), ele é recentralizado automaticamente quando o formato chega.
 * - Pausa sozinho quando o jogo é pausado e volta quando o jogo volta (use
 *   `playVideo/pauseVideo/resumeVideo/stopVideo` para o controle ser respeitado).
 * - É destruído (libera o libvlc) quando o state fecha.
 */
class ScriptVideoSprite extends FlxVideoSprite
{
	public static var instances:Array<ScriptVideoSprite> = [];

	/** Chamado quando o vídeo termina (só se `loop` = false). */
	public var onEnd:Void->Void = null;

	/** Encaixa na largura do jogo ao carregar. Desligue para usar o tamanho nativo do vídeo. */
	public var autoFit:Bool = true;

	public var looping(default, null):Bool = false;
	public var videoPath(default, null):String = null;
	public var videoFound(default, null):Bool = false;
	public var playing(default, null):Bool = false;
	public var disposed(default, null):Bool = false;

	var fit:Float = 1;
	var startX:Float = 0;
	var startY:Float = 0;
	var preW:Float = 0;
	var preH:Float = 0;
	var posGiven:Bool = false;
	var gamePaused:Bool = false;
	var volume:Float = 1;

	/**
	 * Descobre o arquivo real a partir do que o script passou.
	 * Aceita 'meuvideo', 'videos/meuvideo', 'videos/meuvideo.mp4', 'mods/x/videos/a.mp4', etc.
	 */
	public static function resolve(name:String):Null<String>
	{
		if (name == null || name.length == 0)
			return null;

		var n:String = name.replace('\\', '/');
		if (FileSystem.exists(n) && !FileSystem.isDirectory(n))
			return n;

		var key:String = n;
		var ext:String = null;
		var dot:Int = key.lastIndexOf('.');
		if (dot > key.lastIndexOf('/'))
		{
			ext = key.substr(dot + 1).toLowerCase();
			key = key.substr(0, dot);
		}
		if (key.startsWith('videos/'))
			key = key.substr(7);

		var exts:Array<String> = ext != null ? [ext] : [Paths.VIDEO_EXT, 'webm', 'mov', 'mkv', 'avi'];
		for (e in exts)
		{
			#if MODS_ALLOWED
			var m:String = Paths.modFolders('videos/$key.$e');
			if (FileSystem.exists(m))
				return m;
			#end
			var a:String = 'assets/videos/$key.$e';
			if (FileSystem.exists(a))
				return a;
			var s:String = 'assets/shared/videos/$key.$e';
			if (FileSystem.exists(s))
				return s;
		}
		return null;
	}

	public function new(videoName:String, ?x:Float, ?y:Float, ?loop:Bool = false)
	{
		var sx:Float = x == null ? 0 : x;
		var sy:Float = y == null ? 0 : y;
		super(sx, sy);

		posGiven = (x != null || y != null);
		startX = sx;
		startY = sy;
		looping = (loop == true);
		scrollFactor.set(1, 1);
		antialiasing = ClientPrefs.data.antialiasing;
		preW = width;
		preH = height;

		instances.push(this);

		bitmap.onFormatSetup.add(onFormat);
		if (!looping)
			bitmap.onEndReached.add(onEndReached);

		videoPath = resolve(videoName);
		if (videoPath == null)
		{
			trace('ScriptVideoSprite: vídeo não encontrado: $videoName');
			return;
		}

		load(videoPath, looping ? ['input-repeat=65545'] : null);
		videoFound = true;
		bitmap.volumeAdjust = volume * FlxG.sound.volume;
	}

	function onFormat():Void
	{
		if (disposed)
			return;

		fit = (autoFit && frameWidth > 0) ? FlxG.width / frameWidth : 1;
		updateHitbox();

		// Se o script centralizou (ou não posicionou) antes do tamanho ser conhecido, centraliza de novo.
		var wasCenteredX:Bool = Math.abs(x - (FlxG.width - preW) / 2) < 1.5;
		var wasCenteredY:Bool = Math.abs(y - (FlxG.height - preH) / 2) < 1.5;
		if (!posGiven && x == startX && y == startY)
			wasCenteredX = wasCenteredY = true;

		if (wasCenteredX)
			screenCenter(X);
		if (wasCenteredY)
			screenCenter(Y);
	}

	function onEndReached():Void
	{
		playing = false;
		var cb:Void->Void = onEnd;
		if (cb != null && !disposed)
			cb();
	}

	// O encaixe (fit) é aplicado só na hora de desenhar; assim `scale` continua sendo o valor do script.
	override function draw():Void
	{
		if (fit != 1)
		{
			var sx:Float = scale.x;
			var sy:Float = scale.y;
			scale.set(sx * fit, sy * fit);
			super.draw();
			scale.set(sx, sy);
		}
		else
			super.draw();
	}

	// ---- controle (use estes nos scripts) -------------------------------------------

	public function playVideo():Bool
	{
		if (disposed || !videoFound)
			return false;
		gamePaused = false;
		play();
		playing = true;
		return true;
	}

	public function pauseVideo():Void
	{
		if (disposed || !videoFound)
			return;
		playing = false;
		gamePaused = false;
		pause();
	}

	public function resumeVideo():Void
	{
		if (disposed || !videoFound)
			return;
		playing = true;
		gamePaused = false;
		resume();
	}

	public function stopVideo():Void
	{
		if (disposed || !videoFound)
			return;
		playing = false;
		gamePaused = false;
		stop();
	}

	public function setVideoVolume(v:Float):Void
	{
		volume = Math.max(0, v);
		if (!disposed && bitmap != null)
			bitmap.volumeAdjust = volume * FlxG.sound.volume;
	}

	// ---- ciclo de vida --------------------------------------------------------------

	override function destroy():Void
	{
		if (disposed)
			return;
		disposed = true;
		playing = false;
		onEnd = null;
		instances.remove(this);
		try
		{
			stop();
		}
		catch (e:Dynamic) {}
		super.destroy();
	}

	/** Pausa os vídeos que estavam tocando (jogo pausou). */
	public static function pauseAll():Void
	{
		for (v in instances)
		{
			if (v.disposed || !v.playing)
				continue;
			try
			{
				v.gamePaused = true;
				v.playing = false;
				v.pause();
			}
			catch (e:Dynamic) {}
		}
	}

	/** Retoma só o que o JOGO pausou (o que o script pausou continua pausado). */
	public static function resumeAll():Void
	{
		for (v in instances)
		{
			if (v.disposed || !v.gamePaused)
				continue;
			try
			{
				v.gamePaused = false;
				v.playing = true;
				v.resume();
			}
			catch (e:Dynamic) {}
		}
	}

	/** Libera todos (chamado ao fechar o state). */
	public static function disposeAll():Void
	{
		var list:Array<ScriptVideoSprite> = instances.copy();
		instances = [];
		for (v in list)
		{
			try
			{
				v.destroy();
			}
			catch (e:Dynamic) {}
		}
	}
}
#else
class ScriptVideoSprite {}
#end
