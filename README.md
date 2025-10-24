# PFSankey.jl

**PFSankey.jl** is a Julia package for visualizing **power flow data** using interactive **Sankey diagrams**.  
It provides a convenient interface for exploring how power flows through networks, with nodes and branches rendered dynamically using [GLMakie](https://makie.juliaplots.org/stable/).

It is developed under [CRESYM-OptGrid](https://cresym.eu/optgrid/) project supervised by TU-Delft and sponsored by RTE.

---

## 🚀 Features

- Generate Sankey diagrams for power flow analysis.
- Automatic scaling and layout based on flow magnitudes.
- Smooth integration with Makie visualization tools.

---

## 📦 Installation

This package is not yet registered, but you can install it directly from GitHub:

```julia
using Pkg
Pkg.add(url="https://github.com/BenoitJeanson/pfsankey.git")
```

Then load it in Julia:

```julia
using PFSankey
```

---

## 🧠 Basic Usage

Example scripts can be found in the [`examples/`](./examples) directory.  
To run a demonstration:

```julia
include("examples/demo.jl")
```

This will open an interactive window showing a sample power flow diagram.

---

## ⚙️ Development

To work on this package locally:

```julia
using Pkg
Pkg.develop(url="https://github.com/BenoitJeanson/pfsankey.git")
```

You can then make changes under `src/` and test them with the examples.

---

## 🧩 Dependencies

- [GLMakie.jl](https://github.com/MakieOrg/Makie.jl) – for interactive graphics
- [GeometryBasics.jl](https://github.com/JuliaGeometry/GeometryBasics.jl)
- Standard Julia packages: `LinearAlgebra`, `Statistics`, `Random`, etc.

---

## 📜 License

This project is released under the [APACHE 2.0](LICENSE).

---

## 📧 Contact

For issues, suggestions, or contributions, please open an [issue](https://github.com/BenoitJeanson/pfsankey/issues) or submit a pull request.
