CLASS lhc_Product DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
*----------------------------
    CONSTANTS:
      BEGIN OF phase_id,
        plan TYPE int1 VALUE 1,
        dev  TYPE int1 VALUE 2,
        prod TYPE int1 VALUE 3,
        out  TYPE int1 VALUE 4,
      END OF phase_id.

*----------------------------
    METHODS SetFirstPhase     FOR DETERMINE ON SAVE IMPORTING keys FOR Product~SetFirstPhase.

    METHODS validateProdGroup FOR VALIDATE  ON SAVE IMPORTING keys FOR Product~validateProdGroup.
    METHODS validateProdDupl  FOR VALIDATE  ON SAVE IMPORTING keys FOR Product~validateProdDupl.

    METHODS copyProduct FOR MODIFY IMPORTING keys FOR ACTION Product~copyProduct  RESULT result.
    METHODS changePhase FOR MODIFY IMPORTING keys FOR ACTION Product~changePhase  RESULT result.

*add for Draft
    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Product RESULT result.

*----------------------------
ENDCLASS.
**********************************************************************
**********************************************************************
CLASS lhc_Product IMPLEMENTATION.
**********************************************************************
  METHOD SetFirstPhase.

    READ ENTITIES OF zpip_i_product IN LOCAL MODE
      ENTITY Product
        FIELDS ( Phaseid ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_product).

    DELETE lt_product WHERE Phaseid IS NOT INITIAL.
    CHECK lt_product IS NOT INITIAL.

    MODIFY ENTITIES OF zpip_i_product IN LOCAL MODE
      ENTITY Product
        UPDATE FIELDS ( Phaseid )
          WITH VALUE #(
                        FOR product IN lt_product

                          ( %tky    = product-%tky
                            Phaseid = phase_id-plan )
                      )
    REPORTED DATA(update_reported).

    reported = CORRESPONDING #( DEEP update_reported ).

  ENDMETHOD.
**********************************************************************
  METHOD validateProdGroup.

    DATA prodgroups TYPE SORTED TABLE OF zpip_d_prod_grp WITH UNIQUE KEY Pgid.

    READ ENTITIES OF zpip_i_product IN LOCAL MODE
      ENTITY Product
        FIELDS ( Pgid )
          WITH CORRESPONDING #( keys )
      RESULT DATA(products).

    prodgroups = CORRESPONDING #( products DISCARDING DUPLICATES MAPPING pgid =  Pgid EXCEPT * ).
    DELETE prodgroups WHERE pgid IS INITIAL.

    IF prodgroups IS NOT INITIAL.
      SELECT FROM zpip_d_prod_grp FIELDS Pgid
        FOR ALL ENTRIES IN @prodgroups
          WHERE pgid = @prodgroups-pgid
        INTO TABLE @DATA(prodgroups_db).
    ENDIF.

    LOOP AT products INTO DATA(product).
      APPEND VALUE #(
                      %tky        = product-%tky
                      %state_area = 'VALIDATE_PRODGROUP'
      )
        TO reported-product.

      IF product-pgid IS INITIAL OR NOT line_exists( prodgroups_db[ pgid = product-pgid ] ).
        APPEND VALUE #( %tky = product-%tky ) TO failed-product.
        APPEND VALUE #(
                        %tky          = product-%tky
                        %state_area   = 'VALIDATE_PRODGROUP'
                        %msg          = NEW zcx_pip_product( severity = if_abap_behv_message=>severity-error
                                                             textid   = zcx_pip_product=>prod_group_unknown
                                                             pgid     = product-pgid )
                        %element-pgid = if_abap_behv=>mk-on
        )
          TO reported-product.
      ENDIF.
    ENDLOOP.


  ENDMETHOD.
**********************************************************************
  METHOD validateProdDupl.

    READ ENTITIES OF zpip_i_product IN LOCAL MODE
      ENTITY Product
        FIELDS ( Prodid ) WITH CORRESPONDING #( keys )
      RESULT DATA(products).

    SELECT FROM zpip_i_product FIELDS Prodid
      FOR ALL ENTRIES IN @products
         WHERE Prodid = @products-Prodid
      INTO TABLE @DATA(prodgroups_db).

    LOOP AT products INTO DATA(product).
      IF line_exists( prodgroups_db[ Prodid = product-Prodid ] ).
        APPEND VALUE #( %tky = product-%tky ) TO failed-product.
        APPEND VALUE #(
                        %tky          = product-%tky
                        %state_area   = 'VALIDATE_PROD_DUPL'
                        %msg          = NEW zcx_pip_product( severity = if_abap_behv_message=>severity-error
                                                             textid   = zcx_pip_product=>prod_dupl
                                                             Prodid   = product-Prodid )
                        %element-Prodid = if_abap_behv=>mk-on
        )
          TO reported-product.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.
**********************************************************************
  METHOD copyProduct.

    SELECT MAX( prodid )
      FROM zpip_d_product
      INTO @DATA(lv_prodid).

    DATA(lv_today) = cl_abap_context_info=>get_system_time( ).
    DATA(lv_user)  = cl_abap_context_info=>get_user_alias( ).

    READ ENTITIES OF zpip_i_product IN LOCAL MODE
       ENTITY Product
         ALL FIELDS
           WITH CORRESPONDING #( keys )
         RESULT DATA(lt_read_result)
         FAILED      failed
         REPORTED    reported.

    TRY.
      DATA(lv_id)  = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error .
    ENDTRY.

    DATA lt_created TYPE TABLE FOR CREATE zpip_i_product\\Product.

    lt_created = VALUE #( FOR ls_read_result IN lt_read_result INDEX INTO idx
                            (
                              ProdUuid      = lv_id
                              Prodid        = conv string( lv_prodid + idx )
                              Phaseid       = 1
                              Pgid          = ls_read_result-Pgid
                              Height        = ls_read_result-Height
                              Depth         = ls_read_result-Depth
                              Width         = ls_read_result-Width
                              SizeUom       = ls_read_result-SizeUom
                              Price         = ls_read_result-Price
                              PriceCurrency = ls_read_result-PriceCurrency
                              Taxrate       = ls_read_result-Taxrate
                              ChangeTime    = lv_today
                              CreationTime  = lv_today
                              CreatedBy     = lv_user
                              ChangedBy     = lv_user
                            )
                        ).

    MODIFY ENTITIES OF zpip_i_product IN LOCAL MODE
      ENTITY Product
        CREATE FIELDS (
                        ProdUuid
                        Prodid
                        Phaseid
                        Pgid
                        Height
                        Depth
                        Width
                        SizeUom
                        Price
                        PriceCurrency
                        Taxrate
                        ChangeTime
                        CreationTime
                        CreatedBy
                        ChangedBy
                      )
          WITH lt_created
        MAPPED   mapped
        FAILED   failed
        REPORTED reported.

    result = VALUE #( FOR ls_created IN lt_created INDEX INTO idx
                        (
                          %tky   = keys[ idx ]-%tky
                          %param = CORRESPONDING #( ls_created )
                        )
                    ) .

  ENDMETHOD.
**********************************************************************
  METHOD changePhase.

    READ ENTITIES OF zpip_i_product IN LOCAL MODE
      ENTITY Product
       FIELDS ( ProdUuid Prodid Phaseid )
       WITH CORRESPONDING #( keys )
      RESULT DATA(pickedProduct)
      ENTITY Product by \_Market
        FIELDS ( ProdUuid MrktUuid Status Enddate )
        WITH CORRESPONDING #( keys )
      RESULT DATA(pickedMarket)
      FAILED failed.
*---
    LOOP AT pickedProduct ASSIGNING FIELD-SYMBOL(<fs_pickedProduct>).
*-----
      IF <fs_pickedProduct>-Phaseid = 1.

        """"""""""""""""""""""""""""""""""""""""""""""""""""""
        IF pickedmarket IS INITIAL.
          APPEND VALUE #( %tky = <fs_pickedProduct>-%tky ) TO failed-product.
          APPEND VALUE #(
                          %tky            = <fs_pickedProduct>-%tky
                          %state_area     = 'VALIDATE_PHASE'
                          %msg            = NEW zcx_pip_product(
                                                                 severity = if_abap_behv_message=>severity-error
                                                                 textid   = zcx_pip_product=>prod_phase
                                                                 Phaseid  = <fs_pickedProduct>-Phaseid
                                                               )
                          %element-Phaseid = if_abap_behv=>mk-on
                        )
                          TO reported-product.
        ELSE.
          MODIFY ENTITIES OF zpip_i_product IN LOCAL MODE
            ENTITY Product
               UPDATE
                 FIELDS ( Phaseid )
                 WITH VALUE #( FOR key IN keys
                                 (
                                   %tky    = key-%tky
                                   Phaseid = phase_id-dev
                                 )
                             )
            FAILED   failed
            REPORTED reported.
          READ ENTITIES OF zpip_i_product IN LOCAL MODE
            ENTITY Product
              ALL FIELDS WITH CORRESPONDING #( keys )
            RESULT DATA(resultLine).
          result = VALUE #( FOR productResultLine IN resultLine
                              (
                                %tky   = productResultLine-%tky
                                %param = productResultLine
                              )
                          ).
        """"""""""""""""""""""""""""""""""""""""""""""""""""""
        ENDIF.
*-----
      ELSEIF <fs_pickedProduct>-Phaseid = 2.
*-----
        LOOP AT pickedMarket ASSIGNING FIELD-SYMBOL(<fs_pickedMarket>).
          """"""""""""""""""""""""""""""""""""""""""""""""""""""
          IF <fs_pickedMarket>-Status = 'X'.
            MODIFY ENTITIES OF zpip_i_product IN LOCAL MODE
              ENTITY Product
                UPDATE
                  FIELDS ( Phaseid )
                  WITH VALUE #( FOR key IN keys
                                  (
                                    %tky    = key-%tky
                                    Phaseid = phase_id-prod
                                  )
                              )
                  FAILED   failed
                  REPORTED reported.
            READ ENTITIES OF zpip_i_product IN LOCAL MODE
              ENTITY Product
                ALL FIELDS WITH CORRESPONDING #( keys )
              RESULT resultLine.
            result = VALUE #( FOR productResultLine IN resultLine
                                (
                                  %tky   = productResultLine-%tky
                                  %param = productResultLine
                                )
                            ).
          ELSE.
             APPEND VALUE #( %tky = <fs_pickedProduct>-%tky ) TO failed-product.
             APPEND VALUE #(
                             %tky            = <fs_pickedProduct>-%tky
                             %state_area     = 'VALIDATE_PHASE'
                             %msg            = NEW zcx_pip_product(
                                                                    severity = if_abap_behv_message=>severity-error
                                                                    textid   = zcx_pip_product=>prod_phase
                                                                    Phaseid  = <fs_pickedProduct>-Phaseid
                                                                  )
                             %element-Phaseid = if_abap_behv=>mk-on
                           )
                             TO reported-product.

          ENDIF.
          """"""""""""""""""""""""""""""""""""""""""""""""""""""
        ENDLOOP.
*-----
      ELSEIF <fs_pickedProduct>-Phaseid = 3.
*-----
        DATA lt_checkDates TYPE TABLE FOR CREATE zpip_i_product\\Market.
*        DATA(lv_today) = SY-DATUM.
        DATA(lv_today) = cl_abap_context_info=>get_system_date( ).

        LOOP AT pickedMarket ASSIGNING <fs_pickedMarket>.
          IF <fs_pickedMarket>-Enddate > lv_today .
            lt_checkDates = VALUE #( FOR ls_read_result IN pickedMarket
                                     ( enddate = <fs_pickedMarket>-Enddate )
                                   ).
          ENDIF.
        ENDLOOP.
        """"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
        IF lt_checkDates IS INITIAL.
          MODIFY ENTITIES OF zpip_i_product IN LOCAL MODE
            ENTITY Product
              UPDATE
                FIELDS ( Phaseid )
                WITH VALUE #( FOR key IN keys
                                (
                                  %tky    = key-%tky
                                  Phaseid = phase_id-out
                                )
                            )
            FAILED   failed
            REPORTED reported.
          READ ENTITIES OF zpip_i_product IN LOCAL MODE
            ENTITY Product
              ALL FIELDS WITH CORRESPONDING #( keys )
            RESULT resultLine.
          result = VALUE #( FOR productResultLine IN resultLine
                              (
                                %tky   = productResultLine-%tky
                                %param = productResultLine
                              )
                          ).
        ELSE.
            APPEND VALUE #( %tky = <fs_pickedProduct>-%tky ) TO failed-product.
            APPEND VALUE #(
                            %tky            = <fs_pickedProduct>-%tky
                            %state_area     = 'VALIDATE_PHASE'
                              %msg            = NEW zcx_pip_product(
                                                                     severity = if_abap_behv_message=>severity-error
                                                                     textid   = zcx_pip_product=>prod_phase
                                                                     Phaseid  = <fs_pickedProduct>-Phaseid
                                                                   )
                              %element-Phaseid = if_abap_behv=>mk-on
                            )
                              TO reported-product.
          ENDIF.
          """"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
*-----
      ELSEIF <fs_pickedProduct>-Phaseid = 4.
*-----
        APPEND VALUE #( %tky = <fs_pickedProduct>-%tky ) TO failed-product.
        APPEND VALUE #(
                        %tky            = <fs_pickedProduct>-%tky
                        %state_area     = 'VALIDATE_PHASE'
                        %msg            = NEW zcx_pip_product(
                                                               severity = if_abap_behv_message=>severity-error
                                                               textid   = zcx_pip_product=>prod_last_phase
                                                             )
                        %element-Phaseid = if_abap_behv=>mk-on
                      )
                        TO reported-product.
      ENDIF.
*-----
    ENDLOOP.
*---
  ENDMETHOD.
**********************************************************************

  METHOD get_instance_features.
  ENDMETHOD.

ENDCLASS.
***********
