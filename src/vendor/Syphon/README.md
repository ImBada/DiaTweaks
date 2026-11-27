# Syphon (server only)

The Metal server half of [Syphon-Framework](https://github.com/Syphon/Syphon-Framework) at
`f4761677a45b8034a3c2069ec0f3d2553da81fba`, built into DiaPatches.dylib for Send PiP to Syphon, so it works
without Syphon.framework installed. BSD 2-clause; see License.txt.

Changes from upstream:

- `SyphonServerRendererMetal.m` compiles its shaders at runtime from `SyphonMetalShaderSource.h` instead of loading
  `default.metallib` from the framework bundle, since a dylib has no bundle and building a metallib needs Xcode.
- `SyphonMetalShaderSource.h` is new: `SyphonMetalShaders.metal` with `SyphonServerMetalTypes.h` inlined, as a C
  string. `SyphonMetalShaders.metal` is kept for reference and isn't built.

The client, OpenGL and directory files aren't here; `SyphonClientBase.h` is only for `SyphonSubclassing.h`.
