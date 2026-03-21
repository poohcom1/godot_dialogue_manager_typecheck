# API

## Finds the Project tool menu for DM
static func find_dialogue_tool_menu() -> PopupMenu:
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

const DMMainView := preload("res://addons/dialogue_manager/views/main_view.gd")

static func find_dm_main_view() -> DMMainView:
	var base = EditorInterface.get_base_control()
	return _search_child(base, func(node: Node):
		return node is DMMainView
	)

static func find_dm_code_edit() -> DMCodeEdit:
	var base = EditorInterface.get_base_control()
	return _search_child(base, func(node: Node):
		return node is DMCodeEdit
	)


# Helper
static func _search_child(node: Node, cond: Callable) -> Node:
	for child in node.get_children():
		if cond.call(child):
			return child
		else:
			var result = _search_child(child, cond)
			if result != null:
				return result
	return null
