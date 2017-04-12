using Base.Test, PtFEM, Compat

data = Dict(
  # Plane(ndim, nst, nxe, nye, nip, direction, finite_element(nod, nodof), axisymmetric)
  :struc_el => Plane(2, 4, 8, 4, 4, :y, Quadrilateral(8, 2), false),
  :properties => [100.0 1.0e5 0.3;],
  :x_coords => [0.0, 1.0, 2.0, 3.0, 4.0, 5.5, 7.0, 9.0, 12.0],
  :y_coords => [0.0, -1.25, -2.5, -3.75, -5.0],
  :support => [
    (  1, [0 1]), (  2, [0 1]), (  3, [0 1]), (  4, [0 1]), (  5, [0 1]), (  6, [0 1]),
    (  7, [0 1]), (  8, [0 1]), (  9, [0 0]), ( 14, [0 0]), ( 23, [0 0]), ( 28, [0 0]),
    ( 37, [0 0]), ( 42, [0 0]), ( 51, [0 0]), ( 56, [0 0]), ( 65, [0 0]), ( 70, [0 0]),
    ( 79, [0 0]), ( 84, [0 0]), ( 93, [0 0]), ( 98, [0 0]), (107, [0 0]), (112, [0 0]),
    (113, [0 1]), (114, [0 1]), (115, [0 1]), (116, [0 1]), (117, [0 1]), (118, [0 1]),
    (119, [0 1]), (120, [0 1]), (121, [0 0])
  ],
  :loaded_nodes => [
    ( 1, [0.0 -0.166667]), (10, [0.0 -0.666667]), (15, [0.0 -0.333333]),
    (24, [0.0 -0.666667]), (29, [0.0 -0.166667])
  ],
  :tol => 0.001,
  :limit => 250,
  :qincs => [200.0, 100.0, 50.0, 50.0, 50.0, 30.0, 20.0, 10.0, 5.0, 4.0],
  :cg_tol => 0.0001,
  :cg_limit => 100
)

@time m = p62(data)

@test m ≈ [10,519.0,-0.0710794,250] atol=1.0e-6
