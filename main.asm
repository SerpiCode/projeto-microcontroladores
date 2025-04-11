    .def temp            = r16
	.def button_mode_state    = r17   ; Estado do bot�o (pressionado ou n�o)
	.def temp2			 = r18
	.def button_start_state    = r19
	.def display_mode = r20
	.def display_index = r21
	.def cron_status = r22
	.def show_cron = r23
	.def temp3 = r24

	.dseg
	digitos_relogio: .byte 4
	digitos_cron: .byte 4
	; sts - carrega do reg pro byte
	; lds - le o byte e carrega no reg

    .cseg

display_table:
    .db 0x7E,0x30,0x6D,0x79,0x33,0x5B,0x5F,0x70,0x7F,0x7B  ; padr�es 0�9

;=============================
; Inicializa��o
;=============================
    ; Pilha
    ldi temp, low(RAMEND)
    out SPL, temp
    ldi temp, high(RAMEND)
    out SPH, temp

    ; PORTD = segmentos (a�g)
    ldi temp, 0xFF
    out DDRD, temp
    ; PORTB = controle de catodos via transistores PC0�PC3
    ldi temp, 0xFF
    out DDRB, temp
    ; PORTC = bot�o em PC4
	ldi temp, 0xCF  ; PC4 como entrada (0), o resto como sa�da (1)
	out DDRC, temp  ; Configura PORTC

	sbi PORTC, PC4  ; Habilita pull-up em PC4
	sbi PORTC, PC5  ; Habilita pull-up em PC5

    ; Zera contadores de tempo e multiplex
    ;clr units
    ;clr tens
    ;clr min_units
    ;clr min_tens
	; zera todos os digitos
	ldi temp2, 0
	sts digitos_relogio, temp2
	sts digitos_relogio+1, temp2
	sts digitos_relogio+2, temp2
	sts digitos_relogio+3, temp2

	; zera todos os digitos do cron
	ldi temp2, 0
	sts digitos_cron, temp2
	sts digitos_cron+1, temp2
	sts digitos_cron+2, temp2
	sts digitos_cron+3, temp2

    clr display_index
    clr display_mode

	ldi button_mode_state, 0
	ldi cron_status, 0

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
	; Verifica o estado do bot�o
    rcall check_mode_button
	rcall check_start_button
    ; multiplexa displays r�pido
    rcall update_display

	; 2) checa estouro de 1?s
    in temp, TIFR1
    andi temp, 1<<OCF1A
    breq skipoverflow3

    ; limpa flag de compara��o
    ldi temp, 1<<OCF1A
    out TIFR1, temp

	rcall update_time

skipoverflow3:
    rjmp main_lp

update_time:
    ; incrementa MM:SS
	lds temp2, digitos_relogio
    inc temp2
	sts digitos_relogio, temp2
    cpi temp2, 10
    brlt update_cron_time

    ldi temp2, 0
	sts digitos_relogio, temp2
	lds temp2, digitos_relogio+1
    inc temp2
	sts digitos_relogio+1, temp2
    cpi temp2, 6
    brlt update_cron_time

    ldi temp2, 0
	sts digitos_relogio+1, temp2
	lds temp2, digitos_relogio+2
    inc temp2
	sts digitos_relogio+2, temp2
    cpi temp2, 10
    brlt update_cron_time

    ldi temp2, 0
	sts digitos_relogio+2, temp2
    lds temp2, digitos_relogio+3
	inc temp2
	sts digitos_relogio+3, temp2
    cpi temp2, 6
    brlt update_cron_time

    ; se chegou em 60:00, reseta tudo
    ldi temp2, 0
	sts digitos_relogio+3, temp2

skipoverflow2:
    rjmp main_lp

update_cron_time:
	cpi cron_status, 1
	brne skip_cron
    ; incrementa MM:SS
	lds temp3, digitos_cron
    inc temp3
	sts digitos_cron, temp3
    cpi temp3, 10
    brlt skipoverflow

    ldi temp3, 0
	sts digitos_cron, temp3
	lds temp3, digitos_cron+1
    inc temp3
	sts digitos_cron+1, temp3
    cpi temp3, 6
    brlt skipoverflow

    ldi temp3, 0
	sts digitos_cron+1, temp3
	lds temp3, digitos_cron+2
    inc temp3
	sts digitos_cron+2, temp3
    cpi temp3, 10
    brlt skipoverflow

    ldi temp3, 0
	sts digitos_cron+2, temp3
    lds temp3, digitos_cron+3
	inc temp3
	sts digitos_cron+3, temp3
    cpi temp3, 6
    brlt skipoverflow

    ; se chegou em 60:00, reseta tudo
    ldi temp3, 0
	sts digitos_cron+3, temp3

skip_cron:
	rjmp main_lp

skipoverflow:
    rjmp main_lp

;=============================
; check_button
; Verifica o estado do bot�o e atualiza o modo de exibi��o
;=============================
check_mode_button:
    sbic PINC, PC4  ; Pula se o bot�o n�o estiver pressionado
    rjmp button_mode_pressed

    ; Bot�o n�o pressionado
    clr button_mode_state
    ret

button_mode_pressed:
    cpi button_mode_state, 0
    brne button_check_end  ; Se j� estava pressionado, n�o faz nada

    ; Bot�o acabou de ser pressionado
    ldi button_mode_state, 1
    
    ; Avan�a para o pr�ximo modo
    inc display_mode
    cpi display_mode, 3
    brlo button_check_end
    clr display_mode  ; Volta para o modo 0 se ultrapassar 2

check_start_button:
    ; Se n�o estiver no modo 1, desconsidera o bot�o start
    cpi display_mode, 1
    brne button_check_end  ; Sai se n�o estiver no modo 1

    sbic PINC, PC5          ; Pula se o bot�o n�o estiver pressionado
    rjmp button_start_pressed ; Se o bot�o est� pressionado, vai para button_start_pressed

    clr button_start_state
	ret

button_start_pressed:
    ; Verifica se o bot�o j� foi pressionado
    cpi button_start_state, 0
    brne button_check_end   ; Se j� estava pressionado, reseta o estado

    ; Se n�o estava pressionado, marca como pressionado
    ldi button_start_state, 1 ; Marca o bot�o como pressionado
    ; Aqui voc� pode adicionar a l�gica para iniciar o cron�metro ou outra a��o
    rjmp invert_cron_state      ; Sai da fun��o

invert_cron_state:
    ldi temp, 1
	eor cron_status, temp


button_check_end:
    ret                        ; Retorna da fun��o

;=============================
; update_display
; Atualiza os displays de acordo com o modo atual
;=============================
update_display:
    cpi display_mode, 0
    breq display_normal
    cpi display_mode, 1
    breq display_cron
	
	; modo 3, exibe 1 1 1 1
    ldi ZH, high(display_table)
    ldi ZL, low(display_table)
    adiw ZL, 1   ; Avan�a para o padr�o do d�gito 1
    lpm temp, Z  ; Carrega o padr�o do um
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

display_cron:
	ldi show_cron, 1

	ldi ZH, high(display_table)
    ldi ZL, low(display_table)

    ; escolhe e exibe
    cpi display_index, 0
    breq disp0
    cpi display_index, 1
    breq disp1
    cpi display_index, 2
    breq disp2
    ; se n�o foi 0,1,2 ent�o � 3
    rjmp disp3

display_normal:
	ldi show_cron, 0

    ; carrega ponteiro da tabela
    ldi ZH, high(display_table)
    ldi ZL, low(display_table)

    ; escolhe e exibe
    cpi display_index, 0
    breq disp0
    cpi display_index, 1
    breq disp1
    cpi display_index, 2
    breq disp2
    ; se n�o foi 0,1,2 ent�o � 3
    rjmp disp3

disp0:  ; segundos unidades
    ldi ZH, high(display_table)
    ldi ZL, low(display_table)

    ; Carrega o valor dependendo do estado de r30
    cpi show_cron, 0
    breq load_relogio  ; Se cron_status � 0, carrega digitos_relogio
    lds temp2, digitos_cron  ; Caso contr�rio, carrega digitos_cron
    rjmp disp0_value

load_relogio:
    lds temp2, digitos_relogio  ; Carrega digitos_relogio
	rjmp disp0_value

disp1:  ; segundos dezenas
    ldi ZH, high(display_table)
    ldi ZL, low(display_table)

    ; Carrega o valor dependendo do estado de cron_status
    cpi show_cron, 0
    breq load_relogio_1  ; Se cron_status � 0, carrega digitos_relogio
    lds temp2, digitos_cron + 1  ; Caso contr�rio, carrega digitos_cron
	rjmp disp1_value

load_relogio_1:
    lds temp2, digitos_relogio + 1  ; Carrega digitos_relogio
	rjmp disp1_value

disp2:  ; minutos unidades
    ldi ZH, high(display_table)
    ldi ZL, low(display_table)

    ; Carrega o valor dependendo do estado de cron_status
    cpi show_cron, 0
    breq load_relogio_2  ; Se cron_status � 0, carrega digitos_relogio
    lds temp2, digitos_cron + 2  ; Caso contr�rio, carrega digitos_cron
    rjmp disp2_value

load_relogio_2:
    lds temp2, digitos_relogio + 2  ; Carrega digitos_relogio
	rjmp disp2_value

disp3:  ; minutos dezenas
    ldi ZH, high(display_table)
    ldi ZL, low(display_table)

    ; Carrega o valor dependendo do estado de cron_status
    cpi show_cron, 0
    breq load_relogio_3  ; Se cron_status � 0, carrega digitos_relogio
    lds temp2, digitos_cron + 3  ; Caso contr�rio, carrega digitos_cron
    rjmp disp3_value

load_relogio_3:
    lds temp2, digitos_relogio + 3  ; Carrega digitos_relogio
	rjmp disp3_value

disp0_value:
    add ZL, temp2
    clr temp
    adc ZH, temp
    lpm temp, Z
    out PORTD, temp         ; segmentos
    ldi temp, 1<<PC0
    out PORTB, temp         ; s� display 0 ligado
    rcall delay_5ms
    ldi temp, 0x00
    out PORTB, temp
	inc display_index
	rjmp disp1

disp1_value:
    add ZL, temp2
    clr temp
    adc ZH, temp
    lpm temp, Z
    out PORTD, temp         ; segmentos
    ldi temp, 1 << PC1
    out PORTB, temp         ; s� display 1 ligado
    rcall delay_5ms
    ldi temp, 0x00
    out PORTB, temp
	inc display_index
    rjmp disp2

disp2_value:
    add ZL, temp2
    clr temp
    adc ZH, temp
    lpm temp, Z
    out PORTD, temp         ; segmentos
    ldi temp, 1 << PC2
    out PORTB, temp         ; s� display 2 ligado
    rcall delay_5ms
    ldi temp, 0x00
    out PORTB, temp
	inc display_index
    rjmp disp3

disp3_value:
    add ZL, temp2
    clr temp
    adc ZH, temp
    lpm temp, Z
    out PORTD, temp         ; segmentos
    ldi temp, 1 << PC3
    out PORTB, temp         ; s� display 3 ligado
    rcall delay_5ms
    inc display_index
    cpi display_index, 4
    brlt dm_skip
    ldi display_index, 0

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