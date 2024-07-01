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

    comm_folder db "/comm", 0
    stat_folder db "/stat", 0
    file_descriptor dd 0
    string_builder_buffer db 64 dup(0)
    line_buffer db 8192 dup(0)

    tmp_buffer db 8192 dup(0)

    json_pid db 123, 34, "pid", 34, ":", 0  ; {"pid":
    json_name db ",", 34, "name", 34, ":", 34, 0  ; ,"name":"
    json_children_begin db 34, ",", 34, "children", 34, ":", 91, 0  ; ","children":[
    json_children_end db 93, 125, ",", 0  ; ]},
    json_buffer db 1048576 dup(0)

    ; struct dirent64
    d_ino dq 0
    d_off dq 0
    d_reclen dw 0
    d_type db 0
    d_name db 256 dup(0)
    d_padding db 5 dup(0)   ; 275 + 5 = 280

    ; struct process_node
    _pid dq 0
    _ppid dq 0
    _name db 256 dup(0)

    process_nodes_size dq 0
    process_nodes db 2383872 dup(0)   ; 2328 * 1024
    ; .pid              8       bytes
    ; .ppid             8       bytes
    ; .name             256     bytes
    ; .children_size    8       bytes
    ; .children         2048    bytes   8 * 256

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

    call collect_node_info

    call push_back_node_info

    jmp read_loop

close_directory:
    ; sys_close
    mov rax, 3
    mov	rdi, [proc_file_descriptor]
    syscall

    call link_tree

    call create_json_tree

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

create_json_tree:
    mov byte [json_buffer], 91

    xor rcx, rcx
    mov r14, [process_nodes_size]
    .create_json_tree_loop_begin:
        cmp rcx, r14
        je .create_json_tree_loop_end

        mov rax, rcx
        call load_node_info_into_buffer ; & in rbx
        inc rcx

        mov rax, [_ppid]
        test rax, rax
        jnz .create_json_tree_loop_begin

        mov r15, rcx

        call add_node_to_json

        mov rcx, r15

        jmp .create_json_tree_loop_begin
    .create_json_tree_loop_end:

    ; trim last ,
    mov rdi, json_buffer
    call strlen
    dec rax
    mov byte [rdi + rax], 0

    mov	rdi, json_buffer
    call strlen
    mov byte [rdi + rax], 93

    ret

add_node_to_json:
    mov rdi, json_buffer
    call strlen
    add rdi, rax
    mov rsi, json_pid
    call strcpy

    mov rax, [rbx]  ; [_pid]
    call itoa   ; number in rax, buffer in rsi, uses rcx, rdx

    mov rdi, json_buffer
    call strlen
    add rdi, rax
    call strcpy

    mov rdi, json_buffer
    call strlen
    add rdi, rax
    mov rsi, json_name
    call strcpy

    mov rdi, json_buffer
    call strlen
    add rdi, rax
    mov rsi, rbx
    add rsi, 16 ; _name
    call strcpy

    mov rdi, json_buffer
    call strlen
    add rdi, rax
    mov rsi, json_children_begin
    call strcpy

    xor rdx, rdx
    .children_loop_begin:
        cmp rdx, [rbx + 272] ; i < children_size
        je .children_loop_end

        push rbx
        push rdx

        mov rbx, [rbx + 272 + 8 + rdx * 8]
        call add_node_to_json

        pop rdx
        pop rbx

        inc rdx
        jmp .children_loop_begin
    .children_loop_end:

    mov rax, [rbx + 272] ; children_size
    test rax, rax
    jz .skip_trimming

    ; trim last ,
    mov rdi, json_buffer
    call strlen
    dec rax
    mov byte [rdi + rax], 0

    .skip_trimming:

    mov rdi, json_buffer
    call strlen
    add rdi, rax
    mov rsi, json_children_end
    call strcpy

    ret

link_tree:
    xor rcx, rcx
    mov r14, [process_nodes_size]
    .link_tree_loop_begin:
        cmp rcx, r14
        je .link_tree_loop_end

        mov rax, rcx
        call load_node_info_into_buffer ; & in rbx

        mov rax, [_ppid]
        test rax, rax
        jz .link_tree_loop_inc

        mov rdi, process_nodes
        xor rdx, rdx
        .find_loop_begin:
            mov rax, [rdi + rdx]
            cmp rax, [_ppid]    ; if (parent.pid == ppid)
            je .find_loop_end
            add rdx, 2328
            jmp .find_loop_begin
        .find_loop_end:

        ; push_back child
        add rdi, rdx    ; & node[i]
        add rdi, 272    ; & node[i].children_size
        mov rax, [rdi]
        mov rdx, rax
        inc rdx
        mov [rdi], rdx  ; ++node[i].children_size
        imul rax, 8     ; j
        add rdi, 8      ; node[i].children
        mov [rdi + rax], rbx    ; node[i].children[j]

    .link_tree_loop_inc:
        inc rcx
        jmp .link_tree_loop_begin
    .link_tree_loop_end:
    ret

; idx in rax, returns &node in rbx
load_node_info_into_buffer:
    imul rax, 2328
    mov rdi, process_nodes
    add rdi, rax

    mov rbx, rdi

    mov rax, [rdi]
    mov [_pid], rax
    mov rax, [rdi + 8]
    mov [_ppid], rax
    add rdi, 16
    mov rsi, rdi
    mov rdi, _name
    call strcpy

    ret

push_back_node_info:
    mov rdi, process_nodes

    mov rax, [process_nodes_size]
    imul rax, 2328
    mov r15, rax
    add rdi, rax

    mov rax, [_pid]
    mov [rdi], rax
    mov rax, [_ppid]
    mov [rdi + 8], rax
    mov rsi, _name
    add rdi, 16
    call strcpy

    mov rax, [process_nodes_size]
    inc rax
    mov [process_nodes_size], rax

    ret

collect_node_info:
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
    mov rsi, comm_folder
    call strcpy
    ; string_builder_buffer = "/proc/{pid}/comm"

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
    mov rsi, _name
    mov rdx, 32
    syscall ; On success, the number of bytes read is returned.

    mov rdi, _name
    add rdi, rax
    dec rdi
    mov byte [rdi], 0   ; _name is now zero-terminated

    ; sys_close
    mov rax, 3
    mov	rdi, [file_descriptor]
    syscall

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
    mov rsi, 0
    mov	rdi, delim
    call strtok

    mov rdi, rax
    call atoi
    mov [_ppid], rax

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
