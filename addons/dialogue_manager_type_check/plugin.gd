@tool
extends EditorPlugin

const ID_CHECK_TYPE := 100

const ToolMenu := preload("./editor/tool_menu.gd")
const CodeEditAddon := preload("./editor/code_edit_addon.gd")

const DMMainView := preload("res://addons/dialogue_manager/views/main_view.gd")

var _tool_menu: ToolMenu
var _code_edit_addon: CodeEditAddon

func _enter_tree() -> void:
	_tool_menu = ToolMenu.new()
	_tool_menu.on_enter_tree()

	_code_edit_addon = CodeEditAddon.new()
	_code_edit_addon.on_enter_tree()

func _exit_tree() -> void:
	_tool_menu.on_exit_tree()
	_code_edit_addon.on_exit_tree()
