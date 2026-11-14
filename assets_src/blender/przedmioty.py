"""PSK-12: modele przedmiotów (styl PS1, płaskie cieniowanie, kilka kolorów).

Uruchomienie:
    python3 assets_src/blender/przedmioty.py game/models/przedmioty.glb

Każdy obiekt nazywa się jak przedmiot w items.json (pole model.mesh).
Konwencja jak w grze: długość wzdłuż osi X, środek w (0, 0, 0), wymiary zgodne
z polem model.size (bryła kolizji). Oś Z Blendera to góra w Godocie (Y),
oś +Y Blendera to w Godocie -Z (przód).

Młotek: trzonek wzdłuż X, obuch na końcu +X. Obuch jest wydłużony w osi Y
Blendera: płaska powierzchnia uderzeniowa na +Y (w Godocie -Z, do przodu),
pazur na -Y. W dłoni gra stawia trzonek pionowo (pole "grip": "up"), więc
uderzenie idzie przód-tył, obuchem w gwóźdź.
"""

import math
import sys

import bpy
import bmesh


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
    MATS[name] = m
    return m


def finish(name, bm, material):
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = False
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def box(name, x0, x1, y0, y1, z0, z1, material, taper=None):
    """Prostopadłościan od (x0,y0,z0) do (x1,y1,z1); taper=(sy, sz) zwęża koniec +X."""
    bm = bmesh.new()
    v = []
    for x in (x0, x1):
        sy, sz = (taper if (taper and x == x1) else (1.0, 1.0))
        cy, cz = (y0 + y1) / 2, (z0 + z1) / 2
        for y, z in ((y0, z0), (y1, z0), (y1, z1), (y0, z1)):
            v.append(bm.verts.new((x, cy + (y - cy) * sy, cz + (z - cz) * sz)))
    for f in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        bm.faces.new([v[i] for i in f])
    return finish(name, bm, material)


def rod(name, rings, sides, material, axis="x"):
    """Bryła obrotowa: rings = [(pozycja na osi, promień_a, promień_b), ...]."""
    bm = bmesh.new()
    loops = []
    for t, ra, rb in rings:
        loop = []
        for i in range(sides):
            a = 2 * math.pi * i / sides + math.pi / sides
            ca, cb = math.cos(a) * ra, math.sin(a) * rb
            co = {"x": (t, ca, cb), "y": (ca, t, cb), "z": (ca, cb, t)}[axis]
            loop.append(bm.verts.new(co))
        loops.append(loop)
    for lo, hi in zip(loops, loops[1:]):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bm.faces.new(list(reversed(loops[0])))
    bm.faces.new(loops[-1])
    obj = finish(name, bm, material)
    if axis == "x":
        obj.data.flip_normals()
    return obj


def join(name, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


def fix_normals(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()


def build():
    wood = mat("drewno_trzonek", (0.42, 0.27, 0.13), rough=0.75)
    wood_dark = mat("drewno_ciemne", (0.2, 0.13, 0.07))
    steel = mat("stal", (0.42, 0.43, 0.45), metal=0.8, rough=0.4)
    steel_dark = mat("stal_ciemna", (0.2, 0.2, 0.22), metal=0.7, rough=0.5)
    red = mat("farba_czerwona", (0.45, 0.07, 0.05), metal=0.3, rough=0.55)
    yellow = mat("plastik_zolty", (0.8, 0.6, 0.08), rough=0.5)
    black = mat("guma_czarna", (0.06, 0.06, 0.06), rough=0.9)
    brass = mat("mosiadz", (0.72, 0.58, 0.28), metal=0.8, rough=0.35)
    board = mat("deska", (0.43, 0.32, 0.2), rough=0.95)
    cardboard = mat("karton", (0.55, 0.42, 0.26), rough=1.0)

    # --- młotek 0,32 x 0,03 x 0,12 (X, wysokość, głębokość)
    handle = rod("mlotek_trzonek", [(-0.16, 0.013, 0.016), (-0.14, 0.015, 0.018), (0.0, 0.012, 0.014),
                                   (0.11, 0.011, 0.013), (0.135, 0.011, 0.013)], 8, wood)
    grip = rod("mlotek_owijka", [(-0.161, 0.0145, 0.0175), (-0.07, 0.0145, 0.0175)], 8, black)
    eye = box("mlotek_oko", 0.118, 0.152, -0.022, 0.022, -0.015, 0.015, steel)
    face = rod("mlotek_obuch", [(0.022, 0.012, 0.012), (0.05, 0.014, 0.014), (0.06, 0.014, 0.014)], 8, steel, axis="y")
    face.location = (0.135, 0.0, 0.0)
    claw_l = box("mlotek_pazur_l", 0.123, 0.147, -0.06, -0.02, 0.002, 0.012, steel_dark, taper=(1.0, 1.0))
    claw_r = box("mlotek_pazur_r", 0.123, 0.147, -0.06, -0.02, -0.012, -0.002, steel_dark, taper=(1.0, 1.0))
    for c in (claw_l, claw_r):
        c.rotation_euler = (math.radians(-12 if c is claw_l else 12), 0.0, 0.0)
    hammer = join("mlotek", [handle, grip, eye, face, claw_l, claw_r])

    # --- łom 0,75: sześciokątny pręt, płaski klin na -X, hak na +X
    bar = rod("lom_pret", [(-0.3, 0.011, 0.011), (0.27, 0.011, 0.011)], 6, red)
    chisel = rod("lom_klin", [(-0.375, 0.0035, 0.016), (-0.3, 0.011, 0.012)], 6, red)
    hook_parts = [bar, chisel]
    prev = (0.27, 0.0)
    for k in range(1, 6):
        a = math.radians(k * 36.0)
        cx, cz = 0.27 + math.sin(a) * 0.045, 0.045 - math.cos(a) * 0.045
        seg = rod("lom_hak%d" % k, [(0.0, 0.011, 0.011), (math.dist(prev, (cx, cz)) + 0.004, 0.011, 0.011)], 6, red)
        ang = math.atan2(cz - prev[1], cx - prev[0])
        seg.rotation_euler = (0.0, -ang, 0.0)
        seg.location = (prev[0], 0.0, prev[1])
        hook_parts.append(seg)
        prev = (cx, cz)
    claw = rod("lom_pazur", [(0.0, 0.011, 0.012), (0.04, 0.003, 0.016)], 6, red)
    claw.rotation_euler = (0.0, math.radians(-180 + 20), 0.0)
    claw.location = (prev[0], 0.0, prev[1])
    hook_parts.append(claw)
    crowbar = join("lom", hook_parts)
    for o in [crowbar]:
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        # hak w całości w bryle kolizji: obniżamy całość
        for v in o.data.vertices:
            v.co.z -= 0.03

    # --- śrubokręt 0,21
    sd_handle = rod("srubokret_raczka", [(-0.105, 0.009, 0.009), (-0.098, 0.0125, 0.0125), (-0.035, 0.012, 0.012),
                                         (-0.02, 0.008, 0.008)], 8, yellow)
    sd_band = rod("srubokret_pasek", [(-0.075, 0.0128, 0.0128), (-0.06, 0.0128, 0.0128)], 8, black)
    sd_shaft = rod("srubokret_trzon", [(-0.02, 0.0032, 0.0032), (0.095, 0.0032, 0.0032)], 6, steel)
    sd_tip = rod("srubokret_grot", [(0.095, 0.0032, 0.0032), (0.105, 0.0008, 0.0035)], 6, steel)
    join("srubokret", [sd_handle, sd_band, sd_shaft, sd_tip])

    # --- nóż 0,24
    kn_handle = rod("noz_raczka", [(-0.12, 0.008, 0.012), (-0.005, 0.008, 0.012)], 6, wood_dark)
    blade = box("noz_ostrze", -0.005, 0.12, -0.0012, 0.0012, -0.012, 0.012, steel, taper=(1.0, 0.15))
    join("noz", [kn_handle, blade])

    # --- gwoździe: wiązka sześciu
    nails = []
    for k in range(6):
        y = -0.02 + k * 0.008
        z = -0.006 + (k % 2) * 0.008
        shaft = rod("gw%d" % k, [(-0.035, 0.0016, 0.0016), (0.03, 0.0016, 0.0016), (0.035, 0.0003, 0.0003)], 5, steel)
        head = rod("gw_leb%d" % k, [(-0.0375, 0.004, 0.004), (-0.0355, 0.004, 0.004)], 6, steel)
        for o in (shaft, head):
            o.location = (0.0, y, z)
        nails += [shaft, head]
    join("gwozdzie", nails)

    # --- wkręty: małe pudełko kartonowe
    join("wkrety", [box("wk_pudelko", -0.035, 0.035, -0.0225, 0.0225, -0.015, 0.012, cardboard),
                    box("wk_wieczko", -0.036, 0.036, -0.023, 0.023, 0.009, 0.015, mat("karton_ciemny", (0.35, 0.26, 0.16)))])

    # --- deska 1,5 x 0,025 x 0,14 ze sfazowanymi krawędziami
    plank = box("deska", -0.75, 0.75, -0.07, 0.07, -0.0125, 0.0125, board)
    bm = bmesh.new()
    bm.from_mesh(plank.data)
    long_edges = [e for e in bm.edges if abs(e.verts[0].co.x - e.verts[1].co.x) > 1.0]
    bmesh.ops.bevel(bm, geom=long_edges, offset=0.004, segments=1, affect="EDGES")
    bm.to_mesh(plank.data)
    bm.free()

    # --- nakładka 0,12 x 0,006 x 0,03: płytka i ucho na kłódkę
    plate = box("nk_plytka", -0.06, 0.03, -0.015, 0.015, -0.003, 0.0, steel)
    staple = box("nk_ucho", 0.03, 0.06, -0.006, 0.006, -0.003, 0.003, steel_dark)
    join("nakladka", [plate, staple])

    # --- zamek drzwiowy 0,16 x 0,03 x 0,1: obudowa, wkładka, rygiel
    case = box("zm_obudowa", -0.08, 0.08, -0.05, 0.05, -0.015, 0.012, steel_dark)
    cyl = rod("zm_wkladka", [(0.012, 0.011, 0.011), (0.017, 0.011, 0.011)], 8, brass, axis="z")
    cyl.location = (0.035, 0.0, 0.0)
    keyhole = box("zm_otwor", 0.032, 0.038, -0.0015, 0.0015, 0.016, 0.0175, black)
    bolt = box("zm_rygiel", -0.09, -0.08, -0.012, 0.012, -0.008, 0.004, steel)
    join("zamek_drzwiowy", [case, cyl, keyhole, bolt])

    # --- klucz 0,06
    bow = rod("kl_glowka", [(-0.002, 0.011, 0.011), (0.002, 0.011, 0.011)], 8, brass, axis="z")
    bow.location = (-0.019, 0.0, 0.0)
    blade_k = box("kl_pior", -0.008, 0.03, -0.004, 0.004, -0.0015, 0.0015, brass)
    teeth = [box("kl_zab%d" % k, 0.006 + k * 0.007, 0.011 + k * 0.007, -0.009, -0.004, -0.0015, 0.0015, brass) for k in range(3)]
    join("klucz", [bow, blade_k] + teeth)

    for o in list(bpy.context.scene.objects):
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        fix_normals(o)


def main():
    out = sys.argv[-1] if sys.argv[-1].endswith(".glb") else "przedmioty.glb"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True,
                              export_materials="EXPORT", export_yup=True)
    print("zapisano", out, [o.name for o in bpy.data.objects])


if __name__ == "__main__":
    main()
