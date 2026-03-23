## Adds a tool menu under Tools -> Dialogue -> Check type
## @deprecated: Deprecated for maintainability; feature is superceded by in-editor highlighting and CLI tool
extends RefCounted

const ID_CHECK_TYPE := 100

const EditorUtil := preload("./util.gd")
const TypeChecker := preload("../type_checker/type_checker.gd")

var _type_checker: TypeChecker
var _quick_open: QuickOpen
var _dialogue_tool_menu: PopupMenu

func _init(type_checker: TypeChecker) -> void:
	_type_checker = type_checker

func on_enter_tree() -> void:
	_quick_open = QuickOpen.new()
	EditorInterface.get_base_control().add_child(_quick_open)
	_quick_open.files_list.file_double_clicked.connect(func(file_path: String):
		var dialogue: DialogueResource = load(file_path)
		var errors := await _type_checker.check_type(dialogue)
		if len(errors) == 0:
			print_rich("[color=dark_gray][DM Typecheck][/color] No errors in %s." % dialogue.resource_path)
		else:
			print_rich("[color=dark_gray][DM Typecheck][/color] Found [color=#ff786b][b]%d errors[/b][/color] in [b]%s[/b]." % [len(errors), dialogue.resource_path])
			for line in errors:
				print_rich("[color=#ff786b] - Error at %d:[/color] %s" % [line, errors[line]])
	)

	await EditorInterface.get_base_control().get_tree().process_frame

	_dialogue_tool_menu = EditorUtil.find_dialogue_tool_menu()
	assert(_dialogue_tool_menu != null, "Could not find Dialogue Manager tool menu.")
	
	_dialogue_tool_menu.add_icon_item(load("res://addons/dialogue_manager/assets/region.svg"), "Check Type", ID_CHECK_TYPE)
	_dialogue_tool_menu.id_pressed.connect(_on_tool_pressed)


func on_exit_tree() -> void:
	EditorInterface.get_base_control().remove_child(_quick_open)

	if _dialogue_tool_menu != null and  _dialogue_tool_menu.is_inside_tree():
		_dialogue_tool_menu.id_pressed.disconnect(_on_tool_pressed)
		_dialogue_tool_menu.remove_item(_dialogue_tool_menu.get_item_index(ID_CHECK_TYPE))

# Callbacks
func _on_tool_pressed(id: int) -> void:
	if id == ID_CHECK_TYPE:
		_quick_open.files_list.files = DMCache.get_files()
		_quick_open.popup_centered()

# Helpers
class QuickOpen extends ConfirmationDialog:
	const DMFilesListScene: PackedScene = preload("res://addons/dialogue_manager/components/files_list.tscn")
	const DMFilesList: Script = preload("res://addons/dialogue_manager/components/files_list.gd")

	var files_list: DMFilesList

	func _init():
		title = "Select Dialogue File"
		size = Vector2(600, 900)
		min_size = Vector2(600, 900)
		ok_button_text = "Open"

		files_list = DMFilesListScene.instantiate()
		files_list.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(files_list)

	func _ready():
		files_list.file_double_clicked.connect(func(file_path: String):
			hide()
		)
