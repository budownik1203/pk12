"""PSK-12: broń z paczki CC0 (3dmodelscc0, "Free CC0 Guns & Explosives Pack", domena publiczna)
przeniesiona do układu gry.

Uruchomienie:
    python3 assets_src/blender/bron_cc0.py <folder "Guns&Explosives"> game/models/bron_cc0.glb

Paczki nie trzymamy w repozytorium (150 MB); skrypt bierze z niej tylko Makarova i strzelbę,
zmniejsza tekstury do 1024 px i zapisuje jeden plik .glb.

Układ gry (jak bron.py): X do przodu (lufa), Y w górę, Z w prawo, początek w punkcie chwytu
prawej dłoni. W pliku źródłowym lufa jest wzdłuż +Y Blendera, góra to +Z.

Obiekty:
    pistolet (szkielet, lufa, kurek, bezpiecznik, spust), pistolet__zamek, pistolet__magazynek,
    magazynek_9mm (luźny magazynek, leży wzdłuż X), strzelba, strzelba__czolenko,
    dwururka__kolba (kolba strzelby dla dwururki z bron.py).
"""

import math
import os
import sys

import bpy
import mathutils

TEX_SIZE = 1024

# punkt chwytu w układzie pliku źródłowego (x, y, z Blendera) i przesunięcie magazynka do chwytu
PISTOL_GRIP = mathutils.Vector((0.0045, -0.022, -0.015))
PISTOL_MAG_SHIFT = mathutils.Vector((0.0, 0.081, 0.0))
SHOTGUN_GRIP = mathutils.Vector((0.0, -0.45, -0.035))
STOCK_CUT = 0.02   # x gry: kolba dwururki kończy się tuż przed szyjką


def to_game(grip):
    """Macierz: plik źródłowy -> układ gry zapisany w osiach Blendera (eksport glTF oddaje Y w górę).
    Godot (gx, gy, gz) = (sy, sz, sx); w Blenderze zapisujemy (gx, -gz, gy) = (sy, -sx, sz)."""
    rot = mathutils.Matrix.Rotation(-math.pi / 2.0, 4, "Z")
    return rot @ mathutils.Matrix.Translation(-grip)


def load_fbx(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def bake_world(objs):
    """Odpina rodziców i stosuje transformacje: wierzchołki w układzie świata pliku."""
    for o in objs:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in objs:
        if o.type != "MESH":
            continue
        o.data.transform(o.matrix_world)
        o.matrix_world = mathutils.Matrix.Identity(4)


def join(name, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    return o


def textured_material(name, folder, prefix):
    """Materiał z teksturą koloru (zmniejszoną) i metalicznością/szorstkością jako liczby."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    img = bpy.data.images.load(os.path.join(folder, prefix + "_Base_Color.png"))
    if img.size[0] > TEX_SIZE:
        img.scale(TEX_SIZE, TEX_SIZE)
    img.name = name + "_kolor"
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.45
    bsdf.inputs["Roughness"].default_value = 0.55
    return m


def place(obj, matrix, material, pivot=None):
    """Przenosi siatkę do układu gry; pivot (w układzie gry, osie Blendera) = położenie obiektu."""
    obj.data.transform(matrix)
    obj.data.materials.clear()
    obj.data.materials.append(material)
    for p in obj.data.polygons:
        p.use_smooth = True
    if pivot is not None:
        obj.data.transform(mathutils.Matrix.Translation(-pivot))
        obj.location = pivot
    return obj


def pistol(root):
    folder = os.path.join(root, "Pistol_MK")
    objs = load_fbx(os.path.join(folder, "Makarov.fbx"))
    bake_world(objs)
    meshes = {o.name.split(".")[0]: o for o in objs if o.type == "MESH"}
    mat = textured_material("makarov", folder, "Makarov")
    M = to_game(PISTOL_GRIP)
    # magazynek: w paczce leży obok broni, wsuwamy go do chwytu
    mag = meshes["Magazine"]
    mag.data.transform(mathutils.Matrix.Translation(PISTOL_MAG_SHIFT))
    loose = mag.copy()
    loose.data = mag.data.copy()
    bpy.context.scene.collection.objects.link(loose)
    frame = join("pistolet", [meshes[k] for k in ("Body", "Barrel", "Trigger") if k in meshes])
    place(frame, M, mat)
    slide = join("pistolet__zamek", [meshes[k] for k in ("Slide", "Hammer", "Safety") if k in meshes])
    place(slide, M, mat, pivot=mathutils.Vector((0, 0, 0)))
    place(mag, M, mat, pivot=mathutils.Vector((0, 0, 0)))
    mag.name = "pistolet__magazynek"
    # luźny magazynek: wzdłuż X, środek w zerze
    place(loose, M, mat)
    loose.name = "magazynek_9mm"
    # stojący magazynek (oś Y gry = Z Blendera) kładziemy wzdłuż X gry i centrujemy
    loose.data.transform(mathutils.Matrix.Rotation(-math.pi / 2.0, 4, "Y"))
    vs = [v.co for v in loose.data.vertices]
    c = mathutils.Vector([(min(v[i] for v in vs) + max(v[i] for v in vs)) / 2.0 for i in range(3)])
    loose.data.transform(mathutils.Matrix.Translation(-c))
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)


def shotgun(root):
    folder = os.path.join(root, "Shotgun")
    objs = load_fbx(os.path.join(folder, "Shotgun.fbx"))
    bake_world(objs)
    meshes = {o.name.split(".")[0]: o for o in objs if o.type == "MESH"}
    mat = textured_material("strzelba_cc0", folder, "Shotgun")
    M = to_game(SHOTGUN_GRIP)
    body = join("strzelba", [meshes[k] for k in ("Shotgun", "Ejection_Port", "Trigger") if k in meshes])
    place(body, M, mat)
    # kolba do dwururki: tylna część strzelby (do przodu szyjki), obcięta płaszczyzną
    stock = body.copy()
    stock.data = body.data.copy()
    stock.name = "dwururka__kolba"
    bpy.context.scene.collection.objects.link(stock)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(stock.data)
    res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(STOCK_CUT, 0, 0),
                                 plane_no=(1, 0, 0), clear_outer=True)
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    if edges:
        bmesh.ops.holes_fill(bm, edges=edges)
    bm.to_mesh(stock.data)
    bm.free()
    fore = meshes["Fore_Stock"]
    fore.name = "strzelba__czolenko"
    place(fore, M, mat, pivot=mathutils.Vector((0, 0, 0)))
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)


def report():
    bpy.context.view_layer.update()
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        ws = [o.matrix_world @ mathutils.Vector(v) for v in o.bound_box]
        mn = [min(w[i] for w in ws) for i in range(3)]
        mx = [max(w[i] for w in ws) for i in range(3)]
        # w osiach gry: X = x, Y = z, Z = -y
        print(o.name, "gra min", [round(mn[0], 3), round(mn[2], 3), round(-mx[1], 3)],
              "max", [round(mx[0], 3), round(mx[2], 3), round(-mn[1], 3)], "trójkąty",
              sum(len(p.vertices) - 2 for p in o.data.polygons))


def main():
    root = sys.argv[-2]
    out = sys.argv[-1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    pistol(root)
    shotgun(root)
    report()
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True,
                              export_materials="EXPORT", export_yup=True)
    print("zapisano", out)


if __name__ == "__main__":
    main()
