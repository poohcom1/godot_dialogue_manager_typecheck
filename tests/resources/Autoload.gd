extends Node

enum Enum { A, B, C }
const TestConstant := 12
class SubClass:
	const Constant := 12
	var instance_member: int
	static func static_func(): pass
	func instance_func(): pass

var subclass_instance := SubClass.new()
var node2d := TestNode2D.new()

class TestNode2D extends Node2D:
	var num: int

func _ready() -> void:
	print(node2d.name)

func test_autoload():
	pass
