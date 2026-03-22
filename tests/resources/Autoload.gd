extends Node

enum Enum { A, B, C }
const TestConstant := 12
class TestClass:
	const TestClassContant := 12
	var test_class_member: int

var test_class_instance := TestClass.new()
var node2d := Node2D.new()

func _ready() -> void:
	print(node2d.name)

func test_autoload():
	pass
