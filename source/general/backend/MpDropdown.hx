package general.backend;

import flixel.FlxG;

class MpDropdown
{
	public var main:MpButton;
	public var rows:Array<MpButton> = [];
	public var options:Array<String> = [];
	public var selected:Int = 0;
	public var open:Bool = false;
	public var shown:Bool = false;
	public var onChange:Int->Void;

	static final STEP:Int = 34;
	static final DRAG_THRESHOLD:Float = 8;

	var prefix:String;
	var scroll:Int = 0;
	var pressing:Bool = false;
	var dragging:Bool = false;
	var startY:Float = 0;
	var startScroll:Int = 0;

	public function new(x:Float, y:Float, w:Int, h:Int, visibleRows:Int, prefix:String, color:Int, cb:Int->Void)
	{
		this.prefix = prefix;
		onChange = cb;
		main = new MpButton(x, y, w, h, '', color, function() {});
		for (i in 0...visibleRows)
			rows.push(new MpButton(x, y + h + 2 + i * STEP, w, 32, '', 0xFF1C2631, function() {}));
		show(false);
	}

	public function setOptions(list:Array<String>, sel:Int):Void
	{
		options = list;
		selected = sel < 0 || sel >= list.length ? 0 : sel;
		scroll = clampScroll(selected);
		refresh();
	}

	function clampScroll(v:Int):Int
	{
		return Std.int(Math.max(0, Math.min(v, Math.max(0, options.length - rows.length))));
	}

	public function show(v:Bool):Void
	{
		shown = v;
		main.show(v);
		if (!v)
		{
			open = false;
			pressing = false;
			dragging = false;
		}
		refreshRows();
	}

	public function refresh():Void
	{
		main.setLabel(prefix + ': ' + (options.length == 0 ? '-' : options[selected]) + '  v');
		refreshRows();
	}

	function refreshRows():Void
	{
		for (i in 0...rows.length)
		{
			var idx:Int = scroll + i;
			var visible:Bool = shown && open && idx < options.length;
			if (visible)
				rows[i].setLabel((idx == selected ? '> ' : '') + options[idx]);
			rows[i].show(visible);
		}
	}

	public function setOpen(v:Bool):Void
	{
		open = v && shown && options.length > 0;
		pressing = false;
		dragging = false;
		if (open)
			scroll = clampScroll(selected);
		refreshRows();
	}

	public function hover():Void
	{
		if (!shown)
			return;
		main.hover();
		if (open && !dragging)
			for (r in rows)
				r.hover();
	}

	function overRows(px:Float, py:Float):Bool
	{
		for (r in rows)
			if (r.shown && px >= r.bg.x && px <= r.bg.x + r.bg.width && py >= r.bg.y && py <= r.bg.y + r.bg.height)
				return true;
		return false;
	}

	function rowAt(px:Float, py:Float):Int
	{
		for (i in 0...rows.length)
		{
			var r:MpButton = rows[i];
			if (r.shown && px >= r.bg.x && px <= r.bg.x + r.bg.width && py >= r.bg.y && py <= r.bg.y + r.bg.height)
				return i;
		}
		return -1;
	}

	public function update():Bool
	{
		if (!shown)
			return false;
		var px:Float = FlxG.mouse.x;
		var py:Float = FlxG.mouse.y;

		if (FlxG.mouse.justPressed && main.enabled && FlxG.mouse.overlaps(main.bg))
		{
			main.clicked();
			setOpen(!open);
			return true;
		}
		if (!open)
			return false;

		if (FlxG.mouse.justPressed)
		{
			if (overRows(px, py))
			{
				pressing = true;
				dragging = false;
				startY = py;
				startScroll = scroll;
				return true;
			}
			setOpen(false);
			return true;
		}

		if (pressing)
		{
			var dy:Float = py - startY;
			if (!dragging && Math.abs(dy) > DRAG_THRESHOLD)
				dragging = true;
			if (dragging)
			{
				var target:Int = clampScroll(startScroll - Math.round(dy / STEP));
				if (target != scroll)
				{
					scroll = target;
					refreshRows();
				}
			}
			if (FlxG.mouse.justReleased)
			{
				var wasDragging:Bool = dragging;
				pressing = false;
				dragging = false;
				if (!wasDragging)
				{
					var i:Int = rowAt(px, py);
					if (i != -1)
					{
						var idx:Int = scroll + i;
						if (idx < options.length)
						{
							rows[i].clicked();
							selected = idx;
							setOpen(false);
							refresh();
							if (onChange != null)
								onChange(idx);
						}
					}
				}
			}
			return true;
		}

		if (FlxG.mouse.wheel != 0)
		{
			scroll = clampScroll(scroll - FlxG.mouse.wheel);
			refreshRows();
			return true;
		}
		return overRows(px, py);
	}
}
