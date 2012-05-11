\ DebXO installer script

: choose-nand-item
   menu-done
   ." Nand" cr
;

: choose-emmc-item
   menu-done
   ." EMMC" cr
;

: choose-sd-item
   menu-done
   ." SD" cr
;

: choose-usb-item
   menu-done
   ." USB" cr
;

: choose-usb-item-0
   menu-done
   ." USB #1" cr
;
: choose-usb-item-1
   menu-done
   ." USB #2" cr
;
: choose-usb-item-2
   menu-done
   ." USB #3" cr
;
: choose-usb-item-3
   menu-done
   ." USB #4" cr
;

0 value nr-targets

: has-target?  ( devspec$ -- flag )
   open-dev                                     ( ih )
   ?dup 0<> if
      close-dev
      nr-targets 1+ to nr-targets
      true
   else
      false
   then
;

: disk-size  ( devspec$ -- #MB )
   open-dev ?dup 0<> if                         ( ih )
      dup " #blocks" rot $call-method           ( ih #blocks )
      ?dup 0<> if
         \ we're assuming a block size of 512 bytes
         d# 512 um*                             ( ih #bytes )
         d# 1,000,000 um/mod                    ( ih rem #MB )
         rot close-dev swap drop                ( #MB )
      else
         drop
         0  \ TODO
\      dup " block-size" rot $call-method        ( ih  size x )
  \    rot close-dev drop                        ( size.lo )
   \   d# 20 >>                                  ( #MB )
      then
   else
      0                                         ( #MB )
   then
;

\ : disk-size  ( devspec$ -- #MB )
\   open-dev ?dup 0<> if                         ( ih )
\      dup " size" rot $call-method              ( ih size.lo size.hi )
\      rot close-dev drop                        ( size.lo )
\      d# 20 >>                                  ( #MB )
\      \ fuck your signed 32bit division..    d# 100000 /                               ( #MB ).
\   else
\      0                                         ( #MB )
\   then
\ ;

: debxo-find-targets  ( -- help0$ 'func0 'icon0 ... helpk$ 'funck 'iconk )
   0 to nr-targets

   \ check for the existence of nandflash (XO-1)
   " /nandflash" has-target? if
      " Internal NAND"
      ['] choose-nand-item spi.icon
   else
      \ check for internal EMMC (XO-1.5, XO-1.75)
      " int:0" has-target? if
         64 alloc-mem >r
         " int:0" disk-size decimal             ( #MB )
         <# "  MB)" hold$ u#s " Internal MMC (" hold$ u#>
         r> pack count
         \ " Internal MMC"
         ['] choose-emmc-item spi.icon
      then
   then

   " ext:0" has-target? if
       64 alloc-mem >r
       " ext:0" disk-size decimal               ( #MB )
       <# "  MB)" hold$ u#s " SD Card (" hold$ u#>
       r> pack count
\      " SD Card"
      ['] choose-sd-item sdcard.icon
   then

   \ check for up to 4 USB drives
   4 0  do
      i <# " /disk" hold$ u# " /usb/scsi@" hold$ u#>  string2 pack
      count has-target? if
         \ create description
         i 1+                                   ( i )
         64 alloc-mem >r                        ( i )
         <# u# " USB Disk #" hold$ u#>  r@ place
         string2 count disk-size decimal        ( #MB )
         <# "  MB)" hold$ u#s "  (" hold$ u#> r@ $cat

         r> count                               ( desc$ )
         i <# u# " ['] choose-usb-item-" hold$ u#> evaluate usb.icon
      then
   loop

\ TODO: multiple usb disks?
\ differentiate between installer disk & extra disk..
;


: debxo-installer-menu  ( -- )
   \ populate stack w/ icon/target list
   debxo-find-targets      

   \ last entry on the list
   " Abort installation"
   ['] quit-item quit.icon

   \ generate the menu
   d# 1 to rows
   nr-targets 1+ to cols

   clear-menu

   0 nr-targets  do
      0 i install-icon
   -1 +loop
;

: instmenu
   ['] debxo-installer-menu to root-menu
   (menu)
;
