package general.backend;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;

class MpButton
{
	public var bg:FlxSprite;
	public var shadow:FlxSprite;
	public var label:FlxText;
	public var onClick:Void->Void;
	public var enabled:Bool = true;
	public var shown:Bool = false;

	var bw:Int;
	var bh:Int;

	public function new(x:Float, y:Float, w:Int, h:Int, text:String, color:Int, cb:Void->Void)
	{
		bw = w;
		bh = h;
		onClick = cb;

		shadow = new FlxSprite(x + 2, y + 3).makeGraphic(w, h, 0xFF05080B);
		bg = new FlxSprite(x, y).makeGraphic(w, h, color);
		label = new FlxText(x, y, 0, text, 18);
		label.color = FlxColor.WHITE;

		shadow.scrollFactor.set();
		bg.scrollFactor.set();
		label.scrollFactor.set();

		setLabel(text);
		show(false);
	}

	public function setLabel(text:String):Void
	{
		label.text = text;
		label.x = bg.x + (bw - label.width) / 2;
		label.y = bg.y + (bh - label.height) / 2;
	}

	public function setColor(color:Int):Void
	{
		bg.makeGraphic(bw, bh, color);
	}

	public function show(v:Bool):Void
	{
		shown = v;
		shadow.visible = v;
		shadow.active = v;
		bg.visible = v;
		bg.active = v;
		label.visible = v;
		label.active = v;
	}

	public function setEnabled(v:Bool):Void
	{
		enabled = v;
		var a:Float = v ? 1 : 0.45;
		bg.alpha = a;
		label.alpha = a;
		shadow.alpha = a;
	}

	public function clicked():Bool
	{
		return shown && enabled && FlxG.mouse.justPressed && FlxG.mouse.overlaps(bg);
	}
}
