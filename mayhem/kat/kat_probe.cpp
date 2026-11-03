// Known-answer probe. Runs real LichtFeld Studio parsing code on fixed inputs and prints the results;
// mayhem/test.sh compares the output to its expected values.
#include "io/json_chapter_dom.hpp"
#include "load-spz.h"
#include "python_buffer_analysis.hpp"
#include "usd_flat/crate.hpp"
#include "usd_flat/usda_read.hpp"
#include "tinyply.hpp"

#include "stb_image.h"

#include <OpenMesh/Core/IO/MeshIO.hh>
#include <OpenMesh/Core/Mesh/PolyMesh_ArrayKernelT.hh>
#include <OpenMesh/Core/Mesh/TriMesh_ArrayKernelT.hh>

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <sstream>
#include <string>

using TriMesh = OpenMesh::TriMesh_ArrayKernelT<>;
using PolyMesh = OpenMesh::PolyMesh_ArrayKernelT<>;

static void usd() {
    const std::string usda =
        "#usda 1.0\n(\n    defaultPrim = \"Root\"\n    metersPerUnit = 0.01\n    upAxis = \"Z\"\n)\n\n"
        "def Xform \"Root\"\n{\n    def ParticleField \"Splats\"\n    {\n"
        "        point3f[] positions = [(0, 0, 0), (1, 2, 3)]\n"
        "        float[] opacities = [0.25, 0.75]\n"
        "        quatf[] orientations = [(1, 0, 0, 0), (0, 1, 0, 0)]\n    }\n}\n";
    auto s = lfs::io::usd_flat::read_usda_bytes(reinterpret_cast<const uint8_t*>(usda.data()), usda.size());
    if (!s) { std::printf("usda=error\n"); return; }
    std::printf("usda.up_axis=%s\nusda.meters_per_unit=%.2f\nusda.default_prim=%s\nusda.prims=%zu\n",
                s->up_axis.c_str(), s->meters_per_unit, s->default_prim.c_str(), s->prims.size());
    for (const auto& p : s->prims) {
        std::printf("usda.prim=%s:%s\n", p.path.c_str(), p.type_name.c_str());
        for (const auto& [name, a] : p.attributes) {
            std::printf("usda.attr=%s:%s:%d:", name.c_str(), a.type_name.c_str(), a.components);
            for (float v : a.values) std::printf("%g,", v);
            std::printf("\n");
        }
    }
    const std::string junk = "not a crate file at all";
    auto c = lfs::io::usd_flat::read_usdc_bytes(reinterpret_cast<const uint8_t*>(junk.data()), junk.size());
    std::printf("usdc.garbage=%s\n", c ? "accepted" : "rejected");
}

static void python() {
    const std::string good = "import os\n\nclass A:\n    def f(self, x):\n        return x + 1\n\ny = 3\n";
    auto a = lfs::python::analyze_python_buffer(good);
    std::printf("py.good.clean=%d\n", a.clean() ? 1 : 0);
    lfs::python::PythonSyntaxDocument doc;
    doc.reset(good);
    for (const auto& s : doc.symbols())
        std::printf("py.symbol=%d:%s@%zu\n", static_cast<int>(s.kind), s.name.c_str(), s.line);
    std::printf("py.scope_at_return=%s\n", doc.scopeAt(good.find("return")).c_str());
    const std::string bad = "def f(:\n    pass\n";
    auto b = lfs::python::analyze_python_buffer(bad);
    std::printf("py.bad.clean=%d\npy.bad.issues=%d\n", b.clean() ? 1 : 0, b.issues.empty() ? 0 : 1);
}

static void json() {
    auto d = lfs::io::JsonChapterDom::parse("{\"b\":1,\"a\":[true,null,\"x\"]}");
    if (!d) { std::printf("json=error\n"); return; }
    std::printf("json.dump_bytes=%zu\n", d->dump().size());
    std::printf("json.dump=%s\n", d->dump().c_str());
    auto bad = lfs::io::JsonChapterDom::parse("{\"a\":");
    std::printf("json.truncated=%s\n", bad ? "accepted" : "rejected");
}

static void ply() {
    const std::string text =
        "ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\n"
        "end_header\n1 2 3\n4 5 6\n7 8 9\n";
    std::istringstream in(text, std::ios::binary);
    tinyply::PlyFile f;
    f.parse_header(in);
    auto v = f.request_properties_from_element("vertex", {"x", "y", "z"});
    f.read(in);
    const float* p = reinterpret_cast<const float*>(v->buffer.get());
    std::printf("ply.count=%zu\nply.values=", v->count);
    for (size_t i = 0; i < v->count * 3; ++i) std::printf("%g,", p[i]);
    std::printf("\n");
}

static void stb() {
    // 2x1 binary PPM: red, blue
    const unsigned char ppm[] = {'P', '6', ' ', '2', ' ', '1', ' ', '2', '5', '5', '\n', 255, 0, 0, 0, 0, 255};
    int w = 0, h = 0, c = 0;
    unsigned char* px = stbi_load_from_memory(ppm, sizeof(ppm), &w, &h, &c, 3);
    if (!px) { std::printf("stb=error\n"); return; }
    std::printf("stb.dims=%dx%dx%d\nstb.pixels=%d,%d,%d,%d,%d,%d\n", w, h, c, px[0], px[1], px[2], px[3], px[4], px[5]);
    stbi_image_free(px);
    const unsigned char junk[] = "this is not an image";
    std::printf("stb.junk=%s\n", stbi_load_from_memory(junk, sizeof(junk), &w, &h, &c, 3) ? "accepted" : "rejected");
}

static void spz_rt() {
    spz::GaussianCloud g;
    g.numPoints = 2;
    g.shDegree = 0;
    g.positions = {1.0f, -2.0f, 0.5f, 0.0f, 3.0f, -1.5f};
    g.scales = {-1, -1, -1, -2, -2, -2};
    g.rotations = {0, 0, 0, 1, 0, 0, 0, 1};
    g.alphas = {0.5f, -0.5f};
    g.colors = {0.1f, 0.2f, 0.3f, -0.1f, -0.2f, -0.3f};
    std::vector<uint8_t> bytes;
    if (!spz::saveSpz(g, spz::PackOptions{}, &bytes)) { std::printf("spz=save-error\n"); return; }
    spz::GaussianCloud r = spz::loadSpz(bytes, spz::UnpackOptions{});
    std::printf("spz.points=%d\nspz.sh_degree=%d\nspz.positions=", r.numPoints, r.shDegree);
    for (float v : r.positions) std::printf("%.2f,", v);
    std::printf("\n");
}

static void openmesh() {
    {
        TriMesh m;
        std::istringstream in("v 0 0 0\nv 1 0 0\nv 0 1 0\nv 1 1 0\nf 1 2 3\nf 2 4 3\n");
        OpenMesh::IO::Options o;
        const bool ok = OpenMesh::IO::read_mesh(m, in, ".obj", o);
        std::printf("om.obj=%d:%zu:%zu:%zu\n", ok, m.n_vertices(), m.n_faces(), m.n_edges());
    }
    {
        PolyMesh m;
        std::istringstream in("OFF\n4 1 0\n0 0 0\n1 0 0\n1 1 0\n0 1 0\n4 0 1 2 3\n");
        OpenMesh::IO::Options o;
        const bool ok = OpenMesh::IO::read_mesh(m, in, ".off", o);
        std::printf("om.off=%d:%zu:%zu\n", ok, m.n_vertices(), m.n_faces());
    }
    {
        TriMesh m;
        std::istringstream in("solid t\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\n"
                              "endloop\nendfacet\nendsolid t\n");
        OpenMesh::IO::Options o;
        const bool ok = OpenMesh::IO::read_mesh(m, in, ".stl", o);
        std::printf("om.stl=%d:%zu:%zu\n", ok, m.n_vertices(), m.n_faces());
    }
    {
        TriMesh m;
        std::istringstream in("ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\n"
                              "property float z\nelement face 1\nproperty list uchar int vertex_indices\n"
                              "end_header\n0 0 0\n1 0 0\n0 1 0\n3 0 1 2\n");
        OpenMesh::IO::Options o;
        const bool ok = OpenMesh::IO::read_mesh(m, in, ".ply", o);
        std::printf("om.ply=%d:%zu:%zu\n", ok, m.n_vertices(), m.n_faces());
    }
}

int main(int argc, char** argv) {
    const std::string which = argc > 1 ? argv[1] : "all";
    if (which == "all" || which == "usd") usd();
    if (which == "all" || which == "python") python();
    if (which == "all" || which == "json") json();
    if (which == "all" || which == "ply") ply();
    if (which == "all" || which == "stb") stb();
    if (which == "all" || which == "spz") spz_rt();
    if (which == "all" || which == "openmesh") openmesh();
    return 0;
}
