;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; The MUni Race: https://github.com/ricardoquesada/c64-the-muni-race
;
; main screen
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

; exported by the linker
.import __MAIN_CODE_LOAD__, __SIDMUSIC_LOAD__
.import __MAIN_SPRITES_LOAD__, __GAME_CODE_LOAD__, __HIGH_SCORES_CODE_LOAD__

; from utils.s
.import ut_get_key, ut_read_joy2, ut_detect_pal_paln_ntsc
.import ut_vic_video_type, ut_start_clean

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Macros
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.macpack cbm                            ; adds support for scrcode

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Constants
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.include "c64.inc"                      ; c64 constants
SPRITE_ANIMATION_SPEED = 8
SCREEN_BASE = $8400                     ; screen address


.segment "CODE"
        jsr ut_start_clean              ; no basic, no kernal, no interrupts
        jsr ut_detect_pal_paln_ntsc     ; pal, pal-n or ntsc?


        ; disable NMI
;       sei
;       ldx #<disable_nmi
;       ldy #>disable_nmi
;       sta $fffa
;       sta $fffb
;       cli

        jmp __MAIN_CODE_LOAD__

disable_nmi:
        rti

.segment "MAIN_CODE"
        sei

        jsr init_screen

        lda #%00001000                  ; no scroll,single-color,40-cols
        sta $d016

        lda $dd00                       ; Vic bank 2: $8000-$BFFF
        and #$fc
        ora #1
        sta $dd00

        lda #%00010100                  ; charset at $9000 (equal to $1000 for bank 0)
        sta $d018

        lda #%00011011                  ; disable bitmap mode, 25 rows, disable extended color
        sta $d011                       ; and vertical scroll in default position

        lda #$00                        ; background & border color
        sta $d020
        sta $d021


        lda #$7f                        ; turn off cia interrups
        sta $dc0d
        sta $dd0d

        lda #01                         ; enable raster irq
        sta $d01a

        ldx #<irq_a                     ; next IRQ-raster vector
        ldy #>irq_a                     ; needed to open the top/bottom borders
        stx $fffe
        sty $ffff
        lda #50
        sta $d012

        lda $dc0d                       ; clear interrupts and ACK irq
        lda $dd0d
        asl $d019

        lda #$00                        ; turn off volume
        sta SID_Amp

        lda #$00                        ; avoid garbage when opening borders
        sta $bfff                       ; should be $3fff, but I'm in the 2 bank

        cli


@main_loop:
        lda sync_irq
        beq @main_loop
        dec sync_irq

        jsr animate_palette
        jsr animate_screen
        jsr ut_get_key
        bcc @main_loop

        cmp #$40                        ; F1
        beq @start_game
        cmp #$50                        ; F3
        beq @jump_high_scores
        cmp #$30                        ; F7
        bne @main_loop
        jmp @main_loop                  ; FIXME: added here jump to about

@start_game:
        jmp __GAME_CODE_LOAD__
@jump_high_scores:
        jmp __HIGH_SCORES_CODE_LOAD__

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; IRQ: irq_open_borders()
;------------------------------------------------------------------------------;
; used to open the top/bottom borders
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
irq_a:
        pha                             ; saves A, X, Y
        txa
        pha
        tya
        pha

        lda #$f8
        sta $d012
        ldx #<irq_open_borders
        ldy #>irq_open_borders
        stx $fffe
        sty $ffff

        ldx #0
        stx $d021

        ldx palette_idx_top
        .repeat 6 * 8
                lda $d012
:               cmp $d012
                beq :-
                lda luminances,x
                sta $d021
                inx
                txa
                and #%00111111          ; only 64 values are loaded
                tax
        .endrepeat

        ldx palette_idx_bottom
        .repeat 6 * 8
                lda $d012
:               cmp $d012
                beq :-
                lda luminances,x
                sta $d021
                dex 
                txa
                and #%00111111          ; only 64 values are loaded
                tax
        .endrepeat

        lda #0
        sta $d021

        asl $d019
        inc sync_irq

        pla                             ; restores A, X, Y
        tay
        pla
        tax
        pla
        rti                             ; restores previous PC, status

.export irq_open_borders
irq_open_borders:
        pha                             ; saves A, X, Y
        txa
        pha
        tya
        pha

        lda $d011                       ; open vertical borders trick
        and #%11110111                  ; first switch to 24 cols-mode...
        sta $d011

:       lda $d012
        cmp #$ff
        bne :-

        lda $d011                       ; ...a few raster lines switch to 25 cols-mode again
        ora #%00001000
        sta $d011


        lda #50
        sta $d012
        ldx #<irq_a
        ldy #>irq_a
        stx $fffe
        sty $ffff

        asl $d019

        pla                             ; restores A, X, Y
        tay
        pla
        tax
        pla
        rti                             ; restores previous PC, status

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; void init_screen()
;------------------------------------------------------------------------------;
; paints the screen with the "main menu" screen
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.proc init_screen
        ldx #$00
@loop:
        lda main_menu_screen,x          ; copy the first 14 rows
        clc                             ; using the reversed characters
        adc #$80                        ; 14 * 40 = 560 = 256 + 256 + 48
        sta SCREEN_BASE,x
        lda #0
        sta $d800,x                     ; set reverse color

        lda main_menu_screen+$0100,x
        clc
        adc #$80
        sta SCREEN_BASE+$0100,x
        lda #0
        sta $d800+$0100,x               ; set reverse color

        lda main_menu_screen+$0100+48,x
        clc
        adc #$80
        sta SCREEN_BASE+$0100+48,x
        lda #0
        sta $d800+$0100+48,x            ; set reverse color


        lda main_menu_screen+$0200+48,x ; copy the remaining chars
        sta SCREEN_BASE+$0200+48,x      ; in normal mode
        lda #1
        sta $d800+$0200+48,x            ; set normal color
        lda main_menu_screen+$02e8,x
        sta SCREEN_BASE+$02e8,x
        lda #1
        sta $d800+$02e8,x               ; set normal color

        inx
        bne @loop

        lda #2                          ; set color for unicyclist
        .repeat 5,YY
                ldx #2
:               sta $d800+(YY+14)*40,x
                sta $d800+(YY+14)*40+37,x
                dex
                bpl :-
        .endrepeat

        lda #3                          ; set color for unicycle
        .repeat 5,YY
                ldx #2
:               sta $d800+(YY+19)*40,x
                sta $d800+(YY+19)*40+37,x
                dex
                bpl :-
        .endrepeat

        lda #$0b                         ; set color for copyright
        ldx #39
:       sta $d800+24*40,x
        dex
        bpl :-


        lda #%10000000                  ; enable sprite #7
        sta VIC_SPR_ENA
        lda #%10000000                  ; set sprite #7 x-pos 9-bit ON
        sta $d010                       ; since x pos > 255

        lda #$40
        sta VIC_SPR7_X                  ; x= $140 = 320
        lda #$f0
        sta VIC_SPR7_Y

        lda __MAIN_SPRITES_LOAD__ + 64 * 15 + 63; sprite color
        and #$0f
        sta VIC_SPR7_COLOR

        ldx #$0f                        ; sprite pointer to PAL (15)
        lda ut_vic_video_type           ; ntsc, pal or paln?
        cmp #$01                        ; Pal ?
        beq @end                        ; yes.
        cmp #$2f                        ; Pal-N?
        beq @paln                       ; yes
        cmp #$2e                        ; NTSC Old?
        beq @ntscold                    ; yes
        ldx #$0e                        ; otherwise it is NTSC
        bne @end

@ntscold:
        ldx #$0c
        bne @end
@paln:
        ldx #$0d
@end:
        stx $87ff                       ; set sprite pointer

        rts
.endproc

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; void animate_palette(void)
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.proc animate_palette

        dec palette_idx_top             ; animate top palette
        lda palette_idx_top
        and #%00111111
        sta palette_idx_top

        dec palette_idx_bottom          ; animate bottom palette
        lda palette_idx_bottom
        and #%00111111
        sta palette_idx_bottom
        rts
.endproc

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; void animate_screen(void)
; uses $fb-$ff
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.proc animate_screen

        dec delay
        beq :+
        rts
:
        lda #50
        sta delay

        ldy #0
        ldx #4
l0:
        lda addresses_lo,x          ; swaps values
        sta $fc
        lda addresses_hi,x
        sta $fd
        lda addresses_lo+5,x
        sta $fe
        lda addresses_hi+5,x
        sta $ff
                                    ; swaps left and right values
                                    ; using $fb as tmp variable
        lda ($fc),y                 ; A = left
        sta $fb                     ; tmp = A
        lda ($fe),y                 ; A = right
        sta ($fc),y                 ; left = A
        lda $fb                     ; A = tmp
        sta ($fe),y                 ; right = tmp

        dex
        bpl l0

        rts
delay:
        .byte 50
bytes_to_swap:
ADDRESS0 = SCREEN_BASE+15*40        ; left eye
ADDRESS1 = SCREEN_BASE+15*40+2      ; right eye
ADDRESS2 = SCREEN_BASE+17*40        ; left arm
ADDRESS3 = SCREEN_BASE+17*40+2      ; right arm
ADDRESS4 = SCREEN_BASE+21*40+1      ; hub

ADDRESS5 = SCREEN_BASE+15*40+37     ; left eye
ADDRESS6 = SCREEN_BASE+15*40+39     ; right eye
ADDRESS7 = SCREEN_BASE+17*40+37     ; left arm
ADDRESS8 = SCREEN_BASE+17*40+39     ; right arm
ADDRESS9 = SCREEN_BASE+21*40+38     ; hub

addresses_lo:
.repeat 10,YY
        .byte <.IDENT(.CONCAT("ADDRESS", .STRING(YY)))
.endrepeat
addresses_hi:
.repeat 10,YY
        .byte >.IDENT(.CONCAT("ADDRESS", .STRING(YY)))
.endrepeat

.endproc


main_menu_screen:
        .incbin "mainscreen-map.bin"

palette_idx_top:        .byte 0         ; color index for top palette
palette_idx_bottom:     .byte 48        ; color index for bottom palette (palette_size / 2)

luminances:
.byte $01,$01,$0d,$0d,$07,$07,$03,$03,$0f,$0f,$05,$05,$0a,$0a,$0e,$0e
.byte $0c,$0c,$08,$08,$04,$04,$02,$02,$0b,$0b,$09,$09,$06,$06,$00,$00
.byte $01,$01,$0d,$0d,$07,$07,$03,$03,$0f,$0f,$05,$05,$0a,$0a,$0e,$0e
.byte $0c,$0c,$08,$08,$04,$04,$02,$02,$0b,$0b,$09,$09,$06,$06,$00,$00
PALETTE_SIZE = * - luminances

sync_irq:   .byte 0                     ; enabled when raster is triggred (once per frame)

.segment "MAIN_SPRITES"
        .incbin "src/sprites.bin"

