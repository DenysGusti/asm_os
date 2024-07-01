section	.data
    newline db 10
    ASCII_buffer times 20 db 0     ; buffer to store ASCII representation of the number
    ; strtok
    delim db ".", 0
    token_buffer dq 0

    port dw 1234

    AF_INET dd 2
    SOCK_STREAM dd 1
    INADDR_ANY dd 0

    bool_true dd 1
    SOL_SOCKET dd 1
    SO_REUSEADDR dd 2
    SO_RCVTIMEO dd 20

    sockfd dd 0
    connfd dd 0
    socket_error_msg db "create_server_socket: socket error", 10, 0
    bind_error_msg db "create_server_socket: bind error", 10, 0
    listen_error_msg db "create_server_socket: listen error", 10, 0

    addr_len dd 16
    ; sockaddr_in
    sin_family dw 0
    sin_port dw 0
    sin_addr dd 0
    sin_zero dq 0
    ; sockaddr_in
    conn_sin_family dw 0
    conn_sin_port dw 0
    conn_sin_addr dd 0
    conn_sin_zero dq 0
    ; timeval
    tv_sec dq 0
    tv_usec dq 0

    proto_add    dd 0
    proto_sub    dd 1
    proto_mul    dd 2
    proto_left_shift dd 3
    proto_right_shift dd 4

    ; message_unit
    msg_type dd 0
    server_info dd 0
    ; challenge_unit
    op dd 0
    lhs dd 0
    rhs dd 0
    answer dd 0
    ; message_unit
    responce_msg_type dd 0
    responce_server_info dd 0
    ; challenge_unit
    responce_op dd 0
    responce_lhs dd 0
    responce_rhs dd 0
    responce_answer dd 0

    debug db "debug", 10, 0

    correct db 0

    sent_expected_msg db "sent and expected:", 10, 0
    sent_again_msg db "sent again:", 10, 0
    send_buf_error_msg db "handle_client: send buf error", 10, 0
    recv_error_msg db "handle_client: recv error", 10, 0
    send_answer_error_msg db "handle_client: send answer error", 10, 0

section	.text
    global _start
	
_start:
    call create_server_socket
    test rax, rax
    jl .exit_mainloop_1

    .mainloop:
        call accept_wrapper
        test rax, rax
        jl .exit_mainloop_1

        call handle_client
        push rax

        ; sys_close
        mov rax, 3
        mov	rdi, [connfd]
        syscall

        pop rax
        test rax, rax
        jg .mainloop

    .exit_mainloop_0:
        ; sys_close
        mov rax, 3
        mov	rdi, [sockfd]
        syscall
        ; sys_exit
        mov	rax, 60
        mov	rdi, 0
        syscall

    .exit_mainloop_1:
        ; sys_exit
        mov	rax, 60
        mov	rdi, 1
        syscall

handle_client:
    call set_socket_timeout

    mov [msg_type], dword 0

    ; sys_getrandom
    mov	rax, 318
    mov	rdi, op
    mov	rsi, 4
    mov rdx, 0
    syscall

    mov eax, dword [op]
    mov ecx, 5
    xor edx, edx
    div ecx
    mov [op], edx

    ; sys_getrandom
    mov	rax, 318
    mov	rdi, lhs
    mov	rsi, 4
    mov rdx, 0
    syscall

    ; sys_getrandom
    mov	rax, 318
    mov	rdi, rhs
    mov	rsi, 4
    mov rdx, 0
    syscall

    ; sys_sendto
    mov	rax, 44
    mov	rdi, [connfd]
    mov	rsi, msg_type ; &buf
    mov rdx, 24
    mov r10, 0
    mov r8, 0
    mov r9, 0
    syscall

    test rax, rax
    jl .send_buf_error

    ; sys_write with strlen
    mov	rdi, sent_expected_msg
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rsi, rdi
    mov	rdi, 1
    syscall

    call calculate_answer
    call print_message_unit
    call print_challenge_unit

    ; sys_recvfrom
    mov	rax, 45
    mov	rdi, [connfd]
    mov	rsi, responce_msg_type ; &buf
    mov rdx, 24
    mov r10, 0
    mov r8, 0
    mov r9, 0
    syscall

    test rax, rax
    jl .recv_error

    call check_response
    mov [msg_type], dword 1
    movzx rax, byte [correct]
    test al, al
    setz al ; set al to 1 if zero flag is set (al was 0), otherwise set to 0
    mov [server_info], eax

    ; sys_write with strlen
    mov	rdi, sent_again_msg
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rsi, rdi
    mov	rdi, 1
    syscall

    call print_message_unit

    ; sys_sendto
    mov	rax, 44
    mov	rdi, [connfd]
    mov	rsi, msg_type ; &answer_msg
    mov rdx, 8
    mov r10, 0
    mov r8, 0
    mov r9, 0
    syscall

    test rax, rax
    jl .send_answer_error

    mov rax, 1
    ret

    .send_answer_error:
        ; sys_write with strlen
        mov	rdi, send_answer_error_msg
        call strlen
        mov	rdx, rax
        mov	rax, 1
        mov	rsi, rdi
        mov	rdi, 1
        syscall

        xor rax, rax
        ret

    .recv_error:
        ; sys_write with strlen
        mov	rdi, recv_error_msg
        call strlen
        mov	rdx, rax
        mov	rax, 1
        mov	rsi, rdi
        mov	rdi, 1
        syscall

        xor rax, rax
        ret

    .send_buf_error:
        ; sys_write with strlen
        mov	rdi, send_buf_error_msg
        call strlen
        mov	rdx, rax
        mov	rax, 1
        mov	rsi, rdi
        mov	rdi, 1
        syscall

        xor rax, rax
        ret

check_response:
    mov eax, [answer]
    mov ebx, [responce_answer]
    cmp eax, ebx
    jne .not_equal

    mov eax, [op]
    mov ebx, [responce_op]
    cmp eax, ebx
    jne .not_equal

    mov eax, [lhs]
    mov ebx, [responce_lhs]
    cmp eax, ebx
    jne .not_equal

    mov eax, [rhs]
    mov ebx, [responce_rhs]
    cmp eax, ebx
    jne .not_equal

    mov eax, [msg_type]
    mov ebx, [responce_msg_type]
    cmp eax, ebx
    jne .not_equal

    mov eax, [server_info]
    mov ebx, [responce_server_info]
    cmp eax, ebx
    jne .not_equal

    mov byte [correct], 1
    ret
    .not_equal:
         mov byte [correct], 0
         ret

calculate_answer:
    mov eax, [op]
    cmp eax, [proto_add]
    je .add_case
    cmp eax, [proto_sub]
    je .sub_case
    cmp eax, [proto_mul]
    je .mul_case
    cmp eax, [proto_left_shift]
    je .left_shift_case
    cmp eax, [proto_right_shift]
    je .right_shift_case
    .add_case:
        mov eax, [lhs]
        add eax, [rhs]
        mov [answer], eax
        ret
    .sub_case:
        mov eax, [lhs]
        sub eax, [rhs]
        mov [answer], eax
        ret
    .mul_case:
        mov eax, [lhs]
        imul eax, [rhs]
        mov [answer], eax
        ret
    .left_shift_case:
        mov eax, [lhs]
        mov ecx, [rhs]
        and ecx, 31
        shl eax, cl
        mov [answer], eax
        ret
    .right_shift_case:
        mov eax, [lhs]
        mov ecx, [rhs]
        and ecx, 31
        shr eax, cl
        mov [answer], eax
        ret

set_socket_timeout:
    mov rax, 50000
    mov [tv_usec], rax

    ; sys_setsockopt
    mov	rax, 54
    mov	rdi, [sockfd]
    mov	rsi, [SOL_SOCKET]
    mov rdx, [SO_RCVTIMEO]
    mov r10, tv_sec ; &timeout
    mov r8, 16
    syscall

    ret

accept_wrapper:
    ; sys_accept
    mov	rax, 43
    mov	rdi, [sockfd]
    mov	rsi, conn_sin_family ; &addr
    mov rdx, addr_len
    syscall

    mov [connfd], rax
    ret

create_server_socket:
    ; sys_socket
    mov	rax, 41
    mov	rdi, [AF_INET]
    mov	rsi, [SOCK_STREAM]
    mov rdx, 0
    syscall

    mov [sockfd], eax
    test rax, rax
    jl .socket_error

    ; sys_setsockopt
    mov	rax, 54
    mov	rdi, [sockfd]
    mov	rsi, [SOL_SOCKET]
    mov rdx, [SO_REUSEADDR]
    mov r10, bool_true
    mov r8, 4
    syscall

    mov rax, [AF_INET]
    mov [sin_family], ax
    mov rax, [port]
    call htons
    mov [sin_port], ax
    mov rax, [INADDR_ANY]
    mov [sin_addr], eax

    ; sys_bind
    mov	rax, 49
    mov	rdi, [sockfd]
    mov	rsi, sin_family ; &addr
    mov rdx, 16
    syscall

    test rax, rax
    jl .bind_error

    ; sys_listen
    mov	rax, 50
    mov	rdi, [sockfd]
    mov	rsi, 1
    syscall

    test rax, rax
    jl .listen_error
    ret

    .listen_error:
        ; sys_close
        mov rax, 3
        mov	rdi, [sockfd]
        syscall
        ; sys_write with strlen
        mov	rdi, listen_error_msg
        call strlen
        mov	rdx, rax
        mov	rax, 1
        mov	rsi, rdi
        mov	rdi, 1
        syscall

        mov rax, -1
        ret

    .bind_error:
        ; sys_close
        mov rax, 3
        mov	rdi, [sockfd]
        syscall
        ; sys_write with strlen
        mov	rdi, bind_error_msg
        call strlen
        mov	rdx, rax
        mov	rax, 1
        mov	rsi, rdi
        mov	rdi, 1
        syscall

        mov rax, -1
        ret

    .socket_error:
        ; sys_write with strlen
        mov	rdi, socket_error_msg
        call strlen
        mov	rdx, rax
        mov	rax, 1
        mov	rsi, rdi
        mov	rdi, 1
        syscall

        mov rax, -1
        ret

print_message_unit:
    ; sys_write int with strlen
    mov eax, [msg_type]
    call itoa   ; number in rax, buffer in rsi, uses rcx, rdx
    mov	rdi, rsi
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rdi, 1
    syscall

    call println

    ; sys_write int with strlen
    mov eax, [server_info]
    call itoa   ; number in rax, buffer in rsi, uses rcx, rdx
    mov	rdi, rsi
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rdi, 1
    syscall

    call println
    ret

print_challenge_unit:
    ; sys_write int with strlen
    mov eax, [op]
    call itoa   ; number in rax, buffer in rsi, uses rcx, rdx
    mov	rdi, rsi
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rdi, 1
    syscall

    call println

    ; sys_write int with strlen
    mov eax, [lhs]
    call itoa   ; number in rax, buffer in rsi, uses rcx, rdx
    mov	rdi, rsi
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rdi, 1
    syscall

    call println

    ; sys_write int with strlen
    mov eax, [rhs]
    call itoa   ; number in rax, buffer in rsi, uses rcx, rdx
    mov	rdi, rsi
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rdi, 1
    syscall

    call println

    ; sys_write int with strlen
    mov eax, [answer]
    call itoa   ; number in rax, buffer in rsi, uses rcx, rdx
    mov	rdi, rsi
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rdi, 1
    syscall

    call println
    ret

htons:
    xchg al, ah
    ret

debug_point:
        push rdi
        push rsi
        push rax
        push rbx
        push rcx
        push rdx
        ; sys_write with strlen
        mov rdi, debug
        call strlen
        mov	rdx, rax
        mov	rax, 1
        mov	rsi, rdi
        mov	rdi, 1
        syscall
        pop rdx
        pop rcx
        pop rbx
        pop rax
        pop rsi
        pop rdi
        ret

; const char * str in rsi, const char * delim in rdi, return value (const char *) in rax
strtok:
    mov rcx, [token_buffer]
    cmp rsi, 0 ; if (str != nullptr)
    jne .set_buffer
    .check_buffer:
        cmp byte [rcx], 0    ; if (*buffer == '\0')
        je .ret_null
        mov rax, rcx    ; char *ret = buffer;
        mov rbx, rcx    ; char *b = buffer;
    .outer_loop:
        cmp byte [rbx], 0  ; while (*b != '\0')
        je .end_strtok_end
        mov rdx, rdi    ; const char *d = delim;
    .inner_loop:
        cmp byte [rdx], 0  ; while (*d != '\0')
        je .outer_loop_inc
        mov r15b, byte [rdx]
        cmp byte [rbx], r15b    ; if (*b == *d)
        jne .inner_loop_inc
        mov byte [rbx], 0   ; *b = '\0';
        mov rcx, rbx
        inc rcx ; buffer = b + 1;
        cmp rbx, rax    ; if (b != ret) // skip the beginning delimiters
        jne .end_strtok
        inc rax ; ++ret;
        jmp .outer_loop_inc
    .inner_loop_inc:
        inc rdx ; ++d;
        jmp .inner_loop
    .outer_loop_inc:
        inc rbx ; ++b;
        jmp .outer_loop
    .set_buffer:
        mov rcx, rsi    ; buffer = str;
        jmp .check_buffer
    .ret_null:
        xor rax, rax    ; return nullptr;
    .end_strtok:
        mov [token_buffer], rcx
        ret ; return ret;
    .end_strtok_end:
        mov [token_buffer], rbx
        ret ; return ret;

; char in al, return value (bool) in rax
is_digit:
    cmp al, '0'
    jl .not_digit
    cmp al, '9'
    jg .not_digit
    mov rax, 1
    ret
    .not_digit:
        xor rax, rax
        ret

; const char * in rdi, return value (bool) in rax
str_is_digit:
    call strlen
    test rax, rax
    jz .char_not_digit
    .check_next_char:
        mov al, [rdi]
        test al, al
        jz .all_chars_digits
        call is_digit
        test rax, rax
        jz .char_not_digit
        inc rdi
        jmp .check_next_char 
    .char_not_digit:
        xor rax, rax
        ret
    .all_chars_digits:
        mov rax, 1
        ret

; const char * integer in rdi, return value (int) in rax
atoi:
    xor rax, rax
    xor rcx, rcx
    .next_digit:
        movzx rcx, byte [rdi]
        test rcx, rcx
        jz .end_of_string
        cmp rcx, '0'
        jl .not_digit
        cmp rcx, '9'
        jg .not_digit
        sub rcx, '0'
        imul rax, 10
        add rax, rcx
        inc rdi
        jmp .next_digit
    .not_digit:
        ret
    .end_of_string:
        ret

; const char * integer in rdi, return value (int) in rax
atoi_hex:
    xor rax, rax
    xor rcx, rcx
    .next_digit:
        movzx rcx, byte [rdi]
        test rcx, rcx
        jz .end_of_string
        cmp rcx, 'a'
        jl .numeric
        cmp rcx, 'f'
        jg .not_digit
        sub rcx, 'a' - 10
        jmp .store_digit
    .numeric:
        cmp rcx, '0'
        jl .not_digit
        cmp rcx, '9'
        jg .not_digit
        sub rcx, '0'
    .store_digit:
        imul rax, 16
        add rax, rcx
        inc rdi
        jmp .next_digit
    .not_digit:
        ret
    .end_of_string:
        ret

; const char * str1 in rsi, const char * str2 in rdi, return value (int) in rax
strcmp:
    .compare_loop:
        mov al, byte [rsi]
        mov bl, byte [rdi]
        cmp al, bl
        jne .unequal
        test al, al
        jz .end_of_strings
        inc rsi
        inc rdi
        jmp .compare_loop
    .unequal:
        sub rax, rbx
        ret
    .end_of_strings:
        xor rax, rax
        ret

; const char * source in rsi, const char * destination in rdi
strcpy:
    .copy_loop:
        mov al, byte [rsi]
        mov byte [rdi], al
        test al, al
        jz .end_copy
        inc rsi
        inc rdi
        jmp .copy_loop
    .end_copy:
        ret

println:
    ; sys_write
    mov	rax, 1
    mov	rdi, 1
    mov	rsi, newline
    mov	rdx, 1
    syscall
    ret

; const char * in rdi, return value (int) in rax
strlen:
    xor rax, rax    ; string length in rax, zeroed
    .find_null_byte:
        cmp byte [rdi + rax], 0 ; rdi[rax] == '\0', byte size operands
        je .end ; break if true
        inc rax ; ++rax
        jmp .find_null_byte
    .end:
        ret

; integer in rax, return value (const char *) in rsi
itoa:
    ; convert the number to its ASCII representation
    mov rsi, ASCII_buffer + 19  ; rsi is last element in buffer
    mov byte [rsi], 0   ; null terminate the buffer
    dec rsi ; move pointer to the previous byte
    mov rcx, 10 ; set divisor, rax % 10
    .mod10:
        xor rdx, rdx    ; zeroed remainder
        div rcx ; divide rax by 10; result goes in rax, remainder in rdx
        add dl, '0' ; convert remainder to ASCII
        mov [rsi], dl   ; store ASCII character in the buffer
        dec rsi ; move pointer to the previous byte
        test rax, rax ; if rax != 0
        jnz .mod10  ; repeat until quotient is zero
    inc rsi ; after "dec rsi" move pointer to the next byte, last stored ASCII character in the buffer
    ret
