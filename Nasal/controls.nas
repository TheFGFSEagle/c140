globals.controls.flapsDown = func(direction) {
	props.globals.setDoubleValue(
		"/controls/flight/flaps", math.clamp(props.globals.getValue("/controls/flight/flaps") + (direction * 0.01), 0, 1)
	);
};

