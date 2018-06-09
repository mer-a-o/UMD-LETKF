MODULE letkf
  USE letkf_loc
  USE letkf_loc_novrt
  USE letkf_mpi
  USE letkf_obs
  USE letkf_obs_nc
  USE letkf_obs_test
  USE letkf_solver
  USE letkf_state
  USE letkf_state_nc
  USE timing
  USE getmem
  USE netcdf

  IMPLICIT NONE
  PRIVATE



  ! Public methods
  !--------------------------------------------------------------------------------
  PUBLIC :: letkf_init
  PUBLIC :: letkf_run
  PUBLIC :: letkf_register_hook


  ! private variables
  CHARACTER(:), ALLOCATABLE :: nml_filename

  ! use this to get the repository version at compile time
#ifndef CVERSION
#define CVERSION "Unknown"
#endif



CONTAINS



  !-----------------------------------------------------------------------------------------
  !> Initialize the LETKF library.
  !! This needs to be done before any other user-called functions are performed
  SUBROUTINE letkf_init(nml)
    character(len=*) :: nml

    ! temprary pointers for initializing and registering the default classes
    CLASS(letkf_obsio),     POINTER :: obsio_ptr
    CLASS(letkf_stateio),   POINTER :: stateio_ptr
    CLASS(letkf_localizer), POINTER :: localizer_ptr

    nml_filename=nml

    ! initialize the mpi backend
    CALL letkf_mpi_preinit()

    CALL getmem_init(pe_root, letkf_mpi_comm)

    ! initialize global timers
    CALL timing_init(letkf_mpi_comm, 0)
    CALL timing_start("pre-init")


    ! print out the welcome screen
    IF (pe_isroot) THEN
       PRINT *, "=========================================================================================="
       PRINT *, "=========================================================================================="
       PRINT *, "Universal Multi-Domain Local Ensemble Transform Kalman Filter"
       PRINT *, " (UMD-LETKF)"
       print *, " version:  ", CVERSION
       PRINT *, "=========================================================================================="
       PRINT *, "=========================================================================================="
    END IF


    if (pe_isroot) then
       print *, "Using namelist: "//trim(nml_filename)
       print *, ""
       end if

    ! initialize the rest of MPI
    ! (determines the processor distribution for I/O)
    ! TODO

    ! setup the default observation I/O classes
    ALLOCATE(obsio_nc :: obsio_ptr)
    CALL letkf_obs_register(obsio_ptr)
    ALLOCATE(obsio_test :: obsio_ptr)
    CALL letkf_obs_register(obsio_ptr)

    ! setup the default state I/O classes
    ALLOCATE(stateio_nc :: stateio_ptr)
    CALL letkf_state_register(stateio_ptr)

    ! setup the default localizer classes
    ALLOCATE(loc_novrt :: localizer_ptr)
    CALL letkf_loc_register(localizer_ptr)

    CALL timing_stop("pre-init")

  END SUBROUTINE letkf_init



  !-----------------------------------------------------------------------------------------

  !> Does all the fun stuff of actually running the LETKF
  SUBROUTINE letkf_run()

    ! LETKF initialization
    ! module initialization order is somewhat important
    ! "obs" must be initialized before "state" because, in the case of the test obs
    ! reader, the "obs" module might create hooks to get information from the state
    ! before "obs_read" is called.
    CALL timing_start("init", TIMER_SYNC)
    CALL letkf_mpi_init(nml_filename)
    CALL letkf_state_init(nml_filename)
    CALL letkf_obs_init(nml_filename)
    CALL letkf_obs_read()
    CALL letkf_loc_init(nml_filename)
    call letkf_solver_init(nml_filename)
    CALL timing_stop("init")

    ! run the LETKF solver
    CALL letkf_solver_run()
    CALL letkf_mpi_barrier()


    ! LETKF final output
    ! ------------------------------------------------------------
    CALL timing_start("output", TIMER_SYNC)
    IF(pe_isroot) THEN
       PRINT *, ""
       PRINT *, "Saving output..."
    END IF

    ! miscellaneous diagnostics from the LETKF solver
    CALL letkf_write_diag()

    ! ensemble mean, spread
    call letkf_state_write_meansprd("ana")

    ! save ensemble members
    call letkf_state_write_ens()

    CALL timing_stop("output")



    ! all done
    call letkf_mpi_barrier()
    CALL timing_print()
    CALL getmem_print()
    CALL letkf_mpi_final()

  END SUBROUTINE letkf_run



  !< Register a callback function for one of the hooks where
  !! users can implement custom functionality
  !! @TODO implement this
  SUBROUTINE letkf_register_hook
    PRINT *, "NOT yet implemented (letkf_register_hook)"
    STOP 1
  END SUBROUTINE letkf_register_hook



  SUBROUTINE letkf_write_diag()
    INTEGER :: p
    REAL, ALLOCATABLE :: tmp_2d_real(:,:)
    INTEGER :: ncid, d_t, d_x, d_y, vid
    CALL timing_start("diag_write")

    p=letkf_mpi_nextio()
    ALLOCATE(tmp_2d_real(grid_nx, grid_ny))

    IF(pe_rank == p) THEN
       CALL check(nf90_create("letkf.diag.nc", nf90_hdf5, ncid))
       CALL check(nf90_def_dim(ncid, "time", 1, d_t))
       CALL check(nf90_def_dim(ncid, "lon", grid_nx, d_x))
       CALL check(nf90_def_dim(ncid, "lat", grid_ny ,d_y))
       CALL check(nf90_def_var(ncid, "maxhz_loc", nf90_real, &
            (/d_x, d_y/), vid))
       CALL check(nf90_def_var(ncid, "obs_count", nf90_real, &
            (/d_x, d_y/), vid))
       CALL check(nf90_def_var(ncid, "obs_count_loc", nf90_real, &
            (/d_x, d_y/), vid))
       CALL check(nf90_enddef(ncid))
    END IF

    CALL letkf_mpi_ij2grd(p,diag_maxhz, tmp_2d_real)
    IF(pe_rank == p) then
       call check(nf90_inq_varid(ncid, "maxhz_loc", vid))
       CALL check(nf90_put_var(ncid, vid, tmp_2d_real))
    end if

    CALL letkf_mpi_ij2grd(p,diag_obs_cnt, tmp_2d_real)
    IF(pe_rank == p) then
       call check(nf90_inq_varid(ncid, "obs_count", vid))
       CALL check(nf90_put_var(ncid, vid, tmp_2d_real))
    end if

    CALL letkf_mpi_ij2grd(p,diag_obs_cnt_loc, tmp_2d_real)
    IF(pe_rank == p) then
       call check(nf90_inq_varid(ncid, "obs_count_loc", vid))
       CALL check(nf90_put_var(ncid, vid, tmp_2d_real))
    end if

    IF(pe_rank == p) CALL check(nf90_close(ncid))

    CALL timing_stop("diag_write")

  CONTAINS

    SUBROUTINE check(status, str)
      INTEGER, INTENT(in) :: status
      CHARACTER(*), OPTIONAL, INTENT(in) :: str

      IF(status /= nf90_noerr) THEN
         IF(PRESENT(str)) THEN
            WRITE (*,*) TRIM(nf90_strerror(status)), ": ", str
         ELSE
            WRITE (*,*) TRIM(nf90_strerror(status))
         END IF
         CALL letkf_mpi_abort("NetCDF error")
      END IF
    END SUBROUTINE check
  END SUBROUTINE letkf_write_diag

END MODULE letkf