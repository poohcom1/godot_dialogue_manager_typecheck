extends RefCounted

const EditorUtil := preload("./util.gd")
const TypeChecker := preload("../type_checker/type_checker.gd")

const DMMainView := preload("res://addons/dialogue_manager/views/main_view.gd")

var _type_checker: TypeChecker
var _dm_main_view: DMMainView
var _error_cache: Dictionary[int, TypeChecker.TypeError] = {}

func _init(type_checker: TypeChecker) -> void:
	_type_checker = type_checker

func on_enter_tree() -> void:
	await EditorInterface.get_base_control().get_tree().process_frame

	_dm_main_view = EditorUtil.find_dm_main_view()
	if _dm_main_view == null:
		push_warning("[DMTypeCheck] Could not find Dialogue Manager main view.")
		return
	if _dm_main_view.get("code_edit") == null:
		push_warning("[DMTypeCheck] Could not find Dialogue Manager code edit.")
		return
	if _dm_main_view.get("parse_timer") == null:
		push_warning("[DMTypeCheck] Could not find Dialogue Manager parse timer.")
		return
	
	_dm_main_view.parse_timer.timeout.connect(_on_parse)
	_dm_main_view.code_edit.gutter_clicked.connect(_on_gutter_clicked)


func on_exit_tree() -> void:
	if _dm_main_view != null and _dm_main_view.is_inside_tree():
		_dm_main_view.parse_timer.timeout.disconnect(_on_parse)
		_dm_main_view.code_edit.gutter_clicked.disconnect(_on_gutter_clicked)


# Code edit
func _on_parse() -> void:
	var code_edit := _dm_main_view.code_edit

	# See DialogueManager.create_resource_from_text()
	var result: DMCompilerResult = DMCompiler.compile_string(code_edit.text, _dm_main_view.current_file_path)

	if result.errors.size() > 0:
		_error_cache = {}
		_add_gutter_warnings(_error_cache)

	_error_cache = await _type_checker.check_type(result.lines, result.using_states)
	_add_gutter_warnings(_error_cache)

func _add_gutter_warnings(errors: Dictionary[int, TypeChecker.TypeError]) -> void:
	var code_edit := _dm_main_view.code_edit

	var warning_color := Color(EditorInterface.get_editor_settings().get_setting("text_editor/theme/highlighting/comment_markers/warning_color"), 0.2)

	for i in range(code_edit.get_line_count()):
		var line_number := i + 1
		if code_edit.get_line_background_color(i) != Color(0, 0, 0, 0):
			# already marked by DM error
			continue

		if errors.has(line_number):
			code_edit.set_line_background_color(i, warning_color)
			code_edit.set_line_gutter_icon(i, 0, _dm_main_view.get_theme_icon("StatusWarning", "EditorIcons"))
		else:
			code_edit.set_line_background_color(i, Color(0, 0, 0, 0))
			code_edit.set_line_gutter_icon(i, 0, null)

func _on_gutter_clicked(line: int, gutter: int) -> void:
	var actual_line := line + 1
	if _error_cache.has(actual_line):
		var err := _error_cache[actual_line]
		#print_rich("[color=#d4c79e]● Type error at %d: %s" % [actual_line, err])
		push_warning("Type error at %d: %s" % [actual_line, err])
