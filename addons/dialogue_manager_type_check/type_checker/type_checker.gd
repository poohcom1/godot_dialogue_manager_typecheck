## DM TypeErrorType Checker
extends RefCounted

const DialogueManager := preload("res://addons/dialogue_manager/dialogue_manager.gd")
const DMSettings := preload("res://addons/dialogue_manager/settings.gd")
const DMConstants := preload("res://addons/dialogue_manager/constants.gd")

var _dialogue_manager: DialogueManager
var _cs_type_checker = null # don't preload as C# might not be compiled


const BUILT_IN_FUNCS := [&"wait", &"Wait", &"debug", &"Debug"]

func _init() -> void:
	_dialogue_manager = DialogueManager.new()
	if ClassDB.class_exists("CSharpScript"):
		_cs_type_checker = load("res://addons/dialogue_manager_type_check/type_checker/TypeChecker.cs").new()

func cleanup() -> void:
	_dialogue_manager.free()

# API
func check_type(dialogue: DialogueResource) -> Dictionary[int, TypeError]:
	var global_scripts: Array[Script] = []
	# TODO: Also include extra_script_source
	var autoload_shortcuts: PackedStringArray = DMSettings.get_setting(DMSettings.STATE_AUTOLOAD_SHORTCUTS, [])
	for autoload in autoload_shortcuts:
		global_scripts.append(_get_autoload_script(autoload))
	for autoload in dialogue.using_states:
		global_scripts.append(_get_autoload_script(autoload))
	
	# Analyze
	var errors: Dictionary[int, TypeError] = {}
	for key in dialogue.lines:
		var line: Dictionary = dialogue.lines[key]
		var line_no = int(line[&"id"]) + 1
		var expressions := []

		if line.type == DMConstants.TYPE_MUTATION:
			if &"expression" in line.mutation:
				expressions = line.mutation.expression
		elif line.type == DMConstants.TYPE_CONDITION:
			if &"expression" in line.condition:
				expressions = line.condition.expression
		elif line.type == DMConstants.TYPE_DIALOGUE:
			var resolved_line_data = await _dialogue_manager.get_resolved_line_data(line)
			if "mutations" in resolved_line_data:
				for mutation in resolved_line_data.mutations:
					var data = mutation[1]
					if &"expression" in data:
						expressions = data.expression
		if len(expressions) == 0:
			continue

		var items: Array[TreeNode] = _parse_expression_list(expressions)
		for item in items:
			if item.next is TreeFunction && item.next.identifier in BUILT_IN_FUNCS:
				continue

			var err = _verify_item(item.next, global_scripts, item)
			if not err.is_ok():
				errors[line_no] = err
	return errors


#region Parsing Helpers

static func _parse_expression_list(tokens: Array) -> Array[TreeNode]:
	var items: Array[TreeNode] = []
	var i := 0
	
	var current_base: TreeNode = null
	var tail: TreeNode = null

	while i < tokens.size():
		var token = tokens[i]
		var new_node: TreeNode = null
		
		match token.type:
			DMConstants.TOKEN_VARIABLE:
				new_node = TreeNode.new()
				new_node.identifier = token[&"value"]
				
			DMConstants.TOKEN_FUNCTION:
				var func_node = TreeFunction.new()
				func_node.identifier = token[&"function"]
				# Recursive Step: DM stores function args as nested arrays/tokens
				if token.has(&"arguments"):
					for arg_tokens in token[&"arguments"]:
						func_node.args.append(_parse_expression_list(arg_tokens)[0])
				new_node = func_node
				
			DMConstants.TOKEN_STRING, DMConstants.TOKEN_NUMBER, DMConstants.TOKEN_BOOL:
				new_node = TreeLiteral.new()
				new_node.identifier = str(token[&"value"])
			
			DMConstants.TOKEN_OPERATOR, DMConstants.TOKEN_ASSIGNMENT, DMConstants.TOKEN_COMPARISON:
				# Operators break the current chain and become their own 'item'
				var op_node = TreeOperator.new()
				op_node.token_type = token.type
				items.append(_wrap_in_base(op_node))
				current_base = null # Reset for the next part of the expression
				tail = null
				i += 1
				continue

			DMConstants.TOKEN_DOT:
				i += 1
				continue # Dots are structural, we just wait for the next variable/function

		if new_node:
			if current_base == null:
				current_base = TreeNode.new()
				current_base.next = new_node
				items.append(current_base)
			else:
				tail.next = new_node
			tail = new_node
			
		i += 1
	return items

static func _wrap_in_base(node: TreeNode) -> TreeNode:
	var b = TreeNode.new()
	b.next = node
	return b

#endregion

#region Verification

func _verify_item(node: TreeNode, base_scripts: Array[Script], base: TreeNode) -> TypeError:
	if node is TreeOperator:
		pass # TODO
	elif node is TreeLiteral:
		pass # TODO
	elif node is TreeFunction:
		for script in base_scripts:
			for method_info in script.get_script_method_list():
				if method_info.name == node.identifier:
					return TypeError.ok()
			# Maybe a cs async function
			if _cs_type_checker and script.resource_path.ends_with(".cs"):
				var method_info = _cs_type_checker.GetCsScriptMethodInfo(script, node.identifier)
				if method_info != null:
					return TypeError.ok()
		return TypeErrorUnknownMember.new(node, base, true)
	# Must be member then
	elif node.next != null:
		var member_script: Script = null

		for script in base_scripts:
			for property_info in script.get_script_property_list():
				if property_info.name == node.identifier:
					member_script = _get_script_for_class_name(property_info.get("class_name", ""))
					if member_script:
						break
		if member_script == null and base.next == node:
			# Top level, look for autoloads
			member_script = _get_autoload_script(node.identifier)
		
		if member_script == null:
			return TypeErrorUnknownMember.new(node, base)
		
		return _verify_item(node.next, [member_script], base)
	else:

		for script in base_scripts:
			for property_info in script.get_script_property_list():
				if property_info.name == node.identifier:
					return TypeError.ok()
		return TypeErrorUnknownMember.new(node, base)
	
	return TypeError.ok()

static func _get_autoload_script(autoload: StringName) -> Script:
	var setting = ProjectSettings.get("autoload/%s" % autoload)
	if setting == null or setting == "":
		return null
	var path: String = setting.replace("*", "")
	var autoload_res = load(path)
	if autoload_res is PackedScene:
		var node: Node = autoload_res.instantiate()
		var script = node.get_script()
		node.free()
		return script
	elif not autoload_res is Script:
		return autoload_res.get_script()
	else:
		# Script or null
		return autoload_res

static func _get_script_for_class_name(class_name_to_find: String) -> Script:
	if class_name_to_find == "": return null

	for class_data: Dictionary in ProjectSettings.get_global_class_list():
		if class_data.get(&"class") == class_name_to_find:
			return load(class_data.path)

	return null

# #endregion

#region AST Classes

## Node to represent the AST
class TreeNode:
	func get_path_to(target_node: TreeNode) -> String:
		var display = identifier
		var node := next

		while node != null:
			if node == target_node:
				return display
			display += "." + node.identifier
			node = node.next
		return display

	func _to_string() -> String:
		var display = identifier
		var node := next
		while node != null:
			display += "." + node.identifier
			node = node.next

			if node is TreeNode:
				display += "()"
		return display

	var identifier: String
	var next: TreeNode


class TreeFunction extends TreeNode:
	var args: Array[TreeNode] = []

class TreeLiteral extends TreeNode:
	pass

class TreeOperator extends TreeNode:
	var token_type: StringName


enum TypeErrorType {
	Ok,
	UnknownMember
}

class TypeError:
	var type: TypeErrorType
	var msg: String = ""

	func _init(p_type: TypeErrorType, p_msg = "") -> void:
		type = p_type
		msg = p_msg

	static func ok() -> TypeError:
		return TypeError.new(TypeErrorType.Ok)
	
	func is_ok() -> bool:
		return type == TypeErrorType.Ok
	
	func _to_string() -> String:
		if msg.is_empty():
			return str(TypeErrorType.keys()[type])
		return msg

class TypeErrorUnknownMember extends TypeError:
	func _init(node: TreeNode, base: TreeNode, is_function: bool = false) -> void:
		var base_context = '"%s"' % base.get_path_to(node)
		if base.next == node:
			base_context = "usings or state autoload shortcuts"
		
		var member_name = "function" if is_function else "property"
		var member_text = node.identifier + "()" if is_function else node.identifier

		super._init(TypeErrorType.UnknownMember, 'Could not find %s "%s" in %s.' % [member_name, member_text, base_context])
#endregion
