# Helpers
static func search_child(node: Node, cond: Callable) -> Node:
	for child in node.get_children():
		if cond.call(child):
			return child
		else:
			var result = search_child(child, cond)
			if result != null:
				return result
	return null
