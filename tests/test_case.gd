class_name TestCase
extends RefCounted
## 測試基底類別。見 tests/run_tests.gd。

var tree: SceneTree
var errors: Array[String] = []
var _nodes: Array[Node] = []


func before_each() -> void:
	pass


## 預設會釋放所有透過 add() 加進場景樹的節點。
func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	await tree.process_frame


func check(cond: bool, msg := "check failed") -> void:
	if not cond:
		errors.append(msg)


func check_eq(actual: Variant, expected: Variant, msg := "") -> void:
	if actual != expected:
		errors.append("%s expected %s, got %s" % [msg, str(expected), str(actual)])


func check_near(actual: float, expected: float, tol: float, msg := "") -> void:
	if absf(actual - expected) > tol:
		errors.append("%s expected %s ± %s, got %s" % [msg, expected, tol, actual])


## 把節點加到場景樹，測試結束時自動釋放。
func add(node: Node) -> Node:
	tree.root.add_child(node)
	_nodes.append(node)
	return node


## 等待 n 個物理幀。
func physics_frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


## 建立一個完整的 GameWorld（含關卡與玩家），測試結束時自動釋放。
## 回傳型別寫成 Node2D 而非 GameWorld，理由見 run_tests.gd。
func make_world() -> Node2D:
	var w: Node2D = load("res://scenes/game/game_world.tscn").instantiate()
	add(w)
	await tree.process_frame
	return w
