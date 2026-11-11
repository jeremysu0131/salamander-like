extends SceneTree
## 極簡測試執行器。
##
## 用法：godot --headless --path . -s tests/run_tests.gd [-- test_檔名片段]
##
## 會載入 tests/ 底下所有 test_*.gd，執行其中以 test_ 開頭的函式。
## 測試腳本繼承 TestCase（tests/test_case.gd），用 check()／check_eq() 斷言。
## 測試函式可以是協程（使用 await），例如需要等物理幀時。

var failures := 0
var passed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# 等 autoload 就緒。
	await process_frame
	var filter := ""
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		filter = user_args[0]
	var files := DirAccess.get_files_at("res://tests")
	files.sort()
	for f in files:
		if not f.begins_with("test_") or not f.ends_with(".gd") or f == "test_case.gd":
			continue
		if filter != "" and not f.contains(filter):
			continue
		await _run_file("res://tests/" + f)
	print("\n%d passed, %d failed" % [passed, failures])
	quit(1 if failures > 0 else 0)


func _run_file(path: String) -> void:
	var script: GDScript = load(path)
	for m in script.get_script_method_list():
		var name: String = m.name
		if not name.begins_with("test_"):
			continue
		# 不寫成 TestCase 型別：否則本檔編譯時就會連帶編譯 GameWorld，
		# 那時 autoload 還沒註冊，會留下編譯失敗的快取。
		var tc: RefCounted = script.new()
		tc.tree = self
		await tc.before_each()
		await tc.call(name)
		await tc.after_each()
		if tc.errors.is_empty():
			passed += 1
			print("  ok   %s :: %s" % [path.get_file(), name])
		else:
			failures += 1
			print("  FAIL %s :: %s" % [path.get_file(), name])
			for e in tc.errors:
				print("         ", e)
