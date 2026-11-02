package states.onlineModsState;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.ui.FlxInputText;
import flixel.math.FlxRect;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import general.backend.GameBananaApi;
import general.backend.GameBananaApi.GbResult;
import general.backend.MpButton;
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
	var button:MpButton;
};

class OnlineModsState extends MusicBeatState
{
	static inline final PX:Int = 40;
	static inline final ROW_H:Int = 96;
	static inline final ROW_START:Int = 128;
	static inline final VISIBLE:Int = 4;
	static inline final BAR_W:Int = 1200;
	static inline final BAR_Y:Int = 600;
	static inline final C_BG:Int = 0xFF0B0F14;
	static inline final C_PANEL:Int = 0xFF141B23;
	static inline final C_ROW:Int = 0xFF1C2631;
	static inline final C_TEXT:Int = 0xFFEAF2FF;
	static inline final C_MUTED:Int = 0xFF8A97A8;
	static inline final C_ACCENT:Int = 0xFF52FCC0;
	static inline final B_PRIMARY:Int = 0xFF178A69;
	static inline final B_NEUTRAL:Int = 0xFF2A3644;
	static inline final B_DONE:Int = 0xFF2F4A3D;

	var events:Deque<Dynamic> = new Deque();
	var mods:Array<OnlineMod> = [];
	var rows:Array<ModRow> = [];
	var buttons:Array<MpButton> = [];
	var scroll:Int = 0;
	var busy:Bool = false;
	var source:String = 'nova';
	var gen:Int = 0;
	var gbPage:Int = 1;
	var gbQuery:String = '';
	var gbMore:Bool = false;
	var tabNova:MpButton;
	var tabGb:MpButton;
	var searchButton:MpButton;
	var prevButton:MpButton;
	var nextButton:MpButton;
	var searchInput:FlxInputText;

	var status:FlxText;
	var barBg:FlxSprite;
	var barFill:FlxSprite;
	var barText:FlxText;
	var upButton:MpButton;
	var downButton:MpButton;
	var backButton:MpButton;

	override function create():Void
	{
		super.create();

		add(new FlxSprite().makeGraphic(FlxG.width, FlxG.height, C_BG));
		add(new FlxSprite(PX, 24).makeGraphic(FlxG.width - PX * 2, 84, C_PANEL));

		var title:FlxText = new FlxText(PX + 24, 40, FlxG.width - PX * 2 - 48, 'MODS ONLINE', 34);
		title.color = C_TEXT;
		add(title);

		var subtitle:FlxText = new FlxText(PX + 24, 80, FlxG.width - PX * 2 - 48, 'Baixe mods direto da lista do NovaFlare. Cada download é verificado antes de instalar.', 15);
		subtitle.color = C_MUTED;
		add(subtitle);

		status = new FlxText(PX, 560, FlxG.width - PX * 2, 'Carregando lista...', 18);
		status.color = C_ACCENT;
		add(status);

		barBg = new FlxSprite(PX, BAR_Y).makeGraphic(BAR_W, 20, 0xFF1A222C);
		barFill = new FlxSprite(PX, BAR_Y).makeGraphic(BAR_W, 20, C_ACCENT);
		barFill.clipRect = FlxRect.get(0, 0, 0, 20);
		barText = new FlxText(PX, BAR_Y + 26, BAR_W, '', 15);
		barText.color = C_MUTED;
		add(barBg);
		add(barFill);
		add(barText);

		upButton = track(new MpButton(FlxG.width - PX - 150, ROW_START, 150, 44, 'SOBE', B_NEUTRAL, function() scrollBy(-1)));
		downButton = track(new MpButton(FlxG.width - PX - 150, ROW_START + VISIBLE * ROW_H - 16, 150, 44, 'DESCE', B_NEUTRAL, function() scrollBy(1)));
		backButton = track(new MpButton(PX, FlxG.height - 64, 220, 46, 'VOLTAR', B_NEUTRAL, goBack));
		upButton.show(true);
		downButton.show(true);
		backButton.show(true);

		tabNova = track(new MpButton(FlxG.width - PX - 340, 42, 160, 40, 'NOVAFLARE', B_PRIMARY, function() setSource('nova')));
		tabGb = track(new MpButton(FlxG.width - PX - 170, 42, 160, 40, 'GAMEBANANA', B_NEUTRAL, function() setSource('gb')));
		tabNova.show(true);
		tabGb.show(true);

		searchInput = new FlxInputText(PX + 240, FlxG.height - 58, 480, '', 18);
		searchInput.visible = false;
		searchInput.active = false;
		add(searchInput);
		searchButton = track(new MpButton(PX + 740, FlxG.height - 64, 140, 46, 'BUSCAR', B_PRIMARY, doSearch));
		prevButton = track(new MpButton(PX + 900, FlxG.height - 64, 130, 46, 'ANTERIOR', B_NEUTRAL, function() changePage(-1)));
		nextButton = track(new MpButton(PX + 1050, FlxG.height - 64, 150, 46, 'PRÓXIMA', B_NEUTRAL, function() changePage(1)));

		loadSource();
	}

	function setSource(next:String):Void
	{
		if (busy || next == source)
			return;
		source = next;
		scroll = 0;
		gbPage = 1;
		tabNova.setColor(source == 'nova' ? B_PRIMARY : B_NEUTRAL);
		tabGb.setColor(source == 'gb' ? B_PRIMARY : B_NEUTRAL);
		loadSource();
	}

	function loadSource():Void
	{
		gen++;
		var mine:Int = gen;
		var gb:Bool = source == 'gb';

		clearRows();
		mods = [];
		scroll = 0;

		searchInput.visible = gb;
		searchInput.active = gb;
		searchButton.show(gb);
		prevButton.show(gb);
		nextButton.show(gb);
		updatePager();

		if (gb)
		{
			status.text = 'Buscando no GameBanana...';
			GameBananaApi.search(gbQuery, gbPage, function(res:GbResult, error:String)
			{
				events.add({kind: 'gblist', gen: mine, res: res, error: error});
			});
			return;
		}

		status.text = 'Carregando lista...';
		Thread.create(() -> OnlineMods.fetchList(function(list:Array<OnlineMod>, error:String)
		{
			events.add({kind: 'list', gen: mine, mods: list, error: error});
		}));
	}

	function doSearch():Void
	{
		if (busy || source != 'gb')
			return;
		gbQuery = StringTools.trim(searchInput.text);
		gbPage = 1;
		loadSource();
	}

	function changePage(delta:Int):Void
	{
		if (busy || source != 'gb')
			return;
		var next:Int = gbPage + delta;
		if (next < 1 || (delta > 0 && !gbMore))
			return;
		gbPage = next;
		loadSource();
	}

	function updatePager():Void
	{
		prevButton.setEnabled(source == 'gb' && gbPage > 1 && !busy);
		nextButton.setEnabled(source == 'gb' && gbMore && !busy);
		searchButton.setEnabled(source == 'gb' && !busy);
		tabNova.setEnabled(!busy);
		tabGb.setEnabled(!busy);
	}

	function clearRows():Void
	{
		for (r in rows)
		{
			remove(r.bg, true);
			remove(r.cover, true);
			remove(r.name, true);
			remove(r.info, true);
			remove(r.button.shadow, true);
			remove(r.button.bg, true);
			remove(r.button.label, true);
			buttons.remove(r.button);
			r.bg.destroy();
			r.cover.destroy();
			r.name.destroy();
			r.info.destroy();
			r.button.shadow.destroy();
			r.button.bg.destroy();
			r.button.label.destroy();
		}
		rows = [];
	}

	function track(b:MpButton):MpButton
	{
		add(b.shadow);
		add(b.bg);
		add(b.label);
		buttons.push(b);
		return b;
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

		for (b in buttons)
		{
			if (b.clicked())
			{
				b.onClick();
				break;
			}
		}

		if (source == 'gb' && searchInput.hasFocus && FlxG.keys.justPressed.ENTER)
			doSearch();

		if (controls.BACK && !(searchInput != null && searchInput.hasFocus))
			goBack();
	}

	function handle(ev:Dynamic):Void
	{
		switch (ev.kind)
		{
			case 'gblist':
				if (ev.gen != gen)
					return;
				if (ev.error != null || ev.res == null)
				{
					general.backend.NFLog.warn('mods', 'GameBanana indisponível: ' + ev.error);
					mods = [];
					gbMore = false;
					buildRows();
					updatePager();
					status.text = 'Falha no GameBanana: ' + ev.error;
					return;
				}
				var res:GbResult = ev.res;
				mods = res.mods;
				gbMore = res.more;
				buildRows();
				updatePager();
				status.text = mods.length == 0 ? 'Nada encontrado no GameBanana.' : 'GameBanana — página ' + gbPage + '. Escolha um mod para baixar.';
				fetchCovers(mods);

			case 'list':
				if (ev.gen != gen)
					return;
				if (ev.error != null || ev.mods == null)
				{
					general.backend.NFLog.warn('mods', 'lista online indisponível: ' + ev.error);
					mods = [];
					buildRows();
					status.text = 'Não há mods online ou erro com a conexão.';
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
				if (ev.gen == gen)
					setCover(ev.index, ev.path);

			case 'phase':
				if (ev.progress < 0)
					setProgress(0, ev.text);
				else
					setProgress(ev.progress, ev.text + '  ' + Math.round(ev.progress * 100) + '%');

			case 'done':
				busy = false;
				updatePager();
				if (ev.ok)
				{
					var mod:OnlineMod = mods[ev.index];
					rows[ev.index].button.setLabel('INSTALADO');
					rows[ev.index].button.setColor(B_DONE);
					rows[ev.index].button.setEnabled(false);
					status.text = 'Pronto: ' + mod.name + '. Ative em Mods para usar.';
					setProgress(1, 'Concluído');
				}
				else
				{
					status.text = 'Falhou: ' + ev.error;
					setProgress(0, 'Erro no download');
				}
				layoutRows();
		}
	}

	function setProgress(p:Float, text:String):Void
	{
		var clamped:Float = Math.max(0, Math.min(1, p));
		barFill.clipRect = FlxRect.get(0, 0, Std.int(BAR_W * clamped), 20);
		barText.text = text;
	}

	function buildRows():Void
	{
		var panelW:Int = FlxG.width - PX * 2;

		for (i in 0...mods.length)
		{
			var m:OnlineMod = mods[i];
			var index:Int = i;

			var rowBg:FlxSprite = new FlxSprite(PX, 0).makeGraphic(panelW, ROW_H - 10, C_ROW);
			var cover:FlxSprite = new FlxSprite(PX + 12, 0).makeGraphic(64, 64, 0xFF2A323C);
			var name:FlxText = new FlxText(PX + 92, 0, panelW - 300, m.name, 22);
			name.color = C_TEXT;
			var info:FlxText = new FlxText(PX + 92, 0, panelW - 300, infoLine(m), 14);
			info.color = C_MUTED;

			add(rowBg);
			add(cover);
			add(name);
			add(info);

			var installed:Bool = FileSystem.exists(Paths.mods(m.folder));
			var button:MpButton = track(new MpButton(FlxG.width - PX - 186, 0, 150, 40, installed ? 'INSTALADO' : 'BAIXAR', installed ? B_DONE : B_PRIMARY,
				function() download(index)));
			button.setEnabled(!installed);

			rows.push({bg: rowBg, cover: cover, name: name, info: info, button: button});
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
			r.cover.y = y + 12;
			r.name.y = y + 12;
			r.info.y = y + 46;
			r.button.bg.y = y + 22;
			r.button.label.y = y + 22 + (40 - r.button.label.height) / 2;
			r.button.shadow.y = y + 25;

			r.bg.visible = show;
			r.cover.visible = show;
			r.name.visible = show;
			r.info.visible = show;
			r.button.show(show);
			if (show && !busy && r.button.enabled)
				r.button.setEnabled(true);
			else if (busy)
				r.button.setEnabled(false);
		}

		upButton.setEnabled(!busy);
		downButton.setEnabled(!busy);
	}

	function scrollBy(delta:Int):Void
	{
		var maxScroll:Int = Std.int(Math.max(0, mods.length - VISIBLE));
		scroll = Std.int(Math.max(0, Math.min(maxScroll, scroll + delta)));
		layoutRows();
	}

	function fetchCovers(list:Array<OnlineMod>):Void
	{
		var mine:Int = gen;
		Thread.create(() ->
		{
			for (i in 0...list.length)
			{
				if (mine != gen)
					return;
				var path:String = OnlineMods.fetchCover(list[i]);
				if (path != null)
					events.add({kind: 'cover', gen: mine, index: i, path: path});
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
		cover.setGraphicSize(64, 64);
		cover.updateHitbox();
	}

	function download(index:Int):Void
	{
		if (busy)
			return;

		busy = true;
		var mod:OnlineMod = mods[index];
		status.text = 'Iniciando ' + mod.name + '...';
		setProgress(0, 'Iniciando download');
		updatePager();
		layoutRows();

		Thread.create(() ->
		{
			try
			{
				var onPhase:String->Float->Void = function(phase:String, progress:Float)
				{
					events.add({kind: 'phase', text: phase + ' ' + mod.name, progress: progress});
				};
				if (GameBananaApi.isGb(mod))
					GameBananaApi.install(mod, onPhase);
				else
					OnlineMods.install(mod, onPhase);
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
		if (GameBananaApi.isGb(m)) parts.push('GameBanana');
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
