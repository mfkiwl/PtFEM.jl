using Compat, Base.Test, CSoM

include(Pkg.dir("CSoM", "examples", "5 Elastic Solids", "FE5_1.jl"))

data = @compat Dict(
  # Plane(ndim, nst, nxe, nye, nip, direction, finite_element(nod, nodof), axisymmetric)
  :element_type => Plane(2, 3, 3, 2, 4, :y, Quadrilateral(4, 2), false),
  :properties => [1.0e6 0.3;],
  :x_coords => [0.0, 10.0, 20.0, 30.0],
  :y_coords => [0.0, -5.0, -10.0],
  :support => [
    (1, [0 1]),
    (2, [0 1]),
    (3, [0 0]),
    (6, [0 0]),
    (9, [0 0]),
    (10, [0 1]),
    (11, [0 1]),
    (12, [0 0])
    ],
  :fixed_freedoms => [
    (1, 2, -1.0e-5),
    (4, 2, -1.0e-5)
    ]
)

@time m = FE5_1(data)

@test_approx_eq_eps m.loads [0.0,-1.0000000000000035e-5,-5.152429570719046e-6,8.101475481120316e-8,-1.0000000000000072e-5,1.5820948250551495e-6,-4.593608962323964e-6,1.2407010196358915e-7,1.257758473173503e-6,1.4721403994132775e-6,1.953453349357416e-7,2.8154845809451437e-7,3.4748952771616183e-7] eps()