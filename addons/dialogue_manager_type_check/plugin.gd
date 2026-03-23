@tool
extends EditorPlugin

const ID_CHECK_TYPE := 100

const TypeChecker := preload("./type_checker/type_checker.gd")
const ToolMenu := preload("./editor/tool_menu.gd")
const CodeEditAddon := preload("./editor/code_edit_addon.gd")

var _type_checker: TypeChecker
var _code_edit_addon: CodeEditAddon

func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return

	_type_checker = TypeChecker.new()

	_code_edit_addon = CodeEditAddon.new(_type_checker)
	_code_edit_addon.on_enter_tree()

func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		return
	_code_edit_addon.on_exit_tree()
	
	_type_checker.cleanup()
