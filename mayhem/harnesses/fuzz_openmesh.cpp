// OpenMesh readers (used by the app's openmesh Python bindings, src/python/lfs/openmesh/io.cpp).
// FORMAT_EXT selects the reader: obj / off / stl / ply.
#include <OpenMesh/Core/IO/MeshIO.hh>
#include <OpenMesh/Core/Mesh/PolyMesh_ArrayKernelT.hh>
#include <OpenMesh/Core/Mesh/TriMesh_ArrayKernelT.hh>

#include <cstddef>
#include <cstdint>
#include <sstream>
#include <string>

#ifndef FORMAT_EXT
#error "define FORMAT_EXT"
#endif

struct Traits : OpenMesh::DefaultTraits {
    VertexAttributes(OpenMesh::Attributes::Normal | OpenMesh::Attributes::Status);
    FaceAttributes(OpenMesh::Attributes::Normal | OpenMesh::Attributes::Status);
    HalfedgeAttributes(OpenMesh::Attributes::PrevHalfedge);
};
using TriMesh = OpenMesh::TriMesh_ArrayKernelT<Traits>;
using PolyMesh = OpenMesh::PolyMesh_ArrayKernelT<Traits>;

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size < 4 || size > (1u << 20)) return -1;
    const std::string bytes(reinterpret_cast<const char*>(data), size);
    {
        TriMesh mesh;
        std::istringstream in(bytes, std::ios::binary);
        OpenMesh::IO::Options opt;
        if (OpenMesh::IO::read_mesh(mesh, in, "." FORMAT_EXT, opt)) {
            mesh.request_face_normals();
            mesh.update_normals();
            volatile size_t n = mesh.n_faces() + mesh.n_vertices();
            (void)n;
        }
    }
    {
        PolyMesh mesh;
        std::istringstream in(bytes, std::ios::binary);
        OpenMesh::IO::Options opt;
        OpenMesh::IO::read_mesh(mesh, in, "." FORMAT_EXT, opt);
    }
    return 0;
}
