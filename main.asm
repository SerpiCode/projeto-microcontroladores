    .def temp            = r16
	.def button_state    = r17   ; Estado do botão (pressionado ou não)
	.def temp2			 = r18
    ;.def units           = r18   ; Unidade de segundo (0–9)
    ;.def tens            = r19  ; Dezena de segundo (0–5)
    ;.def min_units       = r20   ; Unidade de minuto (0–9)
    ;.def min_tens        = r21   ; Dezena de minuto (0–5)
    .def cron_units      = r22   ; Dezena de minuto (0–5)
    .def cron_tens       = r23   ; Dezena de minuto (0–5)
    .def cron_min_units  = r24   ; Dezena de minuto (0–5)
    .def cron_min_tens   = r25  ; Dezena de minuto (0–5)

	.dseg
	digitos_relogio: .byte 4
	; sts - carrega do reg pro byte
	; lds - le o byte e carrega no reg

    .cseg

display_table:
    .db 0x7E,0x30,0x6D,0x79,0x33,0x5B,0x5F,0x70,0x7F,0x7B  ; padrões 0–9

;=============================
; Inicialização
;=============================
    ; Pilha
    ldi temp, low(RAMEND)
    out SPL, temp
    ldi temp, high(RAMEND)
    out SPH, temp

    ; PORTD = segmentos (a–g)
    ldi temp, 0xFF
    out DDRD, temp
    ; PORTB = controle de catodos via transistores PC0–PC3
    ldi temp, 0xFF
    out DDRB, temp
    ; PORTC = botão em PC4
    ldi temp, 0xEF  ; PC4 como entrada, o resto como saída
    out DDRC, temp
    sbi PORTC, PC4  ; Habilita pull-up em PC4 para o botão

    ; Zera contadores de tempo e multiplex
    ;clr units
    ;clr tens
    ;clr min_units
    ;clr min_tens
	ldi temp2, 0
	sts digitos_relogio, temp2
	sts digitos_relogio+1, temp2
	sts digitos_relogio+2, temp2
	sts digitos_relogio+3, temp2
    clr r30
    clr button_state
    clr r29

;=============================
; Timer1 ? 1?Hz (CTC)
;=============================
    #define CLOCK       16.0e6
    #define DELAY       1        ; segundos
    .equ PRESCALE     = 0b100  ; /256
    .equ PRESCALE_DIV = 256
    .equ WGM          = 0b0100 ; CTC
    .equ TOP = int(0.5 + ((CLOCK/PRESCALE_DIV)*DELAY))

    ; Carrega OCR1A
    ldi temp, high(TOP)
    sts OCR1AH, temp
    ldi temp, low(TOP)
    sts OCR1AL, temp

    ; Modo CTC em TCCR1A/B, prescaler /256
    ldi temp, ((WGM & 0b11)<<WGM10)
    sts TCCR1A, temp
    ldi temp, ((WGM>>2)<<WGM12) | (PRESCALE<<CS10)
    sts TCCR1B, temp

    rjmp main_lp

;=============================
; Loop principal
;=============================
main_lp:
	; Verifica o estado do botão
    rcall check_button
    ; multiplexa displays rápido
    rcall update_display

    ; 2) checa estouro de 1?s
    in temp, TIFR1
    andi temp, 1<<OCF1A
    breq skipoverflow

    ; limpa flag de comparação
    ldi temp, 1<<OCF1A
    out TIFR1, temp

    ; incrementa MM:SS
	lds temp2, digitos_relogio
    inc temp2
	sts digitos_relogio, temp2
    cpi temp2, 10
    brlt skipoverflow

    ldi temp2, 0
	sts digitos_relogio, temp2
	lds temp2, digitos_relogio+1
    inc temp2
	sts digitos_relogio+1, temp2
    cpi temp2, 6
    brlt skipoverflow

    ldi temp2, 0
	sts digitos_relogio+1, temp2
	lds temp2, digitos_relogio+2
    inc temp2
	sts digitos_relogio+2, temp2
    cpi temp2, 10
    brlt skipoverflow

    ldi temp2, 0
	sts digitos_relogio+2, temp2
    lds temp2, digitos_relogio+3
	inc temp2
	sts digitos_relogio+3, temp2
    cpi temp2, 6
    brlt skipoverflow

    ; se chegou em 60:00, reseta tudo
    ldi temp2, 0
	sts digitos_relogio+3, temp2

skipoverflow:
    rjmp main_lp

;=============================
; check_button
; Verifica o estado do botão e atualiza o modo de exibição
;=============================
check_button:
    sbic PINC, PC4  ; Pula se o botão não estiver pressionado
    rjmp button_pressed

    ; Botão não pressionado
    clr button_state
    ret

button_pressed:
    cpi button_state, 0
    brne button_check_end  ; Se já estava pressionado, não faz nada

    ; Botão acabou de ser pressionado
    ldi button_state, 1
    
    ; Avança para o próximo modo
    inc r29
    cpi r29, 3
    brlo button_check_end
    clr r29  ; Volta para o modo 0 se ultrapassar 2

button_check_end:
    ret

;=============================
; update_display
; Atualiza os displays de acordo com o modo atual
;=============================
update_display:
    cpi r29, 0
    breq display_normal
    cpi r29, 1
    breq display_zeros
    cpi r29, 2
    breq display_ones

display_zeros:
    ; Exibe zeros em todos os displays
    ldi ZH, high(display_table)
    ldi ZL, low(display_table)
    lpm temp, Z  ; Carrega o padrão do zero
    out PORTD, temp
    ldi temp, 1<<PB0
    out PORTB, temp
    rcall delay_5ms
    ldi temp, 1<<PB1
    out PORTB, temp
    rcall delay_5ms
    ldi temp, 1<<PB2
    out PORTB, temp
    rcall delay_5ms
    ldi temp, 1<<PB3
    out PORTB, temp
    rcall delay_5ms
    ret

display_normal:
    ; carrega ponteiro da tabela
    ldi ZH, high(display_table)
    ldi ZL, low(display_table)

    ; escolhe e exibe
    cpi r30, 0
    breq disp0
    cpi r30, 1
    breq disp1
    cpi r30, 2
    breq disp2
    ; se não foi 0,1,2 então é 3
    rjmp disp3

display_ones:
    ; Exibe uns em todos os displays
    ldi ZH, high(display_table)
    ldi ZL, low(display_table)
    adiw ZL, 1   ; Avança para o padrão do dígito 1
    lpm temp, Z  ; Carrega o padrão do um
    rcall display_all
    ret

;=============================
; display_all
; Exibe o mesmo padrão em todos os displays
; Entrada: temp contém o padrão a ser exibido
;=============================
display_all:
    out PORTD, temp
    ldi temp, 1<<PB0
    out PORTB, temp
    rcall delay_5ms
    ldi temp, 1<<PB1
    out PORTB, temp
    rcall delay_5ms
    ldi temp, 1<<PB2
    out PORTB, temp
    rcall delay_5ms
    ldi temp, 1<<PB3
    out PORTB, temp
    rcall delay_5ms
    ret

disp0:  ; segundos unidades
	ldi ZH, high(display_table)
    ldi ZL, low(display_table)
	lds temp2, digitos_relogio
    add ZL, temp2
    clr temp
    adc ZH, temp
    lpm temp, Z
    out PORTD, temp         ; segmentos
    ldi temp, 1<<PC0
    out PORTB, temp         ; só display 0 ligado
    rcall delay_5ms
    ldi temp, 0x00
    out PORTB, temp

disp1:  ; segundos dezenas
	ldi ZH, high(display_table)
    ldi ZL, low(display_table)
	lds temp2, digitos_relogio+1
    add ZL, temp2
    clr temp
    adc ZH, temp
    lpm temp, Z
    out PORTD, temp
    ldi temp, 1<<PC1
    out PORTB, temp
    rcall delay_5ms

    ldi temp, 0x00
    out PORTB, temp

disp2:  ; minutos unidades
	ldi ZH, high(display_table)
    ldi ZL, low(display_table)
	lds temp2, digitos_relogio+2
    add ZL, temp2
    clr temp
    adc ZH, temp
    lpm temp, Z
    out PORTD, temp
    ldi temp, 1<<PC2
    out PORTB, temp
    rcall delay_5ms

    ldi temp, 0x00
    out PORTB, temp

disp3:  ; minutos dezenas
	ldi ZH, high(display_table)
    ldi ZL, low(display_table)
	lds temp2, digitos_relogio+3
    add ZL, temp2
    clr temp
    adc ZH, temp
    lpm temp, Z
    out PORTD, temp
    ldi temp, 1<<PC3
    out PORTB, temp
    rcall delay_5ms

    ret

dm_next:
    ; avança índice e wrap 0..3
    inc r30
    cpi r30, 4
    brlt dm_skip
    ldi r30, 0
dm_skip:
    ; delay curto (~2?ms)
    rcall delay_2ms
    ret

;=============================
; delay_2ms aproximado (@16?MHz)
;=============================
delay_2ms:
    ldi r27, 100
delay_5ms:
    ldi r27, 150
dly_outer:
    ldi r28, 40
dly_inner:
    dec r28
    brne dly_inner
    dec r27
    brne dly_outer
    ret