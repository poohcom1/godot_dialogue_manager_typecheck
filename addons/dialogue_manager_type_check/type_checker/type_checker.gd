## DM TypeErrorType Checker
extends RefCounted

const DialogueManager := preload("res://addons/dialogue_manager/dialogue_manager.gd")
const DMSettings := preload("res://addons/dialogue_manager/settings.gd")
const DMConstants := preload("res://addons/dialogue_manager/constants.gd")

var _dialogue_manager: DialogueManager
var _cs_type_checker = null # don't preload as C# might not be compiled

var _strict := false

const BUILT_IN_FUNCS := [&"wait", &"Wait", &"debug", &"Debug"]

func _init() -> void:
	_dialogue_manager = DialogueManager.new()
	if ProjectSettings.get("application/config/features").has("C#"):
		_cs_type_checker = load("res://addons/dialogue_manager_type_check/type_checker/TypeChecker.cs").new()

func cleanup() -> void:
	_dialogue_manager.free()

# API
func check_type(dialogue: DialogueResource) -> Dictionary[int, TypeError]:
	var global_scripts: Array[ClassType] = []
	# TODO: Also include extra_script_source
	var autoload_shortcuts: PackedStringArray = DMSettings.get_setting(DMSettings.STATE_AUTOLOAD_SHORTCUTS, [])
	for autoload in autoload_shortcuts + dialogue.using_states:
		global_scripts.append(ScriptType.new(_get_autoload_script(autoload), autoload))
	
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

		var items: Array[ASTNode] = _parse_expression_list(expressions)
		for item in items:
			if item is ASTFunc && item.identifier in BUILT_IN_FUNCS:
				continue

			var err = _verify_expression(item, global_scripts, item)
			if not err.is_ok():
				errors[line_no] = err
	return errors


#region Parsing Helpers

static func _parse_expression_list(tokens: Array) -> Array[ASTNode]:
	var items: Array[ASTNode] = []
	var i := 0
	
	var current_base: ASTNode = null
	var tail: ASTNode = null

	while i < tokens.size():
		var token = tokens[i]
		var new_node: ASTNode = null
		
		match token.type:
			DMConstants.TOKEN_VARIABLE:
				new_node = ASTNode.new()
				new_node.identifier = token[&"value"]
				
			DMConstants.TOKEN_FUNCTION:
				var func_node = ASTFunc.new()
				func_node.identifier = token[&"function"]
				# Recursive Step: DM stores function args as nested arrays/tokens
				if token.has(&"arguments"):
					for arg_tokens in token[&"arguments"]:
						func_node.args.append(_parse_expression_list(arg_tokens)[0])
				new_node = func_node
				
			DMConstants.TOKEN_STRING, DMConstants.TOKEN_NUMBER, DMConstants.TOKEN_BOOL:
				new_node = ASTLiteral.new()
				new_node.identifier = str(token[&"value"])
			
			DMConstants.TOKEN_OPERATOR, DMConstants.TOKEN_ASSIGNMENT, DMConstants.TOKEN_COMPARISON:
				# Operators break the current chain and become their own 'item'
				var op_node = ASTOp.new()
				op_node.token_type = token.type
				items.append(op_node)
				current_base = null # Reset for the next part of the expression
				tail = null
				i += 1
				continue

			DMConstants.TOKEN_DOT:
				i += 1
				continue # Dots are structural, we just wait for the next variable/function

		if new_node:
			if current_base == null:
				current_base = new_node
				items.append(current_base)
			else:
				tail.next = new_node
			tail = new_node
			
		i += 1
	return items

#endregion

#region Verification

## Verifies the type correctness of an expression.
## [base_classes] is the parent class to check. It's a list only because DM allows multiple usings / shortcuts, so at the top level there may be multiple autoloads to check from.
## [ClassType] is a basic wrapper over a Script/built-in class
func _verify_expression(node: ASTNode, base_classes: Array[ClassType], base: ASTNode, is_static := false) -> TypeError:
	if node is ASTOp:
		pass # TODO
	elif node is ASTLiteral:
		pass # TODO
	elif node is ASTFunc:
		for class_type in base_classes:
			for method_info in class_type.get_class_method_list():
				if method_info.name == node.identifier:
					return TypeError.ok()
			# Maybe a cs async function
			if _cs_type_checker and class_type.resource_path.ends_with(".cs"):
				var method_info = _cs_type_checker.GetCsScriptMethodInfo(class_type, node.identifier)
				if method_info != null:
					return TypeError.ok()
		return UnknownMethod.new(node, base, base_classes[0] if base_classes.size() > 0 else null)
	# Must be member then
	else:
		var member_class: ClassType = null
		var member_static := false

		# Top level, look for autoloads
		if base == node and member_class == null:
			var autoload_script := _get_autoload_script(node.identifier)
			if autoload_script != null:
				member_class = ScriptType.new(autoload_script, node.identifier)
		for class_type in base_classes:
			# Check static context first; constants and enums
			var constant_map := class_type.get_class_constant_map()
			for name in constant_map:
				var value: Variant = constant_map[name]
				if name != node.identifier:
					continue
				# Class
				if value is Script:
					if node.next == null:
						# Weird subclass expression (MyClass.SubClass), but technically valid
						return TypeError.ok()
					member_class = ScriptType.new(value)
					member_static = true
					break
				# Enum
				if value is Dictionary:
					if node.next == null:
						# Weird enum base expression (MyClass.MyEnum), but technically valid
						return TypeError.ok()
					# If enum access, must only have tail next
					if node.next != null and node.next.next == null:
						var enum_value = node.next.identifier
						if value.has(enum_value):
							return TypeError.ok()
						else:
							return UnknownEnum.new(node.next, base)
				else:
					# Regular constant
					return TypeError.ok()
			# Check for instance context
			for property_info in class_type.get_class_property_list():
				if property_info.name == node.identifier:
					if is_static:
						# Attempted to access instance prop from static (i.e. MyClass.member)
						return StaticInstanceAccess.new(node, base)
					# Tail and found value, OK
					if node.next == null:
						return TypeError.ok()
					else:
						# Not tail, attempt to find script
						if property_info.has("class_name"):
							member_class = BuiltinType.new(property_info["class_name"])
							for class_data: Dictionary in ProjectSettings.get_global_class_list():
								if class_data.get(&"class") == property_info["class_name"]:
									member_class = ScriptType.new(load(class_data.path))
						if member_class:
							break

		if member_class == null:
			return UnknownProperty.new(node, base, base_classes[0] if not base_classes.size() > 0 else null, is_static)
		if node.next != null:
			return _verify_expression(node.next, [member_class], base, member_static)
		return UnknownProperty.new(node, base, member_class, is_static)
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

## Helper wrapper for Script / built-in class
@abstract class ClassType:
	# API
	@abstract func get_class_name() -> String
	@abstract func get_class_property_list() -> Array[Dictionary]
	@abstract func get_class_method_list() -> Array[Dictionary]
	@abstract func get_class_constant_map() -> Dictionary

class BuiltinType extends ClassType:
	var _type_name: StringName
	func _init(type_name: StringName) -> void:
		_type_name = type_name
	func get_class_name() -> String:
		return _type_name
	func get_class_property_list() -> Array[Dictionary]:
		return ClassDB.class_get_property_list(_type_name)
	func get_class_method_list() -> Array[Dictionary]:
		return ClassDB.class_get_method_list(_type_name)
	func get_class_constant_map() -> Dictionary:
		return {}

class ScriptType extends ClassType:
	var _class_script: Script
	## Used in case of a non-global autoload class
	var _autoload_name: String = ""
	func _init(class_script: Script, autoload_name: String = "") -> void:
		_class_script = class_script
		_autoload_name = autoload_name
	func get_class_name() -> String:
		return _autoload_name if _autoload_name != "" else _class_script.get_global_name()
	func get_class_property_list() -> Array[Dictionary]:
		return _class_script.get_script_property_list() + ClassDB.class_get_property_list(_class_script.get_instance_base_type())
	func get_class_method_list() -> Array[Dictionary]:
		return _class_script.get_script_method_list() + ClassDB.class_get_method_list(_class_script.get_instance_base_type())
	func get_class_constant_map() -> Dictionary:
		return _class_script.get_script_constant_map()

#endregion

#region AST Classes

## Node to represent the AST
class ASTNode:
	func get_path_to(target_node: ASTNode) -> String:
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

			if node is ASTNode:
				display += "()"
		return display

	var identifier: String
	var next: ASTNode


class ASTFunc extends ASTNode:
	var args: Array[ASTNode] = []

class ASTLiteral extends ASTNode:
	pass

class ASTOp extends ASTNode:
	var token_type: StringName

#endregion

#region Errors

enum TypeErrorType {
	Ok = 0,
	UnknownMember = 1,
	UnknownMethod = 2,
	UnknownEnum = 3,
	StaticInstanceAccess = 4,
	LocalVariant = 5,
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

class UnknownProperty extends TypeError:
	func _init(node: ASTNode, base: ASTNode, type: ClassType, is_static: bool) -> void:
		var path := str(base.get_path_to(node))
		var type_class_name := str(type.get_class_name()) if type != null else ""
		var base_context = '"%s"' % path
		if type_class_name != "" and type_class_name != path:
			base_context += " (%s)" % type_class_name
		if base == node:
			base_context = "usings or state autoload shortcuts"
		super._init(TypeErrorType.UnknownMember, 'Could not find %s "%s" in %s.' % ["property" if not is_static else "static variable", node.identifier, base_context])

class UnknownMethod extends TypeError:
	func _init(node: ASTNode, base: ASTNode, type: ClassType) -> void:
		var path := str(base.get_path_to(node))
		var type_class_name := str(type.get_class_name()) if type != null else ""
		var base_context = '"%s"' % path
		if type_class_name != "" and type_class_name != path:
			base_context += " (%s)" % type_class_name
		if base == node:
			base_context = "usings or state autoload shortcuts"
		super._init(TypeErrorType.UnknownMethod, 'Could not find "%s()" in %s.' % [node.identifier, base_context])

class UnknownEnum extends TypeError:
	func _init(node: ASTNode, base: ASTNode) -> void:
		super._init(TypeErrorType.UnknownEnum, 'Could not find enum "%s" in "%s".' % [node.identifier, base.get_path_to(node)])

class StaticInstanceAccess extends TypeError:
	func _init(node: ASTNode, base: ASTNode) -> void:
		super._init(TypeErrorType.StaticInstanceAccess, 'Cannot access instance member "%s" from "%s" in a static context.' % [node.identifier, base.get_path_to(node)])

#endregion
