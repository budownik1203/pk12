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
    # kończyny: jednostkowa długość wzdłuż Z
    loft("udo", [(0.0, 0.085, 0.09, 0.0), (0.55, 0.075, 0.08, 0.005), (1.0, 0.058, 0.06, 0.0)], 8)
    loft("lydka", [(0.0, 0.058, 0.06, 0.0), (0.3, 0.062, 0.068, -0.01), (1.0, 0.044, 0.046, 0.0)], 8)
    loft("ramie", [(0.0, 0.055, 0.055, 0.0), (0.4, 0.05, 0.052, 0.0), (1.0, 0.042, 0.042, 0.0)], 7)
    loft("przedramie", [(0.0, 0.042, 0.042, 0.0), (0.35, 0.045, 0.043, 0.0), (1.0, 0.033, 0.03, 0.0)], 7)
    # tułów: od miednicy (z=0) do podstawy szyi (z=1); szerszy w barkach
    loft("tors", [
        (0.0, 0.155, 0.095, 0.0),
        (0.45, 0.165, 0.105, -0.005),
        (0.82, 0.195, 0.11, 0.0),
        (1.0, 0.12, 0.085, 0.01),
    ], 8)
    # bryły o stałym rozmiarze
    box("miednica", 0.33, 0.2, 0.16, cz=0.0, taper_top=1.0)
    # but: palce w stronę +Y Blendera (przód w grze), kostka na z=0
    boot = box("stopa", 0.11, 0.27, 0.08, cy=0.07, cz=-0.035)
    cuff = box("stopa_cholewa", 0.105, 0.11, 0.07, cy=-0.005, cz=0.03)
    join("stopa", [boot, cuff])
    # dłoń: od nadgarstka (z=0) w dół wzdłuż Z, kciuk z boku
    palm = box("dlon", 0.085, 0.032, 0.1, cz=0.05, taper_top=1.0)
    thumb = box("dlon_kciuk", 0.026, 0.026, 0.055, cx=0.045, cy=0.012, cz=0.035)
    join("dlon", [palm, thumb])
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
