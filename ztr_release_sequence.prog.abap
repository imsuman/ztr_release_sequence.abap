*&---------------------------------------------------------------------*
*& Report ZTR_RELEASE_SEQUENCE
*&---------------------------------------------------------------------*
*& Recommends the order in which selected transport requests should be
*& released to the next system, shown as ALV.
*&
*& Basis of the recommendation
*& - A release exports the CURRENT state of each object (including other
*&   developers' unreleased changes). Releasing in change order keeps the
*&   target consistent; the last release carries the final state.
*& - "Older/newer": VRSD only holds versions of already released tasks, so
*&   for open requests the E070 change date/time (request + tasks) is
*&   normally the basis. It is a proxy: treat the result as a recommendation.
*& - "New" object = R3TR object that is in no released request (assumed not
*&   yet in the target system). Parts (LIMU) are never treated as new.
*& - Hard edge  = breaking the order breaks the target (new used object).
*&   Soft edge  = consistency preference (shared object, same custom. key).
*&   On a cycle soft edges are dropped first; only a hard cycle is flagged.
*& - Objects live in the TASKS of a modifiable request; analysis therefore
*&   runs on request + all its tasks.
*& - Inactive objects: DWINACTIV (any user) is checked per object name.
*& - Import status (optional, RFC destination of the target system): a
*&   request counts as imported when its number exists in E070 of the
*&   target (RFC_READ_TABLE). Needs S_RFC and S_TABU_DIS on the target.
*&   Without a destination the check is skipped.
*& - Suppliers outside the selection: used custom objects (Z*/Y*//ns/) that are
*&   not in a selected request are looked up in E071/E070. In an open request:
*&   add it to the release. In a released request: import status via the
*&   RFC destination, else only recent releases are reported. In no request:
*&   $TMP is an error; "forgotten" needs the RFC destination (TADIR in target).
*& - Released requests: "Rel.seq" = order in which they were released (release
*&   date/time). With the RFC destination, released requests that are NOT yet
*&   imported also get "Imp.seq" = recommended import order (dependencies).
*& - Direct reads of E07*/VRSD/WBCROSSGT: on-premise utility, not ABAP Cloud.
*&---------------------------------------------------------------------*
REPORT ztr_release_sequence.

TYPES:
  ty_trkorr_set TYPE SORTED TABLE OF trkorr WITH UNIQUE KEY table_line,
  ty_range      TYPE RANGE OF trkorr,
  ty_names      TYPE STANDARD TABLE OF string WITH EMPTY KEY,
  ty_name_set   TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.

TYPES:
  BEGIN OF ty_header,
    trkorr     TYPE e070-trkorr,
    strkorr    TYPE e070-strkorr,
    trfunction TYPE e070-trfunction,
    trstatus   TYPE e070-trstatus,
    tarsystem  TYPE e070-tarsystem,
    as4user    TYPE e070-as4user,
    as4date    TYPE e070-as4date,
    as4time    TYPE e070-as4time,
    text       TYPE e07t-as4text,
    request    TYPE trkorr,
    stamp      TYPE timestamp,
  END OF ty_header,
  ty_headers TYPE SORTED TABLE OF ty_header WITH UNIQUE KEY trkorr.

TYPES:
  BEGIN OF ty_object,
    request       TYPE trkorr,
    task          TYPE trkorr,
    pgmid         TYPE e071-pgmid,
    object        TYPE e071-object,
    obj_name      TYPE e071-obj_name,
    objfunc       TYPE e071-objfunc,
    parent_object TYPE e071-object,
    parent_name   TYPE e071-obj_name,
    devclass      TYPE tadir-devclass,
    stamp         TYPE timestamp,
    is_new        TYPE abap_bool,
  END OF ty_object,
  ty_objects TYPE STANDARD TABLE OF ty_object WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_key,
    request TYPE trkorr,
    tabname TYPE e071k-objname,
    tabkey  TYPE e071k-tabkey,
    stamp   TYPE timestamp,
  END OF ty_key,
  ty_keys TYPE SORTED TABLE OF ty_key WITH NON-UNIQUE KEY tabname.

TYPES:
  BEGIN OF ty_ref,
    request     TYPE trkorr,
    user_object TYPE string,
    used_name   TYPE string,
  END OF ty_ref,
  ty_refs TYPE STANDARD TABLE OF ty_ref WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_member,
    request TYPE trkorr,
    name    TYPE string,
  END OF ty_member,
  ty_members TYPE STANDARD TABLE OF ty_member WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_foreign,
    pgmid    TYPE e071-pgmid,
    object   TYPE e071-object,
    obj_name TYPE e071-obj_name,
    request  TYPE trkorr,
    owner    TYPE e070-as4user,
  END OF ty_foreign,
  ty_foreigns TYPE STANDARD TABLE OF ty_foreign WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_inactive,
    object   TYPE dwinactiv-object,
    obj_name TYPE dwinactiv-obj_name,
    uname    TYPE dwinactiv-uname,
  END OF ty_inactive,
  ty_inactives TYPE STANDARD TABLE OF ty_inactive WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_hist,
    pgmid    TYPE e071-pgmid,
    object   TYPE e071-object,
    obj_name TYPE e071-obj_name,
    request  TYPE trkorr,
  END OF ty_hist,
  ty_hists TYPE STANDARD TABLE OF ty_hist WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_supplier,
    name    TYPE string,
    request TYPE trkorr,
    status  TYPE e070-trstatus,
    owner   TYPE e070-as4user,
    changed TYPE e070-as4date,
  END OF ty_supplier,
  ty_suppliers TYPE STANDARD TABLE OF ty_supplier WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_local,
    name     TYPE string,
    devclass TYPE tadir-devclass,
  END OF ty_local,
  ty_locals TYPE STANDARD TABLE OF ty_local WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_import,
    request TYPE trkorr,
    state   TYPE c LENGTH 1,   " I imported, N not imported, U unknown
  END OF ty_import,
  ty_imports TYPE SORTED TABLE OF ty_import WITH UNIQUE KEY request.

TYPES:
  BEGIN OF ty_map,
    task    TYPE trkorr,
    request TYPE trkorr,
  END OF ty_map,
  ty_maps TYPE STANDARD TABLE OF ty_map WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_data,
    headers   TYPE ty_headers,
    selected  TYPE ty_trkorr_set,
    task_map  TYPE ty_maps,
    not_found TYPE ty_names,
    objects   TYPE ty_objects,
    keys      TYPE ty_keys,
    refs      TYPE ty_refs,
    members   TYPE ty_members,
    foreign   TYPE ty_foreigns,
    notes     TYPE ty_names,
    inactive  TYPE ty_inactives,
    hist      TYPE ty_hists,
    imports   TYPE ty_imports,
    suppliers TYPE ty_suppliers,
    locals    TYPE ty_locals,
    existing  TYPE ty_name_set,
    checked   TYPE abap_bool,
  END OF ty_data.

TYPES:
  BEGIN OF ty_finding,
    request  TYPE trkorr,
    severity TYPE c LENGTH 1,
    code     TYPE c LENGTH 4,
    text     TYPE string,
  END OF ty_finding,
  ty_findings TYPE STANDARD TABLE OF ty_finding WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_edge,
    from_tr TYPE trkorr,
    to_tr   TYPE trkorr,
    hard    TYPE abap_bool,
    reason  TYPE string,
  END OF ty_edge,
  ty_edges TYPE STANDARD TABLE OF ty_edge WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_request,
    trkorr     TYPE trkorr,
    trfunction TYPE e070-trfunction,
    trstatus   TYPE e070-trstatus,
    tarsystem  TYPE e070-tarsystem,
    owner      TYPE e070-as4user,
    changed    TYPE e070-as4date,
    text       TYPE string,
    stamp      TYPE timestamp,
    objcount   TYPE i,
    rank       TYPE i,
    excluded   TYPE abap_bool,
    blocker    TYPE abap_bool,
    unimported TYPE abap_bool,
  END OF ty_request,
  ty_requests TYPE SORTED TABLE OF ty_request WITH UNIQUE KEY trkorr.

TYPES:
  BEGIN OF ty_result,
    sort_grp       TYPE i,
    seq            TYPE i,
    rel_seq        TYPE i,
    imp_seq        TYPE i,
    light          TYPE icon_d,
    trkorr         TYPE trkorr,
    trtype         TYPE c LENGTH 12,
    trstate        TYPE c LENGTH 14,
    owner          TYPE e070-as4user,
    changed        TYPE e070-as4date,
    text           TYPE string,
    objcount       TYPE i,
    must_follow    TYPE string,
    blocked_by     TYPE trkorr,
    grp            TYPE string,
    findcount      TYPE i,
    recommendation TYPE string,
  END OF ty_result,
  ty_results TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_detail,
    kind     TYPE c LENGTH 8,
    severity TYPE c LENGTH 1,
    object   TYPE string,
    detail   TYPE string,
  END OF ty_detail,
  ty_details TYPE STANDARD TABLE OF ty_detail WITH EMPTY KEY.

INTERFACE lif_tr_source.
  METHODS read
    IMPORTING it_range       TYPE ty_range
              iv_cross       TYPE abap_bool
              iv_dest        TYPE rfcdest
    RETURNING VALUE(rs_data) TYPE ty_data.
ENDINTERFACE.

*----------------------------------------------------------------------*
* Reader: the only class that touches the database
*----------------------------------------------------------------------*
CLASS lcl_reader DEFINITION FINAL.
  PUBLIC SECTION.
    INTERFACES lif_tr_source.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_pcache,
        pgmid         TYPE e071-pgmid,
        object        TYPE e071-object,
        obj_name      TYPE e071-obj_name,
        parent_object TYPE e071-object,
        parent_name   TYPE e071-obj_name,
      END OF ty_pcache.
    DATA mt_pcache TYPE HASHED TABLE OF ty_pcache WITH UNIQUE KEY pgmid object obj_name.
    DATA mv_parent_failed TYPE abap_bool.
    DATA mv_import_failed TYPE abap_bool.
    DATA mv_dest          TYPE rfcdest.

    METHODS read_headers
      IMPORTING it_range TYPE ty_range
      CHANGING  cs_data  TYPE ty_data.
    METHODS read_objects
      CHANGING cs_data TYPE ty_data.
    METHODS read_versions
      CHANGING cs_data TYPE ty_data.
    METHODS read_keys
      CHANGING cs_data TYPE ty_data.
    METHODS read_foreign
      CHANGING cs_data TYPE ty_data.
    METHODS read_refs
      CHANGING cs_data TYPE ty_data.
    METHODS read_inactive
      CHANGING cs_data TYPE ty_data.
    METHODS read_imports
      CHANGING cs_data TYPE ty_data.
    METHODS import_state
      IMPORTING iv_request      TYPE trkorr
      RETURNING VALUE(rv_state) TYPE ty_import-state.
    METHODS read_suppliers
      CHANGING cs_data TYPE ty_data.
    METHODS read_target_objects
      CHANGING cs_data TYPE ty_data.
    METHODS parent_of
      CHANGING cs_object TYPE ty_object.
    METHODS collect_names
      IMPORTING iv_include      TYPE string
                iv_like         TYPE abap_bool
      RETURNING VALUE(rt_names) TYPE ty_names.
    METHODS base_name
      IMPORTING iv_name        TYPE string
      RETURNING VALUE(rv_base) TYPE string.
ENDCLASS.

CLASS lcl_reader IMPLEMENTATION.

  METHOD lif_tr_source~read.
    read_headers( EXPORTING it_range = it_range CHANGING cs_data = rs_data ).
    read_objects( CHANGING cs_data = rs_data ).
    read_versions( CHANGING cs_data = rs_data ).
    read_keys( CHANGING cs_data = rs_data ).
    read_foreign( CHANGING cs_data = rs_data ).
    read_inactive( CHANGING cs_data = rs_data ).
    mv_dest = iv_dest.
    IF iv_cross = abap_true.
      read_refs( CHANGING cs_data = rs_data ).
      read_suppliers( CHANGING cs_data = rs_data ).
    ENDIF.
    IF mv_dest IS NOT INITIAL.
      read_imports( CHANGING cs_data = rs_data ).
      read_target_objects( CHANGING cs_data = rs_data ).
    ENDIF.
  ENDMETHOD.

  METHOD read_headers.
    SELECT trkorr, strkorr FROM e070
      WHERE trkorr IN @it_range
      INTO TABLE @DATA(lt_entered).

    LOOP AT it_range INTO DATA(ls_range) WHERE sign = 'I' AND option = 'EQ'.
      IF NOT line_exists( lt_entered[ trkorr = ls_range-low ] ).
        APPEND CONV string( ls_range-low ) TO cs_data-not_found.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_entered INTO DATA(ls_entered).
      DATA(lv_request) = COND trkorr( WHEN ls_entered-strkorr IS INITIAL
                                      THEN ls_entered-trkorr
                                      ELSE ls_entered-strkorr ).
      INSERT lv_request INTO TABLE cs_data-selected.
      IF ls_entered-strkorr IS NOT INITIAL.
        APPEND VALUE #( task = ls_entered-trkorr request = ls_entered-strkorr ) TO cs_data-task_map.
      ENDIF.
    ENDLOOP.

    IF cs_data-selected IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lt_sel) = cs_data-selected.
    SELECT trkorr, strkorr, trfunction, trstatus, tarsystem, as4user, as4date, as4time
      FROM e070
      FOR ALL ENTRIES IN @lt_sel
      WHERE trkorr = @lt_sel-table_line
         OR strkorr = @lt_sel-table_line
      INTO TABLE @DATA(lt_e070).

    LOOP AT lt_e070 INTO DATA(ls_e070).
      DATA(ls_header) = CORRESPONDING ty_header( ls_e070 ).
      ls_header-request = COND #( WHEN ls_e070-strkorr IS INITIAL THEN ls_e070-trkorr ELSE ls_e070-strkorr ).
      ls_header-stamp = CONV timestamp( |{ ls_e070-as4date }{ ls_e070-as4time }| ).
      SELECT SINGLE as4text FROM e07t
        WHERE trkorr = @ls_e070-trkorr AND langu = @sy-langu
        INTO @ls_header-text.
      IF sy-subrc <> 0.
        SELECT SINGLE as4text FROM e07t
          WHERE trkorr = @ls_e070-trkorr
          INTO @ls_header-text.
      ENDIF.
      INSERT ls_header INTO TABLE cs_data-headers.
    ENDLOOP.
  ENDMETHOD.

  METHOD read_objects.
    IF cs_data-headers IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lt_tr) = VALUE ty_trkorr_set( FOR h IN cs_data-headers ( h-trkorr ) ).
    SELECT trkorr, pgmid, object, obj_name, objfunc FROM e071
      FOR ALL ENTRIES IN @lt_tr
      WHERE trkorr = @lt_tr-table_line
      INTO TABLE @DATA(lt_e071).

    LOOP AT lt_e071 INTO DATA(ls_e071).
      APPEND VALUE #( request  = cs_data-headers[ trkorr = ls_e071-trkorr ]-request
                      task     = ls_e071-trkorr
                      pgmid    = ls_e071-pgmid
                      object   = ls_e071-object
                      obj_name = ls_e071-obj_name
                      objfunc  = ls_e071-objfunc ) TO cs_data-objects.
    ENDLOOP.

    " a released task is copied into its request: keep each object once per request
    SORT cs_data-objects BY request pgmid object obj_name task.
    DELETE ADJACENT DUPLICATES FROM cs_data-objects COMPARING request pgmid object obj_name.

    LOOP AT cs_data-objects ASSIGNING FIELD-SYMBOL(<ls_object>).
      parent_of( CHANGING cs_object = <ls_object> ).
    ENDLOOP.
    IF mv_parent_failed = abap_true.
      APPEND `TR_CHECK_TYPE failed: parts (LIMU) are compared by exact key only` TO cs_data-notes.
    ENDIF.

    TYPES: BEGIN OF ty_parent,
             object   TYPE tadir-object,
             obj_name TYPE tadir-obj_name,
           END OF ty_parent.
    DATA lt_parent TYPE SORTED TABLE OF ty_parent WITH UNIQUE KEY object obj_name.
    LOOP AT cs_data-objects INTO DATA(ls_object).
      INSERT VALUE #( object = ls_object-parent_object obj_name = ls_object-parent_name ) INTO TABLE lt_parent.
    ENDLOOP.
    IF lt_parent IS INITIAL.
      RETURN.
    ENDIF.

    SELECT object, obj_name, devclass FROM tadir
      FOR ALL ENTRIES IN @lt_parent
      WHERE pgmid = 'R3TR'
        AND object = @lt_parent-object
        AND obj_name = @lt_parent-obj_name
      INTO TABLE @DATA(lt_tadir).

    LOOP AT cs_data-objects ASSIGNING <ls_object>.
      ASSIGN lt_tadir[ object = <ls_object>-parent_object obj_name = <ls_object>-parent_name ]
        TO FIELD-SYMBOL(<ls_tadir>).
      IF sy-subrc = 0.
        <ls_object>-devclass = <ls_tadir>-devclass.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD parent_of.
    cs_object-parent_object = cs_object-object.
    cs_object-parent_name   = cs_object-obj_name.
    IF cs_object-pgmid = 'R3TR'.
      RETURN.
    ENDIF.

    ASSIGN mt_pcache[ pgmid = cs_object-pgmid object = cs_object-object obj_name = cs_object-obj_name ]
      TO FIELD-SYMBOL(<ls_cache>).
    IF sy-subrc = 0.
      cs_object-parent_object = <ls_cache>-parent_object.
      cs_object-parent_name   = <ls_cache>-parent_name.
      RETURN.
    ENDIF.

    " LIMU parts are mapped to their R3TR parent by SAP's own logic.
    " Dynamic call: a changed signature or a raised exception degrades to the exact key
    " and is reported as a finding (notes).
    DATA ls_e071  TYPE e071.
    DATA ls_tadir TYPE tadir.
    ls_e071 = VALUE #( pgmid = cs_object-pgmid object = cs_object-object obj_name = cs_object-obj_name ).
    DATA(lt_params) = VALUE abap_func_parmbind_tab(
      ( name = 'WI_E071'  kind = abap_func_exporting value = REF #( ls_e071 ) )
      ( name = 'WE_TADIR' kind = abap_func_importing value = REF #( ls_tadir ) ) ).
    DATA(lt_exceptions) = VALUE abap_func_excpbind_tab( ( name = 'OTHERS' value = 1 ) ).
    TRY.
        CALL FUNCTION 'TR_CHECK_TYPE' PARAMETER-TABLE lt_params EXCEPTION-TABLE lt_exceptions.
        IF sy-subrc <> 0.
          mv_parent_failed = abap_true.
        ELSEIF ls_tadir-object IS NOT INITIAL AND ls_tadir-obj_name IS NOT INITIAL.
          cs_object-parent_object = ls_tadir-object.
          cs_object-parent_name   = ls_tadir-obj_name.
        ENDIF.
      CATCH cx_sy_dyn_call_error.
        mv_parent_failed = abap_true.
    ENDTRY.

    INSERT VALUE #( pgmid         = cs_object-pgmid
                    object        = cs_object-object
                    obj_name      = cs_object-obj_name
                    parent_object = cs_object-parent_object
                    parent_name   = cs_object-parent_name ) INTO TABLE mt_pcache.
  ENDMETHOD.

  METHOD read_versions.
    IF cs_data-headers IS INITIAL OR cs_data-objects IS INITIAL.
      RETURN.
    ENDIF.

    " fallback stamp per request = latest header stamp of request and tasks
    TYPES: BEGIN OF ty_rstamp,
             request TYPE trkorr,
             stamp   TYPE timestamp,
           END OF ty_rstamp.
    DATA lt_rstamp TYPE SORTED TABLE OF ty_rstamp WITH UNIQUE KEY request.
    LOOP AT cs_data-headers INTO DATA(ls_header).
      ASSIGN lt_rstamp[ request = ls_header-request ] TO FIELD-SYMBOL(<ls_rs>).
      IF sy-subrc = 0.
        <ls_rs>-stamp = nmax( val1 = <ls_rs>-stamp val2 = ls_header-stamp ).
      ELSE.
        INSERT VALUE #( request = ls_header-request stamp = ls_header-stamp ) INTO TABLE lt_rstamp.
      ENDIF.
    ENDLOOP.

    " version stamps per request, object type and name (exists only for released tasks)
    TYPES: BEGIN OF ty_vstamp,
             request TYPE trkorr,
             objtype TYPE vrsd-objtype,
             objname TYPE vrsd-objname,
             stamp   TYPE timestamp,
           END OF ty_vstamp.
    DATA lt_vstamp TYPE HASHED TABLE OF ty_vstamp WITH UNIQUE KEY request objtype objname.

    DATA(lt_tr) = VALUE ty_trkorr_set( FOR h IN cs_data-headers ( h-trkorr ) ).
    SELECT objtype, objname, korrnum, datum, zeit FROM vrsd
      FOR ALL ENTRIES IN @lt_tr
      WHERE korrnum = @lt_tr-table_line
      INTO TABLE @DATA(lt_vrsd).

    LOOP AT lt_vrsd INTO DATA(ls_vrsd).
      DATA(lv_stamp)   = CONV timestamp( |{ ls_vrsd-datum }{ ls_vrsd-zeit }| ).
      DATA(lv_request) = cs_data-headers[ trkorr = ls_vrsd-korrnum ]-request.
      ASSIGN lt_vstamp[ request = lv_request objtype = ls_vrsd-objtype objname = ls_vrsd-objname ]
        TO FIELD-SYMBOL(<ls_vs>).
      IF sy-subrc = 0.
        <ls_vs>-stamp = nmax( val1 = <ls_vs>-stamp val2 = lv_stamp ).
      ELSE.
        INSERT VALUE #( request = lv_request objtype = ls_vrsd-objtype
                        objname = ls_vrsd-objname stamp = lv_stamp ) INTO TABLE lt_vstamp.
      ENDIF.
    ENDLOOP.

    LOOP AT cs_data-objects ASSIGNING FIELD-SYMBOL(<ls_object>).
      <ls_object>-stamp = lt_rstamp[ request = <ls_object>-request ]-stamp.
      ASSIGN lt_vstamp[ request = <ls_object>-request
                        objtype = <ls_object>-object
                        objname = <ls_object>-obj_name ] TO FIELD-SYMBOL(<ls_hit>).
      IF sy-subrc <> 0.
        ASSIGN lt_vstamp[ request = <ls_object>-request
                          objtype = <ls_object>-parent_object
                          objname = <ls_object>-parent_name ] TO <ls_hit>.
      ENDIF.
      IF sy-subrc = 0.
        <ls_object>-stamp = <ls_hit>-stamp.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD read_keys.
    IF cs_data-headers IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lt_tr) = VALUE ty_trkorr_set( FOR h IN cs_data-headers ( h-trkorr ) ).
    SELECT trkorr, objname, tabkey FROM e071k
      FOR ALL ENTRIES IN @lt_tr
      WHERE trkorr = @lt_tr-table_line
      INTO TABLE @DATA(lt_e071k).

    DATA lt_seen TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    LOOP AT lt_e071k INTO DATA(ls_e071k).
      DATA(ls_header) = cs_data-headers[ trkorr = ls_e071k-trkorr ].
      INSERT |{ ls_header-request }/{ ls_e071k-objname }/{ ls_e071k-tabkey }| INTO TABLE lt_seen.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      INSERT VALUE #( request = ls_header-request
                      tabname = ls_e071k-objname
                      tabkey  = ls_e071k-tabkey
                      stamp   = ls_header-stamp ) INTO TABLE cs_data-keys.
    ENDLOOP.
  ENDMETHOD.

  METHOD read_foreign.
    IF cs_data-objects IS INITIAL.
      RETURN.
    ENDIF.
    TYPES: BEGIN OF ty_okey,
             pgmid    TYPE e071-pgmid,
             object   TYPE e071-object,
             obj_name TYPE e071-obj_name,
           END OF ty_okey.
    DATA lt_okey TYPE SORTED TABLE OF ty_okey WITH UNIQUE KEY pgmid object obj_name.
    LOOP AT cs_data-objects INTO DATA(ls_object).
      INSERT VALUE #( pgmid = ls_object-pgmid object = ls_object-object obj_name = ls_object-obj_name )
        INTO TABLE lt_okey.
    ENDLOOP.

    " open requests of other users (foreign) and released history (object already shipped)
    SELECT e071~pgmid, e071~object, e071~obj_name, e070~trkorr, e070~strkorr, e070~as4user, e070~trstatus
      FROM e071 INNER JOIN e070 ON e070~trkorr = e071~trkorr
      FOR ALL ENTRIES IN @lt_okey
      WHERE e071~pgmid = @lt_okey-pgmid
        AND e071~object = @lt_okey-object
        AND e071~obj_name = @lt_okey-obj_name
        AND e070~trstatus IN ('D', 'L', 'R', 'N')
      INTO TABLE @DATA(lt_hit).

    DATA lt_released TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    LOOP AT lt_hit INTO DATA(ls_hit).
      DATA(lv_request) = COND trkorr( WHEN ls_hit-strkorr IS INITIAL THEN ls_hit-trkorr ELSE ls_hit-strkorr ).
      IF line_exists( cs_data-selected[ table_line = lv_request ] ).
        CONTINUE.
      ENDIF.
      IF ls_hit-trstatus = 'R' OR ls_hit-trstatus = 'N'.
        INSERT |{ ls_hit-pgmid }{ ls_hit-object }{ ls_hit-obj_name }| INTO TABLE lt_released.
        APPEND VALUE #( pgmid    = ls_hit-pgmid
                        object   = ls_hit-object
                        obj_name = ls_hit-obj_name
                        request  = lv_request ) TO cs_data-hist.
      ELSE.
        APPEND VALUE #( pgmid    = ls_hit-pgmid
                        object   = ls_hit-object
                        obj_name = ls_hit-obj_name
                        request  = lv_request
                        owner    = ls_hit-as4user ) TO cs_data-foreign.
      ENDIF.
    ENDLOOP.

    " a whole object (R3TR) that never appeared in a released request is treated as new
    LOOP AT cs_data-objects ASSIGNING FIELD-SYMBOL(<ls_object>).
      DATA(lv_key) = |{ <ls_object>-pgmid }{ <ls_object>-object }{ <ls_object>-obj_name }|.
      <ls_object>-is_new = xsdbool( <ls_object>-pgmid = 'R3TR'
                                    AND NOT line_exists( lt_released[ table_line = lv_key ] ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD read_inactive.
    IF cs_data-objects IS INITIAL.
      RETURN.
    ENDIF.
    TYPES: BEGIN OF ty_nm,
             obj_name TYPE dwinactiv-obj_name,
           END OF ty_nm.
    DATA lt_nm TYPE SORTED TABLE OF ty_nm WITH UNIQUE KEY obj_name.
    LOOP AT cs_data-objects INTO DATA(ls_object).
      INSERT VALUE #( obj_name = ls_object-parent_name ) INTO TABLE lt_nm.
    ENDLOOP.

    SELECT object, obj_name, uname FROM dwinactiv
      FOR ALL ENTRIES IN @lt_nm
      WHERE obj_name = @lt_nm-obj_name
      INTO TABLE @DATA(lt_inactive).

    LOOP AT lt_inactive INTO DATA(ls_inactive).
      APPEND VALUE #( object   = ls_inactive-object
                      obj_name = ls_inactive-obj_name
                      uname    = ls_inactive-uname ) TO cs_data-inactive.
    ENDLOOP.
  ENDMETHOD.

  METHOD read_imports.
    CONSTANTS lc_max TYPE i VALUE 100.
    DATA lt_check TYPE ty_trkorr_set.

    " selected requests that are already released
    LOOP AT cs_data-headers INTO DATA(ls_header) WHERE strkorr IS INITIAL
                                                    AND ( trstatus = 'R' OR trstatus = 'N' ).
      IF line_exists( cs_data-selected[ table_line = ls_header-trkorr ] ).
        INSERT ls_header-trkorr INTO TABLE lt_check.
      ENDIF.
    ENDLOOP.
    " released requests that contain objects of the selection
    LOOP AT cs_data-hist INTO DATA(ls_hist).
      INSERT ls_hist-request INTO TABLE lt_check.
    ENDLOOP.
    " released requests that deliver used objects outside the selection
    LOOP AT cs_data-suppliers INTO DATA(ls_supplier) WHERE status = 'R' OR status = 'N'.
      INSERT ls_supplier-request INTO TABLE lt_check.
    ENDLOOP.

    DATA(lv_count) = 0.
    LOOP AT lt_check INTO DATA(lv_request).
      lv_count = lv_count + 1.
      IF lv_count > lc_max.
        APPEND |Import check limited to { lc_max } requests| TO cs_data-notes.
        EXIT.
      ENDIF.
      INSERT VALUE #( request = lv_request state = import_state( lv_request ) ) INTO TABLE cs_data-imports.
    ENDLOOP.

    IF mv_import_failed = abap_true.
      APPEND |Import status could not be read via RFC destination { mv_dest }| TO cs_data-notes.
    ENDIF.
  ENDMETHOD.

  METHOD import_state.
    rv_state = 'U'.
    IF mv_import_failed = abap_true.
      RETURN.
    ENDIF.

    DATA lt_options TYPE STANDARD TABLE OF rfc_db_opt WITH EMPTY KEY.
    DATA lt_fields  TYPE STANDARD TABLE OF rfc_db_fld WITH EMPTY KEY.
    DATA lt_data    TYPE STANDARD TABLE OF tab512 WITH EMPTY KEY.
    lt_options = VALUE #( ( text = |TRKORR = '{ iv_request }'| ) ).
    lt_fields  = VALUE #( ( fieldname = 'TRKORR' ) ).

    CALL FUNCTION 'RFC_READ_TABLE' DESTINATION mv_dest
      EXPORTING
        query_table = 'E070'
      TABLES
        options     = lt_options
        fields      = lt_fields
        data        = lt_data
      EXCEPTIONS
        system_failure        = 1
        communication_failure = 2
        OTHERS                = 3.
    IF sy-subrc <> 0.
      mv_import_failed = abap_true.
      RETURN.
    ENDIF.
    rv_state = COND #( WHEN lt_data IS INITIAL THEN 'N' ELSE 'I' ).
  ENDMETHOD.

  METHOD read_suppliers.
    IF cs_data-refs IS INITIAL.
      RETURN.
    ENDIF.

    " names delivered by a selected request are handled by the usage check
    DATA lt_selected_names TYPE ty_name_set.
    LOOP AT cs_data-objects INTO DATA(ls_object).
      INSERT CONV string( ls_object-parent_name ) INTO TABLE lt_selected_names.
      INSERT CONV string( ls_object-obj_name ) INTO TABLE lt_selected_names.
    ENDLOOP.

    TYPES: BEGIN OF ty_nm,
             obj_name TYPE e071-obj_name,
           END OF ty_nm.
    DATA lt_nm TYPE SORTED TABLE OF ty_nm WITH UNIQUE KEY obj_name.
    LOOP AT cs_data-refs INTO DATA(ls_ref).
      IF NOT line_exists( lt_selected_names[ table_line = ls_ref-used_name ] ).
        INSERT VALUE #( obj_name = ls_ref-used_name ) INTO TABLE lt_nm.
      ENDIF.
    ENDLOOP.
    IF lt_nm IS INITIAL.
      RETURN.
    ENDIF.

    SELECT e071~obj_name, e070~trkorr, e070~strkorr
      FROM e071 INNER JOIN e070 ON e070~trkorr = e071~trkorr
      FOR ALL ENTRIES IN @lt_nm
      WHERE e071~pgmid = 'R3TR'
        AND e071~obj_name = @lt_nm-obj_name
      INTO TABLE @DATA(lt_hit).

    IF lt_hit IS NOT INITIAL.
      DATA lt_requests TYPE ty_trkorr_set.
      LOOP AT lt_hit INTO DATA(ls_hit).
        INSERT COND trkorr( WHEN ls_hit-strkorr IS INITIAL THEN ls_hit-trkorr ELSE ls_hit-strkorr )
          INTO TABLE lt_requests.
      ENDLOOP.
      " the status of the REQUEST decides (a released task can sit in an open request)
      SELECT trkorr, trstatus, as4user, as4date FROM e070
        FOR ALL ENTRIES IN @lt_requests
        WHERE trkorr = @lt_requests-table_line
        INTO TABLE @DATA(lt_head).

      LOOP AT lt_hit INTO ls_hit.
        DATA(lv_request) = COND trkorr( WHEN ls_hit-strkorr IS INITIAL THEN ls_hit-trkorr ELSE ls_hit-strkorr ).
        IF line_exists( cs_data-selected[ table_line = lv_request ] ).
          CONTINUE.
        ENDIF.
        ASSIGN lt_head[ trkorr = lv_request ] TO FIELD-SYMBOL(<ls_head>).
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
        DATA(ls_supplier) = VALUE ty_supplier( name    = condense( CONV string( ls_hit-obj_name ) )
                                               request = lv_request
                                               status  = <ls_head>-trstatus
                                               owner   = <ls_head>-as4user
                                               changed = <ls_head>-as4date ).
        IF NOT line_exists( cs_data-suppliers[ name = ls_supplier-name request = ls_supplier-request ] ).
          APPEND ls_supplier TO cs_data-suppliers.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " names found in no request: local ($TMP) or transportable package?
    TYPES: BEGIN OF ty_tn,
             obj_name TYPE tadir-obj_name,
           END OF ty_tn.
    DATA lt_tn TYPE SORTED TABLE OF ty_tn WITH UNIQUE KEY obj_name.
    LOOP AT lt_nm INTO DATA(ls_nm).
      DATA(lv_name) = condense( CONV string( ls_nm-obj_name ) ).
      IF strlen( lv_name ) <= 40 AND NOT line_exists( cs_data-suppliers[ name = lv_name ] ).
        INSERT VALUE #( obj_name = lv_name ) INTO TABLE lt_tn.
      ENDIF.
    ENDLOOP.
    IF lt_tn IS INITIAL.
      RETURN.
    ENDIF.

    SELECT obj_name, devclass FROM tadir
      FOR ALL ENTRIES IN @lt_tn
      WHERE pgmid = 'R3TR'
        AND obj_name = @lt_tn-obj_name
      INTO TABLE @DATA(lt_tadir).
    LOOP AT lt_tadir INTO DATA(ls_tadir).
      APPEND VALUE #( name     = condense( CONV string( ls_tadir-obj_name ) )
                      devclass = ls_tadir-devclass ) TO cs_data-locals.
    ENDLOOP.
  ENDMETHOD.

  METHOD read_target_objects.
    CONSTANTS lc_batch TYPE i VALUE 10.
    CONSTANTS lc_max   TYPE i VALUE 300.

    IF mv_import_failed = abap_true.
      RETURN.
    ENDIF.

    " objects whose existence in the target is unknown: no request at all, or
    " released request without a known import status
    DATA lt_names TYPE ty_name_set.
    LOOP AT cs_data-locals INTO DATA(ls_local) WHERE devclass <> '$TMP' AND devclass IS NOT INITIAL.
      INSERT ls_local-name INTO TABLE lt_names.
    ENDLOOP.
    LOOP AT cs_data-suppliers INTO DATA(ls_supplier) WHERE status = 'R' OR status = 'N'.
      ASSIGN cs_data-imports[ request = ls_supplier-request ] TO FIELD-SYMBOL(<ls_imp>).
      IF sy-subrc <> 0 OR <ls_imp>-state = 'U'.
        INSERT ls_supplier-name INTO TABLE lt_names.
      ENDIF.
    ENDLOOP.
    IF lt_names IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lt_all) = VALUE ty_names( FOR n IN lt_names ( n ) ).
    IF lines( lt_all ) > lc_max.
      APPEND |Target existence check limited to { lc_max } objects| TO cs_data-notes.
      DELETE lt_all FROM lc_max + 1.
    ENDIF.

    DATA lt_options TYPE STANDARD TABLE OF rfc_db_opt WITH EMPTY KEY.
    DATA lt_fields  TYPE STANDARD TABLE OF rfc_db_fld WITH EMPTY KEY.
    DATA lt_data    TYPE STANDARD TABLE OF tab512 WITH EMPTY KEY.
    lt_fields = VALUE #( ( fieldname = 'OBJ_NAME' ) ).

    DATA(lv_from) = 1.
    WHILE lv_from <= lines( lt_all ) AND mv_import_failed = abap_false.
      DATA(lv_to) = nmin( val1 = lv_from + lc_batch - 1 val2 = lines( lt_all ) ).
      CLEAR: lt_options, lt_data.
      LOOP AT lt_all INTO DATA(lv_name) FROM lv_from TO lv_to.
        APPEND VALUE #( text = COND #( WHEN sy-tabix = lv_from
                                       THEN |OBJ_NAME = '{ lv_name }'|
                                       ELSE | OR OBJ_NAME = '{ lv_name }'| ) ) TO lt_options.
      ENDLOOP.

      CALL FUNCTION 'RFC_READ_TABLE' DESTINATION mv_dest
        EXPORTING
          query_table = 'TADIR'
        TABLES
          options     = lt_options
          fields      = lt_fields
          data        = lt_data
        EXCEPTIONS
          system_failure        = 1
          communication_failure = 2
          OTHERS                = 3.
      IF sy-subrc <> 0.
        mv_import_failed = abap_true.
      ELSE.
        LOOP AT lt_data INTO DATA(ls_row).
          INSERT condense( CONV string( ls_row-wa ) ) INTO TABLE cs_data-existing.
        ENDLOOP.
      ENDIF.
      lv_from = lv_to + 1.
    ENDWHILE.

    cs_data-checked = xsdbool( mv_import_failed = abap_false ).
    IF mv_import_failed = abap_true.
      APPEND |Target existence check failed via RFC destination { mv_dest }| TO cs_data-notes.
    ENDIF.
  ENDMETHOD.

  METHOD base_name.
    rv_base = condense( iv_name ).
    IF rv_base CS '\'.
      rv_base = substring_before( val = rv_base sub = '\' ).
    ENDIF.
    IF rv_base CS '-'.
      rv_base = substring_before( val = rv_base sub = '-' ).
    ENDIF.
  ENDMETHOD.

  METHOD collect_names.
    DATA lt_a TYPE ty_names.
    DATA lt_b TYPE ty_names.
    IF iv_like = abap_true.
      DATA(lv_like) = replace( val = iv_include sub = '_' with = '#_' occ = 0 ).
      lv_like = |{ lv_like }%|.
      SELECT DISTINCT name FROM wbcrossgt WHERE include LIKE @lv_like ESCAPE '#' INTO TABLE @lt_a.
      SELECT DISTINCT name FROM cross WHERE include LIKE @lv_like ESCAPE '#' AND type = 'F' INTO TABLE @lt_b.
    ELSE.
      DATA(lv_include) = CONV programm( iv_include ).
      SELECT DISTINCT name FROM wbcrossgt WHERE include = @lv_include INTO TABLE @lt_a.
      SELECT DISTINCT name FROM cross WHERE include = @lv_include AND type = 'F' INTO TABLE @lt_b.
    ENDIF.
    rt_names = lt_a.
    APPEND LINES OF lt_b TO rt_names.
  ENDMETHOD.

  METHOD read_refs.
    " (1) function modules owned by each request (so CROSS 'F' hits can be matched)
    LOOP AT cs_data-objects INTO DATA(ls_object).
      IF ls_object-object = 'FUNC'.
        APPEND VALUE #( request = ls_object-request name = CONV string( ls_object-obj_name ) )
          TO cs_data-members.
      ELSEIF ls_object-pgmid = 'R3TR' AND ls_object-object = 'FUGR' AND ls_object-obj_name(1) <> '/'.
        SELECT funcname FROM tfdir
          WHERE pname = @( |SAPL{ ls_object-obj_name }| )
          INTO TABLE @DATA(lt_fm).
        LOOP AT lt_fm INTO DATA(ls_fm).
          APPEND VALUE #( request = ls_object-request name = CONV string( ls_fm-funcname ) )
            TO cs_data-members.
        ENDLOOP.
      ENDIF.
    ENDLOOP.

    " names that could satisfy a dependency: parent objects and FMs of the selection
    DATA lt_known TYPE ty_name_set.
    LOOP AT cs_data-objects INTO ls_object.
      INSERT CONV string( ls_object-parent_name ) INTO TABLE lt_known.
      INSERT CONV string( ls_object-obj_name ) INTO TABLE lt_known.
    ENDLOOP.
    LOOP AT cs_data-members INTO DATA(ls_member).
      INSERT ls_member-name INTO TABLE lt_known.
    ENDLOOP.

    " (2) repository usage and (3) DDIC to DDIC, once per request and parent object
    DATA(lt_parents) = cs_data-objects.
    SORT lt_parents BY request parent_object parent_name.
    DELETE ADJACENT DUPLICATES FROM lt_parents COMPARING request parent_object parent_name.

    LOOP AT lt_parents INTO DATA(ls_parent).
      DATA(lv_user) = |{ ls_parent-parent_object } { ls_parent-parent_name }|.
      DATA(lt_used) = VALUE ty_names( ).
      DATA(lv_name) = CONV string( ls_parent-parent_name ).

      CASE ls_parent-parent_object.
        WHEN 'PROG'.
          lt_used = collect_names( iv_include = lv_name iv_like = abap_false ).
        WHEN 'CLAS' OR 'INTF'.
          lt_used = collect_names( iv_include = |{ ls_parent-parent_name WIDTH = 30 PAD = '=' }|
                                   iv_like    = abap_true ).
        WHEN 'FUGR'.
          lt_used = collect_names( iv_include = |SAPL{ lv_name }| iv_like = abap_false ).
          APPEND LINES OF collect_names( iv_include = |L{ lv_name }| iv_like = abap_true ) TO lt_used.
        WHEN 'TABL'.
          SELECT DISTINCT rollname FROM dd03l
            WHERE tabname = @ls_parent-parent_name AND as4local = 'A' AND rollname <> @space
            INTO TABLE @DATA(lt_roll).
          lt_used = VALUE #( FOR r IN lt_roll ( CONV string( r-rollname ) ) ).
        WHEN 'DTEL'.
          SELECT domname FROM dd04l
            WHERE rollname = @ls_parent-parent_name AND as4local = 'A'
            INTO TABLE @DATA(lt_dom).
          lt_used = VALUE #( FOR d IN lt_dom ( CONV string( d-domname ) ) ).
        WHEN 'TTYP'.
          SELECT rowtype FROM dd40l
            WHERE typename = @ls_parent-parent_name AND as4local = 'A'
            INTO TABLE @DATA(lt_row).
          lt_used = VALUE #( FOR w IN lt_row ( CONV string( w-rowtype ) ) ).
        WHEN 'VIEW'.
          SELECT tabname FROM dd26s
            WHERE viewname = @ls_parent-parent_name AND as4local = 'A'
            INTO TABLE @DATA(lt_tab).
          lt_used = VALUE #( FOR t IN lt_tab ( CONV string( t-tabname ) ) ).
      ENDCASE.

      LOOP AT lt_used INTO DATA(lv_used).
        DATA(lv_base) = base_name( lv_used ).
        IF lv_base IS INITIAL OR lv_base = lv_name.
          CONTINUE.
        ENDIF.
        " keep names of the selection and all custom names (suppliers outside the selection)
        IF NOT line_exists( lt_known[ table_line = lv_base ] ) AND lv_base(1) NA 'ZY/'.
          CONTINUE.
        ENDIF.
        APPEND VALUE #( request = ls_parent-request user_object = lv_user used_name = lv_base ) TO cs_data-refs.
      ENDLOOP.
    ENDLOOP.
    SORT cs_data-refs BY request user_object used_name.
    DELETE ADJACENT DUPLICATES FROM cs_data-refs COMPARING request user_object used_name.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Analyzer: findings and ordering edges (pure logic, no DB access)
*----------------------------------------------------------------------*
CLASS lcl_analyzer DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_analysis,
        requests TYPE ty_requests,
        findings TYPE ty_findings,
        edges    TYPE ty_edges,
        import_edges TYPE ty_edges,
      END OF ty_analysis.

    METHODS analyze
      IMPORTING is_data            TYPE ty_data
      RETURNING VALUE(rs_analysis) TYPE ty_analysis.

    CLASS-METHODS type_rank
      IMPORTING iv_object      TYPE e071-object
      RETURNING VALUE(rv_rank) TYPE i.

  PRIVATE SECTION.
    DATA ms_data   TYPE ty_data.
    DATA ms_result TYPE ty_analysis.

    METHODS add_finding
      IMPORTING iv_request  TYPE trkorr
                iv_severity TYPE ty_finding-severity
                iv_code     TYPE ty_finding-code
                iv_text     TYPE string.
    METHODS add_edge
      IMPORTING iv_from   TYPE trkorr
                iv_to     TYPE trkorr
                iv_hard   TYPE abap_bool
                iv_reason TYPE string.
    METHODS is_active
      IMPORTING iv_request       TYPE trkorr
      RETURNING VALUE(rv_active) TYPE abap_bool.
    METHODS put_edge
      IMPORTING iv_from   TYPE trkorr
                iv_to     TYPE trkorr
                iv_hard   TYPE abap_bool
                iv_reason TYPE string
      CHANGING  ct_edges  TYPE ty_edges.
    METHODS build_requests.
    METHODS check_selection_mix.
    METHODS check_object_overlap.
    METHODS check_keys.
    METHODS check_usage.
    METHODS check_foreign_and_local.
    METHODS check_inactive.
    METHODS check_import_history.
    METHODS check_external_usage.
    METHODS is_unimported
      IMPORTING iv_request            TYPE trkorr
      RETURNING VALUE(rv_unimported) TYPE abap_bool.
    METHODS order_pair
      IMPORTING iv_request_a TYPE trkorr
                iv_stamp_a   TYPE timestamp
                iv_request_b TYPE trkorr
                iv_stamp_b   TYPE timestamp
                iv_reason    TYPE string.
ENDCLASS.

CLASS lcl_analyzer IMPLEMENTATION.

  METHOD analyze.
    ms_data = is_data.
    CLEAR ms_result.
    build_requests( ).
    LOOP AT ms_data-notes INTO DATA(lv_note).
      LOOP AT ms_result-requests INTO DATA(ls_req) WHERE excluded = abap_false.
        add_finding( iv_request = ls_req-trkorr iv_severity = 'W' iv_code = 'W015' iv_text = lv_note ).
      ENDLOOP.
    ENDLOOP.
    check_selection_mix( ).
    check_object_overlap( ).
    check_keys( ).
    check_usage( ).
    check_foreign_and_local( ).
    check_inactive( ).
    check_import_history( ).
    check_external_usage( ).
    rs_analysis = ms_result.
  ENDMETHOD.

  METHOD type_rank.
    rv_rank = SWITCH #( iv_object
      WHEN 'DOMA' THEN 10
      WHEN 'DTEL' THEN 20
      WHEN 'TABL' OR 'TABD' OR 'TABT' THEN 30
      WHEN 'TTYP' OR 'VIEW' OR 'SHLP' OR 'ENQU' THEN 40
      WHEN 'MSAG' OR 'ENHO' OR 'ENHS' OR 'SXCI' THEN 50
      WHEN 'CLAS' OR 'INTF' OR 'METH' OR 'CPUB' OR 'CPRI' OR 'CPRO' OR 'CINC' THEN 60
      WHEN 'FUGR' OR 'FUNC' THEN 70
      WHEN 'PROG' OR 'REPS' THEN 80
      WHEN 'TABU' OR 'VDAT' OR 'CDAT' OR 'TDAT' THEN 90
      ELSE 85 ).
  ENDMETHOD.

  METHOD add_finding.
    IF line_exists( ms_result-findings[ request = iv_request code = iv_code text = iv_text ] ).
      RETURN.
    ENDIF.
    APPEND VALUE #( request = iv_request severity = iv_severity code = iv_code text = iv_text )
      TO ms_result-findings.
  ENDMETHOD.

  METHOD is_unimported.
    ASSIGN ms_result-requests[ trkorr = iv_request ] TO FIELD-SYMBOL(<ls_request>).
    IF sy-subrc <> 0 OR <ls_request>-excluded = abap_false.
      RETURN.
    ENDIF.
    rv_unimported = <ls_request>-unimported.
  ENDMETHOD.

  METHOD is_active.
    ASSIGN ms_result-requests[ trkorr = iv_request ] TO FIELD-SYMBOL(<ls_request>).
    rv_active = xsdbool( sy-subrc = 0 AND <ls_request>-excluded = abap_false ).
  ENDMETHOD.

  METHOD add_edge.
    " two released-but-not-imported requests: import order, kept apart from the release order
    IF iv_from <> iv_to AND is_unimported( iv_from ) = abap_true AND is_unimported( iv_to ) = abap_true.
      put_edge( EXPORTING iv_from = iv_from iv_to = iv_to iv_hard = iv_hard iv_reason = iv_reason
                CHANGING  ct_edges = ms_result-import_edges ).
      RETURN.
    ENDIF.
    IF iv_from <> iv_to AND ( is_unimported( iv_from ) = abap_true OR is_unimported( iv_to ) = abap_true ).
      DATA(lv_other) = COND trkorr( WHEN is_unimported( iv_from ) = abap_true THEN iv_from ELSE iv_to ).
      DATA(lv_mine)  = COND trkorr( WHEN lv_other = iv_from THEN iv_to ELSE iv_from ).
      IF is_active( lv_mine ) = abap_true.
        add_finding( iv_request  = lv_mine
                     iv_severity = COND #( WHEN iv_hard = abap_true THEN 'E' ELSE 'W' )
                     iv_code     = COND #( WHEN iv_hard = abap_true THEN 'E017' ELSE 'W017' )
                     iv_text     = |{ iv_reason } ({ lv_other } is released but NOT imported in the target - import it first)| ).
      ENDIF.
      RETURN.
    ENDIF.
    IF iv_from = iv_to OR is_active( iv_from ) = abap_false OR is_active( iv_to ) = abap_false.
      RETURN.
    ENDIF.
    put_edge( EXPORTING iv_from = iv_from iv_to = iv_to iv_hard = iv_hard iv_reason = iv_reason
              CHANGING  ct_edges = ms_result-edges ).
  ENDMETHOD.

  METHOD put_edge.
    ASSIGN ct_edges[ from_tr = iv_from to_tr = iv_to ] TO FIELD-SYMBOL(<ls_edge>).
    IF sy-subrc = 0.
      IF iv_hard = abap_true.
        <ls_edge>-hard = abap_true.
      ENDIF.
      IF NOT <ls_edge>-reason CS iv_reason.
        <ls_edge>-reason = |{ <ls_edge>-reason }; { iv_reason }|.
      ENDIF.
    ELSE.
      APPEND VALUE #( from_tr = iv_from to_tr = iv_to hard = iv_hard reason = iv_reason ) TO ct_edges.
    ENDIF.
  ENDMETHOD.

  METHOD order_pair.
    " older change first; equal stamps fall back to request number
    IF iv_stamp_a < iv_stamp_b OR ( iv_stamp_a = iv_stamp_b AND iv_request_a < iv_request_b ).
      add_edge( iv_from = iv_request_a iv_to = iv_request_b iv_hard = abap_false iv_reason = iv_reason ).
    ELSE.
      add_edge( iv_from = iv_request_b iv_to = iv_request_a iv_hard = abap_false iv_reason = iv_reason ).
    ENDIF.
  ENDMETHOD.

  METHOD build_requests.
    LOOP AT ms_data-not_found INTO DATA(lv_missing).
      DATA(lv_number) = CONV trkorr( lv_missing ).
      INSERT VALUE #( trkorr = lv_number text = `Not found` excluded = abap_true ) INTO TABLE ms_result-requests.
      add_finding( iv_request = lv_number iv_severity = 'E' iv_code = 'E001'
                   iv_text = `Transport request not found in this system` ).
    ENDLOOP.

    LOOP AT ms_data-task_map INTO DATA(ls_map).
      add_finding( iv_request = ls_map-request iv_severity = 'I' iv_code = 'I002'
                   iv_text = |{ ls_map-task } is a task - analysed as part of { ls_map-request }| ).
    ENDLOOP.

    LOOP AT ms_data-selected INTO DATA(lv_request).
      ASSIGN ms_data-headers[ trkorr = lv_request ] TO FIELD-SYMBOL(<ls_header>).
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      DATA(ls_request) = VALUE ty_request( trkorr     = lv_request
                                           trfunction = <ls_header>-trfunction
                                           trstatus   = <ls_header>-trstatus
                                           tarsystem  = <ls_header>-tarsystem
                                           owner      = <ls_header>-as4user
                                           changed    = <ls_header>-as4date
                                           text       = <ls_header>-text
                                           stamp      = <ls_header>-stamp ).

      LOOP AT ms_data-headers INTO DATA(ls_task) WHERE strkorr = lv_request.
        ls_request-stamp = nmax( val1 = ls_request-stamp val2 = ls_task-stamp ).
        IF ls_task-trstatus CA 'DLO'.
          ls_request-blocker = abap_true.
          add_finding( iv_request = lv_request iv_severity = 'E' iv_code = 'E004'
                       iv_text = |Task { ls_task-trkorr } ({ ls_task-as4user }) is not released| ).
        ENDIF.
      ENDLOOP.

      IF <ls_header>-trstatus = 'O'.
        ls_request-blocker = abap_true.
        add_finding( iv_request = lv_request iv_severity = 'E' iv_code = 'E004'
                     iv_text = `Release of this request has already started` ).
      ENDIF.
      IF <ls_header>-trstatus CA 'RN'.
        ls_request-excluded = abap_true.
        ASSIGN ms_data-imports[ request = lv_request ] TO FIELD-SYMBOL(<ls_imp>).
        DATA(lv_state) = COND #( WHEN sy-subrc = 0 THEN <ls_imp>-state ELSE 'U' ).
        CASE lv_state.
          WHEN 'I'.
            add_finding( iv_request = lv_request iv_severity = 'I' iv_code = 'I003'
                         iv_text = `Already released and imported in the target - excluded` ).
          WHEN 'N'.
            ls_request-unimported = xsdbool( <ls_header>-trfunction <> 'T' ).
            add_finding( iv_request = lv_request iv_severity = 'E' iv_code = 'E017'
                         iv_text = `Released but NOT imported in the target - import it before requests that depend on it` ).
          WHEN OTHERS.
            add_finding( iv_request = lv_request iv_severity = 'I' iv_code = 'I003'
                         iv_text = `Already released - excluded; confirm it is imported in the target` ).
        ENDCASE.
      ENDIF.
      IF <ls_header>-trfunction = 'T'.
        ls_request-excluded = abap_true.
        add_finding( iv_request = lv_request iv_severity = 'W' iv_code = 'W006'
                     iv_text = `Transport of copies - not part of the release sequence` ).
      ELSEIF <ls_header>-trfunction CA 'COEL'.
        add_finding( iv_request = lv_request iv_severity = 'W' iv_code = 'W006'
                     iv_text = |Special request type { <ls_header>-trfunction } (relocation/deletion) - check separately| ).
      ENDIF.

      ls_request-rank = 999.
      LOOP AT ms_data-objects INTO DATA(ls_object) WHERE request = lv_request.
        ls_request-objcount = ls_request-objcount + 1.
        ls_request-rank = nmin( val1 = ls_request-rank val2 = type_rank( ls_object-object ) ).
      ENDLOOP.
      IF ls_request-objcount = 0 AND ls_request-excluded = abap_false.
        add_finding( iv_request = lv_request iv_severity = 'W' iv_code = 'W005'
                     iv_text = `Request contains no objects (request and tasks)` ).
      ENDIF.

      INSERT ls_request INTO TABLE ms_result-requests.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_selection_mix.
    DATA lt_targets TYPE ty_name_set.
    DATA lv_has_wb   TYPE abap_bool.
    DATA lv_has_cust TYPE abap_bool.
    LOOP AT ms_result-requests INTO DATA(ls_request) WHERE excluded = abap_false.
      INSERT CONV string( ls_request-tarsystem ) INTO TABLE lt_targets.
      IF ls_request-trfunction = 'W'.
        lv_has_cust = abap_true.
      ELSEIF ls_request-trfunction = 'K'.
        lv_has_wb = abap_true.
      ENDIF.
    ENDLOOP.
    LOOP AT ms_result-requests INTO ls_request WHERE excluded = abap_false.
      IF lines( lt_targets ) > 1 OR ls_request-tarsystem IS INITIAL.
        add_finding( iv_request = ls_request-trkorr iv_severity = 'W' iv_code = 'W007'
                     iv_text = |Target system differs or is blank ({ ls_request-tarsystem }) - different transport route| ).
      ENDIF.
      IF lv_has_wb = abap_true AND lv_has_cust = abap_true.
        add_finding( iv_request = ls_request-trkorr iv_severity = 'W' iv_code = 'W008'
                     iv_text = `Workbench and customizing requests are mixed in the selection` ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_object_overlap.
    DATA(lt_active) = VALUE ty_objects( ).
    LOOP AT ms_data-objects INTO DATA(ls_o).
      IF ( is_active( ls_o-request ) = abap_true OR is_unimported( ls_o-request ) = abap_true )
         AND ls_o-object <> 'TABU' AND ls_o-object <> 'VDAT'
         AND ls_o-object <> 'CDAT' AND ls_o-object <> 'TDAT'.
        APPEND ls_o TO lt_active.
      ENDIF.
    ENDLOOP.

    " exact object in several requests
    LOOP AT lt_active INTO ls_o
         GROUP BY ( pgmid = ls_o-pgmid object = ls_o-object obj_name = ls_o-obj_name )
         INTO DATA(ls_group).
      DATA(lt_member) = VALUE ty_objects( FOR m IN GROUP ls_group ( m ) ).
      IF lines( lt_member ) < 2.
        CONTINUE.
      ENDIF.
      SORT lt_member BY stamp request.
      DATA(lv_label) = |{ ls_group-object } { condense( CONV string( ls_group-obj_name ) ) }|.
      DATA(lv_has_delete) = abap_false.
      LOOP AT lt_member INTO DATA(ls_m).
        IF ls_m-objfunc = 'D'.
          lv_has_delete = abap_true.
        ENDIF.
        DATA(lv_others) = REDUCE string( INIT s = `` FOR x IN lt_member
                                          WHERE ( request <> ls_m-request )
                                          NEXT s = COND #( WHEN s IS INITIAL THEN x-request
                                                           ELSE |{ s }, { x-request }| ) ).
        add_finding( iv_request = ls_m-request iv_severity = 'W' iv_code = 'W009'
                     iv_text = |{ lv_label } is also in { lv_others } - release in change order| ).
        IF ls_m-objfunc = 'D'.
          add_finding( iv_request = ls_m-request iv_severity = 'W' iv_code = 'W010'
                       iv_text = |{ lv_label } is deleted here and also touched in { lv_others }| ).
        ENDIF.
      ENDLOOP.
      " consecutive pairs only
      DO lines( lt_member ) - 1 TIMES.
        DATA(ls_a) = lt_member[ sy-index ].
        DATA(ls_b) = lt_member[ sy-index + 1 ].
        order_pair( iv_request_a = ls_a-request iv_stamp_a = ls_a-stamp
                    iv_request_b = ls_b-request iv_stamp_b = ls_b-stamp
                    iv_reason    = |same object { lv_label }| ).
      ENDDO.
    ENDLOOP.

    " same parent object, different parts (info only)
    LOOP AT lt_active INTO ls_o
         GROUP BY ( parent_object = ls_o-parent_object parent_name = ls_o-parent_name )
         INTO DATA(ls_pgroup).
      DATA(lt_pm) = VALUE ty_objects( FOR m IN GROUP ls_pgroup ( m ) ).
      DATA(lt_exact) = VALUE ty_name_set( ).
      DATA(lt_reqs)  = VALUE ty_trkorr_set( ).
      LOOP AT lt_pm INTO DATA(ls_pm).
        INSERT |{ ls_pm-pgmid }{ ls_pm-object }{ ls_pm-obj_name }| INTO TABLE lt_exact.
        INSERT ls_pm-request INTO TABLE lt_reqs.
      ENDLOOP.
      IF lines( lt_reqs ) < 2 OR lines( lt_exact ) < 2.
        CONTINUE.
      ENDIF.
      " whole object in one request, a part of it in another: same object changed twice
      LOOP AT lt_pm INTO DATA(ls_whole) WHERE pgmid = 'R3TR'.
        LOOP AT lt_pm INTO DATA(ls_part) WHERE pgmid <> 'R3TR' AND request <> ls_whole-request.
          DATA(lv_whole) = |{ ls_whole-object } { condense( CONV string( ls_whole-obj_name ) ) }|.
          order_pair( iv_request_a = ls_whole-request iv_stamp_a = ls_whole-stamp
                      iv_request_b = ls_part-request  iv_stamp_b = ls_part-stamp
                      iv_reason    = |{ lv_whole } and a part of it| ).
          add_finding( iv_request = ls_whole-request iv_severity = 'W' iv_code = 'W009'
                       iv_text = |{ lv_whole } is also changed in part in { ls_part-request } - release in change order| ).
          add_finding( iv_request = ls_part-request iv_severity = 'W' iv_code = 'W009'
                       iv_text = |{ lv_whole } is also in { ls_whole-request } as a whole - release in change order| ).
        ENDLOOP.
      ENDLOOP.
      LOOP AT lt_reqs INTO DATA(lv_req).
        add_finding( iv_request = lv_req iv_severity = 'I' iv_code = 'I011'
                     iv_text = |Other parts of { ls_pgroup-parent_object } | &&
                               |{ condense( CONV string( ls_pgroup-parent_name ) ) } are in other selected requests| ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_keys.
    LOOP AT ms_data-keys INTO DATA(ls_a).
      IF is_active( ls_a-request ) = abap_false.
        CONTINUE.
      ENDIF.
      LOOP AT ms_data-keys INTO DATA(ls_b) WHERE tabname = ls_a-tabname.
        IF ls_b-request <= ls_a-request OR is_active( ls_b-request ) = abap_false.
          CONTINUE.
        ENDIF.
        IF NOT ( ls_a-tabkey CP ls_b-tabkey OR ls_b-tabkey CP ls_a-tabkey ).
          CONTINUE.
        ENDIF.
        DATA(lv_reason) = |same customizing key { condense( CONV string( ls_a-tabname ) ) }|.
        order_pair( iv_request_a = ls_a-request iv_stamp_a = ls_a-stamp
                    iv_request_b = ls_b-request iv_stamp_b = ls_b-stamp
                    iv_reason    = lv_reason ).
        add_finding( iv_request = ls_a-request iv_severity = 'W' iv_code = 'W011'
                     iv_text = |{ lv_reason } also in { ls_b-request } - release in change order| ).
        add_finding( iv_request = ls_b-request iv_severity = 'W' iv_code = 'W011'
                     iv_text = |{ lv_reason } also in { ls_a-request } - release in change order| ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_usage.
    LOOP AT ms_data-refs INTO DATA(ls_ref).
      LOOP AT ms_data-objects INTO DATA(ls_owner)
           WHERE request <> ls_ref-request
             AND ( parent_name = ls_ref-used_name OR obj_name = ls_ref-used_name ).
        DATA(lv_reason) = |{ ls_ref-user_object } uses { ls_ref-used_name }|.
        add_edge( iv_from = ls_owner-request iv_to = ls_ref-request
                  iv_hard = ls_owner-is_new iv_reason = lv_reason ).
        add_finding( iv_request = ls_ref-request iv_severity = 'I' iv_code = 'I013'
                     iv_text = |{ lv_reason } ({ COND #( WHEN ls_owner-is_new = abap_true THEN `new` ELSE `changed` ) } | &&
                               |in { ls_owner-request }) - release { ls_owner-request } first| ).
      ENDLOOP.
      LOOP AT ms_data-members INTO DATA(ls_member)
           WHERE request <> ls_ref-request AND name = ls_ref-used_name.
        lv_reason = |{ ls_ref-user_object } calls { ls_ref-used_name }|.
        add_edge( iv_from = ls_member-request iv_to = ls_ref-request
                  iv_hard = abap_false iv_reason = lv_reason ).
        add_finding( iv_request = ls_ref-request iv_severity = 'I' iv_code = 'I013'
                     iv_text = |{ lv_reason } (in { ls_member-request }) - release { ls_member-request } first| ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_inactive.
    LOOP AT ms_data-inactive INTO DATA(ls_inactive).
      LOOP AT ms_data-objects INTO DATA(ls_o) WHERE parent_name = ls_inactive-obj_name.
        IF is_active( ls_o-request ) = abap_true.
          add_finding( iv_request = ls_o-request iv_severity = 'E' iv_code = 'E016'
                       iv_text = |{ ls_o-object } { condense( CONV string( ls_o-obj_name ) ) } is inactive | &&
                                 |(user { ls_inactive-uname }) - activate before release| ).
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_import_history.
    LOOP AT ms_data-hist INTO DATA(ls_hist).
      ASSIGN ms_data-imports[ request = ls_hist-request ] TO FIELD-SYMBOL(<ls_import>).
      IF sy-subrc <> 0 OR <ls_import>-state <> 'N'.
        CONTINUE.
      ENDIF.
      LOOP AT ms_data-objects INTO DATA(ls_o)
           WHERE pgmid = ls_hist-pgmid AND object = ls_hist-object AND obj_name = ls_hist-obj_name.
        IF is_active( ls_o-request ) = abap_true.
          add_finding( iv_request = ls_o-request iv_severity = 'W' iv_code = 'W018'
                       iv_text = |{ ls_o-object } { condense( CONV string( ls_o-obj_name ) ) } is also in released request | &&
                                 |{ ls_hist-request } which is NOT imported in the target - import it first| ).
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_external_usage.
    CONSTANTS lc_recent_days TYPE i VALUE 30.

    LOOP AT ms_data-refs INTO DATA(ls_ref).
      IF is_active( ls_ref-request ) = abap_false.
        CONTINUE.
      ENDIF.

      DATA(lv_found) = abap_false.
      LOOP AT ms_data-suppliers INTO DATA(ls_sup) WHERE name = ls_ref-used_name.
        lv_found = abap_true.

        IF ls_sup-status = 'D' OR ls_sup-status = 'L' OR ls_sup-status = 'O'.
          " open request outside the selection; new = never shipped before
          DATA(lv_new) = xsdbool( NOT line_exists( ms_data-suppliers[ name = ls_ref-used_name status = 'R' ] )
                                  AND NOT line_exists( ms_data-suppliers[ name = ls_ref-used_name status = 'N' ] ) ).
          add_finding( iv_request  = ls_ref-request
                       iv_severity = COND #( WHEN lv_new = abap_true THEN 'E' ELSE 'W' )
                       iv_code     = COND #( WHEN lv_new = abap_true THEN 'E021' ELSE 'W021' )
                       iv_text     = |{ ls_ref-user_object } uses { ls_ref-used_name }, which is only in open request | &&
                                     |{ ls_sup-request } ({ ls_sup-owner }) - not selected, add it to the release| ).
        ELSE.
          ASSIGN ms_data-imports[ request = ls_sup-request ] TO FIELD-SYMBOL(<ls_imp>).
          DATA(lv_state) = COND #( WHEN sy-subrc = 0 THEN <ls_imp>-state ELSE 'U' ).
          CASE lv_state.
            WHEN 'I'.
              CONTINUE.
            WHEN 'N'.
              add_finding( iv_request = ls_ref-request iv_severity = 'E' iv_code = 'E022'
                           iv_text = |{ ls_ref-user_object } uses { ls_ref-used_name } from released request | &&
                                     |{ ls_sup-request } which is NOT imported in the target - import it first| ).
            WHEN OTHERS.
              IF ms_data-checked = abap_true.
                IF NOT line_exists( ms_data-existing[ table_line = ls_ref-used_name ] ).
                  add_finding( iv_request = ls_ref-request iv_severity = 'E' iv_code = 'E022'
                               iv_text = |{ ls_ref-user_object } uses { ls_ref-used_name } (released in { ls_sup-request }) | &&
                                         |which does not exist in the target - import { ls_sup-request } first| ).
                ENDIF.
              ELSEIF sy-datum - ls_sup-changed <= lc_recent_days.
                add_finding( iv_request = ls_ref-request iv_severity = 'W' iv_code = 'W022'
                             iv_text = |{ ls_ref-user_object } uses { ls_ref-used_name } from recently released request | &&
                                       |{ ls_sup-request }; import status unknown (no target RFC destination)| ).
              ENDIF.
          ENDCASE.
        ENDIF.
      ENDLOOP.

      IF lv_found = abap_true.
        CONTINUE.
      ENDIF.

      " used object that is in no request at all
      LOOP AT ms_data-locals INTO DATA(ls_local) WHERE name = ls_ref-used_name.
        IF ls_local-devclass = '$TMP'.
          add_finding( iv_request = ls_ref-request iv_severity = 'E' iv_code = 'E023'
                       iv_text = |{ ls_ref-user_object } uses local object { ls_ref-used_name } ($TMP) - not transportable| ).
        ELSEIF ms_data-checked = abap_true AND NOT line_exists( ms_data-existing[ table_line = ls_ref-used_name ] ).
          add_finding( iv_request = ls_ref-request iv_severity = 'E' iv_code = 'E024'
                       iv_text = |{ ls_ref-user_object } uses { ls_ref-used_name } (package { ls_local-devclass }), which is in no | &&
                                 |request and does not exist in the target - forgotten object?| ).
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_foreign_and_local.
    LOOP AT ms_data-foreign INTO DATA(ls_foreign).
      LOOP AT ms_data-objects INTO DATA(ls_o)
           WHERE pgmid = ls_foreign-pgmid AND object = ls_foreign-object AND obj_name = ls_foreign-obj_name.
        IF is_active( ls_o-request ) = abap_true.
          add_finding( iv_request = ls_o-request iv_severity = 'W' iv_code = 'W012'
                       iv_text = |{ ls_o-object } { condense( CONV string( ls_o-obj_name ) ) } is also in open request | &&
                                 |{ ls_foreign-request } ({ ls_foreign-owner }) which is not selected| ).
        ENDIF.
      ENDLOOP.
    ENDLOOP.
    LOOP AT ms_data-objects INTO ls_o WHERE devclass = '$TMP'.
      IF is_active( ls_o-request ) = abap_true.
        add_finding( iv_request = ls_o-request iv_severity = 'W' iv_code = 'W013'
                     iv_text = |Local object { ls_o-object } { condense( CONV string( ls_o-obj_name ) ) } ($TMP) is not transportable| ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Sequencer: Kahn topological sort with hard/soft edges
*----------------------------------------------------------------------*
CLASS lcl_sequencer DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_node,
        trkorr   TYPE trkorr,
        rank     TYPE i,
        stamp    TYPE timestamp,
        excluded TYPE abap_bool,
        blocker  TYPE abap_bool,
      END OF ty_node,
      ty_nodes TYPE STANDARD TABLE OF ty_node WITH EMPTY KEY,
      BEGIN OF ty_order,
        trkorr     TYPE trkorr,
        seq        TYPE i,
        grp        TYPE string,
        blocked_by TYPE trkorr,
        blocked    TYPE abap_bool,
        note       TYPE string,
      END OF ty_order,
      ty_orders TYPE SORTED TABLE OF ty_order WITH UNIQUE KEY trkorr.

    METHODS sequence
      IMPORTING it_nodes        TYPE ty_nodes
                it_edges        TYPE ty_edges
      RETURNING VALUE(rt_order) TYPE ty_orders.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_work,
        trkorr     TYPE trkorr,
        rank       TYPE i,
        stamp      TYPE timestamp,
        blocked    TYPE abap_bool,
        blocked_by TYPE trkorr,
        done       TYPE abap_bool,
        seq        TYPE i,
        grp        TYPE string,
        note       TYPE string,
      END OF ty_work.

    DATA mt_work  TYPE SORTED TABLE OF ty_work WITH UNIQUE KEY trkorr.
    DATA mt_edges TYPE ty_edges.

    METHODS propagate_blockers.
    METHODS is_open
      IMPORTING iv_trkorr      TYPE trkorr
      RETURNING VALUE(rv_open) TYPE abap_bool.
    TYPES:
      BEGIN OF ty_pair,
        a TYPE trkorr,
        b TYPE trkorr,
      END OF ty_pair,
      ty_reach TYPE HASHED TABLE OF ty_pair WITH UNIQUE KEY a b.
    METHODS has_open_predecessor
      IMPORTING iv_trkorr      TYPE trkorr
      RETURNING VALUE(rv_open) TYPE abap_bool.
    METHODS pick_best
      RETURNING VALUE(rv_trkorr) TYPE trkorr.
    METHODS build_reach
      IMPORTING iv_hard_only    TYPE abap_bool
      RETURNING VALUE(rt_reach) TYPE ty_reach.
    METHODS drop_cyclic_soft_edges
      RETURNING VALUE(rv_dropped) TYPE abap_bool.
    METHODS take_cycle
      IMPORTING iv_seq          TYPE i
                iv_group        TYPE string
      RETURNING VALUE(rv_taken) TYPE abap_bool.
ENDCLASS.

CLASS lcl_sequencer IMPLEMENTATION.

  METHOD sequence.
    mt_edges = it_edges.
    mt_work = VALUE #( FOR n IN it_nodes WHERE ( excluded = abap_false )
                       ( trkorr = n-trkorr rank = n-rank stamp = n-stamp blocked = n-blocker ) ).
    propagate_blockers( ).

    DATA(lv_seq)   = 0.
    DATA(lv_group) = 0.
    WHILE line_exists( mt_work[ done = abap_false blocked = abap_false ] ).
      lv_seq = lv_seq + 1.

      DATA(lv_pick) = pick_best( ).
      IF lv_pick IS NOT INITIAL.
        ASSIGN mt_work[ trkorr = lv_pick ] TO FIELD-SYMBOL(<ls_pick>).
        <ls_pick>-seq  = lv_seq.
        <ls_pick>-done = abap_true.
        CONTINUE.
      ENDIF.

      " stalled: drop only the soft edges that sit on a cycle, then retry
      IF drop_cyclic_soft_edges( ) = abap_true.
        lv_seq = lv_seq - 1.
        CONTINUE.
      ENDIF.

      " stalled on hard edges: real cycle
      lv_group = lv_group + 1.
      IF take_cycle( iv_seq = lv_seq iv_group = |G{ lv_group }| ) = abap_false.
        LOOP AT mt_work ASSIGNING FIELD-SYMBOL(<ls_rest>) WHERE done = abap_false AND blocked = abap_false.
          <ls_rest>-blocked = abap_true.
          <ls_rest>-note    = `Order could not be resolved`.
        ENDLOOP.
      ENDIF.
    ENDWHILE.

    rt_order = VALUE #( FOR w IN mt_work
                        ( trkorr = w-trkorr seq = w-seq grp = w-grp blocked_by = w-blocked_by
                          blocked = w-blocked note = w-note ) ).
  ENDMETHOD.

  METHOD propagate_blockers.
    DO.
      DATA(lv_changed) = abap_false.
      LOOP AT mt_edges INTO DATA(ls_edge) WHERE hard = abap_true.
        ASSIGN mt_work[ trkorr = ls_edge-from_tr ] TO FIELD-SYMBOL(<ls_from>).
        IF sy-subrc <> 0 OR <ls_from>-blocked = abap_false.
          CONTINUE.
        ENDIF.
        ASSIGN mt_work[ trkorr = ls_edge-to_tr ] TO FIELD-SYMBOL(<ls_to>).
        IF sy-subrc <> 0 OR <ls_to>-blocked = abap_true.
          CONTINUE.
        ENDIF.
        <ls_to>-blocked    = abap_true.
        <ls_to>-blocked_by = COND #( WHEN <ls_from>-blocked_by IS INITIAL
                                     THEN ls_edge-from_tr ELSE <ls_from>-blocked_by ).
        lv_changed = abap_true.
      ENDLOOP.
      IF lv_changed = abap_false.
        EXIT.
      ENDIF.
    ENDDO.
  ENDMETHOD.

  METHOD is_open.
    ASSIGN mt_work[ trkorr = iv_trkorr ] TO FIELD-SYMBOL(<ls_w>).
    rv_open = xsdbool( sy-subrc = 0 AND <ls_w>-done = abap_false AND <ls_w>-blocked = abap_false ).
  ENDMETHOD.

  METHOD has_open_predecessor.
    LOOP AT mt_edges INTO DATA(ls_edge) WHERE to_tr = iv_trkorr.
      IF is_open( ls_edge-from_tr ) = abap_true.
        rv_open = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD pick_best.
    DATA ls_best TYPE ty_work.
    LOOP AT mt_work INTO DATA(ls_w) WHERE done = abap_false AND blocked = abap_false.
      IF has_open_predecessor( ls_w-trkorr ) = abap_true.
        CONTINUE.
      ENDIF.
      IF ls_best-trkorr IS INITIAL
         OR ls_w-rank < ls_best-rank
         OR ( ls_w-rank = ls_best-rank AND ls_w-stamp < ls_best-stamp )
         OR ( ls_w-rank = ls_best-rank AND ls_w-stamp = ls_best-stamp AND ls_w-trkorr < ls_best-trkorr ).
        ls_best = ls_w.
      ENDIF.
    ENDLOOP.
    rv_trkorr = ls_best-trkorr.
  ENDMETHOD.

  METHOD build_reach.
    LOOP AT mt_edges INTO DATA(ls_edge).
      IF iv_hard_only = abap_true AND ls_edge-hard = abap_false.
        CONTINUE.
      ENDIF.
      IF is_open( ls_edge-from_tr ) = abap_true AND is_open( ls_edge-to_tr ) = abap_true.
        INSERT VALUE #( a = ls_edge-from_tr b = ls_edge-to_tr ) INTO TABLE rt_reach.
      ENDIF.
    ENDLOOP.

    " transitive closure (selections are small)
    DO.
      DATA(lv_added) = abap_false.
      DATA(lt_copy) = rt_reach.
      LOOP AT lt_copy INTO DATA(ls_ab).
        LOOP AT lt_copy INTO DATA(ls_bc) WHERE a = ls_ab-b.
          INSERT VALUE #( a = ls_ab-a b = ls_bc-b ) INTO TABLE rt_reach.
          IF sy-subrc = 0.
            lv_added = abap_true.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
      IF lv_added = abap_false.
        EXIT.
      ENDIF.
    ENDDO.
  ENDMETHOD.

  METHOD drop_cyclic_soft_edges.
    DATA(lt_reach) = build_reach( abap_false ).
    DATA(lt_keep) = VALUE ty_edges( ).
    LOOP AT mt_edges INTO DATA(ls_edge).
      IF ls_edge-hard = abap_false
         AND is_open( ls_edge-from_tr ) = abap_true
         AND is_open( ls_edge-to_tr ) = abap_true
         AND line_exists( lt_reach[ a = ls_edge-to_tr b = ls_edge-from_tr ] ).
        rv_dropped = abap_true.
        ASSIGN mt_work[ trkorr = ls_edge-from_tr ] TO FIELD-SYMBOL(<ls_from>).
        <ls_from>-note = `Soft ordering relaxed (circular overlap)`.
        ASSIGN mt_work[ trkorr = ls_edge-to_tr ] TO FIELD-SYMBOL(<ls_to>).
        <ls_to>-note = `Soft ordering relaxed (circular overlap)`.
      ELSE.
        APPEND ls_edge TO lt_keep.
      ENDIF.
    ENDLOOP.
    mt_edges = lt_keep.
  ENDMETHOD.

  METHOD take_cycle.
    DATA(lt_reach) = build_reach( abap_true ).

    LOOP AT mt_work INTO DATA(ls_w) WHERE done = abap_false AND blocked = abap_false.
      IF NOT line_exists( lt_reach[ a = ls_w-trkorr b = ls_w-trkorr ] ).
        CONTINUE.
      ENDIF.
      DATA(lt_scc) = VALUE ty_trkorr_set( ).
      LOOP AT mt_work INTO DATA(ls_m) WHERE done = abap_false AND blocked = abap_false.
        IF ls_m-trkorr = ls_w-trkorr
           OR ( line_exists( lt_reach[ a = ls_w-trkorr b = ls_m-trkorr ] )
                AND line_exists( lt_reach[ a = ls_m-trkorr b = ls_w-trkorr ] ) ).
          INSERT ls_m-trkorr INTO TABLE lt_scc.
        ENDIF.
      ENDLOOP.

      DATA(lv_outside) = abap_false.
      LOOP AT mt_edges INTO DATA(ls_edge) WHERE hard = abap_true.
        IF line_exists( lt_scc[ table_line = ls_edge-to_tr ] )
           AND NOT line_exists( lt_scc[ table_line = ls_edge-from_tr ] )
           AND is_open( ls_edge-from_tr ) = abap_true.
          lv_outside = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.

      IF lv_outside = abap_false.
        LOOP AT lt_scc INTO DATA(lv_member).
          ASSIGN mt_work[ trkorr = lv_member ] TO FIELD-SYMBOL(<ls_x>).
          <ls_x>-seq  = iv_seq.
          <ls_x>-grp  = iv_group.
          <ls_x>-done = abap_true.
        ENDLOOP.
        rv_taken = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* ALV output with drill-down popup
*----------------------------------------------------------------------*
CLASS lcl_alv DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS display
      IMPORTING it_results  TYPE ty_results
                it_findings TYPE ty_findings
                it_edges    TYPE ty_edges
                it_objects  TYPE ty_objects.

  PRIVATE SECTION.
    DATA mt_results  TYPE ty_results.
    DATA mt_findings TYPE ty_findings.
    DATA mt_edges    TYPE ty_edges.
    DATA mt_objects  TYPE ty_objects.

    METHODS on_double_click
      FOR EVENT double_click OF cl_salv_events_table
      IMPORTING row column.
    METHODS set_text
      IMPORTING io_columns TYPE REF TO cl_salv_columns_table
                iv_name    TYPE lvc_fname
                iv_short   TYPE scrtext_s
                iv_long    TYPE scrtext_l.
    METHODS show_details
      IMPORTING iv_request TYPE trkorr.
ENDCLASS.

CLASS lcl_alv IMPLEMENTATION.

  METHOD display.
    mt_results  = it_results.
    mt_findings = it_findings.
    mt_edges    = it_edges.
    mt_objects  = it_objects.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = DATA(lo_alv)
                                CHANGING  t_table      = mt_results ).
        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->get_display_settings( )->set_list_header( `Transport release sequence` ).
        lo_alv->get_display_settings( )->set_striped_pattern( abap_true ).

        DATA(lo_columns) = lo_alv->get_columns( ).
        lo_columns->set_optimize( abap_true ).
        lo_columns->get_column( 'SORT_GRP' )->set_visible( abap_false ).
        CAST cl_salv_column_table( lo_columns->get_column( 'LIGHT' ) )->set_icon( if_salv_c_bool_sap=>true ).

        set_text( io_columns = lo_columns iv_name = 'SEQ'            iv_short = 'Seq'        iv_long = 'Release sequence' ).
        set_text( io_columns = lo_columns iv_name = 'LIGHT'          iv_short = 'Status'     iv_long = 'Status' ).
        set_text( io_columns = lo_columns iv_name = 'TRKORR'         iv_short = 'Request'    iv_long = 'Transport request' ).
        set_text( io_columns = lo_columns iv_name = 'TRTYPE'         iv_short = 'Type'       iv_long = 'Request type' ).
        set_text( io_columns = lo_columns iv_name = 'TRSTATE'        iv_short = 'State'      iv_long = 'Request state' ).
        set_text( io_columns = lo_columns iv_name = 'OWNER'          iv_short = 'Owner'      iv_long = 'Owner' ).
        set_text( io_columns = lo_columns iv_name = 'CHANGED'        iv_short = 'Changed'    iv_long = 'Changed on' ).
        set_text( io_columns = lo_columns iv_name = 'TEXT'           iv_short = 'Text'       iv_long = 'Description' ).
        set_text( io_columns = lo_columns iv_name = 'OBJCOUNT'       iv_short = '#Obj'       iv_long = 'Number of objects' ).
        set_text( io_columns = lo_columns iv_name = 'REL_SEQ'        iv_short = 'Rel.seq'    iv_long = 'Release order (released)' ).
        set_text( io_columns = lo_columns iv_name = 'IMP_SEQ'        iv_short = 'Imp.seq'    iv_long = 'Import order (not imported)' ).
        set_text( io_columns = lo_columns iv_name = 'MUST_FOLLOW'    iv_short = 'After'      iv_long = 'Release/import after' ).
        set_text( io_columns = lo_columns iv_name = 'BLOCKED_BY'     iv_short = 'Blocked by' iv_long = 'Blocked by' ).
        set_text( io_columns = lo_columns iv_name = 'GRP'            iv_short = 'Group'      iv_long = 'Cycle group' ).
        set_text( io_columns = lo_columns iv_name = 'FINDCOUNT'      iv_short = '#Find'      iv_long = 'Number of findings' ).
        set_text( io_columns = lo_columns iv_name = 'RECOMMENDATION' iv_short = 'Advice'     iv_long = 'Recommendation' ).

        SET HANDLER on_double_click FOR lo_alv->get_event( ).
        lo_alv->display( ).
      CATCH cx_salv_msg cx_salv_not_found cx_salv_data_error INTO DATA(lx_salv).
        MESSAGE lx_salv TYPE 'E'.
    ENDTRY.
  ENDMETHOD.

  METHOD set_text.
    TRY.
        DATA(lo_column) = io_columns->get_column( iv_name ).
        lo_column->set_short_text( iv_short ).
        lo_column->set_medium_text( CONV #( iv_long ) ).
        lo_column->set_long_text( iv_long ).
      CATCH cx_salv_not_found.
        RETURN.
    ENDTRY.
  ENDMETHOD.

  METHOD on_double_click.
    ASSIGN mt_results[ row ] TO FIELD-SYMBOL(<ls_result>).
    IF sy-subrc = 0.
      show_details( <ls_result>-trkorr ).
    ENDIF.
  ENDMETHOD.

  METHOD show_details.
    DATA(lt_detail) = VALUE ty_details( ).
    LOOP AT mt_findings INTO DATA(ls_finding) WHERE request = iv_request.
      APPEND VALUE #( kind = 'Finding' severity = ls_finding-severity
                      object = ls_finding-code detail = ls_finding-text ) TO lt_detail.
    ENDLOOP.
    LOOP AT mt_edges INTO DATA(ls_edge) WHERE to_tr = iv_request.
      APPEND VALUE #( kind = 'Order' object = ls_edge-from_tr
                      detail = |Must be released first ({ COND #( WHEN ls_edge-hard = abap_true THEN `hard` ELSE `soft` ) }): { ls_edge-reason }| )
        TO lt_detail.
    ENDLOOP.
    LOOP AT mt_objects INTO DATA(ls_object) WHERE request = iv_request.
      APPEND VALUE #( kind   = 'Object'
                      object = |{ ls_object-pgmid } { ls_object-object } { condense( CONV string( ls_object-obj_name ) ) }|
                      detail = |Task { ls_object-task }, changed { ls_object-stamp TIMESTAMP = USER }| )
        TO lt_detail.
    ENDLOOP.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = DATA(lo_popup)
                                CHANGING  t_table      = lt_detail ).
        lo_popup->get_display_settings( )->set_list_header( |Details { iv_request }| ).
        lo_popup->get_columns( )->set_optimize( abap_true ).
        lo_popup->set_screen_popup( start_column = 10 end_column = 150 start_line = 5 end_line = 22 ).
        lo_popup->display( ).
      CATCH cx_salv_msg INTO DATA(lx_salv).
        MESSAGE lx_salv TYPE 'E'.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Application: wires reader -> analyzer -> sequencer -> ALV
*----------------------------------------------------------------------*
CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run
      IMPORTING it_range TYPE ty_range
                iv_cross TYPE abap_bool
                iv_dest  TYPE rfcdest.
    CLASS-METHODS build_results
      IMPORTING is_analysis       TYPE lcl_analyzer=>ty_analysis
                it_order          TYPE lcl_sequencer=>ty_orders
                it_import_order   TYPE lcl_sequencer=>ty_orders
      EXPORTING et_results        TYPE ty_results
                et_findings       TYPE ty_findings.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.

  METHOD run.
    DATA lo_source TYPE REF TO lif_tr_source.
    lo_source = NEW lcl_reader( ).
    DATA(ls_data) = lo_source->read( it_range = it_range iv_cross = iv_cross iv_dest = iv_dest ).
    IF ls_data-headers IS INITIAL AND ls_data-not_found IS INITIAL.
      MESSAGE 'No transport requests found for the selection' TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

    DATA(ls_analysis) = NEW lcl_analyzer( )->analyze( ls_data ).
    DATA(lt_order) = NEW lcl_sequencer( )->sequence(
      it_nodes = VALUE #( FOR r IN ls_analysis-requests
                          ( trkorr = r-trkorr rank = r-rank stamp = r-stamp
                            excluded = r-excluded blocker = r-blocker ) )
      it_edges = ls_analysis-edges ).

    " released but not imported requests: recommended import order
    DATA(lt_import_order) = NEW lcl_sequencer( )->sequence(
      it_nodes = VALUE #( FOR r IN ls_analysis-requests WHERE ( unimported = abap_true )
                          ( trkorr = r-trkorr rank = r-rank stamp = r-stamp ) )
      it_edges = ls_analysis-import_edges ).

    build_results( EXPORTING is_analysis = ls_analysis it_order = lt_order it_import_order = lt_import_order
                   IMPORTING et_results  = DATA(lt_results) et_findings = DATA(lt_findings) ).

    DATA(lt_all_edges) = ls_analysis-edges.
    APPEND LINES OF ls_analysis-import_edges TO lt_all_edges.
    NEW lcl_alv( )->display( it_results  = lt_results
                             it_findings = lt_findings
                             it_edges    = lt_all_edges
                             it_objects  = ls_data-objects ).
  ENDMETHOD.

  METHOD build_results.
    TYPES: BEGIN OF ty_ranked,
             rank TYPE i,
             idx  TYPE i,
             text TYPE string,
           END OF ty_ranked,
           ty_ranked_t TYPE STANDARD TABLE OF ty_ranked WITH EMPTY KEY.
    et_findings = is_analysis-findings.

    " release order of released requests (release date/time)
    TYPES: BEGIN OF ty_rel,
             trkorr TYPE trkorr,
             stamp  TYPE timestamp,
           END OF ty_rel.
    DATA lt_rel TYPE STANDARD TABLE OF ty_rel WITH EMPTY KEY.
    LOOP AT is_analysis-requests INTO DATA(ls_released)
         WHERE excluded = abap_true AND trstatus CA 'RN' AND trfunction <> 'T'.
      APPEND VALUE #( trkorr = ls_released-trkorr stamp = ls_released-stamp ) TO lt_rel.
    ENDLOOP.
    SORT lt_rel BY stamp trkorr.

    DATA(lt_edges) = is_analysis-edges.
    APPEND LINES OF is_analysis-import_edges TO lt_edges.

    " findings that only exist after sequencing
    LOOP AT it_order INTO DATA(ls_order).
      IF ls_order-grp IS NOT INITIAL.
        APPEND VALUE #( request = ls_order-trkorr severity = 'E' code = 'E014'
                        text = |Circular dependency (group { ls_order-grp }): release the group consecutively | &&
                               |and import in one run, or merge the open tasks first| )
          TO et_findings.
      ENDIF.
      IF ls_order-blocked_by IS NOT INITIAL.
        APPEND VALUE #( request = ls_order-trkorr severity = 'E' code = 'E015'
                        text = |Blocked by { ls_order-blocked_by }| ) TO et_findings.
      ENDIF.
      IF ls_order-note IS NOT INITIAL.
        APPEND VALUE #( request = ls_order-trkorr severity = 'W' code = 'W014' text = ls_order-note )
          TO et_findings.
      ENDIF.
    ENDLOOP.

    LOOP AT it_import_order INTO DATA(ls_import) WHERE grp IS NOT INITIAL.
      APPEND VALUE #( request = ls_import-trkorr severity = 'E' code = 'E025'
                      text = |Circular dependency (group { ls_import-grp }) in the import order: | &&
                             |import the group in one run| ) TO et_findings.
    ENDLOOP.

    LOOP AT is_analysis-requests INTO DATA(ls_request).
      DATA(ls_o) = VALUE lcl_sequencer=>ty_order( ).
      IF ls_request-excluded = abap_false.
        ls_o = it_order[ trkorr = ls_request-trkorr ].
      ENDIF.

      DATA(lt_own) = VALUE ty_findings( FOR f IN et_findings WHERE ( request = ls_request-trkorr ) ( f ) ).
      DATA(lv_errors)   = REDUCE i( INIT n = 0 FOR f IN lt_own WHERE ( severity = 'E' ) NEXT n = n + 1 ).
      DATA(lv_warnings) = REDUCE i( INIT n = 0 FOR f IN lt_own WHERE ( severity = 'W' ) NEXT n = n + 1 ).

      ASSIGN it_import_order[ trkorr = ls_request-trkorr ] TO FIELD-SYMBOL(<ls_imp_order>).
      DATA(lv_imp_seq) = COND i( WHEN sy-subrc = 0 THEN <ls_imp_order>-seq ).

      DATA(ls_result) = VALUE ty_result(
        seq        = ls_o-seq
        rel_seq    = line_index( lt_rel[ trkorr = ls_request-trkorr ] )
        imp_seq    = lv_imp_seq
        trkorr     = ls_request-trkorr
        owner      = ls_request-owner
        changed    = ls_request-changed
        text       = ls_request-text
        objcount   = ls_request-objcount
        blocked_by = ls_o-blocked_by
        grp        = ls_o-grp
        findcount  = lines( lt_own ) ).

      ls_result-trtype = SWITCH #( ls_request-trfunction
        WHEN 'K' THEN 'Workbench' WHEN 'W' THEN 'Customizing' WHEN 'T' THEN 'Copies'
        WHEN 'L' THEN 'Deletion'  WHEN 'C' OR 'O' OR 'E' THEN 'Relocation'
        ELSE ls_request-trfunction ).
      ls_result-trstate = SWITCH #( ls_request-trstatus
        WHEN 'D' OR 'L' THEN 'Modifiable' WHEN 'O' THEN 'Releasing'
        WHEN 'R' OR 'N' THEN 'Released'   ELSE 'Unknown' ).

      ls_result-must_follow = REDUCE string( INIT s = `` FOR e IN lt_edges
                                              WHERE ( to_tr = ls_request-trkorr )
                                              NEXT s = COND #( WHEN s IS INITIAL THEN e-from_tr
                                                               ELSE |{ s }, { e-from_tr }| ) ).

      IF ls_request-excluded = abap_true.
        ls_result-sort_grp = COND #( WHEN ls_request-unimported = abap_true THEN 3 ELSE 4 ).
        ls_result-light    = COND #( WHEN lv_errors > 0 THEN icon_red_light ELSE icon_light_out ).
      ELSEIF ls_o-blocked = abap_true OR ls_request-blocker = abap_true.
        ls_result-sort_grp = 2.
        ls_result-light    = icon_red_light.
      ELSE.
        ls_result-sort_grp = 1.
        ls_result-light    = COND #( WHEN lv_errors > 0 OR ls_o-grp IS NOT INITIAL THEN icon_red_light
                                     WHEN lv_warnings > 0 THEN icon_yellow_light
                                     ELSE icon_green_light ).
      ENDIF.

      " recommendation = most severe finding (E before W before I)
      DATA(lt_ranked) = VALUE ty_ranked_t( ).
      LOOP AT lt_own INTO DATA(ls_own).
        APPEND VALUE #( rank = SWITCH #( ls_own-severity WHEN 'E' THEN 1 WHEN 'W' THEN 2 ELSE 3 )
                        idx  = sy-tabix
                        text = ls_own-text ) TO lt_ranked.
      ENDLOOP.
      SORT lt_ranked BY rank idx.
      IF lt_ranked IS NOT INITIAL.
        ls_result-recommendation = lt_ranked[ 1 ]-text.
        IF lines( lt_ranked ) > 1.
          ls_result-recommendation = |{ ls_result-recommendation } (+{ lines( lt_ranked ) - 1 } more)|.
        ENDIF.
      ELSE.
        ls_result-recommendation = `No conflicts found`.
      ENDIF.

      APPEND ls_result TO et_results.
    ENDLOOP.

    SORT et_results BY sort_grp seq imp_seq rel_seq trkorr.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* ABAP Unit: pure logic (analyzer, sequencer) with in-memory data
*----------------------------------------------------------------------*
CLASS ltc_sequencer DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO lcl_sequencer.
    METHODS setup.
    METHODS node
      IMPORTING iv_trkorr      TYPE trkorr
                iv_rank        TYPE i DEFAULT 80
                iv_stamp       TYPE timestamp DEFAULT 20261110090000
                iv_blocker     TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(rs_node) TYPE lcl_sequencer=>ty_node.
    METHODS hard_edge_orders_dependency FOR TESTING.
    METHODS tie_break_uses_rank_then_stamp FOR TESTING.
    METHODS soft_cycle_is_relaxed FOR TESTING.
    METHODS soft_relax_stays_on_cycle FOR TESTING.
    METHODS hard_cycle_is_grouped FOR TESTING.
    METHODS blocker_propagates FOR TESTING.
    METHODS excluded_nodes_are_ignored FOR TESTING.
ENDCLASS.

CLASS ltc_sequencer IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW #( ).
  ENDMETHOD.

  METHOD node.
    rs_node = VALUE #( trkorr = iv_trkorr rank = iv_rank stamp = iv_stamp blocker = iv_blocker ).
  ENDMETHOD.

  METHOD hard_edge_orders_dependency.
    DATA(lt_order) = mo_cut->sequence(
      it_nodes = VALUE #( ( node( iv_trkorr = 'DEVK000001' iv_rank = 80 ) )
                          ( node( iv_trkorr = 'DEVK000002' iv_rank = 20 ) ) )
      it_edges = VALUE #( ( from_tr = 'DEVK000001' to_tr = 'DEVK000002' hard = abap_true reason = 'x' ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_order[ trkorr = 'DEVK000001' ]-seq exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lt_order[ trkorr = 'DEVK000002' ]-seq exp = 2 ).
  ENDMETHOD.

  METHOD tie_break_uses_rank_then_stamp.
    DATA(lt_order) = mo_cut->sequence(
      it_nodes = VALUE #( ( node( iv_trkorr = 'DEVK000001' iv_rank = 80 ) )
                          ( node( iv_trkorr = 'DEVK000002' iv_rank = 20 ) )
                          ( node( iv_trkorr = 'DEVK000003' iv_rank = 20 iv_stamp = 20261109090000 ) ) )
      it_edges = VALUE #( ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_order[ trkorr = 'DEVK000003' ]-seq exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lt_order[ trkorr = 'DEVK000002' ]-seq exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = lt_order[ trkorr = 'DEVK000001' ]-seq exp = 3 ).
  ENDMETHOD.

  METHOD soft_cycle_is_relaxed.
    DATA(lt_order) = mo_cut->sequence(
      it_nodes = VALUE #( ( node( 'DEVK000001' ) ) ( node( 'DEVK000002' ) ) )
      it_edges = VALUE #( ( from_tr = 'DEVK000001' to_tr = 'DEVK000002' hard = abap_false reason = 'a' )
                          ( from_tr = 'DEVK000002' to_tr = 'DEVK000001' hard = abap_false reason = 'b' ) ) ).
    cl_abap_unit_assert=>assert_initial( lt_order[ trkorr = 'DEVK000001' ]-grp ).
    cl_abap_unit_assert=>assert_initial( lt_order[ trkorr = 'DEVK000002' ]-grp ).
    cl_abap_unit_assert=>assert_differs( act = lt_order[ trkorr = 'DEVK000001' ]-seq
                                         exp = lt_order[ trkorr = 'DEVK000002' ]-seq ).
  ENDMETHOD.

  METHOD soft_relax_stays_on_cycle.
    DATA(lt_order) = mo_cut->sequence(
      it_nodes = VALUE #( ( node( 'DEVK000001' ) ) ( node( 'DEVK000002' ) )
                          ( node( iv_trkorr = 'DEVK000003' iv_rank = 20 ) ) )
      it_edges = VALUE #( ( from_tr = 'DEVK000001' to_tr = 'DEVK000002' hard = abap_false reason = 'a' )
                          ( from_tr = 'DEVK000002' to_tr = 'DEVK000001' hard = abap_false reason = 'b' )
                          ( from_tr = 'DEVK000001' to_tr = 'DEVK000003' hard = abap_false reason = 'c' ) ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( lt_order[ trkorr = 'DEVK000001' ]-seq
                                               < lt_order[ trkorr = 'DEVK000003' ]-seq ) ).
  ENDMETHOD.

  METHOD hard_cycle_is_grouped.
    DATA(lt_order) = mo_cut->sequence(
      it_nodes = VALUE #( ( node( 'DEVK000001' ) ) ( node( 'DEVK000002' ) ) ( node( 'DEVK000003' ) ) )
      it_edges = VALUE #( ( from_tr = 'DEVK000001' to_tr = 'DEVK000002' hard = abap_true reason = 'a' )
                          ( from_tr = 'DEVK000002' to_tr = 'DEVK000001' hard = abap_true reason = 'b' )
                          ( from_tr = 'DEVK000002' to_tr = 'DEVK000003' hard = abap_true reason = 'c' ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_order[ trkorr = 'DEVK000001' ]-grp exp = `G1` ).
    cl_abap_unit_assert=>assert_equals( act = lt_order[ trkorr = 'DEVK000002' ]-grp exp = `G1` ).
    cl_abap_unit_assert=>assert_equals( act = lt_order[ trkorr = 'DEVK000001' ]-seq
                                        exp = lt_order[ trkorr = 'DEVK000002' ]-seq ).
    cl_abap_unit_assert=>assert_initial( lt_order[ trkorr = 'DEVK000003' ]-grp ).
    cl_abap_unit_assert=>assert_true( xsdbool( lt_order[ trkorr = 'DEVK000003' ]-seq
                                               > lt_order[ trkorr = 'DEVK000001' ]-seq ) ).
  ENDMETHOD.

  METHOD blocker_propagates.
    DATA(lt_order) = mo_cut->sequence(
      it_nodes = VALUE #( ( node( iv_trkorr = 'DEVK000001' iv_blocker = abap_true ) )
                          ( node( 'DEVK000002' ) )
                          ( node( 'DEVK000003' ) ) )
      it_edges = VALUE #( ( from_tr = 'DEVK000001' to_tr = 'DEVK000002' hard = abap_true reason = 'a' ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_order[ trkorr = 'DEVK000002' ]-blocked_by exp = 'DEVK000001' ).
    cl_abap_unit_assert=>assert_true( lt_order[ trkorr = 'DEVK000002' ]-blocked ).
    cl_abap_unit_assert=>assert_equals( act = lt_order[ trkorr = 'DEVK000003' ]-seq exp = 1 ).
  ENDMETHOD.

  METHOD excluded_nodes_are_ignored.
    DATA(ls_excluded) = node( 'DEVK000009' ).
    ls_excluded-excluded = abap_true.
    DATA(lt_order) = mo_cut->sequence(
      it_nodes = VALUE #( ( ls_excluded ) ( node( 'DEVK000001' ) ) )
      it_edges = VALUE #( ( from_tr = 'DEVK000009' to_tr = 'DEVK000001' hard = abap_true reason = 'a' ) ) ).
    cl_abap_unit_assert=>assert_false( xsdbool( line_exists( lt_order[ trkorr = 'DEVK000009' ] ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lt_order[ trkorr = 'DEVK000001' ]-seq exp = 1 ).
  ENDMETHOD.

ENDCLASS.

CLASS ltc_analyzer DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO lcl_analyzer.
    METHODS setup.
    METHODS header
      IMPORTING iv_trkorr        TYPE trkorr
                iv_strkorr       TYPE trkorr OPTIONAL
                iv_status        TYPE e070-trstatus DEFAULT 'D'
                iv_function      TYPE e070-trfunction DEFAULT 'K'
                iv_stamp         TYPE timestamp DEFAULT 20261110090000
      RETURNING VALUE(rs_header) TYPE ty_header.
    METHODS object
      IMPORTING iv_request       TYPE trkorr
                iv_object        TYPE e071-object
                iv_name          TYPE e071-obj_name
                iv_stamp         TYPE timestamp DEFAULT 20261110090000
                iv_new           TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(rs_object) TYPE ty_object.
    METHODS has_finding
      IMPORTING it_findings   TYPE ty_findings
                iv_request    TYPE trkorr
                iv_code       TYPE ty_finding-code
      RETURNING VALUE(rv_has) TYPE abap_bool.
    METHODS overlap_orders_older_first FOR TESTING.
    METHODS open_task_is_blocker FOR TESTING.
    METHODS objects_in_tasks_are_counted FOR TESTING.
    METHODS released_request_is_excluded FOR TESTING.
    METHODS usage_of_new_object_is_hard FOR TESTING.
    METHODS usage_of_changed_is_soft FOR TESTING.
    METHODS customizing_key_mask_overlaps FOR TESTING.
    METHODS task_selection_maps_to_request FOR TESTING.
    METHODS customizing_object_no_overlap FOR TESTING.
    METHODS whole_object_vs_part_edge FOR TESTING.
    METHODS inactive_object_is_error FOR TESTING.
    METHODS released_not_imported_error FOR TESTING.
    METHODS overlap_with_unimported FOR TESTING.
    METHODS history_not_imported_warns FOR TESTING.
    METHODS external_open_new_is_error FOR TESTING.
    METHODS external_open_changed_warns FOR TESTING.
    METHODS external_not_imported_error FOR TESTING.
    METHODS external_imported_is_quiet FOR TESTING.
    METHODS external_recent_unknown_warns FOR TESTING.
    METHODS local_object_is_error FOR TESTING.
    METHODS forgotten_object_is_error FOR TESTING.
    METHODS existing_in_target_is_quiet FOR TESTING.
    METHODS unimported_pair_import_edge FOR TESTING.
ENDCLASS.

CLASS ltc_analyzer IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW #( ).
  ENDMETHOD.

  METHOD header.
    rs_header = VALUE #( trkorr = iv_trkorr strkorr = iv_strkorr trfunction = iv_function
                         trstatus = iv_status tarsystem = 'QAS' as4user = 'TESTER'
                         request = COND #( WHEN iv_strkorr IS INITIAL THEN iv_trkorr ELSE iv_strkorr )
                         stamp = iv_stamp ).
  ENDMETHOD.

  METHOD object.
    rs_object = VALUE #( request = iv_request task = iv_request pgmid = 'R3TR'
                         object = iv_object obj_name = iv_name
                         parent_object = iv_object parent_name = iv_name
                         stamp = iv_stamp is_new = iv_new ).
  ENDMETHOD.

  METHOD has_finding.
    rv_has = xsdbool( line_exists( it_findings[ request = iv_request code = iv_code ] ) ).
  ENDMETHOD.

  METHOD overlap_orders_older_first.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( 'DEVK000001' ) ) ( header( 'DEVK000002' ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) ( CONV #( 'DEVK000002' ) ) )
      objects  = VALUE #( ( object( iv_request = 'DEVK000002' iv_object = 'CLAS' iv_name = 'ZCL_X'
                                    iv_stamp = 20261110140000 ) )
                          ( object( iv_request = 'DEVK000001' iv_object = 'CLAS' iv_name = 'ZCL_X'
                                    iv_stamp = 20261110090000 ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-edges ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-edges[ 1 ]-from_tr exp = 'DEVK000001' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-edges[ 1 ]-to_tr exp = 'DEVK000002' ).
    cl_abap_unit_assert=>assert_false( ls_result-edges[ 1 ]-hard ).
    cl_abap_unit_assert=>assert_true( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000001' iv_code = 'W009' ) ).
  ENDMETHOD.

  METHOD open_task_is_blocker.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( 'DEVK000001' ) ) ( header( iv_trkorr = 'DEVK000002' iv_strkorr = 'DEVK000001' ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) )
      objects  = VALUE #( ( object( iv_request = 'DEVK000001' iv_object = 'PROG' iv_name = 'ZP' ) ) ) ) ).
    cl_abap_unit_assert=>assert_true( ls_result-requests[ trkorr = 'DEVK000001' ]-blocker ).
    cl_abap_unit_assert=>assert_true( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000001' iv_code = 'E004' ) ).
  ENDMETHOD.

  METHOD objects_in_tasks_are_counted.
    DATA(ls_task_object) = object( iv_request = 'DEVK000001' iv_object = 'PROG' iv_name = 'ZP' ).
    ls_task_object-task = 'DEVK000002'.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( 'DEVK000001' ) )
                          ( header( iv_trkorr = 'DEVK000002' iv_strkorr = 'DEVK000001' iv_status = 'R' ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) )
      objects  = VALUE #( ( ls_task_object ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-requests[ trkorr = 'DEVK000001' ]-objcount exp = 1 ).
    cl_abap_unit_assert=>assert_false( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000001' iv_code = 'W005' ) ).
  ENDMETHOD.

  METHOD released_request_is_excluded.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( iv_trkorr = 'DEVK000001' iv_status = 'R' ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) ) ) ).
    cl_abap_unit_assert=>assert_true( ls_result-requests[ trkorr = 'DEVK000001' ]-excluded ).
  ENDMETHOD.

  METHOD usage_of_new_object_is_hard.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( 'DEVK000001' ) ) ( header( 'DEVK000002' ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) ( CONV #( 'DEVK000002' ) ) )
      objects  = VALUE #( ( object( iv_request = 'DEVK000001' iv_object = 'DTEL' iv_name = 'ZDE_STATUS' iv_new = abap_true ) )
                          ( object( iv_request = 'DEVK000002' iv_object = 'CLAS' iv_name = 'ZCL_ORDER' ) ) )
      refs     = VALUE #( ( request = 'DEVK000002' user_object = 'CLAS ZCL_ORDER' used_name = 'ZDE_STATUS' ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-edges[ 1 ]-from_tr exp = 'DEVK000001' ).
    cl_abap_unit_assert=>assert_true( ls_result-edges[ 1 ]-hard ).
  ENDMETHOD.

  METHOD usage_of_changed_is_soft.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( 'DEVK000001' ) ) ( header( 'DEVK000002' ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) ( CONV #( 'DEVK000002' ) ) )
      objects  = VALUE #( ( object( iv_request = 'DEVK000001' iv_object = 'DTEL' iv_name = 'ZDE_STATUS' ) )
                          ( object( iv_request = 'DEVK000002' iv_object = 'CLAS' iv_name = 'ZCL_ORDER' ) ) )
      refs     = VALUE #( ( request = 'DEVK000002' user_object = 'CLAS ZCL_ORDER' used_name = 'ZDE_STATUS' ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_result-edges[ 1 ]-hard ).
  ENDMETHOD.

  METHOD customizing_key_mask_overlaps.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( iv_trkorr = 'DEVK000001' iv_function = 'W' )
                          ) ( header( iv_trkorr = 'DEVK000002' iv_function = 'W' iv_stamp = 20261110150000 ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) ( CONV #( 'DEVK000002' ) ) )
      keys     = VALUE #( ( request = 'DEVK000001' tabname = 'ZORD_CFG' tabkey = '100*' stamp = 20261110090000 )
                          ( request = 'DEVK000002' tabname = 'ZORD_CFG' tabkey = '100A' stamp = 20261110150000 ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-edges[ 1 ]-from_tr exp = 'DEVK000001' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-edges[ 1 ]-to_tr exp = 'DEVK000002' ).
  ENDMETHOD.

  METHOD customizing_object_no_overlap.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( 'DEVK000001' ) ) ( header( 'DEVK000002' ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) ( CONV #( 'DEVK000002' ) ) )
      objects  = VALUE #( ( object( iv_request = 'DEVK000001' iv_object = 'TABU' iv_name = 'ZORD_CFG' ) )
                          ( object( iv_request = 'DEVK000002' iv_object = 'TABU' iv_name = 'ZORD_CFG' ) ) ) ) ).
    cl_abap_unit_assert=>assert_initial( ls_result-edges ).
  ENDMETHOD.

  METHOD whole_object_vs_part_edge.
    DATA(ls_part) = object( iv_request = 'DEVK000002' iv_object = 'METH' iv_name = 'ZCL_X~M' ).
    ls_part-pgmid         = 'LIMU'.
    ls_part-parent_object = 'CLAS'.
    ls_part-parent_name   = 'ZCL_X'.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( 'DEVK000001' ) ) ( header( 'DEVK000002' ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) ( CONV #( 'DEVK000002' ) ) )
      objects  = VALUE #( ( object( iv_request = 'DEVK000001' iv_object = 'CLAS' iv_name = 'ZCL_X' ) )
                          ( ls_part ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-edges ) exp = 1 ).
  ENDMETHOD.

  METHOD inactive_object_is_error.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( 'DEVK000001' ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) )
      objects  = VALUE #( ( object( iv_request = 'DEVK000001' iv_object = 'PROG' iv_name = 'ZP' ) ) )
      inactive = VALUE #( ( object = 'REPS' obj_name = 'ZP' uname = 'TESTER' ) ) ) ).
    cl_abap_unit_assert=>assert_true( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000001' iv_code = 'E016' ) ).
  ENDMETHOD.

  METHOD released_not_imported_error.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( iv_trkorr = 'DEVK000001' iv_status = 'R' ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) )
      imports  = VALUE #( ( request = 'DEVK000001' state = 'N' ) ) ) ).
    cl_abap_unit_assert=>assert_true( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000001' iv_code = 'E017' ) ).
  ENDMETHOD.

  METHOD overlap_with_unimported.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( iv_trkorr = 'DEVK000001' iv_status = 'R' ) ) ( header( 'DEVK000002' ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) ( CONV #( 'DEVK000002' ) ) )
      objects  = VALUE #( ( object( iv_request = 'DEVK000001' iv_object = 'CLAS' iv_name = 'ZCL_X' ) )
                          ( object( iv_request = 'DEVK000002' iv_object = 'CLAS' iv_name = 'ZCL_X' ) ) )
      imports  = VALUE #( ( request = 'DEVK000001' state = 'N' ) ) ) ).
    cl_abap_unit_assert=>assert_initial( ls_result-edges ).
    cl_abap_unit_assert=>assert_true( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000002' iv_code = 'W017' ) ).
  ENDMETHOD.

  METHOD history_not_imported_warns.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( 'DEVK000001' ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) )
      objects  = VALUE #( ( object( iv_request = 'DEVK000001' iv_object = 'CLAS' iv_name = 'ZCL_X' ) ) )
      hist     = VALUE #( ( pgmid = 'R3TR' object = 'CLAS' obj_name = 'ZCL_X' request = 'DEVK000009' ) )
      imports  = VALUE #( ( request = 'DEVK000009' state = 'N' ) ) ) ).
    cl_abap_unit_assert=>assert_true( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000001' iv_code = 'W018' ) ).
  ENDMETHOD.

  METHOD external_open_new_is_error.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers   = VALUE #( ( header( 'DEVK000001' ) ) )
      selected  = VALUE #( ( CONV #( 'DEVK000001' ) ) )
      refs      = VALUE #( ( request = 'DEVK000001' user_object = 'CLAS ZCL_ORDER' used_name = 'ZDE_STATUS' ) )
      suppliers = VALUE #( ( name = 'ZDE_STATUS' request = 'DEVK000999' status = 'D' owner = 'BEN' ) ) ) ).
    cl_abap_unit_assert=>assert_true( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000001' iv_code = 'E021' ) ).
  ENDMETHOD.

  METHOD external_open_changed_warns.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers   = VALUE #( ( header( 'DEVK000001' ) ) )
      selected  = VALUE #( ( CONV #( 'DEVK000001' ) ) )
      refs      = VALUE #( ( request = 'DEVK000001' user_object = 'CLAS ZCL_ORDER' used_name = 'ZDE_STATUS' ) )
      suppliers = VALUE #( ( name = 'ZDE_STATUS' request = 'DEVK000999' status = 'D' owner = 'BEN' )
                           ( name = 'ZDE_STATUS' request = 'DEVK000500' status = 'R' owner = 'ANNA' ) ) ) ).
    cl_abap_unit_assert=>assert_true( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000001' iv_code = 'W021' ) ).
    cl_abap_unit_assert=>assert_false( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000001' iv_code = 'E021' ) ).
  ENDMETHOD.

  METHOD external_not_imported_error.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers   = VALUE #( ( header( 'DEVK000001' ) ) )
      selected  = VALUE #( ( CONV #( 'DEVK000001' ) ) )
      refs      = VALUE #( ( request = 'DEVK000001' user_object = 'CLAS ZCL_ORDER' used_name = 'ZDE_STATUS' ) )
      suppliers = VALUE #( ( name = 'ZDE_STATUS' request = 'DEVK000999' status = 'R' owner = 'BEN' changed = sy-datum ) )
      imports   = VALUE #( ( request = 'DEVK000999' state = 'N' ) ) ) ).
    cl_abap_unit_assert=>assert_true( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000001' iv_code = 'E022' ) ).
  ENDMETHOD.

  METHOD external_imported_is_quiet.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers   = VALUE #( ( header( 'DEVK000001' ) ) )
      selected  = VALUE #( ( CONV #( 'DEVK000001' ) ) )
      refs      = VALUE #( ( request = 'DEVK000001' user_object = 'CLAS ZCL_ORDER' used_name = 'ZDE_STATUS' ) )
      suppliers = VALUE #( ( name = 'ZDE_STATUS' request = 'DEVK000999' status = 'R' owner = 'BEN' changed = sy-datum ) )
      imports   = VALUE #( ( request = 'DEVK000999' state = 'I' ) ) ) ).
    cl_abap_unit_assert=>assert_false( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000001' iv_code = 'E022' ) ).
    cl_abap_unit_assert=>assert_false( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000001' iv_code = 'W022' ) ).
  ENDMETHOD.

  METHOD external_recent_unknown_warns.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers   = VALUE #( ( header( 'DEVK000001' ) ) )
      selected  = VALUE #( ( CONV #( 'DEVK000001' ) ) )
      refs      = VALUE #( ( request = 'DEVK000001' user_object = 'CLAS ZCL_ORDER' used_name = 'ZDE_STATUS' ) )
      suppliers = VALUE #( ( name = 'ZDE_STATUS' request = 'DEVK000999' status = 'R' owner = 'BEN' changed = sy-datum ) ) ) ).
    cl_abap_unit_assert=>assert_true( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000001' iv_code = 'W022' ) ).
  ENDMETHOD.

  METHOD local_object_is_error.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( 'DEVK000001' ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) )
      refs     = VALUE #( ( request = 'DEVK000001' user_object = 'CLAS ZCL_ORDER' used_name = 'ZCL_LOC' ) )
      locals   = VALUE #( ( name = 'ZCL_LOC' devclass = '$TMP' ) ) ) ).
    cl_abap_unit_assert=>assert_true( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000001' iv_code = 'E023' ) ).
  ENDMETHOD.

  METHOD forgotten_object_is_error.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( 'DEVK000001' ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) )
      refs     = VALUE #( ( request = 'DEVK000001' user_object = 'CLAS ZCL_ORDER' used_name = 'ZCL_OLD' ) )
      locals   = VALUE #( ( name = 'ZCL_OLD' devclass = 'ZDEV' ) )
      checked  = abap_true ) ).
    cl_abap_unit_assert=>assert_true( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000001' iv_code = 'E024' ) ).
  ENDMETHOD.

  METHOD existing_in_target_is_quiet.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( 'DEVK000001' ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) )
      refs     = VALUE #( ( request = 'DEVK000001' user_object = 'CLAS ZCL_ORDER' used_name = 'ZCL_OLD' ) )
      locals   = VALUE #( ( name = 'ZCL_OLD' devclass = 'ZDEV' ) )
      existing = VALUE #( ( `ZCL_OLD` ) )
      checked  = abap_true ) ).
    cl_abap_unit_assert=>assert_false( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000001' iv_code = 'E024' ) ).
  ENDMETHOD.

  METHOD unimported_pair_import_edge.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( iv_trkorr = 'DEVK000001' iv_status = 'R' ) )
                          ( header( iv_trkorr = 'DEVK000002' iv_status = 'R' ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) ( CONV #( 'DEVK000002' ) ) )
      objects  = VALUE #( ( object( iv_request = 'DEVK000002' iv_object = 'CLAS' iv_name = 'ZCL_X'
                                    iv_stamp = 20261110140000 ) )
                          ( object( iv_request = 'DEVK000001' iv_object = 'CLAS' iv_name = 'ZCL_X'
                                    iv_stamp = 20261110090000 ) ) )
      imports  = VALUE #( ( request = 'DEVK000001' state = 'N' ) ( request = 'DEVK000002' state = 'N' ) ) ) ).
    cl_abap_unit_assert=>assert_initial( ls_result-edges ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-import_edges ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-import_edges[ 1 ]-from_tr exp = 'DEVK000001' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-import_edges[ 1 ]-to_tr exp = 'DEVK000002' ).
  ENDMETHOD.

  METHOD task_selection_maps_to_request.
    DATA(ls_result) = mo_cut->analyze( VALUE #(
      headers  = VALUE #( ( header( 'DEVK000001' ) ) ( header( iv_trkorr = 'DEVK000002' iv_strkorr = 'DEVK000001' ) ) )
      selected = VALUE #( ( CONV #( 'DEVK000001' ) ) )
      task_map = VALUE #( ( task = 'DEVK000002' request = 'DEVK000001' ) ) ) ).
    cl_abap_unit_assert=>assert_true( has_finding( it_findings = ls_result-findings iv_request = 'DEVK000001' iv_code = 'I002' ) ).
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Selection screen and start
*----------------------------------------------------------------------*
DATA gv_trkorr TYPE e070-trkorr.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE gv_title.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) lbl_trk FOR FIELD s_trkorr.
    SELECT-OPTIONS s_trkorr FOR gv_trkorr OBLIGATORY.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) lbl_cro FOR FIELD p_cross.
    PARAMETERS p_cross AS CHECKBOX DEFAULT abap_true.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) lbl_dst FOR FIELD p_dest.
    PARAMETERS p_dest TYPE rfcdest.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b1.

INITIALIZATION.
  gv_title  = 'Transport release sequence'.
  lbl_trk = 'Transport requests / tasks'.
  lbl_cro = 'Analyse object dependencies'.
  lbl_dst = 'Target RFC dest. (import chk)'.

START-OF-SELECTION.
  lcl_app=>run( it_range = s_trkorr[] iv_cross = p_cross iv_dest = p_dest ).
