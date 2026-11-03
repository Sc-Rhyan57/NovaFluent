package hxcodec.flixel;

#if (VIDEOS_ALLOWED && hxvlc && !hxCodec)
import openfl.display.Sprite;
import openfl.display.BitmapData;
import hxvlc.flixel.FlxVideoSprite;
import flixel.util.FlxSignal;
import flixel.FlxG;

class FlxVideo extends Sprite {
    var videoSprite:FlxVideoSprite;

    public var onTextureSetup:FlxSignal;
    public var onEndReached:FlxSignal;
    public var onOpening:FlxSignal;

    public var bitmapData(get, never):BitmapData;

    public function new(?x:Float = 0, ?y:Float = 0) {
        super();
        this.x = x;
        this.y = y;
        this.alpha = 0;

        videoSprite = new FlxVideoSprite(0, 0);
        videoSprite.visible = false;

        onTextureSetup = new FlxSignal();
        onEndReached = new FlxSignal();
        onOpening = new FlxSignal();

        videoSprite.bitmap.onFormatSetup.add(function() {
            onTextureSetup.dispatch();
        });
        videoSprite.bitmap.onEndReached.add(function() {
            onEndReached.dispatch();
        });
        videoSprite.bitmap.onOpening.add(function() {
            onOpening.dispatch();
        });

        FlxG.state.add(videoSprite);
    }

    public function play(?path:String, ?loop:Bool):Bool {
        if (path != null) {
            var loops:Int = (loop == true) ? 65545 : 0;
            var options:Array<String> = (loop == true) ? ['input-repeat=65545'] : null;
            videoSprite.load(path, loops, options);
        }
        return videoSprite.play();
    }

    public function pause():Void {
        videoSprite.pause();
    }

    public function resume():Void {
        videoSprite.resume();
    }

    public function stop():Void {
        videoSprite.stop();
    }

    public function dispose():Void {
        stop();
        if (videoSprite != null) {
            FlxG.state.remove(videoSprite);
            videoSprite.destroy();
            videoSprite = null;
        }
    }

    function get_bitmapData():BitmapData {
        if (videoSprite != null && videoSprite.bitmap != null && videoSprite.bitmap.frames != null && videoSprite.bitmap.frames.parent != null) {
            return videoSprite.bitmap.frames.parent.bitmap;
        }
        return null;
    }
}
#elseif (VIDEOS_ALLOWED && hxCodec)
#end
