using Requests: get
using SeisIO

# =============================================================
# Utility functions not for export

# Remove null entries of arrays that we plan to reuse
sa_prune!(S::Union{Array{String,1},Array{SubString{String},1}}) = (deleteat!(S, find(isempty, S)); return S)

gc_ctr(lat, lon) = (atan(tan(lat*π/180.0)*0.9933056), lon*π/180.0)
gc_unwrap!(t::Array{Float64,1}) = (t[t .< 0] .+= 2.0*π; return t)

get_phase_start(pha::String, Pha::Array{String,2}) = findmin([parse(Float64,i) for i in Pha[:,4]])
get_phase_time(pha::String, Pha::Array{String,2}) = parse(Float64, Pha[find(Pha[:,3].==pha)[1],4])
get_phase_end(pha::String, Pha::Array{String,2}) = findmax([parse(Float64,i) for i in Pha[:,4]])

function next_phase(pha::String, Pha::Array{String,2})
  s = Pha[:,3]
  t = [parse(Float64,i) for i in Pha[:,4]]
  j = find(s.==pha)[1]
  i = t.-t[j].>0
  tt = t[i]
  ss = s[i]
  k = sortperm(tt.-t[j])[1]
  return(ss[k],tt[k])
end

function next_converted(pha::String, Pha::Array{String,2})
  s = Pha[:,3]
  t = [parse(Float64,i) for i in Pha[:,4]]
  j = find(s.==pha)[1]

  p = replace(lowercase(s[j]),"diff","")[end]
  if p == 'p'
    c = 's'
  else
    c = 'p'
  end
  p_bool = [replace(lowercase(a),"diff","")[end]==c for a in s]
  t_bool = t.-t[j].>0
  i = t_bool.*p_bool

  tt = t[i]
  ss = s[i]
  k = sortperm(tt.-t[j])[1]
  return(ss[k],tt[k])
end

function mkevthdr(evt_line::String)
  evt = split(evt_line,'|')
  cid = evt[9]
  CONTRIB_ID = isnumber(cid) ? parse(cid) : -1
  return SeisHdr( id = parse(Int64, evt[1]),
                  time = Dates.DateTime(evt[2]),
                  lat = parse(Float64, evt[3]),
                  lon = parse(Float64, evt[4]),
                  dep = parse(Float64, evt[5]),
                  auth = evt[6],
                  cat = evt[7],
                  contrib = evt[8],
                  contrib_id = CONTRIB_ID,
                  mag_typ = evt[10],
                  mag = parse(Float32, evt[11]),
                  mag_auth = evt[12],
                  loc_name = evt[13])
end
# =============================================================

"""
    S = evq(t)

Multi-server query for the events with the closest origin time to **t**. **t**
should be an ASCII string, formatted YYYY-MM-DDThh:mm:ss with times given in UTC
(e.g. "2001-02-08T18:54:32"). Returns a SeisHdr object.

Incomplete string queries are read to the nearest fully specified time
constraint, e.g., evq("2001-02-08") returns the nearest event to 2001-02-08T00:00:00
UTC. If no event is found on any server within one day of the specified search
time, evq exits with an error.

Additional arguments can be passed at the command line for more specific queries:

    S = evq(t, w=TIME_LENGTH)

Specify time length (in seconds) to search around **t**. Default is 86400.

    S = evq(t, x=true)

Treat **t** as exact (within one second). Overrides **w**.

    S = evq(t, mag=[MIN_MAG MAX_MAG])

Restrict queries to **MIN_MAG** ≤ m ≤ **MAX_MAG**.

    S = evq(s, n=N)

Return **N** events, rather than 1. S will be an array of SeisEvents.

    S = evq(s, lat=[LAT_MIN LAT_MAX], lon=[LON_MIN LON_MAX], dep=[DEP_MIN DEP_MAX])

Only search within the specified region. Specify lat and lon in decimal degrees;
treat North and East as positive, respectively. Specify dep in km.

    S = evq(s, src=SRC)

Only query server **SRC**. Specify as a string. See list of sources in SeisIO
documentation.
"""
function evq(ts::String;
  dep=[-30.0 700.0]::Array{Float64,2},
  lat=[-90.0 90.0]::Array{Float64,2},
  lon=[-180.0 180.0]::Array{Float64,2},
  mag=[6.0 9.9]::Array{Float64,2},
  n=1::Int,
  src="IRIS"::String,
  to=10::Real,
  w=600.0::Real,
  x=false::Bool,
  v=false::Bool,
  vv=false::Bool)
  if x
    w = 1.0
  end

  # Determine time window
  if length(ts) <= 14
    ts0 = string(ts[1:4],"-",ts[5:6],"-",ts[7:8],"T",ts[9:10],":",ts[11:12])
    if length(ts) > 12
      ts = string(ts0, ":", ts[13:14])
    else
      ts = string(ts0, ":00")
    end
  end
  ts = d2u(DateTime(ts))
  s = string(u2d(ts-w))
  t = string(u2d(ts+w))

  # Do multi-server query (not tested)
  if src == "All"
    sources = ["IRIS", "RESIF", "NCEDC", "GFZ"]
  else
    sources = split(src,",")
  end
  evt_data = Array{String,1}()
  for k in sources
    url = string(get_uhead(k), "event/1/query?",
    "starttime=", s, "&endtime=", t,
    "&minlat=", lat[1], "&maxlat=", lat[2],
    "&minlon=", lon[1], "&maxlon=", lon[2],
    "&mindepth=", dep[1], "&maxdepth=", dep[2],
    "&minmag=", mag[1], "&maxmag=", mag[2],
    "&format=text")
    evt_data = [evt_data; split(readall(get(url, timeout=to, headers=webhdr())), '\n')[2:end]]
    vv && println("evt_data = ", evt_data)
  end
  sa_prune!(evt_data)
  ot = Array{Float64,1}(length(evt_data))
  for i = 1:1:length(evt_data)
    ot[i] = d2u(DateTime(split(evt_data[i],"|")[2]))
  end
  k = sortperm(abs(ot.-ts))
  evt_cat = evt_data[k[1:n]]
  if n == 1
    return mkevthdr(evt_cat[1])
  else
    evt_list = Array{SeisHdr,1}(n)
    for i = 1:1:n
      evt_list[n] = mkevthdr(evt_cat[i])
    end
    return evt_list
  end
end

"""
(dist, az, baz) = gcdist([lat_src, lon_src], rec)

  Compute great circle distance, azimuth, and backazimuth from source
coordinates [lat_src, lon_src] to receiver coordinates [lat_rec, lon_rec].
*rec* should be a matix with latitudes in column 1, longitudes in column 2.

"""
function gcdist(src::Array{Float64,1}, rec::Array{Float64,2})
  N = size(rec, 1)
  lat_src = repmat([src[1]], N)
  lon_src = repmat([src[2]], N)
  lat_rec = rec[:,1]
  lon_rec = rec[:,2]

  ϕ1, λ1 = gc_ctr(lat_src, lon_src)
  ϕ2, λ2 = gc_ctr(lat_rec, lon_rec)
  Δϕ = ϕ2 - ϕ1
  Δλ = λ2 - λ1

  a = sin(Δϕ/2.0) .* sin(Δϕ/2.0) + cos(ϕ1) .* cos(ϕ2) .* sin(Δλ/2.0) .* sin(Δλ/2.0)
  Δ = 2.0 .* atan2(sqrt(a), sqrt(1.0 - a))
  A = atan2(sin(Δλ).*cos(ϕ2), cos(ϕ1).*sin(ϕ2) - sin(ϕ1).*cos(ϕ2).*cos(Δλ))
  B = atan2(-1.0.*sin(Δλ).*cos(ϕ1), cos(ϕ2).*sin(ϕ1) - sin(ϕ2).*cos(ϕ1).*cos(Δλ))

  # convert to degrees
  return (Δ.*180.0/π, gc_unwrap!(A).*180.0/π, gc_unwrap!(B).*180.0/π )
end
gcdist(lat0::Float64, lon0::Float64, lat1::Float64, lon1::Float64) = (gcdist([lat0, lon0], [lat1 lon1]))
gcdist(src::Array{Float64,2}, rec::Array{Float64,2}) = (gcdist([src[1], src[2]], rec))
gcdist(src::Array{Float64,2}, rec::Array{Float64,1}) = (
  warn("Multiple sources or source coords passed as a matrix; only using first coordinate pair!");
  gcdist([src[1,1], src[1,2]], [rec[1] rec[2]]);
  )

"""
    distaz!(S::SeisEvent)

Compute Δ, Θ by the Haversine formula. Updates `S` with distance, azimuth, and backazimuth for each channel. Values are stored as `S.data.misc["dist"], S.data.misc["az"], S.data.misc["baz"]`.

"""
function distaz!(S::SeisEvent)
  rec = Array{Float64,2}(S.data.n,2)
  for i = 1:S.data.n
    rec[i,:] = S.data.loc[i][1:2]
  end
  (dist, az, baz) = gcdist([S.hdr.lat, S.hdr.lon], rec)
  for i = 1:S.data.n
    S.data.misc[i]["dist"] = dist[i]
    S.data.misc[i]["az"] = az[i]
    S.data.misc[i]["baz"] = baz[i]
  end
end

"""
    T = get_pha(Δ::Float64, z::Float64)

Command-line interface to IRIS online travel time calculator using TauP (1-3). Returns a matrix of strings.

Specify `Δ` in decimal degrees, `z` in km.

### Keyword Arguments and Default Values
* `pha="ttall"`: comma-separated string of phases to return, e.g. "P,S,ScS"
* `model="iasp91"`: velocity model
* `to=10.0`: ste web request timeout, in seconds
* `v=false`: verbose mode
* `vv=false`: very verbose mode

### References
(1) IRIS travel time calculator: https://service.iris.edu/irisws/traveltime/1/
(2) TauP manual: http://www.seis.sc.edu/downloads/TauP/taup.pdf
(3) Crotwell, H. P., Owens, T. J., & Ritsema, J. (1999). The TauP Toolkit:
Flexible seismic travel-time and ray-path utilities, SRL 70(2), 154-160.
"""
function get_pha(Δ::Float64, z::Float64;
  phases=""::String,
  model="iasp91"::String,
  to=10.0::Real,
  v=false::Bool,
  vv=false::Bool)

  # Generate URL and do web query
  if isempty(phases)
    #pq = ""
    #pq = "&phases=p,s,P,S,pS,PS,sP,SP,Pn,Sn,PcP,Pdiff,Sdiff,PKP,PKiKP,PKIKP"
    pq = "&phases=ttall"
  else
    pq = string("&phases=", phases)
  end

  url = string("http://service.iris.edu/irisws/traveltime/1/query?", "distdeg=", Δ, "&evdepth=", z, pq, "&model=", model, "&mintimeonly=true&noheader=true")
  (v | vv) && println("url = ", url)
  req = readall(get(url, timeout=to, headers=webhdr()))
  (v | vv) && println("Request result:\n", req)

  # Parse results
  phase_data = split(req, '\n')
  sa_prune!(phase_data)
  Nf = length(split(phase_data[1]))
  Np = length(phase_data)
  Pha = Array{String,2}(Np, Nf)
  for p = 1:Np
    Pha[p,1:Nf] = split(phase_data[p])
  end
  return Pha
end



"""
    get_evt(evt::String, cc::String)

Get data for event **evt** on channels **cc**. Event and channel data are auto-filled using auxiliary functions.

Calls/see: `evq`, `get_sta`, `distaz!`, `
"""
function get_evt(evt::String, cc::String;
  mag=[6.0 9.9]::Array{Float64,2},
  to=10.0::Real,
  pha="P"::String,
  spad=1.0::Real,
  epad=0.0::Real,
  v=false::Bool,
  vv=false::Bool)

  if (v|vv)
    println(now(), ": request begins.")
  end

  # Parse channel config
  #(Sta, Cha) = chparse(cc)
  Q = SL_parse(C)
  Sta = Q[:,1]
  Cha = Q[:,2]

  # Create header
  h = evq(evt, mag=mag, to=to, v=v, vv=vv)      # Get event of interest with evq
  if (v|vv)
    println(now(), ": header query complete.")
  end

  # Create channel data
  s = h.time                                    # Start time for get_sta is event origin time
  t = u2d(d2u(s) + 1.0)                         # End time is one second later
  d = get_sta(Sta, Cha, st=s, et=t, to=to, v=v, vv=vv)
  if (v|vv)
    println(now(), ": channels initialized.")
  end

  # Initialize SeisEvent structure
  S = SeisEvent(hdr = h, data = d)
  if (v|vv)
    println(now(), ": SeisEvent created.")
  end
  vv && println(S)

  # Update S with distance, azimuth
  distaz!(S)
  if (v|vv)
    println(now(), ": Δ,Θ updated.")
  end

  # Desired behavior:
  # If the phase string supplied is "all", request window is spad s before P to twice the last phase arrival
  # If a phase name is supplied, request window is spad s before that phase to epad s after next phase
  pstr = Array{String,1}(S.data.n)
  bads = falses(S.data.n)
  for i = 1:1:S.data.n
    pdat = get_pha(S.data.misc[i]["dist"], S.hdr.dep, to=to, v=v, vv=vv)
    if pha == "all"
      j = get_phase_start(pdat)
      s = parse(Float64,pdat[j,4]) - spad
      t = 2.0*parse(Float64,pdat[get_phase_end(pdat),4])
      S.data.misc[i]["PhaseWindow"] = string(pdat[j,3], " : Coda")
    else
      # Note: at Δ > ~90, we must use Pdiff; we can't use P
      p1 = pha
      j = findfirst(pdat[:,3].==p1)
      if j == 0
        p1 = pha*"diff"
        j = findfirst(pdat[:,3].==p1)
        if j == 0
          error(string("Neither ", pha, " nor ", pha, "diff found!"))
        else
          warn(string(pha, "diff substituted for ", pha, " at ", S.data.id[i]))
        end
      end
      s = parse(Float64,pdat[j,4]) - spad
      #(p2,t) = nextPhase(p1, pdat)
      (p2,t) = next_converted(p1, pdat)
      t += epad
      S.data.misc[i]["PhaseWindow"] = string(p1, " : ", p2)
    end
    s = string(u2d(d2u(S.hdr.time) + s))
    t = string(u2d(d2u(S.hdr.time) + t))
    (NET, STA, LOC, CHA) = split(S.data.id[i],".")
    if isempty(LOC)
      LOC = "--"
    end
    C = FDSNget(net = NET, sta = STA, loc = LOC, cha = CHA,
                s = s, t = t, si = false, y = false, v=v, vv=vv)
    vv && println("FDSNget output:\n", C)
    if C.n == 0
      bads[i] = true
    else
      S.data.t[i] = C.t[1]
      S.data.x[i] = C.x[1]
      S.data.notes[i] = C.notes[1]
      S.data.src[i] = C.src[1]
      if (v | vv)
        println(now(), ": data acquired for ", S.data.id[i])
      end
    end
  end
  bad = find(bads.==true)
  if !isempty(bad)
    ids = join(S.data.id[bad],',')
    warn(string("Channels ", ids, " removed (no data were found)."))
    deleteat!(S.data, bad)
  end
  return S
end
