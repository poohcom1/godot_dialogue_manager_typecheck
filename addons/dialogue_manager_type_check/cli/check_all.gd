extends Node

const TypeChecker := preload("res://addons/dialogue_manager_type_check/type_checker/type_checker.gd")

func _ready():
	await get_tree().process_frame
	DMCache.prepare()
	var dialogue_files := DMCache.get_files()

	print()
	print_rich("[color=gray]==== DM Typecheck started ====[/color]")
	print()

	var has_errors := false
	for file in dialogue_files:
		var dialogue: DialogueResource = load(file)
		var errors := TypeChecker.check_type(dialogue)
		if len(errors) == 0:
			print_rich(" [color=green]✓[/color] [color=gray]%s[/color]" % dialogue.resource_path)
		else:
			has_errors = true
			print_rich(" [color=red]✕[/color] [color=#ff786b]%s[/color]" % dialogue.resource_path)
			for line in errors:
				print_rich("[color=#ff786b]   - Error at ln %d:[/color] %s" % [line, errors[line]])

	print()
	print_rich("[color=gray]==== DM Typecheck finished ====[/color]")
	print()

	get_tree().quit(1 if has_errors else 0)
