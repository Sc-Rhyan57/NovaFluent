package states.onlineModsState;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import general.backend.MusicBeatState;
import general.backend.OnlineMods;
import general.backend.OnlineMods.OnlineMod;
import general.backend.Paths;
import states.freeplayState.FreeplayState;
import sys.FileSystem;
import sys.thread.Deque;
import sys.thread.Thread;

typedef ModRow =
{
	var bg:FlxSprite;
	var cover:FlxSprite;
	var name:FlxText;
	var info:FlxText;
	var button:FlxButton;
};

class OnlineModsState extends MusicBeatState
{
	static inline final ROW_H:Int = 100;
	static inline final ROW_START:Int = 150;
	static inline final VISIBLE:Int = 4;
	static inline final PANEL_X:Int = 40;

	var events:Deque<Dynamic> = new Deque();
	var mods:Array<OnlineMod> = [];
	var rows:Array<ModRow> = [];
	var scroll:Int = 0;
	var busy:Bool = false;

	var status:FlxText;
	var upButton:FlxButton;
	var downButton:FlxButton;
	var backButton:FlxButton;

	override function create():Void
	{
		super.create();

		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF0E1216);
		add(bg);

		var title:FlxText = new FlxText(PANEL_X, 36, FlxG.width - PANEL_X * 2, 'MODS ONLINE', 36);
		add(title);

		status = new FlxText(PANEL_X, 96, FlxG.width - PANEL_X * 2, 'Carregando lista...', 18);
		add(status);

		upButton = new FlxButton(FlxG.width - 130, ROW_START - 44, 'SOBE', function() scrollBy(-1));
		downButton = new FlxButton(FlxG.width - 130, ROW_START + VISIBLE * ROW_H - 20, 'DESCE', function() scrollBy(1));
		backButton = new FlxButton(PANEL_X, FlxG.height - 80, 'VOLTAR', goBack);
		add(upButton);
		add(downButton);
		add(backButton);

		Thread.create(() -> OnlineMods.fetchList(function(list:Array<OnlineMod>, error:String)
		{
			events.add({kind: 'list', mods: list, error: error});
		}));
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		var ev:Dynamic = events.pop(false);
		while (ev != null)
		{
			handle(ev);
			ev = events.pop(false);
		}

		if (controls.BACK)
			goBack();
	}

	function handle(ev:Dynamic):Void
	{
		switch (ev.kind)
		{
			case 'list':
				if (ev.error != null)
				{
					status.text = 'Erro: ' + ev.error;
					return;
				}
				mods = ev.mods;
				buildRows();
				if (mods.length == 0)
				{
					status.text = 'Nenhum mod na lista.';
					return;
				}
				status.text = 'Escolha um mod para baixar.';
				fetchCovers(mods);

			case 'cover':
				setCover(ev.index, ev.path);

			case 'phase':
				status.text = ev.text;

			case 'done':
				busy = false;
				if (ev.ok)
				{
					var mod:OnlineMod = mods[ev.index];
					rows[ev.index].button.label.text = 'INSTALADO';
					status.text = 'Pronto: ' + mod.name + '. Ative em Mods para usar.';
				}
				else
				{
					status.text = 'Falhou: ' + ev.error;
				}
				layoutRows();
		}
	}

	function buildRows():Void
	{
		var panelW:Int = FlxG.width - PANEL_X * 2;

		for (i in 0...mods.length)
		{
			var m:OnlineMod = mods[i];
			var index:Int = i;

			var rowBg:FlxSprite = new FlxSprite(PANEL_X, 0).makeGraphic(panelW, ROW_H - 10, 0xFF1C232B);
			var cover:FlxSprite = new FlxSprite(PANEL_X + 10, 0).makeGraphic(72, 72, 0xFF2A323C);
			var name:FlxText = new FlxText(PANEL_X + 96, 0, panelW - 290, m.name, 22);
			var info:FlxText = new FlxText(PANEL_X + 96, 0, panelW - 290, infoLine(m), 14);
			var installed:Bool = FileSystem.exists(Paths.mods(m.folder));
			var button:FlxButton = new FlxButton(FlxG.width - 170, 0, installed ? 'INSTALADO' : 'BAIXAR', function() download(index));

			var row:ModRow = {bg: rowBg, cover: cover, name: name, info: info, button: button};
			rows.push(row);

			add(rowBg);
			add(cover);
			add(name);
			add(info);
			add(button);
		}

		layoutRows();
	}

	function layoutRows():Void
	{
		for (i in 0...rows.length)
		{
			var r:ModRow = rows[i];
			var slot:Int = i - scroll;
			var show:Bool = slot >= 0 && slot < VISIBLE;
			var y:Float = ROW_START + slot * ROW_H;

			r.bg.y = y;
			r.cover.y = y + 10;
			r.name.y = y + 14;
			r.info.y = y + 48;
			r.button.y = y + 20;

			r.bg.visible = show;
			r.cover.visible = show;
			r.name.visible = show;
			r.info.visible = show;
			r.button.visible = show;
			r.button.active = show && !busy;
		}

		upButton.active = !busy;
		downButton.active = !busy;
	}

	function scrollBy(delta:Int):Void
	{
		var maxScroll:Int = Std.int(Math.max(0, mods.length - VISIBLE));
		scroll = Std.int(Math.max(0, Math.min(maxScroll, scroll + delta)));
		layoutRows();
	}

	function fetchCovers(list:Array<OnlineMod>):Void
	{
		Thread.create(() ->
		{
			for (i in 0...list.length)
			{
				var path:String = OnlineMods.fetchCover(list[i]);
				if (path != null)
					events.add({kind: 'cover', index: i, path: path});
			}
		});
	}

	function setCover(index:Int, path:String):Void
	{
		if (index < 0 || index >= rows.length || !FileSystem.exists(path))
			return;

		var graphic = Paths.cacheBitmap(path);
		if (graphic == null)
			return;

		var cover:FlxSprite = rows[index].cover;
		cover.loadGraphic(graphic);
		cover.setGraphicSize(72, 72);
		cover.updateHitbox();
	}

	function download(index:Int):Void
	{
		if (busy)
			return;

		busy = true;
		status.text = 'Iniciando ' + mods[index].name + '...';
		layoutRows();

		var mod:OnlineMod = mods[index];
		Thread.create(() ->
		{
			try
			{
				OnlineMods.install(mod, function(phase:String)
				{
					events.add({kind: 'phase', text: phase + ' ' + mod.name + '...'});
				});
				events.add({kind: 'done', index: index, ok: true, error: null});
			}
			catch (e:Dynamic)
			{
				events.add({kind: 'done', index: index, ok: false, error: Std.string(e)});
			}
		});
	}

	function infoLine(m:OnlineMod):String
	{
		var parts:Array<String> = [];
		if (m.version != '') parts.push('v' + m.version);
		if (m.author != '') parts.push(m.author);
		if (m.size > 0) parts.push(Std.string(Math.round(m.size / 1048576 * 10) / 10) + ' MB');
		return parts.join('  ·  ');
	}

	function goBack():Void
	{
		if (busy)
			return;
		MusicBeatState.switchState(new FreeplayState());
	}
}
