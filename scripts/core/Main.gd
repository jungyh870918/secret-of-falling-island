extends Node2D
## 게임 코디네이터. 입력 → 상호작용 → 결과 실행의 흐름을 이어 붙인다.
##
## 이 파일에도 특정 장면/퍼즐 분기는 없다.
## 클릭이 어떤 의미인지 판단해서 InteractionResolver 에 넘기는 일만 한다.
##
## 명세서 §21 상호작용 분해:
##   actor(항상 한개미) / action(동사) / target(핫스폿·아이템) / optional item(손에 든 것)
##   → InteractionResolver 가 preconditions 를 보고 result 또는 fallback dialogue 를 돌려준다.

enum Mode { TITLE, PLAY, PAUSE, SETTINGS, SAVE, LOAD, LOG }

const START_SCENE := "office_meeting_room"
const START_CHAPTER := "prologue"
const ENABLE_DEBUG := true
const KEYBOARD_WALK_SPEED := 90.0
const THUMBNAIL_INTERVAL := 1.5

var mode: int = Mode.TITLE
var busy := false                 ## 대사/결과 시퀀스 진행 중

var current_verb: int = Actions.Verb.LOOK
var held_item := ""

var world: Node2D
var ui_layer: CanvasLayer
var panel: CommandPanel
var subtitles: SubtitleLayer
var choice_box: ChoiceBox
var title_screen: TitleScreen
var pause_menu: MenuList
var settings_menu: MenuList
var save_menu: SaveSlotMenu
var log_view: LogView
var card: CardView
var cursor: GameCursor
var debug_panel: DebugPanel

var result_runner: ResultRunner
var dialogue_runner: DialogueRunner

var _hover_id := ""
var _thumb_timer := 0.0

## 대상까지 걸어가는 중인지. 이 상태에서는 클릭이 새 목표로 즉시 전환된다.
var walking_to_target := false
var _action_token := 0


func _ready() -> void:
	_register_input_actions()
	_build_tree()
	_apply_settings()
	_open_title()
	set_process(true)
	set_process_unhandled_input(true)


# ---------------------------------------------------------------- 구성

func _build_tree() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	SceneDirector.world_root = world

	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	ui_layer.layer = 1
	add_child(ui_layer)

	panel = CommandPanel.new()
	panel.name = "CommandPanel"
	ui_layer.add_child(panel)
	panel.verb_selected.connect(_on_verb_selected)
	panel.item_selected.connect(_on_item_selected)
	panel.item_examined.connect(_on_item_examined)
	panel.hint_requested.connect(_on_hint_requested)

	subtitles = SubtitleLayer.new()
	subtitles.name = "Subtitles"
	subtitles.location_provider = Callable(self, "_current_view")
	ui_layer.add_child(subtitles)

	choice_box = ChoiceBox.new()
	choice_box.name = "ChoiceBox"
	ui_layer.add_child(choice_box)

	result_runner = ResultRunner.new()
	result_runner.name = "ResultRunner"
	result_runner.subtitles = subtitles
	add_child(result_runner)
	result_runner.event_handler = Callable(self, "_on_event_requested")

	dialogue_runner = DialogueRunner.new()
	dialogue_runner.name = "DialogueRunner"
	dialogue_runner.subtitles = subtitles
	dialogue_runner.choice_box = choice_box
	dialogue_runner.result_runner = result_runner
	add_child(dialogue_runner)
	result_runner.dialogue_runner = dialogue_runner

	title_screen = TitleScreen.new()
	title_screen.name = "TitleScreen"
	ui_layer.add_child(title_screen)
	title_screen.activated.connect(_on_title_activated)

	pause_menu = MenuList.new()
	pause_menu.name = "PauseMenu"
	pause_menu.box = Rect2i(96, 40, 128, 100)
	ui_layer.add_child(pause_menu)
	pause_menu.activated.connect(_on_pause_activated)
	pause_menu.cancelled.connect(_resume)

	settings_menu = MenuList.new()
	settings_menu.name = "SettingsMenu"
	settings_menu.box = Rect2i(18, 2, 284, 176)
	settings_menu.row_h = 11
	ui_layer.add_child(settings_menu)
	settings_menu.activated.connect(_on_settings_activated)
	settings_menu.adjusted.connect(_on_settings_adjusted)
	settings_menu.cancelled.connect(_close_settings)

	save_menu = SaveSlotMenu.new()
	save_menu.name = "SaveMenu"
	ui_layer.add_child(save_menu)
	save_menu.activated.connect(func(_i): save_menu.choose())
	save_menu.slot_chosen.connect(_on_slot_chosen)
	save_menu.cancelled.connect(_close_save_menu)

	log_view = LogView.new()
	log_view.name = "LogView"
	ui_layer.add_child(log_view)

	card = CardView.new()
	card.name = "Card"
	ui_layer.add_child(card)

	if ENABLE_DEBUG:
		debug_panel = DebugPanel.new()
		debug_panel.name = "DebugPanel"
		ui_layer.add_child(debug_panel)

	cursor = GameCursor.new()
	cursor.name = "Cursor"
	ui_layer.add_child(cursor)   # 항상 맨 위


## project.godot 에 InputEvent 리소스를 손으로 적는 대신 런타임에 등록한다.
func _register_input_actions() -> void:
	_add_action("game_menu", [KEY_ESCAPE])
	_add_action("game_log", [KEY_TAB, KEY_L])
	_add_action("game_hint", [KEY_H])
	_add_action("game_quicksave", [KEY_F5])
	_add_action("game_quickload", [KEY_F9])
	_add_action("game_fullscreen", [KEY_F11])
	_add_action("game_confirm", [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER])
	_add_action("debug_toggle", [KEY_F1])
	_add_action("debug_page", [KEY_F2])
	_add_action("debug_reload", [KEY_F3])


func _add_action(action_name: String, keys: Array) -> void:
	if InputMap.has_action(action_name):
		InputMap.erase_action(action_name)
	InputMap.add_action(action_name)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action_name, ev)


func _current_view() -> LocationView:
	return SceneDirector.current_view


# ---------------------------------------------------------------- 게임 시작

func _open_title() -> void:
	mode = Mode.TITLE
	busy = false
	held_item = ""
	GameState.set_timer_paused(true)
	_hide_all_menus()
	panel.visible = false
	panel.set_held_item("")
	cursor.held_item = ""
	# 진행 중이던 장면은 정리한다. 타이틀 뒤에서 계속 돌아가면 안 된다.
	if SceneDirector.current_view != null and is_instance_valid(SceneDirector.current_view):
		SceneDirector.current_view.queue_free()
		SceneDirector.current_view = null
	title_screen.open("", _title_rows())
	AudioDirector.play_music("title")


func _title_rows() -> Array:
	var has_save := SaveManager.has_any_save()
	return [
		{"label": Loc.t("ui.title.new_game")},
		{"label": Loc.t("ui.title.continue"), "enabled": has_save},
		{"label": Loc.t("ui.title.load"), "enabled": has_save},
		{"label": Loc.t("ui.title.settings")},
		{"label": Loc.t("ui.title.quit")},
	]


func _on_title_activated(index: int) -> void:
	match index:
		0: _start_new_game()
		1: _continue_game()
		2: _open_save_menu(SaveSlotMenu.Mode.LOAD)
		3: _open_settings()
		4: get_tree().quit()


func _start_new_game() -> void:
	title_screen.close()
	panel.visible = true
	mode = Mode.PLAY
	GameState.reset()
	DialogueLog.clear()
	HintSystem.reset()
	GameState.chapter_id = START_CHAPTER
	current_verb = Actions.Verb.LOOK
	held_item = ""
	panel.set_verb(current_verb)
	panel.set_held_item("")
	GameState.set_timer_paused(false)

	var ch: Dictionary = GameData.chapters.get(GameState.chapter_id, {})
	var start_scene := str(ch.get("start_scene", START_SCENE))
	var start_entry := str(ch.get("start_entry", "default"))
	await SceneDirector.change_scene(start_scene, start_entry)
	await _run_chapter_intro()


func _continue_game() -> void:
	if not SaveManager.load_latest():
		return
	title_screen.close()
	panel.visible = true
	mode = Mode.PLAY
	HintSystem.reset()
	GameState.set_timer_paused(false)
	await SceneDirector.enter_scene_immediate(GameState.scene_id, "default", GameState.player_position)


func _run_chapter_intro() -> void:
	var ch: Dictionary = GameData.chapters.get(GameState.chapter_id, {})

	# §10 시작 소지품 — 사원증과 휴대전화는 프롤로그 내내 농담의 재료가 된다.
	for id in ch.get("starting_items", []):
		GameState.give_item(str(id))

	var intro = ch.get("intro_card", null)
	if intro is Array and not (intro as Array).is_empty():
		busy = true
		await card.show_card(intro, str(ch.get("intro_image", "")))
		busy = false
	var opening := str(ch.get("opening_dialogue", ""))
	if not opening.is_empty() and GameData.dialogues.has(opening):
		busy = true
		await dialogue_runner.play(opening)
		busy = false
	SaveManager.autosave()


# ---------------------------------------------------------------- 루프

func _process(delta: float) -> void:
	_update_thumbnail(delta)

	if mode != Mode.PLAY or busy:
		return

	var view := _current_view()
	if view == null:
		return

	GameState.player_position = view.player.position if view.player != null else GameState.player_position
	_update_hover()
	_keyboard_walk(delta)


func _update_thumbnail(delta: float) -> void:
	_thumb_timer += delta
	if _thumb_timer < THUMBNAIL_INTERVAL:
		return
	_thumb_timer = 0.0
	if mode != Mode.PLAY:
		return
	_grab_frame()


func _grab_frame() -> void:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null:
		return
	var tex := vp.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img != null:
		SaveManager.last_frame = img


func _update_hover() -> void:
	var view := _current_view()
	var p := get_viewport().get_mouse_position()
	panel.hover(p)

	var hover_id := ""
	var target_name := ""

	if Layout.in_view(p):
		var h := view.hotspot_at(p)
		if not h.is_empty():
			hover_id = str(h.get("id", ""))
			target_name = Loc.t(str(h.get("name_key", "")))
	else:
		var inv_id := panel.hovered_item_id()
		if not inv_id.is_empty():
			hover_id = inv_id
			target_name = Loc.t(str(GameData.item(inv_id).get("name_key", "")))

	if hover_id != _hover_id:
		_hover_id = hover_id
		view.set_hover(hover_id if Layout.in_view(p) else "")

	cursor.over_hotspot = not hover_id.is_empty()
	cursor.held_item = held_item

	# §5.3 문장 라인
	var verb := current_verb
	var hv := panel.hovered_verb()
	if hv >= 0:
		verb = hv
	var held_name := "" if held_item.is_empty() else Loc.t(str(GameData.item(held_item).get("name_key", "")))
	panel.set_sentence(Actions.sentence(verb, panel.is_simple_ui(), target_name, held_name))


## §21 "마우스와 키보드 지원" — 방향키/WASD 로도 걸을 수 있다.
func _keyboard_walk(delta: float) -> void:
	var view := _current_view()
	if view == null or view.player == null:
		return
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
		dir.x += 1
	if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W):
		dir.y -= 1
	if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S):
		dir.y += 1
	if dir == Vector2.ZERO:
		return
	view.player.stop()
	var next: Vector2 = view.clamp_to_walkbox(view.player.position + dir.normalized() * KEYBOARD_WALK_SPEED * delta)
	view.player.face_towards(next)
	view.player.place(next)
	view.player.is_walking = true


# ---------------------------------------------------------------- 입력

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle") and debug_panel != null:
		debug_panel.toggle()
		return
	if event.is_action_pressed("debug_page") and debug_panel != null and debug_panel.visible:
		debug_panel.next_page()
		return
	if event.is_action_pressed("debug_reload") and debug_panel != null and debug_panel.visible:
		GameData.reload()
		return
	if event.is_action_pressed("game_fullscreen"):
		_toggle_fullscreen()
		return

	if busy:
		_input_busy(event)
		return

	match mode:
		Mode.TITLE: _input_title(event)
		Mode.PLAY: _input_play(event)
		Mode.PAUSE: _input_menu(event, pause_menu)
		Mode.SETTINGS: _input_menu(event, settings_menu)
		Mode.SAVE, Mode.LOAD: _input_menu(event, save_menu)
		Mode.LOG: _input_log(event)


## 대사/선택지/컷신이 진행 중일 때.
func _input_busy(event: InputEvent) -> void:
	# 대상까지 걸어가는 중이라면 클릭을 씹지 않고 새 목표로 갈아탄다.
	if walking_to_target and event is InputEventMouseButton \
			and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_action_token += 1        # 진행 중인 걷기를 무효화
			walking_to_target = false
			busy = false
			_on_click(mb.position, mb.button_index == MOUSE_BUTTON_RIGHT)
			return

	if choice_box.is_active():
		if event is InputEventMouseMotion:
			choice_box.hover_at((event as InputEventMouseMotion).position)
			return
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				choice_box.select_at((event as InputEventMouseButton).position)
			return
		if event.is_action_pressed("ui_down"):
			choice_box.move_selection(1)
		elif event.is_action_pressed("ui_up"):
			choice_box.move_selection(-1)
		elif event.is_action_pressed("game_confirm"):
			choice_box.confirm()
		elif event is InputEventKey and (event as InputEventKey).pressed:
			var k := (event as InputEventKey).physical_keycode
			if k >= KEY_1 and k <= KEY_4:
				choice_box.select_index(k - KEY_1)
		return

	if card.is_active():
		if (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
				or event.is_action_pressed("game_confirm") or event.is_action_pressed("game_menu"):
			card.dismiss()
		return

	if subtitles.is_active():
		if (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
				or event.is_action_pressed("game_confirm"):
			subtitles.advance()
		return


func _input_title(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		title_screen.hover_at((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		title_screen.click_at((event as InputEventMouseButton).position)
	elif event.is_action_pressed("ui_down"):
		title_screen.move(1)
	elif event.is_action_pressed("ui_up"):
		title_screen.move(-1)
	elif event.is_action_pressed("game_confirm"):
		title_screen.activate()


func _input_menu(event: InputEvent, menu: MenuList) -> void:
	if event is InputEventMouseMotion:
		menu.hover_at((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			menu.click_at(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			menu.cancel()
	elif event.is_action_pressed("ui_down"):
		menu.move(1)
	elif event.is_action_pressed("ui_up"):
		menu.move(-1)
	elif event.is_action_pressed("ui_right"):
		menu.adjust(1)
	elif event.is_action_pressed("ui_left"):
		menu.adjust(-1)
	elif event.is_action_pressed("game_confirm"):
		menu.activate()
	elif event.is_action_pressed("game_menu"):
		menu.cancel()


func _input_log(event: InputEvent) -> void:
	if event.is_action_pressed("game_menu") or event.is_action_pressed("game_log"):
		log_view.close()
		mode = Mode.PLAY
		GameState.set_timer_paused(false)
	elif event.is_action_pressed("ui_down"):
		log_view.scroll_by(1)
	elif event.is_action_pressed("ui_up"):
		log_view.scroll_by(-1)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			log_view.scroll_by(2)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			log_view.scroll_by(-2)
		else:
			log_view.close()
			mode = Mode.PLAY
			GameState.set_timer_paused(false)


func _input_play(event: InputEvent) -> void:
	if event.is_action_pressed("game_menu"):
		_open_pause()
		return
	if event.is_action_pressed("game_log"):
		mode = Mode.LOG
		GameState.set_timer_paused(true)
		log_view.open()
		return
	if event.is_action_pressed("game_hint"):
		_on_hint_requested()
		return
	if event.is_action_pressed("game_quicksave"):
		SaveManager.save_to(SaveManager.manual_slot(0))
		_flash_system(Loc.t("ui.save.quicksaved"))
		return
	if event.is_action_pressed("game_quickload"):
		if SaveManager.load_from(SaveManager.manual_slot(0)):
			await SceneDirector.enter_scene_immediate(GameState.scene_id, "default", GameState.player_position)
		return

	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_on_click(mb.position, false)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_on_click(mb.position, true)
		return

	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).physical_keycode
		# 동사 단축키 — 왼쪽 손으로 잡히는 위치.
		var layout := panel.verb_layout()
		if k >= KEY_1 and k <= KEY_8:
			var idx := k - KEY_1
			if idx < layout.size():
				_on_verb_selected(layout[idx])


func _on_click(p: Vector2, right: bool) -> void:
	if panel.handles_point(p):
		panel.click(p, right)
		return

	var view := _current_view()
	if view == null or SceneDirector.is_changing():
		return

	var h := view.hotspot_at(p)
	if h.is_empty():
		# 빈 바닥 — 걸어간다. 진행 중이던 목표는 버린다.
		_action_token += 1
		view.player.walk_to(view.clamp_to_walkbox(p))
		if not held_item.is_empty():
			_release_item()
		return

	# 우클릭 = 그 대상에게 가장 자연스러운 동작. 고전 어드벤처의 관습이고,
	# 문 앞에서 '열다'를 못 찾아 헤매는 상황을 막는다. (§11.2 정신)
	var verb := current_verb
	if right:
		verb = Actions.from_id(str(h.get("default_verb", Actions.id(Actions.DEFAULT_VERB))))
	await _walk_then_interact(view, h, verb)


## 눈으로 하는 동작은 걸어갈 필요가 없다. 멀리서도 볼 수 있고,
## 무엇보다 클릭에 즉시 반응해야 답답하지 않다.
const INSTANT_VERBS := [Actions.Verb.LOOK]


func _walk_then_interact(view: LocationView, h: Dictionary, verb: int) -> void:
	var player: Actor = view.player

	# 조사(보다)는 걷지 않는다 — 고개만 돌리고 바로 대사가 나온다.
	if INSTANT_VERBS.has(verb):
		if player != null:
			player.stop()
			player.face_towards(LocationView._rect_of(h).get_center())
		await _interact(str(h.get("id", "")), verb)
		return

	var goal: Vector2 = view.walk_to_of(h)
	if player != null and player.position.distance_to(goal) > 3.0:
		_action_token += 1
		var token := _action_token
		walking_to_target = true
		busy = true
		player.walk_to(goal)
		var waited := 0.0
		while player.is_walking and waited < 2.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
			# 걷는 도중 다른 곳을 클릭하면 이 행동은 취소된다.
			if token != _action_token:
				walking_to_target = false
				busy = false
				return
		player.stop()
		walking_to_target = false
		busy = false

	if player != null:
		player.face_towards(LocationView._rect_of(h).get_center())

	await _interact(str(h.get("id", "")), verb)


## §21 상호작용 4요소를 그대로 넘긴다.
func _interact(target_id: String, verb: int) -> void:
	if busy:
		return
	busy = true
	var action := Actions.id(verb)
	var item := held_item

	var res := InteractionResolver.resolve(action, target_id, item)
	if debug_panel != null:
		debug_panel.note_interaction(action, target_id, item, res)

	# 출구는 룰이 없으면 그냥 이동한다. 잠긴 문은 룰 + on_fail 로 표현한다.
	var hs := GameData.hotspot_def(GameState.scene_id, target_id)
	var is_exit_target := hs.has("target")
	var exit_verbs := [Actions.Verb.WALK, Actions.Verb.OPEN, Actions.Verb.USE, Actions.Verb.PUSH, Actions.Verb.PULL]

	if is_exit_target and res.kind == InteractionResult.Kind.DEFAULT_LINE \
			and exit_verbs.has(verb) and item.is_empty():
		_release_item()
		await SceneDirector.change_scene(str(hs.get("target", "")), str(hs.get("entry", "default")))
		busy = false
		return

	# 실패음은 '해보려다 안 된' 경우에만. 조사(보다)는 뭘 보든 실패가 아니고,
	# 결과가 자기 효과음을 지정했으면 그쪽을 존중한다.
	var declares_own_sfx := not str(res.result.get("sfx", "")).is_empty()
	if not declares_own_sfx and not res.is_success() and verb != Actions.Verb.LOOK:
		AudioDirector.play_sfx("fail")

	await result_runner.run(res.result)

	# 아이템은 한 번 쓰면 손에서 놓는다. (SCUMM 관습)
	if verb == Actions.Verb.USE and not held_item.is_empty():
		_release_item()

	# 핫스폿이 켜지고 꺼졌을 수 있으니 배우를 다시 맞춘다.
	var v2 := _current_view()
	if v2 != null and is_instance_valid(v2):
		v2.refresh_actors()

	busy = false


# ---------------------------------------------------------------- UI 콜백

func _on_verb_selected(verb: int) -> void:
	current_verb = verb
	panel.set_verb(verb)
	if verb != Actions.Verb.USE:
		_release_item()


func _on_item_selected(item_id: String) -> void:
	if current_verb == Actions.Verb.USE:
		if held_item.is_empty():
			held_item = item_id
			panel.set_held_item(item_id)
			return
		if held_item == item_id:
			_release_item()
			return
		# §16.3 아이템 조합
		await _interact(item_id, Actions.Verb.USE)
		return
	await _interact(item_id, current_verb)


func _on_item_examined(item_id: String) -> void:
	await _interact(item_id, Actions.Verb.LOOK)


func _release_item() -> void:
	held_item = ""
	panel.set_held_item("")
	cursor.held_item = ""


## §11.3 힌트 — 페널티 없음.
func _on_hint_requested() -> void:
	if busy or mode != Mode.PLAY:
		return
	var h := HintSystem.next_hint()
	if h.is_empty():
		return
	busy = true
	await subtitles.say(str(h.get("speaker", "player")), Loc.t(str(h.get("key", ""))))
	busy = false


## ResultRunner 가 await 하는 특수 연출 처리기. (§3.2 컷신)
func _on_event_requested(event_name: String) -> void:
	match event_name:
		"prologue_end":
			busy = true
			await card.show_card([
				"card.prologue_end.1",
				"card.prologue_end.2",
				"card.prologue_end.3",
				"card.prologue_end.4",
			], "prologue_end")
			busy = false
			_open_title()
		_:
			push_warning("[Main] 처리되지 않은 이벤트: %s" % event_name)


func _flash_system(text: String) -> void:
	DialogueLog.add("system", text, "system")
	panel.set_sentence(text)


# ---------------------------------------------------------------- 메뉴

func _hide_all_menus() -> void:
	title_screen.close()
	pause_menu.close()
	settings_menu.close()
	save_menu.close()
	log_view.close()


func _open_pause() -> void:
	mode = Mode.PAUSE
	GameState.set_timer_paused(true)
	pause_menu.open("ui.pause.title", [
		{"label": Loc.t("ui.pause.resume")},
		{"label": Loc.t("ui.pause.save")},
		{"label": Loc.t("ui.pause.load"), "enabled": SaveManager.has_any_save()},
		{"label": Loc.t("ui.pause.log")},
		{"label": Loc.t("ui.pause.settings")},
		{"label": Loc.t("ui.pause.title_screen")},
	], "ui.pause.footer")


func _on_pause_activated(index: int) -> void:
	match index:
		0: _resume()
		1: _open_save_menu(SaveSlotMenu.Mode.SAVE)
		2: _open_save_menu(SaveSlotMenu.Mode.LOAD)
		3:
			pause_menu.close()
			mode = Mode.LOG
			log_view.open()
		4: _open_settings()
		5:
			pause_menu.close()
			_open_title()


func _resume() -> void:
	pause_menu.close()
	mode = Mode.PLAY
	GameState.set_timer_paused(false)


func _open_save_menu(p_mode: int) -> void:
	pause_menu.close()
	title_screen.close()
	mode = Mode.SAVE if p_mode == SaveSlotMenu.Mode.SAVE else Mode.LOAD
	save_menu.open_for(p_mode)


func _close_save_menu() -> void:
	save_menu.close()
	if GameState.scene_id.is_empty():
		_open_title()
	else:
		_open_pause()


func _on_slot_chosen(slot: String, p_mode: int) -> void:
	if p_mode == SaveSlotMenu.Mode.SAVE:
		SaveManager.save_to(slot)
		save_menu.open_for(p_mode)   # 갱신
		return
	if not SaveManager.load_from(slot):
		return
	save_menu.close()
	title_screen.close()
	panel.visible = true
	mode = Mode.PLAY
	HintSystem.reset()
	GameState.set_timer_paused(false)
	await SceneDirector.enter_scene_immediate(GameState.scene_id, "default", GameState.player_position)


# ---------------------------------------------------------------- 설정 (§18)

const SETTING_ROWS := [
	{"key": "verb_ui", "label": "ui.settings.verb_ui", "type": "enum",
	 "values": ["classic", "simple"], "labels": ["ui.settings.verb_classic", "ui.settings.verb_simple"]},
	{"key": "font_size_index", "label": "ui.settings.font_size", "type": "index",
	 "labels": ["ui.settings.font_small", "ui.settings.font_medium", "ui.settings.font_large"]},
	{"key": "text_speed", "label": "ui.settings.text_speed", "type": "index",
	 "labels": ["ui.settings.speed_slow", "ui.settings.speed_normal", "ui.settings.speed_fast", "ui.settings.speed_instant"]},
	{"key": "hint_level", "label": "ui.settings.hint_level", "type": "index",
	 "labels": ["ui.settings.hint_off", "ui.settings.hint_1", "ui.settings.hint_2", "ui.settings.hint_3"]},
	{"key": "high_contrast_hotspots", "label": "ui.settings.high_contrast", "type": "bool"},
	{"key": "show_exit_markers", "label": "ui.settings.exit_markers", "type": "bool"},
	{"key": "reduce_flashing", "label": "ui.settings.reduce_flashing", "type": "bool"},
	{"key": "reduce_shake", "label": "ui.settings.reduce_shake", "type": "bool"},
	{"key": "fullscreen", "label": "ui.settings.fullscreen", "type": "bool"},
	{"key": "master_volume", "label": "ui.settings.master_volume", "type": "percent"},
	{"key": "music_volume", "label": "ui.settings.music_volume", "type": "percent"},
	{"key": "sfx_volume", "label": "ui.settings.sfx_volume", "type": "percent"},
]


func _open_settings() -> void:
	pause_menu.close()
	title_screen.close()
	mode = Mode.SETTINGS
	settings_menu.open("ui.settings.title", _settings_rows(), "ui.settings.footer")


func _settings_rows() -> Array:
	var rows: Array = []
	for s in SETTING_ROWS:
		rows.append({"label": Loc.t(str(s["label"])), "value": _setting_value_text(s)})
	rows.append({"label": Loc.t("ui.settings.back"), "value": ""})
	return rows


func _setting_value_text(s: Dictionary) -> String:
	var key := str(s["key"])
	var v = SaveManager.get_setting(key)
	match str(s["type"]):
		"bool":
			return Loc.t("ui.settings.on" if bool(v) else "ui.settings.off")
		"percent":
			return "%d%%" % int(roundf(float(v) * 100.0))
		"enum":
			var vals: Array = s["values"]
			var i: int = maxi(0, vals.find(str(v)))
			return Loc.t(str((s["labels"] as Array)[i]))
		"index":
			var labels: Array = s["labels"]
			var i2: int = clampi(int(v), 0, labels.size() - 1)
			return Loc.t(str(labels[i2]))
	return str(v)


func _on_settings_activated(index: int) -> void:
	if index >= SETTING_ROWS.size():
		_close_settings()
		return
	_on_settings_adjusted(index, 1)


func _on_settings_adjusted(index: int, delta: int) -> void:
	if index >= SETTING_ROWS.size():
		return
	var s: Dictionary = SETTING_ROWS[index]
	var key := str(s["key"])
	var v = SaveManager.get_setting(key)

	match str(s["type"]):
		"bool":
			SaveManager.set_setting(key, not bool(v))
		"percent":
			SaveManager.set_setting(key, clampf(float(v) + 0.1 * delta, 0.0, 1.0))
		"enum":
			var vals: Array = s["values"]
			var i: int = posmod(maxi(0, vals.find(str(v))) + delta, vals.size())
			SaveManager.set_setting(key, str(vals[i]))
		"index":
			var n: int = (s["labels"] as Array).size()
			SaveManager.set_setting(key, posmod(int(v) + delta, n))

	_apply_settings()
	settings_menu.set_rows(_settings_rows())


func _apply_settings() -> void:
	Theming.set_font_size_index(int(SaveManager.get_setting("font_size_index", 1)))
	AudioDirector.apply_volumes()
	var want_fs := bool(SaveManager.get_setting("fullscreen", false))
	var is_fs := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	if want_fs != is_fs:
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED)
	if panel != null:
		panel.queue_redraw()


func _close_settings() -> void:
	settings_menu.close()
	if GameState.scene_id.is_empty() or mode == Mode.TITLE:
		_open_title()
	else:
		_open_pause()


func _toggle_fullscreen() -> void:
	SaveManager.set_setting("fullscreen", not bool(SaveManager.get_setting("fullscreen", false)))
	_apply_settings()
