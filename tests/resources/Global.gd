extends Node

enum GlobalEnum { A, B, C }

func test_global():
	for method in get_method_list():
		if method.name == "test_vararg":
			print(method)
	pass

func test_args(_a, _b):
	pass

func test_args_typed(_a: int, _b: String, _c: Vector2):
	pass

func test_vararg(_a, _b = 0, ..._args):
	pass
