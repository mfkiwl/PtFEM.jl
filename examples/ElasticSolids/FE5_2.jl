function FE5_2(data::Dict)
  
  # Setup basic dimensions of arrays
  # Parse & check FEdict data
  
  if :element_type in keys(data)
    element_type = data[:element_type]
  else
    println("No element type specified.")
    return
  end
  
  ndim = element_type.ndim
  nst = element_type.nst
  
  # Handle :r direction (implicit axisymmetric)
  if element_type.direction == :r
    nre = element_type.nxe::Int64
    nze = element_type.nye::Int64
  end
  
  # Add radial stress
  if element_type.axisymmetric
    nst = 4
  end
  
  element = element_type.element
  @assert typeof(element) <: Element
  
  if typeof(element) == Line
    (nels, nn) = mesh_size(element, element_type.nxe)
  elseif typeof(element) == Triangle || typeof(element) == Quadrilateral
    (nels, nn) = mesh_size(element, element_type.nxe, element_type.nye)
  elseif typeof(element) == Hexahedron
    (nels, nn) = mesh_size(element, element_type.nxe, element_type.nye, element_type.nze)
  else
    println("$(typeof(element)) is not a known finite element.")
    return
  end
     
  nodof = element.nodof           # Degrees of freedom per node
  ndof = element.nod * nodof      # Degrees of freedom per element
  
  # Update penalty if specified in FEdict
  
  penalty = 1e20
  if :penalty in keys(data)
    penalty = data[:penalty]
  end
  
  # Allocate all arrays
  
  # Start with arrays to be initialized from FEdict
  
  if :properties in keys(data)
    prop = zeros(size(data[:properties], 1), size(data[:properties], 2))
    for i in 1:size(data[:properties], 1)
      prop[i, :] = data[:properties][i, :]
    end
  else
    println("No :properties key found in FEdict.")
    exit(1)
  end
    
  nf = ones(Int64, nodof, nn)
  if :support in keys(data)
    for i in 1:size(data[:support], 1)
      nf[:, data[:support][i][1]] = data[:support][i][2]
    end
  else
    println("No :supports key found in FEdict.")
    exit(1)
  end
  
  x_coords = zeros(nn)
  if :x_coords in keys(data)
    x_coords = data[:x_coords]
  end
  
  y_coords = zeros(nn)
  if :y_coords in keys(data)
    y_coords = data[:y_coords]
  end
  
  z_coords = zeros(nn)
  if :z_coords in keys(data)
    z_coords = data[:z_coords]
  end

  r_coords = zeros(nn)
  if :r_coords in keys(data)
    r_coords = data[:r_coords]
  end

  etype = ones(Int64, nels)
  if :etype in keys(data)
    etype = data[:etype]
  end
  
  @assert :lth in keys(data)
  @assert :iflag in keys(data)
  @assert :chi in keys(data)
  lth = data[:lth]::Int64
  iflag = data[:iflag]::Int64
  chi = data[:chi]*pi/180.0
  ca = cos(chi)
  sa = sin(chi)
  radius = 0.0
  
  # All other arrays
  
  points = zeros(element_type.nip, ndim)
  g = zeros(Int64, ndof)
  g_coord = zeros(ndim,nn)
  fun = zeros(element.nod)
  coord = zeros(element.nod, ndim)
  gamma = zeros(nels)
  jac = zeros(ndim, ndim)
  g_num = zeros(Int64, element.nod, nels)
  der = zeros(ndim, element.nod)
  deriv = zeros(ndim, element.nod)
  bee = zeros(nst,ndof)
  km = zeros(ndof, ndof)
  mm = zeros(ndof, ndof)
  gm = zeros(ndof, ndof)
  kg = zeros(ndof, ndof)
  eld = zeros(ndof)
  weights = zeros(element_type.nip)
  g_g = zeros(Int64, ndof, nels)
  num = zeros(Int64, element.nod)
  actions = zeros(ndof, nels)
  displacements = zeros(size(nf, 1), ndim)
  gc = ones(ndim)
  dee = zeros(nst,nst)
  sigma = zeros(nst)
  axial = zeros(nels)
  
  formnf!(nodof, nn, nf)
  neq = maximum(nf)
  kdiag = zeros(Int64, neq)
  
  # Find global array sizes
  
  for iel in 1:nels
    geom_rect!(element, iel, r_coords, z_coords, coord, num, element_type.direction)
    num_to_g!(num, nf, g)
    g_num[:, iel] = num
    g_coord[:, num] = coord'
    g_g[:, iel] = g
    fkdiag!(kdiag, g)
  end
  
  for i in 2:neq
    kdiag[i] = kdiag[i] + kdiag[i-1]
  end
  
  kv = zeros(kdiag[neq])
  gv = zeros(kdiag[neq])
  
  println("There are $(neq) equations and the skyline storage is $(kdiag[neq]).")
  
  sample!(element, points, weights)

  for iel in 1:nels
    deemat!(dee, prop[etype[iel], 1], prop[etype[iel], 2])
    num = g_num[:, iel]
    coord = g_coord[:, num]'              # Transpose
    g = g_g[:, iel]
    km = zeros(ndof, ndof)
    for i in 1:element_type.nip
      shape_fun!(fun, points, i)
      shape_der!(der, points, i)
      jac = der*coord
      detm = det(jac)
      jac = inv(jac)
      deriv = jac*der
      (radius, bee) = beemat_nonaxi!(bee, radius, coord, deriv, fun, iflag, lth)
      km += (((bee')*dee)*bee)*detm*weights[i]*radius
    end
    fsparv!(kv, km, g, kdiag)
  end
  println()
  
  loads = zeros(neq + 1)
  if :loaded_nodes in keys(data)
    for i in 1:size(data[:loaded_nodes], 1)
      loads[nf[:, data[:loaded_nodes][i][1]]+1] = data[:loaded_nodes][i][2]
    end
  end
  
  fixed_freedoms = 0
  if :fixed_freedoms in keys(data)
    fixed_freedoms = size(data[:fixed_freedoms], 1)
  end
  no = zeros(Int64, fixed_freedoms)
  node = zeros(Int64, fixed_freedoms)
  sense = zeros(Int64, fixed_freedoms)
  value = zeros(Float64, fixed_freedoms)
  if :fixed_freedoms in keys(data) && fixed_freedoms > 0
    for i in 1:fixed_freedoms
      no[i] = nf[data[:fixed_freedoms][i][2], data[:fixed_freedoms][i][1]]
      value[i] = data[:fixed_freedoms][i][3]
    end
    kv[kdiag[no]] = kv[kdiag[no]] + penalty
    loads[no+1] = kv[kdiag[no]] .* value
  end
  
  sparin!(kv, kdiag)
  loads[2:end] = spabac!(kv, loads[2:end], kdiag)
  loads[1] = 0.0
  nf1 = deepcopy(nf) + 1
  
  println("\nNode     r-disp          z-disp          t-disp")
  
  tmp = []
  for i in 1:nn
    tmp = vcat(tmp, loads[nf1[:,i]])
    rstr = @sprintf("%+.4e", loads[nf1[1,i]])
    zstr = @sprintf("%+.4e", loads[nf1[2,i]])
    tstr = @sprintf("%+.4e", loads[nf1[3,i]])
    println("  $(i)    $(rstr)     $(zstr)     $(tstr)")
  end
  
  element_type.nip = 1
  points = zeros(element_type.nip, ndim)
  weights = zeros(element_type.nip)
  sample!(element, points, weights)
  println("\nThe integration point (nip = $(element_type.nip)) stresses are:")
  println("\nElement  r-coord   z-coord     sig_r         sig_z        sig-t")
  println("                               tau_rz        tau_zt       tau-tr")
  for iel in 1:nels
    deemat!(dee, prop[etype[iel], 1], prop[etype[iel], 2])
    num = g_num[:, iel]
    coord = g_coord[:, num]'
    g = g_g[:, iel]
    eld = loads[g+1]
    for i in 1:element_type.nip
      shape_fun!(fun, points, i)
      shape_der!(der, points, i)
      gc = fun'*coord
      jac = inv(der*coord)
      deriv = jac*der
      (radius, bee) = beemat_nonaxi!(bee,radius,coord,deriv,fun,iflag,lth)
      bee[1:4,:]=bee[1:4,:]*ca 
      bee[5:6,:]=bee[5:6,:]*sa
      sigma = dee*(bee*eld)
      gc1 = @sprintf("%+.4f", gc[1])
      gc2 = @sprintf("%+.4f", gc[2])
      s1 = @sprintf("%+.4e", sigma[1])
      s2 = @sprintf("%+.4e", sigma[2])
      s3 = @sprintf("%+.4e", sigma[3])
      s4 = @sprintf("%+.4e", sigma[4])
      s5 = @sprintf("%+.4e", sigma[5])
      s6 = @sprintf("%+.4e", sigma[6])
      println("   $(iel)     $(gc1)   $(gc2)   $(s1)  $(s2)  $(s3)")
      println("                             $(s4)  $(s5)  $(s6)")
    end
  end
  println()
  
  
  FEM(element_type, element, ndim, nels, nst, ndof, nn, nodof, neq, penalty,
    etype, g, g_g, g_num, kdiag, nf, no, node, num, sense, actions, 
    bee, coord, gamma, dee, der, deriv, displacements, eld, fun, gc,
    g_coord, jac, km, mm, gm, kv, gv, loads, points, prop, sigma, value,
    weights, x_coords, y_coords, z_coords, axial)
  
end

