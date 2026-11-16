"""PSK-12: broń palna na wzór Iron Blight.

Mało wielokątów, ale zaokrąglone kształty i gładkie cieniowanie (krawędzie ostre
tylko powyżej 40°), kolba i czółenko z owalnymi przekrojami, lufy z 14 ścian,
fazowane krawędzie zamka i komory. Detal: szczerbinka, muszka, rowki na zamku,
okienko wyrzutnika, kurek z pierścieniem, kabłąk, okładziny z gwiazdą, szyny między lufami.

Uruchomienie:
    python3 assets_src/blender/bron.py game/models/bron.glb

Geometria w układzie Godota: X do przodu (lufa), Y w górę, Z w bok.
Początek układu każdej broni to punkt chwytu prawej dłoni (grip_at = [0, 0, 0]).

Obiekty:
    pistolet (TT), pistolet__zamek, pistolet__magazynek, magazynek_9mm,
    dwururka (pionowa, jak TOZ-34), dwururka__lufy (obrót wokół zawiasu),
    strzelba, strzelba__czolenko, luska_9mm, luska_12.

Materiały (gra podmienia je po nazwie na teksturowane): stal, stal_jasna,
stal_grawer, drewno, bakelit, guma, mosiadz, plastik_czerwony.
"""

import math
import sys

import bpy
import bmesh
import mathutils


MATS = {}


def mat(name, rgb, metal=0.0, rough=0.8):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    MATS[name] = m
    return m


def G(x, y, z):
    """Godot (x, y, z) -> Blender."""
    return (x, -z, y)


def _ring_pt(t, power, a, b):
    """Punkt superelipsy: power 2 = elipsa, większe = zaokrąglony prostokąt."""
    c, s = math.cos(t), math.sin(t)
    return (math.copysign(abs(c) ** (2.0 / power), c) * a, math.copysign(abs(s) ** (2.0 / power), s) * b)


class Part:
    def __init__(self, name, pivot=(0.0, 0.0, 0.0)):
        self.name = name
        self.pivot = pivot
        self.bm = bmesh.new()
        self.mats = []
        self.extras = []

    def organic(self, build, subdiv=2):
        """Część organiczna (kolba, czółenko, dłoń): budowana osobno, wygładzana podziałem
        powierzchni (Subdivision Surface) i dołączana do tej części."""
        sub = Part(self.name + "_org%d" % len(self.extras), self.pivot)
        build(sub)
        self.extras.append(sub.finish(subdiv=subdiv, link_pivot=False))

    def _mi(self, material):
        if material not in self.mats:
            self.mats.append(material)
        return self.mats.index(material)

    def _v(self, x, y, z):
        px, py, pz = self.pivot
        return self.bm.verts.new(G(x - px, y - py, z - pz))

    def _tag(self, faces, material):
        mi = self._mi(material)
        for f in faces:
            f.material_index = mi
        return faces

    def _bevel(self, faces, amount, segments=3):
        if amount <= 0.0:
            return
        mi = faces[0].material_index
        edges = list({e for f in faces for e in f.edges})
        res = bmesh.ops.bevel(self.bm, geom=edges, offset=amount, segments=segments, affect="EDGES",
                              clamp_overlap=True, profile=0.5)
        for f in res.get("faces", []):
            f.material_index = mi  # fazy w kolorze bryły

    def _skin(self, rings, material, caps=True):
        faces = []
        n = len(rings[0])
        for lo, hi in zip(rings, rings[1:]):
            for i in range(n):
                j = (i + 1) % n
                faces.append(self.bm.faces.new((lo[i], lo[j], hi[j], hi[i])))
        if caps:
            faces.append(self.bm.faces.new(list(reversed(rings[0]))))
            faces.append(self.bm.faces.new(rings[-1]))
        self._tag(faces, material)

    def box(self, c, s, material, rot=(0.0, 0.0, 0.0), bevel=0.0, seg=3):
        """Prostopadłościan o środku c i wymiarach s; rot = obrót (stopnie) wokół X, Y, Z Godota."""
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        R = (mathutils.Matrix.Rotation(math.radians(rot[2]), 3, "Z")
             @ mathutils.Matrix.Rotation(math.radians(rot[1]), 3, "Y")
             @ mathutils.Matrix.Rotation(math.radians(rot[0]), 3, "X"))
        vs = []
        for x in (-hx, hx):
            for y, z in ((-hy, -hz), (hy, -hz), (hy, hz), (-hy, hz)):
                p = R @ mathutils.Vector((x, y, z))
                vs.append(self._v(c[0] + p.x, c[1] + p.y, c[2] + p.z))
        faces = [self.bm.faces.new([vs[i] for i in f]) for f in
                 ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7))]
        self._tag(faces, material)
        self._bevel(faces, bevel, seg)

    def cyl(self, a, b, r, material, sides=14, r2=None):
        A = mathutils.Vector(a)
        B = mathutils.Vector(b)
        d = (B - A).normalized()
        up = mathutils.Vector((0, 1, 0)) if abs(d.y) < 0.9 else mathutils.Vector((1, 0, 0))
        u = d.cross(up).normalized()
        w = d.cross(u).normalized()
        rings = []
        for P, rr in ((A, r), (B, r if r2 is None else r2)):
            ring = []
            for i in range(sides):
                t = 2 * math.pi * i / sides + math.pi / sides
                q = P + (u * math.cos(t) + w * math.sin(t)) * rr
                ring.append(self._v(q.x, q.y, q.z))
            rings.append(ring)
        self._skin(rings, material)

    def loft(self, sections, material, sides=14, power=2.6, zoff=0.0):
        """Owalne przekroje wzdłuż X: sections = [(x, środek_y, wysokość, szerokość), ...]."""
        rings = []
        for x, yc, h, w in sections:
            ring = []
            for i in range(sides):
                zz, yy = _ring_pt(2 * math.pi * i / sides + math.pi / sides, power, w / 2, h / 2)
                ring.append(self._v(x, yc + yy, zoff + zz))
            rings.append(ring)
        self._skin(rings, material)

    def loft_y(self, sections, material, sides=12, power=3.0, zoff=0.0):
        """Przekroje wzdłuż Y (chwyt): sections = [(y, środek_x, głębokość, szerokość), ...]."""
        rings = []
        for y, xc, dpt, w in sections:
            ring = []
            for i in range(sides):
                xx, zz = _ring_pt(2 * math.pi * i / sides + math.pi / sides, power, dpt / 2, w / 2)
                ring.append(self._v(xc + xx, y, zoff + zz))
            rings.append(ring)
        self._skin(rings, material)

    def arc(self, center, r, a0, a1, thick, width, material, segs=8):
        """Łuk w płaszczyźnie X-Y (kabłąk spustu) od kąta a0 do a1 (stopnie)."""
        cx, cy, cz = center
        rings = []
        for i in range(segs + 1):
            a = math.radians(a0 + (a1 - a0) * i / segs)
            ring = []
            for dr, dz in ((-thick / 2, -width / 2), (thick / 2, -width / 2), (thick / 2, width / 2), (-thick / 2, width / 2)):
                rr = r + dr
                ring.append(self._v(cx + math.cos(a) * rr, cy + math.sin(a) * rr, cz + dz))
            rings.append(ring)
        self._skin(rings, material)

    def tube(self, path, r0, r1, material, sides=7):
        """Palec: rura wzdłuż łamanej (punkty w układzie Godota), promień od r0 do r1, zaokrąglony koniec."""
        P = [mathutils.Vector(q) for q in path]
        rings = []
        n = len(P)
        prev_u = None
        for i, q in enumerate(P):
            d = (P[min(i + 1, n - 1)] - P[max(i - 1, 0)]).normalized()
            if prev_u is None:
                ref = mathutils.Vector((0, 1, 0)) if abs(d.y) < 0.9 else mathutils.Vector((1, 0, 0))
                u = d.cross(ref).normalized()
            else:
                u = (prev_u - d * prev_u.dot(d)).normalized()
            prev_u = u
            w = d.cross(u).normalized()
            rr = r0 + (r1 - r0) * i / max(1, n - 1)
            ring = []
            for k in range(sides):
                t = 2 * math.pi * k / sides
                v = q + (u * math.cos(t) + w * math.sin(t)) * rr
                ring.append(self._v(v.x, v.y, v.z))
            rings.append(ring)
        # opuszek: dodatkowy, mniejszy pierścień za końcem
        d = (P[-1] - P[-2]).normalized()
        tip = P[-1] + d * r1 * 0.8
        u = prev_u
        w = d.cross(u).normalized()
        ring = []
        for k in range(sides):
            t = 2 * math.pi * k / sides
            v = tip + (u * math.cos(t) + w * math.sin(t)) * r1 * 0.45
            ring.append(self._v(v.x, v.y, v.z))
        rings.append(ring)
        self._skin(rings, material)

    def finish(self, smooth_angle=40.0, subdiv=0, link_pivot=True):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        mesh = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(mesh)
        self.bm.free()
        for m in self.mats:
            mesh.materials.append(m)
        mesh.shade_smooth()
        obj = bpy.data.objects.new(self.name, mesh)
        obj.location = G(*self.pivot)
        bpy.context.scene.collection.objects.link(obj)
        if subdiv > 0:
            mod = obj.modifiers.new("gladko", "SUBSURF")
            mod.levels = subdiv
            mod.render_levels = subdiv
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.ops.object.modifier_apply(modifier="gladko")
            obj.data.shade_smooth()
        if self.extras:
            bpy.ops.object.select_all(action="DESELECT")
            for e in self.extras:
                e.select_set(True)
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.join()
        obj.data.set_sharp_from_angle(angle=math.radians(smooth_angle if subdiv == 0 else 80.0))
        return obj


# --- pistolet TT ----------------------------------------------------------------

def pistol(M):
    f = Part("pistolet")
    # szkielet pod zamkiem, z osłoną lufy przed kabłąkiem
    f.box((0.032, 0.037, 0), (0.15, 0.018, 0.021), M["stal"], bevel=0.003)
    # chwyt TT: prawie pionowy, przekrój zaokrąglony
    f.organic(lambda q: q.loft_y([(-0.076, -0.019, 0.032, 0.021), (-0.04, -0.014, 0.034, 0.021),
              (0.0, -0.008, 0.035, 0.021), (0.03, -0.004, 0.034, 0.02)], M["stal"], sides=12, power=4.0), subdiv=1)
    # okładziny z bakelitu po obu stronach, z wypukłą gwiazdą
    for zs in (1, -1):
        f.organic(lambda q, zs=zs: q.loft_y([(-0.066, -0.0185, 0.026, 0.0045), (-0.03, -0.0135, 0.028, 0.005),
                  (0.008, -0.008, 0.028, 0.005), (0.022, -0.006, 0.026, 0.0045)], M["bakelit"],
                 sides=10, power=5.0, zoff=zs * 0.0118), subdiv=1)
        f.cyl((-0.011, -0.022, zs * 0.0128), (-0.011, -0.022, zs * 0.0146), 0.0058, M["bakelit"], sides=10)
    # stopka magazynka i kółko na smycz
    f.box((-0.0195, -0.077, 0), (0.033, 0.006, 0.021), M["stal_jasna"], bevel=0.0015)
    f.cyl((-0.034, -0.074, -0.004), (-0.034, -0.074, 0.004), 0.0045, M["stal_jasna"], sides=8)
    # kabłąk spustu (łuk) i spust
    f.arc((0.034, 0.024, 0), 0.02, 205, 335, 0.0035, 0.009, M["stal"], segs=9)
    f.box((0.032, 0.017, 0), (0.005, 0.016, 0.006), M["stal_jasna"], rot=(0, 0, -15), bevel=0.0012)
    # kurek z pierścieniem
    f.cyl((-0.055, 0.052, -0.0035), (-0.055, 0.052, 0.0035), 0.0072, M["stal_jasna"], sides=12)
    f.box((-0.048, 0.048, 0), (0.012, 0.008, 0.007), M["stal_jasna"], bevel=0.0015)
    # zatrzask zamka po lewej
    f.box((0.02, 0.041, -0.0118), (0.03, 0.005, 0.003), M["stal_jasna"], bevel=0.001)
    # wylot lufy z tuleją
    f.cyl((0.112, 0.059, 0), (0.12, 0.059, 0), 0.0072, M["stal_jasna"], sides=12)
    f.finish()

    z = Part("pistolet__zamek")
    z.loft([(-0.05, 0.059, 0.028, 0.0235), (0.1, 0.059, 0.028, 0.0235), (0.113, 0.0595, 0.026, 0.022)],
           M["stal"], sides=20, power=5.0)
    for i in range(9):  # pionowe rowki z tyłu zamka
        z.box((-0.045 + i * 0.0042, 0.058, 0), (0.0014, 0.022, 0.0244), M["stal_jasna"])
    z.box((0.03, 0.066, 0.0114), (0.03, 0.011, 0.0012), M["stal_jasna"], bevel=0.0005)  # wyrzutnik
    z.box((0.104, 0.0755, 0), (0.009, 0.006, 0.0032), M["stal"], bevel=0.0012)  # muszka
    z.box((-0.042, 0.075, -0.0055), (0.007, 0.006, 0.0055), M["stal"], bevel=0.0008)  # szczerbinka
    z.box((-0.042, 0.075, 0.0055), (0.007, 0.006, 0.0055), M["stal"], bevel=0.0008)
    z.finish()

    m = Part("pistolet__magazynek")
    m.loft_y([(-0.072, -0.0195, 0.028, 0.016), (0.025, -0.006, 0.028, 0.016)], M["stal_jasna"], sides=8, power=6.0)
    m.cyl((-0.006, 0.026, 0), (0.004, 0.026, 0), 0.0046, M["mosiadz"], sides=8)
    m.finish()


def loose_mag(M):
    m = Part("magazynek_9mm")
    m.loft([(-0.055, 0.0, 0.026, 0.016), (0.055, 0.0, 0.026, 0.016)], M["stal_jasna"], sides=8, power=6.0)
    m.box((-0.058, 0.0, 0), (0.006, 0.031, 0.021), M["stal_jasna"], bevel=0.0012)
    m.cyl((0.052, 0.0, 0), (0.062, 0.0, 0), 0.0046, M["mosiadz"], sides=8)
    m.finish()


# --- kolba ---------------------------------------------------------------------------

# przekroje (x, środek_y, wysokość, szerokość): szyjka przy dłoni, grzbiet opada do tyłu
STOCK = [(0.012, 0.016, 0.044, 0.04), (-0.03, 0.009, 0.04, 0.034), (-0.075, 0.0, 0.05, 0.035),
         (-0.15, -0.016, 0.074, 0.038), (-0.25, -0.034, 0.098, 0.04), (-0.35, -0.051, 0.116, 0.041),
         (-0.432, -0.061, 0.124, 0.042)]


def stock(part, M):
    part.organic(lambda q: q.loft(STOCK, M["drewno"], sides=12, power=2.8), subdiv=2)
    part.loft([(-0.433, -0.061, 0.124, 0.042), (-0.449, -0.062, 0.126, 0.043)], M["guma"], sides=16, power=3.2)


# --- dwururka pionowa (jak TOZ-34) -----------------------------------------------------------

def double_barrel(M):
    d = Part("dwururka")
    # kolba przychodzi z bron_cc0.py (dwururka__kolba); tu tylko krótka szyjka łącząca z baskilą
    d.organic(lambda q: q.loft([(0.012, 0.018, 0.04, 0.038), (0.03, 0.02, 0.046, 0.04)], M["drewno"], sides=12, power=2.8), subdiv=1)
    d.box((0.045, 0.018, 0), (0.075, 0.056, 0.042), M["stal_grawer"], bevel=0.005)  # baskila
    d.cyl((0.08, -0.004, -0.021), (0.08, -0.004, 0.021), 0.009, M["stal_jasna"], sides=12)  # zawias
    d.box((0.0, 0.04, 0), (0.03, 0.006, 0.014), M["stal"], rot=(0, 0, -6), bevel=0.002)  # dźwignia
    d.box((-0.025, 0.036, 0), (0.012, 0.004, 0.008), M["stal_jasna"], bevel=0.0012)  # bezpiecznik
    d.arc((0.02, -0.005, 0), 0.026, 205, 330, 0.004, 0.011, M["stal"], segs=9)
    d.box((0.016, -0.016, 0), (0.005, 0.02, 0.005), M["stal_jasna"], rot=(0, 0, -15), bevel=0.0012)
    d.box((0.03, -0.016, 0), (0.005, 0.02, 0.005), M["stal_jasna"], rot=(0, 0, -15), bevel=0.0012)
    d.finish()

    l = Part("dwururka__lufy", pivot=(0.08, -0.004, 0.0))
    for yc in (0.0105, 0.0335):
        l.cyl((0.083, yc, 0), (0.72, yc, 0), 0.0118, M["stal"], sides=18, r2=0.0108)
        l.cyl((0.716, yc, 0), (0.722, yc, 0), 0.0112, M["stal_jasna"], sides=18)
    for zs in (-1, 1):  # szyny boczne
        l.box((0.4, 0.022, zs * 0.0085), (0.63, 0.007, 0.004), M["stal"])
    l.box((0.4, 0.0475, 0), (0.63, 0.0025, 0.007), M["stal"], bevel=0.0008)  # szyna celownicza
    for i in range(10):
        l.box((0.12 + i * 0.06, 0.0455, 0), (0.006, 0.003, 0.004), M["stal"])
    l.cyl((0.712, 0.048, 0), (0.712, 0.053, 0), 0.0018, M["mosiadz"], sides=6)  # muszka
    l.box((0.086, 0.022, 0), (0.007, 0.048, 0.036), M["stal_jasna"], bevel=0.002)  # czoło luf
    l.organic(lambda q: q.loft([(0.1, -0.002, 0.018, 0.034), (0.13, -0.004, 0.026, 0.044), (0.32, -0.002, 0.024, 0.042),
              (0.36, 0.003, 0.014, 0.032)], M["drewno"], sides=10, power=2.6), subdiv=2)  # czółenko
    l.finish()


# --- strzelba pompowa --------------------------------------------------------------------

def pump_shotgun(M):
    s = Part("strzelba")
    stock(s, M)
    s.box((0.1, 0.017, 0), (0.18, 0.054, 0.042), M["stal"], bevel=0.005)
    s.box((0.115, 0.024, 0.0212), (0.07, 0.016, 0.0015), M["stal_jasna"], bevel=0.0006)
    s.arc((0.05, -0.008, 0), 0.026, 205, 330, 0.004, 0.011, M["stal"], segs=9)
    s.box((0.046, -0.018, 0), (0.005, 0.02, 0.005), M["stal_jasna"], rot=(0, 0, -15), bevel=0.0012)
    s.cyl((0.19, 0.026, 0), (0.72, 0.026, 0), 0.0115, M["stal"], sides=18)
    s.cyl((0.716, 0.026, 0), (0.722, 0.026, 0), 0.0112, M["stal_jasna"], sides=18)
    s.cyl((0.19, -0.003, 0), (0.65, -0.003, 0), 0.0105, M["stal_jasna"], sides=16)
    s.box((0.64, 0.011, 0), (0.018, 0.04, 0.024), M["stal"], bevel=0.003)
    s.cyl((0.712, 0.037, 0), (0.712, 0.042, 0), 0.0018, M["mosiadz"], sides=6)
    s.finish()

    c = Part("strzelba__czolenko")
    c.organic(lambda q: q.loft([(0.27, -0.004, 0.03, 0.042), (0.29, -0.004, 0.038, 0.05), (0.44, -0.004, 0.038, 0.05),
              (0.46, -0.004, 0.03, 0.042)], M["drewno"], sides=12, power=2.6), subdiv=1)
    for i in range(6):
        c.loft([(0.305 + i * 0.024, -0.004, 0.039, 0.051), (0.309 + i * 0.024, -0.004, 0.039, 0.051)],
               M["guma"], sides=14, power=2.6)
    c.finish()


def casings(M):
    a = Part("luska_9mm")
    a.cyl((-0.0095, 0, 0), (0.0095, 0, 0), 0.0049, M["mosiadz"], sides=8)
    a.finish()
    b = Part("luska_12")
    b.cyl((-0.035, 0, 0), (0.022, 0, 0), 0.0105, M["plastik_czerwony"], sides=10)
    b.cyl((0.022, 0, 0), (0.035, 0, 0), 0.011, M["mosiadz"], sides=10)
    b.finish()



# --- dłonie trzymające broń ---------------------------------------------------------------
# Dłoń budowana w swoim układzie (nadgarstek w 0, palce wzdłuż +Y, wnętrze dłoni w -Z,
# kciuk po stronie -X dla prawej i +X dla lewej), z paliczkami zginanymi o kąty w stawach,
# potem przenoszona macierzą na chwyt broni i wygładzana podziałem powierzchni.

V = mathutils.Vector

FINGERS = [  # (x podstawy w ułamku szerokości, długości paliczków, szerokość)
    (-0.36, (0.041, 0.025, 0.02), 0.0172),   # wskazujący
    (-0.12, (0.045, 0.028, 0.021), 0.0178),  # środkowy
    (0.12, (0.042, 0.026, 0.02), 0.0168),    # serdeczny
    (0.35, (0.033, 0.021, 0.018), 0.0148),   # mały
]


def _frame(x_axis, y_axis, origin):
    X = V(x_axis).normalized()
    Y = V(y_axis)
    Y = (Y - X * Y.dot(X)).normalized()
    Z = X.cross(Y)
    m = mathutils.Matrix.Identity(4)
    for r in range(3):
        m[r][0], m[r][1], m[r][2], m[r][3] = X[r], Y[r], Z[r], origin[r]
    return m


def _finger_rings(base, angles, lengths, width, side_sign, spread=0.0):
    """Pierścienie palca: każdy paliczek obraca kierunek w stronę wnętrza dłoni (-Z)."""
    d = V((math.sin(spread), math.cos(spread), 0.0))
    p = V(base)
    pts = [(p.copy(), d.copy(), width, width * 0.85)]
    for k, (a, ln) in enumerate(zip(angles, lengths)):
        R = mathutils.Matrix.Rotation(-math.radians(a), 3, "X")
        d = (R @ d).normalized()
        mid = p + d * ln * 0.5
        p = p + d * ln
        w = width * (1.0 - 0.09 * (k + 0.5))
        pts.append((mid, d.copy(), w, w * 0.86))
        w2 = width * (1.0 - 0.09 * (k + 1))
        pts.append((p.copy(), d.copy(), w2, w2 * 0.84))
    tip = p + d * width * 0.35
    pts.append((tip, d.copy(), width * 0.5, width * 0.42))
    return pts


def _tube_frames(part, frames, material, xf, sides=8):
    rings = []
    for c, d, w, t in frames:
        u = V((1.0, 0.0, 0.0))
        u = (u - d * u.dot(d)).normalized()
        wv = d.cross(u).normalized()
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            q = c + u * math.cos(a) * w / 2 + wv * math.sin(a) * t / 2
            q = xf @ q
            ring.append(part._v(q.x, q.y, q.z))
        rings.append(ring)
    part._skin(rings, material)


def make_hand(M, name, xf, side, curls, thumb, pivot=(0.0, 0.0, 0.0)):
    """side: +1 prawa (kciuk po -X), -1 lewa. curls: kąty trzech stawów dla każdego palca.
    thumb: (kąty, rozchylenie) kciuka."""
    h = Part(name, pivot)
    sk = M["skora"]
    sx = -side  # strona kciuka
    # śródręcze: owalne przekroje wzdłuż Y, spłaszczone
    secs = [(0.0, 0.052, 0.03), (0.03, 0.068, 0.028), (0.062, 0.078, 0.025), (0.084, 0.076, 0.021)]
    rings = []
    for y, w, t in secs:
        ring = []
        for k in range(14):
            a = 2 * math.pi * k / 14 + math.pi / 14
            xx, zz = _ring_pt(a, 3.0, w / 2, t / 2)
            q = xf @ V((xx, y, zz))
            ring.append(h._v(q.x, q.y, q.z))
        rings.append(ring)
    h._skin(rings, sk)
    # kłąb kciuka (wypukłość u nasady)
    _tube_frames(h, [(V((sx * 0.02, 0.012, -0.004)), V((sx * 0.35, 0.94, 0)).normalized(), 0.03, 0.026),
                     (V((sx * 0.03, 0.04, -0.006)), V((sx * 0.4, 0.92, 0)).normalized(), 0.028, 0.022)], sk, xf)
    # palce
    for (fx, lens, wid), ang in zip(FINGERS, curls):
        base = (fx * side * 0.078, 0.074, 0.0)
        _tube_frames(h, _finger_rings(base, ang, lens, wid, side), sk, xf)
    # kciuk: od kłębu, odchylony na bok, zgięty
    tang, tspread = thumb
    d = V((sx * math.sin(math.radians(tspread)), math.cos(math.radians(tspread)), -0.25)).normalized()
    p = V((sx * 0.03, 0.028, -0.008))
    frames = [(p.copy(), d.copy(), 0.021, 0.019)]
    for k, (a, ln) in enumerate(zip(tang, (0.032, 0.03, 0.024))):
        axis = V((0.0, 0.0, 1.0)).cross(d).normalized() if abs(d.z) < 0.95 else V((1, 0, 0))
        R = mathutils.Matrix.Rotation(math.radians(a) * side, 3, V((0, 0, 1)))
        d = (R @ d).normalized()
        mid = p + d * ln * 0.5
        p = p + d * ln
        frames.append((mid, d.copy(), 0.02 - 0.002 * k, 0.017 - 0.0015 * k))
        frames.append((p.copy(), d.copy(), 0.019 - 0.002 * (k + 1), 0.016 - 0.0015 * (k + 1)))
    frames.append((p + d * 0.006, d.copy(), 0.009, 0.008))
    _tube_frames(h, frames, sk, xf)
    h.finish(subdiv=1)


def hands(M):
    # prawa na chwycie pistoletu: palce do przodu, mały palec w dół, wnętrze dłoni do chwytu (-Z broni)
    xf = _frame((0.08, -1.0, 0.0), (1.0, 0.18, 0.0), (-0.058, -0.012, 0.028))
    make_hand(M, "reka_pistolet_p", xf, 1, [(15, 55, 35), (70, 75, 45), (75, 75, 45), (80, 70, 45)], ((25, 20, 10), 55))
    # lewa podtrzymuje od spodu-lewej: palce owijają palce prawej
    xf = _frame((0.12, 1.0, 0.0), (1.0, -0.05, 0.12), (-0.04, -0.048, -0.04))
    make_hand(M, "reka_pistolet_l", xf, -1, [(55, 65, 40), (60, 70, 40), (62, 70, 40), (65, 65, 40)], ((10, 10, 5), 40))
    # prawa na szyjce kolby (chwyt bardziej poziomy)
    xf = _frame((0.85, -0.55, 0.0), (0.45, 0.5, 0.0), (-0.085, 0.0, 0.032))
    make_hand(M, "reka_kolba_p", xf, 1, [(20, 55, 35), (75, 75, 45), (78, 75, 45), (80, 70, 45)], ((20, 20, 10), 55))
    # lewe pod czółenkiem: wnętrze dłoni do góry, palce po prawej stronie, kciuk po lewej
    for nm, cx, cy, hh in (("reka_czolenko_pompa", 0.37, -0.004, 0.019), ("reka_czolenko_dwururka", 0.24, -0.003, 0.013)):
        xf = _frame((1.0, 0.0, 0.05), (0.15, 0.25, 1.0), (cx - 0.04, cy - hh - 0.018, -0.05))
        make_hand(M, nm, xf, -1, [(35, 60, 40), (40, 60, 40), (42, 60, 40), (45, 55, 40)], ((15, 25, 10), 35))


def build():
    M = {
        "stal": mat("stal", (0.13, 0.13, 0.145), metal=0.75, rough=0.45),
        "stal_jasna": mat("stal_jasna", (0.33, 0.33, 0.34), metal=0.8, rough=0.4),
        "stal_grawer": mat("stal_grawer", (0.4, 0.4, 0.41), metal=0.8, rough=0.4),
        "drewno": mat("drewno", (0.38, 0.2, 0.09), rough=0.6),
        "bakelit": mat("bakelit", (0.17, 0.09, 0.06), rough=0.6),
        "guma": mat("guma", (0.06, 0.06, 0.06), rough=0.9),
        "mosiadz": mat("mosiadz", (0.72, 0.56, 0.26), metal=0.85, rough=0.35),
        "plastik_czerwony": mat("plastik_czerwony", (0.55, 0.08, 0.06), rough=0.6),
        "skora": mat("skora", (0.62, 0.47, 0.38), rough=0.7),
    }
    pistol(M)
    loose_mag(M)
    double_barrel(M)
    pump_shotgun(M)
    casings(M)


def main():
    out = sys.argv[-1] if sys.argv[-1].endswith(".glb") else "bron.glb"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True,
                              export_materials="EXPORT", export_yup=True)
    print("zapisano", out, [o.name for o in bpy.data.objects])


if __name__ == "__main__":
    main()
