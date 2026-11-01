package substates;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.FlxCamera;
import flixel.input.gamepad.FlxGamepadInputID;

class MpDeathSubstate extends MusicBeatSubstate
{
	var cam:FlxCamera;
	var chosen:Bool = false;

	public function new(cam:FlxCamera)
	{
		super();
		this.cam = cam;
	}

	override function create()
	{
		var bg:FlxSprite = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xB0000000);
		bg.scrollFactor.set();
		bg.cameras = [cam];
		add(bg);

		var title:FlxText = new FlxText(0, FlxG.height * 0.34, FlxG.width, 'VOCÊ MORREU', 56);
		title.setFormat(Paths.font('vcr.ttf'), 56, FlxColor.RED, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.scrollFactor.set();
		title.cameras = [cam];
		add(title);

		var help:FlxText = new FlxText(0, FlxG.height * 0.34 + 90, FlxG.width, 'ENTER / ESPAÇO / A  -  VER RESULTADOS\nB  -  VOLTAR AO LOBBY', 28);
		help.setFormat(Paths.font('vcr.ttf'), 28, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		help.scrollFactor.set();
		help.cameras = [cam];
		add(help);

		super.create();
	}

	function padPressed(id:FlxGamepadInputID):Bool
	{
		return FlxG.gamepads.anyJustPressed(id);
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if (chosen)
			return;

		var toLobby:Bool = controls.BACK || padPressed(FlxGamepadInputID.B);
		var toResults:Bool = controls.ACCEPT || FlxG.keys.justPressed.ENTER || FlxG.keys.justPressed.SPACE || padPressed(FlxGamepadInputID.A);

		if (toLobby)
			choose(false);
		else if (toResults)
			choose(true);
	}

	function choose(results:Bool):Void
	{
		chosen = true;
		var state:PlayState = PlayState.instance;
		close();
		if (state != null)
			state.mpLeaveAfterDeath(results);
	}
}
