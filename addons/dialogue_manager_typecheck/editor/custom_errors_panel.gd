
@tool
extends "res://addons/dialogue_manager/components/errors_panel.gd"

const TypeChecker := preload("../type_checker/type_checker.gd")

func apply_warning_theme() -> void:
	error_button.add_theme_color_override("font_color", get_theme_color("warning_color", "Editor"))
	error_button.add_theme_color_override("font_hover_color", get_theme_color("warning_color", "Editor"))
	error_button.icon = get_theme_icon("StatusWarning", "EditorIcons")


func show_error() -> void:
	if errors.size() == 0:
		hide()
	else:
		show()
		count_label.text = DMConstants.translate(&"n_of_n").format({ index = error_index + 1, total = errors.size() })
		var error = errors[error_index]
		if "warning" in error:
			error_button.text = "Type error at {line}, {column}: {message}".format({ line = error.line_number, column = error.warning.column_number, message = error.warning.msg })
			apply_warning_theme()
		else:
			error_button.text = DMConstants.translate(&"errors.line_and_message").format({ line = error.line_number, column = error.column_number, message = DMConstants.get_error_message(error.error) })
			apply_theme()

func add_warnings(warnings: Dictionary[int, TypeChecker.TypeError]) -> void:
	for line_number in warnings:
		var error := {}
		error.line_number = line_number
		error.column_number = warnings[line_number].column_number
		error.warning = warnings[line_number]
		errors.append(error)
	errors.sort_custom(func(a, b): return a.line_number < b.line_number)

