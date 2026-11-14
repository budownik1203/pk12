extends RefCounted
## Wygląd PS1 w samej geometrii: każdy StandardMaterial3D w scenie zamieniany jest
## na materiał z shaderem, który przyciąga wierzchołki do siatki pikseli (drgania
## przy ruchu kamery) i rysuje tekstury bez korekcji perspektywy (tekstura
## „płynie” po dużych ścianach). Siłę obu efektów ustawia styl (F1–F4) przez
## globalne parametry shadera, więc zmiana stylu działa od razu wszędzie.
## Duże pudełka dzielone są na mniejsze kwadraty, jak robiły to gry na PS1,
## żeby tekstura nie wyginała się przesadnie.

const PARAMS := {"psx_snap": 0.0, "psx_affine": 0.0}
const SUBDIV_STEP := 0.75   # metry na jeden podział dużego pudełka

const BODY := """
global uniform float psx_snap;
global uniform float psx_affine;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform bool triplanar = false;
uniform bool world_space = false;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform float rough = 0.9;
uniform float metal = 0.0;
uniform vec3 emission_color = vec3(0.0);
uniform float emission_energy = 0.0;
varying vec3 uv_a;
varying vec4 tri_a;
varying vec3 tri_n;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (psx_snap > 0.0 && clip.w > 0.0) {
		vec2 grid = VIEWPORT_SIZE * 0.5 / psx_snap;
		clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	}
	POSITION = clip;
	float w = mix(1.0, max(clip.w, 0.05), psx_affine);
	uv_a = vec3((UV * uv_scale.xy + uv_offset.xy) * w, w);
	vec3 p = world_space ? (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz : VERTEX;
	tri_a = vec4(p * w, w);
	tri_n = world_space ? (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz : NORMAL;
}

void fragment() {
	vec4 c = albedo;
	if (use_tex) {
		vec2 uv;
		if (triplanar) {
			vec3 p = tri_a.xyz / tri_a.w * uv_scale + uv_offset;
			vec3 n = abs(normalize(tri_n));
			if (n.x >= n.y && n.x >= n.z) {
				uv = p.zy;
			} else if (n.y >= n.z) {
				uv = p.xz;
			} else {
				uv = p.xy;
			}
		} else {
			uv = uv_a.xy / uv_a.z;
		}
		c *= texture(tex, uv);
	}
	ALBEDO = c.rgb;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emission_color * emission_energy;
#ifdef TRANSPARENT
	ALPHA = c.a;
#endif
}
"""

static var _shaders := {}
static var _ready := false


## Globalne parametry muszą istnieć, zanim powstanie pierwszy materiał.
static func init() -> void:
	if _ready:
		return
	# raz na uruchomienie gry (static); lista parametrów jest dostępna tylko w edytorze
	for k in PARAMS:
		RenderingServer.global_shader_parameter_add(k, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, PARAMS[k])
	_ready = true


static func set_style(snap: float, affine: float) -> void:
	init()
	RenderingServer.global_shader_parameter_set("psx_snap", snap)
	RenderingServer.global_shader_parameter_set("psx_affine", affine)


static func _shader(unshaded: bool, transparent: bool, cull_off: bool) -> Shader:
	var key := "%s%s%s" % [unshaded, transparent, cull_off]
	if _shaders.has(key):
		return _shaders[key]
	var modes := ["diffuse_lambert", "specular_disabled", "cull_disabled" if cull_off else "cull_back"]
	if unshaded:
		modes.append("unshaded")
	var code := "shader_type spatial;\nrender_mode %s;\n" % ", ".join(modes)
	if transparent:
		code += "#define TRANSPARENT\n"
	var sh := Shader.new()
	sh.code = code + BODY
	_shaders[key] = sh
	return sh


## Materiał PS1 odpowiadający materiałowi standardowemu (wspólny dla wszystkich jego użyć).
static func material(src: Material) -> Material:
	if not src is StandardMaterial3D:
		return src
	if src.has_meta("psx"):
		return src.get_meta("psx")
	init()
	var m := ShaderMaterial.new()
	var std := src as StandardMaterial3D
	m.shader = _shader(std.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
			std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED,
			std.cull_mode == BaseMaterial3D.CULL_DISABLED)
	m.render_priority = std.render_priority
	src.set_meta("psx", m)
	refresh(std)
	return m


## Przepisuje parametry po zmianie materiału standardowego (np. włącznik światła).
static func refresh(std: StandardMaterial3D) -> void:
	if not std.has_meta("psx"):
		return
	var m: ShaderMaterial = std.get_meta("psx")
	m.set_shader_parameter("albedo", std.albedo_color)
	m.set_shader_parameter("use_tex", std.albedo_texture != null)
	if std.albedo_texture != null:
		m.set_shader_parameter("tex", std.albedo_texture)
	m.set_shader_parameter("triplanar", std.uv1_triplanar)
	m.set_shader_parameter("world_space", std.uv1_world_triplanar)
	m.set_shader_parameter("uv_scale", std.uv1_scale)
	m.set_shader_parameter("uv_offset", std.uv1_offset)
	m.set_shader_parameter("rough", std.roughness)
	m.set_shader_parameter("metal", std.metallic)
	if std.emission_enabled:
		m.set_shader_parameter("emission_color", Vector3(std.emission.r, std.emission.g, std.emission.b))
		m.set_shader_parameter("emission_energy", std.emission_energy_multiplier)


## Podpinane pod SceneTree.node_added: zamienia materiały każdej nowej bryły.
static func on_node_added(node: Node) -> void:
	if node is MeshInstance3D:
		convert_mesh(node)


static func convert_mesh(mi: MeshInstance3D) -> void:
	if mi.has_meta("psx_skip"):
		return
	if mi.mesh is BoxMesh:
		_subdivide(mi.mesh)
	if mi.material_override != null:
		mi.material_override = material(mi.material_override)
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var own: Material = mi.get_surface_override_material(i)
		var src: Material = own if own != null else mi.mesh.surface_get_material(i)
		if src is StandardMaterial3D:
			mi.set_surface_override_material(i, material(src))


static func _subdivide(box: BoxMesh) -> void:
	var s := box.size
	if maxf(s.x, maxf(s.y, s.z)) < SUBDIV_STEP * 1.5:
		return
	box.subdivide_width = mini(int(s.x / SUBDIV_STEP), 16)
	box.subdivide_height = mini(int(s.y / SUBDIV_STEP), 16)
	box.subdivide_depth = mini(int(s.z / SUBDIV_STEP), 16)
