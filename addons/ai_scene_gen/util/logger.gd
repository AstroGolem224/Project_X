class_name AiSceneGenLogger
extends RefCounted

## Centralized logging facade for all AI Scene Gen plugin modules.

enum LogLevel {
	DEBUG = 0,
	INFO = 1,
	WARNING = 2,
	ERROR = 3
}

const LOG_PREFIX: String = "[AI_SCENE_GEN]"

var _min_level: int = LogLevel.INFO
var _metrics: Dictionary = {}
var _telemetry_enabled: bool = false


## Logs message only if current log level <= DEBUG.
func log_debug(category: String, message: String) -> void:
	if _min_level <= LogLevel.DEBUG:
		_print_formatted("DEBUG", category, message, "gray")


## Logs message only if current log level <= INFO.
func log_info(category: String, message: String) -> void:
	if _min_level <= LogLevel.INFO:
		_print_formatted("INFO", category, message, "white")


## Logs message only if current log level <= WARNING. Also calls push_warning.
func log_warning(category: String, message: String) -> void:
	if _min_level <= LogLevel.WARNING:
		var formatted: String = _format_message("WARN", category, message)
		print_rich("[color=yellow]%s[/color]" % formatted)
		push_warning(formatted)


## Always logs. Also calls push_error.
func log_error(category: String, message: String) -> void:
	var formatted: String = _format_message("ERROR", category, message)
	print_rich("[color=red]%s[/color]" % formatted)
	push_error(formatted)


## Records a metric value; updates count, sum, min, max. Ignores NaN with a warning.
func record_metric(metric_name: String, value: float) -> void:
	if is_nan(value):
		log_warning("Logger", "record_metric: ignoring NaN for metric '%s'" % metric_name)
		return
	if metric_name not in _metrics:
		_metrics[metric_name] = {"count": 0, "sum": 0.0, "min": INF, "max": -INF}
	var m: Dictionary = _metrics[metric_name]
	m["count"] += 1
	m["sum"] += value
	m["min"] = minf(m["min"], value)
	m["max"] = maxf(m["max"], value)


## Returns a copy of metrics with avg (sum/count) calculated per metric.
func get_metrics_summary() -> Dictionary:
	var summary: Dictionary = {}
	for key in _metrics:
		var m: Dictionary = _metrics[key]
		var avg: float = m["sum"] / m["count"] if m["count"] > 0 else 0.0
		summary[key] = {
			"count": m["count"],
			"sum": m["sum"],
			"min": m["min"],
			"max": m["max"],
			"avg": avg
		}
	return summary


func set_log_level(level: int) -> void:
	_min_level = level


func get_log_level() -> int:
	return _min_level


func set_telemetry_enabled(enabled: bool) -> void:
	_telemetry_enabled = enabled


func is_telemetry_enabled() -> bool:
	return _telemetry_enabled


func clear_metrics() -> void:
	_metrics.clear()


func _print_formatted(level_label: String, category: String, message: String, color: String) -> void:
	var formatted: String = _format_message(level_label, category, message)
	print_rich("[color=%s]%s[/color]" % [color, formatted])


func _format_message(level_label: String, category: String, message: String) -> String:
	return "%s[%s][%s] %s" % [LOG_PREFIX, level_label, category, message]
