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

	var prefix:String;
	var scroll:Int = 0;

	public function new(x:Float, y:Float, w:Int, h:Int, visibleRows:Int, prefix:String, color:Int, cb:Int->Void)
	{
		this.prefix = prefix;
		onChange = cb;
		main = new MpButton(x, y, w, h, '', color, function() {});
		for (i in 0...visibleRows)
			rows.push(new MpButton(x, y + h + 2 + i * 34, w, 32, '', 0xFF1C2631, function() {}));
		show(false);
	}

	public function setOptions(list:Array<String>, sel:Int):Void
	{
		options = list;
		selected = sel < 0 || sel >= list.length ? 0 : sel;
		scroll = Std.int(Math.max(0, Math.min(selected, Math.max(0, options.length - rows.length))));
		refresh();
	}

	public function show(v:Bool):Void
	{
		shown = v;
		main.show(v);
		if (!v)
			open = false;
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
		refreshRows();
	}

	public function update():Bool
	{
		if (!shown)
			return false;
		if (main.clicked())
		{
			setOpen(!open);
			return true;
		}
		if (!open)
			return false;
		if (FlxG.mouse.wheel != 0)
		{
			scroll = Std.int(Math.max(0, Math.min(scroll - FlxG.mouse.wheel, Math.max(0, options.length - rows.length))));
			refreshRows();
		}
		for (i in 0...rows.length)
		{
			if (rows[i].clicked())
			{
				var idx:Int = scroll + i;
				if (idx < options.length)
				{
					selected = idx;
					setOpen(false);
					refresh();
					if (onChange != null)
						onChange(idx);
				}
				return true;
			}
		}
		if (FlxG.mouse.justPressed)
		{
			setOpen(false);
			return true;
		}
		return false;
	}
}
