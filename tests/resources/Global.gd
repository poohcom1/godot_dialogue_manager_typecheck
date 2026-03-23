extends Node

enum GlobalEnum { A, B, C }

func test_global():
	pass

func test_args(_a, _b):
	pass

func test_args_typed(a: int, b: String, c: Vector2, d = "12"):
	print(get_method_list().filter(func(x): return x.name == "test_args_typed")[0])
	prints(a, b, c, d)

func test_vararg(_a, _b = 0, ..._args):
	pass
