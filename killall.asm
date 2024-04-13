section	.data
    newline db 10
    ASCII_buffer times 20 db 0     ; buffer to store ASCII representation of the number

    proc_dir db "/proc/", 0
    AT_FDCWD dq -100
    O_RDONLY dq 00
    SIGKILL dq 9
    comm db "/comm", 0
    getdents64_ret db " - getdents64 return value", 0

    proc_file_descriptor dd 0
    comm_file_descriptor dd 0
    comm_buffer db 64 dup(0)
    comm_name_buffer db 64 dup(0)

    ; struct dirent64
    d_ino dq 0
    d_off dq 0
    d_reclen dw 0
    d_type db 0
    d_name db 256 dup(0)
    d_padding db 5 dup(0)   ; 275 + 5 = 280

section	.text
    global _start
	
_start:
    ; sys_openat
    mov rax, 257
    mov	rdi, [AT_FDCWD]
    mov rsi, proc_dir
    mov rdx, [O_RDONLY]
    syscall

    mov [proc_file_descriptor], eax

read_loop:
    ; sys_getdents64
    mov	rdi, [proc_file_descriptor]
    mov rax, 217
    mov rsi, d_ino  ; &buf
    mov rdx, 40    ; count, optimal value is brute-forced
    syscall
    test rax, rax
    jle close_directory    ; On end of directory, 0 is returned. On error, -1 is returned.

    mov	rdi, d_name
    mov rsi, rdi
    call str_is_digit
    test rax, rax
    jz read_loop

    ; call output_dirent64

    mov rdi, comm_buffer
    mov rsi, proc_dir
    call strcpy
    ; comm_buffer = "/proc/"

    mov rdi, comm_buffer
    call strlen
    add rdi, rax
    mov rsi, d_name
    call strcpy
    ; comm_buffer = "/proc/{pid}"

    mov rdi, comm_buffer
    call strlen
    add rdi, rax
    mov rsi, comm
    call strcpy
    ; comm_buffer = "/proc/{pid}/comm"

    ; sys_openat
    mov rax, 257
    mov	rdi, [AT_FDCWD]
    mov rsi, comm_buffer
    mov rdx, [O_RDONLY]
    syscall

    mov [comm_file_descriptor], eax

    ; sys_read
    mov rax, 0
    mov	rdi, [comm_file_descriptor]
    mov rsi, comm_name_buffer
    mov rdx, 64
    syscall ; On success, the number of bytes read is returned.

    mov rdi, comm_name_buffer
    add rdi, rax
    dec rdi
    mov byte [rdi], 0   ; comm_name_buffer is now zero-terminated

    ; sys_close
    mov rax, 3
    mov	rdi, [comm_file_descriptor]
    syscall

    ; sys_write with strlen
    mov	rdi, comm_name_buffer
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rsi, rdi
    mov	rdi, 1
    syscall

    call println

    ; sys_write with strlen
    mov	rdi, d_name
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rsi, rdi
    mov	rdi, 1
    syscall

    call println

    mov rsi, comm_name_buffer
    ; rsp = argc, argv[1] = argc + 8 bytes sizeof(int) + 8 bytes sizeof(char *)
    mov	rdi, [rsp + 8 + 8]  ; argv[0] program name, argv[1] first argument
    call strcmp
    test rax, rax
    jnz read_loop

    mov	rdi, d_name
    call atoi

    ; sys_kill
    mov rdi, rax    ; pid
    mov rax, 62
    mov rsi, [SIGKILL]
    syscall

    call println

    jmp read_loop

close_directory:
    call itoa   ; number in rax, buffer in rsi, uses rcx, rdx

    ; sys_write int with strlen
    mov	rdi, rsi
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rdi, 1
    syscall

    ; sys_write with strlen
    mov	rdi, getdents64_ret
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rsi, rdi
    mov	rdi, 1
    syscall

    call println

    ; sys_close
    mov rax, 3
    mov	rdi, [proc_file_descriptor]
    syscall

    ; sys_exit
    mov	rax, 60
    mov	rdi, 0
    syscall

; dirent64 in buf
output_dirent64:
    mov rax, [d_ino]
    call itoa   ; number in rax, buffer in rsi, uses rcx, rdx

    ; sys_write int with strlen
    mov	rdi, rsi
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rdi, 1
    syscall

    call println

    mov rax, [d_off]
    call itoa   ; number in rax, buffer in rsi, uses rcx, rdx

    ; sys_write int with strlen
    mov	rdi, rsi
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rdi, 1
    syscall

    call println

    mov ax, [d_reclen]
    call itoa   ; number in rax, buffer in rsi, uses rcx, rdx

    ; sys_write int with strlen
    mov	rdi, rsi
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rdi, 1
    syscall

    call println

    mov al, [d_type]
    call itoa   ; number in rax, buffer in rsi, uses rcx, rdx

    ; sys_write int with strlen
    mov	rdi, rsi
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rdi, 1
    syscall

    call println

    ; sys_write with strlen
    mov	rdi, d_name
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rdi, 1
    mov	rsi, d_name
    syscall

    call println
    call println
    ret

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
    ; Convert the number to its ASCII representation
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
