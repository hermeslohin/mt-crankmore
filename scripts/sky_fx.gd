extends Node2D
## Fireworks over the town, drawn on a layer above the night (see night.gd) so they shine in the dark. They are in the
## world's canvas coordinates, so this draws with the camera's transform.

var city: Node2D


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if city == null or not city.visible or city.events == null:
		return
	draw_set_transform_matrix(get_viewport().get_canvas_transform())
	city.events.draw_sky(self)
