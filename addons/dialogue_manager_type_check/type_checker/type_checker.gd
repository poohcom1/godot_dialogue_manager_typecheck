## DM ErrType Checker

const CsTypeCheckerScript = "res://addons/dialogue_manager_type_check/type_checker/TypeChecker.cs"
static var cs_type_checker: Object:
	get:
		if cs_type_checker == null or not is_instance_valid(cs_type_checker):
			cs_type_checker = load(CsTypeCheckerScript).new()
		return cs_type_checker


const BUILT_IN_FUNCS := [&"wait", &"Wait", &"debug", &"Debug"]

static func check_type(dialogue: DialogueResource) -> Dictionary[int, DMError]:
	var result := DMCompiler.compile_string(dialogue.raw_text, dialogue.resource_path)
	var lines := result.lines

	var global_scripts: Array[Script] = []
	# TODO: Also include extra_script_source
	var autoload_shortcuts: PackedStringArray = DMSettings.get_setting(DMSettings.STATE_AUTOLOAD_SHORTCUTS, [])
	for autoload in autoload_shortcuts:
		global_scripts.append(_get_autoload_script(autoload))
	for autoload in dialogue.using_states:
		global_scripts.append(_get_autoload_script(autoload))

	# Analyze
	var errors: Dictionary[int, DMError] = {}
	for key in lines:
		var line: Dictionary = lines[key]
		var line_no = int(lines[key][&"id"]) + 1
		var expressions := []

		if line.type == DMConstants.TYPE_MUTATION:
			if &"expression" in line.mutation:
				expressions = line.mutation.expression
		elif line.type == DMConstants.TYPE_CONDITION:
			if &"expression" in line.condition:
				expressions = line.condition.expression
		if len(expressions) == 0:
			continue

		var items: Array[DMBase] = _parse_expression_list(expressions)
		for item in items:
			if item.root is DMFunction && item.root.identifier in BUILT_IN_FUNCS:
				continue

			var err = _verify_item(item.root, global_scripts, item)
			if not err.is_ok():
				errors[line_no] = err
	return errors
	

#region Parsing Helpers

static func _parse_expression_list(tokens: Array) -> Array[DMBase]:
	var items: Array[DMBase] = []
	var i := 0
	
	var current_base: DMBase = null
	var tail: DMNode = null

	while i < tokens.size():
		var token = tokens[i]
		var new_node: DMNode = null
		
		match token.type:
			DMConstants.TOKEN_VARIABLE:
				new_node = DMNode.new()
				new_node.identifier = token[&"value"]
				
			DMConstants.TOKEN_FUNCTION:
				var func_node = DMFunction.new()
				func_node.identifier = token[&"function"]
				# Recursive Step: DM stores function args as nested arrays/tokens
				if token.has(&"arguments"):
					for arg_tokens in token[&"arguments"]:
						func_node.args.append(_parse_expression_list(arg_tokens)[0])
				new_node = func_node
				
			DMConstants.TOKEN_STRING, DMConstants.TOKEN_NUMBER, DMConstants.TOKEN_BOOL:
				new_node = DMLiteral.new()
				new_node.identifier = str(token[&"value"])
			
			DMConstants.TOKEN_OPERATOR, DMConstants.TOKEN_ASSIGNMENT, DMConstants.TOKEN_COMPARISON:
				# Operators break the current chain and become their own 'item'
				var op_node = DMOperator.new()
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
				current_base = DMBase.new()
				current_base.root = new_node
				items.append(current_base)
			else:
				tail.next = new_node
			tail = new_node
			
		i += 1
	return items

static func _wrap_in_base(node: DMNode) -> DMBase:
	var b = DMBase.new()
	b.root = node
	return b

#endregion

#region Verification

static func _verify_item(node: DMNode, base_scripts: Array[Script], base: DMBase) -> DMError:
	if node is DMOperator:
		pass # TODO
	elif node is DMLiteral:
		pass # TODO
	elif node is DMFunction:
		for script in base_scripts:
			for method_info in script.get_script_method_list():
				if method_info.name == node.identifier:
					return DMError.ok()
			# Maybe a cs async function
			if script.resource_path.ends_with(".cs"):
				var method_info = cs_type_checker.GetCsScriptMethodInfo(script, node.identifier)
				if method_info != null:
					return DMError.ok()
		return DMErrorUnknownMember.new(node, base)
	# Must be member then
	elif node.next != null:
		var member_script: Script = null

		for script in base_scripts:
			for property_info in script.get_script_property_list():
				if property_info.name == node.identifier:
					member_script = _get_script_for_class_name(property_info.get("class_name", ""))
					if member_script:
						break
		if member_script == null and base.root == node:
			# Top level, look for autoloads
			member_script = _get_autoload_script(node.identifier)
		
		if member_script == null:
			return DMErrorUnknownMember.new(node, base)
		
		return _verify_item(node.next, [member_script], base)
	else:

		for script in base_scripts:
			for property_info in script.get_script_property_list():
				if property_info.name == node.identifier:
					return DMError.ok()
		return DMErrorUnknownMember.new(node, base)
	
	return DMError.ok()

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

#endregion

#region Classes

class DMBase:
	var root: DMNode

	func get_path_to(target_node: DMNode) -> String:
		var display = root.identifier
		var node := root.next

		while node != null:
			if node == target_node:
				return display
			display += "." + node.identifier
			node = node.next
		return display

	func _to_string() -> String:
		var display = root.identifier
		var node := root.next
		while node != null:
			display += "." + node.identifier
			node = node.next

			if node is DMFunction:
				display += "()"
		return display

class DMNode:
	var identifier: String
	var next: DMNode
	func _to_string() -> String:
		return "DMNode(identifier: %s)" % identifier

class DMFunction extends DMNode:
	var args: Array[DMBase] = []
	func _to_string() -> String:
		return "DMFunction(identifier: %s, args: %s)" % [identifier, args]

class DMLiteral extends DMNode:
	func _to_string() -> String:
		return "DmLiteral(identifier: %s)" % identifier

class DMOperator extends DMNode:
	var token_type: StringName
	func _to_string() -> String:
		return "DMOperator(token_type: %s)" % token_type


enum ErrType {
	Ok,
	UnknownMember
}

class DMError:
	var type: ErrType
	var msg: String = ""

	func _init(p_type: ErrType, p_msg = "") -> void:
		type = p_type
		msg = p_msg

	static func ok() -> DMError:
		return DMError.new(ErrType.Ok)
	
	func is_ok() -> bool:
		return type == ErrType.Ok
	
	func _to_string() -> String:
		if msg.is_empty():
			return str(ErrType.keys()[type])
		return msg

class DMErrorUnknownMember extends DMError:
	func _init(node: DMNode, base: DMBase) -> void:
		var base_context = '"%s"' % base.get_path_to(node)
		if base.root == node:
			base_context = "usings or state autoload shortcuts"
		super._init(ErrType.UnknownMember, 'Could not find member "%s" in %s.' % [node.identifier, base_context])
#endregion
