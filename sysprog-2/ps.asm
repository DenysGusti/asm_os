section	.data
    newline db 10
    ASCII_buffer times 20 db 0     ; buffer to store ASCII representation of the number
    ; strtok
    delim db " ", 0
    token_buffer dq 0

    proc_dir db "/proc/", 0
    AT_FDCWD dq -100
    O_RDONLY dq 00
    error dq 18446744073709551603
    getdents64_ret db " - getdents64 return value", 0
    openat_ret db " - openat return value", 0
    debug_point db "here", 0

    proc_file_descriptor dd 0

    exe_folder db "/exe", 0
    cwd_folder db "/cwd", 0
    maps_folder db "/maps", 0
    stat_folder db "/stat", 0
    cmdline_folder db "/cmdline", 0
    file_descriptor dd 0
    string_builder_buffer db 64 dup(0)
    line_buffer db 8192 dup(0)

    tmp_buffer db 8192 dup(0)

    json_pid db 123, 34, "pid", 34, ":", 0  ; {"pid":
    json_exe db ",", 34, "exe", 34, ":", 34, 0  ; ,"exe":"
    json_cwd db 34, ",", 34, "cwd", 34, ":", 34, 0  ; ","cwd":"
    json_base_address db 34, ",", 34, "base_address", 34, ":", 0  ; ","base_address":
    json_state db ",", 34, "state", 34, ":", 34, 0  ; ,"state":"
    json_cmdline_begin db 34, ",", 34, "cmdline", 34, ":", 91, 0  ; ","cmdline":[
    json_cmdline_entry db 34, ",", 0  ; ",
    json_cmdline_end db 93, 125, ",", 0  ; ]},
    json_buffer db 1048576 dup(0)

    ; struct dirent64
    d_ino dq 0
    d_off dq 0
    d_reclen dw 0
    d_type db 0
    d_name db 256 dup(0)
    d_padding db 5 dup(0)   ; 275 + 5 = 280

    ; struct process_info
    _pid dq 0
    _exe db 128 dup(0)
    _cwd db 128 dup(0)
    _base_address dq 0
    _state db 0
    _cmdline dq 8192 dup(0) ; args separated by space

section	.text
    global _start
	
_start:
    mov byte [json_buffer], 91

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

    call collect_info
    test rax, rax
    jnz read_loop

    call create_json

    jmp read_loop

close_directory:
    ; sys_close
    mov rax, 3
    mov	rdi, [proc_file_descriptor]
    syscall

    ; trim last ,
    mov rdi, json_buffer
    call strlen
    dec rax
    mov byte [rdi + rax], 0

    mov	rdi, json_buffer
    call strlen
    mov byte [rdi + rax], 93

    ; sys_write with strlen
    mov	rdi, json_buffer
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rsi, rdi
    mov	rdi, 1
    syscall

    ; sys_exit
    mov	rax, 60
    mov	rdi, 0
    syscall

collect_info:
    mov	rdi, d_name
    call atoi
    mov [_pid], rax

    mov rdi, string_builder_buffer
    mov rsi, proc_dir
    call strcpy
    ; string_builder_buffer = "/proc/"

    mov rdi, string_builder_buffer
    call strlen
    add rdi, rax
    mov rsi, d_name
    call strcpy
    ; string_builder_buffer = "/proc/{pid}"

    mov rdi, string_builder_buffer
    call strlen
    add rdi, rax
    mov rsi, exe_folder
    call strcpy
    ; string_builder_buffer = "/proc/{pid}/exe"

    ; sys_readlink
    mov rax, 89
    mov	rdi, string_builder_buffer
    mov rsi, _exe
    mov rdx, 128
    syscall ; On success, the number of bytes read is returned.

    mov rbx, rax
    sub rbx, [error]
    test rbx, rbx
    jz .access_denied

    mov rdi, _exe
    add rdi, rax
    mov byte [rdi], 0   ; _exe is now zero-terminated

    mov rdi, string_builder_buffer
    mov rsi, proc_dir
    call strcpy
    ; string_builder_buffer = "/proc/"

    mov rdi, string_builder_buffer
    call strlen
    add rdi, rax
    mov rsi, d_name
    call strcpy
    ; string_builder_buffer = "/proc/{pid}"

    mov rdi, string_builder_buffer
    call strlen
    add rdi, rax
    mov rsi, cwd_folder
    call strcpy
    ; string_builder_buffer = "/proc/{pid}/cwd"

    ; sys_readlink
    mov rax, 89
    mov	rdi, string_builder_buffer
    mov rsi, _cwd
    mov rdx, 128
    syscall ; On success, the number of bytes read is returned.

    mov rbx, rax
    sub rbx, [error]
    test rbx, rbx
    jz .access_denied

    mov rdi, _cwd
    add rdi, rax
    mov byte [rdi], 0   ; _cwd is now zero-terminated

    mov rdi, string_builder_buffer
    mov rsi, proc_dir
    call strcpy
    ; string_builder_buffer = "/proc/"

    mov rdi, string_builder_buffer
    call strlen
    add rdi, rax
    mov rsi, d_name
    call strcpy
    ; string_builder_buffer = "/proc/{pid}"

    mov rdi, string_builder_buffer
    call strlen
    add rdi, rax
    mov rsi, maps_folder
    call strcpy
    ; string_builder_buffer = "/proc/{pid}/maps"

    ; sys_openat
    mov rax, 257
    mov	rdi, [AT_FDCWD]
    mov rsi, string_builder_buffer
    mov rdx, [O_RDONLY]
    syscall

    mov [file_descriptor], eax

    ; sys_read
    mov rax, 0
    mov	rdi, [file_descriptor]
    mov rsi, line_buffer
    mov rdx, 8192
    syscall ; On success, the number of bytes read is returned.

    mov rdi, line_buffer
    add rdi, rax
    dec rdi
    mov byte [rdi], 0   ; line_buffer is now zero-terminated

    ; sys_close
    mov rax, 3
    mov	rdi, [file_descriptor]
    syscall

    mov rdi, line_buffer
    call atoi_hex
    mov [_base_address], rax

    mov rdi, string_builder_buffer
    mov rsi, proc_dir
    call strcpy
    ; string_builder_buffer = "/proc/"

    mov rdi, string_builder_buffer
    call strlen
    add rdi, rax
    mov rsi, d_name
    call strcpy
    ; string_builder_buffer = "/proc/{pid}"

    mov rdi, string_builder_buffer
    call strlen
    add rdi, rax
    mov rsi, stat_folder
    call strcpy
    ; string_builder_buffer = "/proc/{pid}/stat"

    ; sys_openat
    mov rax, 257
    mov	rdi, [AT_FDCWD]
    mov rsi, string_builder_buffer
    mov rdx, [O_RDONLY]
    syscall

    mov [file_descriptor], eax

    ; sys_read
    mov rax, 0
    mov	rdi, [file_descriptor]
    mov rsi, line_buffer
    mov rdx, 8192
    syscall ; On success, the number of bytes read is returned.

    mov rdi, line_buffer
    add rdi, rax
    dec rdi
    mov byte [rdi], 0   ; line_buffer is now zero-terminated

    ; sys_close
    mov rax, 3
    mov	rdi, [file_descriptor]
    syscall

    mov rsi, line_buffer
    mov	rdi, delim
    call strtok
    mov rsi, 0
    mov	rdi, delim
    call strtok
    mov rsi, 0
    mov	rdi, delim
    call strtok
    mov rbx, [rax]
    mov [_state], rbx

    mov rdi, string_builder_buffer
    mov rsi, proc_dir
    call strcpy
    ; string_builder_buffer = "/proc/"

    mov rdi, string_builder_buffer
    call strlen
    add rdi, rax
    mov rsi, d_name
    call strcpy
    ; string_builder_buffer = "/proc/{pid}"

    mov rdi, string_builder_buffer
    call strlen
    add rdi, rax
    mov rsi, cmdline_folder
    call strcpy
    ; string_builder_buffer = "/proc/{pid}/cmdline"

    ; sys_openat
    mov rax, 257
    mov	rdi, [AT_FDCWD]
    mov rsi, string_builder_buffer
    mov rdx, [O_RDONLY]
    syscall

    mov [file_descriptor], eax

    ; sys_read
    mov rax, 0
    mov	rdi, [file_descriptor]
    mov rsi, line_buffer
    mov rdx, 8192
    syscall ; On success, the number of bytes read is returned.

    mov rdi, line_buffer
    add rdi, rax
    dec rdi
    mov byte [rdi], 0   ; line_buffer is now zero-terminated

    call change_delim

    ; sys_close
    mov rax, 3
    mov	rdi, [file_descriptor]
    syscall

    call add_escape_character_to_quotes

    mov rsi, line_buffer
    mov rdi, _cmdline
    call strcpy

    xor	rax, rax
    ret
    
    .access_denied:
        mov rax, 1
        ret

create_json:
    mov rdi, json_buffer
    call strlen
    add rdi, rax
    mov rsi, json_pid
    call strcpy

    mov rax, [_pid]
    call itoa   ; number in rax, buffer in rsi, uses rcx, rdx

    mov rdi, json_buffer
    call strlen
    add rdi, rax
    call strcpy

    mov rdi, json_buffer
    call strlen
    add rdi, rax
    mov rsi, json_exe
    call strcpy

    mov rdi, json_buffer
    call strlen
    add rdi, rax
    mov rsi, _exe
    call strcpy

    mov rdi, json_buffer
    call strlen
    add rdi, rax
    mov rsi, json_cwd
    call strcpy

    mov rdi, json_buffer
    call strlen
    add rdi, rax
    mov rsi, _cwd
    call strcpy

    mov rdi, json_buffer
    call strlen
    add rdi, rax
    mov rsi, json_base_address
    call strcpy

    mov rax, [_base_address]
    call itoa   ; number in rax, buffer in rsi, uses rcx, rdx

    mov rdi, json_buffer
    call strlen
    add rdi, rax
    call strcpy

    mov rdi, json_buffer
    call strlen
    add rdi, rax
    mov rsi, json_state
    call strcpy

    mov rdi, json_buffer
    call strlen
    mov bl, [_state]
    mov [rdi + rax], bl

    mov rdi, json_buffer
    call strlen
    add rdi, rax
    mov rsi, json_cmdline_begin
    call strcpy

    mov rsi, _cmdline
    mov rdi, delim
    call strtok
    mov rbx, rax

    .cmdline_loop_begin:
        test rbx, rbx
        jz .cmdline_loop_end

        mov rdi, json_buffer
        call strlen
        mov byte [rdi + rax], 34    ; "

        mov rdi, json_buffer
        call strlen
        add rdi, rax
        mov rsi, rbx
        call strcpy

        mov rdi, json_buffer
        call strlen
        add rdi, rax
        mov rsi, json_cmdline_entry
        call strcpy

        mov rsi, 0
        mov rdi, delim
        call strtok
        mov rbx, rax

        jmp .cmdline_loop_begin

    .cmdline_loop_end:

    ; trim last ,
    mov rdi, json_buffer
    call strlen
    dec rax
    mov byte [rdi + rax], 0

    mov rdi, json_buffer
    call strlen
    add rdi, rax
    mov rsi, json_cmdline_end
    call strcpy    

    ret

add_escape_character_to_quotes:
    mov rdi, line_buffer
    call strlen
    mov rbx, rax
    xor rcx, rcx
    xor r15, r15
    .escape_character_loop_begin:
        cmp rcx, rbx
        je .escape_character_loop_end
        cmp byte [rdi + rcx], 34 ; "
        jne .escape_character_loop_increment
        mov rsi, rdi
        add rsi, rcx
        mov rdi, tmp_buffer
        call strcpy
        mov rsi, tmp_buffer
        mov rdi, line_buffer
        add rdi, rcx
        inc rdi
        call strcpy
        inc rbx
        mov rdi, line_buffer
        mov byte [rdi + rcx], 92 ; \
        ; don't delete this comment, ^ backslash
        inc rcx
        inc r15
    .escape_character_loop_increment:
        inc rcx
        jmp .escape_character_loop_begin
    .escape_character_loop_end:
        ret

change_delim:
    mov rdi, line_buffer
    dec rax
    xor rcx, rcx
    .loop_begin:
        cmp rcx, rax
        je .loop_end
        inc rcx
        cmp byte [rdi + rcx - 1], 0
        jne .loop_begin
        mov byte [rdi + rcx - 1], 32    ; space
        jmp .loop_begin
    .loop_end:
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
