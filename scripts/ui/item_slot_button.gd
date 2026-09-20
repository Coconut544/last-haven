class_name ItemSlotButton
extends Button
## One inventory/hotbar slot.
##
## Built in code and reused by the hotbar, the backpack grid and the container
## grid so every slot looks and behaves the same. The icon is a colour chip from
## the item definition until real item art exists.

signal slot_pressed(index: int)

const SLOT_SIZE := Vector2(76, 76)

var slot_index: int = -1
var stack: ItemStack = null
var selected: bool = false

var _chip: ColorRect
var _name_label: Label
var _count_label: Label


func _init() -> void:
	custom_minimum_size = SLOT_SIZE
	clip_text = true
	focus_mode = Control.FOCUS_NONE
	text = ""

	_chip = ColorRect.new()
	_chip.name = "Chip"
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.color = Color(0.18, 0.19, 0.18, 0.75)
	add_child(_chip)

	_name_label = Label.new()
	_name_label.name = "Name"
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.clip_text = true
	_name_label.add_theme_font_size_override("font_size", 11)
	add_child(_name_label)

	_count_label = Label.new()
	_count_label.name = "Count"
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.add_theme_font_size_override("font_size", 13)
	add_child(_count_label)

	pressed.connect(func() -> void: slot_pressed.emit(slot_index))


func setup(new_stack: ItemStack, index: int) -> void:
	stack = new_stack
	slot_index = index
	_refresh()


func set_selected(value: bool) -> void:
	selected = value
	_refresh()


func _refresh() -> void:
	if stack == null or stack.is_empty():
		text = ""
		tooltip_text = "Empty"
		_chip.color = Color(0.16, 0.17, 0.16, 0.7)
		_name_label.text = ""
		_count_label.text = ""
	else:
		var definition := stack.get_definition()
		var display_name := definition.display_name if definition != null else stack.item_id
		_chip.color = definition.icon_color if definition != null else Color(0.5, 0.5, 0.5)
		_name_label.text = display_name
		_count_label.text = "x%d" % stack.quantity if stack.quantity > 1 else ""
		tooltip_text = "%s\n%s" % [display_name, definition.description if definition != null else ""]
	_apply_selection_style()
	_layout()


func _apply_selection_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.1, 0.85)
	style.border_color = Color(0.95, 0.78, 0.35) if selected else Color(0.35, 0.37, 0.34)
	style.set_border_width_all(3 if selected else 1)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", style)
	add_theme_stylebox_override("pressed", style)
	add_theme_stylebox_override("focus", style)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _layout() -> void:
	if _chip == null:
		return
	var width := maxf(24.0, size.x)
	var height := maxf(24.0, size.y)
	_chip.position = Vector2(10, 8)
	_chip.size = Vector2(maxf(12.0, width - 20.0), maxf(12.0, height * 0.38))
	_name_label.position = Vector2(4, height * 0.48)
	_name_label.size = Vector2(width - 8, 16)
	_count_label.position = Vector2(4, height * 0.68)
	_count_label.size = Vector2(width - 8, 16)
