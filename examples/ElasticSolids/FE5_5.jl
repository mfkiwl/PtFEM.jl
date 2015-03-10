function FE5_4(data::Dict)
  
  # Setup basic dimensions of arrays
  
  # Parse & check FEdict data
  
  if :element_type in keys(data)
    element_type = data[:element_type]
    @assert typeof(element_type) == GenericSolid
  else
    println("No element type specified.")
    return
  end
  
  ndim = element_type.ndim
  nst = element_type.nst
  nels = element_type.nels
  nn = element_type.nn
  
  element = element_type.element
  @assert typeof(element) <: Element
  
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
    println("No :properties key found in FEdict")
  end
    
  nf = ones(Int64, nodof, nn)
  if :support in keys(data)
    for i in 1:size(data[:support], 1)
      nf[:, data[:support][i][1]] = data[:support][i][2]
    end
  end
  
  x_coords = zeros(nn)
  y_coords = zeros(nn)
  z_coords = zeros(nn)
  
  g_coord = zeros(ndim,nn)
  @assert :g_coord in keys(data)
  g_coord = data[:g_coord]'
  
  g_num = zeros(Int64, element.nod, nels)
  @assert :g_num in keys(data)
  g_num = reshape(data[:g_num]', element.nod, nels)

  etype = ones(Int64, nels)
  if :etype in keys(data)
    etype = data[:etype]
  end
  
  # All other arrays
  
  points = zeros(element_type.nip, ndim)
  g = zeros(Int64, ndof)
  fun = zeros(element.nod)
  coord = zeros(element.nod, ndim)
  gamma = zeros(nels)
  jac = zeros(ndim, ndim)
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
  
  loads = zeros(Float64, neq+1)
  gravlo = zeros(Float64, neq+1)
  
  # Find global array sizes
  for iel in 1:nels
    num = g_num[:, iel]
    num_to_g!(num, nf, g)
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
      beemat!(bee, deriv)
      km += (bee')*dee*bee*detm*weights[i]
      eld[nodof:nodof:ndof] += fun[:]*detm*weights[i]
    end
    fsparv!(kv, km, g, kdiag)
    gravlo[g+1] -= eld*prop[etype[iel], 3]
  end
  
  if :loaded_nodes in keys(data)
    for i in 1:size(data[:loaded_nodes], 1)
      loads[nf[:, data[:loaded_nodes][i][1]]+1] = data[:loaded_nodes][i][2]
    end
  end
  loads += gravlo
  
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
  
  if ndim == 3
    println("\nNode     x-disp          y-disp          z-disp")
  else
    println("\nNode     x-disp          y-disp")
  end
  
  tmp = []
  for i in 1:nn
    xstr = @sprintf("%+.4e", loads[nf1[1,i]])
    ystr = @sprintf("%+.4e", loads[nf1[2,i]])
    if ndim == 3
      zstr = @sprintf("%+.4e", loads[nf1[3,i]])
      println("  $(i)    $(xstr)     $(ystr)     $(zstr)")
    else
      println("  $(i)    $(xstr)     $(ystr)")
    end
  end
  
  println("\nThe integration point (nip = $(element_type.nip)) stresses are:")
  println("\nElement  x-coord   y-coord      sig_x        sig_y        sig_z")
  if ndim == 3
    println("                                tau_xy       tau_yz       tau_zx")
  end
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
      beemat!(bee, deriv)
      sigma = dee*(bee*eld)
      gc1 = @sprintf("%+.4f", gc[1])
      gc2 = @sprintf("%+.4f", gc[2])
      s1 = @sprintf("%+.4e", sigma[1])
      s2 = @sprintf("%+.4e", sigma[2])
      s3 = @sprintf("%+.4e", sigma[3])
      if ndim == 3
        s4 = @sprintf("%+.4e", sigma[4])
        s5 = @sprintf("%+.4e", sigma[5])
        s6 = @sprintf("%+.4e", sigma[6])
      end
      println("   $(iel)     $(gc1)   $(gc2)   $(s1)  $(s2)  $(s3)")
      if ndim == 3
        println("                             $(s4)  $(s5)  $(s6)")
      end
    end
  end
  println()
  
  FEM(element_type, element, ndim, nels, nst, ndof, nn, nodof, neq, penalty,
    etype, g, g_g, g_num, kdiag, nf, no, node, num, sense, actions, 
    bee, coord, gamma, dee, der, deriv, displacements, eld, fun, gc,
    g_coord, jac, km, mm, gm, kv, gv, loads, points, prop, sigma, value,
    weights, x_coords, y_coords, z_coords, axial)
  end

