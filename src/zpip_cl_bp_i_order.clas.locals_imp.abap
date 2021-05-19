CLASS lhc_Order DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS validateDeliveryDate FOR VALIDATE ON SAVE IMPORTING keys FOR Order~validateDeliveryDate.

    METHODS calculateOrderID FOR DETERMINE ON MODIFY IMPORTING keys FOR Order~calculateOrderID.
    METHODS calculateAmounts FOR DETERMINE ON SAVE IMPORTING keys FOR Order~calculateAmounts.

ENDCLASS.
**********************************************************************
**********************************************************************
CLASS lhc_Order IMPLEMENTATION.
*----------------------------
  METHOD calculateOrderID.

    DATA: lv_maxOrderID    TYPE zpip_order_id,
          lt_UpdateOrderID TYPE TABLE FOR UPDATE zpip_i_product\\Order.

    READ ENTITIES OF zpip_i_product IN LOCAL MODE
      ENTITY  Order BY \_Market
        FIELDS ( MrktUuid ) WITH CORRESPONDING #( keys )
      RESULT DATA(picedMarketID).

*---
    LOOP AT picedMarketID ASSIGNING FIELD-SYMBOL(<fs_picedMarketID>).

      READ ENTITIES OF zpip_i_product IN LOCAL MODE
        ENTITY Market BY \_MarketOrder
          FIELDS ( Orderid ) WITH VALUE #( ( %tky = <fs_picedMarketID>-%tky ) )
        RESULT DATA(picedOrderID).

      lv_maxOrderID = 0.
      LOOP AT picedOrderID ASSIGNING FIELD-SYMBOL(<fs_picedOrderID>).
        IF <fs_picedOrderID>-Orderid > lv_maxOrderID.
          lv_maxOrderID = <fs_picedOrderID>-Orderid.
        ENDIF.
      ENDLOOP.

      LOOP AT picedOrderID ASSIGNING <fs_picedOrderID> WHERE Orderid IS INITIAL.
         lv_maxOrderID += 1.
         APPEND VALUE #(
                         %tky    = <fs_picedOrderID>-%tky
                         orderid = lv_maxOrderID
                       )
                         TO lt_UpdateOrderID.
      ENDLOOP.
    ENDLOOP.
*---
    MODIFY ENTITIES OF zpip_i_product IN LOCAL MODE
      ENTITY Order
        UPDATE FIELDS ( Orderid ) WITH lt_UpdateOrderID
      REPORTED DATA(update_reported).

    reported = CORRESPONDING #( DEEP update_reported ).

  ENDMETHOD.

**********************************************************************
  METHOD CalculateAmounts.


    TYPES: BEGIN OF ty_for_transefer,
             Netamount    TYPE zpip_netamount,
             Grossamount  TYPE zpip_grossamount,
             Amountcurr   TYPE waers_curc,
             DeliveryDate TYPE zpip_delivery_date,
             CalendarYear TYPE zpip_year,
           END OF ty_for_transefer.

    DATA: lt_for_transefer  TYPE TABLE FOR UPDATE zpip_i_product\\Order.

      READ ENTITIES OF zpip_i_product IN LOCAL MODE
        ENTITY Product
          FIELDS ( Price
                   PriceCurrency
                   Taxrate       ) WITH CORRESPONDING #( keys )
          RESULT DATA(picedProdPrice).

*---
    LOOP AT picedProdPrice ASSIGNING FIELD-SYMBOL(<fs_picedProdPrice>)  .

      READ ENTITIES OF zpip_i_product IN LOCAL MODE
        ENTITY Order
          FIELDS ( Quantity
                   Netamount
                   DeliveryDate ) WITH CORRESPONDING #( keys )
        RESULT DATA(picedOrders).


      LOOP AT picedOrders ASSIGNING FIELD-SYMBOL(<fs_picedOrders>) .
         APPEND VALUE #(
                         %tky         = <fs_picedOrders>-%tky
                         Netamount    = <fs_picedOrders>-Quantity * <fs_picedProdPrice>-Price
                         Grossamount  = ( <fs_picedOrders>-Quantity * <fs_picedProdPrice>-Price * 107 / 100 ) *
                                        ( <fs_picedProdPrice>-Taxrate + 100 ) / 100
                         Amountcurr   = <fs_picedProdPrice>-PriceCurrency
                         DeliveryDate = <fs_picedOrders>-DeliveryDate
                         CalendarYear = <fs_picedOrders>-DeliveryDate+0(4)
                       )
                         TO lt_for_transefer.
      ENDLOOP.

    ENDLOOP.
*---
      LOOP AT lt_for_transefer ASSIGNING FIELD-SYMBOL(<fs_lt_for_transefer>).
        IF NOT line_exists( picedOrders[ Netamount    = <fs_lt_for_transefer>-Netamount ] ) OR
           NOT line_exists( picedOrders[ DeliveryDate = <fs_lt_for_transefer>-DeliveryDate ] ).

          MODIFY ENTITIES OF zpip_i_product IN LOCAL MODE
                 ENTITY Order
                   UPDATE FIELDS ( Netamount
                                   Grossamount
                                   Amountcurr
                                   DeliveryDate
                                   CalendarYear ) WITH lt_for_transefer
                   REPORTED DATA(update_reported).

          reported = CORRESPONDING #( DEEP update_reported ).
        ENDIF.
      ENDLOOP.

  ENDMETHOD.
**********************************************************************
  METHOD validateDeliveryDate.

    READ ENTITIES OF zpip_i_product IN LOCAL MODE
      ENTITY Market
        FIELDS ( Startdate
                 Enddate   ) WITH CORRESPONDING #( keys )
        RESULT DATA(picedMarketDate).

    LOOP AT picedMarketDate ASSIGNING FIELD-SYMBOL(<fs_picedMarketDate>).
      READ ENTITIES OF zpip_i_product IN LOCAL MODE
        ENTITY Market BY \_MarketOrder
          FIELDS ( DeliveryDate ) WITH VALUE #( ( %tky = <fs_picedMarketDate>-%tky )  )
          RESULT DATA(picedOrderDate).

      LOOP AT picedOrderDate ASSIGNING FIELD-SYMBOL(<fs_picedOrderDate>).
        APPEND VALUE #(
                        %tky        = <fs_picedOrderDate>-%tky
                        %state_area = 'VALIDATE_DELIVERY_DATE'
                      )
                        TO reported-order.
        IF <fs_picedOrderDate>-DeliveryDate > <fs_picedMarketDate>-Enddate OR
           <fs_picedOrderDate>-DeliveryDate < <fs_picedMarketDate>-Startdate.
          APPEND VALUE #(
                          %tky               = <fs_picedOrderDate>-%tky
                          %state_area        = 'VALIDATE_DELIVERY_DATE'
                          %msg               = NEW zcx_pip_product(
                                                                    severity  = if_abap_behv_message=>severity-error
                                                                    textid    = zcx_pip_product=>invalid_delivery_date
                                                                    Startdate = <fs_picedMarketDate>-Startdate
                                                                    Enddate   = <fs_picedMarketDate>-Enddate
                                                                  )
                          %element-DeliveryDate = if_abap_behv=>mk-on
                        )
                          TO reported-order.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.
**********************************************************************
ENDCLASS.
