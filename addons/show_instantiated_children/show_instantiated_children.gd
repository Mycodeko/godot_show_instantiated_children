@tool
extends EditorPlugin

const TIMER_NODE_NAME: String = "show_instantiated_children_timer"

const DEBUG = true

var timer: Timer = null
var timer_tick = -1
var processed_scene_tree_dialogs: Array = []
var scene_tree_dialog_to_scene_tree_editor: Dictionary[Node, Node] = {}
var scene_tree_dialog_to_node_to_previous_children_editable_instance: Dictionary = {}

func recursive_iterate(node: Node, include_parent: bool = false) -> Array[Node]:
	var return_nodes: Array[Node] = []
	if include_parent:
		return_nodes.append(node)

	for child_node in node.get_children():
		return_nodes.append_array(recursive_iterate(child_node, true))

	return return_nodes

func scene_tree_dialog_visibility_changed(scene_tree_dialog: ConfirmationDialog, first_open: bool = false):
	if scene_tree_dialog.visible:
		if DEBUG:
			print("Overriding node editable...")

		var scene_tree_editor = scene_tree_dialog_to_scene_tree_editor.get(scene_tree_dialog, null)

		if scene_tree_editor != null:
			# Cannot access this method.
			# scene_tree_editor.set_display_foreign_nodes(true)
			# Also isn't exposed.
			# print(scene_tree_editor.display_foreign)
			var node_to_previous_children_editable_instance = {}
			scene_tree_dialog_to_node_to_previous_children_editable_instance[scene_tree_dialog] = node_to_previous_children_editable_instance

			# TODO: Use tree from scene_tree_editor instead of global.
			var edited_scene_root = get_tree().get_edited_scene_root()
			for child_node in recursive_iterate(edited_scene_root):
				node_to_previous_children_editable_instance[child_node] = edited_scene_root.is_editable_instance(child_node)
				edited_scene_root.set_editable_instance(child_node, true)
		else:
			push_warning("Unable to find SceneTreeEditor for dialog '" + str(scene_tree_dialog.get_path()) + "', which previously had one.")
	elif not first_open:
		var node_to_previous_children_editable_instance = scene_tree_dialog_to_node_to_previous_children_editable_instance.get(scene_tree_dialog, null)
		if node_to_previous_children_editable_instance != null:
			var edited_scene_root = get_tree().get_edited_scene_root()
			for node in node_to_previous_children_editable_instance:
				edited_scene_root.set_editable_instance(node, node_to_previous_children_editable_instance[node])
		else:
			push_error("Failed to get previous editable instance values for dialog '" + str(scene_tree_dialog.get_path()) + "', this has likely override all the values of the scene.")

func register_scene_tree_dialog(scene_tree_dialog: ConfirmationDialog):
	processed_scene_tree_dialogs.append(scene_tree_dialog)

	var scene_tree_editor = null
	for child_node in recursive_iterate(scene_tree_dialog):
		if child_node.get_class() == "SceneTreeEditor":
			scene_tree_editor = child_node
			break

	if scene_tree_editor != null:
		if DEBUG:
			print("Found SceneTreeEditor, connecting signals.")

		scene_tree_dialog_to_scene_tree_editor[scene_tree_dialog] = scene_tree_editor

		scene_tree_dialog.visibility_changed.connect(scene_tree_dialog_visibility_changed.bind(scene_tree_dialog, false))

		scene_tree_dialog_visibility_changed(scene_tree_dialog, true)
	else:
		push_warning("Unable to find SceneTreeEditor for dialog '" + str(scene_tree_dialog.get_path()) + "', skipping.")

func _timer_timeout():
	timer_tick += 1

	if timer_tick % 5 == 0:
		# TODO: Access via singleton: https://docs.godotengine.org/en/stable/classes/class_editorinterface.html#class-editorinterface
		var editor_control_nodes: Array[Node] = recursive_iterate(self.get_editor_interface().get_base_control())
		for node in editor_control_nodes:
			if node is LineEdit:
				if node.placeholder_text.to_lower().begins_with("filter nodes"):
					var scene_tree_dialog = node.get_parent()
					while scene_tree_dialog != null and scene_tree_dialog.get_class() != "SceneTreeDialog":
						scene_tree_dialog = scene_tree_dialog.get_parent()

					if scene_tree_dialog != null and scene_tree_dialog is ConfirmationDialog and scene_tree_dialog not in processed_scene_tree_dialogs:
						register_scene_tree_dialog(scene_tree_dialog)

func _child_entered_tree(node: Node):
	if node.get_class() == "SceneTreeDialog":
		var scene_tree_dialog = node

		if scene_tree_dialog is ConfirmationDialog and scene_tree_dialog not in processed_scene_tree_dialogs:
			register_scene_tree_dialog(scene_tree_dialog)

func _cleanup():
	if timer != null:
		if timer.timeout.is_connected(_timer_timeout):
			timer.timeout.disconnect(_timer_timeout)
		timer.queue_free()
	timer = null

	for node in self.get_editor_interface().get_base_control().get_children():
		if node.name == TIMER_NODE_NAME:
			node.queue_free()

	for scene_tree_dialog in processed_scene_tree_dialogs:
		if scene_tree_dialog.is_instance_valid():
			var bound_visibility_changed_function = scene_tree_dialog_visibility_changed.bind(scene_tree_dialog)

			if scene_tree_dialog.visibility_changed.is_connected(bound_visibility_changed_function):
				scene_tree_dialog.visibility_changed.disconnect(bound_visibility_changed_function)
			else:
				push_warning("Could not disconnect visibility_changed.")
	processed_scene_tree_dialogs.clear()

	scene_tree_dialog_to_scene_tree_editor.clear()
	scene_tree_dialog_to_node_to_previous_children_editable_instance.clear()

	if self.get_editor_interface().get_base_control().child_entered_tree.is_connected(_child_entered_tree):
		self.get_editor_interface().get_base_control().child_entered_tree.disconnect(_child_entered_tree)

	if get_tree().node_added.is_connected(_child_entered_tree):
		get_tree().node_added.disconnect(_child_entered_tree)

func _enter_tree() -> void:
	timer = Timer.new()
	timer.name = TIMER_NODE_NAME
	timer.wait_time = 1
	timer.timeout.connect(_timer_timeout)

	self.get_editor_interface().get_base_control().add_child(timer)
	timer.start()

	self.get_editor_interface().get_base_control().child_entered_tree.connect(_child_entered_tree)
	get_tree().node_added.connect(_child_entered_tree)

func _exit_tree() -> void:
	_cleanup()