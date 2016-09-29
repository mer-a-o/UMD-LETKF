module letkf_obs
  use letkf_mpi
  use timing
  use global
  use kdtree
  
  implicit none
  private

  ! public subroutines
  public :: letkf_obs_init, letkf_obs_read

  ! observation and obsio class
  public :: observation
  public :: obsio, I_obsio_write, I_obsio_read

  ! observation definitions
  public :: obsdef, obsdef_list
  public :: obsdef_read,  obsdef_getbyname,  obsdef_getbyid

  !platform definitions
  public :: platdef, platdef_list
  public :: platdef_read, platdef_getbyname, platdef_getbyid
 

  !------------------------------------------------------------
  

  
  type observation
     !! information for a single observation
     integer :: id = -1
     !! observation type id, as specified in the `obsdef` configuration file.
     !! A value of -1 indicates no observation data has been read in.
     integer :: plat
     !! Platform type id, as specified in the `platdef` configuration file.
     real(dp) :: lat
     !! Latitude (degrees)
     real(dp) :: lon
     !! Longitude (degrees)
     real(dp) :: depth
     !! Depth, in whatever units is appropriate for the domain.
     !! If this is a 2D observation, this value is ignored.
     real(dp) :: time
     !! Time (hours) from base time
     real(dp) :: val
     !! Observation value
     real(dp) :: err
     !! standard deviation of observation error
!     integer :: qc
     !! Quality control flag. ( 0 = no errors, > 0 removed by obs op, < 0
     !! removed by LETKF qc
  end type observation

  
  
  type obsdef
     !! The specification for a single user-defined observation type
     integer :: id
     !! unique identifier
     character(len=:), allocatable :: name_short
     !! short (3-4 characters) name of observation type
     character(len=:), allocatable :: name_long
     !! longer more descriptive name
     character(len=:), allocatable :: units
   contains
     procedure :: print => obsdef_print
  end type obsdef


  

  type platdef
     !!specification for a single user-defined observation platform type
     integer :: id
     !! unique id for the platform type
     character(len=:), allocatable :: name_short
     !! short (3-4 character) name of platform type
     character(len=:), allocatable :: name_long
     !! longer more descriptive name of platform type
   contains
     procedure :: print => platdef_print     
  end type platdef

  

  type, abstract :: obsio
     !! Abstract base class for observation file reading and writing.
     !! All user-defined, and built-in, obs file I/O modules for
     !! specific file types should be built from a class extending this
   contains
     procedure(I_obsio_write), deferred :: write
     !! write a list of observatiosn to the given file     
     procedure(I_obsio_read),  deferred :: read
     !! read a list of observatiosn from the given file
  end type obsio
  
  abstract interface
     subroutine I_obsio_write(self, file, obs, iostat)
       !! interface for procedures to write observation data
       import obsio
       import observation
       class(obsio) :: self
       character(len=*), intent(in)   :: file
       !! filename to write observations to
       type(observation), intent(in) :: obs(:)
       !! list of 1 or more observatiosn to write
       integer, optional, intent(out) :: iostat
     end subroutine I_obsio_write

     subroutine I_obsio_read(self, file, obs, obs_innov, obs_qc, iostat)
       !! interface for procedures to load observation data
       import observation
       import obsio
       import dp
       class(obsio) :: self
       character(len=*), intent(in) :: file
       
       type(observation),allocatable, intent(out) :: obs(:)
       real(dp), allocatable, intent(out) :: obs_innov(:)
       integer,  allocatable, intent(out) :: obs_qc(:)
       
       integer, optional, intent(out) :: iostat
     end subroutine I_obsio_read
  end interface


  !------------------------------------------------------------
  type(obsdef),  allocatable ::  obsdef_list(:)
  type(platdef), allocatable :: platdef_list(:)

  type(kd_root)                  :: obs_tree
  type(observation), allocatable :: obs_list(:)
  integer, allocatable           :: obs_qc(:)
  real(dp), allocatable          :: obs_ohx(:,:)
  real(dp), allocatable          :: obs_ohx_mean(:)
  
  !------------------------------------------------------------

  
contains


  ! ============================================================
  ! ============================================================    
  subroutine letkf_obs_init(obsdef_file, platdef_file)
    character(len=*), optional, intent(in) :: obsdef_file
    !! observation definition file to read in. By default `letkf.obsdef`
    !! will be used.
    character(len=*), optional, intent(in) :: platdef_file
    !! observation platform definition file to read in. By default
    !! `letkf.platdef` will be used.

    if (pe_isroot) then
       print *, ''
       print *, 'LETKF observation configuration files'
       print *, '------------------------------------------------------------'
       print *, '  observation definition file: "', trim(obsdef_file),'"'
       print *, '  platform    definition file: "', trim(platdef_file),'"'
       print *, '  I/O format: ???'
       print *, ''       
    end if
    
    call obsdef_read(obsdef_file)
    call platdef_read(platdef_file)
    
  end subroutine letkf_obs_init



  ! ============================================================
  ! ============================================================    
  subroutine letkf_obs_read(reader)
    class(obsio), intent(in) :: reader    

    integer :: ierr
    integer :: i, j
    integer :: timer, timer2, timer3, timer4

    character(len=1024) :: filename    
    
    integer, allocatable :: obs_qc_l(:,:)

    type(observation), allocatable :: obs_t(:)
    real(dp), allocatable :: obs_ohx_t(:)
    integer, allocatable :: obs_qc_t(:)

    integer, allocatable :: obstat_count(:,:)
    integer, allocatable :: obplat_count(:,:)

    real(dp), allocatable :: obs_lons(:), obs_lats(:)
    integer :: cnt

    timer  = timer_init("obs read", TIMER_SYNC)
    timer2 = timer_init("obs read I/O")
    timer3 = timer_init("obs read MPI", timer_sync)
    timer4 = timer_init("obs kd_init")
    
    call timer_start(timer)

    if (pe_isroot) then
       print *, ""
       print *, "Reading Observations"
       print *, "============================================================"
    end if

    ! parallel read of the observation innovation files for each ensemble member
    do i=1,size(ens_list)
       write (filename, '(A,I0.3,A)') 'data/obsop/2005070300_atm',ens_list(i),'.dat'

       ! read the file
       !TODO, not the most efficient, general observation information is not
       ! needed with every single ensemble member, this should be in a separate
       ! file, with each ens member file only containing the obs space value and qc
       call timer_start(timer2)       
       call reader%read(filename, obs_t, obs_ohx_t, obs_qc_t)
       call timer_stop(timer2)

       ! create the obs storage if it hasn't already been done
       if (.not. allocated(obs_list)) then
          allocate(obs_list(size(obs_t)))
          obs_list = obs_t
          allocate(obs_ohx( mem, size(obs_ohx_t)))
          allocate(obs_ohx_mean( size(obs_ohx_t)))          
          allocate(obs_qc_l( mem, size(obs_qc_t)))
       end if

       ! copy the per ensemble member innovation and qc
       obs_ohx(ens_list(i), :) = obs_ohx_t(:)
       obs_qc_l (ens_list(i), :) = obs_qc_t(:)

       !cleanup
       deallocate(obs_t)
       deallocate(obs_ohx_t)
       deallocate(obs_qc_t)
    end do

    
    ! distribute the qc and innovation values
    ! TODO, using MPI_SUM is likely inefficient, do this another way
    call timer_start(timer3)    
    call mpi_allreduce(mpi_in_place, obs_ohx, mem*size(obs_list), mpi_real8, mpi_sum, mpi_comm_letkf, ierr)
    call mpi_allreduce(mpi_in_place, obs_qc_l , mem*size(obs_list), mpi_integer, mpi_sum, mpi_comm_letkf, ierr)
    call timer_stop(timer3)


    ! calculate the combined QC
    allocate(obs_qc(size(obs_list)))
    do i=1,size(obs_list)
       obs_qc(i) = sum(obs_qc_l(:,i))
    end do
    deallocate(obs_qc_l)

    ! calculate ohx perturbations
    do i=1,size(obs_list)
       obs_ohx_mean(i) = sum(obs_ohx(:,i))/mem
       obs_ohx(:,i) = obs_ohx(:,i) - obs_ohx_mean(i)
    end do

    !TODO basic QC checks on the observations
    ! TODO: check stddev of ohx, problems if == 0 (odds of this happening though?)
    do i=1,size(obs_list)
       if (obs_qc(i) == 0) then
          if( abs(obs_ohx_mean(i)-obs_list(i)%val)/obs_list(i)%err  > obsqc_maxstd) then
             obs_qc(i) = -1
          end if
       end if
    end do

    !TODO: keep track of invalid obs or plat IDs
    !TODO: set qc < 0 for invalid obs or plat IDs
    
    ! add locations to the kd-tree
    ! TODO: dont add obs to the tree that have a bad QC value
    allocate(obs_lons(size(obs_list)))
    allocate(obs_lats(size(obs_list)))
    call timer_start(timer4)
    call kd_init(obs_tree, obs_lons, obs_lats)
    call timer_stop(timer4)
    deallocate(obs_lons)
    deallocate(obs_lats)
    
    ! print statistics about the observations
    if (pe_isroot) then
       print '(I11,A)', size(obs_list), " observations loaded"

       allocate(obstat_count (size(obsdef_list)+1,  4))
       allocate(obplat_count (size(platdef_list)+1, 4))
       
       obstat_count = 0
       obplat_count = 0

       ! count
       do i=1,size(obs_list)
          if (obs_qc(i) == 0) then
             cnt = 2
          else if (obs_qc(i) > 0) then
             cnt = 3
          else
             cnt = 4
          end if

          ! if (obs_list(i)%id == 1220 .and. obs_qc(i) < 0) then
          !    print *, obs_qc(i)
          !    print *, obs_ohx_mean(i)
          !    print *, obs_list(i)
          !    print *, obs_ohx(:,i)
          !    print *,""
          ! end if
          
          ! count by obs type
          do j=1,size(obsdef_list)
             if (obs_list(i)%id == obsdef_list(j)%id) then
                obstat_count(j,1) = obstat_count(j,1) + 1
                obstat_count(j,cnt) = obstat_count(j,cnt) + 1
                exit
             end if
          end do
          if (j > size(obsdef_list)) &
               obstat_count(size(obsdef_list)+1,1) = obstat_count(size(obsdef_list)+1,1) + 1

          ! count by plat type
          do j=1,size(platdef_list)
             if (obs_list(i)%plat == platdef_list(j)%id) then
                obplat_count(j,1) = obplat_count(j,1) + 1
                obplat_count(j,cnt) = obplat_count(j,cnt) + 1
                exit
             end if
          end do
          if (j > size(platdef_list)) &
               obplat_count(size(platdef_list)+1,1) = obplat_count(size(platdef_list)+1,1) + 1
       end do

       ! print for counts by obs type
       print *, ""
       print '(4A10,A12)', '','total','bad-obop','bad-qc','good'
       print *, '         --------------------------------------------'       
       do i=1,size(obstat_count,1)
          if (obstat_count(i,1) == 0) cycle
          if (i < size(obstat_count,1)) then
             print '(A10,I10, 2I10, I10,A2,F5.1,A)',&
                  obsdef_list(i)%name_short, obstat_count(i,1), &
                  obstat_count(i,3), obstat_count(i,4), &
                  obstat_count(i,2), '(',real(obstat_count(i,2))/obstat_count(i,1)*100, ')%'
          else
             print '(A10,I10,3A10,A)', 'unknown', obstat_count(i,1),'X','X','0',' (  0.0)%'
             
          end if
       end do

       ! print stats for counts by plat type
       print *, ""
       print '(4A10,A12)', '','total','bad-obop','bad-qc','good'
       print *, '         --------------------------------------------'       
       do i=1,size(obplat_count,1)
          if (obplat_count(i,1) == 0) cycle
          if (i < size(obplat_count,1)) then
             print '(A10,I10, 2I10, I10,A2,F5.1,A)',&
                  platdef_list(i)%name_short, obplat_count(i,1), &
                  obplat_count(i,3), obplat_count(i,4),&                  
                  obplat_count(i,2), '(',real(obplat_count(i,2))/obplat_count(i,1)*100, ')%'

          else
             print '(A10,I10,3A10,A)', 'unknown', obplat_count(i,1),'X','X','0',' (  0.0)%'
          end if
       end do
       
       !cleanup
       deallocate(obstat_count)
       deallocate(obplat_count)
    end if
    

    call timer_stop(timer)
  end subroutine letkf_obs_read


  
  ! ============================================================
  ! ============================================================    
  subroutine obsdef_read(file)    
    character(len=*), intent(in) :: file

    integer :: unit, pos, iostat
    character(len=1024) :: line, s_tmp
    logical :: ex
    type(obsdef) :: new_ob
    integer, parameter :: MAX_OBSDEF = 1024
    type(obsdef) :: obsdef_list_tmp(MAX_OBSDEF)
    integer :: obsdef_list_tmp_len
    integer :: i,j

    if (pe_isroot) then
       print *, ''       
       print *, ""
       print *, "Observation Definition File"
       print *, "------------------------------------------------------------"
       print *, 'Reading file "',trim(file),'" ...'
    end if

    ! make sure the file exists
    inquire(file=file, exist=ex)
    if (.not. ex) then
       print *, 'ERROR: file does not exists: "',trim(file),'"'
       stop 1
    end if

    obsdef_list_tmp_len = 0
    
    ! open it up for reading
    open(newunit=unit, file=file, action='read')
    do while (1==1)
       ! read a new line
       read(unit, '(A)', iostat=iostat) line
       if (iostat < 0) exit
       if (iostat > 0) then
          print *, 'ERROR: there was a problem reading "', &
            trim(file), '" error code: ', iostat
            stop 1
       end if

       ! convert tabs to spaces
       do i = 1, len(line)
          if (line(i:i) == char(9)) line(i:i) = ' '
       end do
       
       ! ignore comments
       s_tmp = adjustl(line)
       if (s_tmp(1:1) == '#') cycle

       ! ignore empty lines
       if (len(trim(adjustl(line))) == 0) cycle

       ! read ID
       line = adjustl(line)
       pos = findspace(line)
       read(line(1:pos), *) new_ob%id

       ! read short name
       line = adjustl(line(pos+1:))
       pos = findspace(line)
       new_ob%name_short = toupper(trim(line(:pos-1)))

       ! read units
       line = adjustl(line(pos+1:))
       pos = findspace(line)
       new_ob%units = trim(line(:pos-1))

       ! read long name
       line = adjustl(line(pos+1:))
       new_ob%name_long = trim(line)

       ! add this one to the list
       obsdef_list_tmp_len = obsdef_list_tmp_len + 1
       if (obsdef_list_tmp_len > MAX_OBSDEF) then
          print *, 'ERROR, there are more observation definitions ',&
               'than there is room for. Check the "',trim(file),&
               '" file, and/or increase MAX_OBSDEF.'
          print *, 'MAX_OBSDEF = ',MAX_OBSDEF
          stop 1
       end if
       obsdef_list_tmp(obsdef_list_tmp_len) = new_ob         
    end do
    
    close (unit)
    allocate(obsdef_list(obsdef_list_tmp_len))
    obsdef_list = obsdef_list_tmp(1:obsdef_list_tmp_len)

    ! write summary
    if (pe_isroot) then
       print *, 'obs defined = ', size(obsdef_list)
       print "(A6,A10,A10,A5,A)", "ID", "NAME", "UNITS", "","FULL NAME"
       do pos=1, size(obsdef_list)
          call obsdef_list(pos)%print()
       end do
    end if

    ! check for duplicate ID / short name
    if (pe_isroot) then
       i = 1
       do while(i < size(obsdef_list))
          j = i + 1
          do while(j <= size(obsdef_list))
             if ( obsdef_list(i)%id == obsdef_list(j)%id) then
                print *, "ERROR: multiple definitions for ID = ",&
                     obsdef_list(j)%id
                stop 1
             else if( obsdef_list(i)%name_short==obsdef_list(j)%name_short) then
                print *, "ERROR: multiple definitions for NAME = ",&
                     obsdef_list(j)%name_short
                stop 1
             end if
             j = j + 1
          end do
          i = i + 1
       end do
    end if

    ! all done
    if (pe_isroot)    print *, ""
  end subroutine obsdef_read



  
  ! ============================================================
  ! ============================================================    
  subroutine platdef_read(file)
    character(len=*), intent(in) :: file
    integer :: unit, pos, iostat
    character(len=1024) :: line, s_tmp
    logical :: ex
    type(platdef) :: new_plat
    integer, parameter :: MAX_PLATDEF = 1024
    type(platdef) :: platdef_list_tmp(MAX_PLATDEF)
    integer :: platdef_list_tmp_len
    integer :: i,j

    if (pe_isroot) then
       print *, ''       
       print *, ""
       print *, "Platform Definition File"
       print *, "------------------------------------------------------------"
       print *, 'Reading file "',trim(file),'" ...'       
    end if

    ! make sure the file exists
    inquire(file=file, exist=ex)
    if (.not. ex) then
       print *, 'ERROR: file does not exists: "',trim(file),'"'
       stop 1
    end if

    platdef_list_tmp_len = 0
    
    ! open it up for reading
    open(newunit=unit, file=file, action='read')
    do while (1==1)
       ! read a new line
       read(unit, '(A)', iostat=iostat) line
       if (iostat < 0) exit
       if (iostat > 0) then
          print *, 'ERROR: there was a problem reading "', &
            trim(file), '" error code: ', iostat
            stop 1
       end if

       ! convert tabs to spaces
       do i = 1, len(line)
          if (line(i:i) == char(9)) line(i:i) = ' '
       end do       
       
       ! ignore comments
       s_tmp = adjustl(line)
       if (s_tmp(1:1) == '#') cycle

       ! ignore empty lines
       if (len(trim(adjustl(line))) == 0) cycle
          
       ! read ID
       line = adjustl(line)
       pos = findspace(line)
       read(line(1:pos), *) new_plat%id

       ! read short name
       line = adjustl(line(pos+1:))
       pos = findspace(line)
       new_plat%name_short = toupper(trim(line(:pos-1)))

       ! read long name
       line = adjustl(line(pos+1:))
       new_plat%name_long = trim(line)

       ! add this one to the list
       platdef_list_tmp_len = platdef_list_tmp_len + 1
       if (platdef_list_tmp_len > MAX_PLATDEF) then
          print *, 'ERROR, there are more platform definitions ',&
               'than there is room for. Check the "',trim(file),&
               '" file, and/or increase MAX_PLATDEF.'
          print *, 'MAX_PLATDEF = ',MAX_PLATDEF
          stop 1
       end if
       platdef_list_tmp(platdef_list_tmp_len) = new_plat
    end do
    
    close (unit)
    allocate(platdef_list(platdef_list_tmp_len))
    platdef_list = platdef_list_tmp(1:platdef_list_tmp_len)

    ! write summary
    if (pe_isroot) then
       print *, 'platforms defined = ', size(platdef_list)
       print "(A6,A10,A5,A)", "ID", "NAME", "","DESCRIPTION"
       do pos=1, size(platdef_list)
          call platdef_list(pos)%print()
       end do
    end if

    ! check for duplicate ID / short name
    if (pe_isroot) then
       i = 1
       do while(i < size(platdef_list))
          j = i + 1
          do while(j <= size(platdef_list))
             if ( platdef_list(i)%id == platdef_list(j)%id) then
                print *, "ERROR: multiple definitions for ID = ",&
                     platdef_list(j)%id
                stop 1
             else if( platdef_list(i)%name_short==platdef_list(j)%name_short) then
                print *, "ERROR: multiple definitions for NAME = ",&
                     platdef_list(j)%name_short
                stop 1
             end if
             j = j + 1
          end do
          i = i + 1
       end do
    end if
    
    ! all done
    if (pe_isroot)    print *, ""    
  end subroutine platdef_read



  ! ============================================================
  ! ============================================================  
  function obsdef_getbyid(id) result(res)
    !! returns information about an observation type given its id number.
    !! An error is thrown if the id is not found
    !! @warning this has not been implemented    
    integer, intent(in) :: id
    type(obsdef) :: res

    integer :: i
  end function obsdef_getbyid

  

  ! ============================================================
  ! ============================================================    
  function obsdef_getbyname(name) result(res)
    !! @warning this has not been implemented    
    character(len=*), intent(in) :: name
    type(obsdef) :: res

    integer :: i
  end function obsdef_getbyname



  ! ============================================================
  ! ============================================================    
  function platdef_getbyid(id) result(res)
    !! @warning this has not been implemented    
    integer, intent(in) :: id
    type(platdef) :: res

    integer :: i
  end function platdef_getbyid



  ! ============================================================
  ! ============================================================    
  function platdef_getbyname(name) result(res)
    !! @warning this has not been implemented
    
    character(len=*), intent(in) :: name
    type(platdef) :: res

    integer :: i
  end function platdef_getbyname

  

  ! ============================================================
  ! ============================================================  
  subroutine obsdef_print(ob)
    class(obsdef), intent(in) :: ob
    print "(I6,A10,A10,A5,A)", ob%id, ob%name_short, &
         ob%units, " ", ob%name_long
  end subroutine obsdef_print



  ! ============================================================
  ! ============================================================    
  subroutine platdef_print(plat)
    class(platdef), intent(in) :: plat
    print "(I6,A10,A5,A)", plat%id, plat%name_short, &
         "", plat%name_long
  end subroutine platdef_print


  ! ============================================================
  ! ============================================================    
  function tolower(in_str) result(out_str)
    character(*), intent(in) :: in_str
    character(len(in_str)) :: out_str
    integer :: i,n
    integer, parameter :: offset = 32
    out_str = in_str

    do i = 1, len(out_str)
       if (out_str(i:i) >= "A" .and. out_str(i:i) <= "Z") then
          out_str(i:i) = achar(iachar(out_str(i:i)) + offset)
       end if
    end do
  end function tolower


  
  ! ============================================================
  ! ============================================================    
  function toupper(in_str) result(out_str)
    character(*), intent(in) :: in_str
    character(len(in_str)) :: out_str
    integer :: i,n
    integer, parameter :: offset = 32
    out_str = in_str

    do i = 1, len(out_str)
       if (out_str(i:i) >= "a" .and. out_str(i:i) <= "z") then
          out_str(i:i) = achar(iachar(out_str(i:i)) - offset)
       end if
    end do
  end function toupper



  ! ============================================================
  ! ============================================================    
  function findspace(string)
    integer :: findspace
    character(len=*), intent(in) :: string
    integer :: i, start = 1

    i = start
    do while(string(i:i) /= ' ' .and. i < len(string))
       i = i + 1
    end do
    if (i >= len(string)) i = -1
    findspace = i    
  end function findspace

end module letkf_obs
