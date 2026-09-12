extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")
const TONE_PATH: String = "user://gdss_test_tone.tres"

const FIXTURE: String = """
@resources {
	SFX_HOVER: sound("user://gdss_test_tone.tres")
	LOGO: texture("res://meta/icon.png")
}
Button {
	bg_color: "#202020"
	:hover {
		sfx: $SFX_HOVER
	}
	on_pressed() {
		sfx: $SFX_HOVER
	}
}
"""

const FIXTURE_RESTING: String = """
@resources {
	SFX_HOVER: sound("user://gdss_test_tone.tres")
}
Button {
	sfx: $SFX_HOVER
	:hover {
		bg_color: "#303030"
	}
}
"""

var _tone: AudioStreamWAV


func run(t: TC) -> void:
	if not _make_tone():
		print("SKIP could not write a test audio stream")
		return
	_check_declaration(t)
	_check_validation(t)
	_check_playback(t)
	_check_resting_block(t)
	GDSS.sfx_enabled = true
	t.restore_theme()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TONE_PATH))


func _make_tone() -> bool:
	_tone = AudioStreamWAV.new()
	_tone.data = PackedByteArray([0, 16, 0, 32, 0, 16, 0, 0])
	_tone.mix_rate = 22050
	return ResourceSaver.save(_tone, TONE_PATH) == OK


func _check_declaration(t: TC) -> void:
	t.check(GdssStylesheet.resource_methods().has("sound"), "sound() is discovered as a loader")
	var result: Dictionary = t.parse_fixture(FIXTURE)
	var hover: Variant = t.entry_val(result, "Button", "hover", "sfx")
	t.check(hover is Dictionary, "the state's sfx parses to a loader call")
	t.check_eq((hover as Dictionary).get("__gdss_method__"), "sound", "sfx uses the sound loader")
	t.check(t.entry_val(result, "Button", "on_pressed", "sfx") != null, "an event block can carry sfx")
	t.check(GDSS.get_resource("SFX_HOVER") is AudioStream, "get_resource resolves an audio key")
	t.check(GDSS.get_resource("NOPE") == null, "an unknown key resolves to null")


func _check_validation(t: TC) -> void:
	var clean: Array[Array] = t.validate_fixture(FIXTURE)
	t.check(clean.is_empty(), "the audio fixture validates clean (got: %s)" % ", ".join(t.error_messages(clean)))
	var wrong: Array[Array] = t.validate_fixture(FIXTURE.replace("sfx: $SFX_HOVER", "sfx: $LOGO"))
	t.check(t.has_error_containing(wrong, "is a texture(), which property 'sfx' cannot take"), "a texture on sfx is flagged")
	var bare: Array[Array] = t.validate_fixture(FIXTURE.replace("sfx: $SFX_HOVER", "sfx: \"user://gdss_test_tone.tres\""))
	t.check(t.has_error_containing(bare, "expects sound(\"res://...\") or a $resource"), "a bare path on sfx is flagged")
	var as_color: Array[Array] = t.validate_fixture(FIXTURE.replace("bg_color: \"#202020\"", "bg_color: $SFX_HOVER"))
	t.check(t.has_error_containing(as_color, "is a sound(), which property 'bg_color' cannot take"), "a sound on a colour property is flagged")


func _check_playback(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	GDSS.sfx_enabled = true
	var button: Button = t.make_styled_button()
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(button)
	t.check(stylebox != null, "the button binds")
	t.check(_streams().is_empty(), "binding alone plays nothing")
	_clear_voices()
	stylebox.current_state = "hover"
	t.check(_streams().size() == 1, "entering a state with sfx plays one voice")
	t.check(_streams().get(0) is AudioStream, "the voice got the declared stream")
	_clear_voices()
	stylebox.current_state = "normal"
	t.check(_streams().is_empty(), "leaving that state plays nothing")
	GDSS.sfx_enabled = false
	stylebox.current_state = "hover"
	t.check(_streams().is_empty(), "sfx_enabled = false silences it")
	GDSS.sfx_enabled = true
	GdssNodeBinder.unbind(button)
	button.free()


func _check_resting_block(t: TC) -> void:
	t.apply_fixture(FIXTURE_RESTING)
	var button: Button = t.make_styled_button()
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(button)
	_clear_voices()
	stylebox.current_state = "hover"
	t.check(_streams().is_empty(), "a state without sfx does not inherit the resting block's sound")
	GdssNodeBinder.unbind(button)
	button.free()


func _clear_voices() -> void:
	for player: AudioStreamPlayer in _players():
		player.stream = null


func _players() -> Array[AudioStreamPlayer]:
	var result: Array[AudioStreamPlayer] = []
	if GDSS._runtime != null:
		result.assign(GDSS._runtime._sfx_players)
	return result


func _streams() -> Array[AudioStream]:
	var result: Array[AudioStream] = []
	for player: AudioStreamPlayer in _players():
		if player.stream != null:
			result.append(player.stream)
	return result
