@tool
extends EditorPlugin


func _enable_plugin() -> void:
	# Add autoloads here.
	pass


func _disable_plugin() -> void:
	# Remove autoloads here.
	pass


const ID_CHECK_TYPE := 100

const TypeChecker := preload("type_checker/type_checker.gd")
const QuickOpen: Script = preload("editor/quick_open.gd")
var quick_open: QuickOpen

func _enter_tree() -> void:
	var base = EditorInterface.get_base_control()
	quick_open = QuickOpen.new()
	base.add_child(quick_open)

	quick_open.files_list.file_double_clicked.connect(func(file_path: String):
		var dialogue: DialogueResource = load(file_path)
		var errors := TypeChecker.check_type(dialogue)
		if len(errors) == 0:
			print_rich("[color=dark_gray][DM Typecheck][/color] No errors in %s." % dialogue.resource_path)
		else:
			print_rich("[color=dark_gray][DM Typecheck][/color] Found [color=#ff786b][b]%d errors[/b][/color] in [b]%s[/b]." % [len(errors), dialogue.resource_path])
			for line in errors:
				print_rich("[color=#ff786b] - Error at %d: %s" % [line, errors[line]])
	)


	await get_tree().process_frame
	var dialogue_tool_menu := _find_dialogue_tool_menu()
	assert(dialogue_tool_menu != null)

	
	dialogue_tool_menu.add_icon_item(load("res://addons/dialogue_manager/assets/region.svg"), "Check Type", ID_CHECK_TYPE)
	dialogue_tool_menu.id_pressed.connect(_on_tool_pressed)

func _exit_tree() -> void:
	var base = EditorInterface.get_base_control()
	base.remove_child(quick_open)

	var dialogue_tool_menu := _find_dialogue_tool_menu()
	if dialogue_tool_menu == null or not dialogue_tool_menu.is_inside_tree():
		return
	dialogue_tool_menu.id_pressed.disconnect(_on_tool_pressed)
	dialogue_tool_menu.remove_item(dialogue_tool_menu.get_item_index(ID_CHECK_TYPE))


func _on_tool_pressed(id: int) -> void:
	if id == ID_CHECK_TYPE:
		quick_open.files_list.files = DMCache.get_files()
		quick_open.popup_centered()

# Control helpers
func _find_dialogue_tool_menu() -> PopupMenu:
	var base = EditorInterface.get_base_control()
	
	var menu_bar = _search_child(base, func(node: Node):
		return node is MenuBar and node.has_node("Project")
	)
	var project_menu: PopupMenu = menu_bar.get_node("Project")
	
	var tool_menu: PopupMenu
	for i in range(project_menu.item_count):
		if project_menu.get_item_text(i) == "Tools":
			tool_menu = project_menu.get_item_submenu_node(i)
			break
	
	var dialogue_manager_menu: PopupMenu
	for i in range(tool_menu.item_count):
		if tool_menu.get_item_text(i) == "Dialogue":
			dialogue_manager_menu = tool_menu.get_item_submenu_node(i)
			break
	return dialogue_manager_menu

func _search_child(node: Node, cond: Callable) -> Node:
	for child in node.get_children():
		if cond.call(child):
			return child
		else:
			var result = _search_child(child, cond)
			if result != null:
				return result
	return null
