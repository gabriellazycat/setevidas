extends Node
## Loads every script of the project so the engine reports all parse / compile errors at once.

func _ready() -> void:
	var files := []
	_walk("res://scripts", files)
	for f in files:
		var s = ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_REUSE)
		if s == null:
			print("FAILED ", f)
	print("CHECK DONE ", files.size())
	get_tree().quit()


func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	for sub in d.get_directories():
		_walk(dir.path_join(sub), out)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
