;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; The Uni Games: https://github.com/ricardoquesada/c64-the-uni-games
;
; High Scores screen
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

; from utils.s
.import ut_clear_color, ut_get_key, ut_clear_screen, ut_convert_key_matrix

; from main.s
.import sync_timer_irq
.import menu_read_events
.import mainscreen_colors, main_irq_timer, main_init_music, main_init_data
.import main_loop, main_reset_menu
.import ut_get_key


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Macros
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.macpack cbm                            ; adds support for scrcode

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Constants
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.include "c64.inc"                      ; c64 constants
.include "myconstants.inc"


.segment "HI_CODE"

.enum SCORES_STATE
        PAITING
        WAITING
.endenum


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; scores_init
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.export scores_init
.proc scores_init
        lda #$0
        sta zp_hs_new_entries_pos         ; reset value when called from menu
                                        ; $ff means invalid entry and could get confused
                                        ; with the very fragile input handling code
        lda #$0f
        sta hs_new_entry_pos

        jsr scores_init_soft
        jmp scores_mainloop
.endproc

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; scores_init_soft
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.proc scores_init_soft
        lda #0
        sta score_counter

        lda #SCORES_STATE::WAITING
        sta scores_state

        lda #%00000000                  ; enable/disable sprites
        sta VIC_SPR_ENA

        lda #$01
        jsr ut_clear_color              ; clear color RAM

        lda #$20
        jsr ut_clear_screen             ; clear screen RAM

        jmp scores_init_screen
.endproc

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; void scores_init_hard()
; to be called from game.s, when it also needs to uncrunch some stuff for the scores
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.export scores_init_hard
.proc scores_init_hard
        sei

        lda #0
        sta $d01a                       ; no raster interrups
        sta VIC_SPR_ENA                 ; no sprites while initing the screen
        sta score_cursor_pos            ; reset cursor
        sta $d020                       ; background / foreground color
        sta $d021
        sta SID_Amp                     ; turn off volume

        lda #$7f                        ; turn off cia interrups
        sta $dc0d
        sta $dd0d

                                        ; multicolor mode + extended color causes
        lda #%01011011                  ; the bug that blanks the screen
        sta $d011                       ; extended color mode: on
        lda #%00011000
        sta $d016                       ; turn on multicolor

        jsr scores_init_soft

        jsr main_init_data
        jsr main_init_music

                                        ; turn VIC on again
        lda #%00011011                  ; charset mode, default scroll-Y position, 25-rows
        sta $d011                       ; extended color mode: off

        lda #%00001000                  ; no scroll, hires (mono color), 40-cols
        sta $d016                       ; turn off multicolor

        ldx #<main_irq_timer            ; irq for timer
        ldy #>main_irq_timer
        stx $fffe
        sty $ffff

        lda $dc0d                       ; clear interrupts and ACK irq
        lda $dd0d
        asl $d019

        lda #SCORES_MODE::NEW_HS        ; "new high score", even if there is none
        sta zp_hs_mode

        cli
        jmp scores_mainloop
.endproc

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; scores_mainloop
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.proc scores_mainloop
        lda sync_timer_irq
        bne animate

        lda zp_hs_mode                  ; if mode is CYCLE or new score
        cmp #SCORES_MODE::CYCLE         ; is invalid, then check for space
        beq check_space
        lda hs_new_entry_pos
        cmp #$0f                        ; no high score?
        bne new_hs_branch

check_space:
        jsr menu_read_events
        cmp #%00010000                  ; space or button
        bne scores_mainloop

        lda zp_hs_mode
        cmp #SCORES_MODE::CYCLE
        beq l1
        jmp jump_to_main                ; return to main, by jumping
l1:     rts                             ; return to caller (main menu) by rts

animate:
        dec sync_timer_irq
        jsr MUSIC_PLAY                  ; play music
        jsr paint_score                 ; print new scores if needed

        lda zp_hs_mode
        cmp #SCORES_MODE::CYCLE
        beq scores_mainloop
        lda hs_new_entry_pos
        cmp #$0f
        beq scores_mainloop

        jsr print_cursor                ; animate cursor if in "new score" mode
        jmp scores_mainloop             ; and with a valid entry

new_hs_branch:
        jsr ut_get_key                  ; returns matrix code
        bcs l0                          ; if C=1
        ldx #1
        stx keyboard_released
        bne scores_mainloop             ; ASSERT (Z=0). always jump

l0:
        ldx keyboard_released
        beq scores_mainloop

        ldx #0
        stx keyboard_released

        cmp #$10                        ; RETURN?
        beq return_pressed
        cmp #$00
        beq delete_pressed              ; delete pressed?

        jsr ut_convert_key_matrix       ; matrix code is useless. convert it to screen codes
        cmp #$ff                        ; invalid key? ignore it
        beq scores_mainloop

        ldy score_cursor_pos
        sta (zp_hs_new_ptr2_lo),y       ; self-modyfing

        iny
        cpy #11
        bne :+
        dey
:       sty score_cursor_pos

        jmp scores_mainloop

delete_pressed:                         ; "DELETE / INSERT" pressed
        ldy score_cursor_pos            ; don't delete if already 0
        lda #$20                        ; clean current cursor with space
        sta (zp_hs_new_ptr2_lo),y

        cpy #0
        beq scores_mainloop
        dey                             ; score_cursor_pos -= 1
        sty score_cursor_pos
        jmp scores_mainloop

return_pressed:                         ; "RETURN" pressed.
        lda #$20                        ; space, in case it is the inversed ($a0)
        ldy score_cursor_pos
        sta (zp_hs_new_ptr2_lo),y

        jsr copy_entry                  ; copy name to entries

        lda zp_hs_new_entries_pos
        cmp #$ff
        beq save_and_exit

        lda #0
        sta score_cursor_pos            ; cursor back to start position

        ldx #1                          ; load second score
        jsr scores_init_hs_score_entry
        bcc save_and_exit               ; error? means no other score needs to be saved
        jmp scores_mainloop

save_and_exit:
        sei
        lda #0
        sta SID_Amp                     ; volume off
        lda #$7f
        sta $dc0d                       ; no timer IRQ

        jsr scores_file_save            ; save to disk

        lda #$81
        sta $dc0d                       ; enable timer IRQ again
        cli

jump_to_main:
        jsr main_reset_menu             ; jump to main loop
        jmp main_loop                   ; since it was called by game.s and not by main.s


print_cursor:
        dec delay
        beq :+
        rts

:       lda #$08
        sta delay

        ldy score_cursor_pos
        lda space_char
        sta (zp_hs_new_ptr2_lo),y        ; self-modyfing
        eor #%10000000
        sta space_char
        rts

copy_entry:
        ldx hs_new_entry_pos
        cpx #0
        beq l3

l4:     lda zp_hs_new_ptr_lo            ; the thing is that zp_hs_new_ptr_lo/hi
        clc                             ; points to the beginning of the scores entries
        adc #16                         ; and not to the entry that needs to be udpated
        sta zp_hs_new_ptr_lo            ; so we have to update zp_hs_new_ptr_lo/hi manually
        bcc :+                          ; by adding 16 bytes for each entry needed
        inc zp_hs_new_ptr_hi
:       dex
        bne l4

l3:
        ldy #9
l2:     lda (zp_hs_new_ptr2_lo),y
        sta (zp_hs_new_ptr_lo),y
        dey
        bpl l2
        rts

delay:                  .byte 1         ; delay for cursor
space_char:             .byte $20       ; swtiches from $20 to $a0
keyboard_released:      .byte 1         ; to prevent auto-repeat
.endproc



;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; scores_init_screen
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.proc scores_init_screen
        ldx #0
l0:
        lda hiscores_map,x
        sta SCREEN0_BASE,x
        tay
        lda mainscreen_colors,y
        sta $d800,x

        inx
        cpx #240
        bne l0

        jmp scores_setup_paint
.endproc

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; scores_init_hs_score_entry
; entries:
;       x: which score to set: 0 or 1
; return:
;       C: set: Ok
;          clear: Error
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.export scores_init_hs_score_entry
.proc scores_init_hs_score_entry
        lda zp_hs_new_entries_pos       ; set pointer for name input

        cpx #0                          ; X, from entries
        beq score_0

        lsr                             ; use MSB
        lsr
        lsr
        lsr

        jmp set_entry

score_0:
        and #%00001111                  ; use LSB


set_entry:
        sta hs_new_entry_pos            ; save current idx to hs_new_entry_pos

        cmp #$0f                        ; valid entry
        beq error

        tay                             ; udpate pointer to where the name
                                        ; should be copied to.
        lda screen_ptr_lo,y             ; can't reuse the zp_hs_new_ptr_lo ptr
        sta zp_hs_new_ptr2_lo           ; since both will be used at the same time
        lda screen_ptr_hi,y
        sta zp_hs_new_ptr2_hi

        ldy zp_hs_category              ; setup scores to compare
        lda scores_entries_lo,y         ; scores_entries must point to the beginning
        sta zp_hs_new_ptr_lo            ; this is needed when two scores are added
        lda scores_entries_hi,y
        sta zp_hs_new_ptr_hi

        cpx #0                          ; reset value after using it
        bne clear_1

        lda zp_hs_new_entries_pos       ; after using score 0, reset it
        ora #$0f
        sta zp_hs_new_entries_pos
        jmp end

clear_1:
        lda zp_hs_new_entries_pos       ; after using score 1, reset it
        ora #$f0
        sta zp_hs_new_entries_pos

end:
        sec                             ; score set Ok
        rts

error:
        clc                             ; score was not set
        rts
.endproc

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; void scores_swap_entries()
; swap the nibbles of zp_hs_new_entries_pos
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.export scores_swap_entries
.proc scores_swap_entries
        lda zp_hs_new_entries_pos       ; swaps the nibbles in zp_hs_new_entries_pos

        lsr
        lsr
        lsr
        lsr
        sta tmp                         ; shift 4 right bits. store in tmp

        lda zp_hs_new_entries_pos       ; shift left 4 bits
        asl
        asl
        asl
        asl

        ora tmp                         ; ora the previous shifted values
        sta zp_hs_new_entries_pos
        rts
tmp:
        .byte 0
.endproc



;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; void scores_sort(void* scores_to_sort)
; entries: zp_hs_latest_score
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.export scores_sort
.proc scores_sort
        ldx zp_hs_category              ; setup scores to compare
        lda scores_entries_lo,x
        sta zp_hs_new_ptr_lo
        lda scores_entries_hi,x
        sta zp_hs_new_ptr_hi

        asl zp_hs_new_entries_pos       ; zp_hs_new_entries_pos holds
        asl zp_hs_new_entries_pos       ; two possible entries
        asl zp_hs_new_entries_pos       ; $f means no entry.
        asl zp_hs_new_entries_pos       ; shift 4 to left to save current LSB value

        ldx #0
        stx tmp_entry_pos

l0:     lda valid_y,x                   ; scores are 10 bytes after the name
        tay

        jsr scores_cmp_score            ; uses Y
        bmi new_hs
        inc tmp_entry_pos               ; inc entry index
        ldx tmp_entry_pos
        cpx #8                          ; there are only 8 entries
        bne l0

;no new hs
        lda zp_hs_new_entries_pos
        ora #$0f                        ; LSB is $f (no high score entry)
        sta zp_hs_new_entries_pos
        rts

new_hs:
        ldx tmp_entry_pos               ; position for the new score
        jsr scores_insert_entry         ; insert new entry in the table

        ldx tmp_entry_pos               ; set new score
        lda valid_y,x

        sec
        sbc #10                         ; start at the beginning of the entry
        tay

        ldx #9
        lda #$20                        ; space
l1:     sta (zp_hs_new_ptr_lo),y        ; replace old name with spaces
        iny
        dex
        bpl l1

        ; ASSERT(y should point to "minutes")
                                        ; replace old score with new one
        lda zp_hs_latest_score          ; minutes
        sta (zp_hs_new_ptr_lo),y
        iny
        lda zp_hs_latest_score+1        ; seconds MSB
        sta (zp_hs_new_ptr_lo),y
        iny
        lda zp_hs_latest_score+2        ; seconds LSB
        sta (zp_hs_new_ptr_lo),y
        iny
        lda zp_hs_latest_score+3        ; deci-seconds
        sta (zp_hs_new_ptr_lo),y

        lda zp_hs_new_entries_pos       ; update LSB entry pos
        ora tmp_entry_pos
        sta zp_hs_new_entries_pos

        rts

valid_y:
        .byte 0+10, 16+10, 32+10, 48+10         ; scores are 10 bytes after the name
        .byte 64+10, 80+10, 96+10, 112+10

tmp_entry_pos:
        .byte 0

.endproc

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; scores_cmp_score
; entries:
;       zp_hs_new_ptr_lo/hi: must point to valid score entries
;       y = index inside score entries
; returns:
;       Flags: CMP(zp_hs_score, entries_score)
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.proc scores_cmp_score
        lda zp_hs_latest_score          ; the minutes
        cmp (zp_hs_new_ptr_lo),y        ; so, compare minutes
        bne end                         ; fallthrough only if the are equal

        iny                             ; next digit
        lda zp_hs_latest_score+1        ; seconds. first digit
        cmp (zp_hs_new_ptr_lo),y
        bne end                         ; fallthrough only if the are equal

        iny                             ; next digit
        lda zp_hs_latest_score+2        ; seconds. secong digit
        cmp (zp_hs_new_ptr_lo),y
        bne end                         ; fallthrough only if the are equal

        iny                             ; next digit
        lda zp_hs_latest_score+3        ; deci-seconds
        cmp (zp_hs_new_ptr_lo),y

end:
        rts
.endproc

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; scores_insert_entry
; entries:
;       zp_hs_new_ptr_lo/hi: must point to valid score entries
;       x: entry idx where the new score should be inserted
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.proc scores_insert_entry
        stx zp_tmp01

        lda #7                          ; entry 7
        sta zp_tmp00


l1:     cmp zp_tmp01                    ; entry where it should be inserted
        beq end

        ldx zp_tmp00
        lda score_ptr,x
        tay                             ; Y = pointer to next score entry

        ldx #15                         ; copy in total 16 bytes (each entry == 16 bytes)
l0:     lda (zp_hs_new_ptr_lo),y        ; so, compare minutes
        pha                             ; save A

        sty save_y                      ; save Y
        tya                             ; Y += 16
        clc
        adc #16
        tay

        pla                             ; restore A
        sta (zp_hs_new_ptr_lo),y        ; and copy it to entry #8

save_y = *+1
        ldy #00                         ; self modyfing. restore Y
        iny                             ; next byte to copy

        dex
        bpl l0

        dec zp_tmp00
        lda zp_tmp00
        jmp l1

end:
        rts

score_ptr:
        .byte 0                         ; ignore
        .byte 0, 16, 32, 48, 64, 80, 96
.endproc

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; paint_score
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.proc paint_score

        lda scores_state
        cmp #SCORES_STATE::WAITING
        bne paint_delay                 ; paint or wait?

;wait_delay                             ; SCORES_STATE::WAITING
        dec delay
        bne @end
        jmp scores_setup_paint
@end:
        rts


paint_delay:                            ; SCORES_STATE::PAITING
        dec delay
        beq paint
        rts

paint:
        lda #$04
        sta delay

        ldx score_counter
        cpx #8                          ; paint only 8 scores
        bne paint_next

        lda zp_hs_mode                  ; only display next category
        cmp #SCORES_MODE::CYCLE         ; if in cycle mode
        beq :+
        rts
:       jmp scores_next_category        ; setup next category then

paint_next:
        jsr @print_highscore_entry

        clc                             ; pointer to the next line in the screen
        lda zp_hs_ptr_lo
        adc #(40 * 2)                   ; skip one line
        sta zp_hs_ptr_lo
        bcc :+
        inc zp_hs_ptr_hi
:
        inc score_counter

        rts

@print_highscore_entry:
        txa                             ; x has the high score entry index

        ldy #$01                        ; y = screen idx

        clc
        adc #$01                        ; positions start with 1, not 0

        ora #$30
        sta (zp_hs_ptr_lo),y            ; print position
        iny

        lda #$2e                        ; print '.'
        sta (zp_hs_ptr_lo),y
        iny


        lda #10                         ; print name. 10 chars
        sta zp_tmp00

        txa                             ; multiply x by 16, since each entry has 16 bytes
        asl
        asl
        asl
        asl
        tax                             ; x = high score pointer

:       lda scores_entries,x            ; points to entry[i].name
        sta (zp_hs_ptr_lo),y            ; pointer to screen
        iny
        inx
        dec zp_tmp00
        bne :-


        lda #6                          ; print score. 6 digits
        sta zp_tmp00

        tya                             ; advance some chars
        clc
        adc #8
        tay

                                        ; minutes
        lda scores_entries,x            ; points to entry[i].score
        ora #$30
        sta (zp_hs_ptr_lo),y            ; write to screen

        iny                             ; ptr to screen++
        lda #58                         ; ':'
        sta (zp_hs_ptr_lo),y            ; write to screen

                                        ; seconds (first digit)
        iny                             ; ptr to screen++
        inx                             ; ptr to score++
        lda scores_entries,x            ; points to entry[i].score
        ora #$30
        sta (zp_hs_ptr_lo),y            ; write to screen

                                        ; seconds (second digit)
        iny                             ; ptr to screen++
        inx                             ; ptr to score++
        lda scores_entries,x            ; points to entry[i].score
        ora #$30
        sta (zp_hs_ptr_lo),y            ; write to screen

        iny                             ; ptr to screen++
        lda #58                         ; ':'
        sta (zp_hs_ptr_lo),y            ; write to screen

                                        ; decimal
        iny                             ; ptr to screen++
        inx                             ; ptr to score++
        lda scores_entries,x            ; points to entry[i].score
        ora #$30
        sta (zp_hs_ptr_lo),y            ; write to screen

        rts
.endproc

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; void scores_next_category()
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.proc scores_next_category
        lda #$ff                        ; finished paiting the 8 entries ?
        sta delay                       ; then switch to wait mode
        lda #SCORES_STATE::WAITING
        sta scores_state
        ldx zp_hs_category
        inx
        cpx #3
        bne :+
        ldx #0
:       stx zp_hs_category
        rts
.endproc

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; void scores_setup_paint()
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.proc scores_setup_paint
        lda #SCORES_STATE::PAITING
        sta scores_state
        lda #$04
        sta delay
        lda #0
        sta score_counter


        ldx #0                          ; clear bottom part of the screen,
        lda #$20                        ; where the scores go
l0:     sta SCREEN0_BASE + 240,x
        sta SCREEN0_BASE + 256 + 240,x
        sta SCREEN0_BASE + 512 + 240,x
        inx
        bne l0

        ldx zp_hs_category
        lda categories_name_lo,x
        sta categories_name
        lda categories_name_hi,x
        sta categories_name+1

        ldx #39
categories_name = *+1                   ; self modifying
:       lda categories_roadrace,x       ; displays the  category
        sta SCREEN0_BASE + 280,x
        dex
        bpl :-


        ldx zp_hs_category              ; copy scores from "load"
        lda scores_entries_lo,x         ; to final position
        sta entries
        lda scores_entries_hi,x
        sta entries+1

        ldx #127
entries = *+1
:       lda entries_roadrace,x          ; self modyfing
        sta scores_entries,x
        dex
        bpl :-


        ldx #<(SCREEN0_BASE + 40 * 10 + 6)  ; init "save" pointer
        ldy #>(SCREEN0_BASE + 40 * 10 + 6)  ; start writing at 10th line
        stx zp_hs_ptr_lo
        sty zp_hs_ptr_hi


        rts
.endproc


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; void scores_file_save()
; code taken from here: http://codebase64.org/doku.php?id=base:saving_a_file
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.export scores_file_save
.proc scores_file_save
FILE_START = $e80
FILE_END = $fff

        ldx #3
l0:     lda saving_lbl,x
        sta SCREEN0_BASE + 40 * 24 + 36, x
        dex
        bpl l0

        inc $01                         ; $36: kernal in

        lda #FILENAME_LEN
        ldx #<fname
        ldy #>fname
        jsr $ffbd                       ; call SETNAM

        lda #$00
        ldx $ba                         ; last used device number
        bne @skip
        ldx #$08                        ; default to device 8
@skip:  ldy #$00
        jsr $ffba                       ; call SETLFS

        lda #<FILE_START
        sta $c1                         ; reuse zp's used by kernal
        lda #>FILE_START
        sta $c2

        ldx #<FILE_END
        ldy #>FILE_END
        lda #$c1                        ; start address located in $c1/$c2
        jsr $ffd8                       ; call SAVE
        bcs @error                      ; if carry set, a load error has happened

        dec $01                         ; $35: kernal out. use RAM
        rts
@error:
        ; Acumulator contains BASIC error code
        dec $01                         ; $35: kernal out. use RAM

        rts

saving_lbl:
        .byte 221,222,223,190
.endproc

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; void scores_file_load ()
; code taken from here: http://codebase64.org/doku.php?id=base:loading_a_file
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.export scores_file_load
.proc scores_file_load
        inc $01                         ; $36: kernal in

        lda #FILENAME_LEN
        ldx #<fname
        ldy #>fname
        jsr $ffbd                       ; call SETNAM

        lda #$01
        ldx $ba                         ; last used device number
        bne @skip
        ldx #$08                        ; default to device 8
@skip:  ldy #$01                        ; not $00 means: load to address stored in file
        jsr $ffba                       ; call SETLFS

        lda #$00                        ; $00 means: load to memory (not verify)
        jsr $ffd5                       ; call LOAD
        bcs @error                      ; if carry set, a load error has happened

        dec $01                         ; $35: kernal out
        rts
@error:
        ; Accumulator contains BASIC error code

        ; most likely errors:
        ; A = $05 (DEVICE NOT PRESENT)
        ; A = $04 (FILE NOT FOUND)
        ; A = $1D (LOAD ERROR)
        ; A = $00 (BREAK, RUN/STOP has been pressed during loading)

        inc $d020
        dec $01                         ; $35: kernal out
        rts
.endproc

fname:  .byte "@0:unigames-scores"
FILENAME_LEN = * - fname


score_cursor_pos: .byte 0                       ; uses for name input
score_counter: .byte 0                          ; score that has been drawn
delay:         .byte $10                        ; delay used to print the scores
scores_state:  .byte SCORES_STATE::PAITING      ; status: paiting? or waiting?

hs_new_entry_pos:   .byte $0f                       ; high score being processed

categories_name_lo:
        .byte <categories_roadrace
        .byte <categories_cyclocross
        .byte <categories_crosscountry
categories_name_hi:
        .byte >categories_roadrace
        .byte >categories_cyclocross
        .byte >categories_crosscountry
scores_entries_lo:
        .byte <entries_roadrace
        .byte <entries_cyclocross
        .byte <entries_crosscountry
scores_entries_hi:
        .byte >entries_roadrace
        .byte >entries_cyclocross
        .byte >entries_crosscountry

                ;0123456789|123456789|123456789|123456789|
categories_roadrace:
        scrcode "                road race               "
categories_cyclocross:
        scrcode "               cyclo cross              "
categories_crosscountry:
        scrcode "              cross country             "

hiscores_map:
        .incbin "hiscores-map.bin"      ; 40 * 6



screen_ptr_lo:
        .repeat 8,YY
                .byte <(SCREEN0_BASE + 40 * (10 + YY * 2) + 9)
        .endrepeat
screen_ptr_hi:
        .repeat 8,YY
                .byte >(SCREEN0_BASE + 40 * (10 + YY * 2) + 9)
        .endrepeat

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; segment SCORES
; fixed at $e80 to load/save them from disk
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.segment "SCORES"
entries_roadrace:
        ; high score entry: must have exactly 16 bytes each entry
        ;     name: 10 bytes in PETSCII
        ;     score: 4 bytes
        ;     pad: 2 bytes
        ;        0123456789
        scrcode "nathan    "
        .byte 0,3,7,2
        .byte 0,0               ; ignore
        scrcode "harrison  "
        .byte 0,3,7,6
        .byte 0,0               ; ignore
        scrcode "stefan    "
        .byte 0,3,8,0
        .byte 0,0               ; ignore
        scrcode "rob       "
        .byte 0,3,8,4
        .byte 0,0               ; ignore
        scrcode "sydney    "
        .byte 0,3,8,8
        .byte 0,0               ; ignore
        scrcode "nader     "
        .byte 0,3,9,4
        .byte 0,0               ; ignore
        scrcode "ricardo   "
        .byte 0,4,3,1
        .byte 0,0               ; ignore
        scrcode "ricardo   "
        .byte 0,4,5,2
        .byte 0,0               ; ignore

entries_cyclocross:
        ; high score entry: must have exactly 16 bytes each entry
        ;     name: 10 bytes in PETSCII
        ;     score: 4 bytes
        ;     pad: 2 bytes
        ;        0123456789
        scrcode "tom       "
        .byte 0,3,3,8
        .byte 0,0               ; ignore
        scrcode "dragon    "
        .byte 0,3,3,9
        .byte 0,0               ; ignore
        scrcode "chris     "
        .byte 0,3,4,0
        .byte 0,0               ; ignore
        scrcode "josh      "
        .byte 0,3,4,1
        .byte 0,0               ; ignore
        scrcode "jimbo     "
        .byte 0,3,4,2
        .byte 0,0               ; ignore
        scrcode "ashley    "
        .byte 0,3,4,3
        .byte 0,0               ; ignore
        scrcode "ricardo   "
        .byte 0,3,8,1
        .byte 0,0               ; ignore
        scrcode "ricardo   "
        .byte 0,3,9,5
        .byte 0,0               ; ignore

entries_crosscountry:
        ; high score entry: must have exactly 16 bytes each entry
        ;     name: 10 bytes in PETSCII
        ;     score: 4 bytes
        ;     pad: 2 bytes
        ;        0123456789
        scrcode "corbin    "
        .byte 0,3,4,6
        .byte 0,0               ; ignore
        scrcode "beau      "
        .byte 0,3,5,0
        .byte 0,0               ; ignore
        scrcode "michele   "
        .byte 0,3,5,4
        .byte 0,0               ; ignore
        scrcode "yu        "
        .byte 0,3,5,9
        .byte 0,0               ; ignore
        scrcode "geronimo  "
        .byte 0,3,6,2
        .byte 0,0               ; ignore
        scrcode "ray       "
        .byte 0,3,6,9
        .byte 0,0               ; ignore
        scrcode "ricardo   "
        .byte 0,4,3,3
        .byte 0,0               ; ignore
        scrcode "ricardo   "
        .byte 0,4,4,8
        .byte 0,0               ; ignore
