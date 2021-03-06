!================================================================================
!> default, simple, horizontal only  localization
!================================================================================
MODULE letkf_loc_novrt_mod
  USE letkf_config
  USE letkf_mpi
  USE letkf_loc
  USE letkf_obs
  USE letkf_state

  IMPLICIT NONE
  PRIVATE



  !================================================================================
  !================================================================================
  ! Public module components
  !================================================================================
  !================================================================================


  !================================================================================
  !> localizer class for simple horizontal only localization
  !--------------------------------------------------------------------------------
  TYPE, EXTENDS(letkf_localizer), PUBLIC :: letkf_loc_novrt
     ! horizontal localization
     TYPE(linearinterp_lat) :: hzdist

   CONTAINS
     PROCEDURE, NOPASS :: name => loc_novrt_name
     PROCEDURE, NOPASS :: desc => loc_novrt_desc
     PROCEDURE         :: init => loc_novrt_init
     PROCEDURE         :: FINAL => loc_novrt_final
     PROCEDURE         :: groups => loc_novrt_groups
     PROCEDURE         :: localize => loc_novrt_localize
     PROCEDURE         :: maxhz => loc_novrt_maxhz
  END TYPE letkf_loc_novrt
  !================================================================================



CONTAINS


  !================================================================================
  !> Get the name of the class
  !--------------------------------------------------------------------------------
  FUNCTION loc_novrt_name() RESULT(str)
    CHARACTER(:), ALLOCATABLE :: str
    str="LOC_NOVRT"
  END FUNCTION loc_novrt_name
  !================================================================================



  !================================================================================
  !> Get the description of the class
  !--------------------------------------------------------------------------------
  FUNCTION loc_novrt_desc() RESULT(str)
    CHARACTER(:), ALLOCATABLE :: str
    str="Generic horizontal only localization"
  END FUNCTION loc_novrt_desc
  !================================================================================



  !================================================================================
  !> Initialize this class, reading in settings from the namelist mostly
  !--------------------------------------------------------------------------------
  SUBROUTINE loc_novrt_init(self, config)
    CLASS(letkf_loc_novrt), INTENT(inout) :: self
    TYPE(configuration), INTENT(in) :: config

    CHARACTER(:), ALLOCATABLE :: str

    IF (pe_isroot) THEN
       PRINT *, ""
       PRINT *, "LOC_NOVRT initialization"
       PRINT *, "------------------------------------------------------------"
    END IF

    CALL config%get("hzloc", str, "0.0 500.0e3 / 90.0 50.0e3")
    self%hzdist = linearinterp_lat(str)
    IF (pe_isroot) PRINT *, "hzloc=",self%hzdist%string()

    self%maxgroups=1

  END SUBROUTINE loc_novrt_init
  !================================================================================


  !================================================================================
  !>
  !--------------------------------------------------------------------------------
  SUBROUTINE loc_novrt_final(self)
    CLASS(letkf_loc_novrt), INTENT(inout) :: self

    ! ... nothing to do here
  END SUBROUTINE loc_novrt_final
  !================================================================================


  !================================================================================
  !> For a given gridpoint, get the desired localization parameters
  !! (horizontal search radius and level/variable localization groups)
  !--------------------------------------------------------------------------------
  SUBROUTINE loc_novrt_groups(self, ij, groups)
    CLASS(letkf_loc_novrt), INTENT(inout) :: self
    INTEGER, INTENT(in)  :: ij
    TYPE(letkf_localizer_group), ALLOCATABLE, INTENT(inout) :: groups(:)

    INTEGER :: i

    ! TODO, need to correctly set the number of slabs
    ALLOCATE(groups(1))
    ALLOCATE(groups(1)%slab(grid_ns))
    DO i=1, grid_ns
       groups(1)%slab(i) = i
    END DO

  END SUBROUTINE loc_novrt_groups
  !================================================================================



  !================================================================================
  !>
  !--------------------------------------------------------------------------------
  FUNCTION loc_novrt_maxhz(self, ij) RESULT(dist)
    CLASS(letkf_loc_novrt), INTENT(inout) :: self
    INTEGER, INTENT(in)  :: ij
    REAL :: dist

    dist = self%hzdist%get_dist(lat_ij(ij))
  END FUNCTION loc_novrt_maxhz
  !================================================================================




  !================================================================================
  !>
  !--------------------------------------------------------------------------------
  FUNCTION loc_novrt_localize(self, ij, group, obs, dist) RESULT(loc)
    CLASS(letkf_loc_novrt), INTENT(inout) :: self
    INTEGER, INTENT(in) :: ij
    TYPE(letkf_localizer_group), INTENT(in) :: group
    TYPE(letkf_observation), INTENT(in) :: obs
    REAL, INTENT(in) :: dist
    REAL :: loc, r

    ! TODO temporal localization

    ! horizontal localization
    loc = letkf_loc_gc(dist, self%hzdist%get_dist(lat_ij(ij)))

  END FUNCTION loc_novrt_localize
  !================================================================================


END MODULE letkf_loc_novrt_mod
