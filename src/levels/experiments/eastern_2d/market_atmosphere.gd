extends Node2D

## 细小的落叶与灵光，让静态原画在游戏里有呼吸感。

const PARTICLES := [
	Vector2(382, 407), Vector2(508, 338), Vector2(634, 462), Vector2(739, 367),
	Vector2(962, 485), Vector2(1103, 365), Vector2(1196, 552), Vector2(317, 627),
	Vector2(466, 692), Vector2(660, 774), Vector2(899, 709), Vector2(1075, 775),
	Vector2(1324, 665), Vector2(802, 547),
]

var _elapsed := 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()


func _draw() -> void:
	for index in range(PARTICLES.size()):
		var phase := float(index) * 1.73
		var origin: Vector2 = PARTICLES[index]
		var drift := Vector2(sin(_elapsed * 0.52 + phase) * 14.0, fposmod(_elapsed * (8.0 + float(index % 3) * 3.0) + phase * 9.0, 52.0) - 26.0)
		var alpha := 0.22 + 0.20 * (0.5 + 0.5 * sin(_elapsed * 1.8 + phase))
		var color := Color(0.95, 0.69, 0.27, alpha) if index % 3 == 0 else Color(0.70, 0.84, 0.68, alpha * 0.8)
		draw_circle(origin + drift, 1.6 + float(index % 3) * 0.5, color)
