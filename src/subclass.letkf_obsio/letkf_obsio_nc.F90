!================================================================================
!>
!================================================================================
MODULE letkf_obsio_nc_mod
  USE netcdf
  USE letkf_config
  USE letkf_obs
  USE letkf_mpi

  IMPLICIT NONE
  PRIVATE

  !================================================================================
  !================================================================================
  ! Public module components
  !================================================================================
  !================================================================================

  INTEGER, PARAMETER :: MAX_FILENAME_LEN = 1024

  !================================================================================
  !> observation file I/O class for handling NetCDF files
  !--------------------------------------------------------------------------------
  TYPE, EXTENDS(letkf_obsio), PUBLIC :: letkf_obsio_nc
     LOGICAL :: read_inc

     !> filename from which the observation files are read
     CHARACTER(LEN=MAX_FILENAME_LEN) :: filename_obs

     !> filename from which the ensemble model state in obseration space is read
     CHARACTER(LEN=MAX_FILENAME_LEN) :: filename_obs_hx

   CONTAINS
     PROCEDURE, NOPASS :: name => obsio_nc_get_name
     PROCEDURE, NOPASS :: desc => obsio_nc_get_desc
     PROCEDURE         :: init => obsio_nc_init
     PROCEDURE         :: read_obs => obsio_nc_read_obs
     PROCEDURE         :: read_hx  => obsio_nc_read_hx
  END TYPE letkf_obsio_nc
  !================================================================================





CONTAINS



  !================================================================================
  !> Get the unique name of the observation I/O class
  !! @param name short (less than ~10 character) class name
  !--------------------------------------------------------------------------------
  FUNCTION obsio_nc_get_name() RESULT(name)
    CHARACTER(:), ALLOCATABLE :: name
    name = "OBSIO_NC"
  END FUNCTION obsio_nc_get_name
  !================================================================================



  !================================================================================
  !> Get a human readable description of this observation I/O class
  !! @param desc description of the class
  !--------------------------------------------------------------------------------
  FUNCTION obsio_nc_get_desc() RESULT(desc)
    CHARACTER(:), ALLOCATABLE :: desc
    desc = "NetCDF formatted observation I/O"
  END FUNCTION obsio_nc_get_desc
  !================================================================================



  !================================================================================
  !> Initialize the netcdf obsio reader/writer.
  !! This loads in a section of the namelist (&letkf_obs_nc) to determine what the
  !! input filenames should be.
  !! @param nml_filename path to the namelist we are to open
  !--------------------------------------------------------------------------------
  SUBROUTINE obsio_nc_init(self, config)
    CLASS(letkf_obsio_nc) :: self
    TYPE(configuration), INTENT(in) :: config

    CHARACTER(len=:), ALLOCATABLE :: str

    IF (pe_isroot) THEN
       PRINT '(/A)', ""
       PRINT *, " letkf_obsio_nc_init() : "
       PRINT *, "============================================================"
    END IF

    ! load in our section of the namelist
    CALL config%get("filename_obs", str)
    self%filename_obs = str
    CALL config%get("filename_obshx", str)
    self%filename_obs_hx = str
    CALL config%get("read_inc", self%read_inc)
    IF(pe_isroot) THEN
       PRINT '(A,A)', " filename_obs=", TRIM(self%filename_obs)
       PRINT '(A,A)', " filename_obshx=", TRIM(self%filename_obs_hx)
       PRINT *, "read_inc=",self%read_inc
    END IF
  END SUBROUTINE obsio_nc_init
  !================================================================================



  !================================================================================
  !> Read the observations from a netcdf file.
  !! Note: this is the observation only (location, value, etc.) and NOT the
  !! per-ensemble observation departure
  !! @param obs the list of observations as they are loaded in.
  !--------------------------------------------------------------------------------
  SUBROUTINE obsio_nc_read_obs(self, obs)
    CLASS(letkf_obsio_nc) :: self
    TYPE(letkf_observation), ALLOCATABLE, INTENT(out) :: obs(:)

    LOGICAL :: ex
    INTEGER :: nobs, n
    INTEGER :: ncid, dimid, varid
    INTEGER, ALLOCATABLE :: tmp_i(:)
    REAL(4), ALLOCATABLE :: tmp_r(:)

    PRINT *, "Reading observations from file: ", TRIM(self%filename_obs)

    ! make sure the file exists
    INQUIRE(file=self%filename_obs, exist=ex)
    IF (.NOT. ex) CALL letkf_mpi_abort(&
         "File not found: "//self%filename_obs)

    ! open the file, get size of observations
    CALL check( nf90_open(self%filename_obs, nf90_nowrite, ncid))
    CALL check( nf90_inq_dimid(ncid, "obs", dimid), &
         'Reading dimension "obs"')
    CALL check( nf90_inquire_dimension(ncid, dimid, len=nobs) )

    ! allocate space depending on number of observations
    ALLOCATE(obs(nobs))
    ALLOCATE(tmp_i(nobs))
    ALLOCATE(tmp_r(nobs))

    ! read in the variables
    CALL check( nf90_inq_varid(ncid, "obid", varid), &
         '"obid" in '//self%filename_obs)
    CALL check( nf90_get_var(ncid, varid, tmp_i) )
    DO n=1,nobs
       obs(n)%obsid = tmp_i(n)
    END DO

    CALL check( nf90_inq_varid(ncid, "plat", varid), &
         '"plat" in '//self%filename_obs)
    CALL check( nf90_get_var(ncid, varid, tmp_i) )
    DO n=1,nobs
       obs(n)%platid = tmp_i(n)
    END DO

    CALL check( nf90_inq_varid(ncid, "lat", varid),&
         '"lat" in '//self%filename_obs )
    CALL check( nf90_get_var(ncid, varid, tmp_r) )
    DO n=1,nobs
       obs(n)%lat = tmp_r(n)
    END DO

    CALL check( nf90_inq_varid(ncid, "lon", varid),&
         '"lon" in '//self%filename_obs )
    CALL check( nf90_get_var(ncid, varid, tmp_r) )
    DO n=1,nobs
       obs(n)%lon = tmp_r(n)
    END DO

    CALL check( nf90_inq_varid(ncid, "depth", varid),&
         '"depth" in '//self%filename_obs )
    CALL check( nf90_get_var(ncid, varid, tmp_r) )
    DO n=1,nobs
       obs(n)%zdim = tmp_r(n)
    END DO

    CALL check( nf90_inq_varid(ncid, "hr", varid),&
         '"hr" in '//self%filename_obs )
    CALL check( nf90_get_var(ncid, varid, tmp_r) )
    DO n=1,nobs
       obs(n)%time = tmp_r(n)
    END DO

    CALL check( nf90_inq_varid(ncid, "val", varid), &
         '"val" in '//self%filename_obs )
    CALL check( nf90_get_var(ncid, varid, tmp_r) )
    DO n=1,nobs
       obs(n)%val = tmp_r(n)
    END DO

    CALL check( nf90_inq_varid(ncid, "err", varid),&
         '"err" in '//self%filename_obs )
    CALL check( nf90_get_var(ncid, varid, tmp_r) )
    DO n=1,nobs
       obs(n)%err = tmp_r(n)
    END DO

    CALL check( nf90_inq_varid(ncid, "qc", varid), &
         '"qc" in '//self%filename_obs )
    CALL check( nf90_get_var(ncid, varid, tmp_i) )
    DO n=1,nobs
       obs(n)%qc = tmp_i(n)
    END DO

    ! cleanup
    CALL check( nf90_close(ncid) )
    DEALLOCATE(tmp_i, tmp_r)

  END SUBROUTINE obsio_nc_read_obs
  !================================================================================



  !================================================================================
  !> Read the observation operator output for a single ensemble member.
  !! @param ensmem ensemble member number to load in
  !! @param hx the ensemble member state mapped to observation space
  !--------------------------------------------------------------------------------
  SUBROUTINE obsio_nc_read_hx(self, ensmem, hx)
    CLASS(letkf_obsio_nc) :: self
    INTEGER, INTENT(in) :: ensmem
    REAL, ALLOCATABLE, INTENT(out) :: hx(:)
    REAL, ALLOCATABLE :: val(:)

    LOGICAL :: ex
    INTEGER :: ncid, dimid, varid
    INTEGER :: n, i
    CHARACTER(len=6)  :: pattern
    CHARACTER(len=10) :: fmt
    CHARACTER(len=1024) :: filename

    ! determine the filename to load in.
    ! filename_obs_hx provides the template into which we need to subsitute the
    ! ensemble number in the filename.
    filename = self%filename_obs_hx
    DO n=1,9
       ! we are looking for "#ENSx#" strings, where "x" is the number of digits.
       ! For example, "#ENS4#" in the filename will be replaced with "0001" for
       ! ensemble member number 1.
       WRITE (pattern, "(A,I0,A)") "#ENS",n, "#"
       i = INDEX(self%filename_obs_hx, pattern)

       IF(i > 0) THEN
          WRITE (fmt, '(A,I0,A)') '(A,I0.', n, ',A)'
          WRITE (filename, fmt) self%filename_obs_hx(1:i-1), ensmem, &
               self%filename_obs_hx(i+LEN(pattern):LEN(self%filename_obs_hx))
          EXIT
       END IF
    END DO

    ! make sure the file exists
    INQUIRE(file=filename, exist=ex)
    IF(.NOT. ex) CALL letkf_mpi_abort("observation hx file does not exist: "&
         // TRIM(filename))

    ! load in the data
    CALL check( nf90_open(filename, nf90_nowrite, ncid) )
    CALL check( nf90_inq_dimid(ncid, "obs", dimid), &
         '"obs" in '//self%filename_obs)
    CALL check( nf90_inquire_dimension(ncid, dimid, len=n) )


    ALLOCATE(hx(n))

    IF(self%read_inc) THEN
       ALLOCATE(val(n))
       CALL check( nf90_inq_varid(ncid, "val", varid), &
            '"val" in'//filename )
       CALL check( nf90_get_var(ncid, varid, val) )
       CALL check( nf90_inq_varid(ncid, "inc", varid), &
            '"inc" in'//filename )
       CALL check( nf90_get_var(ncid, varid, hx) )
       hx = hx + val
       DEALLOCATE(val)
    ELSE
       CALL check( nf90_inq_varid(ncid, "hx", varid), &
            '"hx" in'//filename )
       CALL check( nf90_get_var(ncid, varid, hx) )
    END IF

    CALL check( nf90_close(ncid))
  END SUBROUTINE obsio_nc_read_hx
  !================================================================================



  !================================================================================
  !> Helper function to check status of netcdf calls
  !--------------------------------------------------------------------------------
  SUBROUTINE check(status, str)
    INTEGER, INTENT(in) :: status
    CHARACTER(*), OPTIONAL, INTENT(in) :: str

    IF(status /= nf90_noerr) THEN
       IF (PRESENT(str)) THEN
          WRITE (*,*) TRIM(nf90_strerror(status)), ": ",str
       ELSE
          WRITE (*,*) TRIM(nf90_strerror(status))
       END IF
       CALL letkf_mpi_abort("NetCDF error")
    END IF
  END SUBROUTINE check
  !================================================================================


END MODULE letkf_obsio_nc_mod
