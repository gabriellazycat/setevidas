class_name Interactions
extends RefCounted
## Everything the cat can do to the world (switches, doors, plugs, faucets, carrying, the chest, the
## ritual circle, the duct and the window, the attic cord, the cat bed, purring, hiding, begging for
## pets, playing, eating, the bathtub, the key of day 1, scratching at the outside doors) and the picker
## that chooses the best one in reach.
## Port of Interactions.ts + Interactables.ts.

const CLUES := ["foto", "coleira", "chave"]


class Interactable:
	var id: String
	var pos := Vector3.ZERO
	var pos_fn: Callable = Callable()   # moving targets (a person)
	var radius := 0.8
	var above := 0.9
	var below := 0.5
	var prompt: Callable
	var enabled: Callable
	var hold = 0.0                      # float or Callable -> float
	var priority := 0
	var omni := false
	var on_interact: Callable
	var hold_label: Callable = Callable()
	var pose := "busy"
	var outline: Callable = Callable()   # -> the nodes it outlines (InteractMarks); none: only the button

	func p() -> Vector3:
		return pos_fn.call() if pos_fn.is_valid() else pos

	func hold_time() -> float:
		return float(hold.call()) if hold is Callable else float(hold)


var list: Array = []


func add(d: Dictionary) -> Interactable:
	var it := Interactable.new()
	for k in d:
		it.set(k, d[k])
	list.append(it)
	return it


func find(id: String) -> Interactable:
	for it: Interactable in list:
		if it.id == id:
			return it
	return null


func best(cat_pos: Vector3, forward: Vector3) -> Interactable:
	var bst: Interactable = null
	var best_score := -INF
	for it: Interactable in list:
		var ip := it.p()
		var dy := ip.y - cat_pos.y
		if dy > it.above or dy < -it.below:
			continue
		var dd := Vector3(ip.x - cat_pos.x, 0, ip.z - cat_pos.z)
		var dist := dd.length()
		if dist > it.radius:
			continue
		if not it.enabled.call():
			continue
		var facing := 1.0
		if dist > 0.05:
			dd /= dist
			facing = dd.dot(forward)
			if not it.omni and facing < -0.25 and dist > 0.35:
				continue
		var score := it.priority * 10.0 - dist * 2.0 + facing * 1.2
		if score > best_score:
			best_score = score
			bst = it
	return bst


static func ritual_slot(i: int) -> Vector3:
	var c := Layout.v3(Layout.data()["RITUAL_CENTER"])
	var a := -PI / 2 + float(i) / 3.0 * TAU
	return Vector3(c.x + cos(a) * 0.85, c.y, c.z + sin(a) * 0.85)


func register(g: Game) -> void:
	var h := g.house
	var cat := g.cat
	var night := func() -> bool: return g.phase == "night"

	# ---- light switches
	for l: LightSystem.RoomLight in h.lights.lights:
		if l.switch_pos == null:
			continue
		var room: String = l.room()
		var room_name := Layout.room_name(room).to_lower() if room != "" else ""
		var sp: Vector3 = l.switch_pos + l.switch_normal * 0.25
		sp.y = (l.switch_pos as Vector3).y
		add({"id": "sw_%d" % l.index, "pos": sp, "radius": 0.85, "above": 1.4, "below": 0.6, "omni": true,
			"outline": func(): return g.marks.near_meshes(l.switch_pos, 0.16),
			"prompt": func(): return "A lâmpada não responde..." if l.dead > 0 else tr("%s a luz%s") % [tr("Apagar") if l.on else tr("Acender"), tr(" (%s)") % room_name if room_name != "" else ""],
			"enabled": func(): return true,
			"on_interact": func():
				g.cat_reach(l.switch_pos, func():
					if l.dead > 0:
						Sfx.click(l.switch_pos, 0.4)
						return
					h.lights.toggle(l)
					Sfx.click(l.switch_pos, 0.5)
					g.on_light_toggled(l.index, l.on))})
	# ---- bedside lamps
	for li in [[8, Vector3(0.3, 3.55, 1.68), "abajur"], [17, Vector3(0.3, 3.55, 9.32), "abajur_hosp"]]:
		var lamp: LightSystem.RoomLight = h.lights.get_light(li[0])
		if lamp == null:
			continue
		var lp: Vector3 = li[1]
		if lamp.light:
			lp = Vector3(lamp.light.position.x, lamp.light.position.y - 0.45, lamp.light.position.z)
		add({"id": li[2], "pos": lp, "radius": 0.85, "above": 0.9, "omni": true,
			"outline": func(): return g.marks.near_meshes(lamp.light.global_position, 0.4) if lamp.light else [],
			"prompt": func(): return "O abajur não acende..." if lamp.dead > 0 else tr("%s o abajur") % (tr("Apagar") if lamp.on else tr("Acender")),
			"enabled": func(): return true,
			"on_interact": func():
				g.cat_reach(lamp.light.global_position if lamp.light else lp, func():
					if lamp.dead > 0:
						return
					h.lights.toggle(lamp)
					Sfx.click(lamp.light.global_position, 0.4)
					g.on_light_toggled(lamp.index, lamp.on))})

	# ---- doors
	for d: Door in h.doors.values():
		if d.def.get("style", "") == "front":
			continue
		var c := d.center()
		for side in [-1.0, 1.0]:
			var p := d.side_point(side, 0.45)
			p.y = float(d.def["y"])
			add({"id": "door_%s_%d" % [d.id, int(side)], "pos": p, "radius": 0.7, "above": 0.6, "below": 0.4, "omni": true, "priority": 1,
				"outline": func(): return [d.leaf] if d.leaf else [],
				"prompt": func(): return "Arranhar a porta" if d.locked else "Abrir a porta",
				"enabled": func(): return d.is_closed,
				"hold": func(): return 5.0 if d.locked else 0.9,
				"pose": "scratch",
				"hold_label": func(): return "Arranhando..." if d.locked else "Empurrando...",
				"on_interact": func():
					if d.locked:
						d.locked = false
						g.clara.add_patience(-8)
						g.emit_noise(c, 0.6, "scratch")
						g.on_escaped_lock()
					d.set_state("ajar")
					Sfx.creak(c + Vector3(0, 1, 0), 0.4, 1.0)})

	# ---- devices: pull the plug
	for dv: House.Device in h.devices:
		add({"id": "plug_" + dv.id, "pos_fn": func(): return dv.outlet + dv.normal * 0.25, "radius": 0.8, "above": 1.4, "below": 0.6, "omni": true, "priority": 2,
			"outline": func(): return [dv.plug] if dv.plug else [],
			"prompt": func(): return tr("Puxar o fio: %s") % tr(dv.name),
			"enabled": func(): return dv.plugged and not dv.hidden and (dv.id != "nightlight" or g.phase == "night"),
			"on_interact": func():
				g.cat_reach(dv.outlet, func():
					if not dv.plugged:
						return
					h.set_plugged(dv, false)
					Sfx.click(dv.outlet, 0.7)
					Sfx.thud(dv.outlet, 0.15, 200)
					g.on_task("unplug"))})

	# ---- faucets
	for f: House.Faucet in h.faucets:
		add({"id": "faucet_" + f.id, "pos": Vector3(f.handle.x, f.floor_y, f.handle.z), "radius": 1.0 if f.id == "tub" else 0.85, "above": 1.4, "below": 0.6, "omni": true, "priority": 2,
			"outline": func(): return g.marks.near_meshes(f.handle, 0.16),
			"prompt": func(): return "Puxar a tampa do ralo" if f.id == "tub" else tr("Fechar a torneira (%s)") % tr(f.name),
			"enabled": func(): return f.running > 0.04,
			"hold": 0.6, "pose": "busy",
			"on_interact": func():
				g.director.drowner.close_faucet(f)
				if f.id == "tub":
					f.level = minf(f.level, 0.6)})

	# ---- night relics with a rule: washed in the bathroom sink (from the floor or up on it), fished
	# out of the drain, out of the mailbox
	for f: House.Faucet in h.faucets:
		if f.id == "tub":
			continue
		add({"id": "wash_" + f.id, "pos": Vector3(f.handle.x, f.floor_y, f.handle.z), "radius": 0.9, "above": 1.4, "below": 1.3, "omni": true, "priority": 4,
			"prompt": func(): return tr("Lavar %s na pia do banheiro") % tr(cat.carrying.name),
			"enabled": func(): return f.id == "banb" and g.phase == "night" and cat.carrying != null and g.carrying_dirty(),
			"hold": 2.0, "pose": "busy",
			"on_interact": func(): g.wash_carried(f)})
		add({"id": "drain_" + f.id, "pos": Vector3(f.handle.x, f.floor_y, f.handle.z), "radius": 0.9, "above": 1.4, "below": 0.6, "omni": true, "priority": 4,
			"prompt": func(): return "Puxar o que caiu no ralo",
			"enabled": func(): return g.phase == "night" and cat.carrying == null and g.hidden_relic_at(f.basin_c, 0.8) != null,
			"hold": 2.0, "pose": "scratch",
			"on_interact": func():
				var r = g.hidden_relic_at(f.basin_c, 0.8)
				if r:
					g.take_hidden_relic(r)})
	add({"id": "mailbox", "pos": Game.MAILBOX_POS, "radius": 0.9, "above": 1.4, "below": 0.5, "omni": true, "priority": 4,
		"prompt": func(): return "Puxar a carta da caixa de correio",
		"enabled": func(): return g.phase == "night" and cat.carrying == null and g.hidden_relic_at(Game.MAILBOX_POS, 0.5) != null,
		"hold": 1.2, "pose": "scratch",
		"on_interact": func():
			var r = g.hidden_relic_at(Game.MAILBOX_POS, 0.5)
			if r:
				g.take_hidden_relic(r)})

	# ---- carryables
	var pickup := func(id: String): pick(g, id)
	for id: String in h.carryables.keys():
		_add_pick(g, id, pickup)

	# ---- put the doll back in the chest
	add({"id": "chest", "pos": Vector3(h.chest_pos.x, h.chest_pos.y, h.chest_pos.z - 0.7), "radius": 0.9, "above": 0.9, "omni": true, "priority": 5,
		"prompt": func(): return "Guardar a boneca no baú",
		"enabled": func(): return cat.carrying != null and cat.carrying.id == "doll",
		"on_interact": func():
			var c: PropSystem.Carryable = cat.carrying
			cat.carrying = null
			c.carried = false
			g.director.doll.returned()})

	# ---- ritual circle
	var rc := h.ritual_center
	add({"id": "ritual_place", "pos": rc, "radius": 1.6, "above": 0.6, "omni": true, "priority": 5,
		"prompt": func(): return tr("Colocar %s no círculo") % tr(cat.carrying.name),
		"enabled": func(): return cat.carrying != null and cat.carrying.id in CLUES and g.day == Config.LAST_NIGHT,
		"on_interact": func():
			var c: PropSystem.Carryable = cat.carrying
			var id: String = c.id
			cat.carrying = null
			c.carried = false
			var n := 0
			for k in CLUES:
				if g.flags["clues"][k] != null and g.flags["clues"][k]["on_circle"]:
					n += 1
			var slot := ritual_slot(n)
			c.place(slot + Vector3(0, 0.005, 0), randf() * 6.0)
			g.flags["clues"][id] = {"x": slot.x, "y": slot.y, "z": slot.z, "on_circle": true}
			Sfx.bell(slot, 1, 0.25)
			g.on_ritual_item()})
	add({"id": "relic_place", "pos": rc, "radius": 1.6, "above": 0.6, "omni": true, "priority": 5,
		"prompt": func(): return tr("Deixar %s no círculo") % tr(cat.carrying.name),
		"enabled": func(): return night.call() and g.is_relic(cat.carrying),
		"on_interact": func(): g.deliver_relic()})
	add({"id": "ritual_do", "pos": rc, "radius": 1.3, "above": 0.6, "omni": true, "priority": 6,
		"prompt": func(): return "Completar o ritual",
		"enabled": func(): return g.day == Config.LAST_NIGHT and cat.carrying == null and g.ritual_ready() and night.call(),
		"hold": func(): return 3.0,
		"pose": "busy",
		"hold_label": func(): return "O círculo responde...",
		"on_interact": func(): g.complete_ritual()})

	# ---- duct between the laundry and the kitchen
	var duct_ends := [Vector3(10.95, -3, 0.45), Vector3(10.8, 0, 3.95)]
	for i in 2:
		var p: Vector3 = duct_ends[i]
		add({"id": "duct_%d" % i, "pos": p, "radius": 0.75, "above": 0.6, "below": 0.5, "omni": true, "priority": 2,
			"prompt": func(): return ("Entrar no duto (para a cozinha)" if i == 0 else "Entrar no duto (para a lavanderia)") if h.duct_target > 0.5 else "Abrir a grade do duto",
			"enabled": func(): return cat.carrying == null or h.duct_target > 0.5,
			"hold": func(): return 0.0 if h.duct_target > 0.5 else 1.2,
			"pose": "scratch",
			"on_interact": func():
				if h.duct_target < 0.5:
					h.set_duct(true)
					g.flags["duct_open"] = true
					Sfx.creak(p + Vector3(0, 0.2, 0), 0.3, 0.6, 2.4)
					Sfx.thud(p, 0.2, 160)
					g.on_task("duct")
					return
				var other: Vector3 = duct_ends[1 - i]
				g.passage(other + (Vector3(0, 0, 0.25) if i == 0 else Vector3(0, 0, -0.3)), PI if i == 0 else 0.0, "duct")})

	# ---- bathroom window (basculante)
	add({"id": "basculante_in", "pos": Vector3(10.4, 3.9, 6.3), "radius": 0.7, "above": 1.0, "below": 0.3, "omni": true, "priority": 2,
		"prompt": func(): return "Passar pela janela (varanda)" if h.basculante_target > 0.5 else "Abrir a janela basculante",
		"enabled": func(): return true,
		"hold": func(): return 0.0 if h.basculante_target > 0.5 else 1.4,
		"pose": "scratch",
		"on_interact": func():
			if h.basculante_target < 0.5:
				h.set_basculante(true)
				g.flags["basculante_open"] = true
				Sfx.creak(Vector3(10.4, 5.0, 6.0), 0.35, 0.8, 1.8)
				g.on_task("basculante")
				return
			g.passage(Vector3(10.4, 3, 5.4), PI, "window")})
	add({"id": "basculante_out", "pos": Vector3(10.4, 3, 5.55), "radius": 0.7, "above": 1.8, "below": 0.3, "omni": true, "priority": 2,
		"prompt": func(): return "Pular pela janela (banheiro)",
		"enabled": func(): return h.basculante_target > 0.5,
		"on_interact": func(): g.passage(Vector3(10.4, 3.9, 6.32), 0.0, "window")})

	# ---- ways out to the yard: the pantry cat flap (from day 1), the basement window (morning 7) and
	# the old tree by the balcony (from day 4). The hunters cannot follow through them.
	var routes: Dictionary = Layout.data().get("ROUTES", {})
	if routes.has("flap"):
		var fl: Dictionary = routes["flap"]
		add({"id": "flap_in", "pos": Layout.v3(fl["inside"]), "radius": 0.7, "above": 0.6, "below": 0.4, "omni": true, "priority": 2,
			"prompt": func(): return "Sair pela portinhola (quintal)" if g.flags.get("flap_open", false) else "Empurrar a portinhola emperrada",
			"enabled": func(): return true,
			"hold": func(): return 0.0 if g.flags.get("flap_open", false) else 1.4,
			"pose": "scratch",
			"on_interact": func():
				if not g.flags.get("flap_open", false):
					g.flags["flap_open"] = true
					Sfx.creak(Layout.v3(fl["inside"]) + Vector3(0, 0.2, 0), 0.3, 0.5, 2.0)
					g.on_task("flap")
					return
				g.swing_flap()
				g.passage(Layout.v3(fl["outside"]), 0.0, "flap")})
		add({"id": "flap_out", "pos": Layout.v3(fl["outside"]), "radius": 0.75, "above": 1.2, "below": 0.4, "omni": true, "priority": 2,
			"prompt": func(): return "Entrar pela portinhola (despensa)",
			"enabled": func(): return g.flags.get("flap_open", false),
			"on_interact": func():
				g.swing_flap()
				g.passage(Layout.v3(fl["inside"]), PI, "flap")})
	if routes.has("porao_win"):
		var pw: Dictionary = routes["porao_win"]
		add({"id": "porao_win_in", "pos": Layout.v3(pw["inside"]), "radius": 0.8, "above": 2.6, "below": 0.4, "omni": true, "priority": 2,
			"prompt": func(): return "Sair pela janela do porão (quintal)" if g.flags.get("porao_win_open", false) else "Forçar a janela do porão",
			"enabled": func(): return g.flags.get("porao_win_open", false) or g.phase == "morning",
			"hold": func(): return 0.0 if g.flags.get("porao_win_open", false) else 1.6,
			"pose": "scratch",
			"on_interact": func():
				if not g.flags.get("porao_win_open", false):
					g.flags["porao_win_open"] = true
					Sfx.creak(Layout.v3(pw["inside"]) + Vector3(0, 2.3, 0), 0.4, 0.7, 1.6)
					g.on_task("porao_win")
					return
				g.passage(Layout.v3(pw["outside"]), -PI / 2, "window")})
		add({"id": "porao_win_out", "pos": Layout.v3(pw["outside"]), "radius": 0.75, "above": 1.0, "below": 0.4, "omni": true, "priority": 2,
			"prompt": func(): return "Entrar pela janela do porão",
			"enabled": func(): return g.flags.get("porao_win_open", false),
			"on_interact": func(): g.passage(Layout.v3(pw["inside"]), PI / 2, "window")})
	if routes.has("tree"):
		var tr: Dictionary = routes["tree"]
		add({"id": "tree_down", "pos": Layout.v3(tr["inside"]), "radius": 0.8, "above": 1.4, "below": 0.4, "omni": true, "priority": 2,
			"prompt": func(): return "Descer pela árvore (quintal)",
			"enabled": func(): return g.day >= 4 and cat.carrying == null,
			"on_interact": func(): g.passage(Layout.v3(tr["outside"]), 0.6, "tree")})
		add({"id": "tree_up", "pos": Layout.v3(tr["outside"]), "radius": 0.9, "above": 1.0, "below": 0.4, "omni": true, "priority": 2,
			"prompt": func(): return "Subir na árvore (varanda)",
			"enabled": func(): return g.day >= 4 and cat.carrying == null,
			"on_interact": func(): g.passage(Layout.v3(tr["inside"]), PI, "tree")})

	# ---- attic cord
	add({"id": "cord", "pos": Vector3(6.97, 3, 2.75), "radius": 0.7, "above": 1.6, "below": 0.3, "omni": true, "priority": 2,
		"prompt": func(): return "Puxar o cordão do sótão",
		"enabled": func(): return h.hatch_target < 0.5,
		"hold": 0.8, "pose": "scratch",
		"on_interact": func():
			h.set_hatch(true)
			g.flags["hatch_open"] = true
			Sfx.creak(Vector3(6.97, 5.6, 1.7), 0.55, 1.6, 0.9)
			g.get_tree().create_timer(1.3).timeout.connect(func(): Sfx.thud(Vector3(6.97, 3.2, 3.0), 0.6, 60))
			g.emit_noise(Vector3(6.97, 3.2, 3.0), 0.4, "thud")
			g.on_task("hatch")})

	# ---- the cat bed (skip the morning; the afternoon only ends lying down with Clara)
	add({"id": "catbed", "pos": h.cat_bed, "radius": 0.7, "above": 0.5, "omni": true,
		"prompt": func(): return "Dormir até Clara chegar",
		"enabled": func(): return g.phase == "morning" and cat.carrying == null,
		"hold": 1.0, "pose": "busy",
		"on_interact": func(): g.skip_phase()})

	# ---- lie down next to whoever is in bed (at night; in the afternoon it is how the day ends, once
	# Clara went to bed)
	for who: Owner in [g.clara, g.davi]:
		var bs := Layout.spot_pos(who.cfg["bed_spot"])
		var aft_bed := func() -> bool: return g.phase == "afternoon" and who == g.clara and g.aft.get("can_skip", false) and not g.aft.get("ending", false)
		add({"id": "purr_" + str(who.cfg["id"]), "pos": Vector3(1.6, 3, bs.z), "radius": 1.6, "above": 0.8, "below": 0.4, "omni": true, "priority": 4,
			"prompt": func():
				if g.phase == "afternoon":
					return "Ronronando..." if cat.mode == "purr" else tr("Deitar com %s") % who.display_name
				return "Levantar" if cat.mode == "purr" else (tr("Deitar no rosto de %s (acordar)") % who.display_name if who.paralysis else tr("Deitar com %s e ronronar") % who.display_name),
			"enabled": func(): return (night.call() or aft_bed.call()) and who.present and who.in_bed and cat.carrying == null,
			"on_interact": func():
				if g.phase == "afternoon" and cat.mode == "purr":
					return
				g.toggle_purr(who)})
	# ---- hiding places against the hound
	for spot in Layout.data()["HIDE_SPOTS"]:
		var sp := Layout.v3(spot["p"])
		add({"id": "hide_" + str(spot["id"]), "pos": sp, "radius": 0.95, "above": 0.6, "below": 0.5, "omni": true, "priority": 1,
			"prompt": func(): return tr("Esconder-se (%s)") % spot["name"],
			"enabled": func(): return night.call() and cat.mode == "free",
			"on_interact": func(): g.hide_at(spot)})
	# ---- cardboard boxes: pushed around in the morning, a one-time refuge at night
	for i in h.boxes.size():
		var bi: int = i
		add({"id": "box_push_%d" % bi, "pos_fn": func(): return h.boxes[bi]["pos"], "radius": 0.9, "above": 0.7, "below": 0.5, "omni": true, "priority": 3,
			"outline": func(): return [h.boxes[bi]["node"]],
			"prompt": func(): return "Soltar a caixa" if g._pushing == bi else "Empurrar a caixa",
			"enabled": func(): return g.phase == "morning" and g.flags["boxes"][bi] != null and cat.carrying == null and (g._pushing == -1 or g._pushing == bi),
			"on_interact": func():
				if g._pushing == bi:
					g.stop_push()
				else:
					g.start_push(bi)})
		add({"id": "box_in_%d" % bi, "pos_fn": func(): return h.boxes[bi]["pos"], "radius": 0.95, "above": 0.7, "below": 0.5, "omni": true, "priority": 2,
			"outline": func(): return [h.boxes[bi]["node"]],
			"prompt": func(): return "Entrar na caixa",
			"enabled": func(): return night.call() and cat.mode == "free" and g.box_usable(bi),
			"on_interact": func(): g.enter_box(bi)})
	# ---- afternoon with Clara
	# day 2: her lap is a jump target while she calls the cat from the sofa
	cat.extra_targets.append(func(): return g.lap_point())
	add({"id": "pet", "pos_fn": func(): return g.clara.global_position, "radius": 1.1, "above": 1.2, "below": 0.6, "omni": true, "priority": 4,
		"prompt": func(): return "Pedir carinho",
		"enabled": func(): return g.phase == "afternoon" and g.aft["pets"] < 3 and g.aft["pet_cd"] <= 0 and g.clara.interruptible() and not g.clara.in_bed and cat.mode == "free" and cat.carrying == null,
		"on_interact": func(): g.pet_owner()})
	add({"id": "toy", "pos_fn": func(): return g.clara.global_position, "radius": 1.3, "above": 1.2, "below": 0.6, "omni": true, "priority": 5,
		"prompt": func(): return "Levar o ratinho para Clara",
		"enabled": func(): return g.phase == "afternoon" and cat.carrying != null and cat.carrying.id == "toy" and not g.aft["played"],
		"on_interact": func(): g.play_with_owner()})
	add({"id": "yarn", "pos_fn": func(): return g.clara.global_position, "radius": 1.3, "above": 1.2, "below": 0.6, "omni": true, "priority": 5,
		"prompt": func(): return "Levar o novelo para Clara",
		"enabled": func(): return g.phase == "afternoon" and cat.carrying != null and cat.carrying.id == "yarn" and not g.aft.get("yarned", false),
		"on_interact": func(): g.give_yarn()})
	add({"id": "water", "pos": Vector3(8.9, 0, 3.92), "radius": 0.6, "above": 0.5, "omni": true, "priority": 4,
		"prompt": func(): return "Miar para a Clara encher a água",
		"enabled": func(): return g.aft_has("water") and not g.aft.get("water_asked", false) and g.clara.interruptible() and not g.clara.in_bed,
		"on_interact": func(): g.ask_water()})
	add({"id": "sun", "pos": Game.SUN_SPOT, "radius": 0.7, "above": 0.5, "omni": true, "priority": 3,
		"prompt": func(): return "Cochilar no sol",
		"enabled": func(): return g.aft_has("sun") and not g.aft.get("sunned", false) and cat.mode == "free" and cat.carrying == null,
		"hold": 0.6, "pose": "busy",
		"on_interact": func(): g.sun_nap()})
	# day 1: the padlock key from the moving box, down to Clara in the basement
	add({"id": "give_key", "pos_fn": func(): return g.clara.global_position, "radius": 1.3, "above": 1.2, "below": 0.6, "omni": true, "priority": 5,
		"prompt": func(): return "Dar a chave para Clara",
		"enabled": func(): return g.phase == "afternoon" and cat.carrying != null and cat.carrying.id == Game.PORAO_KEY and not g.aft.get("key_given", false) and g.clara.visible,
		"on_interact": func(): g.give_key()})
	add({"id": "eat", "pos": Game.BOWL_POS, "radius": 0.6, "above": 0.5, "omni": true, "priority": 3,
		"prompt": func(): return "Comer",
		"enabled": func(): return g.phase == "afternoon" and g.aft["bowl_filled"] and not g.aft["fed"] and cat.carrying == null and not g.is_eating(),
		"hold": 1.5, "pose": "busy",
		"on_interact": func(): g.eat()})
	add({"id": "bath_door", "pos": Vector3(7.25, 3, 9.1), "radius": 0.8, "above": 0.8, "omni": true, "priority": 5,
		"prompt": func(): return "Arranhar a porta do banheiro",
		"enabled": func(): return g.phase == "afternoon" and g.aft.get("bath_wait", false),
		"hold": 1.0, "pose": "scratch",
		"on_interact": func(): g.open_bath_door(true)})
	add({"id": "bath", "pos": Vector3(10.6, 3, 8.75), "radius": 1.3, "above": 0.8, "omni": true, "priority": 5,
		"prompt": func(): return "Tirar a Clara da banheira",
		"enabled": func(): return g.phase == "afternoon" and g.aft["scene"] == "bath" and g.aft["bathing"],
		"hold": 1.2, "pose": "scratch",
		"on_interact": func(): g.end_bath(true)})


	# ---- shut out: scratching at the front or back door from outside brings the cat back in (the
	# windows have no way in, the door is the way home)
	for door_id in ["d_front", "d_back"]:
		if not h.doors.has(door_id):
			continue
		var dr: Door = h.doors[door_id]
		var dc := dr.center()
		var out_n := _door_outward(dr)
		var outside := dc + out_n * 0.5
		var inside := dc - out_n * 0.65
		add({"id": "scratch_in_" + door_id, "pos": outside, "radius": 0.85, "above": 1.2, "below": 0.5, "omni": true, "priority": 2,
			"outline": func(): return [dr.leaf] if dr.leaf else [],
			"prompt": func(): return "Arranhar a porta (entrar)",
			"enabled": func(): return dr.is_closed and (cat.global_position - dc).dot(out_n) > 0.12 and g.phase != "none",
			"hold": 1.2, "pose": "scratch",
			"hold_label": func(): return "Arranhando...",
			"on_interact": func():
				g.emit_noise(dc, 0.35, "scratch")
				Sfx.creak(dc + Vector3(0, 1, 0), 0.3, 1.0)
				g.passage(inside, atan2(-out_n.x, -out_n.z), "door")})


## the way out of the house through an outside door: away from the middle of the house plan
static func _door_outward(d: Door) -> Vector3:
	var c := d.center()
	var n := Vector3(1, 0, 0) if d.def["axis"] == "z" else Vector3(0, 0, 1)
	# the house body is x 0..12, z 0..13: the outward side is the one farther from its middle
	var mid := Vector3(6.0, c.y, 6.5)
	if (c - mid).dot(n) < 0:
		n = -n
	return n


## the cat takes a carryable in its mouth
func pick(g: Game, id: String) -> void:
	var c: PropSystem.Carryable = g.house.carryables[id]
	g.cat.carrying = c
	c.carried = true
	Sfx.click(c.pos, 0.3)
	if id == "doll":
		g.director.doll.picked_up()
	if id in CLUES:
		var first: bool = g.flags["clues"][id] == null
		g.flags["clues"][id] = {"x": c.pos.x, "y": c.pos.y, "z": c.pos.z, "on_circle": false}
		if first:
			g.on_clue_found(id)


func _add_pick(g: Game, id: String, pickup: Callable) -> void:
	var h := g.house
	var cat := g.cat
	var c: PropSystem.Carryable = h.carryables[id]
	# the yarn and the toy mouse are played with: a pounce, and then it is in the cat's mouth (the leap
	# reaches further than a pick-up, and playing wins over asking Clara for a cuddle)
	var toy := id == "yarn" or id == "toy"
	add({"id": "pick_" + id, "pos_fn": func(): return c.pos, "radius": 1.15 if id == "coleira" else (1.0 if id == "foto" else (1.2 if toy else 0.6)), "above": 1.0, "below": 0.7,
		"omni": id == "coleira" or id == "foto", "priority": 5 if toy else 3,
		"outline": func(): return [c.node],
		"prompt": func():
			if toy:
				return tr("Brincar com %s") % tr(c.name)
			if id == "coleira" and g.flags["clues"]["coleira"] == null:
				return "Fuçar atrás da máquina de lavar"
			if id == "foto" and g.flags["clues"]["foto"] == null:
				return "Fuçar na caixa aberta"
			if id == "doll":
				return "Pegar a boneca"
			if g.relic_of(c).get("dirty", false):
				return tr("Pegar %s suja de lama") % tr(c.name)
			return tr("Pegar %s") % tr(c.name),
		"enabled": func(): return c.enabled and not c.carried and cat.carrying == null and c.node.visible and not g.ritual_placed(id) and not (id == "nightlight" and g.phase == "night"),
		"hold": func():
			if id == "coleira" and g.flags["clues"]["coleira"] == null:
				return 1.6
			if id == "foto" and g.flags["clues"]["foto"] == null:
				return 1.2
			return 0.0,
		"pose": "busy",
		"on_interact": func():
			if toy:
				g.play_toy(c)
			else:
				pickup.call(id)})
