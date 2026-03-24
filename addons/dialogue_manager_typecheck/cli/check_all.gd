extends Node

const TypeChecker := preload("res://addons/dialogue_manager_typecheck/type_checker/type_checker.gd")

func _ready():
	await get_tree().process_frame
	DMCache.prepare()
	var dialogue_files := DMCache.get_files()

	var type_checker := TypeChecker.new()

	print()
	print_rich("[color=gray]==== DM Typecheck started ====[/color]")
	print()

	var has_errors := false
	for file in dialogue_files:
		var dialogue: DialogueResource = load(file)
		var errors := await type_checker.check_type(dialogue.lines, dialogue.using_states)
		if len(errors) == 0:
			print_rich(" [color=green]✓[/color] [color=gray]%s[/color]" % dialogue.resource_path)
		else:
			has_errors = true
			print_rich(" [color=red]✕[/color] [color=#ff786b]%s[/color]" % dialogue.resource_path)
			for line in errors:
				print_rich("[color=#ff786b]   - Error at ln %d: %s" % [line, errors[line]])

	print()
	print_rich("[color=gray]==== DM Typecheck finished ====[/color]")
	print()

	type_checker.cleanup()

	await get_tree().create_timer(1).timeout

	get_tree().call_deferred("quit", 1 if has_errors else 0)
