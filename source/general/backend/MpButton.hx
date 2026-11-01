package general.backend;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
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
	var hovering:Bool = false;
	var scaleTween:FlxTween;

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

	function scaleTo(target:Float, time:Float, ease:Float->Float):Void
	{
		if (scaleTween != null)
			scaleTween.cancel();
		scaleTween = FlxTween.tween(bg.scale, {x: target, y: target}, time, {
			ease: ease,
			onUpdate: function(_)
			{
				shadow.scale.set(bg.scale.x, bg.scale.y);
				label.scale.set(bg.scale.x, bg.scale.y);
			}
		});
	}

	public function hover():Void
	{
		if (!shown || !enabled)
			return;
		var over:Bool = FlxG.mouse.overlaps(bg);
		if (over != hovering)
		{
			hovering = over;
			scaleTo(over ? 1.04 : 1, 0.12, FlxEase.quadOut);
		}
	}

	function pressAnim():Void
	{
		bg.scale.set(0.92, 0.92);
		shadow.scale.set(0.92, 0.92);
		label.scale.set(0.92, 0.92);
		scaleTo(hovering ? 1.04 : 1, 0.28, FlxEase.backOut);
	}

	public function show(v:Bool):Void
	{
		if (!v)
		{
			if (scaleTween != null)
				scaleTween.cancel();
			hovering = false;
			bg.scale.set(1, 1);
			shadow.scale.set(1, 1);
			label.scale.set(1, 1);
		}
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
		var hit:Bool = shown && enabled && FlxG.mouse.justPressed && FlxG.mouse.overlaps(bg);
		if (hit)
			pressAnim();
		return hit;
	}
}
