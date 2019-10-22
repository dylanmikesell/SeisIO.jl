function write_asdf( hdf_out::String, S::GphysData, chan_numbers::Array{Int64,1} ;
  add           ::Bool      = false,            # add traces
  ovr           ::Bool      = false,            # overwrite trace data
  len           ::Period    = Day(1),           # length of added traces
  v             ::Int64     = KW.v              # verbosity
  )

  # "add" implies "ovr"
  if add == true
    ovr = true
  end

  # Precheck for ungap, degenerate time structs
  if ovr
    for i in chan_numbers
      if (size(S.t[i],1) < 2) && (S.fs[i] != 0.0)
        error(string(S.id[i] *
          ": gapped :x or malformed :t; can't write with ovr=true."))
      end
    end
  end

  xml_buf = IOBuffer()
  netsta, cha, nsid = mk_netsta(S)

  if isfile(hdf_out)
    io = h5open(hdf_out, "r+")
    fmt = read(attrs(io)["file_format"])
    (fmt == "ASDF") || (close(io); error("invalid ASDF file!"))
    if has(io, "Waveforms")
      wav = io["Waveforms"]
    else
      wav = g_create(io, "Waveforms")
    end
  else
    io = h5open(hdf_out, "cw")
    attrs(io)["file_format"] = "ASDF"
    attrs(io)["file_format_version"] = "1.0.2"
    wav = g_create(io, "Waveforms")
  end

  # =======================================================================
  # Add "empty" traces of all NaNs
  if add
    nc = length(chan_numbers)
    ts = zeros(Int64, nc)
    te = zeros(Int64, nc)
    for (i,j) in enumerate(chan_numbers)
      ts[i] = S.t[j][1,2]*1000
      te[i] = endtime(S.t[j], S.fs[j])*1000
    end
    p = convert(Nanosecond, len).value
    asdf_mktrace(S, xml_buf, chan_numbers, wav, ts, te, p, v)
  end

  # determine a setting for msr
  if ovr
    msr = false
    for i in chan_numbers
      if typeof(S.resp[i]) == MultiStageResp
        msr = true
        break
      end
    end
  end

  # write channels to net.sta waveform groups
  for j in 1:length(nsid)
    (v > 0) && println("writing ", nsid)
    id = nsid[j]
    chans = Int64[]
    for i in chan_numbers
      if (netsta[i] == id) && (S.fs[i] != 0.0)
        push!(chans, i)
      end
    end
    nc = length(chans)

    # does net.sta exist?
    if has(wav, id)
      sta = wav[id]

      if ovr
        # ====================================================================
        # overwrite StationXML
        (v > 1) && println("merging XML")

        # read old XML
        SX = SeisData()
        sxml = String(UInt8.(read(sta["StationXML"])))
        read_station_xml!(SX, sxml, msr=msr, v=v)
        # (v > 2) && println("Current XML SeisData = ", SX)

        # merge S into SX, overwriting it
        SM = SeisData(length(chan_numbers))
        for f in (:id, :name, :loc, :fs, :gain, :resp, :units)
          setfield!(SM, f, deepcopy(getindex(getfield(S, f), chan_numbers)))
        end
        sxml_mergehdr!(SX, SM, nofs=true, app=false, v=v)
        # (v > 2) && println("Merged XML SeisData = ", SX)

        # remake channel list; SX ordering differs from S
        cc = Int64[]
        for i in 1:SX.n
          idx = split_id(SX.id[i])
          ns = idx[1]*"."*idx[2]
          if ns == id
            push!(cc, i)
          end
        end
        o_delete(sta, "StationXML")
        asdf_sxml(xml_buf, SX, cc, sta)

        # ==================================================================
        # overwrite trace data
        trace_ids = S.id[chans]
        # ts = zeros(Int64, nc)
        # te = zeros(Int64, nc)
        t = Array{Array{Int64,2},1}(undef,nc)
        for (i,j) in enumerate(chans)
          # ts[i] = S.t[j][1,2]*1000
          # te[i] = endtime(S.t[j], S.fs[j])*1000
          t[i] = t_win(S.t[j], S.fs[j])
          broadcast!(*, t[i], t[i], 1000)
        end
        (v > 2) && println("t = ", t)

        # loop over trace waveforms using id, start time, end time
        for n in names(sta)
          (n == "StationXML") && continue
          cha_id = String(split(n, "_", limit=2, keepempty=true)[1])
          x = sta[n]
          nx = length(x)
          t0 = read(x["starttime"])
          fs = read(x["sampling_rate"])

          # convert fs to sampling interval in ns
          Δ = round(Int64, 1.0e9/fs)
          t1 = t0 + (nx-1)*Δ

          for i in 1:length(chans)
            (trace_ids[i] == cha_id) || continue
            nk = size(t[i], 1)

            for k in 1:nk
              # overlap
              ts = t[i][k,1]
              te = t[i][k,2]
              if (ts ≤ t1) && (te ≥ t0)
                # set channel index j in S
                j = chans[i]

                # check for fs mismatch
                trace_fs = S.fs[j]
                Lx = length(S.x[j])
                if trace_fs != fs
                  @warn(string("Can't write ", S.id[j], "; fs mismatch!"))
                  continue
                end

                # determine start, end indices in x that are overwritten
                i0, i1, t2 = get_trace_bounds(ts, te, t0, t1, Δ, nx)

                # determine start, end indices in X to copy
                si, ei, t2 = get_trace_bounds(t0, t1, ts, te, Δ, Lx)

                # overwrite
                save_data!(S.x[j], x, i0:i1, si:ei)
              end
            end
          end

        end
      else
        for i in chans
          asdf_write_chan(S, sta, i, cha[i], v)
        end
      end

    elseif ovr == false
      # Create Waveforms/net.sta
      sta = g_create(wav, id)

      # Create Waveforms/net.sta/chan_str
      for i in chans
        asdf_write_chan(S, sta, i, cha[i], v)
      end

      # Write StationXML to sta
      asdf_sxml(xml_buf, S, chans, sta)
    end
  end

  close(xml_buf)
  close(io)
  return nothing
end
