class_name BMesh
## Loader for the tools/fetch_data.py mesh format:
## uint32 nv | float32 xyz*nv | float32 normal*nv | uint32 nt | uint32 idx*3*nt

static func load(path: String) -> ArrayMesh:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("BMesh: cannot open %s" % path)
		return null
	var nv := f.get_32()
	var verts := f.get_buffer(nv * 12).to_float32_array()
	var norms := f.get_buffer(nv * 12).to_float32_array()
	var nt := f.get_32()
	if nv == 0 or nt == 0:
		push_warning("BMesh: %s is empty" % path)
		return null
	var idx := f.get_buffer(nt * 12).to_int32_array()
	f.close()

	var v := PackedVector3Array()
	v.resize(nv)
	var n := PackedVector3Array()
	n.resize(nv)
	for i in nv:
		var k := i * 3
		v[i] = Vector3(verts[k], verts[k + 1], verts[k + 2])
		n[i] = Vector3(norms[k], norms[k + 1], norms[k + 2])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
