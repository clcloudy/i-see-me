extends Node
## 一轮一次请求；玩家文本只在内存中，不记录响应、密钥或输入。
signal completed(result: Dictionary, error: String)
var config: Dictionary
var theories: Array = []
var _request: HTTPRequest
var _submitted: Array = []
var _api_key := ""

func set_api_key(value: String) -> void:
	_api_key = value.strip_edges()

func has_api_key() -> bool:
	return not _api_key.is_empty()

func _exit_tree() -> void:
	cancel()
	_api_key = ""

func setup(settings: Dictionary, theory_catalog: Array = []) -> void:
	config = settings
	theories = theory_catalog.duplicate(true)
	_request = HTTPRequest.new()
	_request.timeout = 35.0
	_request.body_size_limit = 131072
	_request.max_redirects = 0
	add_child(_request)
	_request.request_completed.connect(_on_completed)

func cancel() -> void:
	if _request != null:
		_request.cancel_request()
	_submitted.clear()

func generate(entries: Array) -> void:
	cancel()
	if entries.is_empty():
		completed.emit({}, "empty")
		return
	if not has_api_key():
		completed.emit({}, "missing_key")
		return
	_submitted = entries.duplicate(true)
	var model := OS.get_environment("ISEEME_AI_MODEL").strip_edges()
	if model.is_empty():
		model = str(config["model"])
	var payload := {
		"model": model, "stream": false, "thinking": {"type": "disabled"},
		"max_tokens": 1800, "response_format": {"type": "json_object"},
		"messages": [
			{"role": "system", "content": str(config["system_prompt"]) + "\n学说资料（由游戏提供）：" + JSON.stringify(theories)},
			{"role": "user", "content": JSON.stringify({"entries": _submitted})}
		]
	}
	var error := _request.request(str(config["endpoint"]), ["Content-Type: application/json", "Authorization: Bearer " + _api_key], HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_submitted.clear()
		completed.emit({}, "network")

func _on_completed(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	if _submitted.is_empty():
		return
	var expected := _submitted.duplicate(true)
	_submitted.clear()
	if result == HTTPRequest.RESULT_SUCCESS and code in [401, 403]:
		completed.emit({}, "authentication")
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		completed.emit({}, "network")
		return
	var envelope: Variant = _parse_json(bytes.get_string_from_utf8())
	var valid := parse_response(envelope, expected)
	completed.emit(valid, "" if not valid.is_empty() else "invalid")

## 验证条目数量、id、原话及长度；不展示截断或无法对应玩家的输出。
func parse_response(envelope: Variant, expected: Array) -> Dictionary:
	if not envelope is Dictionary:
		return {}
	var choices: Variant = envelope.get("choices", [])
	if not choices is Array or choices.size() != 1 or not choices[0] is Dictionary:
		return {}
	var choice: Dictionary = choices[0]
	if choice.get("finish_reason", "") != "stop" or not choice.get("message") is Dictionary:
		return {}
	var parsed: Variant = _parse_json(str(choice["message"].get("content", "")))
	if not parsed is Dictionary or not parsed.get("items") is Array:
		return {}
	var items: Array = parsed["items"]
	if items.size() != expected.size():
		return {}
	var clean: Array = []
	for index in range(expected.size()):
		var item: Variant = items[index]
		var source: Dictionary = expected[index]
		if not item is Dictionary or item.get("id") != source["id"] or item.get("quote") != source["thought"]:
			return {}
		for field in ["reading", "uncertainty", "theory_id", "evidence"]:
			if not item.get(field) is String or str(item[field]).length() > 350:
				return {}
		if str(item["reading"]).strip_edges().is_empty() or str(item["uncertainty"]).strip_edges().is_empty():
			return {}
		var theory_id: String = item["theory_id"]
		var evidence: String = item["evidence"]
		if theory_id.is_empty():
			if not evidence.is_empty():
				return {}
		else:
			var known := false
			for theory in theories:
				known = known or theory["id"] == theory_id
			if not known or evidence.strip_edges().is_empty() or evidence.length() > 120 or not str(source["thought"]).contains(evidence):
				return {}
		clean.append({"id": source["id"], "quote": source["thought"], "reading": item["reading"], "uncertainty": item["uncertainty"], "theory_id": theory_id, "evidence": evidence})
	var summary: Variant = parsed.get("summary", "")
	if not summary is String or summary.length() > 400:
		return {}
	if expected.size() < 2:
		summary = ""
	return {"items": clean, "summary": summary}

func _parse_json(text: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	return parser.data
