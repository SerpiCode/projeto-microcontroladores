.def temp            = r16
.def button_mode_state    = r17   ; Estado do bot?o (pressionado ou n?o)
.def temp2			 = r18
.def button_start_state    = r19
.def display_mode = r20
.def display_index = r21
.def cron_status = r22
.def show_cron = r23
.def button_reset_state = r24
.def ajuste_index = r25
.def piscar_flag = r26
.def piscar_count = r29

.dseg
digitos_relogio: .byte 4
digitos_cron: .byte 4
; sts - carrega do reg pro byte
; lds - le o byte e carrega no reg

.cseg

display_table:
    .db 0x7E,0x30,0x6D,0x79,0x33,0x5B,0x5F,0x70,0x7F,0x7B  ; padr?es 0?9

msg_header_modo1:
    .db "[MODO 1] ", 0    ; string terminada em zero

msg_header_modo2: 
	.db "[MODO 2] ", 0

msg_header_modo3: 
	.db "[MODO 3] ", 0

msg_header_modo2_start:
    .db "[MODO 2] START", 0

msg_header_modo2_reset:
    .db "[MODO 2] RESET", 0

msg_header_modo2_zero:
    .db "[MODO 2] ZERO", 0

msg_header_modo2_contando:
    .db "[MODO 2] CONTANDO", 0

;=============================
; Inicializacao
;=============================
    ; Pilha
    ldi temp, low(RAMEND)
    out SPL, temp
    ldi temp, high(RAMEND)
    out SPH, temp

    ; Configura PORTB para os segmentos dos displays (PB0-PB6 como saída)
    ldi temp, 0x7F
    out DDRB, temp
	; Configura PORTD para comunicação serial e controle dos transistores:
    ; PD0: entrada (RX), PD1: saída (TX), PD2 a PD5: saídas para transistores.
    ; (PD0=0, PD1=1, PD2=1, PD3=1, PD4=1, PD5=1, PD6=0, PD7=0) ? 0x3E (0b00111110)
    ldi temp, 0x3E
    out DDRD, temp

    ; PORTC = bot?o em PC4
	ldi temp, 0xCF  ; PC4 como entrada (0), o resto como sa?da (1)
	out DDRC, temp  ; Configura PORTC

	sbi PORTC, PC4  ; Habilita pull-up em PC4 - Modo
	sbi PORTC, PC5  ; Habilita pull-up em PC5 - Start/Pause
	sbi PORTC, PC3  ; Habilita pull-up em PC3 - Reset

	;=============================
	; Configurando a comunicação serial
	;=============================
    ; Configura baud rate para 9600 (UBRR = 103)
    ldi  r16, 103         ; valor baixo: 103 = 0x67
    sts  UBRR0L, r16
    ldi  r16, 0           ; valor alto: 0
    sts  UBRR0H, r16

    ; Habilita somente o transmissor (TXEN0) em UCSR0B
    ldi  r16, (1<<TXEN0)
    sts  UCSR0B, r16

    ; Configura o frame: 8 bits, sem paridade, 1 stop bit (por exemplo, UCSZ01 e UCSZ00 = 1)
    ldi  r16, (1<<UCSZ01)|(1<<UCSZ00)
    sts  UCSR0C, r16

    ; Zera contadores de tempo e multiplex
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
	ldi display_mode, 2
	clr button_reset_state

	ldi button_mode_state, 0
	ldi cron_status, 0
	ldi piscar_flag, 0

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
    ; 1) Muda de modo (PC4)
    rcall check_mode_button

    ; 2) Trata estouro do Timer1 ? blink + time update (1?Hz)
    in   temp, TIFR1
    andi temp, 1<<OCF1A
    breq skip_timer          ; sem estouro, pula tudo abaixo

    ; — houve estouro: limpa o flag
    ldi  temp, 1<<OCF1A
    out  TIFR1, temp

    ; — toggle de piscar (0.5?s on/off)
    inc  piscar_count
    cpi  piscar_count, 1
    brne no_blink_toggle
      ldi piscar_count, 0
      ldi temp, 1
      eor piscar_flag, temp
no_blink_toggle:

    ; — só atualiza relógio/cronômetro nos modos 0 e 1
    cpi  display_mode, 2
    breq skip_time_update
      rcall send_time_serial
      rcall update_time
skip_time_update:

skip_timer:
    ; 3) Multiplexa os displays (usa piscar_flag internamente)
    rcall update_display

    ; 4) Se for modo 3 (ajuste), chama ajustar_horario (lê PC5/PC3 sempre)
    cpi  display_mode, 2
    breq ajustar_horario

    ; 5) Nos modos 0/1, trata start/reset (cronômetro)
    rcall check_start_button
    rcall check_reset_button

    rjmp main_lp

ajustar_horario:
	; Seleção de dígito com botão PC5
	sbic PINC, 5
	rjmp no_select_button
	rcall debounce_select
		inc ajuste_index
		cpi ajuste_index, 4
		brlt no_select_button
		ldi ajuste_index, 0  ; volta ao início se passar de 3
	no_select_button:
	; Incremento de valor com botão PC3
	sbic PINC, 3
	rjmp no_inc_button
	rcall debounce_inc
		cpi ajuste_index, 0
		breq inc_hora_dezena
		cpi ajuste_index, 1
		breq inc_hora_unidade
		cpi ajuste_index, 2
		breq inc_min_dezena
		cpi ajuste_index, 3
		breq inc_min_unidade

	inc_hora_dezena:
		lds temp2, digitos_relogio+3
		inc temp2
		cpi temp2, 7
		brlt ok1
		ldi temp2, 0
		ok1:
		sts digitos_relogio+3, temp2
		rjmp no_inc_button

	inc_hora_unidade:
		lds temp2, digitos_relogio+2
		inc temp2
		cpi temp2, 10
		brne ok2
		ldi temp2, 0
		ok2:
		sts digitos_relogio+2, temp2
		rjmp no_inc_button
	
	inc_min_dezena:
		lds temp2, digitos_relogio+1
		inc temp2
		cpi temp2, 10
		brne ok3
		ldi temp2, 0
		ok3:
		sts digitos_relogio+1, temp2
		rjmp no_inc_button

	inc_min_unidade:
		lds temp2, digitos_relogio
		inc temp2
		cpi temp2, 10
		brne ok4
		ldi temp2, 0
		ok4:
		sts digitos_relogio, temp2
		rjmp no_inc_button

	no_inc_button:
		rjmp main_lp

	debounce_select:
	sbis PINC, 5
	rjmp debounce_select
	call delay_2ms
	wait_ds:
		dec r27
		brne wait_ds
		ret

	debounce_inc:
		sbis PINC, 3
		rjmp debounce_inc
		call delay_2ms
	wait_di:
		dec r27
		brne wait_di
		ret

update_time:
	;rcall send_time_serial	

	; Para a contagem no Modo 3
	cpi display_mode, 2
	breq update_cron_time

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
	lds temp2, digitos_cron
    inc temp2
	sts digitos_cron, temp2
    cpi temp2, 10
    brlt skipoverflow

    ldi temp2, 0
	sts digitos_cron, temp2
	lds temp2, digitos_cron+1
    inc temp2
	sts digitos_cron+1, temp2
    cpi temp2, 6
    brlt skipoverflow

    ldi temp2, 0
	sts digitos_cron+1, temp2
	lds temp2, digitos_cron+2
    inc temp2
	sts digitos_cron+2, temp2
    cpi temp2, 10
    brlt skipoverflow

    ldi temp2, 0
	sts digitos_cron+2, temp2
    lds temp2, digitos_cron+3
	inc temp2
	sts digitos_cron+3, temp2
    cpi temp2, 6
    brlt skipoverflow

    ; se chegou em 60:00, reseta tudo
    ldi temp2, 0
	sts digitos_cron+3, temp2

skip_cron:
	rjmp main_lp

skipoverflow:
    rjmp main_lp

;=============================
; check_button
; Verifica o estado do bot?o e atualiza o modo de exibi??o
;=============================
check_mode_button:
    sbic PINC, PC4  ; Pula se o bot?o n?o estiver pressionado
    rjmp button_mode_pressed

    ; Bot?o n?o pressionado
    clr button_mode_state
    ret

button_mode_pressed:
    cpi button_mode_state, 0
    brne button_check_end  ; Se j? estava pressionado, n?o faz nada

    ; Bot?o acabou de ser pressionado
    ldi button_mode_state, 1
    
    ; Avan?a para o pr?ximo modo
    inc display_mode
    cpi display_mode, 3
    brlo button_check_end
    clr display_mode  ; Volta para o modo 0 se ultrapassar 2

check_start_button:
    cpi display_mode, 1
    brne button_check_end

    sbic PINC, PC5          ; Pula se o bot?o n?o estiver pressionado
    rjmp button_start_pressed ; Se o bot?o est? pressionado, vai para button_start_pressed

    clr button_start_state
	ret

button_start_pressed:
    ; Verifica se o botao ja foi pressionado
    cpi button_start_state, 0
    brne button_check_end   ; Se ja estava pressionado, reseta o estado

    ; Se n?o estava pressionado, marca como pressionado
    ldi button_start_state, 1 ; Marca o bot?o como pressionado
    ; Aqui voc? pode adicionar a l?gica para iniciar o cron?metro ou outra a??o

	cpi display_mode, 1
    brne skip_start_message
    ;rjmp invert_cron_state      ; Sai da funcao

	; Envia "[MODO 2] START"
    push r16
    push r17
    push r30
    push r31
    ldi  ZH, high(2*msg_header_modo2_start)
    ldi  ZL, low(2*msg_header_modo2_start)
    rcall send_string
    ; Envia CR e LF 
    ldi  r17, 0x0D
    rcall send_char
    ldi  r17, 0x0A
    rcall send_char
    pop r31
    pop r30
    pop r17
    pop r16

skip_start_message:
    rjmp invert_cron_state

invert_cron_state:
    ldi temp, 1
	eor cron_status, temp

check_reset_button:
	cpi display_mode, 1
	brne button_check_end

	sbic PINC, PC3
	rjmp button_reset_pressed

    clr button_reset_state
	ret

button_check_end:
    ret                        ; Retorna da fun??o

button_reset_pressed:
    ; Verifica se o bot?o j? foi pressionado
    cpi button_reset_state, 0
    brne button_check_end   ; Se j? estava pressionado, reseta o estado

    ; Se nao estava pressionado, marca como pressionado
    ldi button_reset_state, 1 ; Marca o bot?o como pressionado

	; Verifica se está no modo 2 para enviar a mensagem
    cpi display_mode, 1
    brne skip_reset_message

	; Envia "[MODO 2] RESET"
    push r16
    push r17
    push r30
    push r31
    ldi  ZH, high(2*msg_header_modo2_reset)
    ldi  ZL, low(2*msg_header_modo2_reset)
    rcall send_string
    ; Envia CR e LF 
    ldi  r17, 0x0D
    rcall send_char
    ldi  r17, 0x0A
    rcall send_char
    pop r31
    pop r30
    pop r17
    pop r16

skip_reset_message:
    rjmp reset_cron

reset_cron:
	cpi cron_status, 1
	breq button_check_end
	ldi temp2, 0
	sts digitos_cron, temp2
	sts digitos_cron+1, temp2
	sts digitos_cron+2, temp2
	sts digitos_cron+3, temp2
	ldi cron_status, 0

	; Verifica se está no modo 2 para enviar a mensagem
    cpi display_mode, 1
    brne skip_zero_message
    
    ; Envia "[MODO 2] ZERO"
    push r16
    push r17
    push r30
    push r31
    ldi  ZH, high(2*msg_header_modo2_zero)
    ldi  ZL, low(2*msg_header_modo2_zero)
    rcall send_string
    ; Envia CR e LF 
    ldi  r17, 0x0D
    rcall send_char
    ldi  r17, 0x0A
    rcall send_char
    pop r31
    pop r30
    pop r17
    pop r16

skip_zero_message:
    ret   ; Adicione um retorno aqui
;=============================
; update_display
; Atualiza os displays de acordo com o modo atual
;=============================
update_display:
    cpi display_mode, 0
    breq display_normal
    cpi display_mode, 1
    breq display_cron
	cpi display_mode, 2
	rjmp display_normal ; modo 3
	
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
    ; se n?o foi 0,1,2 ent?o ? 3
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
    ; se n?o foi 0,1,2 ent?o ? 3
    rjmp disp3

disp0:  ; segundos unidades
    ldi ZH, high(display_table)
    ldi ZL, low(display_table)

    ; Carrega o valor dependendo do estado de r30
    cpi show_cron, 0
    breq load_relogio  ; Se cron_status ? 0, carrega digitos_relogio
    lds temp2, digitos_cron  ; Caso contr?rio, carrega digitos_cron
    rjmp disp0_value

load_relogio:
    lds temp2, digitos_relogio  ; Carrega digitos_relogio
	rjmp disp0_value

disp1:  ; segundos dezenas
    ldi ZH, high(display_table)
    ldi ZL, low(display_table)

    ; Carrega o valor dependendo do estado de cron_status
    cpi show_cron, 0
    breq load_relogio_1  ; Se cron_status ? 0, carrega digitos_relogio
    lds temp2, digitos_cron + 1  ; Caso contr?rio, carrega digitos_cron
	rjmp disp1_value

load_relogio_1:
    lds temp2, digitos_relogio + 1  ; Carrega digitos_relogio
	rjmp disp1_value

disp2:  ; minutos unidades
    ldi ZH, high(display_table)
    ldi ZL, low(display_table)

    ; Carrega o valor dependendo do estado de cron_status
    cpi show_cron, 0
    breq load_relogio_2  ; Se cron_status ? 0, carrega digitos_relogio
    lds temp2, digitos_cron + 2  ; Caso contr?rio, carrega digitos_cron
    rjmp disp2_value

load_relogio_2:
    lds temp2, digitos_relogio + 2  ; Carrega digitos_relogio
	rjmp disp2_value

disp3:  ; minutos dezenas
    ldi ZH, high(display_table)
    ldi ZL, low(display_table)

    ; Carrega o valor dependendo do estado de cron_status
    cpi show_cron, 0
    breq load_relogio_3  ; Se cron_status ? 0, carrega digitos_relogio
    lds temp2, digitos_cron + 3  ; Caso contr?rio, carrega digitos_cron
    rjmp disp3_value

load_relogio_3:
    lds temp2, digitos_relogio + 3  ; Carrega digitos_relogio
	rjmp disp3_value

disp0_value:
	cpi display_mode, 2
	brne skip_piscar0

	cpi ajuste_index, 3
	brne skip_piscar0

	cpi piscar_flag, 0
	breq apaga_disp0

	skip_piscar0:
    add ZL, temp2
    clr temp
    adc ZH, temp
    lpm temp, Z
    out PORTB, temp         ; segmentos
    ldi temp, 1<<PD2
    out PORTD, temp         ; so display 0 ligado
    rcall delay_5ms
    ldi temp, 0x00
    out PORTD, temp
	inc display_index
	rjmp disp1

apaga_disp0:
	; Se for pra piscar, apaga o display
    ldi temp, 0x00
    out PORTB, temp         ; segmentos apagados
    ldi temp, 1<<PD2
    out PORTD, temp         ; display ainda liga
    rcall delay_5ms
    ldi temp, 0x00
    out PORTD, temp
    inc display_index
    rjmp disp1		

disp1_value:
	cpi display_mode, 2
	brne skip_piscar1

	cpi ajuste_index, 2
	brne skip_piscar1

	cpi piscar_flag, 0
	breq apaga_disp1

	skip_piscar1:
    add ZL, temp2
    clr temp
    adc ZH, temp
    lpm temp, Z
    out PORTB, temp         ; segmentos
    ldi temp, 1<<PD3
    out PORTD, temp         ; so display 1 ligado
    rcall delay_5ms
    ldi temp, 0x00
    out PORTD, temp
	inc display_index
    rjmp disp2

apaga_disp1:
	; Se for pra piscar, apaga o display
    ldi temp, 0x00
    out PORTB, temp         ; segmentos apagados
    ldi temp, 1<<PD3
    out PORTD, temp         ; display ainda liga
    rcall delay_5ms
    ldi temp, 0x00
    out PORTD, temp
    inc display_index
    rjmp disp2	

disp2_value:
	cpi display_mode, 2
	brne skip_piscar2

	cpi ajuste_index, 1
	brne skip_piscar2

	cpi piscar_flag, 0
	breq apaga_disp2

	skip_piscar2:
    add ZL, temp2
    clr temp
    adc ZH, temp
    lpm temp, Z
    out PORTB, temp         ; segmentos
    ldi temp, 1<<PD4
    out PORTD, temp         ; so display 2 ligado
    rcall delay_5ms
    ldi temp, 0x00
    out PORTD, temp
	inc display_index
    rjmp disp3

apaga_disp2:
	; Se for pra piscar, apaga o display
    ldi temp, 0x00
    out PORTB, temp         ; segmentos apagados
    ldi temp, 1<<PD4
    out PORTD, temp         ; display ainda liga
    rcall delay_5ms
    ldi temp, 0x00
    out PORTD, temp
    inc display_index
    rjmp disp3

disp3_value:
	cpi display_mode, 2
	brne skip_piscar3

	cpi ajuste_index, 0
	brne skip_piscar3

	cpi piscar_flag, 0
	breq apaga_disp3

	skip_piscar3:
    add ZL, temp2
    clr temp
    adc ZH, temp
    lpm temp, Z
    out PORTB, temp         ; segmentos
    ldi temp, 1<<PD5
    out PORTD, temp         ; so display 3 ligado
    rcall delay_5ms
    inc display_index
    cpi display_index, 4
    brlt dm_skip
    ldi display_index, 0
	rjmp dm_skip

apaga_disp3:
	; Se for pra piscar, apaga o display
    ldi temp, 0x00
    out PORTB, temp         ; segmentos apagados
    ldi temp, 1<<PD5
    out PORTD, temp         ; display ainda liga
    rcall delay_5ms
    ldi temp, 0x00
    out PORTD, temp
    inc display_index
    cpi display_index, 4
    brlt dm_skip
    ldi display_index, 0

dm_skip:
    ; delay curto (~2?ms)
    rcall delay_2ms
    ret

;-----------------------------
; Envia um único caractere
; Entrada: r17 com o caractere a enviar
;-----------------------------
send_char:
    ; Espera enquanto o registrador de dados não estiver vazio
Wait_UDRE:
    lds  r16, UCSR0A
    sbrs r16, UDRE0	; Checa se o registrador de dados está vazio (livre para enviar)
    rjmp Wait_UDRE
    sts  UDR0, r17	; Grava o valor no endereço de memória UDR0 (registrador de dados UART)
    ret

;-----------------------------
; Envia uma string de caracteres
; O ponteiro Z (r30:r31) deve apontar para a string
;-----------------------------
send_string:
SendString_loop:
    lpm   r17, Z+
    cpi  r17, 0
    breq SendString_end
    rcall send_char
    rjmp SendString_loop
SendString_end:
    ret

;-----------------------------
; Envia a mensagem com o tempo formatado
; No formato: "[MODO 1] MM:SS"
; Utiliza os dados armazenados em digitos_relogio:
;  digitos_relogio+3 -> minutos dezenas
;  digitos_relogio+2 -> minutos unidades
;  digitos_relogio+1 -> segundos dezenas
;  digitos_relogio   -> segundos unidades
;-----------------------------
send_time_serial:
	cpi display_mode, 0
	breq send_modo1_serial
	cpi display_mode, 1
	breq send_modo2_serial
	cpi display_mode, 2
	breq send_modo3_serial
	ret

send_modo1_serial:
	push r16
	push r17
	push r30
	push r31

	; Envia o cabeçalho "[MODO 1] "
    ldi  ZH, high(2*msg_header_modo1)
    ldi  ZL, low(2*msg_header_modo1)
    rcall send_string

	; Envia os dígitos dos minutos:
    ; Minutos dezenas
    lds  r16, digitos_relogio+3
    ldi  r17, '0'
    add  r16, r17      ; converte para ASCII
    mov  r17, r16
    rcall send_char

    ; Minutos unidades
    lds  r16, digitos_relogio+2
    ldi  r17, '0'
    add  r16, r17
    mov  r17, r16
    rcall send_char

    ; Envia o separador ':'
    ldi  r17, ':'  
    rcall send_char

    ; Envia os dígitos dos segundos:
    ; Segundos dezenas
    lds  r16, digitos_relogio+1
    ldi  r17, '0'
    add  r16, r17
    mov  r17, r16
    rcall send_char

    ; Segundos unidades
    lds  r16, digitos_relogio
    ldi  r17, '0'
    add  r16, r17
    mov  r17, r16
    rcall send_char

    ; Opcional: Envia CR e LF para mudar de linha
    ldi  r17, 0x0D     ; Carriage Return
    rcall send_char
    ldi  r17, 0x0A     ; Line Feed
    rcall send_char

	pop r31
	pop r30
	pop r17
	pop r16

    ret

send_modo2_serial:
	; Verifica se o cronômetro está contando
    cpi cron_status, 1
    brne skip_modo2_message   ; Se não estiver contando, pula toda a função

	push r16
	push r17
	push r30
	push r31

	/*; Envia o cabeçalho "[MODO 2] "
    ldi  ZH, high(2*msg_header_modo2)
    ldi  ZL, low(2*msg_header_modo2)
    rcall send_string*/

	; Envia "[MODO 2] CONTANDO" somente se estiver contando
    ldi  ZH, high(2*msg_header_modo2_contando)
    ldi  ZL, low(2*msg_header_modo2_contando)
    rcall send_string

	; Opcional: Envia CR e LF para mudar de linha
    ldi  r17, 0x0D     ; Carriage Return
    rcall send_char
    ldi  r17, 0x0A     ; Line Feed
    rcall send_char

	pop r31
	pop r30
	pop r17
	pop r16

	ret

skip_modo2_message:
    ret

send_modo3_serial:
	push r16
	push r17
	push r30
	push r31

	; Envia o cabeçalho "[MODO 3] "
    ldi  ZH, high(2*msg_header_modo3)
    ldi  ZL, low(2*msg_header_modo3)
    rcall send_string

	; Opcional: Envia CR e LF para mudar de linha
    ldi  r17, 0x0D     ; Carriage Return
    rcall send_char
    ldi  r17, 0x0A     ; Line Feed
    rcall send_char

	pop r31
	pop r30
	pop r17
	pop r16
	
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