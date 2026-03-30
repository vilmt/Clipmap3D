class_name CallableStateMachine

var _states: Dictionary[StringName, Dictionary]
var _current_state_name: StringName
var _queued_state_name: StringName
var _silent: bool

const STATE := 0
const ENTER := 1
const EXIT := 2

func add_state(state: Callable, enter := Callable(), exit := Callable()) -> void:
	var state_name := state.get_method()
	_states[state_name] = {}
	_states[state_name][STATE] = state
	if enter:
		_states[state_name][ENTER] = enter
	if exit:
		_states[state_name][EXIT] = exit

func remove_state(state: Callable) -> void:
	var state_name := state.get_method()
	_states.erase(state_name)

func queue_state(state: Callable, silent: bool = false) -> void:
	var state_name := state.get_method()
	if not _states.has(state_name):
		push_error("Unrecognized state %s was queued." % state_name)
		return
	_silent = silent
	_queued_state_name = state_name

func update() -> void:
	if _queued_state_name:
		_set_state(_queued_state_name)
		_queued_state_name = &""
	if _current_state_name:
		_states[_current_state_name][STATE].call()

func get_current_state() -> Callable:
	if _current_state_name:
		return _states[_current_state_name][STATE]
	return Callable()

func get_queued_state() -> Callable:
	if _queued_state_name:
		return _states[_queued_state_name][STATE]
	return Callable()

func _set_state(state_name: StringName):
	if _current_state_name and not _silent:
		if _states[_current_state_name].has(EXIT):
			_states[_current_state_name][EXIT].call()
	_current_state_name = state_name
	
	if _states[_current_state_name].has(ENTER) and not _silent:
		_states[_current_state_name][ENTER].call()
