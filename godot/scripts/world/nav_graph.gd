class_name NavGraph
extends RefCounted
## Hand-placed navigation graph through the house (people and ghosts walk it). A* with optional
## per-node extra cost (the Shadow avoids lit rooms). Port of NavGraph.ts.

class NavNode:
	var id: String
	var p: Vector3
	var room: String
	var links: Array = []  # [{to: NavNode, ghost: bool, cost: float}]

var nodes: Dictionary = {}
var _room_hops: Dictionary = {}


func _init() -> void:
	var L := Layout.data()
	for n in L["NAV_NODES"]:
		var nn := NavNode.new()
		nn.id = n["id"]
		nn.p = Layout.v3(n["p"])
		nn.room = n["room"]
		nodes[nn.id] = nn
	for e in L["NAV_EDGES"]:
		var a: NavNode = nodes[e[0]]
		var b: NavNode = nodes[e[1]]
		var ghost: bool = e.size() > 2 and e[2] == true
		var c := a.p.distance_to(b.p)
		a.links.append({"to": b, "ghost": ghost, "cost": c})
		b.links.append({"to": a, "ghost": ghost, "cost": c})
	_build_room_hops()


func get_node(id: String) -> NavNode:
	return nodes[id]


func nearest(p: Vector3, ghost := false) -> NavNode:
	var best: NavNode = null
	var bd := INF
	for n: NavNode in nodes.values():
		if not ghost and n.room == "sotao":
			continue
		var d := Vector2(n.p.x - p.x, n.p.z - p.z).length() + absf(n.p.y - p.y) * 4.0
		if d < bd:
			bd = d
			best = n
	return best


## A* between two nodes. extra: optional Callable(NavNode) -> float added to the step cost.
func route(from: NavNode, to: NavNode, ghost := false, extra: Callable = Callable()) -> Array:
	if from == to:
		return [from]
	var open := {from: true}
	var came := {}
	var g := {from: 0.0}
	var f := {from: from.p.distance_to(to.p)}
	while not open.is_empty():
		var cur: NavNode = null
		var best := INF
		for n in open.keys():
			var v: float = f.get(n, INF)
			if v < best:
				best = v
				cur = n
		if cur == to:
			var path := [cur]
			while came.has(cur):
				cur = came[cur]
				path.push_front(cur)
			return path
		open.erase(cur)
		for l in cur.links:
			if l["ghost"] and not ghost:
				continue
			var nb: NavNode = l["to"]
			var ng: float = g.get(cur, INF) + l["cost"] + (extra.call(nb) if extra.is_valid() else 0.0)
			if ng < g.get(nb, INF):
				came[nb] = cur
				g[nb] = ng
				f[nb] = ng + nb.p.distance_to(to.p)
				open[nb] = true
	return [from, to]


## A* from a free position. A walker standing on an edge (mid-staircase) starts from that edge
## instead of the nearest node, which may be across a wall: the path is [behind, ahead, ...], so
## path[0] is where it stands and path[1] the next node, as on any route.
func route_from(p: Vector3, to: NavNode, ghost := false, extra: Callable = Callable()) -> Array:
	var near := nearest(p, ghost)
	var a: NavNode = null
	var b: NavNode = null
	var bd := 0.25
	for n: NavNode in nodes.values():
		for l in n.links:
			if l["ghost"] and not ghost:
				continue
			var m: NavNode = l["to"]
			var q := Geometry3D.get_closest_point_to_segment(p, n.p, m.p)
			var d := q.distance_to(p)
			if d < bd and q.distance_to(n.p) > 0.05 and q.distance_to(m.p) > 0.05:
				bd = d
				a = n
				b = m
	if a == null:
		return route(near, to, ghost, extra)
	var ra := route(a, to, ghost, extra)
	var rb := route(b, to, ghost, extra)
	if p.distance_to(a.p) + _cost(ra, extra) <= p.distance_to(b.p) + _cost(rb, extra):
		return [b] + ra if ra.size() < 2 or ra[1] != b else ra
	return [a] + rb if rb.size() < 2 or rb[1] != a else rb


## p already walks the leg a→b (close to the segment, nearer b than a is): no need to go back to a
static func on_first_leg(p: Vector3, a: Vector3, b: Vector3) -> bool:
	return p.distance_to(b) < a.distance_to(b) and Geometry3D.get_closest_point_to_segment(p, a, b).distance_to(p) < 0.3


func _cost(path: Array, extra: Callable) -> float:
	var c := 0.0
	for i in range(1, path.size()):
		c += (path[i - 1] as NavNode).p.distance_to(path[i].p) + (extra.call(path[i]) if extra.is_valid() else 0.0)
	return c


## world-space points from a position to a node (optionally ending at an exact point)
func path_to(from: Vector3, to_id: String, end = null, ghost := false) -> Array:
	var a := nearest(from, ghost)
	var b: NavNode = nodes[to_id]
	var ns := route(a, b, ghost)
	var pts: Array = []
	for n: NavNode in ns:
		pts.append(n.p)
	if pts.size() > 1:
		var d0 := from.distance_to(pts[1])
		var d01 := (pts[0] as Vector3).distance_to(pts[1])
		if d0 < d01 and absf(from.y - (pts[0] as Vector3).y) < 0.6:
			pts.pop_front()
	if end != null:
		pts.append(end)
	return pts


func hops(a: String, b: String) -> int:
	if a == b:
		return 0
	return _room_hops.get(a + "|" + b, 4)


func _build_room_hops() -> void:
	var adj := {}
	for r in Layout.rooms():
		adj[r["id"]] = {}
	for n: NavNode in nodes.values():
		for l in n.links:
			var to: NavNode = l["to"]
			if to.room != n.room:
				adj[n.room][to.room] = true
	adj["banheiro_cima"]["varanda"] = true
	adj["varanda"]["banheiro_cima"] = true
	for r in Layout.rooms():
		var start: String = r["id"]
		var dist := {start: 0}
		var q := [start]
		while not q.is_empty():
			var c: String = q.pop_front()
			for nb in adj[c].keys():
				if dist.has(nb):
					continue
				dist[nb] = dist[c] + 1
				q.append(nb)
		for k in dist.keys():
			_room_hops[start + "|" + k] = dist[k]
