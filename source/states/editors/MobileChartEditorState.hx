package states.editors;

import flixel.FlxG;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.ui.FlxButton;
import states.editors.content.MetaNote;
import mobile.objects.Hitbox;
import mobile.objects.TouchButton;

/**
 * MobileChartEditorState
 * -----------------------
 * Es el Chart Editor de siempre (hereda TODO de ChartingState, no duplica
 * nada), con 3 agregados:
 *
 *   1) "Hitbox Mode": muestra el botón "Iniciar canción".
 *   2) "Iniciar canción": arranca el instrumental y aparece el Hitbox NATIVO
 *      de Psych Android (el mismo objects/mobile.Hitbox que usás en
 *      gameplay real). Cada vez que tocás una zona, se agrega una nota
 *      nueva al chart en ese carril, en el tiempo exacto en que tocaste.
 *   3) "Large Sustain Notes": con esto activado, cuanto más tiempo mantengas
 *      apretada la zona, más larga sale la nota (sostenida).
 */
class MobileChartEditorState extends ChartingState
{
	var hitboxModeOn:Bool = false;
	var largeSustainOn:Bool = false;
	var recordingActive:Bool = false;

	var hitboxModeBtn:FlxButton;
	var largeSustainBtn:FlxButton;
	var startSongBtn:FlxButton;
	var stopSongBtn:FlxButton;

	var hitbox:Hitbox;
	var laneButtons:Array<TouchButton> = [];
	var hitboxHoldStart:Array<Float> = [-1, -1, -1, -1];
	var hitboxHoldNote:Array<MetaNote> = [null, null, null, null];

	override function create()
	{
		super.create();
		buildMobileEditorButtons();
	}

	function buildMobileEditorButtons()
	{
		hitboxModeBtn = new FlxButton(FlxG.width - 220, 10, 'Hitbox Mode', toggleHitboxMode);
		hitboxModeBtn.setGraphicSize(200, 44);
		hitboxModeBtn.updateHitbox();
		hitboxModeBtn.color = FlxColor.ORANGE;
		add(hitboxModeBtn);

		largeSustainBtn = new FlxButton(FlxG.width - 220, 60, 'Large Sustain Notes', toggleLargeSustain);
		largeSustainBtn.setGraphicSize(200, 44);
		largeSustainBtn.updateHitbox();
		largeSustainBtn.color = FlxColor.GRAY;
		add(largeSustainBtn);

		startSongBtn = new FlxButton(FlxG.width - 220, 110, 'Iniciar canción', startRecording);
		startSongBtn.setGraphicSize(200, 44);
		startSongBtn.updateHitbox();
		startSongBtn.color = FlxColor.LIME;
		startSongBtn.visible = startSongBtn.active = false;
		add(startSongBtn);

		stopSongBtn = new FlxButton(FlxG.width - 220, 160, 'Detener', stopRecording);
		stopSongBtn.setGraphicSize(200, 44);
		stopSongBtn.updateHitbox();
		stopSongBtn.color = FlxColor.RED;
		stopSongBtn.visible = stopSongBtn.active = false;
		add(stopSongBtn);
	}

	function toggleHitboxMode()
	{
		hitboxModeOn = !hitboxModeOn;
		hitboxModeBtn.color = hitboxModeOn ? FlxColor.LIME : FlxColor.ORANGE;
		startSongBtn.visible = startSongBtn.active = hitboxModeOn;
		if (!hitboxModeOn)
			stopRecording();
	}

	function toggleLargeSustain()
	{
		largeSustainOn = !largeSustainOn;
		largeSustainBtn.color = largeSustainOn ? FlxColor.LIME : FlxColor.GRAY;
	}

	// ------------------------------------------------------------------
	// GRABACIÓN TOCANDO EL HITBOX NATIVO
	// ------------------------------------------------------------------
	function startRecording()
	{
		if (recordingActive)
			return;

		recordingActive = true;
		startSongBtn.visible = startSongBtn.active = false;
		stopSongBtn.visible = stopSongBtn.active = true;

		FlxG.sound.playMusic(Paths.inst(PlayState.SONG.song), 1, false);

		hitbox = new Hitbox();
		add(hitbox);

		laneButtons = [hitbox.buttonLeft, hitbox.buttonDown, hitbox.buttonUp, hitbox.buttonRight];

		hitbox.onButtonDown.add(onHitboxDown);
		hitbox.onButtonUp.add(onHitboxUp);
	}

	function stopRecording()
	{
		recordingActive = false;
		startSongBtn.visible = startSongBtn.active = hitboxModeOn;
		stopSongBtn.visible = stopSongBtn.active = false;

		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();

		if (hitbox != null)
		{
			hitbox.onButtonDown.remove(onHitboxDown);
			hitbox.onButtonUp.remove(onHitboxUp);
			remove(hitbox, true);
			hitbox.destroy();
			hitbox = null;
		}
		laneButtons = [];

		for (i in 0...4)
		{
			hitboxHoldStart[i] = -1;
			hitboxHoldNote[i] = null;
		}

		notes.sort(PlayState.sortByTime);
		updateChartData();
	}

	function laneOf(btn:TouchButton):Int
	{
		return laneButtons.indexOf(btn);
	}

	function onHitboxDown(btn:TouchButton)
	{
		if (!recordingActive)
			return;
		var lane:Int = laneOf(btn);
		if (lane < 0)
			return;
		beginNoteAtLane(lane);
	}

	function onHitboxUp(btn:TouchButton)
	{
		if (!recordingActive)
			return;
		var lane:Int = laneOf(btn);
		if (lane < 0)
			return;
		finishNoteAtLane(lane);
	}

	function sectionForTime(t:Float):Int
	{
		var sec = 0;
		while (cachedSectionTimes[sec + 1] != null && cachedSectionTimes[sec + 1] <= t)
			sec++;
		return sec;
	}

	function beginNoteAtLane(lane:Int)
	{
		if (hitboxHoldStart[lane] >= 0)
			return; // ya está tocada esta flecha, no duplicar

		var strumTime:Float = FlxG.sound.music != null ? FlxG.sound.music.time : 0;
		var secNum:Int = sectionForTime(strumTime);
		var noteData:Int = lane + 4; // lado del jugador (mustPress), carriles 4-7

		var noteAdded:MetaNote = createNote([strumTime, noteData, 0], secNum);
		notes.push(noteAdded);
		curRenderedNotes.add(noteAdded);

		hitboxHoldStart[lane] = strumTime;
		hitboxHoldNote[lane] = noteAdded;
	}

	function finishNoteAtLane(lane:Int)
	{
		var note:MetaNote = hitboxHoldNote[lane];
		if (note != null && largeSustainOn && FlxG.sound.music != null)
		{
			var heldMs:Float = FlxG.sound.music.time - hitboxHoldStart[lane];
			if (heldMs > 50) // ignora toques mínimos, no vale la pena hacerlos sostenidos
			{
				var secNum:Int = sectionForTime(hitboxHoldStart[lane]);
				note.setSustainLength(heldMs, cachedSectionCrochets[secNum] / 4, curZoom);
			}
		}
		hitboxHoldStart[lane] = -1;
		hitboxHoldNote[lane] = null;
	}
}
