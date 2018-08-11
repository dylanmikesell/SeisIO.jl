# SeisIO
A minimalist, platform-agnostic package for working with univariate geophysical data.

| **Build Status: Julia v0.7.0** |
|:-------------------------------------------------------------------------------:|
| [![](https://travis-ci.org/jpjones76/SeisIO.jl.svg?branch=master)](https://travis-ci.org/jpjones76/SeisIO.jl) [![Build status](https://ci.appveyor.com/api/projects/status/ocilv0u1sy41m934?svg=true)](https://ci.appveyor.com/project/jpjones76/seisio-jl) |

# Documentation
http://seisio.readthedocs.org

# Current Functionality
SeisIO presently includes three web clients, readers for several data formats, and writers for SAC and a native SeisIO format. Utility functions allow synchronization, seamless data merging, and padding time gaps.

## Web clients
* SeedLink
* FDSN (data, event, and station queries)
* IRIS timeseries

## Readable File Formats
* SAC
* miniSEED
* SEG Y
  + rev 0
  + rev 1
  + PASSCAL/NMT single-channel files
* Win32
* UW

# Known Issues (2018-08-10)
* Rarely, `SeedLink!` may cause a Julia session to hang when a connection fails to initialize.
* Required packages LightXML and Blosc both generate "Deprecated syntax" warnings.

# Changelog
## 2018-08-10
* Updated for Julia 0.7. Testing for 1.0.
* `wseis` has changed:
  + New syntax: `wseis(filename, objects)`
  + Keywords are no longer accepted.
* `SeisHdr` has changed:
  + The field `:mag` (magnitude) is now Tuple(Float32, String) to allow freeform magnitude scale designations. (was: Tuple(Float32, Char, Char))
* `batch_read` has been removed.
* Switched to HTTP.jl due to Requests.jl being abandoned by its creators.
  + In web requests, keyword `to=` (timeout) must now be an Integer. (was: Real)
* SeisIO objects can no longer be saved in single-object files.
* Notable bug fixes:
  + Issues with `wseis` and `SeisHdr` objects should be corrected.
  + Improved partial string matches for channel names and IDs.

## 2017-08-07
* Improved `note!` functionality and logging of basic processing operations.
* New function: `clear_notes!` can delete notes for a given channel number or string ID.
* Minor bug fix for `readuw`
* Fixed a bug in how `ungap!` handled very short data segments (N < 20 samples).

## 2017-08-04
* Fixed a mini-SEED bug introduced 2017-07-16 where some IDs were set incorrectly.
* Internal function `tzcorr()` moved to PlotSeis.
* Added functions:
  + `env, env!`: Convert time-series data to envelopes (still in testing; gapped data not yet fully supported)
  + `del_sta!`: Delete all channels matching a station string (2nd part of ID)

# Acknowledgements
miniSEED routines are based on rdmseed.m for Matlab by Francois Beauducel, Institut de Physique du Globe de Paris (France). Many thanks to Robert Casey and Chad Trabant (IRIS, USA) for discussions of IRIS web services, and Douglas Neuhauser (UC Berkeley Seismological Laboratory, USA) for discussions of the SAC data format.

# References
1. IRIS (2010), SEED Reference Manual: SEED Format Version 2.4, May 2010, IFDSN/IRIS/USGS, http://www.iris.edu
2. Trabant C. (2010), libmseed: the Mini-SEED library, IRIS DMC.
3. Steim J.M. (1994), 'Steim' Compression, Quanterra Inc.
