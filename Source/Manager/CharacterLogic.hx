package manager;

typedef CharacterSpeaker = {
	var id:String;
	var name:String;
	var frameH:Int;
}

class CharacterLogic {
	public static function matchesSpeaker(speaker:String, c:CharacterSpeaker):Bool {
		if (speaker == null) return false;
		if (speaker == c.id) return true;
		if (speaker == c.name) return true;
		if (StringTools.endsWith(c.name, speaker)) return true;
		if (StringTools.startsWith(c.name, speaker)) return true;
		return false;
	}

	public static function stripOriginY(frameH:Int, strip:Int):Int {
		return strip * frameH;
	}
}
