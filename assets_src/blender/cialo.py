"""PSK-12: segmenty ciała postaci (styl PS1/PS2, osobne bryły na stawach).

Uruchomienie (Blender jako moduł Pythona albo blender --background --python):
    python3 assets_src/blender/cialo.py game/models/cialo_segmenty.glb

Konwencja: kończyny modelowane wzdłuż osi Z Blendera od 0 do 1 (jednostkowa
długość; w grze skalowane do długości kości), przekrój w prawdziwych metrach.
Bryły o stałym rozmiarze (miednica, stopa, dłoń, głowa, latarka) w metrach.
Po eksporcie do glTF oś Z Blendera staje się osią Y w Godocie, a oś +Y
Blendera staje się osią -Z (przód) w Godocie.
"""

import math
import sys

import bpy  # musi być przed bmesh
import bmesh


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def new_object(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = False  # płaskie cieniowanie: wygląd low-poly
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def loft(name, rings, sides, cap_bottom=True, cap_top=True):
    """Bryła z pierścieni: rings = [(z, promień_x, promień_y, przesunięcie_y), ...]."""
    bm = bmesh.new()
    loops = []
    for z, rx, ry, oy in rings:
        loop = []
        for i in range(sides):
            a = 2.0 * math.pi * i / sides + math.pi / sides
            loop.append(bm.verts.new((math.cos(a) * rx, math.sin(a) * ry + oy, z)))
        loops.append(loop)
    for lo, hi in zip(loops, loops[1:]):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    if cap_bottom:
        bm.faces.new(list(reversed(loops[0])))
    if cap_top:
        bm.faces.new(loops[-1])
    return new_object(name, bm)


def box(name, sx, sy, sz, cx=0.0, cy=0.0, cz=0.0, taper_top=1.0):
    """Prostopadłościan o wymiarach sx, sy, sz; górna ściana zwężona taper_top."""
    bm = bmesh.new()
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    v = []
    for z in (-hz, hz):
        t = taper_top if z > 0 else 1.0
        for x, y in ((-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)):
            v.append(bm.verts.new((cx + x * t, cy + y * t, cz + z)))
    for f in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        bm.faces.new([v[i] for i in f])
    return new_object(name, bm)


def join(name, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


def build():
    # Sylwetka dorosłego mężczyzny w kurtce roboczej, dżinsach i butach za kostkę.
    # Kończyny: jednostkowa długość wzdłuż Z; przekroje w metrach, przód to +Y.
    # udo: mocne u góry, zwęża się do kolana; nogawka prosta jak w dżinsach
    loft("udo", [(0.0, 0.092, 0.098, 0.0), (0.25, 0.088, 0.094, 0.006), (0.6, 0.074, 0.08, 0.006),
                 (1.0, 0.058, 0.062, 0.0)], 10)
    # łydka: mięsień z tyłu (przesunięcie -Y), nogawka opada na cholewkę
    loft("lydka", [(0.0, 0.058, 0.062, 0.0), (0.28, 0.064, 0.07, -0.012), (0.7, 0.054, 0.058, -0.004),
                   (1.0, 0.056, 0.058, 0.0)], 10)
    # ramię w rękawie kurtki: naramiennik, potem prosto do łokcia
    loft("ramie", [(0.0, 0.062, 0.066, 0.0), (0.18, 0.064, 0.064, 0.0), (0.6, 0.054, 0.056, 0.0),
                   (1.0, 0.047, 0.048, 0.0)], 9)
    # przedramię: grubsze pod łokciem, mankiet rękawa przy nadgarstku
    loft("przedramie", [(0.0, 0.047, 0.048, 0.0), (0.3, 0.05, 0.049, 0.0), (0.85, 0.041, 0.04, 0.0),
                        (0.86, 0.046, 0.045, 0.0), (1.0, 0.046, 0.045, 0.0)], 9)
    # tułów: od miednicy (z=0) do podstawy szyi (z=1); szeroka klatka, płaskie
    # plecy, barki wyżej i szerzej niż talia (sylwetka w kształcie V), kołnierz kurtki
    loft("tors", [
        (0.0, 0.165, 0.105, 0.0),
        (0.2, 0.162, 0.104, 0.004),
        (0.48, 0.178, 0.112, 0.012),
        (0.7, 0.205, 0.12, 0.016),
        (0.84, 0.215, 0.112, 0.008),
        (0.93, 0.15, 0.09, 0.006),
        (0.95, 0.075, 0.07, 0.008),
        (1.0, 0.07, 0.065, 0.006),
    ], 10)
    # miednica z paskiem
    pelvis = box("miednica", 0.34, 0.215, 0.17, cz=0.0, taper_top=1.0)
    belt = box("miednica_pas", 0.345, 0.222, 0.035, cz=0.06)
    join("miednica", [pelvis, belt])
    # but roboczy: gruba podeszwa, zaokrąglony nosek, cholewka; kostka na z=0
    sole = box("stopa_podeszwa", 0.118, 0.29, 0.03, cy=0.07, cz=-0.06)
    boot = box("stopa", 0.112, 0.26, 0.06, cy=0.065, cz=-0.03, taper_top=0.9)
    toe = box("stopa_nosek", 0.1, 0.06, 0.045, cy=0.2, cz=-0.035, taper_top=0.8)
    cuff = box("stopa_cholewa", 0.108, 0.115, 0.085, cy=-0.005, cz=0.035)
    join("stopa", [boot, sole, toe, cuff])
    # dłoń: szeroka śródręcze, palce złączone i lekko zgięte, kciuk z boku
    palm = box("dlon", 0.09, 0.036, 0.085, cz=0.042, taper_top=1.0)
    fingers = box("dlon_palce", 0.086, 0.03, 0.06, cy=0.006, cz=0.11, taper_top=0.92)
    thumb = box("dlon_kciuk", 0.028, 0.028, 0.058, cx=0.05, cy=0.014, cz=0.04)
    join("dlon", [palm, fingers, thumb])
    # głowa: rzuca tylko cień (gracz jej nie widzi)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=0.11)
    head = bpy.context.active_object
    head.name = "glowa"
    head.data.name = "glowa"
    head.scale = (0.9, 1.05, 1.1)
    bpy.ops.object.transform_apply(scale=True)
    # latarka: korpus wzdłuż +Y Blendera (przód), tył latarki na y=0
    loft("latarka", [(0.0, 0.019, 0.019, 0.0), (0.12, 0.019, 0.019, 0.0), (0.135, 0.028, 0.028, 0.0), (0.17, 0.028, 0.028, 0.0)], 8)
    lamp = bpy.data.objects["latarka"]
    lamp.rotation_euler = (-math.pi / 2, 0.0, 0.0)  # oś Z -> +Y
    bpy.context.view_layer.objects.active = lamp
    lamp.select_set(True)
    bpy.ops.object.transform_apply(rotation=True)


def main():
    out = sys.argv[-1] if sys.argv[-1].endswith(".glb") else "cialo_segmenty.glb"
    clear_scene()
    build()
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True,
                              export_materials="NONE", export_yup=True)
    print("zapisano", out, "obiektów:", len(bpy.data.objects))


if __name__ == "__main__":
    main()
