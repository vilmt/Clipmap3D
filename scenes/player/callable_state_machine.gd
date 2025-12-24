class_name CallableStateMachine

var states: Dictionary[StringName, Dictionary]

var current_state_name: StringName
var queued_state_name: StringName

var _queued_silent: bool

func add_state(state: Callable, enter := Callable(), exit := Callable()) -> void:
	var state_name := state.get_method()
	states[state_name] = {}
	states[state_name]["state"] = state
	if enter:
		states[state_name]["enter"] = enter
	if exit:
		states[state_name]["exit"] = exit

func remove_state(state: Callable) -> void:
	var state_name := state.get_method()
	states.erase(state_name)

func queue_state(state: Callable, silent: bool = false) -> void:
	var state_name := state.get_method()
	if not states.has(state_name):
		push_error("[CallableStateMachine] Attempted changing to undeclared state " + str(state_name))
		return
	_queued_silent = silent
	queued_state_name = state_name

func update() -> void:
	if queued_state_name:
		_set_state(queued_state_name)
		queued_state_name = &""
	if current_state_name:
		states[current_state_name]["state"].call()

func get_current_state() -> Callable:
	if current_state_name:
		return states[current_state_name]["state"]
	return Callable()

func get_queued_state() -> Callable:
	if queued_state_name:
		return states[queued_state_name]["state"]
	return Callable()

func _set_state(state_name: StringName):
	if current_state_name and not _queued_silent:
		if states[current_state_name].has("exit"):
			states[current_state_name]["exit"].call()
	current_state_name = state_name
	
	if states[current_state_name].has("enter") and not _queued_silent:
		states[current_state_name]["enter"].call()
