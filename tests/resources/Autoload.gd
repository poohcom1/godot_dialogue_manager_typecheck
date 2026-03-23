extends Node

var string_member: String = "12"
enum Enum { A, B, C }
const TestConstant := 12
static var static_member: Node2D = Node2D.new()
class SubClass:
	const SubConstant := 12
	static var static_member := 12
	static func static_func(): pass
	var instance_member: int
	func instance_func(): pass

var subclass_instance := SubClass.new()
var node2d := TestNode2D.new()

var int_var: int = 1
var str_var: String = "hello"
var arr_var: Array = [1, 2, 3, 4]
var dict_var: Dictionary = { 
	"hello": 12,
	1: "hello"
}
var obj_var: RefCounted = RefCounted.new()

class TestNode2D extends Node2D:
	var num: int

func _ready() -> void:
	print(node2d.name)

func test_autoload():
	print(dict_var[int_var])
