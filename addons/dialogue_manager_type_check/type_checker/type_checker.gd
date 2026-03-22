## DM TypeErrorType Checker
extends RefCounted

const DialogueManager := preload("res://addons/dialogue_manager/dialogue_manager.gd")
const DMSettings := preload("res://addons/dialogue_manager/settings.gd")
const DMConstants := preload("res://addons/dialogue_manager/constants.gd")

var _dialogue_manager: DialogueManager
var _cs_type_checker = null # don't preload as C# might not be compiled

var _strict := false

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
			var err = _verify_expression(item, null, global_scripts, item)
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
				# Not sure why bool tokens are compiled as var, but whatever
				if token[&"value"] in ["true", "false"]:
					new_node = ASTLiteral.new()
					new_node.identifier = token[&"value"]
				else:
					new_node = ASTNode.new()
					new_node.identifier = token[&"value"]
				
			DMConstants.TOKEN_FUNCTION:
				var func_node = ASTFunc.new()
				func_node.identifier = token[&"function"]
				# Recursive Step: DM stores function args as nested arrays/tokens
				if token.has(&"value"):
					for arg_tokens in token[&"value"]:
						func_node.args += _parse_expression_list(arg_tokens)
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

var STATIC_REGEX: RegEx = RegEx.create_from_string("^static var (?<property>[a-zA-Z_0-9]+)(:\\s?(?<type>[a-zA-Z_0-9]+))?")

## Verifies the type correctness of an expression.
## [ClassType] is a basic wrapper over a Script/built-in class
func _verify_expression(node: ASTNode, parent_class: ClassType, global_classes: Array[ClassType], base: ASTNode, is_static := false) -> TypeError:
	var base_classes := global_classes
	if parent_class != null:
		base_classes = []
		base_classes.assign([parent_class])
	
	if node is ASTOp:
		return TypeError.ok()
	elif node is ASTLiteral:
		return TypeError.ok()
	elif node is ASTFunc:
		var found_method: Dictionary = {}
		for class_type in base_classes:
			if parent_class == null:
				for method_info in BUILT_IN_TYPES:
					if method_info.name == node.identifier:
						found_method = method_info
			for method_info in class_type.get_class_method_list():
				if method_info.name == node.identifier:
					if is_static and not (method_info.flags & MethodFlags.METHOD_FLAG_STATIC):
						return StaticFuncAccess.new(node, base)
					found_method = method_info
			# Maybe a cs async function
			if _cs_type_checker and class_type is ScriptType and class_type.class_script.resource_path.ends_with(".cs"):
				var method_info = _cs_type_checker.GetCsScriptMethodInfo(class_type.class_script, node.identifier)
				if method_info != null:
					found_method = method_info
		
		if not found_method.is_empty():
			# Check args
			for arg in node.args:
				var err := _verify_expression(arg, null, global_classes, arg) # reset context as it's not chained
				if not err.is_ok():
					return err

			return TypeError.ok()

		return UnknownMethod.new(node, base, parent_class)
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
			var constant_val: Variant = constant_map.get(node.identifier)
			if constant_val != null:
				# Class
				if constant_val is Script:
					if node.next == null:
						# Weird subclass expression (MyClass.SubClass), but technically valid
						return TypeError.ok()
					member_class = ScriptType.new(constant_val)
					member_static = true
					break
				# Enum
				if constant_val is Dictionary:
					if node.next == null:
						# Weird enum base expression (MyClass.MyEnum), but technically valid
						return TypeError.ok()
					# If enum access, must only have tail next
					if node.next != null and node.next.next == null:
						var enum_value = node.next.identifier
						if constant_val.has(enum_value):
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
							member_class = _get_classtype_for_class_name(property_info["class_name"])
						if member_class:
							break
			# Still not found, might be static var
			if class_type is ScriptType and (class_type.class_script as Script).source_code.contains("static var"):
				for line: String in class_type.class_script.source_code.split("\n"):
					var matched: RegExMatch = STATIC_REGEX.search(line)
					if matched and matched.strings[matched.names.property] == node.identifier:
						# Tail and found value, OK
						if node.next == null:
							return TypeError.ok()
						# Not tail, check if type avail
						else:
							if matched.names.has("type"):
								var type: String = matched.strings[matched.names.type]
								member_class = _get_classtype_for_class_name(type)
		if member_class == null:
			return UnknownProperty.new(node, base, parent_class, is_static)
		if node.next != null:
			return _verify_expression(node.next, member_class, global_classes, base, member_static)
		return UnknownProperty.new(node, base, member_class, is_static)
	return UnknownProperty.new(node, base, parent_class, is_static)

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

static func _get_classtype_for_class_name(class_name_to_find: String) -> ClassType:
	if class_name_to_find == "": return null

	for class_data: Dictionary in ProjectSettings.get_global_class_list():
		if class_data.get(&"class") == class_name_to_find:
			return ScriptType.new(load(class_data.path))
	
	if ClassDB.class_exists(class_name_to_find):
		return BuiltinType.new(class_name_to_find)

	return null

#endregion

#region ClassType
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
	func _to_string() -> String:
		return "BuiltinType(%s)" % _type_name
	func get_class_name() -> String:
		return _type_name
	func get_class_property_list() -> Array[Dictionary]:
		return ClassDB.class_get_property_list(_type_name)
	func get_class_method_list() -> Array[Dictionary]:
		return ClassDB.class_get_method_list(_type_name)
	func get_class_constant_map() -> Dictionary:
		return {}

class ScriptType extends ClassType:
	var class_script: Script
	## Used in case of a non-global autoload class
	var _autoload_name: String = ""
	func _init(p_class_script: Script, autoload_name: String = "") -> void:
		class_script = p_class_script
		_autoload_name = autoload_name
	func _to_string() -> String:
		return "ScriptType(%s)" % class_script
	func get_class_name() -> String:
		return _autoload_name if _autoload_name != "" else class_script.get_global_name()
	func get_class_property_list() -> Array[Dictionary]:
		return class_script.get_script_property_list() + ClassDB.class_get_property_list(class_script.get_instance_base_type())
	func get_class_method_list() -> Array[Dictionary]:
		return class_script.get_script_method_list() + ClassDB.class_get_method_list(class_script.get_instance_base_type())
	func get_class_constant_map() -> Dictionary:
		return class_script.get_script_constant_map()

#endregion

#region AST Classes

## Node to represent the AST
class ASTNode:
	func get_path_to(target_node: ASTNode) -> String:
		var display = identifier
		var node := next

		const MAX := 99
		var i := 0
		while node != null:
			if node == target_node:
				return display
			display += "." + node.identifier
			node = node.next
			i += 1
			if i > MAX:
				push_error("Too many nodes in path")
				break
		return display

	func _to_string() -> String:
		var display = "Node(%s)" % identifier
		if next != null:
			display += " -> " + str(next)
		return display

	var identifier: String
	var next: ASTNode

class ASTFunc extends ASTNode:
	var args: Array[ASTNode] = []

	func _to_string() -> String:
		return "Func(%s)" % identifier

class ASTLiteral extends ASTNode:
	func _to_string() -> String:
		return "Literal(%s)" % identifier

class ASTOp extends ASTNode:
	var token_type: StringName

#endregion

#region Errors

enum TypeErrorType {
	Ok = 0,
	UnknownMember = 1,
	UnknownMethod = 2,
	UnknownEnum = 3,
	StaticMemberAccess = 4,
	StaticFuncAccess = 5,
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
		super._init(TypeErrorType.UnknownMember, 'Could not find %s "%s" in %s.' % ["property" if not is_static else "static variable or constant", node.identifier, base_context])

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
		super._init(TypeErrorType.StaticMemberAccess, 'Cannot access instance member "%s" from "%s" in a static context.' % [node.identifier, base.get_path_to(node)])

class StaticFuncAccess extends TypeError:
	func _init(node: ASTNode, base: ASTNode) -> void:
		super._init(TypeErrorType.StaticFuncAccess, 'Cannot access non-static function "%s"() from "%s" in a static context.' % [node.identifier, base.get_path_to(node)])

#endregion

#region Constants

const BUILT_IN_TYPES := [
	# Custom string casting
	{ &"name": "str", &"args": [{ &"name": "from", &"type": TYPE_NIL }], &"return": { &"type": TYPE_STRING } },
	# Vectors
	{ &"name": "Vector2", &"args": [{ &"name": "x", &"type": TYPE_FLOAT }, { &"name": "y", &"type": TYPE_FLOAT }], &"return": { &"type": TYPE_VECTOR2 } },
	{ &"name": "Vector2i", &"args": [{ &"name": "x", &"type": TYPE_INT }, { &"name": "y", &"type": TYPE_INT }], &"return": { &"type": TYPE_VECTOR2I } },
	{ &"name": "Vector3", &"args": [{ &"name": "x", &"type": TYPE_FLOAT }, { &"name": "y", &"type": TYPE_FLOAT }, { &"name": "z", &"type": TYPE_FLOAT }], &"return": { &"type": TYPE_VECTOR3 } },
	{ &"name": "Vector3i", &"args": [{ &"name": "x", &"type": TYPE_INT }, { &"name": "y", &"type": TYPE_INT }, { &"name": "z", &"type": TYPE_INT }], &"return": { &"type": TYPE_VECTOR3I } },
	{ &"name": "Vector4", &"args": [{ &"name": "x", &"type": TYPE_FLOAT }, { &"name": "y", &"type": TYPE_FLOAT }, { &"name": "z", &"type": TYPE_FLOAT }, { &"name": "w", &"type": TYPE_FLOAT }], &"return": { &"type": TYPE_VECTOR4 } },
	{ &"name": "Vector4i", &"args": [{ &"name": "x", &"type": TYPE_INT }, { &"name": "y", &"type": TYPE_INT }, { &"name": "z", &"type": TYPE_INT }, { &"name": "w", &"type": TYPE_INT }], &"return": { &"type": TYPE_VECTOR4I } },
	# Quaternion
	{ &"name": "Quaternion", &"args": [{ &"name": "x", &"type": TYPE_FLOAT }, { &"name": "y", &"type": TYPE_FLOAT }, { &"name": "z", &"type": TYPE_FLOAT }, { &"name": "w", &"type": TYPE_FLOAT }], &"return": { &"type": TYPE_QUATERNION } },
	# Callable Overloads
	{ &"name": "Callable", &"args": [], &"return": { &"type": TYPE_CALLABLE } },
	{ &"name": "Callable", &"args": [{ &"name": "method", &"type": TYPE_STRING_NAME }], &"return": { &"type": TYPE_CALLABLE } },
	{ &"name": "Callable", &"args": [{ &"name": "object", &"type": TYPE_OBJECT }, { &"name": "method", &"type": TYPE_STRING_NAME }], &"return": { &"type": TYPE_CALLABLE } },
	# Color Overloads
	{ &"name": "Color", &"args": [], &"return": { &"type": TYPE_COLOR } },
	{ &"name": "Color", &"args": [{ &"name": "from", &"type": TYPE_NIL }], &"return": { &"type": TYPE_COLOR } },
	{ &"name": "Color", &"args": [{ &"name": "from", &"type": TYPE_NIL }, { &"name": "alpha", &"type": TYPE_FLOAT }], &"return": { &"type": TYPE_COLOR } },
	{ &"name": "Color", &"args": [{ &"name": "r", &"type": TYPE_FLOAT }, { &"name": "g", &"type": TYPE_FLOAT }, { &"name": "b", &"type": TYPE_FLOAT }], &"return": { &"type": TYPE_COLOR } },
	{ &"name": "Color", &"args": [{ &"name": "r", &"type": TYPE_FLOAT }, { &"name": "g", &"type": TYPE_FLOAT }, { &"name": "b", &"type": TYPE_FLOAT }, { &"name": "a", &"type": TYPE_FLOAT }], &"return": { &"type": TYPE_COLOR } },
	# Resource Loading
	{ &"name": "load", &"args": [{ &"name": "path", &"type": TYPE_STRING }], &"return": { &"type": TYPE_OBJECT } },
	{ &"name": "Load", &"args": [{ &"name": "path", &"type": TYPE_STRING }], &"return": { &"type": TYPE_OBJECT } },
	# Custom Logic / Dice
	{ &"name": "roll_dice", &"args": [{ &"name": "sides", &"type": TYPE_INT }], &"return": { &"type": TYPE_INT } },
	{ &"name": "RollDice", &"args": [{ &"name": "sides", &"type": TYPE_INT }], &"return": { &"type": TYPE_INT } },
	{ &"name": "debug", &"args": [{ &"name": "message", &"type": TYPE_NIL }], &"return": { &"type": TYPE_NIL } },
	{ &"name": "Debug", &"args": [{ &"name": "message", &"type": TYPE_NIL }], &"return": { &"type": TYPE_NIL } },
	{ &"name": "wait", &"args": [{ &"name": "time", &"type": TYPE_FLOAT }], &"return": { &"type": TYPE_NIL } },
	{ &"name": "Wait", &"args": [{ &"name": "time", &"type": TYPE_FLOAT }], &"return": { &"type": TYPE_NIL } },
]
#endregion
