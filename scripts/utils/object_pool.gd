class_name ObjectPool
extends RefCounted

## 物件池 - 用於減少頻繁創建和銷毀物件的開銷

var _pool: Array = []
var _scene: PackedScene
var _max_size: int
var _create_func: Callable


func _init(scene: PackedScene = null, max_size: int = 100) -> void:
	_scene = scene
	_max_size = max_size


## 使用自定義創建函數初始化
func set_create_function(create_func: Callable) -> void:
	_create_func = create_func


## 獲取一個物件
func get_object() -> Node:
	if not _pool.is_empty():
		var obj: Node = _pool.pop_back()
		if is_instance_valid(obj):
			return obj

	return _create_new()


## 回收物件
func release(obj: Node) -> void:
	if obj == null or not is_instance_valid(obj):
		return

	if _pool.size() < _max_size:
		# 從父節點移除
		if obj.get_parent():
			obj.get_parent().remove_child(obj)

		# 重置物件狀態（由物件自己實現 reset 方法）
		if obj.has_method("reset"):
			obj.reset()

		_pool.append(obj)
	else:
		# 池已滿，直接銷毀
		obj.queue_free()


## 預熱池
func warm_up(count: int) -> void:
	for i in range(count):
		if _pool.size() >= _max_size:
			break
		var obj := _create_new()
		if obj:
			_pool.append(obj)


## 清空池
func clear() -> void:
	for obj in _pool:
		if is_instance_valid(obj):
			obj.queue_free()
	_pool.clear()


## 獲取當前池大小
func size() -> int:
	return _pool.size()


func _create_new() -> Node:
	if _create_func.is_valid():
		return _create_func.call()
	elif _scene:
		return _scene.instantiate()
	return null
