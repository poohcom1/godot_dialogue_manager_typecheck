extends Node

enum Enum { A, B, C }
const TestConstant := 12
class TestClass:
	const TestClassContant := 12
	var test_class_member: int

var test_class_instance := TestClass.new()

func test_autoload():
	pass
