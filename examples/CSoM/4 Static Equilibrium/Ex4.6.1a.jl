using CSoM

ProjDir = dirname(@__FILE__)

data = Dict(
  # Beam(ndim, nst, nxe, nip, direction, finite_element(nod, nodof), axisymmetric)
  :struc_el => Beam(2, 1, 100, 1, :x, Line(2, 1), false),
  :properties => [1.0;],
  :x_coords => 0.0:0.01:1.0,
  :support => [
    (1, [0 1]),
    (101, [0 0])
    ],
  :limit => 100,
  :tol => 0.00001
)

data |> display
println()

@time m = p4_6(data)
println()

println("\nThe buckling load = $(m[1])\n")
using DataTables
buckling_dt = DataTable(
  translation = m[4][m[5][1,:]+1],
  rotation = m[4][m[5][2,:]+1]
)
display(buckling_dt)
println()
  
if VERSION.minor < 6
  using Plots
  gr(size=(400,600))

  p = Vector{Plots.Plot{Plots.GRBackend}}(2)
  titles = ["p4.6.1a translation", "p4.6.1a rotation"]
  p[1] = plot(
    convert(Array, buckling_dt[:translation]), 
    ylim=(-0.1, 0.3), xlabel="node",
    ylabel="y translation [m]", color=:blue,
    marker=(:circle,1,0.1,stroke(1,:black)),
    title=titles[1], leg=false)
  p[2] = plot(
    convert(Array, buckling_df[:rotation]),
    ylim=(-1.0, 1.0), xlabel="node", 
    ylabel="rotation [radians]", color=:red,
    marker=(:circle,1,0.1,stroke(1,:black)),
    title=titles[2], leg=false)

  plot(p..., layout=(2, 1))
  savefig(ProjDir*"/Ex4.6.1a.png")
  
end
