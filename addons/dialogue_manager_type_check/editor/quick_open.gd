extends ConfirmationDialog

const DMFilesListScene: PackedScene = preload("res://addons/dialogue_manager/components/files_list.tscn")
const DMFilesList: Script = preload("res://addons/dialogue_manager/components/files_list.gd")

var files_list: DMFilesList

func _init():
	title = "Select Dialogue File"
	size = Vector2(600, 900)
	min_size = Vector2(600, 900)
	ok_button_text = "Open"

	files_list = DMFilesListScene.instantiate()
	files_list.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(files_list)

func _ready():
	files_list.file_double_clicked.connect(func(file_path: String):
		hide()
	)
