function FE5_6(data::Dict, profiling::Bool=false)
  
  # Setup basic dimensions of arrays
  
  # Parse & check FEdict data
  
  if :element_type in keys(data)
    element_type = deepcopy(data[:element_type])
    @assert typeof(element_type) <: ElementType
  else
    println("No element type specified.")
    return
  end
  
  ndim = copy(element_type.ndim)
  nst = copy(element_type.nst)
  
  element = deepcopy(element_type.element)
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
     
  nodof = copy(element.nodof)           # Degrees of freedom per node
  ndof = element.nod * nodof      # Degrees of freedom per element
  
  # Update penalty if specified in FEdict
  
  penalty = 1e20
  if :penalty in keys(data)
    penalty = copy(data[:penalty])
  end
  
  # Allocate all arrays
  
  # Start with arrays to be initialized from FEdict
  
  if :properties in keys(data)
    prop = zeros(size(data[:properties], 1), size(data[:properties], 2))
    for i in 1:size(data[:properties], 1)
      prop[i, :] = deepcopy(data[:properties][i, :])
    end
  else
    println("No :properties key found in FEdict")
  end
    
  nf = ones(Int64, nodof, nn)
  if :support in keys(data)
    for i in 1:size(data[:support], 1)
      nf[:, data[:support][i][1]] = deepcopy(data[:support][i][2])
    end
  end
  
  x_coords = zeros(nn)
  if :x_coords in keys(data)
    x_coords = deepcopy(data[:x_coords])
  end
  
  y_coords = zeros(nn)
  if :y_coords in keys(data)
    y_coords = deepcopy(data[:y_coords])
  end
  
  z_coords = zeros(nn)
  if :z_coords in keys(data)
    z_coords = deepcopy(data[:z_coords])
  end

  etype = ones(Int64, nels)
  if :etype in keys(data)
    etype = deepcopy(data[:etype])
  end
  
  g_coord = zeros(ndim,nn)
  if :g_coord in keys(data)
    g_coord = deepcopy(data[:g_coord]')
  end
  
  g_num = zeros(Int64, element.nod, nels)
  if :g_num in keys(data)
    g_num = reshape(deepcopy(data[:g_num]'), element.nod, nels)
  end
  
  etype = ones(Int64, nels)
  if :etype in keys(data)
    etype = deepcopy(data[:etype])
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
  
  # PCG & program specific variables
  storkm = zeros(ndof, ndof, nels)
  cg_converged = false
  solid = false
  
  p = zeros(neq+1)
  loads = zeros(Float64, neq+1)
  x = zeros(neq+1)
  xnew = zeros(neq+1)
  u = zeros(neq+1)
  diag_precon = zeros(neq+1)
  d = zeros(neq+1)
  
  if :cg_tol in keys(data)
    cg_tol = copy(data[:cg_tol])
  else
    cg_tol = 1.0e-5
  end
  
  if :cg_limit in keys(data)
    cg_limit = copy(data[:cg_limit])
  else
    cg_limit = 200
  end
  
  for i in 2:neq
    kdiag[i] = kdiag[i] + kdiag[i-1]
  end
  
  kv = zeros(kdiag[neq])
  gv = zeros(kdiag[neq])

  println("There are $(neq) equations.")
  
  sample!(element, points, weights)

  for iel in 1:nels
    hexahedron_xz!(iel, x_coords, y_coords, z_coords, coord, num)
    num_to_g!(num, nf, g)
    g_num[:, iel] = num
    g_coord[:, num] = coord'
    g_g[:, iel] = g
    deemat!(dee, prop[etype[iel], 1], prop[etype[iel], 2])
    num = g_num[:, iel]
    g = g_g[:, iel]
    coord = g_coord[:, num]'              # Transpose
    km = zeros(ndof, ndof)
    for i in 1:element_type.nip
      shape_der!(der, points, i)
      jac = der*coord
      detm = det(jac)
      jac = inv(jac)
      deriv = jac*der
      beemat!(bee, deriv)
      storkm[:,:,iel] += (bee')*dee*bee*detm*weights[i]
    end
    for k in 1:ndof
      diag_precon[g[k]+1] += storkm[k,k,iel]
    end
  end
  
  if :loaded_nodes in keys(data)
    for i in 1:size(data[:loaded_nodes], 1)
      loads[nf[:, data[:loaded_nodes][i][1]]+1] = deepcopy(data[:loaded_nodes][i][2])
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
      no[i] = nf[deepcopy(data[:fixed_freedoms][i][2]), deepcopy(data[:fixed_freedoms][i][1])]
      value[i] = deepcopy(data[:fixed_freedoms][i][3])
    end
    diag_precon[no+1] += penalty
    loads[no+1] = diag_precon[no+1] .* value
    store = diag_precon[no+1]
  end

  #mesh_ensi(...)
  
  diag_precon = 1.0 ./ diag_precon
  diag_precon[1] = 0.0
  d = diag_precon .* loads
  p = deepcopy(d)
  x = zeros(neq+1)
  xnew = zeros(neq+1)
  
  profiling && println("Start of CG loop.")
  cg_iters = 0
  while true
    cg_iters += 1
    !profiling && print(".")
    u = zeros(neq+1)
    for iel in 1:nels
      g[:] = g_g[:, iel]
      #km[:,:] = storkm[:, :, iel]
      u[g+1] += storkm[:, :, iel]*p[g+1]
    end
    if fixed_freedoms !== 0
      u[no+1] = p[no+1]*store
    end
    up = dot(loads, d)
    alpha = up/dot(p, u)
    xnew = x + p*alpha
    loads[:] -= u*alpha
    d = diag_precon .* loads
    beta = dot(loads, d)/up
    #@show [cg_iters beta] 
    p = d + p*beta
    cg_converged = checon!(xnew, x, cg_tol, cg_converged)
    if cg_converged || cg_iters >= cg_limit
      break
    end
  end
  println()
  
  loads = xnew
  loads[1] = 0.0
  
  
  println("Number of cg iterations to convergence was $(cg_iters).")
  if !profiling
    println("\nNode     x-disp          y-disp          z-disp")
  
    nf1 = deepcopy(nf) + 1
  
    tmp = []
    for i in 1:nn
      xstr = @sprintf("%+.4e", loads[nf1[1,i]])
      ystr = @sprintf("%+.4e", loads[nf1[2,i]])
      zstr = @sprintf("%+.4e", loads[nf1[3,i]])
      println("  $(i)    $(xstr)     $(ystr)     $(zstr)")
    end
  
    #dismsh_ensi()
  end
  
  element_type.nip = 1
  points = zeros(element_type.nip, ndim)
  weights = zeros(element_type.nip)
  sample!(element, points, weights)
  
  if !profiling
    println("\nThe integration point (nip = $(element_type.nip)) stresses are:")
    println("\nElement  x-coord   y-coord      z_coord      sig_x        sig_y        sig_z")
    println("                                             tau_xy       tau_yz       tau_zx")
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
      if !profiling
        gc1 = @sprintf("%+.4f", gc[1])
        gc2 = @sprintf("%+.4f", gc[2])
        gc3 = @sprintf("%+.4f", gc[3])
        s1 = @sprintf("%+.4e", sigma[1])
        s2 = @sprintf("%+.4e", sigma[2])
        s3 = @sprintf("%+.4e", sigma[3])
        s4 = @sprintf("%+.4e", sigma[4])
        s5 = @sprintf("%+.4e", sigma[5])
        s6 = @sprintf("%+.4e", sigma[6])
        println("   $(iel)     $(gc1)  $(gc2)          $(gc[3])   $(s1)  $(s2)  $(s3)")
        println("                                          $(s4)  $(s5)  $(s6)")
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

