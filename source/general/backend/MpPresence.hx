package general.backend;

import general.backend.Discord;

/**
 * Presença do Discord para o multiplayer.
 * Só chama o Discord quando o texto realmente muda, para não repetir atualizações.
 */
class MpPresence
{
	static var last:String = null;

	public static function set(details:String, state:String):Void
	{
		#if DISCORD_ALLOWED
		var key:String = details + '\n' + state;
		if (key == last)
			return;
		last = key;
		DiscordClient.changePresence(details, state);
		#end
	}

	// Chamado ao abrir a tela de multiplayer, pois outra tela pode ter trocado a presença.
	public static function reset():Void
	{
		last = null;
	}
}
